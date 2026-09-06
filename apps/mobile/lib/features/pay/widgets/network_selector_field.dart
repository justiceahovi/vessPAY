import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/payout_institution_model.dart';

/// A selectable payout network (mobile money operator or bank).
class NetworkOption {
  final String value;
  final String displayName;
  final String badge;
  final Color badgeColor;
  final Color badgeTextColor;
  final IconData? icon;

  const NetworkOption({
    required this.value,
    required this.displayName,
    this.badge = '',
    this.badgeColor = AppColors.surfaceSoft,
    this.badgeTextColor = AppColors.ink,
    this.icon,
  });

  Key get itemKey =>
      Key('pay_network_${value.toLowerCase().replaceAll(' ', '_')}');

  /// Builds an option from a payout institution served by GET /api/banks.
  factory NetworkOption.fromInstitution(PayoutInstitutionModel institution) {
    return NetworkOption(
      value: institution.code,
      displayName: institution.displayName,
      icon: institution.isBank ? Icons.account_balance : Icons.phone_android,
    );
  }
}

const List<NetworkOption> kGhanaMoMoOptions = [
  NetworkOption(
    value: 'MTN',
    displayName: 'MTN Mobile Money',
    badge: 'MTN',
    badgeColor: Color(0xFFFFCC00),
    badgeTextColor: Color(0xFF8A6D00),
  ),
  NetworkOption(
    value: 'Telecel',
    displayName: 'Telecel Cash',
    badge: 'TC',
    badgeColor: Color(0xFFE60000),
    badgeTextColor: Color(0xFFCC0000),
  ),
  NetworkOption(
    value: 'AirtelTigo',
    displayName: 'AirtelTigo Money',
    badge: 'AT',
    badgeColor: Color(0xFF0033A0),
    badgeTextColor: Color(0xFF0033A0),
  ),
];

/// Network picker with an "Auto-detected" hint when the operator was inferred
/// from the number the user typed. The value stays fully overridable.
class NetworkSelectorField extends StatelessWidget {
  final String label;
  final String value;
  final List<NetworkOption> options;
  final ValueChanged<String> onChanged;
  final bool autoDetected;

  const NetworkSelectorField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.autoDetected = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = options.any((o) => o.value == value)
        ? value
        : (options.isNotEmpty ? options.first.value : value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyStrong,
                letterSpacing: -0.1,
              ),
            ),
            if (autoDetected) ...[
              const SizedBox(width: 8),
              Container(
                key: const Key('pay_network_auto_badge'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 10, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Auto-detected',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('pay_network_dropdown'),
          initialValue: selected,
          isExpanded: true,
          dropdownColor: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.muted,
            size: 22,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: _border(AppColors.hairline, 1),
            enabledBorder: _border(AppColors.hairline, 1),
            focusedBorder: _border(AppColors.primary, 1.5),
          ),
          selectedItemBuilder: (context) =>
              options.map((option) => _OptionRow(option: option)).toList(),
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  key: option.itemKey,
                  value: option.value,
                  child: _OptionRow(option: option),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            HapticFeedback.selectionClick();
            onChanged(val);
          },
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
}

class _OptionRow extends StatelessWidget {
  final NetworkOption option;

  const _OptionRow({required this.option});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (option.badge.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: option.badgeColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: option.badgeColor.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              option.badge,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: option.badgeTextColor,
                letterSpacing: -0.3,
              ),
            ),
          )
        else if (option.icon != null)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(option.icon, size: 16, color: AppColors.ink),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            option.displayName,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
