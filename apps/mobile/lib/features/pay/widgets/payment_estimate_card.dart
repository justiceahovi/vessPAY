import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/payment_estimate.dart';

/// Breakdown of what the payment will cost, plus the wallet balance it will be
/// taken from. Everything here is a local estimate; the server figure is shown
/// on the review screen, which is why the heading says so.
class PaymentEstimateCard extends StatelessWidget {
  final PaymentEstimate estimate;
  final String currencySymbol;

  /// Available USD balance, or null while it is still loading / unavailable.
  final double? availableBalance;

  const PaymentEstimateCard({
    super.key,
    required this.estimate,
    required this.currencySymbol,
    this.availableBalance,
  });

  bool get _isInsufficient =>
      availableBalance != null &&
      estimate.total > 0 &&
      estimate.total > availableBalance!;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceDarkElevated),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live Rate Reference',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '1 USD = $currencySymbol${estimate.exchangeRate.toStringAsFixed(2)}',
                    key: const Key('pay_live_rate_text'),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                  ),
                ],
              ),
              const Divider(color: AppColors.surfaceDarkElevated, height: 20),
              _row(
                'Estimated USD Debit',
                '\$${estimate.sourceAmount.toStringAsFixed(2)}',
                valueKey: const Key('pay_estimated_usd_text'),
              ),
              const SizedBox(height: 8),
              _row(
                'Transfer Fee (1%)',
                '\$${estimate.fee.toStringAsFixed(2)}',
                valueKey: const Key('pay_estimated_fee_text'),
              ),
              const Divider(color: AppColors.surfaceDarkElevated, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Estimated Total',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onDark,
                    ),
                  ),
                  Text(
                    '\$${estimate.total.toStringAsFixed(2)} USD',
                    key: const Key('pay_estimated_total_text'),
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (availableBalance != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Wallet Balance',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                    Text(
                      'Available \$${availableBalance!.toStringAsFixed(2)}',
                      key: const Key('pay_available_balance_text'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isInsufficient
                            ? AppColors.semanticDown
                            : AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Estimate only. The final amount is confirmed on the next screen.',
                key: const Key('pay_estimate_disclaimer'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.onDarkSoft.withValues(alpha: 0.8),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (_isInsufficient) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('pay_insufficient_balance_warning'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This is more than your wallet holds. Add money or lower the amount.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.error,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {required Key valueKey}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: AppColors.onDarkSoft,
          ),
        ),
        Text(
          value,
          key: valueKey,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onDark,
          ),
        ),
      ],
    );
  }
}
