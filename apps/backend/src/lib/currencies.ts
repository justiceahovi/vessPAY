/**
 * Wallet currencies a user can hold and deposit into on VessPay.
 *
 * Every entry must have a live WeWire rate into the payout corridors (GHS/NGN)
 * so the "local spending power" conversion keeps working after the user picks it.
 */
export interface WalletCurrency {
  code: string;
  name: string;
  symbol: string;
  /** Flag emoji of the issuing region, used by the mobile selection cards. */
  flag: string;
  /** Short line describing how money reaches the wallet in this currency. */
  fundingRail: string;
}

export const SUPPORTED_WALLET_CURRENCIES: WalletCurrency[] = [
  {
    code: 'USD',
    name: 'US Dollar',
    symbol: '$',
    flag: '🇺🇸',
    fundingRail: 'ACH & Fedwire virtual account',
  },
  {
    code: 'GBP',
    name: 'British Pound',
    symbol: '£',
    flag: '🇬🇧',
    fundingRail: 'Faster Payments virtual account',
  },
  {
    code: 'EUR',
    name: 'Euro',
    symbol: '€',
    flag: '🇪🇺',
    fundingRail: 'SEPA virtual account',
  },
];

/** Currency used when a user has not made a choice yet. */
export const DEFAULT_WALLET_CURRENCY = 'USD';

/**
 * Normalizes a raw currency input to a supported wallet currency code,
 * or returns null when the value is missing or unsupported.
 */
export function normalizeWalletCurrency(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const code = raw.trim().toUpperCase();
  const match = SUPPORTED_WALLET_CURRENCIES.find((c) => c.code === code);
  return match ? match.code : null;
}

export function isSupportedWalletCurrency(raw: unknown): boolean {
  return normalizeWalletCurrency(raw) !== null;
}

/** Comma separated list of codes, for validation error messages. */
export function supportedCurrencyCodes(): string {
  return SUPPORTED_WALLET_CURRENCIES.map((c) => c.code).join(', ');
}
