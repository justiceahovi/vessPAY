import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/transaction_model.dart';
import '../providers/recent_activity_provider.dart';

/// Screen listing all user transactions grouped chronologically by date.
/// Wired to GET /api/payments per T5.5 and VESSPAY_BLUEPRINT.md Section 7.
class TransactionListScreen extends ConsumerWidget {
  final List<TransactionModel>? transactionsOverride;

  const TransactionListScreen({
    super.key,
    this.transactionsOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget content;
    if (transactionsOverride != null) {
      content = _buildContent(context, ref, transactionsOverride!);
    } else {
      final txAsync = ref.watch(userTransactionsProvider);
      content = txAsync.when(
        data: (transactions) => _buildContent(context, ref, transactions),
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Failed to load transactions',
                  style: TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  key: const Key('transactions_retry_button'),
                  onPressed: () => ref.invalidate(userTransactionsProvider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(context, ref),
      body: content,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: AppColors.canvas,
      elevation: 0,
      leading: IconButton(
        key: const Key('transactions_back_button'),
        icon: const Icon(Icons.arrow_back, color: AppColors.ink),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
      title: const Text(
        'Transactions',
        key: Key('transactions_screen_title'),
        style: TextStyle(
          fontFamily: 'StyreneB',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          key: const Key('transactions_refresh_button'),
          icon: const Icon(Icons.refresh, color: AppColors.ink),
          onPressed: () => ref.invalidate(userTransactionsProvider),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<TransactionModel> transactions,
  ) {
    return RefreshIndicator(
      key: const Key('transactions_pull_to_refresh'),
      color: AppColors.primary,
      backgroundColor: AppColors.canvas,
      onRefresh: () async {
        ref.invalidate(userTransactionsProvider);
        await ref.read(userTransactionsProvider.future);
      },
      child: transactions.isEmpty
          ? _buildEmptyState(context)
          : _buildGroupedList(context, transactions),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceSubtle,
              border: Border.all(color: AppColors.hairlineSubtle),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 34,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'No transactions yet',
            key: Key('transactions_empty_text'),
            style: TextStyle(
              fontFamily: 'Copernicus',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'When you send money with Pay Anyone or top up your wallet, your payments will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 13,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => context.push(AppRoutes.payAnyone),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Pay Anyone'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedList(
    BuildContext context,
    List<TransactionModel> transactions,
  ) {
    final grouped = groupTransactionsByDate(transactions);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final dateHeader = grouped.keys.elementAt(index);
        final txList = grouped[dateHeader]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Text(
                dateHeader,
                key: Key('date_group_${dateHeader.toLowerCase().replaceAll(' ', '_')}'),
                style: const TextStyle(
                  fontFamily: 'StyreneB',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairlineSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    for (int i = 0; i < txList.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.hairlineSoft),
                      _buildTransactionRow(context, txList[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransactionRow(BuildContext context, TransactionModel tx) {
    final isPayout = tx.type == 'payout';
    final sign = isPayout ? '-' : '+';
    final amountText = '$sign ${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}';
    final usdTotal = tx.sourceAmount + tx.fee;
    final usdSubtext = isPayout ? '\$${usdTotal.toStringAsFixed(2)} USD' : '';

    return InkWell(
      key: Key('transaction_item_${tx.id}'),
      onTap: () {
        context.push(
          AppRoutes.transactionDetail,
          extra: tx,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Category / Type Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tx.status == 'COMPLETED'
                    ? AppColors.surfaceGreenTint
                    : AppColors.surfaceTint,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  tx.displayIcon,
                  color: tx.status == 'COMPLETED'
                      ? AppColors.semanticUp
                      : AppColors.primary,
                  size: 20,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.displayTitle,
                    style: const TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Status chip
                      _buildStatusChip(tx.status),
                      const SizedBox(width: 6),
                      Text(
                        tx.relativeTime,
                        style: const TextStyle(
                          fontFamily: 'StyreneB',
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Amounts Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountText,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (usdSubtext.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    usdSubtext,
                    style: const TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.mutedSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color text;
    String label;

    switch (status.toUpperCase()) {
      case 'COMPLETED':
      case 'SUCCESS':
        bg = AppColors.semanticUp.withValues(alpha: 0.12);
        text = AppColors.semanticUp;
        label = 'Completed';
        break;
      case 'PENDING':
      case 'PROCESSING':
        bg = AppColors.accentYellow.withValues(alpha: 0.15);
        text = const Color(0xFFB8860B);
        label = status.toUpperCase();
        break;
      case 'FAILED':
        bg = AppColors.error.withValues(alpha: 0.12);
        text = AppColors.error;
        label = 'Failed';
        break;
      default:
        bg = AppColors.surfaceSubtle;
        text = AppColors.muted;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'StyreneB',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}
