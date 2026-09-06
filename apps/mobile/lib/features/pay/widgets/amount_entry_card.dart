import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Hero amount input plus quick preset chips, in the recipient's currency.
class AmountEntryCard extends StatelessWidget {
  final TextEditingController controller;
  final String currencySymbol;
  final ValueChanged<double> onAmountChanged;
  final List<int> presets;
  final FocusNode? focusNode;

  const AmountEntryCard({
    super.key,
    required this.controller,
    required this.currencySymbol,
    required this.onAmountChanged,
    this.presets = const [50, 100, 150, 300, 500],
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairlineSubtle, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recipient Receives ($currencySymbol)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    currencySymbol,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('pay_amount_field'),
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.8,
                      ),
                      decoration: InputDecoration(
                        hintText: '150.00',
                        hintStyle: GoogleFonts.inter(
                          color: AppColors.mutedSoft,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) =>
                          onAmountChanged(double.tryParse(val.trim()) ?? 0.0),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an amount';
                        }
                        final parsed = double.tryParse(value.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Please enter a valid amount greater than 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((amount) {
            final isSelected = controller.text.trim() == amount.toString();

            return InkWell(
              key: Key('pay_chip_$amount'),
              borderRadius: BorderRadius.circular(100),
              onTap: () {
                HapticFeedback.selectionClick();
                controller.text = amount.toString();
                onAmountChanged(amount.toDouble());
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppColors.primary : AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.hairlineSubtle,
                    width: 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '$currencySymbol$amount',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.onPrimary : AppColors.ink,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
