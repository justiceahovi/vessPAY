class KycLinkModel {
  final String url;
  final String stage;

  KycLinkModel({
    required this.url,
    required this.stage,
  });

  factory KycLinkModel.fromJson(Map<String, dynamic> json) {
    return KycLinkModel(
      url: json['url'] as String? ?? '',
      stage: json['stage'] as String? ?? 'ONBOARDING',
    );
  }
}

/// Normalised verification state derived from the WeWire `onboardingStatus`.
enum KycVerificationState {
  /// Nothing submitted yet (DRAFT / NOT_STARTED / unknown).
  notStarted,

  /// Documents submitted, compliance review in progress.
  inReview,

  /// Onboarding approved by compliance.
  approved,

  /// Compliance declined the submission — the user must re-submit.
  rejected,
}

class KycStatusModel {
  final String onboardingStatus;
  final String enhancedKycStatus;

  /// Whether the backend is offering the demo auto-submit shortcut. Off in
  /// production, so the demo button never surfaces to real users.
  final bool demoKycAvailable;

  KycStatusModel({
    required this.onboardingStatus,
    required this.enhancedKycStatus,
    this.demoKycAvailable = false,
  });

  factory KycStatusModel.fromJson(Map<String, dynamic> json) {
    return KycStatusModel(
      onboardingStatus: json['onboardingStatus'] as String? ?? 'DRAFT',
      enhancedKycStatus: json['enhancedKycStatus'] as String? ?? 'NOT_STARTED',
      demoKycAvailable: json['demoKycAvailable'] as bool? ?? false,
    );
  }

  static const Set<String> _approvedValues = {
    'APPROVED',
    'VERIFIED',
    'ACTIVE',
    'COMPLETED',
  };

  static const Set<String> _inReviewValues = {
    'IN_REVIEW',
    'PENDING',
    'SUBMITTED',
    'PROCESSING',
  };

  static const Set<String> _rejectedValues = {
    'REJECTED',
    'DECLINED',
    'FAILED',
  };

  String get _onboarding => onboardingStatus.trim().toUpperCase();
  String get _enhanced => enhancedKycStatus.trim().toUpperCase();

  KycVerificationState get state {
    if (_approvedValues.contains(_onboarding)) return KycVerificationState.approved;
    if (_inReviewValues.contains(_onboarding)) return KycVerificationState.inReview;
    if (_rejectedValues.contains(_onboarding)) return KycVerificationState.rejected;
    return KycVerificationState.notStarted;
  }

  bool get isApproved => state == KycVerificationState.approved;
  bool get isInReview => state == KycVerificationState.inReview;
  bool get isRejected => state == KycVerificationState.rejected;
  bool get isPending => !isApproved && !isInReview;

  /// Enhanced (Tier 2+) KYC has been granted.
  bool get isEnhancedApproved =>
      _approvedValues.contains(_enhanced) || _enhanced.startsWith('TIER_');

  /// Enhanced (Tier 2+) KYC is submitted and awaiting a compliance decision.
  bool get isEnhancedInReview => _inReviewValues.contains(_enhanced);

  /// Human readable limits tier: base onboarding grants Tier 1, enhanced KYC
  /// grants the tier reported by WeWire (Tier 2 unless it names a higher one).
  String get tierLabel {
    if (!isApproved) return 'Unverified';
    if (!isEnhancedApproved) return 'Tier 1';
    final match = RegExp(r'TIER_(\d+)').firstMatch(_enhanced);
    return match != null ? 'Tier ${match.group(1)}' : 'Tier 2';
  }

  String get displayStatus {
    switch (state) {
      case KycVerificationState.approved:
        return 'Verified';
      case KycVerificationState.inReview:
        return 'In Review';
      case KycVerificationState.rejected:
        return 'Verification Failed';
      case KycVerificationState.notStarted:
        return 'Action Required';
    }
  }
}
