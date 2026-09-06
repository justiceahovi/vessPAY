import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// Wraps a screen body that moves money and shows a friendly prompt to finish
/// identity verification instead, when the user is not approved yet.
///
/// Deliberately fails open: if the status cannot be read (offline, backend
/// down) the user keeps their normal flow rather than being locked out of their
/// own money by a failed lookup.
class KycGate extends ConsumerWidget {
  final KycGatedAction action;
  final Widget child;

  const KycGate({
    super.key,
    required this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(kycStatusProvider);

    if (statusAsync.hasError) return child;

    final status = statusAsync.valueOrNull;
    if (status == null) {
      return const Center(
        key: Key('kyc_gate_loading'),
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }

    if (status.isApproved) return child;

    return KycNudgeView(action: action, status: status);
  }
}

/// The nudge itself: warm, specific about what is missing, and one tap from
/// the verification flow.
class KycNudgeView extends StatelessWidget {
  final KycGatedAction action;
  final KycStatusModel status;

  const KycNudgeView({
    super.key,
    required this.action,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color accent;
    late final String headline;
    late final String body;
    late final String primaryLabel;
    late final List<String> points;

    switch (status.state) {
      case KycVerificationState.inReview:
        icon = Icons.hourglass_top_rounded;
        accent = AppColors.warning;
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
        headline = 'We could not verify your ID';
        body =
            'Compliance could not confirm your details, so we cannot let you ${action.phrase} yet. '
            'Re-submitting usually sorts it out.';
        primaryLabel = 'Re-submit Documents';
        points = const [];
        break;
      case KycVerificationState.notStarted:
      case KycVerificationState.approved:
        icon = Icons.verified_user_outlined;
        accent = AppColors.primary;
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

    return SafeArea(
      key: const Key('kyc_gate_nudge'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              headline,
              style: const TextStyle(
                fontFamily: 'StyreneB',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                fontFamily: 'StyreneB',
                fontSize: 14.5,
                color: AppColors.body,
                height: 1.45,
              ),
            ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairlineSubtle),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < points.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 17, color: AppColors.success),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              points[i],
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 13.5,
                                color: AppColors.body,
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
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const Key('kyc_nudge_primary_button'),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push(AppRoutes.kycVerification);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                key: const Key('kyc_nudge_dismiss_button'),
                onPressed: () {
                  // The pay flow can be reached as a nav tab with nothing to
                  // pop, so fall back to home rather than stranding the user.
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go(AppRoutes.home);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                child: const Text(
                  'Maybe later',
                  style: TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
