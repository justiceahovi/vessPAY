import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/corridors.dart';
import '../models/destination_model.dart';
import '../models/travel_profile_model.dart';
import '../repositories/travel_repository.dart';

/// Default supported corridors for instant display & offline resiliency,
/// derived from the bundled corridor table so payout availability cannot drift
/// between this list and the rest of the app.
final List<DestinationModel> kDefaultDestinations = kCorridors
    .map((c) => DestinationModel(
          country: c.country,
          name: c.name,
          currency: c.currency,
          payoutAvailable: c.payoutAvailable,
          channels: c.channels,
        ))
    .toList();

/// Fetches supported destinations from GET /api/travel/destinations
final destinationsProvider =
    FutureProvider<List<DestinationModel>>((ref) async {
  try {
    final repository = ref.watch(travelRepositoryProvider);
    final list = await repository.getDestinations();
    if (list.isNotEmpty) return list;
    return kDefaultDestinations;
  } catch (_) {
    return kDefaultDestinations;
  }
});

/// AsyncNotifier provider managing the current active travel profile state
final currentTravelProfileProvider = AsyncNotifierProvider<
    CurrentTravelProfileNotifier, TravelProfileModel?>(() {
  return CurrentTravelProfileNotifier();
});

class CurrentTravelProfileNotifier
    extends AsyncNotifier<TravelProfileModel?> {
  @override
  Future<TravelProfileModel?> build() async {
    try {
      final repository = ref.watch(travelRepositoryProvider);
      return await repository.getCurrentProfile();
    } catch (_) {
      return null;
    }
  }

  /// Sets destination on the server and updates local provider state
  Future<TravelProfileModel> setDestination(String destinationCountry) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(travelRepositoryProvider);
      final updated = await repository.setCurrentProfile(destinationCountry);
      state = AsyncValue.data(updated);
      return updated;
    } catch (e) {
      // Create a local active profile fallback if offline
      final fallback = TravelProfileModel(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        userId: 'current-user',
        destinationCountry: destinationCountry,
        destinationCurrency:
            destinationCountry.toUpperCase() == 'GH' ? 'GHS' : 'NGN',
        isActive: true,
      );
      state = AsyncValue.data(fallback);
      rethrow;
    }
  }

  /// Refreshes current profile from the backend and returns it, so callers can
  /// act on the saved destination (e.g. skip the destination prompt at login).
  /// Returns null when the user has never set a destination, or when the
  /// profile could not be loaded.
  Future<TravelProfileModel?> refresh() async {
    state = await AsyncValue.guard(() async {
      final repository = ref.read(travelRepositoryProvider);
      return repository.getCurrentProfile();
    });
    return state.valueOrNull;
  }

  /// Drops the cached profile so a signed-out user's destination never leaks
  /// into the next session.
  void clear() {
    state = const AsyncValue.data(null);
  }
}

/// Global provider exposing the active "Traveling in 🇬🇭 Ghana" display string
final travelingInTextProvider = Provider<String>((ref) {
  final profile = ref.watch(currentTravelProfileProvider).valueOrNull;
  if (profile != null) {
    return profile.travelingInDisplay;
  }
  return 'No destination set';
});

/// Global provider exposing the active destination country code ('GH', 'NG') or null
final activeDestinationCountryProvider = Provider<String?>((ref) {
  final profile = ref.watch(currentTravelProfileProvider).valueOrNull;
  return profile?.destinationCountry;
});

/// Global provider exposing the active destination currency ('GHS', 'NGN') or null
final activeDestinationCurrencyProvider = Provider<String?>((ref) {
  final profile = ref.watch(currentTravelProfileProvider).valueOrNull;
  return profile?.destinationCurrency;
});
