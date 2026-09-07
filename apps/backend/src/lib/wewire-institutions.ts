/**
 * Payout institutions (banks and mobile money operators) as served by WeWire's
 * GET /v1/banks?currency=<GHS|NGN> endpoint.
 *
 * Verified against the sandbox on 2026-09-05: the endpoint requires a currency
 * query parameter (`currency must be one of the following values: GHS, NGN`)
 * and returns entries shaped { code, name, types[], country, channel, currency }
 * where channel is 'BANK' or 'MOMO'.
 *
 * Re-verified 2026-09-07: GHS returns 28 institutions across both channels,
 * NGN returns 422 and every one of them is a BANK with a 6-digit NIP code.
 */

import { getCorridor } from './corridors';

export type PayoutChannel = 'MOBILE_MONEY' | 'BANK';

export interface WeWireInstitution {
  /** WeWire sort code, e.g. 'GCB', 'ECO', 'MTN', or an NGN NIP code '000013'. */
  code: string;
  name: string;
  /** Payout channel this institution is reached through. */
  channel: PayoutChannel;
  currency: string;
  country: string;
}

export interface ResolvedInstitution extends WeWireInstitution {
  /** accountDetails.type used when registering a beneficiary. */
  accountType: 'MOBILE_MONEY' | 'BANK_ACCOUNT';
}

/// Cached per currency: the two corridors are queried alternately as users
/// switch destination, and a single shared slot would evict on every switch.
const cached = new Map<string, { institutions: WeWireInstitution[]; timestamp: number }>();
const CACHE_TTL_MS = 60 * 60 * 1000; // institution lists change rarely

/// A failed fetch is cached briefly too: name lookups call through here on every
/// keystroke-debounce, and an unavailable endpoint should not be retried each time.
const FAILURE_CACHE_TTL_MS = 60 * 1000;
const lastFailure = new Map<string, number>();

/**
 * Ghana institutions as returned by the sandbox, used when the API key is not
 * configured or the endpoint is unreachable. Codes are WeWire's own sort codes.
 */
