import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../models/deposit_account_model.dart';
import '../providers/wallet_providers.dart';
import '../repositories/wallet_repository.dart';
import '../../../core/api/api_error.dart';

/// Stands between the user and the deposit form until WeWire has issued them a
/// virtual account.
///
/// Everything it asks for is asked here, at the first deposit, rather than at
/// sign-up: the reason is self-evident at this moment, and most of it is never
/// needed by users who never deposit.
class DepositAccountGate extends ConsumerStatefulWidget {
  final Widget child;

  const DepositAccountGate({super.key, required this.child});

  @override
  ConsumerState<DepositAccountGate> createState() => _DepositAccountGateState();
}

class _DepositAccountGateState extends ConsumerState<DepositAccountGate> {
  bool _isSubmitting = false;
  bool _autoProvisionTried = false;

  /// What the last provision attempt reported. A failed request returns a
  /// terminal state that the read-only poll cannot see, so it is held here
  /// rather than being overwritten by the next refresh.
  DepositAccountModel? _lastAttempt;
  String? _selected;
  String? _error;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Issuance is asynchronous, so keep re-reading until it settles.
  void _pollUntilReady() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = ref.read(depositAccountProvider).valueOrNull;
      if (current != null && current.state != DepositAccountState.provisioning) {
        timer.cancel();
        return;
      }
      ref.invalidate(depositAccountProvider);
    });
  }

  void _ensurePolling() {
    if (_poll?.isActive != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pollUntilReady();
      });
    }
  }

  Future<void> _provision({String? sourceOfFunds}) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(walletRepositoryProvider)
          .provisionDepositAccount(sourceOfFunds: sourceOfFunds);
      if (!mounted) return;

      // Only keep an outcome the poll cannot rediscover: a refusal. Anything
      // in flight is better tracked by re-reading the live state.
      setState(() {
        _lastAttempt = result.state == DepositAccountState.unavailable ||
                result.state == DepositAccountState.kycRequired
            ? result
            : null;
      });
      ref.invalidate(depositAccountProvider);
      if (_lastAttempt == null) _pollUntilReady();
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(depositAccountProvider);

    // Never block the deposit form on a failed status read: the top-up call
    // reports its own errors, and a stuck gate is worse than a failed request.
    if (async.hasError) return widget.child;

    final account = _lastAttempt ?? async.valueOrNull;
    if (account == null) return _shell(const _GateSpinner());
    if (account.isReady) return widget.child;

    switch (account.state) {
      case DepositAccountState.notRequested:
        // Everything the issuer needs is on file, so ask for the account rather
        // than showing a spinner over a state that never changes on its own.
        if (!_autoProvisionTried) {
          _autoProvisionTried = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _provision();
          });
        }
        return _shell(
          _GateMessage(
            key: const Key('deposit_account_provisioning'),
            icon: Icons.hourglass_top_rounded,
            title: 'Setting up your deposit account',
            body:
                'Your ${account.currency} account is being requested. This usually takes a moment.',
            child: const _GateSpinner(),
          ),
        );

      case DepositAccountState.provisioning:
        _ensurePolling();
        return _shell(
          _GateMessage(
            key: const Key('deposit_account_provisioning'),
            icon: Icons.hourglass_top_rounded,
            title: 'Setting up your deposit account',
            body:
                'Your ${account.currency} account is being issued. This usually takes a moment.',
            child: const _GateSpinner(),
          ),
        );

      case DepositAccountState.kycRequired:
        return _shell(
          _GateMessage(
            key: const Key('deposit_account_kyc_required'),
            icon: Icons.verified_user_outlined,
            title: 'Enhanced verification needed',
            body: account.reason ??
                'Complete enhanced verification before a deposit account can be issued to you.',
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                key: const Key('deposit_account_start_kyc_button'),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push(AppRoutes.kycVerification);
                },
                style: _buttonStyle,
                child: const Text('Continue verification'),
              ),
            ),
          ),
        );

      case DepositAccountState.sourceOfFundsRequired:
        return _shell(_buildSourceOfFunds(account));

      case DepositAccountState.unavailable:
      case DepositAccountState.ready:
        return _shell(
          _GateMessage(
            key: const Key('deposit_account_unavailable'),
            icon: Icons.block_rounded,
            title: 'Deposits unavailable',
            body: account.reason ??
                'A ${account.currency} deposit account cannot be issued for your account right now.',
          ),
        );
    }
  }

  Widget _buildSourceOfFunds(DepositAccountModel account) {
    return _GateMessage(
      key: const Key('deposit_account_source_of_funds'),
      icon: Icons.account_balance_outlined,
      title: 'Where is this money from?',
      body:
          'Your provider asks for this before issuing a ${account.currency} deposit account. You only answer once.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in account.sourceOfFundsOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OptionTile(
                label: option.label,
                selected: _selected == option.value,
                onTap: _isSubmitting
                    ? null
                    : () => setState(() => _selected = option.value),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              key: const Key('deposit_account_submit_source_button'),
              onPressed: _selected == null || _isSubmitting
                  ? null
                  : () => _provision(sourceOfFunds: _selected),
              style: _buttonStyle,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle get _buttonStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.primaryDisabled,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _shell(Widget child) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: child,
      ),
    );
  }
}

class _GateSpinner extends StatelessWidget {
  const _GateSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  const _GateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 28, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
          if (child != null) ...[
            const SizedBox(height: 18),
            child!,
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceTint : AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairlineSoft,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
