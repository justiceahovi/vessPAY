import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/corridors.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../travel/providers/travel_providers.dart';
import '../../wallet/models/wallet_currency_model.dart';
import '../models/pay_flow_model.dart';
import '../models/payment_estimate.dart';
import '../models/payment_quote_model.dart';
import '../models/transaction_model.dart';
import '../providers/pay_anyone_providers.dart';
import '../repositories/payment_repository.dart';

class PaymentReviewScreen extends ConsumerStatefulWidget {
  final PayFlowData? dataOverride;
  final PaymentQuoteModel? quoteOverride;

  const PaymentReviewScreen({
    super.key,
    this.dataOverride,
    this.quoteOverride,
  });

  @override
  ConsumerState<PaymentReviewScreen> createState() =>
      _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends ConsumerState<PaymentReviewScreen> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final PayFlowData payData = widget.dataOverride ?? ref.watch(payFlowProvider);

    if (widget.quoteOverride != null) {
      return _buildReviewContent(context, payData, widget.quoteOverride!);
    }

    final quoteRequest = PaymentQuoteRequest.fromPayData(payData);

    // Local estimate, shown only until the server quote lands. It uses the same
    // formula the server does, so the two agree unless the rate moved.
    final estimate = PaymentEstimate.local(
      destinationAmount: payData.destinationAmount,
      exchangeRate: payData.exchangeRate,
      destinationCurrency: payData.destinationCurrency,
    );
    final fallbackQuote = PaymentQuoteModel(
      sourceCurrency: payData.sourceCurrency,
      sourceAmount: payData.quoteSourceAmount ?? estimate.sourceAmount,
      destinationCurrency: payData.destinationCurrency,
      destinationAmount: payData.destinationAmount,
      exchangeRate: payData.exchangeRate,
      fee: payData.quoteFee ?? estimate.fee,
      wewireFee: estimate.wewireFee,
      total: payData.quoteTotal ?? estimate.total,
      country: payData.countryCode,
      network: payData.network,
      phone: quoteRequest.recipient,
    );

    // Never quote against placeholder details: with nothing real to price, the
    // local estimate is all there is to show.
    if (!quoteRequest.isComplete) {
      return _buildReviewContent(
        context,
        payData,
        fallbackQuote,
        isEstimate: true,
      );
    }

    final quoteAsync = ref.watch(paymentQuoteProvider(quoteRequest));

