import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../models/crypto_deposit_model.dart';
import '../providers/wallet_providers.dart';

/// Deposit by crypto: pick a network, get an address.
///
/// Two things carry more risk here than anywhere else in the app, and both
/// shape the layout:
///
///  - Sending a token on the wrong network loses it permanently. The chain is
///    stated on the address itself, not just in the picker above it.
///  - A testnet address looks exactly like a mainnet one. When the provider
///    reports TESTNET, that is said loudly, because a user who sends real funds
///    to a testnet address has lost them.
class CryptoDepositScreen extends ConsumerStatefulWidget {
  const CryptoDepositScreen({super.key});

  @override
  ConsumerState<CryptoDepositScreen> createState() =>
      _CryptoDepositScreenState();
}

class _CryptoDepositScreenState extends ConsumerState<CryptoDepositScreen> {
  String? _selectedChain;

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('crypto_address_copied_snackbar'),
        content: Text('Deposit address copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chainsAsync = ref.watch(cryptoChainsProvider);

    return Scaffold(
      key: const Key('crypto_deposit_screen'),
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        leading: IconButton(
          key: const Key('crypto_deposit_back_button'),
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
          'Deposit Crypto',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: chainsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => _buildError(err.toString()),
          data: (chains) {
            if (chains.isEmpty) {
              return _buildError('No deposit networks are available right now.');
            }
            final selected = _selectedChain ??
                (chains.any((c) => c.chain == 'BASE') ? 'BASE' : chains.first.chain);
            final chain = chains.firstWhere(
              (c) => c.chain == selected,
              orElse: () => chains.first,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose a network',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your address accepts every token listed on the network you pick.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...chains.map(
                    (c) => _ChainCard(
                      key: Key('crypto_chain_${c.chain.toLowerCase()}'),
                      chain: c,
                      isSelected: c.chain == chain.chain,
                      onTap: () => setState(() => _selectedChain = c.chain),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildAddressSection(chain),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              key: const Key('crypto_deposit_error'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection(CryptoChainModel chain) {
    final addressAsync = ref.watch(cryptoAddressProvider(chain.chain));

    return addressAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (err, _) => _buildError(err.toString()),
      data: (address) {
        if (!address.isReady) {
          return _buildProvisioning(chain);
        }
        return _buildAddressCard(chain, address);
      },
    );
  }

  Widget _buildProvisioning(CryptoChainModel chain) {
    return Container(
      key: const Key('crypto_address_provisioning'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            'Creating your ${chain.displayName} address',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This usually takes a few seconds.',
            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          TextButton(
            key: const Key('crypto_address_refresh_button'),
            onPressed: () => ref.invalidate(cryptoAddressProvider(chain.chain)),
            child: const Text('Check again'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(CryptoChainModel chain, CryptoAddressModel address) {
    final assets = address.supportedAssets.isNotEmpty
        ? address.supportedAssets
        : chain.assets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The testnet warning comes first: a user who sends real funds to a
        // testnet address has lost them, and nothing about the address itself
        // reveals which it is.
        if (address.isTestnet) ...[
          Container(
            key: const Key('crypto_testnet_warning'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Test network only. This address is on ${chain.displayName} '
                    'TESTNET — real funds sent here cannot be recovered.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Send ${assets.join(' or ')}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    key: const Key('crypto_address_network_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${chain.displayName} · ${address.network}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryActive,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                address.address!,
                key: const Key('crypto_deposit_address_text'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  key: const Key('crypto_copy_address_button'),
                  onPressed: () => _copyAddress(address.address!),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy address'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Only send ${assets.join(' or ')} on ${chain.displayName}. '
                  'Anything sent on another network is lost. Your balance updates '
                  'once the deposit is confirmed on-chain.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChainCard extends StatelessWidget {
  final CryptoChainModel chain;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChainCard({
    super.key,
    required this.chain,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.hairline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chain.displayName,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Accepts ${chain.assetsLabel}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chain.isTestnet)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'TESTNET',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded,
                      size: 20, color: AppColors.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
