import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_client.dart';
import 'package:vesspay/core/config/app_config.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';

void main() {
  group('Live Travel Endpoints Integration (T2.1 & T2.2 Acceptance Criteria)', () {
    late TokenStorage storage;
    late ApiClient client;

    setUp(() {
      storage = InMemoryTokenStorage();
      AppConfig.setBaseUrl('http://localhost:3000');
      client = ApiClient(tokenStorage: storage);
    });

    test(
        'Live flow: Fetch destinations, initially no profile, set Ghana as current, fetch it back',
        () async {
      final testEmail =
          'travel-user-${DateTime.now().millisecondsSinceEpoch}@example.com';

      // 1. Register a new user on live backend
      final registerRes = await client.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'firstName': 'Traveler',
          'lastName': 'Live',
          'email': testEmail,
          'password': 'Password123!',
          'country': 'GB',
          'nationality': 'British',
        },
      );

      final token = registerRes['token'] as String;
      expect(token, isNotEmpty);
      await client.saveToken(token);

      // 2. Fetch destinations
      final destinationsData =
          await client.get<List<dynamic>>('/api/travel/destinations');
      expect(destinationsData, isNotEmpty);

      final destinations = destinationsData
          .map((d) => DestinationModel.fromJson(d as Map<String, dynamic>))
          .toList();

      final ghana = destinations.firstWhere((d) => d.country == 'GH');
      expect(ghana.name, equals('Ghana'));
      expect(ghana.currency, equals('GHS'));

      final nigeria = destinations.firstWhere((d) => d.country == 'NG');
      expect(nigeria.name, equals('Nigeria'));
      expect(nigeria.currency, equals('NGN'));

      // 3. See no current profile initially
      final initialProfile =
          await client.get<dynamic>('/api/travel/current');
      expect(initialProfile, isNull);

      // 4. Set Ghana as current destination
      final setGhRes = await client.put<Map<String, dynamic>>(
        '/api/travel/current',
        data: {'destinationCountry': 'GH'},
      );

      final ghProfile = TravelProfileModel.fromJson(setGhRes);
      expect(ghProfile.destinationCountry, equals('GH'));
      expect(ghProfile.destinationCurrency, equals('GHS'));
      expect(ghProfile.isActive, isTrue);

      // 5. Fetch it back correctly from server
      final fetchGhRes =
          await client.get<Map<String, dynamic>>('/api/travel/current');
      final fetchedProfile = TravelProfileModel.fromJson(fetchGhRes);
      expect(fetchedProfile.destinationCountry, equals('GH'));
      expect(fetchedProfile.destinationCurrency, equals('GHS'));
      expect(fetchedProfile.id, equals(ghProfile.id));
      expect(fetchedProfile.travelingInDisplay, equals('Traveling in 🇬🇭 Ghana'));

      // 6. Switch to Nigeria
      final setNgRes = await client.put<Map<String, dynamic>>(
        '/api/travel/current',
        data: {'destinationCountry': 'NG'},
      );
      final ngProfile = TravelProfileModel.fromJson(setNgRes);
      expect(ngProfile.destinationCountry, equals('NG'));
      expect(ngProfile.destinationCurrency, equals('NGN'));

      // 7. Verify Nigeria fetched back
      final fetchNgRes =
          await client.get<Map<String, dynamic>>('/api/travel/current');
      final fetchedNgProfile = TravelProfileModel.fromJson(fetchNgRes);
      expect(fetchedNgProfile.destinationCountry, equals('NG'));
      expect(fetchedNgProfile.travelingInDisplay, equals('Traveling in 🇳🇬 Nigeria'));
    });
  });
}
