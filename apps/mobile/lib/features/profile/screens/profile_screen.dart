import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/navigation/main_app_bar.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/models/user_model.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../kyc/models/kyc_model.dart';
import '../../kyc/providers/kyc_providers.dart';
import '../../travel/providers/travel_providers.dart';

/// Provider for user profile data on Profile screen
final profileUserProvider = FutureProvider<UserModel?>((ref) async {
  try {
    return await ref.watch(authRepositoryProvider).getProfile();
  } catch (_) {
    return null;
  }
});

/// Dedicated Profile & Account Screen accessed from the top-left avatar icon.
/// Features profile picture/avatar, user name, KYC status, share app link,
/// invite a friend referral link, travel corridor settings, and account actions.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const String _defaultShareUrl = 'https://vesspay.com/app';

  String _getReferralCode(UserModel? user) {
    if (user != null && user.firstName.isNotEmpty) {
      final sanitized = user.firstName
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toUpperCase();
      return 'VESSPAY-$sanitized';
    }
    return 'VESSPAY-KWAME';
  }

  void _copyToClipboard(
    BuildContext context,
    String text,
    String successMessage,
  ) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                successMessage,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showShareDialog(
    BuildContext context,
    String title,
    String shareContent,
  ) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColors.muted,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairlineSubtle),
                  ),
                  child: Text(
                    shareContent,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.bodyStrong,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('modal_copy_link_button'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyToClipboard(
                        context,
                        shareContent,
                        'Copied to clipboard!',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy to Clipboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.ink,
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out of your VessPay account?',
          style: TextStyle(fontSize: 14, color: AppColors.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          ElevatedButton(
            key: const Key('profile_confirm_logout_button'),
            onPressed: () async {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              await ref.read(authRepositoryProvider).logout();
              ref.read(currentTravelProfileProvider.notifier).clear();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.semanticDown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(profileUserProvider);
    final kycAsync = ref.watch(kycStatusProvider);
    final travelProfile = ref.watch(currentTravelProfileProvider).valueOrNull;

    final user = userAsync.valueOrNull;
    final displayName =
        (user != null &&
            (user.firstName.isNotEmpty || user.lastName.isNotEmpty))
        ? '${user.firstName} ${user.lastName}'.trim()
        : 'Kwame Doe';

    final email = (user != null && user.email.isNotEmpty)
        ? user.email
        : 'kwame.doe@example.com';

    final referralCode = _getReferralCode(user);
    final referralShareText =
        'Hey! Join me on VessPay to send money and travel across West Africa with zero FX markup. Use my code $referralCode or tap: https://vesspay.com/join/$referralCode';

    final initials = displayName
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join()
        .toUpperCase();

    final flagEmoji = travelProfile?.flagEmoji ?? '🇬🇭';
    final corridorName = travelProfile?.countryName ?? 'Ghana';

    return Scaffold(
      key: const Key('profile_screen'),
      backgroundColor: AppColors.surfaceSubtle,
      // Same header as Home and Transactions; sharing lives in the Share App
      // Link card below.
      appBar: const MainAppBar(
        title: 'Profile & Account',
        avatarOpensProfile: false,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.canvas,
          onRefresh: () async {
            ref.invalidate(profileUserProvider);
            ref.invalidate(kycStatusProvider);
            ref.invalidate(currentTravelProfileProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Profile Picture & Name Header Card
                _buildProfileHeaderCard(
                  displayName: displayName,
                  email: email,
                  initials: initials,
                  corridorName: corridorName,
                  flagEmoji: flagEmoji,
                ),
                const SizedBox(height: 18),

                // 2. KYC Status Card
                _buildKycStatusCard(kycAsync),
                const SizedBox(height: 18),

                // 3. Invite a Friend Card
                _buildInviteFriendCard(
                  referralCode: referralCode,
                  referralShareText: referralShareText,
                ),
                const SizedBox(height: 18),

                // 4. Share App Link Card
                _buildShareAppCard(),
                const SizedBox(height: 24),

                // 5. Account & Preferences Section
                _buildPreferencesSection(corridorName, flagEmoji),
                const SizedBox(height: 20),

                // 6. Log Out Button
                Center(
                  child: TextButton.icon(
                    key: const Key('profile_logout_button'),
                    onPressed: () => _showLogoutDialog(context),
                    icon: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.semanticDown,
                    ),
                    label: const Text(
                      'Log Out of VessPay',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.semanticDown,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Profile Picture, Name, Email, and Corridor Badge
  Widget _buildProfileHeaderCard({
    required String displayName,
    required String email,
    required String initials,
    required String corridorName,
    required String flagEmoji,
  }) {
    return Container(
      key: const Key('profile_header_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairlineSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar with edit/camera badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.surfaceTint,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 2.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    initials.isNotEmpty ? initials : 'KD',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  key: const Key('profile_change_photo_button'),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Profile photo upload will be enabled with camera access.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.canvas, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Full Name
          Text(
            displayName,
            key: const Key('profile_user_name'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),

          // Email
          Text(
            email,
            key: const Key('profile_user_email'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),

          // Corridor badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.hairlineSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flagEmoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  'Traveling in $corridorName',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// KYC Status Section Card.
  ///
  /// Fully driven by [kycStatusProvider]: renders a checking state while the
  /// status is in flight, an actionable error state when the lookup fails, and
  /// status-specific badge/copy/CTA for each [KycVerificationState].
  Widget _buildKycStatusCard(AsyncValue<KycStatusModel> kycAsync) {
    final kyc = kycAsync.valueOrNull;
    final isChecking = kycAsync.isLoading && kyc == null;
    final hasError = kycAsync.hasError && kyc == null;

    Color badgeBg;
    Color badgeText;
    IconData badgeIcon;
    String badgeLabel;
    String description;
    String actionLabel;
    String actionSubtitle;
    VoidCallback? onAction;

    void openKycPortal() {
      HapticFeedback.lightImpact();
      context.push(AppRoutes.kycVerification);
    }

    const portalSubtitle = 'WeWire hosted compliance portal';

    if (isChecking) {
      badgeBg = AppColors.surfaceStrong;
      badgeText = AppColors.muted;
      badgeIcon = Icons.sync_rounded;
      badgeLabel = 'Checking';
      description = 'Fetching your latest verification status…';
      actionLabel = 'Checking status';
      actionSubtitle = portalSubtitle;
      onAction = null;
    } else if (hasError) {
      badgeBg = AppColors.error.withValues(alpha: 0.12);
      badgeText = AppColors.error;
      badgeIcon = Icons.cloud_off_rounded;
      badgeLabel = 'Unavailable';
      description =
          'We could not load your verification status. Check your connection and try again.';
      actionLabel = 'Try Again';
      actionSubtitle = 'Refresh verification status';
      onAction = () {
        HapticFeedback.lightImpact();
        ref.invalidate(kycStatusProvider);
      };
    } else {
      final status = kyc!;
      switch (status.state) {
        case KycVerificationState.approved:
          badgeBg = AppColors.success.withValues(alpha: 0.12);
          badgeText = AppColors.success;
          badgeIcon = Icons.verified_rounded;
          badgeLabel = 'Verified';
          if (status.isEnhancedApproved) {
            description =
                '${status.tierLabel} Verified • Full cross-border wallet & virtual card limits active.';
            actionLabel = 'View Verification Details';
          } else if (status.isEnhancedInReview) {
            description =
                '${status.tierLabel} Verified • Enhanced verification is under review for higher limits.';
            actionLabel = 'View Verification Details';
          } else {
            description =
                '${status.tierLabel} Verified • Complete enhanced verification to unlock higher limits.';
            actionLabel = 'Complete Enhanced Verification';
          }
          actionSubtitle = portalSubtitle;
          onAction = openKycPortal;
          break;
        case KycVerificationState.inReview:
          badgeBg = AppColors.warning.withValues(alpha: 0.15);
          badgeText = const Color(0xFFB45309);
          badgeIcon = Icons.hourglass_top_rounded;
          badgeLabel = 'In Review';
          description =
              'Your identity documents are currently under review by compliance.';
          actionLabel = 'Check Verification Status';
          actionSubtitle = portalSubtitle;
          onAction = openKycPortal;
          break;
        case KycVerificationState.rejected:
          badgeBg = AppColors.error.withValues(alpha: 0.12);
          badgeText = AppColors.error;
          badgeIcon = Icons.gpp_bad_rounded;
          badgeLabel = 'Verification Failed';
          description =
              'Compliance could not verify your identity. Re-submit your documents to restore payouts.';
          actionLabel = 'Re-submit Documents';
          actionSubtitle = portalSubtitle;
          onAction = openKycPortal;
          break;
        case KycVerificationState.notStarted:
          badgeBg = AppColors.primary.withValues(alpha: 0.1);
          badgeText = AppColors.primary;
          badgeIcon = Icons.shield_outlined;
          badgeLabel = 'Action Required';
          description =
              'Complete verification to unlock higher transaction limits and payouts.';
          actionLabel = 'Verify Identity Now';
          actionSubtitle = portalSubtitle;
          onAction = openKycPortal;
          break;
      }
    }

    final actionColor = onAction == null ? AppColors.muted : AppColors.primary;

    return Container(
      key: const Key('profile_kyc_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairlineSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(badgeIcon, color: badgeText, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Identity Verification',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Container(
                  key: const Key('profile_kyc_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 12, color: badgeText),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          badgeLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: badgeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            key: const Key('profile_kyc_description'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            key: const Key('home_kyc_card'),
            onTap: onAction,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairlineSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actionLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: actionColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          actionSubtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    hasError
                        ? Icons.refresh_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: hasError ? 15 : 13,
                    color: actionColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Invite a Friend & Referral Reward Card
  Widget _buildInviteFriendCard({
    required String referralCode,
    required String referralShareText,
  }) {
    return Container(
      key: const Key('profile_invite_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairlineSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceGreenTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.semanticUp,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite a Friend, Get \$10',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'You both get \$10 when they make their first transfer.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Referral Code Box with 1-tap Copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR REFERRAL CODE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      referralCode,
                      key: const Key('profile_referral_code_text'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: const Key('profile_copy_code_button'),
                  onPressed: () => _copyToClipboard(
                    context,
                    referralCode,
                    'Referral code copied to clipboard!',
                  ),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'Copy',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    backgroundColor: AppColors.surfaceTint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Invite Friends Action Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              key: const Key('profile_invite_button'),
              onPressed: () => _showShareDialog(
                context,
                'Invite a Friend',
                referralShareText,
              ),
              icon: const Icon(Icons.person_add_rounded, size: 17),
              label: const Text(
                'Invite Friends',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Share App Link Card
  Widget _buildShareAppCard() {
    return Container(
      key: const Key('profile_share_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairlineSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.share_rounded,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share VessPay',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Share the app link with fellow travelers & business partners.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Download URL container with Copy Link and Share action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairlineSubtle),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _defaultShareUrl,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  key: const Key('profile_copy_share_link_button'),
                  onTap: () => _copyToClipboard(
                    context,
                    _defaultShareUrl,
                    'VessPay download link copied!',
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      'Copy Link',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              key: const Key('profile_share_app_button'),
              onPressed: () => _showShareDialog(
                context,
                'Share VessPay App',
                'Download VessPay - Send money and make payments seamlessly across Africa: $_defaultShareUrl',
              ),
              icon: const Icon(
                Icons.ios_share_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              label: const Text(
                'Share App Link',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: AppColors.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.hairline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Preferences and Account Settings Section
  Widget _buildPreferencesSection(String corridorName, String flagEmoji) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Column(
        children: [
          ListTile(
            key: const Key('profile_travel_setup_tile'),
            leading: const Icon(
              Icons.flight_takeoff_rounded,
              color: AppColors.primary,
            ),
            title: const Text(
              'Travel Corridor Setup',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              'Active: $corridorName $flagEmoji (Tap to switch)',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.muted,
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.travelModeSetup);
            },
          ),
          const Divider(height: 1, indent: 56, color: AppColors.hairlineSoft),
          ListTile(
            key: const Key('profile_rates_tile'),
            leading: const Icon(
              Icons.currency_exchange_rounded,
              color: AppColors.primary,
            ),
            title: const Text(
              'Live FX Rates & Corridors',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Real-time quotes with zero markup',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.muted,
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.travelModeSetup);
            },
          ),
          const Divider(height: 1, indent: 56, color: AppColors.hairlineSoft),
          ListTile(
            key: const Key('profile_support_tile'),
            leading: const Icon(
              Icons.support_agent_rounded,
              color: AppColors.primary,
            ),
            title: const Text(
              '24/7 Traveler Support',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Chat with concierge or view FAQs',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.muted,
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Support chat is available 24/7 via support@vesspay.com.',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
