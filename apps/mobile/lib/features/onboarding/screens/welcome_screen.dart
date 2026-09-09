import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';

/// The first screen a signed-out user sees.
///
/// Ported from the `welcome` artboard of the "Fintech travel wallet app"
/// Claude Design project. That design runs on its own warm palette — paper
/// cream on a near-black ink, with a blue and a clay glow bleeding off the
/// edges — rather than the cool product tokens in [AppColors], so the colours
/// live here as private constants instead of entering the shared token set.
/// Content is bottom-aligned; the glow does the work in the empty upper half.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// Near-black warm ink the artboard uses as its canvas.
  static const Color _ink = Color(0xFF1E1B16);

  /// Paper cream — headline, logo chip, and the primary button fill.
  static const Color _cream = Color(0xFFFBF8F3);

  /// The two off-canvas glows.
  static const Color _glowBlue = Color(0xFF2C4BD8);
  static const Color _glowClay = Color(0xFF8A5A3B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('welcome_screen'),
      backgroundColor: _ink,
      body: Stack(
        children: [
          // Glows are drawn before the SafeArea so they can bleed past it,
          // and clipped by the Stack so they never scroll the page.
          const Positioned(
            top: -120,
            right: -140,
            child: _Glow(
              size: 420,
              color: _glowBlue,
              opacity: 0.5,
              sigma: 10,
            ),
          ),
          const Positioned(
            top: 120,
            left: -160,
            child: _Glow(
              size: 300,
              color: _glowClay,
              opacity: 0.55,
              sigma: 20,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildLogoMark(),
                  const SizedBox(height: 28),
                  _buildHeadline(),
                  const SizedBox(height: 16),
                  _buildSubhead(),
                  const SizedBox(height: 34),
                  _buildPrimaryAction(context),
                  const SizedBox(height: 16),
                  _buildSecondaryAction(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoMark() {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(14),
      ),
      // The artboard sets a monospace "v" here, but the product already has a
      // brand mark — the same one the login header carries — so the shared
      // icon wins over the placeholder glyph. Sized to the login chip's
      // 18-in-28 ratio.
      child: const Icon(
        Icons.blur_on_rounded,
        size: 28,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildHeadline() {
    return Text(
      'One wallet.\nLocal Everywhere!',
      style: GoogleFonts.schibstedGrotesk(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        color: _cream,
        height: 1.04,
        // -.035em at 40px.
        letterSpacing: -1.4,
      ),
    );
  }

  Widget _buildSubhead() {
    return ConstrainedBox(
      // The artboard holds this to a 29ch measure so it breaks well short of
      // the button beneath it.
      constraints: const BoxConstraints(maxWidth: 300),
      child: Text(
        'Your money travels acrros Africa.'
        'We connect it to local payment rails wherever you go!',
        style: GoogleFonts.schibstedGrotesk(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: _cream.withValues(alpha: 0.72),
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        key: const Key('welcome_get_started_button'),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.go(AppRoutes.signup);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _cream,
          foregroundColor: _ink,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          'Get started',
          style: GoogleFonts.schibstedGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryAction(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        key: const Key('welcome_login_button'),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.go(AppRoutes.login);
        },
        style: TextButton.styleFrom(
          foregroundColor: _cream.withValues(alpha: 0.74),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(
          'I already have an account',
          style: GoogleFonts.schibstedGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// A soft off-canvas colour wash. CSS `filter: blur(Npx)` maps to a Gaussian
/// of standard deviation N, so [sigma] carries the artboard's blur radius
/// straight across.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.size,
    required this.color,
    required this.opacity,
    required this.sigma,
  });

  final double size;
  final Color color;
  final double opacity;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