export const GHANA_INSTITUTIONS: WeWireInstitution[] = [
  { code: 'MTN', name: 'MTN Mobile Money', channel: 'MOBILE_MONEY', currency: 'GHS', country: 'GH' },
  { code: 'VOD', name: 'Telecel Cash', channel: 'MOBILE_MONEY', currency: 'GHS', country: 'GH' },
  { code: 'ATM', name: 'AirtelTigo Money', channel: 'MOBILE_MONEY', currency: 'GHS', country: 'GH' },
  { code: 'BBG', name: 'ABSA BANK (GH) LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'ACC', name: 'ACCESS BANK LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'ADB', name: 'AGRICULTURAL DEVELOPMENT BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'APB', name: 'ARB APEX BANK LIMITED', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'BOA', name: 'BANK OF AFRICA', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'BOG', name: 'BANK OF GHANA', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'CAL', name: 'CAL BANK LIMITED', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'CBG', name: 'CONSOLIDATED BANK GHANA', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'ECO', name: 'ECOBANK GHANA LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'FBN', name: 'FBN Bank LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'FBL', name: 'FIDELITY BANK LIMITED', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'FAB', name: 'FIRST ATLANTIC BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'FNB', name: 'FIRST NATIONAL BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'GCB', name: 'GCB BANK LIMITED', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'GTB', name: 'GUARANTY TRUST BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'NIB', name: 'NATIONAL INVESTMENT BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'SSB', name: 'OmniBSIC GHANA', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'PRU', name: 'PRUDENTIAL BANK LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'REP', name: 'REPUBLIC BANK LIMITED', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'SGB', name: 'SOCIETE GENERALE BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'STA', name: 'STANBIC BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'SCB', name: 'STANDARD CHARTERED BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'UBA', name: 'UNITED BANK OF AFRICA', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'UMB', name: 'UNIVERSAL MERCHANT BANK', channel: 'BANK', currency: 'GHS', country: 'GH' },
  { code: 'ZEN', name: 'ZENITH BANK GHANA LTD', channel: 'BANK', currency: 'GHS', country: 'GH' },
];

/**
 * The Nigerian institutions users actually reach for, out of the 422 the
 * endpoint serves. Only a fallback for when WeWire is unreachable -- the live
 * list is always preferred -- so it carries the majors plus the wallets that
 * Nigerians think of as mobile money but which settle as bank accounts.
 * Codes are NIP codes, verified against the sandbox on 2026-09-07.
 */
export const NIGERIA_INSTITUTIONS: WeWireInstitution[] = [
  { code: '100004', name: 'OPAY', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '100033', name: 'PALMPAY', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '090405', name: 'MONIEPOINT Microfinance Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '090267', name: 'KUDA Microfinance Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '100002', name: 'PAGA', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000014', name: 'ACCESS Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000013', name: 'GTBANK PLC', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000015', name: 'ZENITH Bank PLC', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000016', name: 'FIRST Bank OF NIGERIA', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000004', name: 'UNITED Bank FOR AFRICA', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000012', name: 'STANBICIBTC Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000007', name: 'FIDELITY Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000017', name: 'WEMA Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000018', name: 'UNION Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000003', name: 'FCMB', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000001', name: 'STERLING Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000010', name: 'ECOBANK Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000023', name: 'PROVIDUS Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000011', name: 'UNITY Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000002', name: 'KEYSTONE Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000008', name: 'POLARIS Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
  { code: '000006', name: 'JAIZ Bank', channel: 'BANK', currency: 'NGN', country: 'NG' },
];

/** The bundled list for a currency, or [] for a corridor we do not serve. */
export function fallbackInstitutions(currency: string): WeWireInstitution[] {
  const key = currency.trim().toUpperCase();
  if (key === 'GHS') return GHANA_INSTITUTIONS;
  if (key === 'NGN') return NIGERIA_INSTITUTIONS;
  return [];
}

function normalizeChannel(raw: unknown): PayoutChannel {
  const value = String(raw ?? '').trim().toUpperCase();
  // WeWire labels mobile money operators 'MOMO' in the institution list, but the
  // disbursement endpoint expects 'MOBILE_MONEY'.
  if (value === 'MOMO' || value === 'MOBILE_MONEY' || value === 'MOBILEMONEY') {
    return 'MOBILE_MONEY';
  }
  return 'BANK';
}

/**
 * Fetches the payout institutions for a currency from GET /v1/banks, cached in
 * memory per currency. Falls back to the bundled list for that corridor when
 * WeWire is unavailable, so a picker never renders empty.
 */
export async function getWeWireInstitutions(
  currency = 'GHS',
  forceRefresh = false
): Promise<WeWireInstitution[]> {
  const key = currency.trim().toUpperCase();
  const now = Date.now();

  // GET /v1/banks serves GHS and NGN only. Asking for anything else is a
  // guaranteed 400, and this runs on every keystroke-debounce behind recipient
  // lookup, so a corridor the endpoint does not cover never reaches the wire.
  if (!getCorridor(key).hasInstitutionList) {
    return fallbackInstitutions(key);
  }

  const hit = cached.get(key);
  if (!forceRefresh && hit && now - hit.timestamp < CACHE_TTL_MS) {
    return hit.institutions;
  }

  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using the fallback institution list');
    return fallbackInstitutions(key);
  }

  const failedAt = lastFailure.get(key);
  if (!forceRefresh && failedAt !== undefined && now - failedAt < FAILURE_CACHE_TTL_MS) {
    return fallbackInstitutions(key);
  }

  try {
    const res = await fetch(`${baseUrl}/v1/banks?currency=${encodeURIComponent(key)}`, {
      headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
    });

    if (!res.ok) {
      console.warn(`WeWire /v1/banks returned ${res.status}; using the fallback institution list`);
      lastFailure.set(key, now);
      return fallbackInstitutions(key);
    }

    const body: any = await res.json();
    const rows: any[] = Array.isArray(body) ? body : Array.isArray(body?.data) ? body.data : [];

    const institutions: WeWireInstitution[] = rows
      .filter((row) => row?.code && (row?.name || row?.bankName))
      .map((row) => ({
        code: String(row.code).trim(),
        name: String(row.name ?? row.bankName).trim(),
        channel: normalizeChannel(row.channel),
        currency: String(row.currency ?? key).trim().toUpperCase(),
        country: String(row.country ?? '').trim().toUpperCase(),
      }));

    if (institutions.length === 0) {
      return fallbackInstitutions(key);
    }

    cached.set(key, { institutions, timestamp: now });
    lastFailure.delete(key);
    return institutions;
  } catch (err: any) {
    console.warn('Failed to fetch WeWire institutions:', err?.message || err);
    lastFailure.set(key, now);
    return fallbackInstitutions(key);
  }
}

/** Aliases the app has historically used for the Ghanaian mobile money operators. */
const MOMO_ALIASES: Record<string, string> = {
  MTN: 'MTN',
  'MTN MOBILE MONEY': 'MTN',
  MOMO: 'MTN',
  TELECEL: 'VOD',
  'TELECEL CASH': 'VOD',
  VODAFONE: 'VOD',
  'VODAFONE CASH': 'VOD',
  VOD: 'VOD',
  AIRTELTIGO: 'ATM',
  'AIRTELTIGO MONEY': 'ATM',
  AIRTEL: 'ATM',
  TIGO: 'ATM',
  ATM: 'ATM',
};

function toResolved(found: WeWireInstitution): ResolvedInstitution {
  return {
    ...found,
    accountType: found.channel === 'BANK' ? 'BANK_ACCOUNT' : 'MOBILE_MONEY',
  };
}

/**
 * Resolves user-facing input ('MTN', 'GCB', 'GCB Bank', '000013', 'Zenith') to
 * a WeWire institution for a corridor.
 *
 * Exact code and exact name matches win outright. Partial name matches are only
 * accepted when they are *unambiguous*: across Nigeria's 422 institutions a
 * substring like 'ACCESS' hits both 'ACCESS Bank' and 'ACCESSMONEY', and
 * silently picking the first would pay the wrong institution.
 */
export async function resolveInstitution(
  input: string,
  currency = 'GHS'
): Promise<ResolvedInstitution> {
  const raw = (input ?? '').trim();
  if (!raw) {
    throw new Error('A network or bank is required');
  }

  const upper = raw.toUpperCase();
  const institutions = await getWeWireInstitutions(currency);
  const pool = institutions.length > 0 ? institutions : fallbackInstitutions(currency);

  if (pool.length === 0) {
    throw new Error(`No payout institutions are available for ${currency}`);
  }

  // 1. Exact matches, in order of how specific they are.
  const aliasCode = MOMO_ALIASES[upper];
  const exact = [
    (i: WeWireInstitution) => aliasCode !== undefined && i.code.toUpperCase() === aliasCode,
    (i: WeWireInstitution) => i.code.toUpperCase() === upper,
    (i: WeWireInstitution) => i.name.toUpperCase() === upper,
  ];

  for (const matches of exact) {
    const found = pool.find(matches);
    if (found) return toResolved(found);
  }

  // 2. Partial matches, accepted only when exactly one institution matches.
  const partial = [
    (i: WeWireInstitution) => i.name.toUpperCase().startsWith(upper),
    (i: WeWireInstitution) => i.name.toUpperCase().includes(upper),
  ];

  for (const matches of partial) {
    const found = pool.filter(matches);
    if (found.length === 1) return toResolved(found[0]);
    if (found.length > 1) {
      const names = found.slice(0, 5).map((i) => `${i.name} (${i.code})`).join(', ');
      throw new Error(
        `"${raw}" matches ${found.length} institutions for ${currency}: ${names}. ` +
          'Send the institution code instead -- call GET /api/banks for the list.'
      );
    }
  }

  throw new Error(
    `Unsupported network or bank: "${raw}". Call GET /api/banks?currency=${currency} for the list of supported institutions.`
  );
}

/**
 * Normalizes a bank account number against the corridor's own rule: Ghana runs
 * roughly 8-20 digits depending on the bank, Nigeria's NUBAN is exactly 10.
 * Defaults to the Ghana rule so pre-corridor callers are unchanged.
 */
export function normalizeBankAccountNumber(input: string, currency = 'GHS'): string | null {
  const { min, max } = getCorridor(currency).accountNumber;
  const digits = (input ?? '').replace(/\D/g, '');
  if (digits.length < min || digits.length > max) return null;
  return digits;
}

/** Human-readable form of the corridor's account number rule, for error text. */
export function accountNumberRuleText(currency = 'GHS'): string {
  const { min, max } = getCorridor(currency).accountNumber;
  return min === max ? `${min} digits` : `${min}-${max} digits`;
}
