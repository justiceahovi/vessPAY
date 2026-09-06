import {
  getWeWireInstitutions,
  normalizeBankAccountNumber,
  resolveInstitution,
  type PayoutChannel,
} from './wewire-institutions';
export {
  getWeWireInstitutions,
  resolveInstitution,
  normalizeBankAccountNumber,
  GHANA_INSTITUTIONS,
} from './wewire-institutions';
export type { PayoutChannel, WeWireInstitution, ResolvedInstitution } from './wewire-institutions';

import dotenv from 'dotenv';
dotenv.config();

export interface CreateSubCustomerParams {
  firstName: string;
  lastName: string;
  email: string;
  country?: string | null;
  referenceId?: string;
}

export interface WeWireSubCustomerResponse {
  id: string;
  readableId?: string;
  name: string;
  email: string;
  country: string;
  status: string;
  type: string;
  purpose: string[];
  onboardingStatus: string;
  enhancedKycStatus: string;
}

/**
 * Normalizes input country or nationality string to ISO 3166-1 alpha-3 code.
 * WeWire strictly requires a 3-letter ISO code (e.g. GBR, USA, GHA, NGA).
 */
export function toAlpha3Country(countryInput?: string | null): string {
  if (!countryInput || typeof countryInput !== 'string') return 'GBR';
  const c = countryInput.trim().toUpperCase();

  const map: Record<string, string> = {
    // UK / Britain
    GB: 'GBR',
    GBR: 'GBR',
    UK: 'GBR',
    'UNITED KINGDOM': 'GBR',
    BRITAIN: 'GBR',
    BRITISH: 'GBR',
    ENGLAND: 'GBR',
    SCOTLAND: 'GBR',
    WALES: 'GBR',

    // USA
    US: 'USA',
    USA: 'USA',
    'UNITED STATES': 'USA',
    'UNITED STATES OF AMERICA': 'USA',
    AMERICAN: 'USA',

    // Ghana
    GH: 'GHA',
    GHA: 'GHA',
    GHANA: 'GHA',
    GHANAIAN: 'GHA',

    // Nigeria
    NG: 'NGA',
    NGA: 'NGA',
    NIGERIA: 'NGA',
    NIGERIAN: 'NGA',

    // Canada
    CA: 'CAN',
    CAN: 'CAN',
    CANADA: 'CAN',
    CANADIAN: 'CAN',

    // Germany
    DE: 'DEU',
    DEU: 'DEU',
    GERMANY: 'DEU',
    GERMAN: 'DEU',

    // France
    FR: 'FRA',
    FRA: 'FRA',
    FRANCE: 'FRA',
    FRENCH: 'FRA',

    // South Africa
    ZA: 'ZAF',
    ZAF: 'ZAF',
    'SOUTH AFRICA': 'ZAF',

    // Kenya
    KE: 'KEN',
    KEN: 'KEN',
    KENYA: 'KEN',
  };

  if (map[c]) return map[c];
  if (/^[A-Z]{3}$/.test(c)) return c;
  return 'GBR';
}

/**
 * Provides demo/simplified address and phone metadata for a country.
 * Used for hackathon demo KYC submissions.
 */
function getDemoKycMetadata(alpha3: string) {
  switch (alpha3) {
    case 'USA':
      return {
        addressLine1: '350 Fifth Avenue',
        city: 'New York',
        stateProvince: 'NY',
        postalCode: '10118',
        country: 'USA',
        phoneNumber: '+12025550143',
      };
    case 'GHA':
      return {
        addressLine1: 'Liberation Road, Airport Residential Area',
        city: 'Accra',
        stateProvince: 'Greater Accra',
        postalCode: 'GA-039-1234',
        country: 'GHA',
        phoneNumber: '+233241234567',
      };
    case 'NGA':
      return {
        addressLine1: '1 Adeola Odeku Street, Victoria Island',
        city: 'Lagos',
        stateProvince: 'Lagos',
        postalCode: '101241',
        country: 'NGA',
        phoneNumber: '+2348031234567',
      };
    case 'CAN':
      return {
        addressLine1: '100 King Street West',
        city: 'Toronto',
        stateProvince: 'ON',
        postalCode: 'M5X 1A9',
        country: 'CAN',
        phoneNumber: '+14165550123',
      };
    case 'GBR':
    default:
      return {
        addressLine1: '10 Downing Street',
        city: 'London',
        stateProvince: 'London',
        postalCode: 'SW1A 2AA',
        country: 'GBR',
        phoneNumber: '+447123456789',
      };
  }
}

/**
 * Creates a WeWire sub-customer for an individual user per Section 8 & OpenAPI spec.
 * Returns the created WeWire sub-customer record including its `id`.
 */
