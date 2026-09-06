/// A currency the user can hold and deposit into their VessPay wallet.
///
/// Mirrors the catalog served by GET /api/wallet/currencies.
class WalletCurrencyModel {
  final String code;
  final String name;
  final String symbol;
  final String flag;
  final String fundingRail;

  const WalletCurrencyModel({
    required this.code,
    required this.name,
    required this.symbol,
    required this.flag,
    required this.fundingRail,
  });

  /// e.g. "$1,240.00" — symbol placement matches the code's usual convention
  String format(double amount, {int decimals = 2}) =>
      '$symbol${amount.toStringAsFixed(decimals)}';

  /// e.g. "USD → GHS"
  String corridorTo(String destinationCurrency) => '$code → $destinationCurrency';

  factory WalletCurrencyModel.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String? ?? 'USD').toUpperCase();
    return WalletCurrencyModel(
      code: code,
      name: json['name'] as String? ?? code,
      symbol: json['symbol'] as String? ?? '',
      flag: json['flag'] as String? ?? '🌍',
      fundingRail: json['fundingRail'] as String? ?? 'Bank transfer',
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'symbol': symbol,
        'flag': flag,
        'fundingRail': fundingRail,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletCurrencyModel &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// Currency assumed before the user has chosen, and when the catalog is unreachable.
const String kDefaultWalletCurrency = 'USD';

/// Offline-safe mirror of the backend catalog, so the choice can always be shown.
const List<WalletCurrencyModel> kDefaultWalletCurrencies = [
  WalletCurrencyModel(
    code: 'USD',
    name: 'US Dollar',
    symbol: '\$',
    flag: '🇺🇸',
    fundingRail: 'ACH & Fedwire virtual account',
  ),
  WalletCurrencyModel(
    code: 'GBP',
    name: 'British Pound',
    symbol: '£',
    flag: '🇬🇧',
    fundingRail: 'Faster Payments virtual account',
  ),
  WalletCurrencyModel(
    code: 'EUR',
    name: 'Euro',
    symbol: '€',
    flag: '🇪🇺',
    fundingRail: 'SEPA virtual account',
  ),
];

/// Resolves a currency code against a catalog, falling back to a synthesised
/// entry so an unknown code still renders sensibly instead of crashing.
WalletCurrencyModel resolveWalletCurrency(
  String code, {
  List<WalletCurrencyModel> catalog = kDefaultWalletCurrencies,
}) {
  final normalized = code.trim().toUpperCase();
  for (final currency in catalog) {
    if (currency.code == normalized) return currency;
  }
  for (final currency in kDefaultWalletCurrencies) {
    if (currency.code == normalized) return currency;
  }
  return WalletCurrencyModel(
    code: normalized,
    name: normalized,
    symbol: '$normalized ',
    flag: '🌍',
    fundingRail: 'Bank transfer',
  );
}
