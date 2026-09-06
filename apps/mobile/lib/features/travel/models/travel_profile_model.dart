/// Travel Profile model per VESSPAY_BLUEPRINT.md Section 6 & 7
class TravelProfileModel {
  final String id;
  final String userId;
  final String destinationCountry;
  final String destinationCurrency;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TravelProfileModel({
    required this.id,
    required this.userId,
    required this.destinationCountry,
    required this.destinationCurrency,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  /// Readable destination country name
  String get countryName {
    switch (destinationCountry.toUpperCase()) {
      case 'GH':
        return 'Ghana';
      case 'NG':
        return 'Nigeria';
      default:
        return destinationCountry;
    }
  }

  /// Flag emoji for the profile destination
  String get flagEmoji {
    switch (destinationCountry.toUpperCase()) {
      case 'GH':
        return '🇬🇭';
      case 'NG':
        return '🇳🇬';
      default:
        return '🌍';
    }
  }

  /// Formatted headline e.g. "Traveling in 🇬🇭 Ghana"
  String get travelingInDisplay => 'Traveling in $flagEmoji $countryName';

  factory TravelProfileModel.fromJson(Map<String, dynamic> json) {
    return TravelProfileModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      destinationCountry: json['destinationCountry'] as String? ?? '',
      destinationCurrency: json['destinationCurrency'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? false,
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
      'userId': userId,
      'destinationCountry': destinationCountry,
      'destinationCurrency': destinationCurrency,
      'isActive': isActive,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
