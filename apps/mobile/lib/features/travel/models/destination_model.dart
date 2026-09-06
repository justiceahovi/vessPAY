/// Supported travel destination model per VESSPAY_BLUEPRINT.md Section 7
class DestinationModel {
  final String country;
  final String name;
  final String currency;

  const DestinationModel({
    required this.country,
    required this.name,
    required this.currency,
  });

  /// Country flag emoji
  String get flagEmoji {
    switch (country.toUpperCase()) {
      case 'GH':
        return '🇬🇭';
      case 'NG':
        return '🇳🇬';
      default:
        return '🌍';
    }
  }

  /// Payment rail description per hackathon corridor specs
  String get paymentRailDescription {
    switch (country.toUpperCase()) {
      case 'GH':
        return 'Mobile Money (MTN, Telecel, AirtelTigo)';
      case 'NG':
        return 'Bank Transfer & Mobile Money';
      default:
        return 'Local Payment Rails';
    }
  }

  /// Currency corridor description
  String get corridorDescription => 'USD → $currency';

  factory DestinationModel.fromJson(Map<String, dynamic> json) {
    return DestinationModel(
      country: json['country'] as String? ?? '',
      name: json['name'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'name': name,
      'currency': currency,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DestinationModel &&
          runtimeType == other.runtimeType &&
          country.toUpperCase() == other.country.toUpperCase();

  @override
  int get hashCode => country.toUpperCase().hashCode;
}
