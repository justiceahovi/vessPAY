import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class PaymentSelectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? badge;
  final bool isSelected;
  final VoidCallback onTap;
  final Key? cardKey;

  const PaymentSelectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badge,
    required this.isSelected,
    required this.onTap,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: cardKey,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.04)
                  : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.hairlineSubtle,
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.20),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.hairline,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
