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

/// Baseline activities used for initial state / tests
final kDefaultActivities = <ActivityItemModel>[
  const ActivityItemModel(
    id: 'default-1',
    title: 'Purchased airtime',
    subtitle: 'You have successfully purchased airtime of GHS 10.00',
    date: '02 Sep 2026, 1:07 PM',
    amount: 'GHS 10.00',
    statusText: 'SUCCESS',
    statusColor: AppColors.semanticUp,
    icon: Icons.phone_rounded,
    iconColor: AppColors.semanticUp,
    iconBgColor: AppColors.surfaceGreenTint,
  ),
  const ActivityItemModel(
    id: 'default-2',
    title: 'Load a Virtual Card',
    subtitle: 'Reason: Card load verified',
    date: '01 Sep 2026, 3:42 PM',
    amount: 'GHS 51.00',
    statusText: 'SUCCESS',
    statusColor: AppColors.semanticUp,
    icon: Icons.credit_card_rounded,
    iconColor: AppColors.primary,
    iconBgColor: AppColors.surfaceTint,
  ),
  const ActivityItemModel(
    id: 'default-3',
    title: 'Transfer to Kwame Mensah',
    subtitle: 'MTN Mobile Money payout completed',
    date: '30 Aug 2026, 10:22 AM',
    amount: 'GHS 150.00',
    statusText: 'SUCCESS',
    statusColor: AppColors.semanticUp,
    icon: Icons.swap_horiz_rounded,
    iconColor: AppColors.primary,
    iconBgColor: AppColors.surfaceTint,
  ),
];

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

  if (transactions.isEmpty) {
    return kDefaultActivities;
  }

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
  if (activities.isNotEmpty) {
    for (final act in activities.take(3)) {
      final notifTitle = act.title.toLowerCase().contains('airtime')
          ? 'Airtime Purchase Succeeded'
          : '${act.title} Succeeded';
      items.add(
        NotificationItemModel(
          id: 'notif-${act.id}',
          title: notifTitle,
          subtitle: act.subtitle,
          time: act.date.contains(',')
              ? act.date.split(',').last.trim()
              : '1:07 PM',
          icon: act.icon,
          iconColor: act.iconColor,
        ),
      );
    }
  } else {
    items.add(
      const NotificationItemModel(
        id: 'default-notif-1',
        title: 'Airtime Purchase Succeeded',
        subtitle: 'You successfully purchased airtime of GHS 10.00',
        time: '1:07 PM',
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.semanticUp,
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
