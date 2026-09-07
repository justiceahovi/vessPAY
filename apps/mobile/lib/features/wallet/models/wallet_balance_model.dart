import '../../../core/utils/currency_formatter.dart';

class WalletBalanceModel {
  final String currency;
  final double balance;

  const WalletBalanceModel({
    required this.currency,
    required this.balance,
  });

  factory WalletBalanceModel.fromJson(Map<String, dynamic> json) {
    return WalletBalanceModel(
      currency: json['currency'] as String? ?? 'USD',
      balance: (json['balance'] is num)
          ? (json['balance'] as num).toDouble()
          : double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
    );
  }

  String get formattedBalance => '\$${formatAmount(balance)}';
}
