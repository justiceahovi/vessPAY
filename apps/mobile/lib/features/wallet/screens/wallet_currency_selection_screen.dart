import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../models/wallet_currency_model.dart';
import '../providers/currency_providers.dart';

/// Wallet Currency Selection ("What currency is your wallet in?")
///
/// Shown once on first sign-on, before travel mode setup. The choice is stored
/// on the user's account, so returning users skip straight past this screen.
/// Also reachable later from the wallet to switch currency.
class WalletCurrencySelectionScreen extends ConsumerStatefulWidget {
  /// Where to go after a successful choice. Defaults to travel mode setup,
  /// which is the next step of first-run onboarding.
  final String nextRoute;

  final bool isBottomSheet;

  const WalletCurrencySelectionScreen({
    super.key,
    this.nextRoute = AppRoutes.travelModeSetup,
    this.isBottomSheet = false,
  });

  /// Presents currency selection as a bottom sheet, for changing it later on.
  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) =>
          const WalletCurrencySelectionScreen(isBottomSheet: true),
    );
  }

  @override
  ConsumerState<WalletCurrencySelectionScreen> createState() =>
      _WalletCurrencySelectionScreenState();
}

class _WalletCurrencySelectionScreenState
    extends ConsumerState<WalletCurrencySelectionScreen> {
  String? _selectedCurrency;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Preselect USD so the primary action is never dead on arrival.
    _selectedCurrency = kDefaultWalletCurrency;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final existing = ref.read(walletCurrencyProvider).valueOrNull;
      if (existing != null && existing.isNotEmpty && mounted) {
        setState(() {
          _selectedCurrency = existing;
        });
      }
    });
  }

  Future<void> _handleConfirmCurrency() async {
    final currency = _selectedCurrency ?? kDefaultWalletCurrency;

    setState(() {
      _isSubmitting = true;
    });

    var saved = true;
    try {
      await ref.read(walletCurrencyProvider.notifier).select(currency);
    } catch (_) {
      // The choice is held locally; surface it but let the user continue so a
      // flaky connection cannot trap them in onboarding.
      saved = false;
    }

    if (!mounted) return;

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved on this device. We will sync your wallet currency shortly.',
          ),
        ),
      );
    }

    if (widget.isBottomSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(widget.nextRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies =
        ref.watch(supportedWalletCurrenciesProvider).valueOrNull ??
            kDefaultWalletCurrencies;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isBottomSheet) ...[
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
                Text(
                  'What currency is your wallet in?',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: widget.isBottomSheet ? 22 : 28,
                    letterSpacing: -0.4,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deposits land in this currency and your balance is held in it. '
                  'You can change it later from your wallet.',
                  style: GoogleFonts.inter(
                    color: AppColors.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Column(
                  children: currencies.map((currency) {
                    final isSelected = _selectedCurrency?.toUpperCase() ==
                        currency.code.toUpperCase();

                    return _CurrencyCard(
                      key: Key(
                          'wallet_currency_card_${currency.code.toLowerCase()}'),
                      currency: currency,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedCurrency = currency.code;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
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
              key: const Key('wallet_currency_confirm_button'),
              onPressed: _isSubmitting ? null : _handleConfirmCurrency,
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
                      'Open my ${_selectedCurrency ?? kDefaultWalletCurrency} wallet',
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
        key: const Key('wallet_currency_selection_screen'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: content,
      );
    }

    return Scaffold(
      key: const Key('wallet_currency_selection_screen'),
      backgroundColor: AppColors.canvas,
      body: SafeArea(child: content),
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
            'WALLET CURRENCY',
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

/// Selection card for a single wallet currency
class _CurrencyCard extends StatelessWidget {
  final WalletCurrencyModel currency;
  final bool isSelected;
  final VoidCallback onTap;

  const _CurrencyCard({
    super.key,
    required this.currency,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [
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
                      currency.flag,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              currency.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.hairline,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${currency.symbol} ${currency.code}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? AppColors.primaryActive
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currency.fundingRail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.hairlineSoft,
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
