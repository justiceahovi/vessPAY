import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/transaction_model.dart';
import '../providers/pay_anyone_providers.dart';

/// Screen displayed when a payout reaches FAILED status.
/// Reassures the user that their money wasn't lost and offers a clean retry action.
class PaymentFailureScreen extends ConsumerWidget {
  final TransactionModel? transaction;
  final String? failureReason;

  const PaymentFailureScreen({
    super.key,
    this.transaction,
    this.failureReason,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = transaction;
    final reason = failureReason ??
        tx?.errorMessage ??
        'The mobile network operator was unable to complete the payout. Please try again.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
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
                const SizedBox(height: 28),

                // Failure Alert Icon
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.error.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.35),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Main Title
                const Text(
                  'Payment Could Not Be Completed',
                  key: Key('failure_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Copernicus',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  reason,
                  key: const Key('failure_reason_text'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 28),

                // ============================================================
                // MANDATORY UX REQUIREMENT: Reassurance that money wasn't lost
                // ============================================================
                Container(
                  key: const Key('failure_reassurance_card'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.semanticUp.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.semanticUp.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.semanticUp.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 20,
                          color: AppColors.semanticUp,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Your money is safe',
                              key: Key('failure_reassurance_heading'),
                              style: TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'No funds were deducted from your wallet. If any funds were temporarily held, they have been completely restored to your balance.',
                              key: Key('failure_reassurance_body'),
                              style: TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 12,
                                color: AppColors.ink,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (tx != null) ...[
                  const SizedBox(height: 24),

                  // Attempted Payment Details Card
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
                          value: tx.recipientName ?? tx.recipientPhone ?? 'Mobile Money',
                        ),
                        if (tx.recipientPhone != null) ...[
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            label: 'Phone Number',
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
                          label: 'Attempted Amount',
                          value:
                              '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          label: 'Status',
                          value: 'FAILED',
                          valueColor: AppColors.error,
                          isBadge: true,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // Primary CTA: Try Again
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    key: const Key('failure_retry_button'),
                    onPressed: () {
                      // Return to review screen or previous step to retry
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        context.go(AppRoutes.paymentReview);
                      }
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
                      'Try Again',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Secondary CTA: Back to Wallet
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const Key('failure_wallet_button'),
                    onPressed: () {
                      ref.read(payFlowProvider.notifier).reset();
                      context.go(AppRoutes.home);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.hairlineSubtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to Wallet',
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
    Color? valueColor,
    bool isBadge = false,
  }) {
    Widget valueWidget = Text(
      value,
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
          color: (valueColor ?? AppColors.error).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: valueWidget,
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
