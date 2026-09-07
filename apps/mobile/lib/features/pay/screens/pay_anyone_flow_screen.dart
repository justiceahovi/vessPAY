import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../wallet/providers/currency_providers.dart';
import '../../../core/widgets/vesspay_text_field.dart';
import '../../kyc/widgets/kyc_gate.dart';
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

  // Live recipient-name confirmation state
  String _phoneInput = '';
  String _accountInput = '';
  String? _autoFilledName;

  /// Set when the user ticks "this is the right recipient" for a name nobody
  /// could confirm. Without it, an unconfirmed payment cannot be reviewed.
  bool _nameConfirmedByUser = false;

  /// Set when the user deliberately edits over a confirmed name.
  bool _nameFieldUnlocked = false;

  /// Set when the user tried to continue with an unconfirmed recipient.
  bool _confirmationMissing = false;

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

    ref
        .read(payFlowProvider.notifier)
        .setCountry(
          code: profile.destinationCountry,
          name: profile.countryName,
          flag: profile.flagEmoji,
          currency: profile.destinationCurrency,
        );
  }

  /// Lookup key for the live recipient-name confirmation. Mobile money is
  /// looked up by number, a bank account by its account number.
  RecipientLookup _recipientLookup(PayFlowData payData) {
    final isMoMo = payData.paymentType == PaymentType.mobileMoney;
    return RecipientLookup(
      phone: isMoMo ? _phoneInput : '',
      accountNumber: isMoMo ? '' : _accountInput,
      network: payData.network,
      channel: isMoMo ? 'MOBILE_MONEY' : 'BANK',
    );
  }

  /// Fills in a resolved recipient name. A name the operator or bank confirmed
  /// is authoritative, so it replaces whatever is in the field; a name we only
  /// remember locally never overwrites what the user typed.
  void _applyResolvedName(RecipientResolutionModel? resolution) {
    final name = resolution?.name;
    if (resolution == null || !resolution.resolved || name == null) return;

    final current = _nameController.text.trim();
    if (!resolution.verified) {
      if (current.isNotEmpty && current != _autoFilledName) return;
    }
    if (current == name && _autoFilledName == name) return;

    _nameController.text = name;
    setState(() {
      _autoFilledName = name;
      // A confirmed name needs no further confirmation from the user
      _nameConfirmedByUser = false;
      _nameFieldUnlocked = false;
    });

    ref
        .read(payFlowProvider.notifier)
        .setRecipientDetails(
          phone: _phoneController.text,
          name: name,
          accountNumber: _accountController.text,
          nameVerified: resolution.verified,
        );
  }

  /// Whether the name currently in the field was confirmed by the operator or
  /// bank for the account currently entered.
  bool _isNameConfirmed(RecipientResolutionModel? resolution) {
    if (resolution == null || !resolution.verified) return false;
    if (_nameFieldUnlocked) return false;
    return _nameController.text.trim() == resolution.name;
  }

  /// Lets the user take over a confirmed name, for the rare case where the
  /// account holder is not who they mean to pay.
  void _unlockNameField() {
    setState(() {
      _nameFieldUnlocked = true;
      _nameConfirmedByUser = false;
    });
  }

  /// Infers the network from the number and clears a stale auto-filled name.
  void _onPhoneChanged(String value) {
    final inferred = inferGhanaNetwork(value);

    setState(() {
      _phoneInput = value;
      _clearNameConfirmation();
    });

    if (!_networkManuallySet &&
        inferred != null &&
        inferred != ref.read(payFlowProvider).network) {
      ref.read(payFlowProvider.notifier).setNetwork(inferred);
    }
  }

  void _onAccountNumberChanged(String value) {
    setState(() {
      _accountInput = value;
      _clearNameConfirmation();
    });
  }

  /// A confirmation belongs to one destination account. Changing the account
  /// drops the confirmed name and any tick the user gave for it.
  void _clearNameConfirmation() {
    if (_autoFilledName != null &&
        _nameController.text.trim() == _autoFilledName) {
      _nameController.clear();
      _autoFilledName = null;
    }
    _nameConfirmedByUser = false;
    _nameFieldUnlocked = false;
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

  void _onSubmit(
    PaymentEstimate estimate,
    double? balance,
    RecipientResolutionModel? resolution,
  ) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_enteredAmount <= 0) return;
    if (balance != null && estimate.total > balance) return;

    // Nothing reaches the review screen with an unconfirmed recipient
    final confirmed = _isNameConfirmed(resolution);
    if (!confirmed && !_nameConfirmedByUser) {
      setState(() => _confirmationMissing = true);
      return;
    }

    HapticFeedback.mediumImpact();

    final notifier = ref.read(payFlowProvider.notifier);
    notifier.setRecipientDetails(
      phone: _phoneController.text,
      name: _nameController.text,
      accountNumber: _accountController.text,
      nameVerified: confirmed,
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
    final balance = ref
        .watch(primaryWalletBalanceProvider)
        .valueOrNull
        ?.balance;
    final isInsufficient =
        balance != null && estimate.total > 0 && estimate.total > balance;

    // The recipient has to be confirmed -- by the operator or bank, or failing
    // that by the user ticking that the name they typed is right. The button
    // stays enabled so field validation still runs; _onSubmit is what refuses
    // to continue with an unconfirmed recipient.
    final resolution = ref
        .watch(recipientNameProvider(_recipientLookup(payData)))
        .valueOrNull;

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
      body: KycGate(
        action: KycGatedAction.sendMoney,
        child: SafeArea(
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
                            walletCurrency: ref.watch(activeWalletCurrencyProvider),
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
                  onPressed: isInsufficient
                      ? null
                      : () => _onSubmit(estimate, balance, resolution),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Recipient fields
  // ------------------------------------------------------------
  List<Widget> _buildMoMoFields(PayFlowData payData) {
    final nameResolution = ref.watch(
      recipientNameProvider(_recipientLookup(payData)),
    );
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
      ..._buildRecipientNameField(nameResolution),
    ];
  }

  List<Widget> _buildBankFields(PayFlowData payData) {
    // Live institution list from WeWire, with the bundled list as a fallback
    final banks =
        ref
            .watch(payoutBanksProvider(payData.destinationCurrency))
            .valueOrNull ??
        kFallbackGhanaBanks;
    final nameResolution = ref.watch(
      recipientNameProvider(_recipientLookup(payData)),
    );

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
        onChanged: _onAccountNumberChanged,
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
      ..._buildRecipientNameField(nameResolution, isBank: true),
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

  // ------------------------------------------------------------
  // Recipient name confirmation
  //
  // The account holder is confirmed with the operator or bank before the
  // payment can be reviewed, and that confirmation is shown inside the name
  // field itself: a verified badge on a locked field when the provider
  // confirms it, a spinner while the check runs, and an explicit tick from the
  // user when nobody can confirm the name.
  // ------------------------------------------------------------
  List<Widget> _buildRecipientNameField(
    AsyncValue<RecipientResolutionModel?> nameResolution, {
    bool isBank = false,
  }) {
    final lookup = _recipientLookup(ref.read(payFlowProvider));
    final hasLookupTarget = lookup.destinationAccount != null;
    final isLookingUp = nameResolution.isLoading && hasLookupTarget;

    final resolution = nameResolution.valueOrNull;
    final confirmed = _isNameConfirmed(resolution);
    final typedName = _nameController.text.trim();
    final needsUserConfirmation = !confirmed && typedName.isNotEmpty;

    return [
      VessPayTextField(
        fieldKey: const Key('pay_recipient_name_field'),
        label: isBank ? 'Account Holder Name' : 'Recipient Name',
        hintText: isBank
            ? 'e.g. Kwame Mensah'
            : 'e.g. Kwame Mensah / Taxi Driver',
        controller: _nameController,
        keyboardType: TextInputType.name,
        readOnly: confirmed,
        onChanged: (_) => setState(() => _nameConfirmedByUser = false),
        suffix: _buildNameFieldSuffix(
          isLookingUp: isLookingUp,
          confirmed: confirmed,
          resolution: resolution,
        ),
        labelAction: confirmed
            ? TextButton(
                key: const Key('pay_recipient_name_change_button'),
                onPressed: _unlockNameField,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Change',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              )
            : null,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return isBank
                ? 'Please enter account holder name'
                : 'Please enter the recipient name';
          }
          return null;
        },
      ),
      _buildNameConfirmationStatus(
        isLookingUp: isLookingUp,
        confirmed: confirmed,
        resolution: resolution,
        hasLookupTarget: hasLookupTarget,
      ),
      if (needsUserConfirmation) ...[
        _buildManualConfirmationTick(resolution, isBank: isBank),
        if (_confirmationMissing && !_nameConfirmedByUser)
          Padding(
            key: const Key('pay_recipient_name_confirm_required'),
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Confirm the recipient before continuing.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.error,
              ),
            ),
          ),
      ],
    ];
  }

  /// The badge shown inside the name field itself.
  Widget? _buildNameFieldSuffix({
    required bool isLookingUp,
    required bool confirmed,
    required RecipientResolutionModel? resolution,
  }) {
    if (isLookingUp) {
      return const Padding(
        key: Key('pay_recipient_name_checking'),
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: AppColors.muted,
          ),
        ),
      );
    }

    if (confirmed) {
      return Container(
        key: const Key('pay_recipient_name_verified_badge'),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.semanticUp.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 13,
              color: AppColors.semanticUp,
            ),
            const SizedBox(width: 4),
            Text(
              'Verified',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.semanticUp,
              ),
            ),
          ],
        ),
      );
    }

    if (resolution != null && resolution.resolved) {
      return const Padding(
        key: Key('pay_recipient_name_known_badge'),
        padding: EdgeInsets.only(right: 12),
        child: Icon(Icons.history_rounded, size: 16, color: AppColors.muted),
      );
    }

    return null;
  }

  /// The line under the field explaining the state of the confirmation.
  Widget _buildNameConfirmationStatus({
    required bool isLookingUp,
    required bool confirmed,
    required RecipientResolutionModel? resolution,
    required bool hasLookupTarget,
  }) {
    String? message;
    Color color = AppColors.muted;
    IconData? icon;

    if (isLookingUp) {
      message = 'Confirming this account with the provider...';
    } else if (confirmed) {
      message = resolution!.sourceLabel;
      color = AppColors.semanticUp;
      icon = Icons.verified_rounded;
    } else if (resolution != null && resolution.resolved) {
      message = resolution.sourceLabel;
      icon = Icons.history_rounded;
    } else if (hasLookupTarget && resolution != null) {
      message = 'We could not confirm this account. Check the details below.';
      icon = Icons.info_outline_rounded;
    }

    if (message == null) return const SizedBox.shrink();

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
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// When nobody could confirm the name, the user confirms it themselves --
  /// nothing reaches the review screen unconfirmed.
  Widget _buildManualConfirmationTick(
    RecipientResolutionModel? resolution, {
    required bool isBank,
  }) {
    final destination = isBank
        ? _accountController.text.trim()
        : _phoneController.text.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        key: const Key('pay_recipient_name_confirm_tick'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _nameConfirmedByUser = !_nameConfirmedByUser;
          if (_nameConfirmedByUser) _confirmationMissing = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _nameConfirmedByUser
                ? AppColors.primary.withValues(alpha: 0.05)
                : (_confirmationMissing
                      ? AppColors.error.withValues(alpha: 0.06)
                      : AppColors.surfaceSoft),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _nameConfirmedByUser
                  ? AppColors.primary
                  : (_confirmationMissing
                        ? AppColors.error
                        : AppColors.hairlineSubtle),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _nameConfirmedByUser
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _nameConfirmedByUser
                        ? AppColors.primary
                        : AppColors.hairline,
                    width: 1.4,
                  ),
                ),
                child: _nameConfirmedByUser
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.isEmpty
                      ? 'I confirm this is the right recipient'
                      : 'I confirm $destination belongs to ${_nameController.text.trim()}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
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
