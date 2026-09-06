import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../home/screens/home_dashboard_screen.dart';
import '../onboarding/screens/onboarding_screen.dart';
import '../travel/screens/destination_selection_screen.dart';

export '../home/screens/home_dashboard_screen.dart';
export '../onboarding/screens/onboarding_screen.dart';
export '../travel/screens/destination_selection_screen.dart';
export '../travel/widgets/traveling_in_indicator.dart';

/// Base template for Phase 1 placeholder screens
class BasePlaceholderScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? actionArea;

  const BasePlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionArea,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Brand mark prefix
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(
                      Icons.blur_on_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'VessPay',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'Georgia',
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Central feature card
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Icon(icon, size: 28, color: AppColors.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Georgia',
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ?actionArea,
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Onboarding Screen typedef for backwards compatibility (Phase 1 T1.6 & UI Polish)
typedef OnboardingPlaceholderScreen = OnboardingScreen;

/// Login Placeholder Screen (Phase 1 T1.6)
class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BasePlaceholderScreen(
      key: const Key('login_screen'),
      title: 'Sign In',
      subtitle: 'Enter your credentials to access your VessPay wallet.',
      icon: Icons.lock_outline_rounded,
      actionArea: Column(
        children: [
          ElevatedButton(
            key: const Key('login_to_home_button'),
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Enter (Demo to Home)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('login_back_button'),
            onPressed: () => context.go(AppRoutes.onboarding),
            child: const Text('Back to Onboarding'),
          ),
        ],
      ),
    );
  }
}

/// Signup Placeholder Screen (Phase 1 T1.6)
class SignupPlaceholderScreen extends StatelessWidget {
  const SignupPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BasePlaceholderScreen(
      key: const Key('signup_screen'),
      title: 'Create an Account',
      subtitle: 'Start paying across Africa in seconds with your USD wallet.',
      icon: Icons.person_add_outlined,
      actionArea: Column(
        children: [
          ElevatedButton(
            key: const Key('signup_to_travel_button'),
            onPressed: () => context.go(AppRoutes.travelModeSetup),
            child: const Text('Continue to Travel Setup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('signup_to_login_button'),
            onPressed: () => context.go(AppRoutes.login),
            child: const Text('Already have an account? Sign In'),
          ),
        ],
      ),
    );
  }
}

/// Travel Mode Setup Screen typedef for backwards compatibility (Phase 2 T2.2)
typedef TravelModeSetupPlaceholderScreen = DestinationSelectionScreen;

/// Home Dashboard Screen typedef for backwards compatibility (Phase 1 T1.7 & UI Polish)
typedef HomePlaceholderScreen = HomeDashboardScreen;

