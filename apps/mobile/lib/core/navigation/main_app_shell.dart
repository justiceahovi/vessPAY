import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import 'floating_bottom_nav_bar.dart';

/// Provider to track current active navigation tab index
final activeNavIndexProvider = StateProvider<int>((ref) => 0);

/// Main persistent app shell providing a modern 3-item floating bottom navigation bar
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
    if (location.startsWith('/wallet')) {
      return 2;
    } else if (location.startsWith('/pay')) {
      return 1;
    }
    return 0;
  }

  void _onTabSelected(BuildContext context, WidgetRef ref, int index) {
    HapticFeedback.selectionClick();
    ref.read(activeNavIndexProvider.notifier).state = index;

    final location = currentLocation ?? GoRouterState.of(context).uri.path;

    switch (index) {
      case 0:
        if (location != AppRoutes.home) {
          context.go(AppRoutes.home);
        }
        break;
      case 1:
        if (location != AppRoutes.payAnyone) {
          context.go(AppRoutes.payAnyone);
        }
        break;
      case 2:
        if (location != AppRoutes.wallet) {
          context.go(AppRoutes.wallet);
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
              thirdTabLabel: 'Cards',
              onTabSelected: (index) => _onTabSelected(context, ref, index),
            ),
    );
  }
}

