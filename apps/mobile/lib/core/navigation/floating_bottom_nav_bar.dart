import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';

/// A modern, institutional-grade 3-item floating bottom navigation bar
/// laid out as Profile | Home | Transactions, with Home as the centre default
/// adhering strictly to DESIGN.md tokens:
/// - Vertical orientation: icons on top, labels directly underneath
/// - Pill geometry: rounded.pill (100px)
/// - Base canvas: pure white with subtle hairline border
/// - Brand voltage: Coinbase Blue (#0052FF) on primary CTAs & active states
/// - Elevation: soft drop shadow (card-on-card depth)
class FloatingBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTabSelected;

  const FloatingBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onTabSelected,
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
          context.go(AppRoutes.profile);
        }
        break;
      case 1:
        if (currentIndex != 1) {
          context.go(AppRoutes.home);
        }
        break;
      case 2:
        if (currentIndex != 2) {
          context.go(AppRoutes.transactionList);
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Profile Tab
                  Expanded(
                    child: _buildVerticalNavItem(
                      context: context,
                      index: 0,
                      icon: currentIndex == 0
                          ? Icons.person_rounded
                          : Icons.person_outline_rounded,
                      label: 'Profile',
                      isSelected: currentIndex == 0,
                      key: const Key('nav_item_profile'),
                    ),
                  ),

                  // 2. Home Tab (centre, default destination)
                  Expanded(
                    child: _buildVerticalNavItem(
                      context: context,
                      index: 1,
                      icon: currentIndex == 1
                          ? Icons.home_rounded
                          : Icons.home_outlined,
                      label: 'Home',
                      isSelected: currentIndex == 1,
                      key: const Key('nav_item_home'),
                    ),
                  ),

                  // 3. Transactions Tab
                  Expanded(
                    child: _buildVerticalNavItem(
                      context: context,
                      index: 2,
                      icon: currentIndex == 2
                          ? Icons.receipt_long_rounded
                          : Icons.receipt_long_outlined,
                      label: 'Transactions',
                      isSelected: currentIndex == 2,
                      key: const Key('nav_item_transactions'),
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
    final iconColor = isSelected ? AppColors.onPrimary : AppColors.muted;
    final textColor = isSelected ? AppColors.onPrimary : AppColors.muted;

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, index),
        borderRadius: BorderRadius.circular(100),
        splashColor: isSelected
            ? Colors.white.withValues(alpha: 0.15)
            : AppColors.primary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: iconColor,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
