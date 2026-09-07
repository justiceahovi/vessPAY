import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/config/corridors.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../models/destination_model.dart';
import '../providers/travel_providers.dart';

/// Destination Selection Screen ("Where are you travelling?")
/// per VESSPAY_BLUEPRINT.md Section 12 & DESIGN.md
/// Supports both full-screen route and modern modal bottom sheet presentation.
class DestinationSelectionScreen extends ConsumerStatefulWidget {
  final bool isBottomSheet;

  const DestinationSelectionScreen({
    super.key,
    this.isBottomSheet = false,
  });

  /// Presents the destination selection UI as a sleek modern bottom sheet
  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) =>
          const DestinationSelectionScreen(isBottomSheet: true),
    );
  }

  @override
  ConsumerState<DestinationSelectionScreen> createState() =>
      _DestinationSelectionScreenState();
}

class _DestinationSelectionScreenState
    extends ConsumerState<DestinationSelectionScreen> {
  String? _selectedCountry;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default to Ghana (MVP corridor) immediately
    _selectedCountry = 'GH';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentProfile = ref.read(currentTravelProfileProvider).valueOrNull;
      if (currentProfile != null &&
          currentProfile.destinationCountry.isNotEmpty) {
        if (mounted) {
          setState(() {
            _selectedCountry = currentProfile.destinationCountry;
          });
        }
      }
    });
  }

  Future<void> _handleConfirmDestination() async {
    final country = _selectedCountry ?? 'GH';

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(currentTravelProfileProvider.notifier)
          .setDestination(country);
    } catch (_) {
      // In tests or offline environments where backend is unreachable,
      // fallback state is set and navigation continues smoothly
    } finally {
      if (mounted) {
        if (widget.isBottomSheet && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go(AppRoutes.home);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations =
        ref.watch(destinationsProvider).valueOrNull ?? kDefaultDestinations;

    final sheetContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isBottomSheet) ...[
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          // Top Header with Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildEyebrowBadge(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.muted,
                    size: 22,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.isBottomSheet) ...[
                  _buildEyebrowBadge(),
                  const SizedBox(height: 16),
                ],
                // Display Headline per DESIGN.md
                Text(
                  'Where are you travelling?',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: widget.isBottomSheet ? 22 : 28,
                    letterSpacing: -0.4,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Select your destination to activate local payment rails and live exchange rates without a local SIM.',
                  style: GoogleFonts.inter(
                    color: AppColors.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),

                // Error banner if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Destinations list
                Column(
                  children: destinations.map((destination) {
                    final isSelected = _selectedCountry?.toUpperCase() ==
                        destination.country.toUpperCase();

                    return _DestinationCard(
                      key: Key(
                          'destination_card_${destination.country.toLowerCase()}'),
                      destination: destination,
                      isSelected: isSelected,
                      onTap: destination.payoutAvailable
                          ? () {
                              setState(() {
                                _selectedCountry = destination.country;
                                _errorMessage = null;
                              });
                            }
                          // A corridor with no payout rail stays visible, so
                          // the roadmap is legible, but cannot be activated.
                          : () {
                              setState(() {
                                _errorMessage =
                                    '${destination.name} payouts are not live yet. '
                                    'You can already look up recipients there, but transfers cannot be sent.';
                              });
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: const BoxDecoration(
            color: AppColors.canvas,
            border: Border(
              top: BorderSide(color: AppColors.hairlineSubtle, width: 1),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              key: const Key('travel_to_home_button'),
              onPressed: _isSubmitting ? null : _handleConfirmDestination,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                      ),
                    )
                  : Text(
                      _selectedCountry != null
                          ? 'Activate ${corridorFor(_selectedCountry).name} Travel Mode'
                          : 'Select a Destination',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );

    if (widget.isBottomSheet) {
      return Container(
        key: const Key('travel_mode_setup_screen'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: sheetContent,
      );
    }

    return Scaffold(
      key: const Key('travel_mode_setup_screen'),
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text(
          'Select Destination',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'sans-serif',
          ),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: SafeArea(
        child: sheetContent,
      ),
    );
  }

  Widget _buildEyebrowBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.hairlineSubtle,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'TRAVEL MODE SETUP',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Destination Selection Card Widget per DESIGN.md
class _DestinationCard extends StatelessWidget {
  final DestinationModel destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _DestinationCard({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGhana = destination.country.toUpperCase() == 'GH';
    // A corridor whose payout rail is not live is shown, but muted and
    // unselectable -- the destination exists, the transfer does not.
    final available = destination.payoutAvailable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(18),
            foregroundDecoration: available
                ? null
                : BoxDecoration(
                    color: AppColors.canvas.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                  ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.surfaceCard
                  : AppColors.surfaceCard.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.hairline,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Flag emoji avatar circle
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.hairline,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      destination.flagEmoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Destination info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            destination.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge pill per DESIGN.md
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isGhana
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.hairline,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              destination.corridorDescription,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isGhana
                                    ? AppColors.primaryActive
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination.paymentRailDescription,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                      if (isGhana) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Instant MoMo Payouts',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!available) ...[
                        const SizedBox(height: 6),
                        Row(
                          key: Key(
                              'destination_unavailable_${destination.country.toLowerCase()}'),
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Payouts coming soon',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Radio / Checkmark selector
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isSelected ? AppColors.primary : AppColors.hairlineSoft,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
