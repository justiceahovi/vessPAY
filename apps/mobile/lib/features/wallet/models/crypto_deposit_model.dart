/// A blockchain network a deposit address can be issued on.
///
/// The address belongs to the *chain*, not to a token: one Base address
/// receives both USDC and GHST. So the user picks a network, and [assets] is
/// everything that address can accept.
class CryptoChainModel {
  /// Provider code, e.g. 'BASE'.
  final String chain;

  /// MAINNET or TESTNET, as reported by the provider.
  ///
  /// Never inferred locally: it is decided by the API key, and showing a
  /// testnet address as though it were mainnet would lose real funds.
  final String network;

  /// Tokens this one address accepts, e.g. ['USDC', 'GHST'].
  final List<String> assets;

  /// Human name, e.g. 'Base'.
  final String displayName;

  const CryptoChainModel({
    required this.chain,
    required this.network,
    required this.assets,
    required this.displayName,
  });

  bool get isTestnet => network.toUpperCase() == 'TESTNET';

  /// e.g. 'USDC or GHST'.
  String get assetsLabel {
    if (assets.isEmpty) return '';
    if (assets.length == 1) return assets.first;
    return '${assets.sublist(0, assets.length - 1).join(', ')} or ${assets.last}';
  }

  factory CryptoChainModel.fromJson(Map<String, dynamic> json) {
    return CryptoChainModel(
      chain: (json['chain'] ?? '').toString().toUpperCase(),
      network: (json['network'] ?? 'UNKNOWN').toString().toUpperCase(),
      assets: (json['assets'] as List?)
              ?.map((a) => a.toString().toUpperCase())
              .toList() ??
          const [],
      displayName: (json['displayName'] ?? json['chain'] ?? '').toString(),
    );
  }
}

/// Where a user is in getting a deposit address for a chain.
enum CryptoAddressState {
  /// The address exists and can receive a deposit.
  ready,

  /// Requested, but the provider is still issuing it. Poll until ready.
  provisioning,

  /// The user has to finish verification before an address can be issued.
  verificationRequired,

  /// The provider cannot issue one right now.
  unavailable,
}

class CryptoAddressModel {
  final CryptoAddressState state;
  final String chain;
  final String network;

  /// Null while the address is still being issued.
  final String? address;
  final List<String> supportedAssets;
  final String? reason;

  const CryptoAddressModel({
    required this.state,
    required this.chain,
    required this.network,
    this.address,
    this.supportedAssets = const [],
    this.reason,
  });

  bool get isReady => state == CryptoAddressState.ready && address != null;
  bool get isTestnet => network.toUpperCase() == 'TESTNET';

  factory CryptoAddressModel.fromJson(Map<String, dynamic> json) {
    final address = json['address'] as String?;
    final rawState = (json['state'] ?? '').toString().toUpperCase();
    return CryptoAddressModel(
      state: rawState == 'READY' && address != null
          ? CryptoAddressState.ready
          : CryptoAddressState.provisioning,
      chain: (json['chain'] ?? '').toString().toUpperCase(),
      network: (json['network'] ?? 'UNKNOWN').toString().toUpperCase(),
      address: address,
      supportedAssets: (json['supportedAssets'] as List?)
              ?.map((a) => a.toString().toUpperCase())
              .toList() ??
          const [],
    );
  }

  factory CryptoAddressModel.unavailable(String chain, String reason) {
    return CryptoAddressModel(
      state: CryptoAddressState.unavailable,
      chain: chain,
      network: 'UNKNOWN',
      reason: reason,
    );
  }

  factory CryptoAddressModel.verificationRequired(String chain) {
    return CryptoAddressModel(
      state: CryptoAddressState.verificationRequired,
      chain: chain,
      network: 'UNKNOWN',
      reason: 'Complete verification before requesting a deposit address',
    );
  }
}
