import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/vesspay_text_field.dart';
import '../../travel/models/travel_profile_model.dart';
import '../../travel/providers/travel_providers.dart';
import '../../travel/screens/destination_selection_screen.dart';
import '../../wallet/providers/wallet_providers.dart';
import '../models/pay_flow_model.dart';
import '../models/payment_estimate.dart';
import '../models/payout_institution_model.dart';
import '../models/recipient_resolution_model.dart';
import '../providers/pay_anyone_providers.dart';
import '../providers/recent_recipients_provider.dart';
import '../widgets/amount_entry_card.dart';
import '../widgets/network_selector_field.dart';
import '../widgets/payment_estimate_card.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/recent_recipients_row.dart';

/// Single-page "send money" form. Recipient and amount live together because
/// one is meaningless without the other; the only remaining step is the review
/// screen, which is where the server quote is confirmed before money moves.
class PayAnyoneFlowScreen extends ConsumerStatefulWidget {
  const PayAnyoneFlowScreen({super.key});

  @override
  ConsumerState<PayAnyoneFlowScreen> createState() =>
      _PayAnyoneFlowScreenState();
}

class _PayAnyoneFlowScreenState extends ConsumerState<PayAnyoneFlowScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  final _formKey = GlobalKey<FormState>();

  // Live recipient-name resolution state
  String _phoneInput = '';
  String? _autoFilledName;

  /// Once the user picks a network by hand, stop inferring it from the number.
  bool _networkManuallySet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyTravelDestination(
        ref.read(currentTravelProfileProvider).valueOrNull,
      );
    });

    final payData = ref.read(payFlowProvider);
    if (payData.recipientPhone.isNotEmpty) {
      _phoneController.text = payData.recipientPhone;
      _phoneInput = payData.recipientPhone;
    }
    if (payData.recipientName.isNotEmpty) {
      _nameController.text = payData.recipientName;
    }
    if (payData.accountNumber.isNotEmpty) {
      _accountController.text = payData.accountNumber;
    }
    if (payData.destinationAmount > 0) {
      _amountController.text = payData.destinationAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _accountController.dispose();
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _close() {
    HapticFeedback.lightImpact();
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// Points the flow at the destination the traveller already set, so the
  /// country never has to be chosen again inside the payment flow.
  void _applyTravelDestination(TravelProfileModel? profile) {
    if (profile == null || profile.destinationCountry.isEmpty) return;
    if (!mounted) return;

    ref.read(payFlowProvider.notifier).setCountry(
          code: profile.destinationCountry,
          name: profile.countryName,
          flag: profile.flagEmoji,
          currency: profile.destinationCurrency,
        );
  }

  /// Lookup key for the live recipient-name resolution. Bank transfers keep the
  /// manually entered account holder name, so no lookup runs for them.
  RecipientLookup _recipientLookup(PayFlowData payData) {
    final isMoMo = payData.paymentType == PaymentType.mobileMoney;
    return RecipientLookup(
      phone: isMoMo ? _phoneInput : '',
      network: isMoMo ? payData.network : '',
    );
  }

  /// Fills in a resolved recipient name without overwriting what the user typed.
  void _applyResolvedName(RecipientResolutionModel? resolution) {
    final name = resolution?.name;
    if (resolution == null || !resolution.resolved || name == null) return;

    final current = _nameController.text.trim();
    if (current.isNotEmpty && current != _autoFilledName) return;
    if (current == name) return;

    _nameController.text = name;
    _autoFilledName = name;
    ref.read(payFlowProvider.notifier).setRecipientDetails(
          phone: _phoneController.text,
          name: name,
          accountNumber: _accountController.text,
        );
  }

  /// Infers the network from the number and clears a stale auto-filled name.
  void _onPhoneChanged(String value) {
    final inferred = inferGhanaNetwork(value);

    setState(() {
      _phoneInput = value;
      if (_autoFilledName != null &&
          _nameController.text.trim() == _autoFilledName) {
        _nameController.clear();
        _autoFilledName = null;
      }
    });

    if (!_networkManuallySet &&
        inferred != null &&
        inferred != ref.read(payFlowProvider).network) {
      ref.read(payFlowProvider.notifier).setNetwork(inferred);
    }
  }

  void _onNetworkChanged(String network) {
    setState(() => _networkManuallySet = true);
    ref.read(payFlowProvider.notifier).setNetwork(network);
  }

  void _onPaymentTypeChanged(PaymentType type) {
    setState(() => _networkManuallySet = false);
    ref.read(payFlowProvider.notifier).setPaymentType(type);
  }

  /// One tap fills in everything known about a previous recipient and drops the
  /// user straight into the amount field.
  void _onRecentRecipientSelected(RecentRecipient recipient) {
    final network = recipient.network.isNotEmpty
        ? recipient.network
        : inferGhanaNetwork(recipient.phone);

    _phoneController.text = recipient.phone;
    _nameController.text = recipient.name;

    setState(() {
      _phoneInput = recipient.phone;
      _autoFilledName = recipient.name;
      _networkManuallySet = false;
    });

    final notifier = ref.read(payFlowProvider.notifier);
    if (network != null && network.isNotEmpty) {
      notifier.setNetwork(network);
    }
    notifier.setRecipientDetails(
      phone: recipient.phone,
      name: recipient.name,
      accountNumber: _accountController.text,
    );

    _amountFocusNode.requestFocus();
  }

  void _onAmountChanged(double amount) {
    ref.read(payFlowProvider.notifier).setAmount(amount);
    setState(() {});
  }

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0.0;

  void _onSubmit(PaymentEstimate estimate, double? balance) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_enteredAmount <= 0) return;
    if (balance != null && estimate.total > balance) return;

    HapticFeedback.mediumImpact();

    final notifier = ref.read(payFlowProvider.notifier);
    notifier.setRecipientDetails(
      phone: _phoneController.text,
      name: _nameController.text,
      accountNumber: _accountController.text,
    );
    notifier.setAmount(_enteredAmount);

    context.push(AppRoutes.paymentReview);
  }

  @override
  Widget build(BuildContext context) {
    final payData = ref.watch(payFlowProvider);

    // Auto-fill the recipient name as soon as the typed number resolves
    ref.listen<AsyncValue<RecipientResolutionModel?>>(
      recipientNameProvider(_recipientLookup(payData)),
      (previous, next) => _applyResolvedName(next.valueOrNull),
    );

    // The saved travel destination may still be loading when this screen opens
    ref.listen<AsyncValue<TravelProfileModel?>>(
      currentTravelProfileProvider,
      (previous, next) => _applyTravelDestination(next.valueOrNull),
    );

    final isMoMo = payData.paymentType == PaymentType.mobileMoney;
    final currencySymbol = payData.destinationCurrency == 'NGN' ? '₦' : 'GH₵';
    final estimate = PaymentEstimate.local(
      destinationAmount: _enteredAmount,
      exchangeRate: payData.exchangeRate,
    );
    final balance =
        ref.watch(primaryWalletBalanceProvider).valueOrNull?.balance;
    final isInsufficient =
        balance != null && estimate.total > 0 && estimate.total > balance;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: InkWell(
              key: const Key('pay_flow_back_button'),
              borderRadius: BorderRadius.circular(100),
              onTap: _close,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.hairlineSubtle,
                    width: 1.0,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Pay Anyone',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              key: const Key('pay_flow_cancel_button'),
              onPressed: _close,
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Send money',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Pay anyone in ${payData.countryName} directly. The recipient does not need a VessPay account.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildDestinationPill(payData),
                        const SizedBox(height: 16),

                        PaymentMethodSelector(
                          selected: payData.paymentType,
                          onChanged: _onPaymentTypeChanged,
                        ),
                        const SizedBox(height: 20),

                        RecentRecipientsRow(
                          selectedPhone: _phoneInput,
                          onSelected: _onRecentRecipientSelected,
                        ),

                        if (isMoMo)
                          ..._buildMoMoFields(payData)
                        else
                          ..._buildBankFields(payData),

                        const SizedBox(height: 22),

                        Text(
                          'Amount',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bodyStrong,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AmountEntryCard(
                          controller: _amountController,
                          currencySymbol: currencySymbol,
                          focusNode: _amountFocusNode,
                          onAmountChanged: _onAmountChanged,
                        ),
                        const SizedBox(height: 18),

                        PaymentEstimateCard(
                          estimate: estimate,
                          currencySymbol: currencySymbol,
                          availableBalance: balance,
                        ),
                        const SizedBox(height: 18),

                        _buildAssuranceBanner(payData),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                key: const Key('pay_continue_to_review_button'),
                label: 'Review Payment',
                onPressed:
                    isInsufficient ? null : () => _onSubmit(estimate, balance),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Recipient fields
  // ------------------------------------------------------------
  List<Widget> _buildMoMoFields(PayFlowData payData) {
    final nameResolution =
        ref.watch(recipientNameProvider(_recipientLookup(payData)));
    final inferred = inferGhanaNetwork(_phoneInput);
    final autoDetected =
        !_networkManuallySet && inferred != null && inferred == payData.network;

    return [
      NetworkSelectorField(
        label: 'Mobile Network',
        value: payData.network,
        options: kGhanaMoMoOptions,
        onChanged: _onNetworkChanged,
        autoDetected: autoDetected,
      ),
      const SizedBox(height: 16),
      VessPayTextField(
        fieldKey: const Key('pay_recipient_phone_field'),
        label: 'Recipient Mobile Number',
        hintText: '024 123 4567',
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        onChanged: _onPhoneChanged,
        prefixIcon: _buildDialCodePrefix(payData),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter recipient phone number';
          }
          final cleaned = value.replaceAll(RegExp(r'\s+'), '');
          if (cleaned.length < 9) {
            return 'Please enter a valid Ghana phone number (min 9 digits)';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      VessPayTextField(
        fieldKey: const Key('pay_recipient_name_field'),
        label: 'Recipient Name (Optional)',
        hintText: 'e.g. Kwame Mensah / Taxi Driver',
        controller: _nameController,
        keyboardType: TextInputType.name,
      ),
      _buildNameResolutionStatus(nameResolution),
    ];
  }

  List<Widget> _buildBankFields(PayFlowData payData) {
    // Live institution list from WeWire, with the bundled list as a fallback
    final banks = ref
            .watch(payoutBanksProvider(payData.destinationCurrency))
            .valueOrNull ??
        kFallbackGhanaBanks;

    return [
      NetworkSelectorField(
        label: 'Destination Bank',
        value: payData.network,
        options: banks.map(NetworkOption.fromInstitution).toList(),
        onChanged: _onNetworkChanged,
      ),
      const SizedBox(height: 16),
      VessPayTextField(
        fieldKey: const Key('pay_account_number_field'),
        label: 'Account Number',
        hintText: 'e.g. 1029384756123',
        controller: _accountController,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter account number';
          }
          if (normalizeBankAccountNumber(value) == null) {
            return 'Please enter a valid account number (8-20 digits)';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      VessPayTextField(
        fieldKey: const Key('pay_recipient_name_field'),
        label: 'Account Holder Name',
        hintText: 'e.g. Kwame Mensah',
        controller: _nameController,
        keyboardType: TextInputType.name,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter account holder name';
          }
          return null;
        },
      ),
    ];
  }

  Widget _buildDialCodePrefix(PayFlowData payData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(payData.countryFlag, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            payData.countryCode == 'NG' ? '+234' : '+233',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '|',
            style: TextStyle(color: AppColors.hairline, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Inline feedback for the automatic recipient name lookup underneath the
  /// name field: a quiet "checking" state while the number is being resolved,
  /// and where the name came from once it is filled in.
  Widget _buildNameResolutionStatus(
    AsyncValue<RecipientResolutionModel?> resolution,
  ) {
    final isLookingUp =
        resolution.isLoading && normalizeGhanaMsisdn(_phoneInput) != null;
    final resolved = resolution.valueOrNull;
    final hasName = resolved != null && resolved.resolved;

    if (!isLookingUp && !hasName) {
      return const SizedBox.shrink();
    }

    return Padding(
      key: const Key('pay_recipient_name_status'),
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Row(
        children: [
          if (isLookingUp)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.muted,
              ),
            )
          else
            const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLookingUp
                  ? 'Looking up recipient name...'
                  : resolved!.sourceLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isLookingUp ? AppColors.muted : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // Chrome
  // ------------------------------------------------------------
  Widget _buildDestinationPill(PayFlowData payData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(payData.countryFlag, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            'Destination: ${payData.countryName}',
            key: const Key('pay_determined_country_badge'),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => DestinationSelectionScreen.showAsBottomSheet(context),
            child: Text(
              'Change',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssuranceBanner(PayFlowData payData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairlineSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 17,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Payment will be credited directly in ${payData.countryName} without recipient needing a VessPay account.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        key: key,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