export async function createWeWireSubCustomer(
  params: CreateSubCustomerParams
): Promise<WeWireSubCustomerResponse> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using fallback subcustomer ID');
    return {
      id: `sub_stub_${Date.now()}`,
      name: `${params.firstName} ${params.lastName}`,
      email: params.email,
      country: toAlpha3Country(params.country),
      status: 'ACTIVE',
      type: 'INDIVIDUAL',
      purpose: ['PAYOUT', 'COLLECTION'],
      onboardingStatus: 'DRAFT',
      enhancedKycStatus: 'NOT_STARTED',
    };
  }

  const alpha3Country = toAlpha3Country(params.country);
  const endpoint = `${baseUrl}/v1/subcustomers`;

  const payload = {
    firstName: params.firstName.trim(),
    lastName: params.lastName.trim(),
    email: params.email.trim().toLowerCase(),
    country: alpha3Country,
    type: 'INDIVIDUAL',
    purpose: ['PAYOUT', 'COLLECTION'],
    referenceId: params.referenceId || undefined,
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  let data: any;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }

  if (!response.ok) {
    const errMsg = typeof data === 'object' && data?.error?.message
      ? data.error.message
      : typeof data === 'object' && data?.message
      ? data.message
      : JSON.stringify(data);
    throw new Error(`Failed to create WeWire sub-customer: ${errMsg} (Status: ${response.status})`);
  }

  return data as WeWireSubCustomerResponse;
}

/**
 * Submits the canned simplified/demo KYC dossier for an individual sub-customer
 * in the WeWire sandbox, moving onboardingStatus off DRAFT.
 *
 * Only ever called from the explicit demo-submit endpoint, never during
 * registration, so the outcome is reported back rather than swallowed: a
 * `submitted: false` result means the sandbox is not wired up, and a rejected
 * submission throws.
 */
export async function submitSimplifiedKyc(
  subCustomerId: string,
  params: {
    firstName: string;
    lastName: string;
    country?: string | null;
  }
): Promise<{ submitted: boolean; reason?: string }> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey || subCustomerId.startsWith('sub_stub_')) {
    return {
      submitted: false,
      reason: 'WeWire sandbox is not configured for this environment',
    };
  }

  const alpha3 = toAlpha3Country(params.country);
  const meta = getDemoKycMetadata(alpha3);
  const endpoint = `${baseUrl}/v1/subcustomers/${subCustomerId}/kyc`;

  const kycPayload = {
    type: 'INDIVIDUAL',
    data: {
      firstName: params.firstName.trim(),
      lastName: params.lastName.trim(),
      gender: 'M',
      dateOfBirth: '1990-01-01',
      address: {
        addressLine1: meta.addressLine1,
        city: meta.city,
        stateProvince: meta.stateProvince,
        postalCode: meta.postalCode,
        country: meta.country,
      },
      nationality: meta.country,
      phoneNumber: meta.phoneNumber,
      idType: 'PASSPORT',
      // Standard 1x1 transparent PNG data URI for hackathon demo
      idFileFront:
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      idIssuingCountry: meta.country,
    },
  };

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(kycPayload),
  });

  if (!res.ok) {
    const text = await res.text();
    let data: any;
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
    const errMsg =
      typeof data === 'object' && data?.error?.message
        ? data.error.message
        : typeof data === 'object' && data?.message
        ? data.message
        : text;
    throw new Error(`Simplified KYC submission failed: ${errMsg} (Status: ${res.status})`);
  }

  return { submitted: true };
}

/**
 * Retrieves the hosted KYC verification URL from WeWire (SumSub WebSDK link).
 * Endpoint: GET /v1/subcustomers/{subCustomerId}/kyc-link
 */
export async function getHostedKycLink(
  subCustomerId: string
): Promise<{ url: string; stage: string }> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey || subCustomerId.startsWith('sub_stub_')) {
    return {
      url: 'https://in.sumsub.com/websdk/p/sbx_demo_mock_url',
      stage: 'ONBOARDING',
    };
  }

  const endpoint = `${baseUrl}/v1/subcustomers/${subCustomerId}/kyc-link`;
  const res = await fetch(endpoint, {
    method: 'GET',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
  });

  const data: any = await res.json();
  if (!res.ok) {
    const errMsg = data?.error?.message || data?.message || JSON.stringify(data);
    throw new Error(`Failed to retrieve hosted KYC link: ${errMsg}`);
  }

  return {
    url: data.url,
    stage: data.stage || 'ONBOARDING',
  };
}

/**
 * Retrieves the current sub-customer status from WeWire.
 * Endpoint: GET /v1/subcustomers/{subCustomerId}
 */
