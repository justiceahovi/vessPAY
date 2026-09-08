import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';

/// 3-slide onboarding carousel.
///
/// Built as the `hero-band-dark` pattern from DESIGN.md — the signature
/// full-bleed dark hero: display headline left at weight 400 with negative
/// tracking, subhead in body, two CTA pills. Slide content is bottom-aligned
/// so the whitespace collects above it as deliberate editorial pacing, rather
/// than pooling around a centred card.
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

  /// Hairline that reads on a dark canvas, where the light-mode hairline token
  /// would be invisible.
  static final Color _darkHairline = Colors.white.withValues(alpha: 0.08);

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
      backgroundColor: AppColors.surfaceDark,
      body: Stack(
        children: [
          // Decorative brand glow. DESIGN.md leans on decorative depth where a
          // dark canvas cannot show a shadow.
          Positioned(
            top: -180,
            left: -80,
            right: -80,
            height: 560,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.22),
                    AppColors.surfaceDark.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                _buildHeader(context),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: _slides.length,
                    itemBuilder: (context, index) => _buildSlide(_slides[index]),
                  ),
                ),
                _buildDots(),
                const SizedBox(height: 28),
                _buildActions(context),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _darkHairline),
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
              color: AppColors.onDark,
            ),
          ),
          const Spacer(),
          TextButton(
            key: const Key('onboarding_skip_button'),
            onPressed: () {
              HapticFeedback.lightImpact();
              context.go(AppRoutes.login);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onDarkSoft,
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
    );
  }

  Widget _buildSlide(_OnboardingSlideData slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              shape: BoxShape.circle,
              border: Border.all(color: _darkHairline),
            ),
            child: Icon(
              slide.icon,
              size: 28,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),

          // Eyebrow badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: _darkHairline),
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
          const SizedBox(height: 16),

          // Display headline — weight stays at 400 per DESIGN.md.
          Text(
            slide.title,
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: AppColors.onDark,
              height: 1.08,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 14),

          Text(
            slide.subtitle,
            style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.onDarkSoft,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),

          // Feature chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: _darkHairline),
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
                    color: AppColors.onDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
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
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('onboarding_signup_button'),
              onPressed: () {
                HapticFeedback.lightImpact();
                context.go(AppRoutes.signup);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
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
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('onboarding_login_button'),
              onPressed: () {
                HapticFeedback.lightImpact();
                context.go(AppRoutes.login);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.onDark,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                padding: const EdgeInsets.symmetric(vertical: 15),
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
          ),
        ],
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
