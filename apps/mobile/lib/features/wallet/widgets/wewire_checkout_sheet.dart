import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/topup_model.dart';
import '../models/wallet_currency_model.dart';
import '../providers/wallet_providers.dart';

enum TransferRail {
  usDomestic, // US ACH & Fedwire
  swift,      // International SWIFT
}

/// Simplified, mobile-first bank transfer sheet for WeWire deposits.
/// Designed for quick, friction-free copy-pasting of banking credentials.
class WeWireCheckoutSheet extends ConsumerStatefulWidget {
  final TopupResponseModel response;
  final double amount;

  const WeWireCheckoutSheet({
    super.key,
    required this.response,
    required this.amount,
  });

  static Future<void> show(
    BuildContext context, {
    required TopupResponseModel response,
    required double amount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WeWireCheckoutSheet(
        response: response,
        amount: amount,
      ),
    );
  }

  @override
  ConsumerState<WeWireCheckoutSheet> createState() =>
      _WeWireCheckoutSheetState();
}

class _WeWireCheckoutSheetState extends ConsumerState<WeWireCheckoutSheet> {
  TransferRail _selectedRail = TransferRail.usDomestic;
  bool _isProcessing = false;
  late final TextEditingController _senderNameController;
  String? _uploadedReceiptName;

  @override
  void initState() {
    super.initState();
    _senderNameController = TextEditingController(text: 'John Doe');
  }

  @override
  void dispose() {
    _senderNameController.dispose();
    super.dispose();
  }

