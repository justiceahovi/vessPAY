import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/transaction_model.dart';
import '../providers/pay_anyone_providers.dart';
import '../providers/recent_activity_provider.dart';

/// Screen displayed when a payout successfully reaches COMPLETED status.
class PaymentSuccessScreen extends ConsumerWidget {
  final TransactionModel transaction;

  const PaymentSuccessScreen({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Invalidate transaction list cache so the newly completed payment appears immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(userTransactionsProvider);
    });

    final tx = transaction;
    final recipient = tx.recipientName ?? 'Recipient';
    final totalUsd = tx.sourceAmount + tx.fee;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(payFlowProvider.notifier).reset();
          context.go(AppRoutes.home);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // Success Checkmark Badge
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.semanticUp.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppColors.semanticUp.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 42,
                        color: AppColors.semanticUp,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Title & Subtitle
                const Text(
                  'Payment Sent!',
                  key: Key('success_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Copernicus',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.4,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)} was successfully delivered to $recipient.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 28),

                // Dual Currency Hero Card
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Left: Recipient Got
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Recipient Got',
                                  style: TextStyle(
                                    fontFamily: 'StyreneB',
                                    fontSize: 12,
                                    color: AppColors.onDarkSoft,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}',
                                  key: const Key('success_recipient_amount'),
                                  style: const TextStyle(
                                    fontFamily: 'Copernicus',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onDark,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Vertical divider
                          Container(
                            height: 42,
                            width: 1,
                            color: Colors.white.withValues(alpha: 0.12),
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                          ),

                          // Right: You Paid
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'You Paid (USD)',
                                  style: TextStyle(
                                    fontFamily: 'StyreneB',
                                    fontSize: 12,
                                    color: AppColors.onDarkSoft,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${totalUsd.toStringAsFixed(2)}',
                                  key: const Key('success_you_pay_amount'),
                                  style: const TextStyle(
                                    fontFamily: 'Copernicus',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onDark,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Rate: 1 USD = ${tx.exchangeRate.toStringAsFixed(2)} GHS',
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 12,
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                            Text(
                              'Fee: \$${tx.fee.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 12,
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Transaction Meta Details Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.hairlineSubtle),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        label: 'Recipient',
                        value: tx.recipientName ?? 'Recipient',
                      ),
                      if (tx.recipientPhone != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Mobile Number',
                          value: tx.recipientPhone!,
                        ),
                      ],
                      if (tx.network != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Network',
                          value: tx.network!,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        label: 'Status',
                        value: 'COMPLETED',
                        valueColor: AppColors.semanticUp,
                        isBadge: true,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        label: 'Reference',
                        value: tx.vesspayReference ?? 'VP-PAY-${tx.id.substring(0, 8).toUpperCase()}',
                        valueKey: const Key('success_reference'),
                        canCopy: true,
                        context: context,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        label: 'Date & Time',
                        value: tx.formattedDate,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Primary CTA: Done -> Returns to Wallet / Home
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    key: const Key('success_done_button'),
                    onPressed: () {
                      ref.read(payFlowProvider.notifier).reset();
                      context.go(AppRoutes.home);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Secondary CTA: View Receipt / History
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    key: const Key('success_view_history_button'),
                    onPressed: () {
                      ref.read(payFlowProvider.notifier).reset();
                      context.push(AppRoutes.transactionDetail, extra: tx);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.hairlineSubtle, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Transaction Receipt',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    Key? valueKey,
    Color? valueColor,
    bool isBadge = false,
    bool canCopy = false,
    BuildContext? context,
  }) {
    Widget valueWidget = Text(
      value,
      key: valueKey,
      style: TextStyle(
        fontFamily: 'StyreneB',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: valueColor ?? AppColors.ink,
      ),
    );

    if (isBadge) {
      valueWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (valueColor ?? AppColors.semanticUp).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: valueWidget,
      );
    }

    if (canCopy && context != null) {
      valueWidget = InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reference copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            valueWidget,
            const SizedBox(width: 4),
            const Icon(Icons.copy_rounded, size: 14, color: AppColors.muted),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 13,
            color: AppColors.muted,
          ),
        ),
        valueWidget,
      ],
    );
  }
}
