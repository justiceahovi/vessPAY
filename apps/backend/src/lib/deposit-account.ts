import { prisma } from './db';
import { DEFAULT_WALLET_CURRENCY } from './currencies';
import {
  AccountRequestDetails,
  getHostedKycLink,
  listWeWireSubCustomerAccounts,
  getSubCustomerStatus,
  isSourceOfFunds,
  resolveWeWireDepositAccount,
  SourceOfFunds,
  WeWireApiError,
} from './wewire';

/**
 * Deposit-account setup, driven from the Add Money flow rather than sign-up.
 *
 * A user cannot receive money until WeWire has issued them a virtual account,
 * and that needs two things they have to supply themselves: Enhanced Due
 * Diligence, and a declared source of funds. Both are asked for at the moment
 * they first try to deposit, where the reason is self-evident.
 */
export type DepositAccountState =
  | 'READY'
  | 'NOT_REQUESTED'
  | 'PROVISIONING'
  | 'KYC_REQUIRED'
  | 'SOURCE_OF_FUNDS_REQUIRED'
  | 'UNAVAILABLE';

export interface DepositAccountStatus {
  state: DepositAccountState;
  currency: string;
  accountId: string | null;
  accountStatus: string | null;
  accountDetails: Record<string, unknown> | null;
  sourceOfFunds: string | null;
  kycLinkUrl?: string | null;
  /** Human readable explanation for KYC_REQUIRED / UNAVAILABLE. */
  reason?: string;
}

/** Only USD demands the compliance declaration; EUR/GBP do not. */
function requiresSourceOfFunds(currency: string): boolean {
  return currency.trim().toUpperCase() === 'USD';
}

const APPROVED_KYC = new Set(['APPROVED', 'VERIFIED', 'ACTIVE', 'COMPLETED']);

function isEnhancedApproved(value: string): boolean {
  const v = (value || '').trim().toUpperCase();
  return APPROVED_KYC.has(v) || v.startsWith('TIER_');
}

/**
 * Reports where the user is in deposit-account setup, optionally provisioning
 * the account when everything it needs is present.
 *
 * `provision: false` never calls WeWire's write endpoints, so the Add Money
 * screen can poll it cheaply.
 */
export async function getDepositAccountStatus(
  userId: string,
  opts: { provision?: boolean } = {}
): Promise<DepositAccountStatus> {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  const currency = (
    user.primaryCurrency || DEFAULT_WALLET_CURRENCY
  ).toUpperCase();

  const base: DepositAccountStatus = {
    state: 'UNAVAILABLE',
    currency,
    accountId: null,
    accountStatus: null,
    accountDetails: null,
    sourceOfFunds: user.sourceOfFunds ?? null,
  };

  if (!user.wewireSubcustomerId) {
    return { ...base, reason: 'This account has no WeWire sub-customer yet' };
  }

  // An account already on file is the fast path: no WeWire write needed.
  const wallet = await prisma.wallet.findFirst({
    where: { userId, currency },
  });

  // Prefer the locally mirrored state kept current by WeWire's KYC webhooks.
  // Only ask WeWire directly when we have never been told anything, which
  // keeps a polling deposit screen off their API entirely.
  let enhancedKycStatus = user.enhancedKycStatus;
  if (!enhancedKycStatus) {
    const kyc = await getSubCustomerStatus(user.wewireSubcustomerId);
    enhancedKycStatus = kyc.enhancedKycStatus;
    await prisma.user.update({
      where: { id: user.id },
      data: {
        onboardingStatus: kyc.onboardingStatus?.toUpperCase() ?? null,
        enhancedKycStatus: kyc.enhancedKycStatus?.toUpperCase() ?? null,
        kycStatusUpdatedAt: new Date(),
      },
    });
  }

  if (!isEnhancedApproved(enhancedKycStatus)) {
    let kycLinkUrl: string | null = null;
    try {
      kycLinkUrl = (await getHostedKycLink(user.wewireSubcustomerId)).url;
    } catch {
      // The link is a convenience; the state still stands without it.
    }
    return {
      ...base,
      state: 'KYC_REQUIRED',
      kycLinkUrl,
      reason:
        'Enhanced verification must be completed before a deposit account can be issued.',
    };
  }

  const details: AccountRequestDetails = {};
  if (requiresSourceOfFunds(currency)) {
    if (!isSourceOfFunds(user.sourceOfFunds)) {
      return { ...base, state: 'SOURCE_OF_FUNDS_REQUIRED' };
    }
    details.sourceOfFunds = user.sourceOfFunds as SourceOfFunds;
  }

  // Read-only poll: ask WeWire what already exists rather than trusting the
  // cached column, and never conflate "never requested" with "still issuing" —
  // the client must POST for the former and only waits for the latter.
  if (!opts.provision) {
    const existing = await listWeWireSubCustomerAccounts(
      user.wewireSubcustomerId
    );
    const match = existing.find(
      (a) => (a.currency || '').toUpperCase() === currency
    );

    if (!match) {
      return { ...base, state: 'NOT_REQUESTED' };
    }

    const status = (match.status || 'UNKNOWN').toUpperCase();
    if (wallet && wallet.wewireAccountId !== match.id) {
      await prisma.wallet.update({
        where: { id: wallet.id },
        data: { wewireAccountId: match.id },
      });
    }

    return {
      ...base,
      state: status === 'ACTIVE' ? 'READY' : 'PROVISIONING',
      accountId: match.id,
      accountStatus: status,
      accountDetails:
        status === 'ACTIVE'
          ? (match as unknown as Record<string, unknown>)
          : null,
    };
  }

  try {
    const resolved = await resolveWeWireDepositAccount(
      user.wewireSubcustomerId,
      currency,
      details
    );

    if (!resolved) {
      return { ...base, reason: 'WeWire is not configured for this environment' };
    }

    if (wallet && wallet.wewireAccountId !== resolved.accountId) {
      await prisma.wallet.update({
        where: { id: wallet.id },
        data: { wewireAccountId: resolved.accountId },
      });
    }

    return {
      ...base,
      state: resolved.isActive ? 'READY' : 'PROVISIONING',
      accountId: resolved.accountId,
      accountStatus: resolved.status,
      accountDetails: resolved.isActive
        ? (resolved.account as unknown as Record<string, unknown>)
        : null,
    };
  } catch (err: any) {
    if (err instanceof WeWireApiError) {
      if (err.code === 'SUBCUSTOMER_ENHANCED_KYC_REQUIRED') {
        return {
          ...base,
          state: 'KYC_REQUIRED',
          reason: 'Enhanced verification must be completed first.',
        };
      }
      if (err.code === 'MISSING_COMPLIANCE_DETAILS') {
        return { ...base, state: 'SOURCE_OF_FUNDS_REQUIRED' };
      }
      // e.g. "GHA is not supported by OpenPayd for EUR" — a jurisdiction rule
      // no amount of verification will change, so say so plainly.
      return { ...base, state: 'UNAVAILABLE', reason: err.message };
    }
    throw err;
  }
}
