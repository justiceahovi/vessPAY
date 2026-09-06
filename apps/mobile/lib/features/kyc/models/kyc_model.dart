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

class KycStatusModel {
  final String onboardingStatus;
  final String enhancedKycStatus;

  KycStatusModel({
    required this.onboardingStatus,
    required this.enhancedKycStatus,
  });

  factory KycStatusModel.fromJson(Map<String, dynamic> json) {
    return KycStatusModel(
      onboardingStatus: json['onboardingStatus'] as String? ?? 'DRAFT',
      enhancedKycStatus: json['enhancedKycStatus'] as String? ?? 'NOT_STARTED',
    );
  }

  bool get isApproved => onboardingStatus.toUpperCase() == 'APPROVED';
  bool get isInReview => onboardingStatus.toUpperCase() == 'IN_REVIEW';
  bool get isPending => !isApproved && !isInReview;

  String get displayStatus {
    if (isApproved) return 'Verified';
    if (isInReview) return 'In Review';
    return 'Action Required';
  }
}