    return quoteAsync.when(
      data: (quote) => _buildReviewContent(context, payData, quote),
      loading: () {
        if (payData.destinationAmount > 0) {
          return _buildReviewContent(
            context,
            payData,
            fallbackQuote,
            isEstimate: true,
          );
        }
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: _buildAppBar(context),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Fetching live quote...',
                  style: TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      error: (err, stack) {
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: _buildAppBar(context),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Unable to fetch live quote',
                    style: TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    key: const Key('review_retry_button'),
                    onPressed: () {
                      ref.invalidate(paymentQuoteProvider(quoteRequest));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.canvas,
      elevation: 0,
      leading: IconButton(
        key: const Key('review_back_button'),
        icon: const Icon(Icons.arrow_back, color: AppColors.ink),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
      title: const Text(
        'Review Payment',
        style: TextStyle(
          fontFamily: 'StyreneB',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildReviewContent(
    BuildContext context,
    PayFlowData payData,
    PaymentQuoteModel quote, {
    bool isEstimate = false,
  }) {
    final destAmount = quote.destinationAmount;
    final sourceAmount = quote.sourceAmount;
    final fee = quote.fee;
    final wewireFee = quote.wewireFee;
    final total = quote.total;
    final rate = quote.exchangeRate;
    // The wallet is not necessarily in USD, so every source-side figure is
    // formatted with the currency the quote was actually priced in.
    final sourceCurrency = resolveWalletCurrency(quote.sourceCurrency);
    final destinationCorridor = corridorFor(quote.destinationCurrency);
    final destCurrencySymbol = destinationCorridor.symbol;
    // The server is the authority on whether a rail is live; the bundled table
    // is the fallback before GET /api/travel/destinations has been read.
    final payoutAvailable = ref
            .watch(destinationsProvider)
            .valueOrNull
            ?.where((d) => d.currency == quote.destinationCurrency)
            .map((d) => d.payoutAvailable)
            .firstOrNull ??
        destinationCorridor.payoutAvailable;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ============================================================
              // Section 11 UX Principle: Always show both currencies Hero Card
              // "You pay $13.08 / Recipient gets GH₵150"
              // ============================================================
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Dual Currencies Display
                    Row(
                      children: [
                        // Left: You Pay
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'You Pay (${sourceCurrency.code})',
                                style: const TextStyle(
                                  fontFamily: 'StyreneB',
                                  fontSize: 12,
                                  color: AppColors.onDarkSoft,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                sourceCurrency.format(total),
                                key: const Key('review_you_pay_header'),
                                style: const TextStyle(
                                  fontFamily: 'Copernicus',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onDark,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Includes ${sourceCurrency.format(fee)} fee',
                                style: TextStyle(
                                  fontFamily: 'StyreneB',
                                  fontSize: 11,
                                  color: AppColors.onDarkSoft.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Arrow Divider
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDarkElevated,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),

                        // Right: Recipient Gets
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Recipient Gets (${quote.destinationCurrency})',
                                style: const TextStyle(
                                  fontFamily: 'StyreneB',
                                  fontSize: 12,
                                  color: AppColors.onDarkSoft,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$destCurrencySymbol${formatAmount(destAmount)}',
                                key: const Key('review_recipient_gets_header'),
                                style: const TextStyle(
                                  fontFamily: 'Copernicus',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Mobile Money / Bank',
                                style: TextStyle(
                                  fontFamily: 'StyreneB',
                                  fontSize: 11,
                                  color: AppColors.onDarkSoft.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Exchange Rate Reference Chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDarkElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: AppColors.onDarkSoft,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Exchange Rate: 1 ${sourceCurrency.code} = $destCurrencySymbol${formatAmount(rate)} ${quote.destinationCurrency}',
                            key: const Key('review_exchange_rate_chip'),
                            style: const TextStyle(
                              fontFamily: 'StyreneB',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // These figures are local until the server quote lands
                    if (isEstimate) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Estimated — confirmed against live rates when you pay.',
                        key: const Key('review_estimate_notice'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'StyreneB',
                          fontSize: 11,
                          color: AppColors.onDarkSoft.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Recipient Details Card
              _buildSectionHeader('Recipient Details'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      label: 'Destination Country',
                      value: '${payData.countryFlag} ${payData.countryName}',
                      valueKey: const Key('review_country'),
                    ),
                    const Divider(color: AppColors.hairline, height: 20),
                    _buildDetailRow(
                      label: 'Payment Method',
                      value: payData.paymentType.displayName,
                      valueKey: const Key('review_payment_type'),
                    ),
                    const Divider(color: AppColors.hairline, height: 20),
                    _buildDetailRow(
                      label: 'Network / Provider',
                      value: quote.network ?? payData.network,
                      valueKey: const Key('review_network'),
                    ),
                    const Divider(color: AppColors.hairline, height: 20),
                    _buildDetailRow(
                      label: payData.paymentType == PaymentType.mobileMoney
                          ? 'Recipient Phone'
                          : 'Account Number',
                      value: payData.paymentType == PaymentType.mobileMoney
                          ? (quote.phone ?? payData.recipientPhone)
                          : payData.accountNumber,
                      valueKey: const Key('review_recipient_phone'),
                    ),
                    if (payData.recipientName.isNotEmpty) ...[
                      const Divider(color: AppColors.hairline, height: 20),
                      _buildDetailRow(
                        label: 'Recipient Name',
                        value: payData.recipientName,
                        valueKey: const Key('review_recipient_name'),
                        // Carries the account-holder confirmation to the last
                        // screen before the money moves
                        trailing: payData.recipientNameVerified
                            ? const _VerifiedNameBadge()
                            : null,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Transfer & Fee Breakdown Card
              _buildSectionHeader('Transfer Breakdown (Live Quote)'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      label: 'Recipient Receives',
                      value: '$destCurrencySymbol${formatAmount(destAmount)}',
                      valueKey: const Key('review_destination_amount'),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      label: 'Exchange Rate',
                      value: '1 ${sourceCurrency.code} = $destCurrencySymbol${formatAmount(rate)}',
                      valueKey: const Key('review_exchange_rate'),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      label: '${sourceCurrency.code} Subtotal',
                      value: sourceCurrency.format(sourceAmount),
                      valueKey: const Key('review_source_amount'),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      label: 'VessPay Fee (1%)',
                      value: sourceCurrency.format(fee),
                      valueKey: const Key('review_fee'),
                    ),
                    if (wewireFee > 0) ...[
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        label: 'Payment Processor Fee',
                        value: sourceCurrency.format(wewireFee),
                        valueKey: const Key('review_wewire_fee'),
                      ),
                    ],
                    const Divider(color: AppColors.hairline, height: 22),
                    _buildDetailRow(
                      label: 'Total to Debit (${sourceCurrency.code})',
                      value: sourceCurrency.format(total),
                      valueKey: const Key('review_total'),
                      isBold: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Everything above this point is real for a corridor whose rail
              // is not live yet -- the recipient was confirmed with the bank,
              // the rate and fees are the server's. Only the step that moves
              // money is held back, and it says so rather than failing at the
              // provider with an error the user cannot act on.
              if (!payoutAvailable) ...[
                Container(
                  key: const Key('review_payout_unavailable_notice'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${destinationCorridor.name} payouts are not live yet',
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'This quote is live and the recipient is confirmed, '
                              'but the payout rail for ${destinationCorridor.currency} is not open yet. '
                              'Nothing will be charged.',
                              style: const TextStyle(
                                fontFamily: 'StyreneB',
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Confirm Payment CTA Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  key: const Key('review_confirm_payment_button'),
                  onPressed: (_isSubmitting || !payoutAvailable)
                      ? null
                      : () => _handleConfirmPayment(payData, quote),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.hairline,
                    disabledForegroundColor: AppColors.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          payoutAvailable
                              ? 'Confirm Payment • Pay ${sourceCurrency.format(total)}'
                              : '${destinationCorridor.name} payouts coming soon',
                          style: const TextStyle(
                            fontFamily: 'StyreneB',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleConfirmPayment(
    PayFlowData payData,
    PaymentQuoteModel quote,
  ) async {
    setState(() {
      _isSubmitting = true;
    });

    final isBank = payData.paymentType == PaymentType.bankTransfer;

    final phone = quote.phone != null && quote.phone!.isNotEmpty
        ? quote.phone!
        : payData.recipientPhone;

    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final cleanAccount = payData.accountNumber.replaceAll(RegExp(r'\D'), '');
    final destinationAccount = isBank ? cleanAccount : cleanPhone;
    final idempotencyKey =
        'VP-PAY-${DateTime.now().millisecondsSinceEpoch}-$destinationAccount';

    final countryCode = (quote.country != null && quote.country!.isNotEmpty)
        ? quote.country!
        : (payData.countryCode.isNotEmpty ? payData.countryCode : 'GH');

    final networkCode = (quote.network != null && quote.network!.isNotEmpty)
        ? quote.network!
        : (payData.network.isNotEmpty ? payData.network : 'MTN');

    final recipientName = payData.recipientName.isNotEmpty
        ? payData.recipientName
        : 'Recipient';

    try {
      final repository = ref.read(paymentRepositoryProvider);
      final response = await repository.createPayment(
        country: countryCode,
        network: networkCode,
        phone: cleanPhone,
        accountNumber: isBank ? cleanAccount : null,
        channel: isBank ? 'BANK' : 'MOBILE_MONEY',
        destinationAmount: quote.destinationAmount,
        destinationCurrency: quote.destinationCurrency,
        idempotencyKey: idempotencyKey,
        recipientName: recipientName,
      );

      final initialTx = TransactionModel(
        id: response.transactionId,
        type: 'payout',
        status: response.status,
        sourceCurrency: quote.sourceCurrency,
        sourceAmount: quote.sourceAmount,
        destinationCurrency: quote.destinationCurrency,
        destinationAmount: quote.destinationAmount,
        fee: quote.fee,
        wewireFee: quote.wewireFee,
        exchangeRate: quote.exchangeRate,
        recipientName: recipientName,
        recipientPhone: cleanPhone,
        network: networkCode,
        country: countryCode,
        vesspayReference: 'VP-PAY-${response.transactionId.replaceAll('-', '').substring(0, 12).toUpperCase()}',
        wewireReference: response.wewireTransactionId,
        createdAt: DateTime.now(),
      );

      if (!mounted) return;
      context.go(
        AppRoutes.paymentProcessing,
        extra: {
          'transactionId': response.transactionId,
          'initialTransaction': initialTx,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment could not be started: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'StyreneB',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.bodyStrong,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    Key? valueKey,
    bool isBold = false,
    Widget? trailing,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'StyreneB',
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            color: isBold ? AppColors.ink : AppColors.muted,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              key: valueKey,
              style: TextStyle(
                fontFamily: 'StyreneB',
                fontSize: isBold ? 15 : 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: isBold ? AppColors.primary : AppColors.ink,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ],
    );
  }
}

/// Marks a recipient name the operator or bank confirmed.
class _VerifiedNameBadge extends StatelessWidget {
  const _VerifiedNameBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('review_recipient_name_verified'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.semanticUp.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 12, color: AppColors.semanticUp),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.semanticUp,
            ),
          ),
        ],
      ),
    );
  }
}
