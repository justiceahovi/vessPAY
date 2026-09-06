import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';

/// 3-slide modern onboarding carousel replacing the single placeholder screen
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingSlideData> _slides = const [
    _OnboardingSlideData(
      badge: 'SEAMLESS TRAVEL PAYMENTS',
      title: 'Welcome to VessPay',
      subtitle:
          'Pay anyone in Africa via Mobile Money without needing a local SIM or local bank account.',
      icon: Icons.flight_takeoff_rounded,
      highlightText: 'Zero Roaming Friction',
    ),
    _OnboardingSlideData(
      badge: 'INSTANT LOCAL DISBURSEMENT',
      title: 'Direct to MTN, Telecel & AirtelTigo',
      subtitle:
          'Pay vendors, taxi drivers, restaurants, and friends in seconds with automated mobile network resolution.',
      icon: Icons.bolt_rounded,
      highlightText: 'GhIPSS Instant Rail',
    ),
    _OnboardingSlideData(
      badge: 'INSTITUTIONAL GRADE',
      title: 'Protected Treasury & Transparent Rates',
      subtitle:
          'USD held in WeWire FDIC-insured partner treasury bank. Payouts cleared over Bank of Ghana rails with a clear 1% flat fee.',
      icon: Icons.shield_outlined,
      highlightText: 'FDIC-Insured Custody',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('onboarding_screen'),
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Brand Bar Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(
                      Icons.blur_on_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'VessPay',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  // Clean Skip button instead of premature destination badge
                  TextButton(
                    key: const Key('onboarding_skip_button'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.go(AppRoutes.login);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Carousel PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Card container per DESIGN.md
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCard,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.hairline),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ink.withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Floating Icon circle
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceStrong,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  slide.icon,
                                  size: 34,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Eyebrow badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceStrong,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  slide.badge,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Display headline per DESIGN.md (Weight 400 Inter)
                              Text(
                                slide.title,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.ink,
                                  height: 1.15,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Subtitle
                              Text(
                                slide.subtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.body,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Feature chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceStrong,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: AppColors.semanticUp,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      slide.highlightText,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Swipe indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? AppColors.primary
                        : AppColors.hairline,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons (Preserve test keys, Pill geometry per DESIGN.md)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  ElevatedButton(
                    key: const Key('onboarding_signup_button'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.go(AppRoutes.signup);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('onboarding_login_button'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.go(AppRoutes.login);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlideData {
  final String badge;
  final String title;
  final String subtitle;
  final IconData icon;
  final String highlightText;

  const _OnboardingSlideData({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.highlightText,
  });
}
