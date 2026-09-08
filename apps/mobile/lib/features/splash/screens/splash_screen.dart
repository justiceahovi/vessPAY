import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../wallet/providers/currency_providers.dart';

/// Splash Screen per VESSPAY_BLUEPRINT.md Section 12 & DESIGN.md
/// Features brand mark, minimal animation, and auth-state routing.
class SplashScreen extends ConsumerStatefulWidget {
  /// Optional duration parameter allowing test overrides
  final Duration minDisplayDuration;

  const SplashScreen({
    super.key,
    this.minDisplayDuration = const Duration(milliseconds: 1100),
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();

    // Kick off auth check and routing logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    final tokenStorage = ref.read(tokenStorageProvider);

    // Run auth check and minimum animation timer in parallel
    final results = await Future.wait([
      tokenStorage.hasToken(),
      Future.delayed(widget.minDisplayDuration),
    ]);

    final hasValidToken = results[0] as bool;

    if (!mounted) return;

    if (!hasValidToken) {
      context.go(AppRoutes.welcome);
      return;
    }

    // Signed in: resolve the wallet currency this account holds. Accounts that
    // never picked one (including those created before the choice existed) are
    // sent to pick it before reaching the dashboard.
    String? currency;
    try {
      currency = await ref.read(walletCurrencyProvider.future);
    } catch (_) {
      currency = null;
    }

    if (!mounted) return;

    if (currency == null || currency.isEmpty) {
      context.go(AppRoutes.walletCurrencySetup, extra: AppRoutes.home);
      return;
    }

    context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // VessPay Brand Mark
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.hairline,
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(20, 20, 19, 0.04),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Subtle radiating accent ring
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Central brand icon
                        const Icon(
                          Icons.blur_on_rounded,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // Brand Display Wordmark
                Text(
                  'VessPay',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w400,
                        fontSize: 34,
                        letterSpacing: -0.6,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 10),
                // Editorial Tagline
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Pay in Africa without a local SIM.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontSize: 15,
                          letterSpacing: 0,
                          height: 1.4,
                        ),
                  ),
                ),
                const SizedBox(height: 48),
                // Minimal loading indicator in primary warm coral
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
