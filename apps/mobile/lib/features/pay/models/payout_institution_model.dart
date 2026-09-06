/// A payout institution served by GET /api/banks: either a bank or a mobile
/// money operator, with the WeWire sort code used to address it.
class PayoutInstitutionModel {
  final String code;
  final String name;

  /// 'BANK' or 'MOBILE_MONEY'.
  final String channel;
  final String currency;

  const PayoutInstitutionModel({
    required this.code,
    required this.name,
    required this.channel,
    this.currency = 'GHS',
  });

  bool get isBank => channel == 'BANK';

  factory PayoutInstitutionModel.fromJson(Map<String, dynamic> json) {
    return PayoutInstitutionModel(
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      channel: (json['channel'] ?? 'BANK').toString().toUpperCase(),
      currency: (json['currency'] ?? 'GHS').toString().toUpperCase(),
    );
  }

  /// Title-cases the shouty names the institution list returns
  /// ("GCB BANK LIMITED" -> "GCB Bank Limited"), leaving short codes alone.
  String get displayName {
    if (name.isEmpty) return code;
    return name
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.length <= 3 && word.toUpperCase() == word) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}

/// The Ghana banks WeWire serves, bundled so the picker still works when the
/// institution endpoint is unreachable. Codes are WeWire sort codes.
const List<PayoutInstitutionModel> kFallbackGhanaBanks = [
  PayoutInstitutionModel(code: 'GCB', name: 'GCB BANK LIMITED', channel: 'BANK'),
  PayoutInstitutionModel(code: 'ECO', name: 'ECOBANK GHANA LTD', channel: 'BANK'),
  PayoutInstitutionModel(code: 'STA', name: 'STANBIC BANK', channel: 'BANK'),
  PayoutInstitutionModel(code: 'ACC', name: 'ACCESS BANK LTD', channel: 'BANK'),
  PayoutInstitutionModel(code: 'BBG', name: 'ABSA BANK (GH) LTD', channel: 'BANK'),
  PayoutInstitutionModel(code: 'CAL', name: 'CAL BANK LIMITED', channel: 'BANK'),
  PayoutInstitutionModel(code: 'FBL', name: 'FIDELITY BANK LIMITED', channel: 'BANK'),
  PayoutInstitutionModel(code: 'GTB', name: 'GUARANTY TRUST BANK', channel: 'BANK'),
  PayoutInstitutionModel(code: 'SCB', name: 'STANDARD CHARTERED BANK', channel: 'BANK'),
  PayoutInstitutionModel(code: 'UBA', name: 'UNITED BANK OF AFRICA', channel: 'BANK'),
  PayoutInstitutionModel(code: 'ZEN', name: 'ZENITH BANK GHANA LTD', channel: 'BANK'),
];
