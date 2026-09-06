/// Result of GET /api/beneficiaries/resolve -- who the destination account
/// belongs to, and how sure we are of it.
class RecipientResolutionModel {
  final bool resolved;

  /// True only when the operator or bank confirmed the account holder name.
  /// Names we merely remember locally are never verified.
  final bool verified;

  final String phone;
  final String? accountNumber;
  final String? network;
  final String? institutionCode;

  /// 'MOBILE_MONEY' or 'BANK'.
  final String? channel;
  final String? name;

  /// 'provider' when the operator or bank confirmed it, 'beneficiary' when it
  /// comes from a saved recipient, 'history' from a previous payout, null when
  /// nothing was found.
  final String? source;

  const RecipientResolutionModel({
    required this.resolved,
    required this.phone,
    this.verified = false,
    this.accountNumber,
    this.network,
    this.institutionCode,
    this.channel,
    this.name,
    this.source,
  });

  const RecipientResolutionModel.unresolved(this.phone)
      : resolved = false,
        verified = false,
        accountNumber = null,
        network = null,
        institutionCode = null,
        channel = null,
        name = null,
        source = null;

  factory RecipientResolutionModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final hasName = name != null && name.trim().isNotEmpty;

    return RecipientResolutionModel(
      resolved: json['resolved'] == true && hasName,
      verified: json['verified'] == true && hasName,
      phone: (json['phone'] ?? '').toString(),
      accountNumber: json['accountNumber'] as String?,
      network: json['network'] as String?,
      institutionCode: json['institutionCode'] as String?,
      channel: json['channel'] as String?,
      name: name?.trim(),
      source: json['source'] as String?,
    );
  }

  /// The institution to name in the UI, e.g. "MTN Mobile Money".
  String get institutionLabel =>
      (network != null && network!.isNotEmpty) ? network! : 'the provider';

  /// Short human explanation of where the name came from.
  String get sourceLabel {
    switch (source) {
      case 'provider':
        return 'Confirmed with $institutionLabel';
      case 'beneficiary':
        return 'From your saved recipients';
      case 'history':
        return 'From a previous payment';
      default:
        return 'Recipient name found';
    }
  }
}
