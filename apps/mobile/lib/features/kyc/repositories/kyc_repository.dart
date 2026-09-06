import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../models/kyc_model.dart';

abstract class KycRepository {
  Future<KycLinkModel> getKycLink();
  Future<KycStatusModel> getKycStatus();

  /// Demo-only shortcut: asks the backend to submit the canned KYC dossier for
  /// this user. Only offered when [KycStatusModel.demoKycAvailable] is true.
  Future<KycStatusModel> submitDemoKyc();
}

class ApiKycRepository implements KycRepository {
  final ApiClient _apiClient;

  ApiKycRepository(this._apiClient);

  @override
  Future<KycLinkModel> getKycLink() async {
    return _apiClient.get(
      '/api/kyc/link',
      fromJson: (data) => KycLinkModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<KycStatusModel> getKycStatus() async {
    return _apiClient.get(
      '/api/kyc/status',
      fromJson: (data) => KycStatusModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<KycStatusModel> submitDemoKyc() async {
    return _apiClient.post(
      '/api/kyc/demo-submit',
      fromJson: (data) => KycStatusModel.fromJson(data as Map<String, dynamic>),
    );
  }
}

final kycRepositoryProvider = Provider<KycRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiKycRepository(apiClient);
});
