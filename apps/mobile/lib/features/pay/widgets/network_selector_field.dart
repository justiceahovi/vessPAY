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

  /// How many leading options are "pinned" -- shown above the rest under
  /// [pinnedLabel]. Used for the Nigerian wallets, which are ordinary bank
  /// entries but are what most people are actually looking for.
  final int pinnedCount;
  final String pinnedLabel;

  /// Swaps the dropdown for a searchable sheet. Defaults to true.
  final bool searchable;

  const NetworkSelectorField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.autoDetected = false,
    this.pinnedCount = 0,
    this.pinnedLabel = '',
    this.searchable = true,
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
        if (searchable)
          _SearchableNetworkField(
            label: label,
            selected: selected,
            options: options,
            pinnedCount: pinnedCount,
            pinnedLabel: pinnedLabel,
            onChanged: onChanged,
          )
        else
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

/// The searchable variant: a tappable field that opens a filterable sheet.
///
/// Filters on both the institution name and its code / sort code / badge, so
/// someone who knows the code can enter it directly.
class _SearchableNetworkField extends StatelessWidget {
  final String label;
  final String selected;
  final List<NetworkOption> options;
  final int pinnedCount;
  final String pinnedLabel;
  final ValueChanged<String> onChanged;

  const _SearchableNetworkField({
    required this.label,
    required this.selected,
    required this.options,
    required this.pinnedCount,
    required this.pinnedLabel,
    required this.onChanged,
  });

  NetworkOption? get _selectedOption {
    for (final o in options) {
      if (o.value == selected) return o;
    }
    return options.isNotEmpty ? options.first : null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NetworkPickerSheet(
        label: label,
        options: options,
        selected: selected,
        pinnedCount: pinnedCount,
        pinnedLabel: pinnedLabel,
      ),
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final option = _selectedOption;
    final isBank = label.toLowerCase().contains('bank');

    return InkWell(
      key: const Key('pay_network_dropdown'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openPicker(context),
      child: Container(
        key: const Key('pay_network_search_field'),
        child: InputDecorator(
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: _fieldBorder(AppColors.hairline, 1),
            enabledBorder: _fieldBorder(AppColors.hairline, 1),
            focusedBorder: _fieldBorder(AppColors.primary, 1.5),
            suffixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ),
          child: option == null
              ? Text(
                  isBank ? 'Select a bank' : 'Select a network',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.muted,
                  ),
                )
              : _OptionRow(option: option),
        ),
      ),
    );
  }
}

OutlineInputBorder _fieldBorder(Color color, double width) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );

class _NetworkPickerSheet extends StatefulWidget {
  final String label;
  final List<NetworkOption> options;
  final String selected;
  final int pinnedCount;
  final String pinnedLabel;

  const _NetworkPickerSheet({
    required this.label,
    required this.options,
    required this.selected,
    required this.pinnedCount,
    required this.pinnedLabel,
  });

  @override
  State<_NetworkPickerSheet> createState() => _NetworkPickerSheetState();
}

class _NetworkPickerSheetState extends State<_NetworkPickerSheet> {
  String _query = '';

  bool _matches(NetworkOption o) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return o.displayName.toLowerCase().contains(q) ||
        o.value.toLowerCase().contains(q) ||
        o.badge.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final isBank = widget.label.toLowerCase().contains('bank');
    final pinned = widget.options
        .take(widget.pinnedCount)
        .where(_matches)
        .toList();
    final rest =
        widget.options.skip(widget.pinnedCount).where(_matches).toList();
    final allLabel = pinned.isNotEmpty
        ? (isBank ? 'All banks' : 'Other networks')
        : (isBank ? 'All banks' : 'Networks');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              key: const Key('pay_network_search_input'),
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: isBank ? 'Search bank or code' : 'Search network or code',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.muted, size: 20),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: _fieldBorder(AppColors.hairline, 1),
                enabledBorder: _fieldBorder(AppColors.hairline, 1),
                focusedBorder: _fieldBorder(AppColors.primary, 1.5),
              ),
            ),
          ),
          Flexible(
            child: (pinned.isEmpty && rest.isEmpty)
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        isBank
                            ? 'No bank matches "$_query"'
                            : 'No network matches "$_query"',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _sectionHeader(widget.pinnedLabel),
                        ...pinned.map(_tile),
                      ],
                      if (rest.isNotEmpty) ...[
                        _sectionHeader(allLabel),
                        ...rest.map(_tile),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _tile(NetworkOption option) {
    final isSelected = option.value == widget.selected;
    return ListTile(
      key: option.itemKey,
      dense: true,
      title: _OptionRow(option: option),
      subtitle: (option.badge.isEmpty && option.value.isNotEmpty)
          ? Text(
              option.value,
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.muted),
            )
          : null,
      trailing: isSelected
          ? const Icon(Icons.check_rounded,
              color: AppColors.primary, size: 20)
          : null,
      onTap: () => Navigator.of(context).pop(option.value),
    );
  }
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
