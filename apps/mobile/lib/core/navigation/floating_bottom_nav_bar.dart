import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';

/// A modern, institutional-grade 3-item floating bottom navigation bar
/// adhering strictly to DESIGN.md tokens:
/// - Vertical orientation: icons on top, labels directly underneath
/// - Pill geometry: rounded.pill (100px)
/// - Base canvas: pure white with subtle hairline border
/// - Brand voltage: Coinbase Blue (#0052FF) on primary CTAs & active states
/// - Elevation: soft drop shadow (card-on-card depth)
class FloatingBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTabSelected;
  final String thirdTabLabel;

  const FloatingBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onTabSelected,
    this.thirdTabLabel = 'Cards',
  });

  void _handleTap(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    if (onTabSelected != null) {
      onTabSelected!(index);
      return;
    }

    switch (index) {
      case 0:
        if (currentIndex != 0) {
          context.go(AppRoutes.home);
        }
        break;
      case 1:
        context.push(AppRoutes.payAnyone);
        break;
      case 2:
        if (currentIndex != 2) {
          context.push(AppRoutes.wallet);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(left: 24, right: 24, bottom: 18),
        height: 68,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: AppColors.hairline.withValues(alpha: 0.85),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Home Tab
                  Expanded(
                    child: _buildVerticalNavItem(
                      context: context,
                      index: 0,
                      icon: currentIndex == 0
                          ? Icons.home_rounded
                          : Icons.home_outlined,
                      label: 'Home',
                      isSelected: currentIndex == 0,
                      key: const Key('nav_item_home'),
                    ),
                  ),

                  // 2. Center Pay Hero CTA
                  Expanded(
                    child: _buildCenterPayItem(
                      context: context,
                      isSelected: currentIndex == 1,
                      key: const Key('nav_item_pay'),
                    ),
                  ),

                  // 3. Cards / Wallet Tab
                  Expanded(
                    child: _buildVerticalNavItem(
                      context: context,
                      index: 2,
                      icon: currentIndex == 2
                          ? Icons.credit_card_rounded
                          : Icons.credit_card_outlined,
                      label: thirdTabLabel,
                      isSelected: currentIndex == 2,
                      key: const Key('nav_item_cards'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

  Widget _buildVerticalNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    Key? key,
  }) {
    final activeColor = AppColors.primary;
    final inactiveColor = AppColors.muted;

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, index),
        borderRadius: BorderRadius.circular(100),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPayItem({
    required BuildContext context,
    required bool isSelected,
    Key? key,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, 1),
        borderRadius: BorderRadius.circular(100),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.send_rounded,
                    size: 15,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Pay',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
