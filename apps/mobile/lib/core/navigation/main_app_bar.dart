import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/pay/providers/recent_activity_provider.dart';
import '../../features/travel/providers/travel_providers.dart';
import '../../features/travel/screens/destination_selection_screen.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';

/// Provider for the user profile shown in the shared app bar greeting.
final homeUserProfileProvider = FutureProvider((ref) async {
  try {
    return await ref.watch(authRepositoryProvider).getProfile();
  } catch (_) {
    return null;
  }
});

/// Shared app bar for the three bottom-nav destinations: Avatar | Greeting /
/// screen name | Notifications | Help | Country Flag Selector.
///
/// Home, Profile and Transactions all wear it so the header stays put while
/// tabs change; [subtitle] is the only per-screen difference. These are tab
/// destinations, so the bar carries no back button - the bottom nav moves
/// between them.
class MainAppBar extends ConsumerWidget implements PreferredSizeWidget {
  /// Second line under the user's name, naming the current screen.
  final String subtitle;

  /// Optional key for the subtitle, letting a screen keep its title test key.
  final Key? subtitleKey;

  /// Whether tapping the avatar opens Profile. Off on Profile itself.
  final bool avatarOpensProfile;

  const MainAppBar({
    super.key,
    this.subtitle = 'VessPay Home',
    this.subtitleKey,
    this.avatarOpensProfile = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(homeUserProfileProvider).valueOrNull;
    final userName =
        (user != null &&
            (user.firstName.isNotEmpty || user.lastName.isNotEmpty))
        ? '${user.firstName} ${user.lastName}'.trim()
        : 'Hello...';

    final travelProfile = ref.watch(currentTravelProfileProvider).valueOrNull;
    final flagEmoji = travelProfile?.flagEmoji ?? '🇬🇭';

    return AppBar(
      backgroundColor: AppColors.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      // The app bar owns the status bar area, so it carries the dark-icon
      // overlay style.
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      toolbarHeight: 68,
      titleSpacing: 18,
      title: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Row(
          children: [
            // Avatar (Taps for profile & more options)
            _buildAvatar(context),
            const SizedBox(width: 12),

            // User Greeting & screen identifier
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    key: subtitleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),

            // Quick Notification Icon
            _buildCircleAction(
              key: const Key('header_notifications_button'),
              icon: Icons.notifications_none_rounded,
              onTap: () => showNotificationsBottomSheet(context),
            ),
            const SizedBox(width: 8),

            // Quick Help Icon
            _buildCircleAction(
              key: const Key('header_help_button'),
              icon: Icons.help_outline_rounded,
              onTap: () => showHelpBottomSheet(context),
            ),
            const SizedBox(width: 8),

            // Country Flag & Corridor Dropdown
            InkWell(
              onTap: () =>
                  DestinationSelectionScreen.showAsBottomSheet(context),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: AppColors.hairlineSubtle,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(flagEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return InkWell(
      key: const Key('home_avatar_button'),
      onTap: avatarOpensProfile ? () => context.push(AppRoutes.profile) : null,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceTint,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 1.5,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.person_outline_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildCircleAction({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairlineSubtle, width: 1.0),
        ),
        child: Center(child: Icon(icon, size: 19, color: AppColors.ink)),
      ),
    );
  }
}

void showHelpBottomSheet(BuildContext context) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.canvas,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Help & Support',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  '24/7 Traveler Support Chat',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Connect with a live support specialist'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(
                  Icons.help_outline_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'African Corridor FAQs',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Learn about local rails, rates & MoMo'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(
                  Icons.report_problem_outlined,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Report Transaction Issue',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Check transaction ID resolution'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showNotificationsBottomSheet(BuildContext context) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.canvas,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Consumer(
        builder: (context, ref, _) {
          final notifications = ref.watch(dynamicNotificationsProvider);

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notifications',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.muted,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (notifications.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                color: AppColors.muted,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No notifications yet',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    for (int i = 0; i < notifications.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.hairlineSoft),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: notifications[i].iconColor.withValues(
                              alpha: 0.12,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            notifications[i].icon,
                            color: notifications[i].iconColor,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          notifications[i].title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          notifications[i].subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        trailing: Text(
                          notifications[i].time,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
