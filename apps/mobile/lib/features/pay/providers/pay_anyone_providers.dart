import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/corridors.dart';
import '../models/pay_flow_model.dart';
import '../models/payment_estimate.dart';
import '../models/payment_quote_model.dart';
import '../models/payout_institution_model.dart';
import '../models/recipient_resolution_model.dart';
import '../repositories/payment_repository.dart';
import '../../wallet/providers/wallet_providers.dart';

class PayFlowNotifier extends StateNotifier<PayFlowData> {
  PayFlowNotifier(double initialRate)
      : super(PayFlowData(exchangeRate: initialRate));

  void setCountry({
    required String code,
    required String name,
    required String flag,
    required String currency,
  }) {
    final corridor = corridorFor(code);

    // A corridor the recipient cannot be paid over must not keep a stale
    // payment type from the previous destination: Nigeria has no mobile money,
    // so a flow arriving from Ghana would otherwise land on a MoMo form that
    // can never be completed.
    final paymentType = corridor.channels.contains(
            state.paymentType == PaymentType.mobileMoney ? 'MOBILE_MONEY' : 'BANK')
        ? state.paymentType
        : (corridor.hasMobileMoney
            ? PaymentType.mobileMoney
            : PaymentType.bankTransfer);

    final channel =
        paymentType == PaymentType.mobileMoney ? 'MOBILE_MONEY' : 'BANK';

    state = state.copyWith(
      countryCode: code,
      countryName: name,
      countryFlag: flag,
      destinationCurrency: currency,
      paymentType: paymentType,
      // The old destination's institution code means nothing on the new rail.
      network: corridor.defaultNetworkFor(channel),
      recipientPhone: '',
      accountNumber: '',
      recipientName: '',
      recipientNameVerified: false,
    );
  }

  void setPaymentType(PaymentType type) {
    // Default to the corridor's first institution for the channel: MTN and GCB
    // in Ghana, OPay in Nigeria. Always an institution code the rail knows.
    final corridor = corridorFor(state.destinationCurrency);
    final defaultNetwork = corridor.defaultNetworkFor(
      type == PaymentType.mobileMoney ? 'MOBILE_MONEY' : 'BANK',
    );
    state = state.copyWith(
      paymentType: type,
      network: defaultNetwork,
    );
  }

  void setNetwork(String network) {
    state = state.copyWith(network: network);
  }

  void setRecipientDetails({
    required String phone,
    String name = '',
    String accountNumber = '',
    bool nameVerified = false,
  }) {
    state = state.copyWith(
      recipientPhone: phone.trim(),
      recipientName: name.trim(),
      recipientNameVerified: nameVerified,
      accountNumber: accountNumber.trim(),
    );
  }

  void setAmount(double amount) {
    if (amount <= 0) {
      state = state.copyWith(
        destinationAmount: 0.0,
        quoteSourceAmount: null,
        quoteFee: null,
        quoteTotal: null,
      );
      return;
    }

    // Local estimate only -- the server recalculates before any payment
    final estimate = PaymentEstimate.local(
      destinationAmount: amount,
      exchangeRate: state.exchangeRate,
      destinationCurrency: state.destinationCurrency,
    );

    state = state.copyWith(
      destinationAmount: estimate.destinationAmount,
      quoteSourceAmount: estimate.sourceAmount,
      quoteFee: estimate.fee,
      quoteTotal: estimate.total,
    );
  }

  void syncWithBackendQuote({
    required double sourceAmount,
    required double fee,
    required double total,
    required double exchangeRate,
  }) {
    state = state.copyWith(
      quoteSourceAmount: sourceAmount,
      quoteFee: fee,
      quoteTotal: total,
      exchangeRate: exchangeRate,
    );
  }

  void updateExchangeRate(double rate) {
    if (rate <= 0) return;
    state = state.copyWith(exchangeRate: rate);
    if (state.destinationAmount > 0) {
      setAmount(state.destinationAmount);
    }
  }

