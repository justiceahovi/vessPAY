/// Payout corridors: the client-side mirror of the backend's lib/corridors.ts.
///
/// Everything that differs between the countries VessPay pays into lives here,
/// so a rail-specific rule is never spelled out inline in a screen. The server
/// remains the authority -- GET /api/travel/destinations carries `symbol`,
/// `channels` and `payoutAvailable` -- and this table is what the app falls
/// back to before that call returns, or when it fails.
class Corridor {
  final String country;
  final String name;
  final String currency;

  /// Symbol for user-facing amounts, e.g. 'GH₵'.
  final String symbol;

  /// International dialling prefix, e.g. '+233'.
  final String dialCode;

  /// Channels this corridor can be paid over: 'MOBILE_MONEY' and/or 'BANK'.
  final List<String> channels;

  /// Local bank account number length, in digits.
  final int accountMinDigits;
  final int accountMaxDigits;

  /// National mobile money number pattern, or null where the corridor has no
  /// mobile money channel.
  final RegExp? msisdnPattern;

  /// Whether a payout can actually be sent today. Nigeria's reference data all
  /// works -- banks, account lookup, beneficiary registration -- but the
  /// provider exposes no NGN payout rail, so the destination is offered as
  /// coming soon rather than letting a user reach a dead Send button.
  final bool payoutAvailable;

  const Corridor({
    required this.country,
    required this.name,
    required this.currency,
    required this.symbol,
    required this.dialCode,
    required this.channels,
    required this.accountMinDigits,
    required this.accountMaxDigits,
    required this.msisdnPattern,
    required this.payoutAvailable,
  });

  bool get hasMobileMoney => channels.contains('MOBILE_MONEY');
  bool get hasBank => channels.contains('BANK');

  /// True when the corridor offers exactly one way to be paid, in which case
  /// the payment-type selector is noise and is hidden.
  bool get isSingleChannel => channels.length == 1;

  String get flagEmoji {
    switch (country.toUpperCase()) {
      case 'GH':
        return '🇬🇭';
      case 'NG':
        return '🇳🇬';
      case 'KE':
        return '🇰🇪';
      default:
        return '🌍';
    }
  }

  /// Default institution code for a channel: the first thing a user is most
  /// likely to want, and always a code the payout rail actually recognises.
  ///
  /// Empty where the provider publishes no institution list for the corridor
  /// (Kenya) -- an invented code would be worse than none, because it would
  /// look selectable and be rejected on submission.
  String defaultNetworkFor(String channel) {
    switch (country) {
      case 'GH':
        return channel == 'MOBILE_MONEY' ? 'MTN' : 'GCB';
      case 'NG':
        return '100004'; // OPay; NGN has no mobile money channel
      default:
        return '';
    }
  }

  /// Human-readable account number rule, for validation messages.
  String get accountRuleText => accountMinDigits == accountMaxDigits
      ? '$accountMinDigits digits'
      : '$accountMinDigits-$accountMaxDigits digits';
}

/// Ghana's mobile money number pattern.
final RegExp kGhanaMsisdnPattern = RegExp(r'^0[235]\d{8}$');

final Corridor ghanaCorridor = Corridor(
  country: 'GH',
  name: 'Ghana',
  currency: 'GHS',
  symbol: 'GH₵',
  dialCode: '+233',
  channels: const ['MOBILE_MONEY', 'BANK'],
  // Ghana account numbers run 8-20 digits depending on the bank.
  accountMinDigits: 8,
  accountMaxDigits: 20,
  msisdnPattern: kGhanaMsisdnPattern,
  payoutAvailable: true,
);

final Corridor nigeriaCorridor = Corridor(
  country: 'NG',
  name: 'Nigeria',
  currency: 'NGN',
  symbol: '₦',
  dialCode: '+234',
  // No mobile money institutions exist for NGN: OPay, PalmPay, Moniepoint and
  // Kuda are all reached as banks, by 10-digit NUBAN.
  channels: const ['BANK'],
  accountMinDigits: 10,
  accountMaxDigits: 10,
  msisdnPattern: null,
  // The provider has no NGN payout rail yet -- see lib/corridors.ts.
  payoutAvailable: false,
);

/// Safaricom and Airtel MSISDNs: 07xxxxxxxx and 01xxxxxxxx.
final RegExp kKenyaMsisdnPattern = RegExp(r'^0[17]\d{8}$');

final Corridor kenyaCorridor = Corridor(
  country: 'KE',
  name: 'Kenya',
  currency: 'KES',
  symbol: 'KSh',
  dialCode: '+254',
  // Not from the provider: WeWire publishes no Kenyan institution list, so
  // this is the market shape (M-Pesa first, banks second) rather than
  // anything verified.
  channels: const ['MOBILE_MONEY', 'BANK'],
  accountMinDigits: 6,
  accountMaxDigits: 20,
  msisdnPattern: kKenyaMsisdnPattern,
  // Rates resolve (USD/KES direct, GBP and EUR through the USD cross) but
  // there is no institution list, no account lookup and no payout rail.
  payoutAvailable: false,
);

final List<Corridor> kCorridors = [
  ghanaCorridor,
  nigeriaCorridor,
  kenyaCorridor,
];

/// Resolves a country code, currency or country name to its corridor,
/// defaulting to Ghana the way the app did before a second corridor existed.
Corridor corridorFor(String? input) {
  if (input == null || input.trim().isEmpty) return ghanaCorridor;
  final key = input.trim().toUpperCase();
  for (final c in kCorridors) {
    if (c.country == key || c.currency == key || c.name.toUpperCase() == key) {
      return c;
    }
  }
  return ghanaCorridor;
}

/// Returns null rather than defaulting, for callers that need to know whether
/// a destination is served at all.
Corridor? findCorridor(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final key = input.trim().toUpperCase();
  for (final c in kCorridors) {
    if (c.country == key || c.currency == key || c.name.toUpperCase() == key) {
      return c;
    }
  }
  return null;
}

/// Formats an amount in a corridor's currency, e.g. 'GH₵150.00'.
String formatCorridorAmount(String currencyOrCountry, num amount) {
  final corridor = corridorFor(currencyOrCountry);
  return '${corridor.symbol}${amount.toStringAsFixed(2)}';
}
