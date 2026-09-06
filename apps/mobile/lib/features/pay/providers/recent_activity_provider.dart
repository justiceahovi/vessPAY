import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../travel/providers/travel_providers.dart';
import '../models/transaction_model.dart';
import '../repositories/payment_repository.dart';

/// Presentation model for an activity row
class ActivityItemModel {
  final String id;
  final String title;
  final String subtitle;
  final String date;
  final String amount;
  final String statusText;
  final Color statusColor;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;

  const ActivityItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.amount,
    required this.statusText,
    required this.statusColor,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
  });
}

/// Presentation model for a notification item
class NotificationItemModel {
  final String id;
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color iconColor;

  const NotificationItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
    required this.iconColor,
  });
}

/// Future provider fetching real transactions from backend
final userTransactionsProvider =
    FutureProvider<List<TransactionModel>>((ref) async {
  try {
    final repo = ref.watch(paymentRepositoryProvider);
    return await repo.getTransactions();
  } catch (_) {
    return <TransactionModel>[];
  }
});

/// Future provider fetching a single transaction's full detail by ID
final transactionDetailProvider =
    FutureProvider.family<TransactionModel, String>((ref, id) async {
  final repo = ref.watch(paymentRepositoryProvider);
  return await repo.getPaymentById(id);
});

/// Formats date for grouping headers (e.g. "Today", "Yesterday", "4 September 2026")
String formatGroupingDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final itemDate = DateTime(date.year, date.month, date.day);

  if (itemDate == today) {
    return 'Today';
  } else if (itemDate == yesterday) {
    return 'Yesterday';
  } else {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Groups transactions chronologically by date preserving order
Map<String, List<TransactionModel>> groupTransactionsByDate(
    List<TransactionModel> transactions) {
  final map = <String, List<TransactionModel>>{};
  for (final tx in transactions) {
    final key = formatGroupingDate(tx.createdAt);
    map.putIfAbsent(key, () => []).add(tx);
  }
  return map;
}

/// Dynamic provider mapping transactions into Activity items
final recentActivitiesProvider = Provider<List<ActivityItemModel>>((ref) {
  final txAsync = ref.watch(userTransactionsProvider);
  final transactions = txAsync.valueOrNull ?? [];

  return transactions.map((tx) {
    return ActivityItemModel(
      id: tx.id,
      title: tx.displayTitle,
      subtitle: tx.displaySubtitle,
      date: tx.formattedDate,
      amount: tx.displayAmount,
      statusText: tx.displayStatus,
      statusColor: tx.statusColor,
      icon: tx.displayIcon,
      iconColor: tx.statusColor,
      iconBgColor: tx.status == 'COMPLETED'
          ? AppColors.surfaceGreenTint
          : AppColors.surfaceTint,
    );
  }).toList();
});

/// Dynamic notifications provider driven by live corridor state & recent activities
final dynamicNotificationsProvider =
    Provider<List<NotificationItemModel>>((ref) {
  final items = <NotificationItemModel>[];

  // 1. Transaction-driven dynamic notifications from recent activities
  final activities = ref.watch(recentActivitiesProvider);
  for (final act in activities.take(3)) {
    final notifTitle = act.title.toLowerCase().contains('airtime')
        ? 'Airtime Purchase Succeeded'
        : '${act.title} Succeeded';
    items.add(
      NotificationItemModel(
        id: 'notif-${act.id}',
        title: notifTitle,
        subtitle: act.subtitle,
        time: act.date.contains(',') ? act.date.split(',').last.trim() : '',
        icon: act.icon,
        iconColor: act.iconColor,
      ),
    );
  }

  // 2. Dynamic Corridor notification
  final profile = ref.watch(currentTravelProfileProvider).valueOrNull;
  final countryName = profile?.destinationCountry == 'NG'
      ? 'Nigeria'
      : (profile?.destinationCountry == 'GH'
          ? 'Ghana'
          : (profile?.destinationCountry.isNotEmpty == true
              ? profile!.destinationCountry
              : 'Ghana'));

  final railsDescription = profile?.destinationCountry == 'NG'
      ? 'Nigeria Bank and MoMo payout rails are live.'
      : 'Ghana MoMo and Bank payout rails are live.';

  items.add(
    NotificationItemModel(
      id: 'notif-travel-corridor',
      title: 'Travel Corridor Active',
      subtitle: '$countryName: $railsDescription',
      time: 'Live',
      icon: Icons.flight_takeoff_rounded,
      iconColor: AppColors.primary,
    ),
  );

  return items;
});
