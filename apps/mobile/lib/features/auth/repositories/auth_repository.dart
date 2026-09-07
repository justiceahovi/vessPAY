import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/token_storage.dart';
import '../models/user_model.dart';

abstract class AuthRepository {
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  });

  Future<UserModel> login({
    required String email,
    required String password,
  });

  Future<UserModel> getProfile();

  /// Updates a subset of the current user's own profile. Only non-null
  /// fields are sent; `country`/`nationality` are rejected by the backend
  /// once identity verification is approved.
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
    String? country,
    String? nationality,
  });

  Future<void> logout();
}

class AuthRepositoryImpl implements AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthRepositoryImpl({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  @override
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  }) async {
    final response = await _apiClient.post<AuthResponse>(
      '/api/auth/register',
      data: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'country': country,
        'nationality': nationality,
      },
      fromJson: (data) => AuthResponse.fromJson(data as Map<String, dynamic>),
    );

    if (response.token.isNotEmpty) {
      await _tokenStorage.saveToken(response.token);
    }

    return response.user;
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post<AuthResponse>(
      '/api/auth/login',
      data: {
        'email': email,
        'password': password,
      },
      fromJson: (data) => AuthResponse.fromJson(data as Map<String, dynamic>),
    );

    if (response.token.isNotEmpty) {
      await _tokenStorage.saveToken(response.token);
    }

    return response.user;
  }

  @override
  Future<UserModel> getProfile() async {
    return await _apiClient.get<UserModel>(
      '/api/auth/me',
      fromJson: (data) {
        final map = data as Map<String, dynamic>;
        return UserModel.fromJson(map['user'] as Map<String, dynamic>);
      },
    );
  }

  @override
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
    String? country,
    String? nationality,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName;
    if (lastName != null) data['lastName'] = lastName;
    if (country != null) data['country'] = country;
    if (nationality != null) data['nationality'] = nationality;

    return await _apiClient.put<UserModel>(
      '/api/auth/me',
      data: data,
      fromJson: (data) {
        final map = data as Map<String, dynamic>;
        return UserModel.fromJson(map['user'] as Map<String, dynamic>);
      },
    );
  }

  @override
  Future<void> logout() async {
    await _tokenStorage.deleteToken();
  }
}

/// Riverpod provider for AuthRepository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthRepositoryImpl(
    apiClient: apiClient,
    tokenStorage: tokenStorage,
  );
});