export async function getSubCustomerStatus(
  subCustomerId: string
): Promise<{ onboardingStatus: string; enhancedKycStatus: string }> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey || subCustomerId.startsWith('sub_stub_')) {
    return {
      onboardingStatus: 'DRAFT',
      enhancedKycStatus: 'NOT_STARTED',
    };
  }

  const endpoint = `${baseUrl}/v1/subcustomers/${subCustomerId}`;
  const res = await fetch(endpoint, {
    method: 'GET',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
  });

  const data: any = await res.json();
  if (!res.ok) {
    const errMsg = data?.error?.message || data?.message || JSON.stringify(data);
    throw new Error(`Failed to retrieve sub-customer status: ${errMsg}`);
  }

  return {
    onboardingStatus: data.onboardingStatus || 'DRAFT',
    enhancedKycStatus: data.enhancedKycStatus || 'NOT_STARTED',
  };
}

export interface TopupInitiationResult {
  checkoutId: string;
  checkoutUrl: string;
  accountDetails: {
    bankName: string;
    accountName: string;
    accountNumber: string;
    routingNumber: string;
    currency: string;
  };
}

/**
 * Initiates funding workflow per WeWire rails (virtual account & hosted checkout fallback).
 */
export function initiateWeWireFunding(params: {
  subCustomerId?: string | null;
  userName: string;
  userId: string;
  amount: number;
  currency: string;
}): TopupInitiationResult {
  const checkoutId = `chk_ww_${Date.now()}_${params.userId.replace(/-/g, '').slice(0, 8)}`;
  const appBaseUrl = (process.env.APP_BASE_URL || `http://localhost:${process.env.PORT || 3000}`).replace(/\/$/, '');
  const checkoutUrl = `${appBaseUrl}/checkout/${checkoutId}?amount=${params.amount}&currency=${params.currency}`;

  // Deterministic, clean demo virtual account routing based on user profile
  const acctSuffix = params.userId.replace(/[^0-9]/g, '').padEnd(8, '45678901').slice(0, 8);
  const accountNumber = `9870${acctSuffix}`;

  return {
    checkoutId,
    checkoutUrl,
    accountDetails: {
      bankName: 'WeWire Treasury Bank / Evolve Bank & Trust',
      accountName: `VessPay / ${params.userName}`,
      accountNumber,
      routingNumber: '021000021',
      currency: params.currency,
    },
  };
}

export interface WeWireRateItem {
  from: string;
  to: string;
  bid: string;
  ask: string;
  updatedAt: string;
}

export interface ExchangeRateResult {
  from: string;
  to: string;
  rate: number;
  asOf: string;
}

interface RatesCache {
  rates: WeWireRateItem[];
  timestamp: number;
}

let cachedRates: RatesCache | null = null;
const CACHE_TTL_MS = 30_000; // 30 seconds in-memory TTL

/**
 * Fetches current rate table from WeWire's GET /v1/rates.
 * Caches in memory for 30s to avoid unnecessary network latency and rate limits.
 */
