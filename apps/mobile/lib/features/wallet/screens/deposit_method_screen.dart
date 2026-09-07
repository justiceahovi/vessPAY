import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../kyc/widgets/kyc_gate.dart';
import '../../travel/widgets/traveling_in_indicator.dart';
import '../providers/currency_providers.dart';

/// How the user wants to put money in, asked before anything else.
///
/// The two rails are shaped differently and do not belong on one form: a bank
/// transfer is amount-first (declare a figure, get account details for it),
/// while crypto is address-first (the address stands permanently and any
/// amount can arrive).
///
/// They are also gated differently, which is the more important reason this
/// screen exists. A bank deposit needs an issued virtual account, which needs
/// Enhanced Due Diligence and a source-of-funds declaration. Crypto needs
/// none of that. Putting the choice behind the bank gate would hide the crypto
/// option from exactly the user who needs it -- someone waiting on EDD.
class DepositMethodScreen extends ConsumerWidget {
  const DepositMethodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeWalletCurrencyProvider);

    return Scaffold(
      key: const Key('deposit_method_screen'),
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          key: const Key('deposit_method_back_button'),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
        title: Text(
          'Add Money',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
      ),
      // KYC applies to both rails; the account gate applies only to the bank
      // one and lives on that screen.
      body: KycGate(
        action: KycGatedAction.addMoney,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: TravelingInIndicator.compact(),
                  ),
                ),
                Text(
                  'How would you like to add money?',
                  style: GoogleFonts.inter(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Both land in your ${currency.code} wallet.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _MethodCard(
                  cardKey: const Key('deposit_method_bank'),
                  icon: Icons.account_balance_rounded,
                  title: 'Bank transfer',
                  subtitle:
                      'Transfer ${currency.code} to your account. '
                      'You choose the amount first.',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push(AppRoutes.addMoney);
                  },
                ),
                const SizedBox(height: 12),
                _MethodCard(
                  cardKey: const Key('deposit_method_crypto'),
                  icon: Icons.currency_bitcoin_rounded,
                  title: 'Crypto',
                  subtitle:
                      'Send USDC or GHST to your deposit address. '
                      'Converted to ${currency.code} when it arrives.',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push(AppRoutes.cryptoDeposit);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final Key cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: cardKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 22, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
