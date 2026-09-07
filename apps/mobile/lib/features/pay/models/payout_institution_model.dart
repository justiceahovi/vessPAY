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

/// Nigerian institutions users reach for most, out of the 422 the endpoint
/// serves. Bundled only as a fallback for when the institution endpoint is
/// unreachable -- the live list is always preferred. Codes are NIP codes.
///
/// The first five are the wallets Nigerians think of as mobile money. They
/// settle as bank accounts by 10-digit NUBAN, because NGN has no mobile money
/// channel at all, so the picker pins them at the top rather than burying them
/// alphabetically among the banks.
const List<PayoutInstitutionModel> kNigeriaWalletCodes = [
  PayoutInstitutionModel(code: '100004', name: 'OPAY', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '100033', name: 'PALMPAY', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '090405', name: 'MONIEPOINT Microfinance Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '090267', name: 'KUDA Microfinance Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '100002', name: 'PAGA', channel: 'BANK', currency: 'NGN'),
];

const List<PayoutInstitutionModel> kFallbackNigeriaBanks = [
  ...kNigeriaWalletCodes,
  PayoutInstitutionModel(code: '000014', name: 'ACCESS Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000013', name: 'GTBANK PLC', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000015', name: 'ZENITH Bank PLC', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000016', name: 'FIRST Bank OF NIGERIA', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000004', name: 'UNITED Bank FOR AFRICA', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000012', name: 'STANBICIBTC Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000007', name: 'FIDELITY Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000017', name: 'WEMA Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000018', name: 'UNION Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000003', name: 'FCMB', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000001', name: 'STERLING Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000010', name: 'ECOBANK Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000023', name: 'PROVIDUS Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000002', name: 'KEYSTONE Bank', channel: 'BANK', currency: 'NGN'),
  PayoutInstitutionModel(code: '000008', name: 'POLARIS Bank', channel: 'BANK', currency: 'NGN'),
];

/// The bundled bank list for a payout currency.
List<PayoutInstitutionModel> fallbackBanksFor(String currency) {
  return currency.trim().toUpperCase() == 'NGN'
      ? kFallbackNigeriaBanks
      : kFallbackGhanaBanks;
}

/// Whether an institution is one of the Nigerian wallets that get pinned above
/// the alphabetical bank list.
bool isPinnedWallet(PayoutInstitutionModel institution) {
  return kNigeriaWalletCodes.any((w) => w.code == institution.code);
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