  void reset() {
    state = const PayFlowData();
  }
}

final payFlowProvider =
    StateNotifierProvider<PayFlowNotifier, PayFlowData>((ref) {
  // Live rate from the held wallet currency into the active destination's
  final rate = ref.watch(walletToDestinationRateProvider);
  return PayFlowNotifier(rate);
});

/// The exact input a server quote is requested for. Value equality keeps one
/// request per distinct set of payment details.
class PaymentQuoteRequest {
  final String country;
  final String network;
  final String recipient;
  final double destinationAmount;
  final String destinationCurrency;

  const PaymentQuoteRequest({
    required this.country,
    required this.network,
    required this.recipient,
    required this.destinationAmount,
    required this.destinationCurrency,
  });

  factory PaymentQuoteRequest.fromPayData(PayFlowData payData) {
    final recipient = payData.paymentType == PaymentType.mobileMoney
        ? payData.recipientPhone
        : payData.accountNumber;

    return PaymentQuoteRequest(
      country: payData.countryCode,
      network: payData.network,
      recipient: recipient.trim(),
      destinationAmount: payData.destinationAmount,
      destinationCurrency: payData.destinationCurrency,
    );
  }

  /// Whether there is enough real input to ask the server for a quote. Nothing
  /// is ever quoted against placeholder details.
  bool get isComplete =>
      recipient.isNotEmpty && network.isNotEmpty && destinationAmount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentQuoteRequest &&
          other.country == country &&
          other.network == network &&
          other.recipient == recipient &&
          other.destinationAmount == destinationAmount &&
          other.destinationCurrency == destinationCurrency;

  @override
  int get hashCode => Object.hash(
        country,
        network,
        recipient,
        destinationAmount,
        destinationCurrency,
      );
}

/// Live backend quote provider that calls POST /api/payments/quote per T4.4
final paymentQuoteProvider = FutureProvider.autoDispose
    .family<PaymentQuoteModel, PaymentQuoteRequest>((ref, request) async {
  final repository = ref.watch(paymentRepositoryProvider);

  return repository.getQuote(
    country: request.country,
    network: request.network,
    phone: request.recipient,
    destinationAmount: request.destinationAmount,
    destinationCurrency: request.destinationCurrency,
  );
});

/// Payout banks for the destination currency, from GET /api/banks. Falls back
/// to the bundled list so the picker is never empty offline.
final payoutBanksProvider =
    FutureProvider.family<List<PayoutInstitutionModel>, String>(
        (ref, currency) async {
  final repository = ref.watch(paymentRepositoryProvider);
  try {
    final banks = await repository.getInstitutions(
      currency: currency,
      channel: 'BANK',
    );
    if (banks.isNotEmpty) return banks;
  } catch (_) {
    // fall through to the bundled list
  }
  return fallbackBanksFor(currency);
});

/// Normalizes a bank account number against the corridor's own rule: Ghana runs
/// 8-20 digits depending on the bank, Nigeria's NUBAN is exactly 10. Defaults
/// to the Ghana rule so existing callers are unchanged.
String? normalizeBankAccountNumber(String input, [String currency = 'GHS']) {
  final corridor = corridorFor(currency);
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length < corridor.accountMinDigits ||
      digits.length > corridor.accountMaxDigits) {
    return null;
  }
  return digits;
}

/// Normalizes a user-typed local mobile number to its national MSISDN for a
/// corridor. Returns null while the number is too short, is not a valid mobile
/// money number, or the corridor has no mobile money channel at all -- each of
/// which is a signal not to attempt a name lookup yet.
String? normalizeMsisdn(String input, [String currency = 'GHS']) {
  final corridor = corridorFor(currency);
  final pattern = corridor.msisdnPattern;
  if (pattern == null) return null;

  final trunk = corridor.dialCode.replaceAll('+', '');
  final digits = input.replaceAll(RegExp(r'\D'), '');
  var msisdn = digits;
  if (digits.startsWith(trunk) && digits.length == trunk.length + 9) {
    msisdn = '0${digits.substring(trunk.length)}';
  } else if (digits.length == 9) {
    msisdn = '0$digits';
  }
  if (!pattern.hasMatch(msisdn)) return null;
  return msisdn;
}

