import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/transaction_model.dart';
import '../providers/recent_activity_provider.dart';

/// Transaction Detail Screen displaying full transaction breakdown per VESSPAY_BLUEPRINT.md
/// Section 7 and T5.5/T5.7.
class TransactionDetailScreen extends ConsumerWidget {
  final TransactionModel? transaction;
  final String? transactionId;

  const TransactionDetailScreen({
    super.key,
    this.transaction,
    this.transactionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transaction != null) {
      return _buildScaffold(context, transaction!);
    }

    final id = transactionId ?? '';
    if (id.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text(
            'Transaction not found',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 16,
              color: AppColors.muted,
            ),
          ),
        ),
      );
    }

    final detailAsync = ref.watch(transactionDetailProvider(id));

    return detailAsync.when(
      data: (tx) => _buildScaffold(context, tx),
      loading: () => Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.canvas,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                const Text(
                  'Failed to load transaction details',
                  style: TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(transactionDetailProvider(id)),
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
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, TransactionModel tx) {
    final totalUsd = tx.sourceAmount + tx.fee;
    final recipientName = tx.recipientName ?? 'Recipient';
    final vesspayRef = tx.vesspayReference ?? 'VP-PAY-${tx.id.substring(0, tx.id.length >= 8 ? 8 : tx.id.length).toUpperCase()}';
    final wewireRef = tx.wewireReference;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Transaction Details',
          style: TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20, color: AppColors.ink),
            tooltip: 'Share Receipt',
            onPressed: () => _shareReceipt(context, tx, vesspayRef),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Amount & Status Card
              _buildHeroCard(tx),

              const SizedBox(height: 20),

              // Beneficiary Card
              _buildRecipientCard(tx, recipientName),

              const SizedBox(height: 16),

              // Payment Breakdown Card
              _buildBreakdownCard(tx, totalUsd),

              const SizedBox(height: 16),

              // Identifiers & References Card
              _buildReferencesCard(context, tx, vesspayRef, wewireRef),

              const SizedBox(height: 32),

              // Done Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  key: const Key('transaction_detail_done_button'),
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'StyreneB',
                      fontSize: 16,
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

  Widget _buildHeroCard(TransactionModel tx) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icon & Status Tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    tx.displayIcon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              _buildStatusBadge(tx.status, tx.statusColor),
            ],
          ),

          const SizedBox(height: 18),

          // Primary Destination Amount
          Text(
            '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}',
            key: const Key('detail_hero_amount'),
            style: const TextStyle(
              fontFamily: 'Copernicus',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onDark,
              letterSpacing: -0.8,
            ),
          ),

          const SizedBox(height: 6),

          // Secondary Source Amount
          Text(
            '-\$${(tx.sourceAmount + tx.fee).toStringAsFixed(2)} USD total debited',
            style: const TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 14,
              color: AppColors.onDarkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            key: const Key('detail_status_badge'),
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientCard(TransactionModel tx, String recipientName) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECIPIENT',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          _buildRowItem('Name', recipientName, key: const Key('detail_recipient_name')),
          if (tx.recipientPhone != null) ...[
            const SizedBox(height: 10),
            _buildRowItem('Mobile Number', tx.recipientPhone!, key: const Key('detail_recipient_phone')),
          ],
          if (tx.network != null) ...[
            const SizedBox(height: 10),
            _buildRowItem('Provider / Network', tx.network!, key: const Key('detail_recipient_network')),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(TransactionModel tx, double totalUsd) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PAYMENT BREAKDOWN',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          _buildRowItem('You Sent (Subtotal)', '\$${tx.sourceAmount.toStringAsFixed(2)} USD'),
          const SizedBox(height: 10),
          _buildRowItem('VessPay Fee (1%)', '\$${tx.fee.toStringAsFixed(2)} USD'),
          const SizedBox(height: 10),
          _buildRowItem('Exchange Rate', '1 USD = ${tx.exchangeRate.toStringAsFixed(2)} ${tx.destinationCurrency}'),
          const SizedBox(height: 10),
          const Divider(height: 16, color: AppColors.hairlineSoft),
          _buildRowItem(
            'Recipient Received',
            '${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}',
            valueWeight: FontWeight.w700,
            valueColor: AppColors.ink,
          ),
          const SizedBox(height: 10),
          _buildRowItem(
            'Total Debited',
            '\$${totalUsd.toStringAsFixed(2)} USD',
            valueWeight: FontWeight.w700,
            valueColor: AppColors.ink,
          ),
        ],
      ),
    );
  }

  Widget _buildReferencesCard(
    BuildContext context,
    TransactionModel tx,
    String vesspayRef,
    String? wewireRef,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRANSACTION REFERENCES',
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          _buildCopyRowItem(
            context,
            'VessPay Reference',
            vesspayRef,
            key: const Key('detail_vesspay_ref'),
          ),
          if (wewireRef != null) ...[
            const SizedBox(height: 10),
            _buildCopyRowItem(
              context,
              'WeWire Reference',
              wewireRef,
              key: const Key('detail_wewire_ref'),
            ),
          ],
          const SizedBox(height: 10),
          _buildRowItem('Date & Time', tx.formattedDate),
          const SizedBox(height: 10),
          _buildRowItem('Transaction Type', tx.type.toUpperCase()),
        ],
      ),
    );
  }

  Widget _buildRowItem(
    String label,
    String value, {
    FontWeight valueWeight = FontWeight.w600,
    Color? valueColor,
    Key? key,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'StyreneB',
            fontSize: 13,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            key: key,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: 'StyreneB',
              fontSize: 13,
              fontWeight: valueWeight,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCopyRowItem(
    BuildContext context,
    String label,
    String value, {
    Key? key,
  }) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied to clipboard'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'StyreneB',
                fontSize: 13,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  key: key,
                  style: const TextStyle(
                    fontFamily: 'StyreneB',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _shareReceipt(BuildContext context, TransactionModel tx, String reference) {
    final receiptText = '''
VessPay Payment Receipt
---------------------------
Reference: $reference
Status: ${tx.status}
Recipient: ${tx.recipientName ?? 'Recipient'} (${tx.recipientPhone ?? ''})
Network: ${tx.network ?? ''}
Amount Delivered: ${tx.destinationCurrency} ${tx.destinationAmount.toStringAsFixed(2)}
Amount Debited: \$${(tx.sourceAmount + tx.fee).toStringAsFixed(2)} USD
Rate: 1 USD = ${tx.exchangeRate.toStringAsFixed(2)} ${tx.destinationCurrency}
Fee: \$${tx.fee.toStringAsFixed(2)} USD
Date: ${tx.formattedDate}
---------------------------
Sent seamlessly via VessPay
''';

    Clipboard.setData(ClipboardData(text: receiptText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment receipt copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
