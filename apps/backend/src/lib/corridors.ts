/**
 * Payout corridors: everything that differs between the countries VessPay pays
 * into, in one place, so a rail-specific rule never has to be rediscovered by
 * grepping for 'GHS'.
 *
 * Verified against the WeWire stage sandbox on 2026-09-07:
 *   - GET /v1/banks?currency=GHS returns 28 institutions, MOMO and BANK.
 *   - GET /v1/banks?currency=NGN returns 422 institutions, *every one* BANK.
 * Nigeria therefore has no mobile money channel: the wallets a Nigerian would
 * call mobile money (OPay, PalmPay, Moniepoint, Kuda, Paga) are BANK entries
 * addressed by a 10-digit NUBAN, not by a phone number.
 */

import type { PayoutChannel } from './wewire-institutions';

export interface Corridor {
  /** ISO 3166-1 alpha-2, as the app and the travel profile use it. */
  country: string;
  /** ISO 3166-1 alpha-3, as WeWire requires it on beneficiaries. */
  alpha3: string;
  name: string;
  /** Payout currency. */
  currency: string;
  /** Symbol for user-facing amounts. */
  symbol: string;
  dialCode: string;
  /** Channels this corridor can actually be paid over. */
  channels: PayoutChannel[];
  /** Local bank account number length, in digits. */
  accountNumber: { min: number; max: number };
  /**
   * National mobile money MSISDN pattern, or null for a corridor with no
   * mobile money channel.
   */
  msisdnPattern: RegExp | null;
  /**
   * WeWire's flat processor fee per disbursement, denominated in the payout
   * asset. Overridable per currency with WEWIRE_PROCESSOR_FEE_<CURRENCY>.
   */
  processorFee: number;
  /** True once a payout has actually been observed settling on this rail. */
  feeConfirmed: boolean;
  /**
   * Which WeWire endpoint pays this corridor out.
   *
   * 'AFRICA_DISBURSEMENT' is POST /v1/disbursements: recipient addressed
   * inline by accountCode + accountNumber. Per WeWire's API reference it
   * "starts a Ghana bank disbursement from the sub-customer GHST wallet" --
   * it is Ghana-only, which is exactly why every Ghana payout debits GHST.
   *
   * 'INITIATE_PAYOUT' is POST /v1/transactions/initiate-payout. Despite the
   * name it is the *offshore* endpoint: its validator rejects anything outside
   * EUR/GBP/USD on both `from` and `to` (verified 2026-09-07). It cannot carry
   * an African currency.
   *
   * 'UNSUPPORTED' means WeWire exposes no payout rail for this corridor yet,
   * even though its reference data (banks, account lookup, beneficiaries,
   * wallets) all work. Fail fast rather than spend a real payout attempt.
   */
  payoutEndpoint: 'AFRICA_DISBURSEMENT' | 'INITIATE_PAYOUT' | 'UNSUPPORTED';
}

export const CORRIDORS: Corridor[] = [
  {
    country: 'GH',
    alpha3: 'GHA',
    name: 'Ghana',
    currency: 'GHS',
    symbol: 'GH₵',
    dialCode: '+233',
    channels: ['MOBILE_MONEY', 'BANK'],
    // Ghana account numbers run 8-20 digits depending on the bank, so the
    // check stays deliberately loose.
    accountNumber: { min: 8, max: 20 },
    msisdnPattern: /^0[235]\d{8}$/,
    // Observed on every sandbox payout: a flat 5, denominated in the payout
    // asset (GHST), regardless of the amount sent.
    processorFee: 5.0,
    feeConfirmed: true,
    // Proven working end to end; do not move Ghana onto the other endpoint.
    payoutEndpoint: 'AFRICA_DISBURSEMENT',
  },
  {
    country: 'NG',
    alpha3: 'NGA',
    name: 'Nigeria',
    currency: 'NGN',
    symbol: '₦',
    dialCode: '+234',
    // No MOMO institutions exist for NGN -- see the file header.
    channels: ['BANK'],
    // NUBAN is exactly 10 digits.
    accountNumber: { min: 10, max: 10 },
    msisdnPattern: null,
    // Observed on a live NGN disbursement (2026-09-07): WeWire charged a flat
    // 1000, the same shape as Ghana's flat 5. Taken from a payout WeWire then
    // rejected downstream, so the figure is theirs but no NGN payout has yet
    // settled SUCCESSFUL -- worth re-checking against the first one that does.
    processorFee: 1000.0,
    feeConfirmed: false,
    // Verified against the sandbox 2026-09-07: WeWire has no NGN payout rail.
    //   /v1/disbursements            -> Ghana-only; took the NGN request,
    //                                   debited and refunded the NGN wallet,
    //                                   then failed with a bare
    //                                   "Disbursement failed".
    //   /v1/transactions/initiate-payout -> VALIDATION_FAILED, "from/to must be
    //                                   one of the following values: EUR, GBP,
    //                                   USD". Offshore rails only.
    // Everything *around* the payout works (banks, account lookup, beneficiary
    // registration, the funded NGN wallet), so flip this to the right value
    // the moment WeWire ships the rail.
    payoutEndpoint: 'UNSUPPORTED',
  },
];

const DEFAULT_CORRIDOR = CORRIDORS[0];

/** Every alias the app has historically used to name a corridor. */
const CORRIDOR_LOOKUP: Record<string, Corridor> = {};
for (const corridor of CORRIDORS) {
  for (const alias of [
    corridor.country,
    corridor.alpha3,
    corridor.currency,
    corridor.name.toUpperCase(),
  ]) {
    CORRIDOR_LOOKUP[alias] = corridor;
  }
}

/**
 * Resolves a country code, alpha-3, currency or country name to its corridor.
 * Returns null rather than guessing, so a caller can decide whether an unknown
 * destination is an error or a reason to fall back to Ghana.
 */
export function findCorridor(input?: string | null): Corridor | null {
  if (!input || typeof input !== 'string') return null;
  return CORRIDOR_LOOKUP[input.trim().toUpperCase()] || null;
}

/**
 * Resolves a corridor, falling back to Ghana. Use where the pre-corridor code
 * already defaulted to Ghana so behaviour is unchanged for existing callers.
 */
export function getCorridor(input?: string | null): Corridor {
  return findCorridor(input) || DEFAULT_CORRIDOR;
}

/** The payout currency for a country, e.g. 'GH' -> 'GHS'. */
export function currencyForCountry(country?: string | null): string {
  return getCorridor(country).currency;
}

export function isSupportedCorridor(input?: string | null): boolean {
  return findCorridor(input) !== null;
}

/** Comma separated corridor currencies, for validation error messages. */
export function supportedPayoutCurrencies(): string {
  return CORRIDORS.map((c) => c.currency).join(', ');
}

/**
 * WeWire's flat processor fee for a corridor, in the payout currency.
 * WEWIRE_PROCESSOR_FEE_<CURRENCY> overrides it, which is how the Nigerian
 * placeholder gets corrected without a deploy.
 */
export function processorFeeFor(currency: string): number {
  const corridor = findCorridor(currency);
  const code = (corridor?.currency || currency).trim().toUpperCase();

  const envFee = process.env[`WEWIRE_PROCESSOR_FEE_${code}`];
  if (envFee && !isNaN(parseFloat(envFee))) return parseFloat(envFee);

  return corridor?.processorFee ?? 0;
}

/** Whether a corridor can be paid over a given channel. */
export function supportsChannel(input: string | null | undefined, channel: PayoutChannel): boolean {
  const corridor = findCorridor(input);
  return corridor ? corridor.channels.includes(channel) : false;
}