/// Ghana-specific spelling of [normalizeMsisdn], kept for existing callers.
String? normalizeGhanaMsisdn(String input) => normalizeMsisdn(input, 'GHS');

/// Ghana mobile money networks supported by the payout rail.
const List<String> kGhanaMoMoNetworks = ['MTN', 'Telecel', 'AirtelTigo'];

/// Ghana number prefixes per operator. Worth re-checking against the NCA
/// allocation list when a new range is issued.
const Map<String, List<String>> kGhanaNetworkPrefixes = {
  'MTN': ['024', '025', '053', '054', '055', '059'],
  'Telecel': ['020', '050'],
  'AirtelTigo': ['026', '027', '056', '057'],
};

/// Infers the mobile money network from a Ghana number, or null when the
/// number is incomplete or its prefix is not allocated to a known operator.
/// The user can always override the inferred value.
/// Infers the mobile money operator from a local number, for corridors that
/// have one. Nigeria has no mobile money channel, so there is nothing to infer
/// and this returns null there.
String? inferNetworkFromPhone(String phoneInput, [String currency = 'GHS']) {
  if (!corridorFor(currency).hasMobileMoney) return null;
  return inferGhanaNetwork(phoneInput);
}

String? inferGhanaNetwork(String phoneInput) {
  final msisdn = normalizeGhanaMsisdn(phoneInput);
  if (msisdn == null) return null;

  final prefix = msisdn.substring(0, 3);
  for (final entry in kGhanaNetworkPrefixes.entries) {
    if (entry.value.contains(prefix)) return entry.key;
  }
  return null;
}

/// Lookup key for [recipientNameProvider]. Value equality keeps one request
/// per (number, network) pair instead of one per keystroke.
class RecipientLookup {
  final String phone;
  final String accountNumber;
  final String network;
  final String channel;

  /// Payout currency, which decides how the account is validated.
  final String currency;

  const RecipientLookup({
    this.phone = '',
    this.accountNumber = '',
    required this.network,
    this.channel = 'MOBILE_MONEY',
    this.currency = 'GHS',
  });

  bool get isBank => channel == 'BANK';

  /// The destination account in the form the backend expects, or null while the
  /// user has not typed enough for a lookup to make sense.
  String? get destinationAccount => isBank
      ? normalizeBankAccountNumber(accountNumber, currency)
      : normalizeMsisdn(phone, currency);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipientLookup &&
          other.phone == phone &&
          other.accountNumber == accountNumber &&
          other.network == network &&
          other.channel == channel &&
          other.currency == currency;

  @override
  int get hashCode =>
      Object.hash(phone, accountNumber, network, channel, currency);
}

/// Debounced recipient name confirmation for the Pay Anyone flow. The backend
/// asks the operator or bank who owns the account, falling back to names we
/// already know. Returns null while there is not enough to look up.
final recipientNameProvider = FutureProvider.autoDispose
    .family<RecipientResolutionModel?, RecipientLookup>((ref, lookup) async {
  final destination = lookup.destinationAccount;
  if (destination == null || lookup.network.isEmpty) return null;

  // Debounce: a further keystroke changes the key and disposes this instance
  // before the delay elapses, so only the account the user settled on is sent.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (cancelled) return null;

  final repository = ref.read(paymentRepositoryProvider);
  return repository.resolveRecipientName(
    phone: lookup.isBank ? null : destination,
    accountNumber: lookup.isBank ? destination : null,
    network: lookup.network,
  );
});
