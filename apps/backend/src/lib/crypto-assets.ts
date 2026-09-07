/**
 * Crypto deposit assets and chains, as served by WeWire's
 * GET /v1/wallets/supported-assets.
 *
 * Verified against the stage sandbox on 2026-09-07. Two things about the shape
 * drive everything downstream:
 *
 *  - A deposit address belongs to a **chain**, not to an asset. One BASE
 *    address receives both USDC and GHST, so the user picks a network and gets
 *    one address for every asset that network carries.
 *  - `network` is derived from the API key: a test key can only ever issue
 *    TESTNET addresses. It is never assumed here, always read back from the
 *    provider, because showing a testnet address as if it were mainnet would
 *    lose real funds.
 *
 * Note the sandbox lists no USDT even though the sub-customer wallet-currency
 * enum accepts it, so USDT is deliberately not offered until it appears here.
 */

export interface CryptoAsset {
  /** Token symbol, e.g. 'USDC'. */
  asset: string;
  /** Chain the token is carried on, e.g. 'BASE'. */
  chain: string;
  /** MAINNET | TESTNET -- decided by the API key, never by us. */
  network: string;
  /** Provider's display label, e.g. 'USDC on BASE (testnet)'. */
  label: string;
}

/** A chain the user can be given a deposit address on. */
export interface CryptoChain {
  chain: string;
  network: string;
  /** Every asset this one address can receive. */
  assets: string[];
  /** Human name for the network, e.g. 'Base'. */
  displayName: string;
}

/**
 * Display names for the chains WeWire serves. A chain missing from here still
 * works -- it just shows its raw code -- so a new provider chain never breaks
 * the picker.
 */
const CHAIN_DISPLAY_NAMES: Record<string, string> = {
  BASE: 'Base',
  ETH: 'Ethereum',
  ETHEREUM: 'Ethereum',
  SOLANA: 'Solana',
  TRON: 'Tron',
  POLYGON: 'Polygon',
};

/**
 * The asset/chain pairs the sandbox served on 2026-09-07, used only when the
 * endpoint is unreachable. `network` is deliberately absent: it depends on the
 * API key, so a cached-but-stale network is worse than none. Callers must treat
 * a fallback entry as "chain exists, network unknown" and say so in the UI.
 */
export const FALLBACK_CRYPTO_PAIRS: Array<{ asset: string; chain: string }> = [
  { asset: 'USDC', chain: 'BASE' },
  { asset: 'GHST', chain: 'BASE' },
  { asset: 'USDC', chain: 'ETH' },
  { asset: 'USDC', chain: 'SOLANA' },
  { asset: 'USDC', chain: 'TRON' },
];

let cached: { assets: CryptoAsset[]; timestamp: number } | null = null;
const CACHE_TTL_MS = 60 * 60 * 1000; // the asset list changes rarely

const FAILURE_CACHE_TTL_MS = 60 * 1000;
let lastFailureAt: number | null = null;

function fallbackAssets(): CryptoAsset[] {
  return FALLBACK_CRYPTO_PAIRS.map(({ asset, chain }) => ({
    asset,
    chain,
    // Unknown rather than guessed -- see the note on FALLBACK_CRYPTO_PAIRS.
    network: 'UNKNOWN',
    label: `${asset} on ${chain}`,
  }));
}

/**
 * Fetches the asset/chain pairs WeWire can issue a deposit address for,
 * cached in memory. Falls back to the bundled pairs when the endpoint is
 * unreachable, so a chain picker is never empty.
 */
export async function getSupportedCryptoAssets(
  forceRefresh = false
): Promise<CryptoAsset[]> {
  const now = Date.now();

  if (!forceRefresh && cached && now - cached.timestamp < CACHE_TTL_MS) {
    return cached.assets;
  }

  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (
    process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com'
  ).replace(/\/$/, '');

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using the fallback crypto asset list');
    return fallbackAssets();
  }

  if (
    !forceRefresh &&
    lastFailureAt !== null &&
    now - lastFailureAt < FAILURE_CACHE_TTL_MS
  ) {
    return fallbackAssets();
  }

  try {
    const res = await fetch(`${baseUrl}/v1/wallets/supported-assets`, {
      headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
    });

    if (!res.ok) {
      console.warn(
        `WeWire /v1/wallets/supported-assets returned ${res.status}; using the fallback list`
      );
      lastFailureAt = now;
      return fallbackAssets();
    }

    const body: any = await res.json();
    const rows: any[] = Array.isArray(body) ? body : Array.isArray(body?.data) ? body.data : [];

    const assets: CryptoAsset[] = rows
      .filter((row) => row?.asset && row?.chain)
      .map((row) => ({
        asset: String(row.asset).trim().toUpperCase(),
        chain: String(row.chain).trim().toUpperCase(),
        network: String(row.network ?? 'UNKNOWN').trim().toUpperCase(),
        label: String(row.label ?? `${row.asset} on ${row.chain}`).trim(),
      }));

    if (assets.length === 0) return fallbackAssets();

    cached = { assets, timestamp: now };
    lastFailureAt = null;
    return assets;
  } catch (err: any) {
    console.warn('Failed to fetch WeWire supported assets:', err?.message || err);
    lastFailureAt = now;
    return fallbackAssets();
  }
}

