import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/kyc_model.dart';
import '../repositories/kyc_repository.dart';

final kycStatusProvider = FutureProvider<KycStatusModel>((ref) async {
  final repository = ref.watch(kycRepositoryProvider);
  return repository.getKycStatus();
});
