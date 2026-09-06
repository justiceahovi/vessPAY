/// Result of GET /api/beneficiaries/resolve -- the recipient name known for a
/// mobile money number, used to auto-fill the Pay Anyone recipient name field.
class RecipientResolutionModel {
  final bool resolved;
  final String phone;
  final String? network;
  final String? name;

  /// 'beneficiary' when the name comes from a saved recipient, 'history' when
  /// it comes from a previous payout, null when nothing was found.
  final String? source;

  const RecipientResolutionModel({
    required this.resolved,
    required this.phone,
    this.network,
    this.name,
    this.source,
  });

  const RecipientResolutionModel.unresolved(this.phone)
      : resolved = false,
        network = null,
        name = null,
        source = null;

  factory RecipientResolutionModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    return RecipientResolutionModel(
      resolved: json['resolved'] == true && name != null && name.trim().isNotEmpty,
      phone: (json['phone'] ?? '').toString(),
      network: json['network'] as String?,
      name: name?.trim(),
      source: json['source'] as String?,
    );
  }

  /// Short human explanation of where the name came from.
  String get sourceLabel {
    switch (source) {
      case 'beneficiary':
        return 'From your saved recipients';
      case 'history':
        return 'From a previous payment';
      default:
        return 'Recipient name found';
    }
  }
}
