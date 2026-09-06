import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../models/destination_model.dart';
import '../models/travel_profile_model.dart';
import '../providers/travel_providers.dart';

abstract class TravelRepository {
  Future<List<DestinationModel>> getDestinations();
  Future<TravelProfileModel?> getCurrentProfile();
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry);
}

class TravelRepositoryImpl implements TravelRepository {
  final ApiClient _apiClient;
  TravelProfileModel? _localTestProfile;

  TravelRepositoryImpl({required ApiClient apiClient}) : _apiClient = apiClient;

  bool get _isFlutterTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<DestinationModel>> getDestinations() async {
    if (_isFlutterTest) {
      return kDefaultDestinations;
    }

    return await _apiClient.get<List<DestinationModel>>(
      '/api/travel/destinations',
      fromJson: (data) {
        if (data is List) {
          return data
              .map((item) =>
                  DestinationModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }

  @override
  Future<TravelProfileModel?> getCurrentProfile() async {
    if (_isFlutterTest) {
      return _localTestProfile;
    }

    return await _apiClient.get<TravelProfileModel?>(
      '/api/travel/current',
      fromJson: (data) {
        if (data == null) return null;
        if (data is Map<String, dynamic>) {
          return TravelProfileModel.fromJson(data);
        }
        return null;
      },
    );
  }

  @override
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry) async {
    if (_isFlutterTest) {
      _localTestProfile = TravelProfileModel(
        id: 'test-profile-1',
        userId: 'test-user-1',
        destinationCountry: destinationCountry,
        destinationCurrency:
            destinationCountry.toUpperCase() == 'GH' ? 'GHS' : 'NGN',
        isActive: true,
      );
      return _localTestProfile!;
    }

    return await _apiClient.put<TravelProfileModel>(
      '/api/travel/current',
      data: {
        'destinationCountry': destinationCountry,
      },
      fromJson: (data) =>
          TravelProfileModel.fromJson(data as Map<String, dynamic>),
    );
  }
}

/// Riverpod provider for TravelRepository
final travelRepositoryProvider = Provider<TravelRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TravelRepositoryImpl(apiClient: apiClient);
});