  void _handlePickReceipt() {
    setState(() {
      _uploadedReceiptName =
          'transfer_receipt_${DateTime.now().millisecondsSinceEpoch % 10000}.pdf';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transfer receipt attached successfully'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleConfirmPayment() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final notifier = ref.read(topupControllerProvider.notifier);
    final success = await notifier
        .simulateWeWireDeposit(widget.response.fundingTransactionId);

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
      if (success) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to confirm deposit. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate clean reference matching WeWire format (e.g. WA08919)
    final cleanRefId = widget.response.checkoutId
        .replaceFirst('chk_ww_', '')
        .replaceAll(RegExp(r'[^0-9A-Z]'), '')
        .toUpperCase();
    final reference = cleanRefId.length >= 6
        ? 'WA${cleanRefId.substring(cleanRefId.length - 5)}'
        : 'WA08919';

    final isUs = _selectedRail == TransferRail.usDomestic;

    // A real issued account replaces the demo rails entirely.
    final details = widget.response.accountDetails;
    final isRealAccount = widget.response.isWeWireBacked &&
        details != null &&
        (details.hasLocalNumbers || details.hasIban);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Icon(
                        Icons.account_balance_outlined,
                        size: 18,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Deposit via Bank Transfer',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('close_checkout_sheet_button'),
                      icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(color: AppColors.hairlineSoft, height: 1),

              // Amount Hero Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                color: AppColors.surfaceSoft,
                child: Column(
                  children: [
                    Text(
                      'Amount to Send',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${resolveWalletCurrency(widget.response.currency).format(widget.amount)} ${widget.response.currency}',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Segmented Rail Switcher (ACH / Wire vs SWIFT).
                    // A real issued account has one set of details and its own
                    // rails, so the switcher only applies to the demo fallback.
                    if (!isRealAccount) Container(
                      height: 40,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.hairlineSoft),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSegmentButton(
                              title: 'US Bank (ACH / Wire)',
                              isSelected: isUs,
                              onTap: () => setState(() => _selectedRail = TransferRail.usDomestic),
                            ),
                          ),
                          Expanded(
                            child: _buildSegmentButton(
                              title: 'International (SWIFT)',
                              isSelected: !isUs,
                              onTap: () => setState(() => _selectedRail = TransferRail.swift),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isRealAccount) const SizedBox(height: 16),

                    // Copyable Account Details Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Column(
                        children: isRealAccount
                            ? _buildIssuedAccountRows(details)
                            : [
                                _buildCopyableRow(
                                  'Bank Name',
                                  isUs
                                      ? 'Evolve Bank & Trust'
                                      : 'Standard Chartered Bank',
                                ),
                                const Divider(
                                    color: AppColors.hairlineSoft, height: 16),
                                _buildCopyableRow(
                                  isUs
                                      ? 'Routing Number (ABA)'
                                      : 'SWIFT / BIC Code',
                                  isUs ? '021000021' : 'SCBLSG22XXX',
                                ),
                                const Divider(
                                    color: AppColors.hairlineSoft, height: 16),
                                _buildCopyableRow(
                                    'Account Number', '0100892209'),
                                const Divider(
                                    color: AppColors.hairlineSoft, height: 16),
                                _buildCopyableRow(
                                    'Account Name', 'WeWire Technologies Inc.'),
                                const Divider(
                                    color: AppColors.hairlineSoft, height: 16),
                                _buildCopyableRow(
                                  'Reference / Memo',
                                  reference,
                                  isHighlighted: true,
                                ),
                              ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Important Reference Note. Only the shared demo account
                    // needs one; an issued virtual account self-attributes.
                    if (!isRealAccount) Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF92400E),
                                  height: 1.35,
                                ),
                                children: [
                                  const TextSpan(text: 'Always include the reference '),
                                  TextSpan(
                                    text: reference,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const TextSpan(
                                    text: ' in your transfer memo so your deposit is credited automatically.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Sender Name Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sender Name',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.hairlineSoft),
                          ),
                          child: TextField(
                            controller: _senderNameController,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: "Name on account you're paying from",
                              hintStyle: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                              prefixIcon: const Icon(
                                Icons.person_outline,
                                size: 18,
                                color: AppColors.muted,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Upload Transfer Receipt
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transfer Receipt (Optional)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          key: const Key('upload_receipt_button'),
                          onTap: _handlePickReceipt,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: _uploadedReceiptName != null
                                  ? AppColors.surfaceGreenTint
                                  : AppColors.surfaceSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _uploadedReceiptName != null
                                    ? AppColors.success.withValues(alpha: 0.4)
                                    : AppColors.hairlineSoft,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _uploadedReceiptName != null
                                      ? Icons.check_circle_rounded
                                      : Icons.upload_file_outlined,
                                  size: 20,
                                  color: _uploadedReceiptName != null
                                      ? AppColors.success
                                      : AppColors.muted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _uploadedReceiptName ?? 'Attach transfer receipt (PDF/PNG)',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _uploadedReceiptName != null
                                          ? AppColors.success
                                          : AppColors.ink,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.canvas,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.hairline),
                                  ),
                                  child: Text(
                                    _uploadedReceiptName != null ? 'Change' : 'Browse',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Action CTA Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('confirm_sandbox_payment_button'),
                        onPressed: _isProcessing ? null : _handleConfirmPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : Text(
                                "I've Made the Deposit",
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          "I'll transfer later",
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.ink : AppColors.muted,
          ),
        ),
      ),
    );
  }

  /// Renders whatever identifiers the issuer actually returned: account plus
  /// sort code and IBAN for GBP/EUR, account plus routing number for USD.
  List<Widget> _buildIssuedAccountRows(TopupAccountDetails d) {
    final rows = <Widget>[];

    void add(String label, String? value, {bool highlight = false}) {
      if (value == null || value.isEmpty) return;
      if (rows.isNotEmpty) {
        rows.add(const Divider(color: AppColors.hairlineSoft, height: 16));
      }
      rows.add(_buildCopyableRow(label, value, isHighlighted: highlight));
    }

    add('Bank Name', d.bankName);
    add('Account Name', d.accountName);
    add('Account Number', d.accountNumber, highlight: true);
    add('Sort Code', d.sortCode);
    add('Routing Number (ABA)', d.routingNumber);
    add('IBAN', d.iban, highlight: d.accountNumber == null);
    add('SWIFT / BIC', d.bic);
    if (d.paymentRails.isNotEmpty) {
      add('Payment Rails', d.paymentRails.join(' · '));
    }
    return rows;
  }

  Widget _buildCopyableRow(
    String label,
    String value, {
    bool isHighlighted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppColors.muted,
          ),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied to clipboard'),
                duration: const Duration(seconds: 1),
                backgroundColor: AppColors.primary,
              ),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: isHighlighted
                ? BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                    color: isHighlighted ? const Color(0xFFB45309) : AppColors.ink,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.copy_outlined,
                  size: 13,
                  color: isHighlighted ? const Color(0xFFB45309) : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
