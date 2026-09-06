import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/recent_recipients_provider.dart';

/// One-tap shortcuts for people this user has paid before. Travellers pay the
/// same handful of people repeatedly, so this is the shortest path through the
/// whole flow: tap a chip, type an amount, confirm.
class RecentRecipientsRow extends ConsumerWidget {
  final ValueChanged<RecentRecipient> onSelected;
  final String? selectedPhone;

  const RecentRecipientsRow({
    super.key,
    required this.onSelected,
    this.selectedPhone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipients = ref.watch(recentRecipientsProvider);
    if (recipients.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('pay_recent_recipients'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay again',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.bodyStrong,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: recipients.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final recipient = recipients[index];
              final isSelected = selectedPhone != null &&
                  selectedPhone!.replaceAll(RegExp(r'\D'), '') ==
                      recipient.phone.replaceAll(RegExp(r'\D'), '');

              return _RecipientChip(
                chipKey: Key('pay_recent_recipient_${recipient.phone}'),
                recipient: recipient,
                isSelected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(recipient);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _RecipientChip extends StatelessWidget {
  final Key chipKey;
  final RecentRecipient recipient;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecipientChip({
    required this.chipKey,
    required this.recipient,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: chipKey,
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 5, right: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.hairlineSubtle,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  recipient.initials,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                recipient.shortName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
