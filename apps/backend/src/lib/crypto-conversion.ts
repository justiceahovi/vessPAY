/**
 * Pricing a crypto deposit into the currency the user actually holds.
 *
 * This prices and credits; it does not move the token. That mirrors how the
 * rest of the product already works: a GBP deposit sweeps into the business GBP
 * wallet and the user's ledger is credited, while payouts are funded from a
 * separately pre-funded float. Converting the asset is a treasury operation
 * that happens out of band.
 *
 * The consequence is worth stating plainly: between crediting a user at today's
 * quoted rate and treasury actually realising that token, the difference is
 * unhedged. `conversionRate` is recorded on every deposit so that gap can be
 * measured rather than silently absorbed.
 */

import { getExchangeRate } from './wewire';

export interface CryptoDepositPricing {
  /** Token received, e.g. 'USDC'. */
  asset: string;
  /** Exact token amount, unrounded. */
  assetAmount: number;
  /** Wallet currency credited, e.g. 'GBP'. */
  currency: string;
  /** Wallet currency per token. */
  rate: number;
  /** 'direct' | 'inverse' | 'via:USD' -- how the rate was resolved. */
  via: string;
  /** Amount credited, in wallet units. */
  fiatAmount: number;
  asOf: string;
}

/**
 * Rounds a credit DOWN to wallet precision.
 *
 * Deliberately not round-to-nearest: rounding up would credit a fraction of a
 * penny nobody deposited, and doing that on every deposit invents money. The
 * remainder stays with the token, which is where it actually is.
 */
function floorToWalletUnits(value: number): number {
  return Math.floor(value * 100) / 100;
}

/**
 * Prices `assetAmount` of `asset` into `currency`.
 *
 * Returns null when the pair cannot be priced at all, which is a reason to
 * leave the deposit uncredited rather than to guess at a value.
 */
export async function priceCryptoDeposit(
  asset: string,
  assetAmount: number | string,
  currency: string
): Promise<CryptoDepositPricing | null> {
  const token = (asset ?? '').trim().toUpperCase();
  const target = (currency ?? '').trim().toUpperCase();
  const amount = typeof assetAmount === 'number' ? assetAmount : Number(assetAmount);

  if (!token || !target) return null;
  if (!Number.isFinite(amount) || amount <= 0) return null;

  // A deposit already in the user's own currency needs no conversion. Stablecoins
  // are not their fiat namesake, so this only fires on an exact match.
  if (token === target) {
    return {
      asset: token,
      assetAmount: amount,
      currency: target,
      rate: 1,
      via: 'identity',
      fiatAmount: floorToWalletUnits(amount),
      asOf: new Date().toISOString(),
    };
  }

  const rateResult = await getExchangeRate(token, target);
  if (!rateResult || !(rateResult.rate > 0)) return null;

  const fiatAmount = floorToWalletUnits(amount * rateResult.rate);
  // A deposit too small to be worth a penny is priced but credits nothing --
  // recorded honestly rather than rounded up into existence.
  if (fiatAmount < 0) return null;

  return {
    asset: token,
    assetAmount: amount,
    currency: target,
    rate: rateResult.rate,
    via: rateResult.via ?? 'direct',
    fiatAmount,
    asOf: rateResult.asOf,
  };
}