/**
 * The same list collapsed to one entry per chain, which is the shape the
 * deposit UI needs: the user chooses a network, and the resulting address
 * accepts every asset listed against it.
 */
export async function getSupportedCryptoChains(
  forceRefresh = false
): Promise<CryptoChain[]> {
  const assets = await getSupportedCryptoAssets(forceRefresh);
  const byChain = new Map<string, CryptoChain>();

  for (const entry of assets) {
    const existing = byChain.get(entry.chain);
    if (existing) {
      if (!existing.assets.includes(entry.asset)) existing.assets.push(entry.asset);
      continue;
    }
    byChain.set(entry.chain, {
      chain: entry.chain,
      network: entry.network,
      assets: [entry.asset],
      displayName: CHAIN_DISPLAY_NAMES[entry.chain] || entry.chain,
    });
  }

  return [...byChain.values()];
}

/** Whether WeWire can issue an address on this chain. */
export async function isSupportedChain(chain: string): Promise<boolean> {
  const wanted = (chain ?? '').trim().toUpperCase();
  if (!wanted) return false;
  return (await getSupportedCryptoChains()).some((c) => c.chain === wanted);
}

/** Comma separated chain codes, for validation error messages. */
export async function supportedChainCodes(): Promise<string> {
  return (await getSupportedCryptoChains()).map((c) => c.chain).join(', ');
}

// ---------------------------------------------------------------------------
// Deposit addresses
//
// Verified against the stage sandbox on 2026-09-07:
//   POST /v1/subcustomers/{id}/addresses  { chains: [...] }  -> 202
//
// There is no GET counterpart -- it 404s -- but the POST is idempotent: asking
// again for a chain already provisioned returns the existing address rather
// than issuing a second one. So this one call is both "list" and "create".
//
// Issuance is asynchronous, exactly like fiat virtual accounts: the first
// response carries status REQUESTED and address null, and the address appears
// on a later call. Unknown chains are ignored silently (a bad chain returns an
// empty array rather than an error), so callers must validate the chain first.
// ---------------------------------------------------------------------------

export interface CryptoDepositAddress {
  /** WeWire's address record id. */
  id: string;
  chain: string;
  /** MAINNET | TESTNET, from the provider. */
  network: string;
  /** Null until issuance completes. */
  address: string | null;
  /** REQUESTED | ACTIVE | ... */
  status: string;
  /** Every asset this address can receive. */
  supportedAssets: string[];
  label?: string | null;
  /** True only when the address can actually receive a deposit. */
  isActive: boolean;
}

function toDepositAddress(row: any): CryptoDepositAddress {
  const status = String(row?.status ?? 'UNKNOWN').toUpperCase();
  const address = row?.address ? String(row.address) : null;
  return {
    id: String(row?.id ?? ''),
    chain: String(row?.chain ?? '').toUpperCase(),
    network: String(row?.network ?? 'UNKNOWN').toUpperCase(),
    address,
    status,
    supportedAssets: Array.isArray(row?.supportedAssets)
      ? row.supportedAssets.map((a: any) => String(a).toUpperCase())
      : [],
    label: row?.label ?? null,
    // An address is only usable once the provider has actually minted one.
    isActive: status === 'ACTIVE' && !!address,
  };
}

/**
 * Issues, or returns, the deposit address for `chain` on a sub-customer.
 *
 * Idempotent by virtue of the provider's own behaviour, so it is safe to call
 * on every render of the deposit screen. Returns null when WeWire is not
 * configured, so callers can degrade rather than throw.
 */
export async function resolveCryptoDepositAddress(
  subCustomerId: string,
  chain: string
): Promise<CryptoDepositAddress | null> {
  const apiKey = process.env.WEWIRE_API_KEY;
  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; cannot issue a crypto deposit address');
    return null;
  }

  const wanted = (chain ?? '').trim().toUpperCase();
  if (!wanted) throw new Error('A chain is required to issue a deposit address');

  // The endpoint ignores chains it does not know, so an unchecked chain would
  // come back as an empty array and read as "provider is broken".
  if (!(await isSupportedChain(wanted))) {
    throw new Error(
      `Chain '${wanted}' is not supported. Supported chains: ${await supportedChainCodes()}`
    );
  }

  const baseUrl = (
    process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com'
  ).replace(/\/$/, '');

  const res = await fetch(`${baseUrl}/v1/subcustomers/${subCustomerId}/addresses`, {
    method: 'POST',
    headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ chains: [wanted] }),
  });

  const text = await res.text();
  let data: any;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }

  if (!res.ok) {
    const message =
      (typeof data === 'object' && (data?.error?.message || data?.message)) ||
      (typeof data === 'string' && data) ||
      JSON.stringify(data);
    throw new Error(`WeWire address issuance failed: ${message} (Status: ${res.status})`);
  }

  const rows: any[] = Array.isArray(data) ? data : Array.isArray(data?.data) ? data.data : [];
  const match = rows.find(
    (row) => String(row?.chain ?? '').toUpperCase() === wanted
  );

  return match ? toDepositAddress(match) : null;
}