export async function getWeWireRates(forceRefresh = false): Promise<WeWireRateItem[]> {
  const now = Date.now();
  if (!forceRefresh && cachedRates && now - cachedRates.timestamp < CACHE_TTL_MS) {
    return cachedRates.rates;
  }

  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using fallback rate table');
    return [
      { from: 'USD', to: 'GHS', bid: '11.58', ask: '0', updatedAt: new Date().toISOString() },
      { from: 'EUR', to: 'GHS', bid: '12.85', ask: '750', updatedAt: new Date().toISOString() },
      { from: 'GBP', to: 'GHS', bid: '15.01', ask: '0', updatedAt: new Date().toISOString() },
      { from: 'USD', to: 'NGN', bid: '843.55', ask: '850.4', updatedAt: new Date().toISOString() },
    ];
  }

  const endpoint = `${baseUrl}/v1/rates`;
  try {
    const res = await fetch(endpoint, {
      method: 'GET',
      headers: {
        'ww-api-key': apiKey,
        'Content-Type': 'application/json',
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      console.warn(`WeWire /v1/rates returned non-200 (${res.status}):`, errText);
      if (cachedRates) return cachedRates.rates;
      throw new Error(`WeWire rates request failed with status ${res.status}`);
    }

    const data: any = await res.json();
    if (Array.isArray(data)) {
      cachedRates = {
        rates: data,
        timestamp: now,
      };
      return data;
    }

    if (cachedRates) return cachedRates.rates;
    throw new Error('Unexpected WeWire rates response format');
  } catch (err) {
    console.error('Error fetching WeWire rates:', err);
    if (cachedRates) return cachedRates.rates;
    return [
      { from: 'USD', to: 'GHS', bid: '11.58', ask: '0', updatedAt: new Date().toISOString() },
      { from: 'EUR', to: 'GHS', bid: '12.85', ask: '750', updatedAt: new Date().toISOString() },
      { from: 'GBP', to: 'GHS', bid: '15.01', ask: '0', updatedAt: new Date().toISOString() },
      { from: 'USD', to: 'NGN', bid: '843.55', ask: '850.4', updatedAt: new Date().toISOString() },
    ];
  }
}

/**
 * Retrieves the exchange rate for a specific currency pair (e.g. from USD to GHS).
 * Returns ExchangeRateResult or null if the pair is not supported.
 */
export async function getExchangeRate(
  fromCurrency: string,
  toCurrency: string,
  forceRefresh = false
): Promise<ExchangeRateResult | null> {
  const from = fromCurrency.trim().toUpperCase();
  const to = toCurrency.trim().toUpperCase();

  const rates = await getWeWireRates(forceRefresh);

  // 1. Direct match: from -> to
  const directMatch = rates.find((r) => r.from.toUpperCase() === from && r.to.toUpperCase() === to);
  if (directMatch) {
    const bid = parseFloat(directMatch.bid);
    const ask = parseFloat(directMatch.ask);
    const rate = bid > 0 ? bid : ask;
    if (rate > 0) {
      return {
        from,
        to,
        rate,
        asOf: directMatch.updatedAt || new Date().toISOString(),
      };
    }
  }

  // 2. Inverse match: to -> from
  const inverseMatch = rates.find((r) => r.from.toUpperCase() === to && r.to.toUpperCase() === from);
  if (inverseMatch) {
    const bid = parseFloat(inverseMatch.bid);
    const ask = parseFloat(inverseMatch.ask);
    const baseRate = ask > 0 ? ask : bid;
    if (baseRate > 0) {
      return {
        from,
        to,
        rate: parseFloat((1 / baseRate).toFixed(6)),
        asOf: inverseMatch.updatedAt || new Date().toISOString(),
      };
    }
  }

  return null;
}

export interface CreateWeWireBeneficiaryParams {
  name: string;
  /** Operator or bank: a WeWire sort code ('MTN', 'GCB') or a display name. */
  network: string;
  /** Mobile money number. Required for MOBILE_MONEY payouts. */
  phone?: string;
  /** Bank account number. Required for BANK payouts. */
  accountNumber?: string;
  /** Defaults to MOBILE_MONEY for backwards compatibility. */
  channel?: PayoutChannel;
  country?: string | null;
  subCustomerId?: string | null;
  email?: string | null;
}

export interface CreateWeWireBeneficiaryResult {
  wewireBeneficiaryId: string;
  wewireAccountId: string;
  network: string;
  accountNumber: string;
  accountName: string;
  channel: PayoutChannel;
  institutionCode: string;
}

/**
 * Normalizes input Ghana phone number to 10-digit MSISDN and international format.
 */
export function normalizeGhanaPhone(phoneInput: string): { msisdn: string; international: string } {
  const digits = phoneInput.replace(/\D/g, '');
  let msisdn = digits;
  if (digits.startsWith('233') && digits.length === 12) {
    msisdn = '0' + digits.slice(3);
  } else if (digits.length === 9) {
    msisdn = '0' + digits;
  }
  const international = `+233${msisdn.replace(/^0/, '')}`;
  return { msisdn, international };
}

/**
 * Maps Ghana network names to WeWire operator codes and bank names.
 */
export function mapGhanaNetwork(networkInput: string): { network: string; sortCode: string; bankName: string } {
  const net = networkInput.trim().toUpperCase();
  if (net === 'MTN') {
    return { network: 'MTN', sortCode: 'MTN', bankName: 'MTN Mobile Money' };
  }
  if (net === 'TELECEL' || net === 'VODAFONE' || net === 'VOD') {
    return { network: 'Telecel', sortCode: 'VOD', bankName: 'Telecel Cash' };
  }
  if (net === 'AIRTELTIGO' || net === 'AIRTEL' || net === 'TIGO' || net === 'ATM') {
    return { network: 'AirtelTigo', sortCode: 'ATM', bankName: 'AirtelTigo Money' };
  }
  throw new Error(`Unsupported network: "${networkInput}". Supported networks are MTN, Telecel, and AirtelTigo.`);
}

/**
 * Creates both a WeWire beneficiary and its Mobile Money beneficiary account
 * via POST /v1/beneficiaries against the live WeWire sandbox.
 * Returns the created wewire_beneficiary_id and wewire_account_id.
 */
export async function createWeWireBeneficiary(
  params: CreateWeWireBeneficiaryParams
): Promise<CreateWeWireBeneficiaryResult> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  const institution = await resolveInstitution(params.network);
  const isBank = (params.channel ?? institution.channel) === 'BANK';
  const alpha3Country = toAlpha3Country(params.country || 'GHA');

  // Mobile money is addressed by MSISDN, a bank account by its account number.
  const { msisdn, international } = normalizeGhanaPhone(params.phone || '');
  let destinationAccount = msisdn;
  if (isBank) {
    const normalized = normalizeBankAccountNumber(params.accountNumber || '');
    if (!normalized) {
      throw new Error(
        'A valid bank account number (8-20 digits) is required for a bank beneficiary'
      );
    }
    destinationAccount = normalized;
  } else if (!/^0[235]\d{8}$/.test(msisdn)) {
    throw new Error(
      'A valid 10-digit Ghana mobile money number is required for a mobile money beneficiary'
    );
  }

  // Split name into first and last name
  const cleanName = params.name.trim();
  const nameParts = cleanName.split(/\s+/);
  const firstName = nameParts[0] || 'Recipient';
  const lastName = nameParts.slice(1).join(' ') || firstName;
  const email =
    params.email?.trim().toLowerCase() ||
    `${firstName.toLowerCase().replace(/[^a-z0-9]/g, '') || 'recipient'}.${destinationAccount}@vesspay.internal`;

  const channel: PayoutChannel = isBank ? 'BANK' : 'MOBILE_MONEY';

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using fallback beneficiary IDs');
    const fakeId = `ben_stub_${Date.now()}`;
    return {
      wewireBeneficiaryId: fakeId,
      wewireAccountId: `acc_stub_${Date.now()}`,
      network: institution.name,
      accountNumber: destinationAccount,
      accountName: cleanName,
      channel,
      institutionCode: institution.code,
    };
  }

  let payload: any = {
    type: 'INDIVIDUAL',
    firstName,
    lastName,
    email,
    // A bank beneficiary still carries a contact number when we have one.
    telephone: params.phone ? international : undefined,
    country: alpha3Country,
    currency: 'GHS',
    subCustomerId: params.subCustomerId && !params.subCustomerId.startsWith('sub_stub_')
      ? params.subCustomerId
      : undefined,
    accountDetails: {
      // Verified sandbox enum: MOBILE_MONEY | BANK_ACCOUNT | CRYPTO_WALLET
      type: institution.accountType,
      accountNumber: destinationAccount,
      accountName: cleanName,
      currency: 'GHS',
      bankName: institution.name,
      sortCode: institution.code,
    },
  };

  const endpoint = `${baseUrl}/v1/beneficiaries`;
  let res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  let text = await res.text();
  let data: any;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }

  // If subcustomer is not approved in sandbox, retry without subCustomerId
  if (!res.ok && payload.subCustomerId && text.includes('Sub-customer is not approved')) {
    delete payload.subCustomerId;
    res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'ww-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    text = await res.text();
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const errMsg =
      typeof data === 'object' && data?.error?.message
        ? data.error.message
        : typeof data === 'object' && data?.message
        ? data.message
        : JSON.stringify(data);
    throw new Error(`Failed to create WeWire beneficiary: ${errMsg} (Status: ${res.status})`);
  }

  const beneficiaryId = data?.id;
  if (!beneficiaryId) {
    throw new Error('WeWire did not return a beneficiary ID in response');
  }

  // Retrieve the created beneficiary to fetch the generated wewire_account_id
  let accountId: string | null = null;
  try {
    const getRes = await fetch(`${baseUrl}/v1/beneficiaries/${beneficiaryId}`, {
      method: 'GET',
      headers: {
        'ww-api-key': apiKey,
        'Content-Type': 'application/json',
      },
    });

    if (getRes.ok) {
      const benDetails: any = await getRes.json();
      const accounts = benDetails?.beneficiaryAccounts;
      if (Array.isArray(accounts) && accounts.length > 0) {
        accountId = accounts[0].id;
      }
    }
  } catch (err) {
    console.warn(`Could not retrieve account details for beneficiary ${beneficiaryId}:`, err);
  }

  return {
    wewireBeneficiaryId: beneficiaryId,
    wewireAccountId: accountId || beneficiaryId,
    network: institution.name,
    accountNumber: destinationAccount,
    accountName: cleanName,
    channel,
    institutionCode: institution.code,
  };
}

