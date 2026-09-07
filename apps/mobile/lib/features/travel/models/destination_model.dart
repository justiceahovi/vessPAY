import '../../../core/config/corridors.dart';

/// Supported travel destination model per VESSPAY_BLUEPRINT.md Section 7
class DestinationModel {
  final String country;
  final String name;
  final String currency;

  /// Whether a payout can actually be sent to this corridor today. The server
  /// is the authority; older builds and offline fallbacks read it from the
  /// bundled corridor table instead.
  final bool payoutAvailable;

  /// Channels the corridor can be paid over: 'MOBILE_MONEY' and/or 'BANK'.
  final List<String> channels;

  const DestinationModel({
    required this.country,
    required this.name,
    required this.currency,
    this.payoutAvailable = true,
    this.channels = const ['MOBILE_MONEY', 'BANK'],
  });

  /// The bundled corridor for this destination, for anything the API does not
  /// carry (dial code, account number rules, MSISDN pattern).
  Corridor get corridor => corridorFor(country);

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
        // Nigeria has no mobile money rail: OPay, PalmPay, Moniepoint and Kuda
        // are all reached as banks, by account number.
        return 'Bank transfer & wallets (OPay, PalmPay, Kuda)';
      default:
        return 'Local Payment Rails';
    }
  }

  /// Currency corridor description
  String get corridorDescription => 'USD → $currency';

  factory DestinationModel.fromJson(Map<String, dynamic> json) {
    final country = json['country'] as String? ?? '';
    // A server that predates these fields still describes a live corridor, so
    // fall back to the bundled table rather than assuming a rail is dead.
    final fallback = corridorFor(country);
    return DestinationModel(
      country: country,
      name: json['name'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      payoutAvailable:
          json['payoutAvailable'] as bool? ?? fallback.payoutAvailable,
      channels: (json['channels'] as List?)?.map((c) => c.toString()).toList() ??
          fallback.channels,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'name': name,
      'currency': currency,
      'payoutAvailable': payoutAvailable,
      'channels': channels,
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
