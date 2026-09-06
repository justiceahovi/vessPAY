import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../models/kyc_model.dart';
import '../providers/kyc_providers.dart';

/// The money-movement flows a user has to be verified to reach.
enum KycGatedAction {
  addMoney,
  sendMoney;

  /// Reads as "...before you can `phrase`".
  String get phrase => switch (this) {
    KycGatedAction.addMoney => 'add money to your wallet',
    KycGatedAction.sendMoney => 'send money',
  };

  String get shortLabel => switch (this) {
    KycGatedAction.addMoney => 'Adding money',
    KycGatedAction.sendMoney => 'Sending money',
  };
}

/// Wraps a screen body that moves money and shows an institutional-grade,
/// modern glassmorphic prompt to finish identity verification instead,
/// when the user is not approved yet.
///
/// Deliberately fails open: if the status cannot be read (offline, backend
/// down) the user keeps their normal flow rather than being locked out of their
/// own money by a failed lookup.
class KycGate extends ConsumerWidget {
  final KycGatedAction action;
  final Widget child;

  const KycGate({super.key, required this.action, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(kycStatusProvider);

    if (statusAsync.hasError) return child;

    final status = statusAsync.valueOrNull;
    if (status == null) {
      return Center(
        key: const Key('kyc_gate_loading'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.95),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    }

    if (status.isApproved) return child;

    // The flow stays on screen behind a frosted glass scrim so the user can
    // see what they are unlocking, beautifully blurred and inert until verified.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: child),
        Positioned.fill(
          child: GestureDetector(
            key: const Key('kyc_gate_scrim'),
            onTap: () => dismissKycNudge(context),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.42),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: KycNudgeSheet(action: action, status: status),
        ),
      ],
    );
  }
}

/// Leaves a gated flow. The pay flow can be reached as a nav tab with nothing
/// to pop, so fall back to home rather than stranding the user.
void dismissKycNudge(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    context.go(AppRoutes.home);
  }
}

/// The nudge itself: ultra-premium glassmorphic bottom sheet, featuring
/// translucent crystalline surfaces, specular highlight rims, glowing ambient
/// status badges, and high-gloss CTAs.
class KycNudgeSheet extends StatelessWidget {
  final KycGatedAction action;
  final KycStatusModel status;

  const KycNudgeSheet({super.key, required this.action, required this.status});

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color accent;
    late final String badgeTag;
    late final String headline;
    late final String body;
    late final String primaryLabel;
    late final List<String> points;

    switch (status.state) {
      case KycVerificationState.inReview:
        icon = Icons.hourglass_top_rounded;
        accent = AppColors.warning;
        badgeTag = 'VERIFICATION IN PROGRESS';
        headline = 'Hang tight — we are reviewing your ID';
        body =
            '${action.shortLabel} unlocks as soon as compliance finishes checking your documents. '
            'It usually takes just a few minutes.';
        primaryLabel = 'Check Verification Status';
        points = const [];
        break;
      case KycVerificationState.rejected:
        icon = Icons.gpp_bad_rounded;
        accent = AppColors.error;
        badgeTag = 'ACTION REQUIRED';
        headline = 'We could not verify your ID';
        body =
            'Compliance could not confirm your details, so we cannot let you ${action.phrase} yet. '
            'Re-submitting usually sorts it out.';
        primaryLabel = 'Re-submit Documents';
        points = const [];
        break;
      case KycVerificationState.notStarted:
      case KycVerificationState.approved:
        icon = Icons.verified_user_rounded;
        accent = AppColors.primary;
        badgeTag = 'ONE-TIME VERIFICATION';
        headline = 'One quick step first';
        body =
            'We need to confirm who you are before you can ${action.phrase}. '
            'It takes about two minutes and you only do it once.';
        primaryLabel = 'Verify My Identity';
        points = const [
          'A photo of your passport, ID card or licence',
          'A quick selfie to match it',
          'Most checks clear within minutes',
        ];
        break;
    }

    return TweenAnimationBuilder<double>(
      key: const Key('kyc_gate_nudge'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, sheet) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1.0 - value) * 160),
          child: sheet,
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.82),
                  Colors.white.withValues(alpha: 0.68),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.14),
                  blurRadius: 40,
                  spreadRadius: -4,
                  offset: const Offset(0, -8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Glass Grab handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        margin: const EdgeInsets.only(bottom: 22),
                        decoration: BoxDecoration(
                          color: AppColors.ink.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 0.8,
                          ),
                        ),
                      ),
                    ),

                    // Badge and Status Tag Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Ambient blur glow
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.35),
                                    blurRadius: 26,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            // Frosted glass ring & icon
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accent.withValues(alpha: 0.18),
                                    accent.withValues(alpha: 0.08),
                                  ],
                                ),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.38),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.18),
                                    blurRadius: 14,
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                              child: Icon(icon, color: accent, size: 28),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      badgeTag,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: accent,
                                        letterSpacing: 0.5,
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

                    const SizedBox(height: 20),

                    // Headline
                    Text(
                      headline,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.22,
                        letterSpacing: -0.4,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Body
                    Text(
                      body,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        color: AppColors.body,
                        height: 1.45,
                        letterSpacing: -0.1,
                      ),
                    ),

                    // Value propositions or status timeline card
                    if (points.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.80),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.03),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < points.length; i++) ...[
                              if (i > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  child: Container(
                                    height: 1,
                                    color: AppColors.hairlineSubtle.withValues(alpha: 0.7),
                                  ),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF05B169),
                                          Color(0xFF039855),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.success.withValues(alpha: 0.30),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      points[i],
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.bodyStrong,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else if (status.state == KycVerificationState.inReview) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.28),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.warning.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.access_time_rounded,
                                size: 20,
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Average turnaround: ~2 minutes',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'We will notify you automatically upon approval.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: AppColors.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (status.state == KycVerificationState.rejected) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.error.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.tips_and_updates_outlined,
                                size: 20,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tips for quick resolution',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ensure all corners are visible with no glare or blur.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: AppColors.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 26),

                    // Primary High-Gloss CTA Button
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1E6BFF),
                            Color(0xFF0052FF),
                            Color(0xFF003ECC),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.38),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        key: const Key('kyc_nudge_primary_button'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push(AppRoutes.kycVerification);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              primaryLabel,
                              style: GoogleFonts.inter(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Secondary Glass CTA Button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        key: const Key('kyc_nudge_dismiss_button'),
                        onPressed: () => dismissKycNudge(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.muted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        child: Text(
                          'Maybe later',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Security & Compliance Trust Lock
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: AppColors.mutedSoft.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '256-bit encrypted • Regulated compliance partner',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.mutedSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