/**
 * Retrieves a beneficiary from WeWire by its ID.
 */
export async function getWeWireBeneficiary(wewireBeneficiaryId: string): Promise<any> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey || !wewireBeneficiaryId || wewireBeneficiaryId.startsWith('ben_stub_')) {
    return null;
  }

  const endpoint = `${baseUrl}/v1/beneficiaries/${wewireBeneficiaryId}`;
  const res = await fetch(endpoint, {
    method: 'GET',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
  });

  if (!res.ok) {
    return null;
  }

  return await res.json();
}

/**
 * Deletes a beneficiary from WeWire by its ID.
 */
export async function deleteWeWireBeneficiary(wewireBeneficiaryId: string): Promise<boolean> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  if (!apiKey || !wewireBeneficiaryId || wewireBeneficiaryId.startsWith('ben_stub_')) {
    return true;
  }

  try {
    const endpoint = `${baseUrl}/v1/beneficiaries/${wewireBeneficiaryId}`;
    const res = await fetch(endpoint, {
      method: 'DELETE',
      headers: {
        'ww-api-key': apiKey,
        'Content-Type': 'application/json',
      },
    });

    return res.ok || res.status === 404;
  } catch (err) {
    console.warn(`Failed to delete WeWire beneficiary ${wewireBeneficiaryId}:`, err);
    return false;
  }
}

