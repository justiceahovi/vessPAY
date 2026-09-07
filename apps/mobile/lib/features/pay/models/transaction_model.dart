import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Transaction Model representing an individual payment or funding activity
class TransactionModel {
  final String id;
  final String type; // 'payout' | 'deposit'
  final String status; // 'CREATED' | 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'FAILED'
  final String sourceCurrency;
  final double sourceAmount;
  final String destinationCurrency;
  final double destinationAmount;
  final double fee;

  /// WeWire's own disbursement fee, passed on to the user rather than
  /// absorbed by vessPay. Zero for deposits and for payouts predating this.
  final double wewireFee;
  final double exchangeRate;

  /// Deposits only: what the rails actually delivered, null while in flight.
  final double? settledAmount;
  final String? recipientName;
  final String? recipientPhone;
  final String? network;
  final String? country;
  final String? vesspayReference;
  final String? wewireReference;
  final String? errorMessage;
  final DateTime createdAt;

  const TransactionModel({
    required this.id,
    required this.type,
    required this.status,
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.destinationCurrency,
    required this.destinationAmount,
    required this.fee,
    this.wewireFee = 0.0,
    required this.exchangeRate,
    this.settledAmount,
    this.recipientName,
    this.recipientPhone,
    this.network,
    this.country,
    this.vesspayReference,
    this.wewireReference,
    this.errorMessage,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    // Parse recipient sub-object if present
    final recipientMap = json['recipient'] is Map<String, dynamic>
        ? json['recipient'] as Map<String, dynamic>
        : null;

    return TransactionModel(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'payout',
      status: json['status'] as String? ?? 'COMPLETED',
      sourceCurrency: json['sourceCurrency'] as String? ??
          json['source_currency'] as String? ??
          'USD',
      sourceAmount: (json['sourceAmount'] ?? json['source_amount'] as num?)
              ?.toDouble() ??
          0.0,
      destinationCurrency: json['destinationCurrency'] as String? ??
          json['destination_currency'] as String? ??
          'GHS',
      destinationAmount:
          (json['destinationAmount'] ?? json['destination_amount'] as num?)
                  ?.toDouble() ??
              0.0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0.0,
      wewireFee: (json['wewireFee'] ?? json['wewire_fee'] as num?)?.toDouble() ?? 0.0,
      exchangeRate:
          (json['exchangeRate'] ?? json['exchange_rate'] ?? json['rate'] as num?)?.toDouble() ??
              1.0,
      settledAmount:
          (json['settledAmount'] ?? json['settled_amount'] as num?)?.toDouble(),
      recipientName: recipientMap?['name'] as String? ??
          json['recipientName'] as String? ??
          json['recipient_name'] as String?,
      recipientPhone: recipientMap?['phone'] as String? ??
          json['recipientPhone'] as String? ??
          json['recipient_phone'] as String?,
      network: recipientMap?['network'] as String? ?? json['network'] as String?,
      country: recipientMap?['country'] as String? ?? json['country'] as String?,
      vesspayReference: json['vesspayReference'] as String? ??
          json['reference'] as String?,
      wewireReference: json['wewireReference'] as String? ??
          json['wewireTransactionId'] as String? ??
          json['wewire_transaction_id'] as String?,
      errorMessage: json['errorMessage'] as String? ??
          json['error_message'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'] as String) ??
                  DateTime.now()
              : DateTime.now()),
    );
  }

  /// Formats date for modern UI display
  String get formattedDate {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final day = createdAt.day.toString().padLeft(2, '0');
    final month = months[createdAt.month - 1];
    final year = createdAt.year;
    final hour = createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour);
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final ampm = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $ampm';
  }

  /// Formats relative time (e.g. "1:07 PM" or "Yesterday")
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inDays == 0) {
      final hour = createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour);
      final minute = createdAt.minute.toString().padLeft(2, '0');
      final ampm = createdAt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${createdAt.day} ${months[createdAt.month - 1]}';
    }
  }

  /// Money coming into the wallet rather than leaving it. 'topup' is the older
  /// name for the same thing and is still accepted from the backend.
  bool get isDeposit => type == 'deposit' || type == 'topup';

  /// What the wallet was actually credited, falling back to what the user sent
  /// while the deposit is still in flight.
  double get creditedAmount => settledAmount ?? destinationAmount;

  /// Presentation title
  String get displayTitle {
    if (isDeposit) {
      switch (status.toUpperCase()) {
        case 'FAILED':
          return 'Deposit failed';
        case 'COMPLETED':
          return 'Money added';
        default:
          return 'Deposit in progress';
      }
    }
    if (recipientName != null && recipientName!.isNotEmpty) {
      return 'Transfer to $recipientName';
    }
    if (network != null) {
      return '$network Payment';
    }
    return 'Purchased airtime';
  }

  /// Presentation subtitle
  String get displaySubtitle {
    if (isDeposit) {
      switch (status.toUpperCase()) {
        case 'FAILED':
          return 'Deposit of $sourceCurrency ${sourceAmount.toStringAsFixed(2)} did not go through';
        case 'COMPLETED':
          return 'Credited to your $destinationCurrency wallet';
        default:
          return 'Awaiting your $sourceCurrency transfer';
      }
    }
    if (recipientPhone != null && recipientPhone!.isNotEmpty) {
      return '${network ?? "MoMo"} payout to $recipientPhone';
    }
    return 'You have successfully purchased airtime of $destinationCurrency ${destinationAmount.toStringAsFixed(2)}';
  }

  /// Presentation amount
  String get displayAmount {
    return '$destinationCurrency ${destinationAmount.toStringAsFixed(2)}';
  }

  /// Presentation amount signed by direction: a deposit adds to the wallet,
  /// a payout takes from it.
  String get signedDisplayAmount {
    return '${isDeposit ? '+' : '-'} $displayAmount';
  }

  /// Status badge color
  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
      case 'SUCCESS':
        return AppColors.semanticUp;
      case 'PENDING':
      case 'PROCESSING':
        return Colors.orange;
      case 'FAILED':
        return AppColors.error;
      default:
        return AppColors.semanticUp;
    }
  }

  /// Status badge text
  String get displayStatus {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return 'SUCCESS';
      default:
        return status.toUpperCase();
    }
  }

  /// Icon
  IconData get displayIcon {
    if (isDeposit) {
      return Icons.arrow_downward_rounded;
    }
    if (recipientName != null) {
      return Icons.swap_horiz_rounded;
    }
    return Icons.phone_rounded;
  }
}
