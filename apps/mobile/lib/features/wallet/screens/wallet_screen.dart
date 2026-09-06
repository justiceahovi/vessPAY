import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../travel/widgets/traveling_in_indicator.dart';
import '../models/wallet_balance_model.dart';
import '../models/wallet_currency_model.dart';
import '../providers/currency_providers.dart';
import '../providers/wallet_providers.dart';
import 'wallet_currency_selection_screen.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(walletBalancesProvider);
    final ghsRate = ref.watch(walletToGhsRateProvider);
    final walletCurrency = ref.watch(activeWalletCurrencyProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          key: const Key('wallet_back_button'),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Travel Wallet',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('wallet_change_currency_button'),
            icon: const Icon(Icons.currency_exchange_rounded,
                size: 21, color: AppColors.ink),
            tooltip: 'Change wallet currency',
            onPressed: () =>
                WalletCurrencySelectionScreen.showAsBottomSheet(context),
          ),
          IconButton(
            key: const Key('wallet_refresh_button'),
            icon: const Icon(Icons.refresh, size: 22, color: AppColors.ink),
            tooltip: 'Refresh balances',
            onPressed: () {
              ref.invalidate(liveExchangeRateProvider);
              ref.invalidate(walletBalancesProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: const Key('wallet_pull_to_refresh'),
          color: AppColors.primary,
          backgroundColor: AppColors.canvas,
          onRefresh: () async {
            ref.invalidate(liveExchangeRateProvider);
            return ref.refresh(walletBalancesProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Traveling in Indicator compact chip
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: TravelingInIndicator.compact(),
                  ),
                ),

                // Live balance card
                balancesAsync.when(
                  data: (balances) {
                    final primaryBalance = balances.firstWhere(
                      (b) => b.currency.toUpperCase() == walletCurrency.code,
                      orElse: () => balances.isNotEmpty
                          ? balances.first
                          : WalletBalanceModel(
                              currency: walletCurrency.code, balance: 0.0),
                    );

                    final walletAmount = primaryBalance.balance;
                    final ghsAmount = walletAmount * ghsRate;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main Hero Card (Dark Luxury Editorial surface per DESIGN.md)
                        _buildHeroWalletCard(
                          context: context,
                          currency: walletCurrency,
                          walletAmount: walletAmount,
                          ghsAmount: ghsAmount,
                          rate: ghsRate,
                        ),
                        const SizedBox(height: 24),

                        // Sub-wallets / Balances Section
                        const Text(
                          'Active Corridors & Balances',
                          style: TextStyle(
                            fontFamily: 'StyreneB',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...balances.map(
                          (b) => _buildBalanceRow(b, ghsRate, walletCurrency),
                        ),
                      ],
                    );
                  },
                  loading: () => _buildLoadingSkeleton(),
                  error: (error, _) => _buildErrorCard(context, ref, error),
                ),

                const SizedBox(height: 24),

                // Compliance & Security Footnote
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairlineSoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: AppColors.accentTeal,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${walletCurrency.code} held in WeWire FDIC-insured partner treasury bank. Payouts cleared via GhIPSS & Bank of Ghana regulatory rails.',
                          style: TextStyle(
                            fontFamily: 'StyreneB',
                            fontSize: 12,
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroWalletCard({
    required BuildContext context,
    required WalletCurrencyModel currency,
    required double walletAmount,
    required double ghsAmount,
    required double rate,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header with US Flag chip & Live status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDarkElevated,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(currency.flag, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      '${currency.code} Travel Float',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDarkElevated,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: AppColors.semanticUp),
                    SizedBox(width: 5),
                    Text(
                      'Live Rails',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.semanticUp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Primary balance, in the currency the user chose to hold
          const Text(
            'Available Balance',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onDarkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currency.format(walletAmount),
            key: const Key('wallet_primary_balance_text'),
            style: GoogleFonts.inter(
              fontSize: 38,
              fontWeight: FontWeight.w400,
              color: AppColors.onDark,
              letterSpacing: -1.0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),

          // Secondary GHS Equivalent Line (UX Principle: Always show both currencies)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairlineSoft.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Text('🇬🇭', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '≈ GH₵ ${ghsAmount.toStringAsFixed(2)}',
                        key: const Key('wallet_ghs_equivalent_text'),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Exchange reference: ${currency.format(1)} = GH₵${rate.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // Action Buttons (Pill geometry)
          Row(
            children: [
              // Add Money Button
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('wallet_add_money_button'),
                  onPressed: () {
                    context.push(AppRoutes.addMoney);
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text(
                    'Add Money',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Pay Anyone Button
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('wallet_pay_button'),
                  onPressed: () {
                    context.push(AppRoutes.payAnyone);
                  },

                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text(
                    'Pay Anyone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surfaceDarkElevated,
                    foregroundColor: AppColors.onDark,
                    side: const BorderSide(color: AppColors.hairlineSoft),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(
    WalletBalanceModel balance,
    double rate,
    WalletCurrencyModel walletCurrency,
  ) {
    final rowCurrency = resolveWalletCurrency(balance.currency);
    final isPrimary = balance.currency.toUpperCase() == walletCurrency.code;
    final ghsVal = isPrimary ? balance.balance * rate : balance.balance;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceStrong,
              shape: BoxShape.circle,
            ),
            child: Text(rowCurrency.flag, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${balance.currency} Wallet',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPrimary
                      ? '≈ GH₵ ${ghsVal.toStringAsFixed(2)} equivalent'
                      : 'Local ledger',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            rowCurrency.format(balance.balance),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, WidgetRef ref, Object error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.error),
          const SizedBox(height: 8),
          const Text(
            'Unable to load wallet balance',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => ref.invalidate(walletBalancesProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
