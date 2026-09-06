import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/travel_providers.dart';
import '../screens/destination_selection_screen.dart';

enum TravelingInVariant {
  /// Compact pill badge ideal for AppBars, navigation headers, or chips
  compact,

  /// Rich card banner ideal for dashboard hero sections
  card,
}

/// A global, reactive "Traveling in 🇬🇭 Ghana" indicator widget per DESIGN.md & T2.3.
/// Automatically listens to `currentTravelProfileProvider` and updates immediately
/// when the user changes destination without requiring an app restart.
class TravelingInIndicator extends ConsumerWidget {
  final TravelingInVariant variant;
  final VoidCallback? onTap;
  final bool showChangeAction;

  const TravelingInIndicator({
    super.key,
    this.variant = TravelingInVariant.card,
    this.onTap,
    this.showChangeAction = true,
  });

  /// Factory constructor for compact pill badge variant
  const TravelingInIndicator.compact({
    super.key,
    this.onTap,
    this.showChangeAction = true,
  }) : variant = TravelingInVariant.compact;

  /// Factory constructor for card banner variant
  const TravelingInIndicator.card({
    super.key,
    this.onTap,
    this.showChangeAction = true,
  }) : variant = TravelingInVariant.card;

  void _navigateToTravelSetup(BuildContext context) {
    if (onTap != null) {
      onTap!();
    } else {
      DestinationSelectionScreen.showAsBottomSheet(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentTravelProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          if (variant == TravelingInVariant.compact) {
            return _buildEmptyCompact(context);
          }
          return _buildEmptyState(context);
        }
        if (variant == TravelingInVariant.compact) {
          return _buildCompactPill(context, profile);
        }
        return _buildCardBanner(context, profile);
      },
      loading: () => variant == TravelingInVariant.compact
          ? _buildLoadingCompact()
          : _buildLoadingCard(),
      error: (err, stack) => _buildErrorState(context),
    );
  }

  Widget _buildCompactPill(BuildContext context, dynamic profile) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('traveling_in_indicator_compact'),
        onTap: () => _navigateToTravelSetup(context),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.travelingInDisplay,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  letterSpacing: 0,
                ),
              ),
              if (showChangeAction) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardBanner(BuildContext context, dynamic profile) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('home_active_corridor_badge'),
        onTap: () => _navigateToTravelSetup(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.hairlineSubtle,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Flag circle container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.hairlineSoft,
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    profile.flagEmoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Corridor details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Traveling in ${profile.flagEmoji} ${profile.countryName}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Active corridor: USD → ${profile.destinationCurrency}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              if (showChangeAction) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceTint,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('traveling_in_indicator_empty'),
        onTap: () => _navigateToTravelSetup(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.public_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No destination selected. Tap to setup.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCompact() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: const Text(
        'Traveling in...',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.flight_takeoff_rounded, size: 20, color: AppColors.muted),
          SizedBox(width: 12),
          Text(
            'Loading travel corridor...',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCompact(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('traveling_in_indicator_empty_compact'),
        onTap: () => _navigateToTravelSetup(context),
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceStrong,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.hairline, width: 1),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public, size: 13, color: AppColors.muted),
              SizedBox(width: 4),
              Text(
                'Set Destination',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    if (variant == TravelingInVariant.compact) {
      return _buildEmptyCompact(context);
    }
    return _buildEmptyState(context);
  }
}
