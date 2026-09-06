import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/kyc_model.dart';
import '../providers/kyc_providers.dart';
import '../repositories/kyc_repository.dart';

class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  bool _isLaunching = false;
  bool _isSubmittingDemo = false;
  String? _errorMessage;

  /// Demo shortcut: submits the canned KYC dossier for this user. Registration
  /// no longer does this silently, so a human has to ask for it here.
  Future<void> _submitDemoKyc() async {
    setState(() {
      _isSubmittingDemo = true;
      _errorMessage = null;
    });

    try {
      await ref.read(kycRepositoryProvider).submitDemoKyc();
      ref.invalidate(kycStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Demo KYC submitted. Approval usually lands within a few minutes — '
              'tap Check Verification Status to refresh.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingDemo = false;
        });
      }
    }
  }

  Future<void> _launchHostedKyc() async {
    setState(() {
      _isLaunching = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(kycRepositoryProvider);
      final linkModel = await repository.getKycLink();

      if (linkModel.url.isEmpty) {
        throw Exception('KYC verification portal URL not available');
      }

      final uri = Uri.parse(linkModel.url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('Could not open verification link: ${linkModel.url}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(kycStatusProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Identity Verification',
          style: TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.canvas,
          onRefresh: () async {
            ref.invalidate(kycStatusProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header badge & title
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'WeWire Identity Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Copernicus',
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _needsEnhanced(statusAsync)
                        ? 'Your identity is verified. Enhanced verification is the second step WeWire requires before a deposit account can be issued to you.'
                        : 'Complete your automated identity verification via WeWire’s licensed compliance portal before sending payouts.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 14,
                      color: AppColors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Live status card
                statusAsync.when(
                  data: (status) => _buildStatusCard(status),
                  loading: () => Container(
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  error: (err, _) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Status check unavailable right now',
                            style: TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Error message if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 13,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // What to expect box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairlineSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What you will need:',
                        style: TextStyle(
                          fontFamily: 'StyreneB',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.bodyStrong,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_needsEnhanced(statusAsync)) ...[
                        _buildCheckItem('Government ID and proof of address'),
                        const SizedBox(height: 6),
                        _buildCheckItem('Source of funds and occupation details'),
                        const SizedBox(height: 6),
                        _buildCheckItem(
                            'Unlocks a deposit account so you can add money'),
                      ] else ...[
                        _buildCheckItem('Government ID (Passport, National ID, or Driver\'s License)'),
                        const SizedBox(height: 6),
                        _buildCheckItem('Quick selfie / liveness check via browser camera'),
                        const SizedBox(height: 6),
                        _buildCheckItem('Takes under 2 minutes with automated review'),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Primary CTA: Launch WeWire KYC
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('launch_kyc_button'),
                    onPressed: _isLaunching ? null : _launchHostedKyc,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: AppColors.primaryDisabled,
                    ),
                    child: _isLaunching
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _needsEnhanced(statusAsync)
                                    ? 'Start Enhanced Verification'
                                    : 'Launch Verification Portal',
                                style: TextStyle(
                                  fontFamily: 'StyreneB',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.open_in_new, size: 18),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Secondary CTA: Refresh status
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    key: const Key('refresh_kyc_button'),
                    onPressed: () => ref.invalidate(kycStatusProvider),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.bodyStrong,
                      side: const BorderSide(color: AppColors.hairline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Check Verification Status',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                // Demo-only shortcut, hidden unless the backend offers it and
                // the user is not already verified.
                if (_showDemoKycButton(statusAsync)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      key: const Key('demo_kyc_button'),
                      onPressed: _isSubmittingDemo ? null : _submitDemoKyc,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmittingDemo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.muted,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt_outlined, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Demo: Auto-Submit KYC',
                                  style: TextStyle(
                                    fontFamily: 'StyreneB',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Regulatory footer
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: AppColors.mutedSoft),
                      const SizedBox(width: 6),
                      Text(
                        'Powered by WeWire & SumSub Identity Rails',
                        style: TextStyle(
                          fontFamily: 'StyreneB',
                          fontSize: 12,
                          color: AppColors.mutedSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// True once basic onboarding is approved but WeWire still wants Enhanced Due
  /// Diligence. This is the state that blocks account issuance — and therefore
  /// real deposits — with SUBCUSTOMER_ENHANCED_KYC_REQUIRED.
  bool _needsEnhanced(AsyncValue<KycStatusModel> statusAsync) {
    final status = statusAsync.valueOrNull;
    if (status == null) return false;
    return status.isApproved &&
        !status.isEnhancedApproved &&
        !status.isEnhancedInReview;
  }

  /// The demo shortcut only appears when the backend advertises it and there is
  /// still something to verify.
  bool _showDemoKycButton(AsyncValue<KycStatusModel> statusAsync) {
    final status = statusAsync.valueOrNull;
    return status != null && status.demoKycAvailable && !status.isApproved;
  }

  Widget _buildStatusCard(KycStatusModel status) {
    final isVerified = status.isApproved;
    final isInReview = status.isInReview;
    final isRejected = status.isRejected;

    final badgeColor = isVerified
        ? AppColors.success
        : isInReview
            ? AppColors.accentAmber
            : isRejected
                ? AppColors.error
                : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVerified
                  ? Icons.check_circle_outline
                  : isInReview
                      ? Icons.hourglass_top_outlined
                      : isRejected
                          ? Icons.gpp_bad_outlined
                          : Icons.pending_actions_outlined,
              color: badgeColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Account Status',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status.displayStatus,
                        style: TextStyle(
                          fontFamily: 'StyreneB',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isVerified
                      ? (status.isEnhancedApproved
                          ? 'Identity verified. Payouts and deposits active.'
                          : status.isEnhancedInReview
                              ? 'Identity verified. Enhanced verification in review.'
                              : 'Identity verified. Payout corridors active — enhanced verification still needed for deposits.')
                      : isInReview
                          ? 'Verification in review. You will be notified shortly.'
                          : isRejected
                              ? 'Verification declined. Please re-submit your documents.'
                              : 'Identity verification outstanding.',
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  key: const Key('kyc_tier_row'),
                  children: [
                    const Text(
                      'Verification tier',
                      style: TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      status.tierLabel,
                      key: const Key('kyc_tier_label'),
                      style: const TextStyle(
                        fontFamily: 'StyreneB',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle, size: 16, color: AppColors.accentTeal),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 13,
              color: AppColors.body,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
