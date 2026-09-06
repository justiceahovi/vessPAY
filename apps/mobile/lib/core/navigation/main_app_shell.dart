import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import 'floating_bottom_nav_bar.dart';

/// Provider to track current active navigation tab index (Home is the default)
final activeNavIndexProvider = StateProvider<int>((ref) => 1);

/// Main persistent app shell providing a modern 3-item floating bottom
/// navigation bar laid out as Profile | Home | Transactions
class MainAppShell extends ConsumerWidget {
  final Widget child;
  final String? currentLocation;

  const MainAppShell({
    super.key,
    required this.child,
    this.currentLocation,
  });

  /// Derives the active navigation index based on the URI path
  static int calculateIndexForLocation(String location) {
    if (location.startsWith(AppRoutes.profile)) {
      return 0;
    } else if (location.startsWith(AppRoutes.transactionList)) {
      return 2;
    }
    return 1;
  }

  void _onTabSelected(BuildContext context, WidgetRef ref, int index) {
    HapticFeedback.selectionClick();
    ref.read(activeNavIndexProvider.notifier).state = index;

    final location = currentLocation ?? GoRouterState.of(context).uri.path;

    switch (index) {
      case 0:
        if (location != AppRoutes.profile) {
          context.go(AppRoutes.profile);
        }
        break;
      case 1:
        if (location != AppRoutes.home) {
          context.go(AppRoutes.home);
        }
        break;
      case 2:
        if (location != AppRoutes.transactionList) {
          context.go(AppRoutes.transactionList);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = currentLocation ?? GoRouterState.of(context).uri.path;
    final activeIndex = calculateIndexForLocation(location);

    // Hide floating nav bar when keyboard is open to avoid obscuring form inputs
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: child,
      extendBody: false,
      bottomNavigationBar: isKeyboardOpen
          ? const SizedBox.shrink()
          : FloatingBottomNavBar(
              currentIndex: activeIndex,
              onTabSelected: (index) => _onTabSelected(context, ref, index),
            ),
    );
  }
}

