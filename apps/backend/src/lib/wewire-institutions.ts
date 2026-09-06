/**
 * Payout institutions (banks and mobile money operators) as served by WeWire's
 * GET /v1/banks?currency=<GHS|NGN> endpoint.
 *
 * Verified against the sandbox on 2026-09-05: the endpoint requires a currency
 * query parameter (`currency must be one of the following values: GHS, NGN`)
 * and returns entries shaped { code, name, types[], country, channel, currency }
 * where channel is 'BANK' or 'MOMO'.
 */

export type PayoutChannel = 'MOBILE_MONEY' | 'BANK';

export interface WeWireInstitution {
  /** WeWire sort code, e.g. 'GCB', 'ECO', 'MTN'. Sent as accountCode on payout. */
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

let cached: { key: string; institutions: WeWireInstitution[]; timestamp: number } | null = null;
const CACHE_TTL_MS = 60 * 60 * 1000; // institution lists change rarely

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
 * memory. Falls back to the verified Ghana list when WeWire is unavailable, so
 * a picker never renders empty.
 */
export async function getWeWireInstitutions(
  currency = 'GHS',
  forceRefresh = false
): Promise<WeWireInstitution[]> {
  const key = currency.trim().toUpperCase();
  const now = Date.now();

  if (!forceRefresh && cached && cached.key === key && now - cached.timestamp < CACHE_TTL_MS) {
    return cached.institutions;
  }

  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using the fallback institution list');
    return key === 'GHS' ? GHANA_INSTITUTIONS : [];
  }

  try {
    const res = await fetch(`${baseUrl}/v1/banks?currency=${encodeURIComponent(key)}`, {
      headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
    });

    if (!res.ok) {
      console.warn(`WeWire /v1/banks returned ${res.status}; using the fallback institution list`);
      return key === 'GHS' ? GHANA_INSTITUTIONS : [];
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
      return key === 'GHS' ? GHANA_INSTITUTIONS : [];
    }

    cached = { key, institutions, timestamp: now };
    return institutions;
  } catch (err: any) {
    console.warn('Failed to fetch WeWire institutions:', err?.message || err);
    return key === 'GHS' ? GHANA_INSTITUTIONS : [];
  }
}

/** Aliases the app has historically used for the mobile money operators. */
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

/**
 * Resolves user-facing input ('MTN', 'GCB', 'GCB Bank', 'Ecobank', 'Stanbic')
 * to a WeWire institution. Matches the sort code first, then the institution
 * name, then a leading-word match so short display names still resolve.
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
  const pool = institutions.length > 0 ? institutions : GHANA_INSTITUTIONS;

  const aliasCode = MOMO_ALIASES[upper];
  const candidates = [
    (i: WeWireInstitution) => aliasCode !== undefined && i.code.toUpperCase() === aliasCode,
    (i: WeWireInstitution) => i.code.toUpperCase() === upper,
    (i: WeWireInstitution) => i.name.toUpperCase() === upper,
    (i: WeWireInstitution) => i.name.toUpperCase().startsWith(upper),
    (i: WeWireInstitution) => i.name.toUpperCase().includes(upper),
  ];

  for (const matches of candidates) {
    const found = pool.find(matches);
    if (found) {
      return {
        ...found,
        accountType: found.channel === 'BANK' ? 'BANK_ACCOUNT' : 'MOBILE_MONEY',
      };
    }
  }

  throw new Error(
    `Unsupported network or bank: "${raw}". Call GET /api/banks for the list of supported institutions.`
  );
}

/**
 * Ghana bank account numbers run roughly 8-20 digits depending on the bank, so
 * the check stays deliberately loose: digits only, within that range.
 */
export function normalizeBankAccountNumber(input: string): string | null {
  const digits = (input ?? '').replace(/\D/g, '');
  if (digits.length < 8 || digits.length > 20) return null;
  return digits;
}