export interface SendWeWireDisbursementParams {
  idempotencyKey: string;
  amount: number;
  currency?: string;
  /** Operator or bank: a WeWire sort code ('MTN', 'GCB') or a display name. */
  network: string;
  /** Mobile money number. Required for MOBILE_MONEY payouts. */
  phone?: string;
  /** Bank account number. Required for BANK payouts. */
  accountNumber?: string;
  /** Defaults to whichever channel the institution belongs to. */
  channel?: PayoutChannel;
  recipientName: string;
  reference?: string;
  memo?: string;
}

export interface SendWeWireDisbursementResult {
  wewireTransactionId: string;
  status: string;
  amount?: string;
  fee?: string;
  currency?: string;
  channel?: string;
}

/**
 * Sends a real mobile money payout via WeWire's POST /v1/disbursements endpoint.
 * Per current docs: local African disbursements use POST /v1/disbursements.
 */
export async function sendWeWireDisbursement(
  params: SendWeWireDisbursementParams
): Promise<SendWeWireDisbursementResult> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  const institution = await resolveInstitution(params.network);
  const channel: PayoutChannel = params.channel ?? institution.channel;
  const currency = (params.currency || 'GHS').trim().toUpperCase();

  // Mobile money is addressed by MSISDN, a bank account by its account number.
  let destinationAccount: string;
  if (channel === 'BANK') {
    const normalized = normalizeBankAccountNumber(params.accountNumber || '');
    if (!normalized) {
      throw new Error('A valid bank account number (8-20 digits) is required for a bank payout');
    }
    destinationAccount = normalized;
  } else {
    destinationAccount = normalizeGhanaPhone(params.phone || '').msisdn;
  }

  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; using fallback disbursement stub');
    return {
      wewireTransactionId: `ww_tx_stub_${Date.now()}`,
      status: 'PENDING',
      amount: params.amount.toString(),
      currency,
      channel,
    };
  }

  const endpoint = `${baseUrl}/v1/disbursements`;
  const payload = {
    idempotencyKey: params.idempotencyKey,
    amount: params.amount,
    currency,
    // Verified sandbox enum: MOBILE_MONEY | BANK
    channel,
    accountCode: institution.code, // MTN / VOD / ATM, or a bank sort code such as GCB
    accountNumber: destinationAccount,
    accountName: params.recipientName.trim(),
    reference: params.reference || undefined,
    memo: params.memo || 'VessPay Payout',
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'ww-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  let data: any;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }

  if (!response.ok) {
    const errMsg =
      typeof data === 'object' && data?.error?.message
        ? data.error.message
        : typeof data === 'object' && data?.message
        ? data.message
        : JSON.stringify(data);
    throw new Error(`WeWire disbursement failed: ${errMsg} (Status: ${response.status})`);
  }

  const wewireTransactionId = data?.id;
  if (!wewireTransactionId) {
    throw new Error('WeWire did not return a transaction ID in disbursement response');
  }

  return {
    wewireTransactionId,
    status: data?.status || 'PENDING',
    amount: data?.amount ? String(data.amount) : String(params.amount),
    fee: data?.fee ? String(data.fee) : undefined,
    currency: data?.currency || currency,
    channel: data?.channel || channel,
  };
}


export interface AccountNameLookupResult {
  accountName: string;
  accountCode: string;
  accountNumber: string;
}

const accountNameCache = new Map<string, { name: string | null; timestamp: number }>();
const ACCOUNT_NAME_TTL_MS = 5 * 60 * 1000;

/**
 * Name enquiry against WeWire's GET /v1/account-lookup.
 *
 * Verified against the sandbox: the endpoint takes currency (GHS|NGN),
 * accountCode (the sort code, 2-16 chars) and accountNumber (6-32 chars), and
 * returns { accountName } for an account the operator or bank recognises.
 * An account it cannot resolve comes back as a 502 INTEGRATION_ERROR rather
 * than a clean 404, so any non-200 is treated as "not confirmed", never as a
 * failure of our own request.
 */
