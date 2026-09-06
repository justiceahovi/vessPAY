/// Authenticated user profile model
class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? country;
  final String? nationality;
  /// Wallet currency chosen on first sign-on; null until the user picks one.
  final String? primaryCurrency;
  final String? wewireSubcustomerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.country,
    this.nationality,
    this.primaryCurrency,
    this.wewireSubcustomerId,
    this.createdAt,
    this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      country: json['country'] as String?,
      nationality: json['nationality'] as String?,
      primaryCurrency:
          (json['primaryCurrency'] as String?)?.trim().toUpperCase(),
      wewireSubcustomerId: json['wewireSubcustomerId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'country': country,
      'nationality': nationality,
      'primaryCurrency': primaryCurrency,
      'wewireSubcustomerId': wewireSubcustomerId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

/// Authentication response containing the user profile and JWT token
class AuthResponse {
  final UserModel user;
  final String token;

  const AuthResponse({
    required this.user,
    required this.token,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      token: json['token'] as String? ?? '',
    );
  }
}
