import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../kyc/widgets/kyc_gate.dart';
import '../../travel/widgets/traveling_in_indicator.dart';
import '../models/wallet_currency_model.dart';
import '../providers/currency_providers.dart';
import '../providers/wallet_providers.dart';
import '../widgets/deposit_account_gate.dart';
import '../widgets/wewire_checkout_sheet.dart';

class AddMoneyScreen extends ConsumerStatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  ConsumerState<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends ConsumerState<AddMoneyScreen> {
  final TextEditingController _amountController = TextEditingController(
    text: '100.00',
  );
  final List<double> _quickAmounts = [25.0, 50.0, 100.0, 250.0, 500.0];

  @override
  void initState() {
    super.initState();
    // The top-up controller is autoDispose, so this screen always opens on a
    // blank state even when a deposit is still waiting on the rails. Ask the
    // backend for that deposit and rebuild the waiting step around it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(topupControllerProvider.notifier).restorePendingTopup();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _currentAmount {
    return double.tryParse(_amountController.text.replaceAll(',', '').trim()) ?? 0.0;
  }

  /// The currency the user chose to hold; deposits are denominated in it.
  WalletCurrencyModel get _currency => ref.read(activeWalletCurrencyProvider);

  Future<void> _handleInitiateTopup() async {
    final amount = _currentAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a valid amount greater than ${_currency.format(0)}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final notifier = ref.read(topupControllerProvider.notifier);
    final response = await notifier.initiateTopup(amount);

    if (response != null && mounted) {
      // Launch in-app checkout sheet modal instead of an external browser redirect
      await WeWireCheckoutSheet.show(
        context,
        response: response,
        amount: amount,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topupState = ref.watch(topupControllerProvider);
    // Subscribe so the whole screen re-renders in the user's chosen currency
    // once it resolves; the helper builders read it through _currency.
    ref.watch(activeWalletCurrencyProvider);
    final destinationRate = ref.watch(walletToDestinationRateProvider);
    final destinationEquivalent = _currentAmount * destinationRate;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          key: const Key('add_money_back_button'),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.ink,
          ),
          onPressed: () {
            ref.read(topupControllerProvider.notifier).reset();
            Navigator.of(context).maybePop();
          },
        ),
        title: const Text(
          'Add Money',
          style: TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
      ),
      body: KycGate(
        action: KycGatedAction.addMoney,
        // Basic KYC clears the gate above; a deposit additionally needs an
        // issued WeWire account, which needs EDD and a source-of-funds answer.
        child: DepositAccountGate(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Traveling In indicator
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: TravelingInIndicator.compact(),
                    ),
                  ),

                  // Switch view based on step
                  if (topupState.step == TopupStep.enterAmount ||
                      topupState.step == TopupStep.initiating) ...[
                    _buildAmountEntrySection(
                      destinationEquivalent,
                      topupState.step == TopupStep.initiating,
                    ),
                  ] else if (topupState.step ==
                      TopupStep.waitingConfirmation) ...[
                    _buildWaitingConfirmationSection(topupState),
                  ] else if (topupState.step == TopupStep.completed) ...[
                    _buildCompletedSection(topupState),
                  ] else if (topupState.step == TopupStep.failed) ...[
                    _buildFailedSection(topupState),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountEntrySection(double destinationEquivalent, bool isInitiating) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Hero Amount Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount to Add (${_currency.code})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: AppColors.hairlineSoft),
                    ),
                    child: Text(
                      '${_currency.flag} ${_currency.code}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Currency prefix and large textfield (Inter weight 400 per DESIGN.md)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _currency.symbol,
                    style: GoogleFonts.inter(
                      fontSize: 40,
                      fontWeight: FontWeight.w400,
                      color: AppColors.ink,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: const Key('add_money_amount_input'),
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.inter(
                        fontSize: 40,
                        fontWeight: FontWeight.w400,
                        color: AppColors.ink,
                        letterSpacing: -1.0,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '0.00',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 40,
                          fontWeight: FontWeight.w400,
                          color: AppColors.muted,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(color: AppColors.hairline, height: 24),

              // GHS Equivalent Line
              Row(
                children: [
                  const Text('🇬🇭', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    '≈ GH₵ ${formatAmount(destinationEquivalent)} local spending power',
                    key: const Key('add_money_ghs_equivalent_text'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Quick Amount Chips
        const Text(
          'Quick Amounts',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _quickAmounts.map((amt) {
            final isSelected = _currentAmount == amt;
            return InkWell(
              onTap: () {
                setState(() {
                  _amountController.text = formatAmount(amt);
                });
              },
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.hairline,
                  ),
                ),
                child: Text(
                  '+${_currency.format(amt, decimals: 0)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.onPrimary : AppColors.ink,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Funding Rails Method Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.hairlineSoft),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WeWire ${_currency.code} Virtual Account',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Direct bank transfer via ${_currency.fundingRail}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Submit Button (Pill geometry)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            key: const Key('add_money_submit_button'),
            onPressed: isInitiating ? null : _handleInitiateTopup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: isInitiating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Text(
                    'Continue to Funding (${_currency.format(_currentAmount)})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingConfirmationSection(TopupState state) {
    final resp = state.response;
    final account = resp?.accountDetails;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          // Animated Pulse & Clock
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Waiting for Bank Confirmation',
            key: Key('waiting_confirmation_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'Transfer ${_currency.format(state.amount)} ${_currency.code} using the provided WeWire virtual account details. Once the ${_currency.fundingRail} confirms receipt, your balance updates immediately.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 13,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          // Details summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairlineSoft),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  'Amount Expected',
                  '${_currency.format(state.amount)} ${_currency.code}',
                ),
                const Divider(color: AppColors.hairlineSoft, height: 16),
                _buildSummaryRow(
                  'Status',
                  'PENDING (Awaiting settlement)',
                  isHighlighted: true,
                ),
                if (resp != null) ...[
                  const Divider(color: AppColors.hairlineSoft, height: 16),
                  _buildSummaryRow(
                    'Transaction ID',
                    resp.fundingTransactionId.substring(0, 8),
                  ),
                ],
                // US accounts are addressed by account/routing number, EUR and
                // GBP ones by IBAN and BIC, so show whichever the issuer gave.
                if (account?.hasLocalNumbers ?? false) ...[
                  const Divider(color: AppColors.hairlineSoft, height: 16),
                  _buildSummaryRow(
                    'Virtual Account',
                    [
                      account!.bankName,
                      if (account.accountNumber != null)
                        '(${account.accountNumber})',
                    ].whereType<String>().join(' '),
                  ),
                  if (account.routingNumber != null) ...[
                    const Divider(color: AppColors.hairlineSoft, height: 16),
                    _buildSummaryRow('Routing Number', account.routingNumber!),
                  ],
                  if (account.sortCode != null) ...[
                    const Divider(color: AppColors.hairlineSoft, height: 16),
                    _buildSummaryRow('Sort Code', account.sortCode!),
                  ],
                ] else if (account?.hasIban ?? false) ...[
                  const Divider(color: AppColors.hairlineSoft, height: 16),
                  if (account!.iban != null)
                    _buildSummaryRow('IBAN', account.iban!),
                  if (account.bic != null) ...[
                    const Divider(color: AppColors.hairlineSoft, height: 16),
                    _buildSummaryRow('BIC', account.bic!),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Instant simulate deposit button.
          //
          // With a real WeWire account behind this top-up the deposit goes
          // through their sandbox and the wallet is credited by the pay-in
          // webhook. Without one there is nothing to deposit into, so it falls
          // back to crediting the local ledger directly.
          if (resp != null) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('simulate_deposit_now_button'),
                onPressed: () {
                  ref
                      .read(topupControllerProvider.notifier)
                      .simulateWeWireDeposit(resp.fundingTransactionId);
                },
                icon: const Icon(Icons.bolt, size: 20),
                label: Text(
                  'Simulate Bank Deposit (${_currency.format(state.amount)})',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('reopen_checkout_button'),
              onPressed: () {
                WeWireCheckoutSheet.show(
                  context,
                  response: resp,
                  amount: state.amount,
                );
              },
              icon: const Icon(Icons.account_balance_outlined, size: 18),
              label: const Text(
                'View Virtual Account Details',
                style: TextStyle(
                  fontFamily: 'StyreneB',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextButton(
            onPressed: () {
              ref.read(topupControllerProvider.notifier).reset();
              Navigator.of(context).maybePop();
            },
            child: const Text(
              'Return to Wallet (Processing in background)',
              style: TextStyle(
                fontFamily: 'StyreneB',
                color: AppColors.muted,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedSection(TopupState state) {
    final resp = state.response;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 44,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Deposit Confirmed!',
            key: Key('topup_success_title'),
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            '+${_currency.format(resp?.creditedAmount ?? state.amount)} ${_currency.code} has been credited to your VessPay Travel Wallet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 14,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),

          // The rails take a cut on the way in, so the credited amount is less
          // than the amount sent. Show the breakdown rather than leaving the
          // user to notice the shortfall on their own.
          if (resp != null && resp.hasFee) ...[
            const SizedBox(height: 16),
            Container(
              key: const Key('deposit_fee_breakdown'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.hairlineSoft),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(
                    'Amount sent',
                    '${_currency.format(resp.amount)} ${resp.currency}',
                  ),
                  const Divider(color: AppColors.hairlineSoft, height: 16),
                  _buildSummaryRow(
                    'Bank fee',
                    '-${_currency.format(resp.fee)} ${resp.currency}',
                  ),
                  const Divider(color: AppColors.hairlineSoft, height: 16),
                  _buildSummaryRow(
                    'Credited to wallet',
                    '${_currency.format(resp.creditedAmount)} ${resp.currency}',
                    isHighlighted: true,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              key: const Key('add_money_done_button'),
              onPressed: () {
                ref.read(topupControllerProvider.notifier).reset();
                Navigator.of(context).maybePop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View Updated Wallet',
                style: TextStyle(
                  fontFamily: 'StyreneB',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedSection(TopupState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          const Text(
            'Funding Failed',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.errorMessage ??
                'An error occurred while initiating your funding transaction.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 13,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => ref.read(topupControllerProvider.notifier).reset(),
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

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isHighlighted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 12,
            color: AppColors.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isHighlighted ? AppColors.accentAmber : AppColors.ink,
          ),
        ),
      ],
    );
  }
}