export async function lookupAccountName(params: {
  accountCode: string;
  accountNumber: string;
  currency?: string;
}): Promise<AccountNameLookupResult | null> {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

  const accountCode = params.accountCode.trim().toUpperCase();
  const accountNumber = params.accountNumber.trim();
  const currency = (params.currency || 'GHS').trim().toUpperCase();

  if (accountCode.length < 2 || accountNumber.length < 6) return null;
  if (!apiKey) {
    console.warn('WEWIRE_API_KEY is not configured; skipping account name lookup');
    return null;
  }

  const cacheKey = `${currency}:${accountCode}:${accountNumber}`;
  const cached = accountNameCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < ACCOUNT_NAME_TTL_MS) {
    return cached.name
      ? { accountName: cached.name, accountCode, accountNumber }
      : null;
  }

  const query = new URLSearchParams({ currency, accountCode, accountNumber });

  try {
    const res = await fetch(`${baseUrl}/v1/account-lookup?${query}`, {
      headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
    });

    if (!res.ok) {
      // Unknown account, wrong operator for the number, or the upstream rail
      // being unavailable all land here. None of them is our error.
      accountNameCache.set(cacheKey, { name: null, timestamp: Date.now() });
      return null;
    }

    const data: any = await res.json();
    const accountName = (data?.accountName ?? data?.name ?? '').toString().trim();
    if (!accountName) {
      accountNameCache.set(cacheKey, { name: null, timestamp: Date.now() });
      return null;
    }

    accountNameCache.set(cacheKey, { name: accountName, timestamp: Date.now() });
    return { accountName, accountCode, accountNumber };
  } catch (err: any) {
    console.warn('WeWire account name lookup failed:', err?.message || err);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Sub-customer virtual accounts (deposits)
//
// Verified against the stage sandbox:
//   GET  /v1/subcustomers/{id}/accounts                        -> bare array
//   POST /v1/subcustomers/{id}/accounts/request                -> issue one
//   POST /v1/subcustomers/{id}/accounts/{aid}/simulate-deposit -> sandbox only
//
// There is no separate "create wallet" call: accounts hang off the sub-customer
// and the business wallet is credited when funds land on one. Account issuance
// is gated on Enhanced Due Diligence, so a sub-customer that is merely
// onboardingStatus APPROVED is rejected with SUBCUSTOMER_ENHANCED_KYC_REQUIRED.
// ---------------------------------------------------------------------------

function wewireConfig(): { apiKey: string; baseUrl: string } | null {
  const apiKey = process.env.WEWIRE_API_KEY;
  if (!apiKey) return null;
  const baseUrl = (
    process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com'
  ).replace(/\/$/, '');
  return { apiKey, baseUrl };
}

export class WeWireApiError extends Error {
  readonly status: number;
  readonly code: string | null;

  constructor(message: string, status: number, code: string | null) {
    super(message);
    this.name = 'WeWireApiError';
    this.status = status;
    this.code = code;
  }
}

/** Single place for the request/parse/error shape every WeWire call shares. */
async function wewireRequest(
  path: string,
  init: { method: 'GET' | 'POST'; body?: unknown } = { method: 'GET' }
): Promise<any> {
  const config = wewireConfig();
  if (!config) {
    throw new Error('WEWIRE_API_KEY is not configured');
  }

  const res = await fetch(`${config.baseUrl}${path}`, {
    method: init.method,
    headers: {
      'ww-api-key': config.apiKey,
      'Content-Type': 'application/json',
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
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
    const code =
      (typeof data === 'object' && (data?.error?.code || data?.code)) || null;
    throw new WeWireApiError(
      `WeWire ${init.method} ${path} failed: ${message}`,
      res.status,
      code
    );
  }

  return data;
}

/** Unwraps the bare-array and `{ data: [...] }` shapes WeWire list routes use. */
function asArray(payload: any): any[] {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.items)) return payload.items;
  return [];
}

export interface WeWireSubCustomerAccount {
  id: string;
  currency: string;
  /** REQUESTED | PENDING | ACTIVE | DENIED | SUSPENDED | CLOSED */
  status: string;
  accountName?: string;
  accountNumber?: string;
  iban?: string;
  bic?: string;
  routingNumber?: string;
  sortCode?: string;
  bankName?: string;
  paymentRails?: string[];
}

/**
 * The values WeWire accepts for `sourceOfFunds`, taken verbatim from the
 * VALIDATION_FAILED response the sandbox returns when the field is omitted.
 * It is a closed enum, so the app offers these as choices rather than free text.
 */
export const SOURCE_OF_FUNDS_VALUES = [
  'company_funds',
  'ecommerce_reseller',
  'gambling_proceeds',
  'gifts',
  'government_benefits',
  'inheritance',
  'investments_loans',
  'pension_retirement',
  'salary',
  'sale_of_assets_real_estate',
  'savings',
  'someone_elses_funds',
  'business_loans',
  'grants',
  'inter_company_funds',
  'investment_proceeds',
  'legal_settlement',
  'owners_capital',
  'sale_of_assets',
  'sales_of_goods_and_services',
  'third_party_funds',
  'treasury_reserves',
] as const;

export type SourceOfFunds = (typeof SOURCE_OF_FUNDS_VALUES)[number];

export function isSourceOfFunds(raw: unknown): raw is SourceOfFunds {
  return (
    typeof raw === 'string' &&
    (SOURCE_OF_FUNDS_VALUES as readonly string[]).includes(raw)
  );
}

/**
 * Compliance answers WeWire requires when issuing a USD account. These are the
 * user's own declarations, so callers must supply them: never invent a value.
 */
export interface AccountRequestDetails {
  sourceOfFunds?: SourceOfFunds;
  occupation?: string;
  employment_status?: string;
  account_purpose?: string;
  account_purpose_other?: string;
  expected_monthly_payments_usd?: string;
  acting_as_intermediary?: boolean;
}

export async function listWeWireSubCustomerAccounts(
  subCustomerId: string
): Promise<WeWireSubCustomerAccount[]> {
  return asArray(
    await wewireRequest(`/v1/subcustomers/${subCustomerId}/accounts`)
  ) as WeWireSubCustomerAccount[];
}

/**
 * Requests a virtual account in `currency`. Issuance is asynchronous, so the
 * returned account is usually REQUESTED or PENDING rather than ACTIVE.
 */
export async function requestWeWireAccount(
  subCustomerId: string,
  currency: string,
  details: AccountRequestDetails = {}
): Promise<WeWireSubCustomerAccount> {
  const wanted = currency.trim().toUpperCase();

  if (wanted === 'USD' && !details.sourceOfFunds) {
    throw new WeWireApiError(
      'A USD account request requires sourceOfFunds (and, in higher-risk jurisdictions, occupation, employment_status and account_purpose)',
      400,
      'MISSING_COMPLIANCE_DETAILS'
    );
  }

  return wewireRequest(`/v1/subcustomers/${subCustomerId}/accounts/request`, {
    method: 'POST',
    body: { currency: wanted, ...details },
  }) as Promise<WeWireSubCustomerAccount>;
}

export interface ResolvedDepositAccount {
  accountId: string;
  currency: string;
  status: string;
  /** True only when the account can actually receive a deposit. */
  isActive: boolean;
  account: WeWireSubCustomerAccount;
}

const USABLE_ACCOUNT_STATUSES = new Set(['ACTIVE', 'REQUESTED', 'PENDING']);

/**
 * Finds, or requests, the virtual account a deposit in `currency` lands on.
 *
 * Returns null when WeWire is not configured so callers can fall back cleanly.
 * Account issuance is asynchronous: a freshly requested account comes back
 * `isActive: false` and has to be polled before it can take a deposit.
 */
export async function resolveWeWireDepositAccount(
  subCustomerId: string,
  currency: string,
  details: AccountRequestDetails = {}
): Promise<ResolvedDepositAccount | null> {
  if (!wewireConfig()) return null;

  const wanted = currency.trim().toUpperCase();
  const matches = (a: WeWireSubCustomerAccount) =>
    (a.currency || '').toUpperCase() === wanted &&
    USABLE_ACCOUNT_STATUSES.has((a.status || '').toUpperCase());

  const existing = await listWeWireSubCustomerAccounts(subCustomerId);

  // Prefer an account usable right now over one still provisioning.
  const usable =
    existing.find(
      (a) => matches(a) && (a.status || '').toUpperCase() === 'ACTIVE'
    ) || existing.find(matches);

  const account =
    usable ?? (await requestWeWireAccount(subCustomerId, wanted, details));
  if (!account?.id) return null;

  const status = (account.status || 'UNKNOWN').toUpperCase();
  return {
    accountId: account.id,
    currency: (account.currency || wanted).toUpperCase(),
    status,
    isActive: status === 'ACTIVE',
    account,
  };
}

/**
 * Triggers a sandbox test deposit onto a virtual account. WeWire rejects this
 * in production with a 400, so it stays a sandbox-only affordance.
 * Crediting happens when the resulting pay-in webhook arrives, not here.
 */
export async function simulateWeWireDeposit(params: {
  subCustomerId: string;
  accountId: string;
  amount: number;
  currency: string;
}): Promise<any> {
  return wewireRequest(
    `/v1/subcustomers/${params.subCustomerId}/accounts/${params.accountId}/simulate-deposit`,
    {
      method: 'POST',
      body: {
        amount: params.amount,
        currency: params.currency.trim().toUpperCase(),
      },
    }
  );
}
