import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'recent_activity_provider.dart';

/// A person this user has paid before, offered as a one-tap shortcut at the
/// top of the Pay Anyone form.
class RecentRecipient {
  final String name;
  final String phone;
  final String network;

  const RecentRecipient({
    required this.name,
    required this.phone,
    required this.network,
  });

  /// Initials for the avatar chip, e.g. "Ama Serwaa" -> "AS".
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// First name only, so the chip stays narrow.
  String get shortName => name.trim().split(RegExp(r'\s+')).first;
}

/// Auto-generated stand-in names ("Recipient 0241234567") are not real names
/// and must never be shown as one.
bool _isPlaceholderName(String? name) {
  if (name == null) return true;
  final trimmed = name.trim();
  if (trimmed.length < 2) return true;
  return RegExp(r'^Recipient\s+\d+$', caseSensitive: false).hasMatch(trimmed);
}

/// The most recent distinct people this user has paid, newest first.
/// Derived from payment history, so it needs no extra endpoint.
final recentRecipientsProvider = Provider<List<RecentRecipient>>((ref) {
  final transactions = ref.watch(userTransactionsProvider).valueOrNull ?? [];

  final byPhone = <String, RecentRecipient>{};
  for (final tx in transactions) {
    if (tx.type != 'payout') continue;

    final phone = tx.recipientPhone?.trim() ?? '';
    if (phone.isEmpty) continue;
    if (_isPlaceholderName(tx.recipientName)) continue;
    if (byPhone.containsKey(phone)) continue;

    byPhone[phone] = RecentRecipient(
      name: tx.recipientName!.trim(),
      phone: phone,
      network: tx.network?.trim() ?? '',
    );

    if (byPhone.length == 5) break;
  }

  return byPhone.values.toList();
});
