import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/pay_flow_model.dart';

/// Bank payouts run over WeWire's BANK disbursement channel, verified against
/// the sandbox. Flip this to false to hide the option if the rail is withdrawn.
const bool kBankTransferEnabled = true;

/// Compact two-option payment method control. Replaces the former full step:
/// mobile money is the default and most users never touch this.
class PaymentMethodSelector extends StatelessWidget {
  final PaymentType selected;
  final ValueChanged<PaymentType> onChanged;
  final bool bankEnabled;

  const PaymentMethodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.bankEnabled = kBankTransferEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              segmentKey: const Key('pay_type_mobile_money'),
              icon: Icons.phone_android_rounded,
              label: 'Mobile Money',
              isSelected: selected == PaymentType.mobileMoney,
              onTap: () => onChanged(PaymentType.mobileMoney),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentButton(
              segmentKey: const Key('pay_type_bank'),
              icon: Icons.account_balance_rounded,
              label: 'Bank',
              badge: bankEnabled ? null : 'Soon',
              isSelected: bankEnabled && selected == PaymentType.bankTransfer,
              onTap: bankEnabled
                  ? () => onChanged(PaymentType.bankTransfer)
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          key: Key('pay_bank_unavailable_snackbar'),
                          content: Text(
                            'Bank transfers are coming soon. Mobile money payouts are live today.',
                          ),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final Key segmentKey;
  final IconData icon;
  final String label;
  final String? badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.segmentKey,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? AppColors.primary
        : (badge != null ? AppColors.mutedSoft : AppColors.muted);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: segmentKey,
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.hairline, width: 0.8),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedSoft,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
