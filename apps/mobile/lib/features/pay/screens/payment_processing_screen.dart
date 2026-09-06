import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/transaction_model.dart';
import '../providers/payment_processing_provider.dart';

/// Screen displayed while a payout is in-flight.
/// Shows real progress by polling GET /api/payments/:id, strictly never showing
/// "Success" before the backend confirms COMPLETED status.
class PaymentProcessingScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final TransactionModel? initialTransaction;

  const PaymentProcessingScreen({
    super.key,
    required this.transactionId,
    this.initialTransaction,
  });

  @override
  ConsumerState<PaymentProcessingScreen> createState() =>
      _PaymentProcessingScreenState();
}

class _PaymentProcessingScreenState
    extends ConsumerState<PaymentProcessingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for terminal state transitions and route accordingly
    ref.listen<PaymentProcessingState>(
      paymentProcessingProvider(widget.transactionId),
      (previous, next) {
        if (!mounted) return;
        if (next.isCompleted && next.transaction != null) {
          context.go(
            AppRoutes.paymentSuccess,
            extra: next.transaction,
          );
        } else if (next.isFailed) {
          context.go(
            AppRoutes.paymentFailure,
            extra: next.transaction,
          );
        }
      },
    );

    final processingState =
        ref.watch(paymentProcessingProvider(widget.transactionId));
    final tx = processingState.transaction ?? widget.initialTransaction;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),

                // Pulsing Center Icon / Animation
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Main Title
                const Text(
                  'Processing Payment',
                  key: Key('processing_title'),
                  style: TextStyle(
                    fontFamily: 'Copernicus',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 8),

                // Dynamic Status Step Subtitle
                Text(
                  processingState.stepLabel,
                  key: const Key('processing_step_label'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 28),

                // Transaction In-Flight Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.hairlineSubtle),
                  ),
                  child: Column(
                    children: [
                      // Amount row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recipient Gets',
                            style: TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                          Text(
                            tx != null
                                ? '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}'
                                : 'Calculating...',
                            key: const Key('processing_dest_amount'),
                            style: const TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.hairlineSubtle),
                      const SizedBox(height: 12),

                      // Recipient row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recipient',
                            style: TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                          Text(
                            tx?.recipientName ?? tx?.recipientPhone ?? 'Mobile Money',
                            key: const Key('processing_recipient'),
                            style: const TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                      if (tx?.network != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Network',
                              style: TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                            Text(
                              tx!.network!,
                              key: const Key('processing_network'),
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // 3-Stage Progress Timeline
                _buildTimelineStep(
                  stepNumber: 1,
                  title: 'Order Created',
                  subtitle: 'Payment instruction accepted',
                  isCompleted: true,
                  isActive: false,
                ),
                _buildTimelineDivider(isCompleted: processingState.currentStep >= 2),
                _buildTimelineStep(
                  stepNumber: 2,
                  title: 'Dispatched to Network',
                  subtitle: 'Payout routing via partner rails',
                  isCompleted: processingState.currentStep >= 3,
                  isActive: processingState.currentStep == 2,
                ),
                _buildTimelineDivider(isCompleted: processingState.currentStep >= 3),
                _buildTimelineStep(
                  stepNumber: 3,
                  title: 'Settlement Confirmation',
                  subtitle: 'Confirming mobile wallet receipt',
                  isCompleted: processingState.isCompleted,
                  isActive: processingState.currentStep == 3 && !processingState.isCompleted,
                ),

                const SizedBox(height: 28),

                // Safety advice
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Do not close or leave this screen',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineStep({
    required int stepNumber,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
  }) {
    Color indicatorColor;
    Widget indicatorChild;

    if (isCompleted) {
      indicatorColor = AppColors.semanticUp;
      indicatorChild = const Icon(Icons.check, size: 14, color: Colors.white);
    } else if (isActive) {
      indicatorColor = AppColors.primary;
      indicatorChild = const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    } else {
      indicatorColor = AppColors.hairlineSubtle;
      indicatorChild = Text(
        '$stepNumber',
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'StyreneB',
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      );
    }

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: indicatorColor,
          ),
          child: Center(child: indicatorChild),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'StyreneB',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCompleted || isActive
                      ? AppColors.ink
                      : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'StyreneB',
                  fontSize: 11,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineDivider({required bool isCompleted}) {
    return Container(
      margin: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
      height: 18,
      width: 2,
      color: isCompleted ? AppColors.semanticUp : AppColors.hairlineSubtle,
    );
  }
}
