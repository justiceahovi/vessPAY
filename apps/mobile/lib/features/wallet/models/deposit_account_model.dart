/// Where the user is in deposit-account setup.
///
/// A deposit account is issued by WeWire, not created locally, and it needs two
/// things only the user can supply: Enhanced Due Diligence, and a declared
/// source of funds. Both are asked for at the first deposit attempt.
enum DepositAccountState {
  /// The account exists and can receive money.
  ready,

  /// Requested, but WeWire is still provisioning it. Poll until ready.
  provisioning,

  /// Enhanced verification is outstanding.
  kycRequired,

  /// The user still has to declare where their money comes from.
  sourceOfFundsRequired,

  /// Cannot be issued at all — usually a jurisdiction rule.
  unavailable,
}

class SourceOfFundsOption {
  final String value;
  final String label;

  const SourceOfFundsOption({required this.value, required this.label});

  factory SourceOfFundsOption.fromJson(Map<String, dynamic> json) {
    return SourceOfFundsOption(
      value: json['value'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class DepositAccountModel {
  final DepositAccountState state;
  final String currency;
  final String? accountId;
  final String? accountStatus;
  final Map<String, dynamic>? accountDetails;
  final String? sourceOfFunds;
  final String? kycLinkUrl;
  final String? reason;
  final List<SourceOfFundsOption> sourceOfFundsOptions;

  const DepositAccountModel({
    required this.state,
    required this.currency,
    this.accountId,
    this.accountStatus,
    this.accountDetails,
    this.sourceOfFunds,
    this.kycLinkUrl,
    this.reason,
    this.sourceOfFundsOptions = const [],
  });

  bool get isReady => state == DepositAccountState.ready;

  static DepositAccountState _parseState(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'READY':
        return DepositAccountState.ready;
      case 'PROVISIONING':
        return DepositAccountState.provisioning;
      case 'KYC_REQUIRED':
        return DepositAccountState.kycRequired;
      case 'SOURCE_OF_FUNDS_REQUIRED':
        return DepositAccountState.sourceOfFundsRequired;
      default:
        return DepositAccountState.unavailable;
    }
  }

  factory DepositAccountModel.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['sourceOfFundsOptions'];
    return DepositAccountModel(
      state: _parseState(json['state'] as String?),
      currency: (json['currency'] as String? ?? 'USD').toUpperCase(),
      accountId: json['accountId'] as String?,
      accountStatus: json['accountStatus'] as String?,
      accountDetails: json['accountDetails'] as Map<String, dynamic>?,
      sourceOfFunds: json['sourceOfFunds'] as String?,
      kycLinkUrl: json['kycLinkUrl'] as String?,
      reason: json['reason'] as String?,
      sourceOfFundsOptions: rawOptions is List
          ? rawOptions
              .map((o) =>
                  SourceOfFundsOption.fromJson(o as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }
}
