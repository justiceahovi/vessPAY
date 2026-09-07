import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { authenticate } from '../middleware/auth';
import { getDepositAccountStatus } from '../lib/deposit-account';
import {
  getSupportedCryptoChains,
  resolveCryptoDepositAddress,
  supportedChainCodes,
} from '../lib/crypto-assets';
import {
  getHostedKycLink,
  isSourceOfFunds,
  buildWeWireCheckoutUrl,
  initiateWeWireFunding,
  resolveWeWireDepositAccount,
  simulateWeWireDeposit,
  WeWireApiError,
} from '../lib/wewire';
import {
  DEFAULT_WALLET_CURRENCY,
  SUPPORTED_WALLET_CURRENCIES,
  normalizeWalletCurrency,
  supportedCurrencyCodes,
} from '../lib/currencies';

const router = Router();

export interface WalletDto {
  id: string;
  currency: string;
  balance: number;
}

export interface BalanceDto {
  currency: string;
  balance: number;
}

/**
 * GET /api/wallet/currencies
 * Lists the wallet currencies a user can choose to hold and deposit into.
 * Unauthenticated so the choice can be presented as part of sign-up.
 */
router.get('/currencies', (_req: Request, res: Response): void => {
  res.status(200).json({
    defaultCurrency: DEFAULT_WALLET_CURRENCY,
    currencies: SUPPORTED_WALLET_CURRENCIES,
  });
});

/**
 * PUT /api/wallet/currency
 * Persists the wallet currency the user picked and makes sure a wallet exists in it.
 * Body: { currency: 'USD' | 'GBP' | 'EUR' }
 * Returns: { primaryCurrency, wallet: { id, currency, balance } }
 *
 * A brand new account starts with an untouched zero-balance USD wallet, so when that
 * is still the user's only wallet the currency is switched on it in place rather than
 * leaving an empty wallet behind.
 */
router.put('/currency', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const currency = normalizeWalletCurrency(req.body?.currency);

    if (!currency) {
      res.status(400).json({
        error: {
          code: 'UNSUPPORTED_CURRENCY',
          message: `Wallet currency must be one of: ${supportedCurrencyCodes()}`,
        },
      });
      return;
    }

    const wallet = await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { primaryCurrency: currency },
      });

      const existing = await tx.wallet.findFirst({
        where: { userId, currency },
      });
      if (existing) return existing;

      const wallets = await tx.wallet.findMany({
        where: { userId },
        orderBy: { createdAt: 'asc' },
      });

      const onlyEmptyWallet =
        wallets.length === 1 && Number(wallets[0].balance) === 0 && !wallets[0].wewireWalletId;

      if (onlyEmptyWallet) {
        const funded = await tx.fundingTransaction.count({
          where: { userId, currency: wallets[0].currency },
        });
        if (funded === 0) {
          return tx.wallet.update({
            where: { id: wallets[0].id },
            data: { currency },
          });
        }
      }

      return tx.wallet.create({
        data: {
          userId,
          currency,
          balance: 0.0,
        },
      });
    });

    res.status(200).json({
      primaryCurrency: currency,
      wallet: {
        id: wallet.id,
        currency: wallet.currency,
        balance: Number(wallet.balance),
      } as WalletDto,
    });
  } catch (err: any) {
    console.error('Error setting wallet currency:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to update wallet currency',
      },
    });
  }
});

/**
 * GET /api/wallet
 * Returns the authenticated user's current wallet (defaults to their chosen currency).
 * Query params (optional):
 *   - currency: e.g. 'USD'
 * 
 * Blueprint Section 7:
 * GET /api/wallet -> { id, currency, balance }
 */
router.get('/', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const defaultCurrency = req.user!.primaryCurrency || DEFAULT_WALLET_CURRENCY;
    const requestedCurrency = typeof req.query.currency === 'string' && req.query.currency.trim()
      ? req.query.currency.trim().toUpperCase()
      : defaultCurrency;

    let wallet = await prisma.wallet.findFirst({
      where: {
        userId,
        currency: requestedCurrency,
      },
      orderBy: {
        createdAt: 'asc',
      },
    });

    // If the user's own currency was requested but not found, fall back to any wallet
    if (!wallet && requestedCurrency === defaultCurrency) {
      wallet = await prisma.wallet.findFirst({
        where: { userId },
        orderBy: { createdAt: 'asc' },
      });
    }

    // Auto-provision the user's default wallet if missing
    if (!wallet) {
      if (requestedCurrency === defaultCurrency) {
        wallet = await prisma.wallet.create({
          data: {
            userId,
            currency: defaultCurrency,
            balance: 0.0,
          },
        });
      } else {
        res.status(404).json({
          error: {
            code: 'WALLET_NOT_FOUND',
            message: `Wallet for currency '${requestedCurrency}' not found`,
          },
        });
        return;
      }
    }

    const response: WalletDto = {
      id: wallet.id,
      currency: wallet.currency,
      balance: Number(wallet.balance),
    };

    res.status(200).json(response);
  } catch (err: any) {
    console.error('Error fetching wallet:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve wallet',
      },
    });
  }
});

/**
 * GET /api/wallet/balances
 * Returns array of all balances for the authenticated user.
 * 
 * Blueprint Section 7:
 * GET /api/wallet/balances -> [{ currency, balance }]
 */
router.get('/balances', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    let wallets = await prisma.wallet.findMany({
      where: { userId },
      orderBy: { createdAt: 'asc' },
    });

    if (wallets.length === 0) {
      const defaultWallet = await prisma.wallet.create({
        data: {
          userId,
          currency: req.user!.primaryCurrency || DEFAULT_WALLET_CURRENCY,
          balance: 0.0,
        },
      });
      wallets = [defaultWallet];
    }

    const balances: BalanceDto[] = wallets.map((w) => ({
      currency: w.currency,
      balance: Number(w.balance),
    }));

    res.status(200).json(balances);
  } catch (err: any) {
    console.error('Error fetching wallet balances:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve wallet balances',
      },
    });
  }
});

/**
 * Source-of-funds options offered to individual travellers.
 *
 * WeWire accepts 22 values, but over half are business-only (treasury reserves,
 * owner's capital, inter-company funds). Offering those to an individual invites
 * a wrong answer on a compliance field, so the list is filtered and labelled.
 */
const INDIVIDUAL_SOURCE_OF_FUNDS = [
  { value: 'salary', label: 'Salary or wages' },
  { value: 'savings', label: 'Personal savings' },
  { value: 'investment_proceeds', label: 'Investment proceeds' },
  { value: 'pension_retirement', label: 'Pension or retirement income' },
  { value: 'sales_of_goods_and_services', label: 'Sale of goods or services' },
  { value: 'sale_of_assets', label: 'Sale of assets' },
  { value: 'sale_of_assets_real_estate', label: 'Sale of property' },
  { value: 'inheritance', label: 'Inheritance' },
  { value: 'gifts', label: 'Gift' },
  { value: 'government_benefits', label: 'Government benefits' },
  { value: 'grants', label: 'Grant or scholarship' },
  { value: 'legal_settlement', label: 'Legal settlement' },
];

/**
 * GET /api/wallet/deposit-account
 * Reports where the user is in deposit-account setup. Read-only: safe to poll.
 */
router.get('/deposit-account', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const status = await getDepositAccountStatus(req.user!.id);
    res.status(200).json({
      ...status,
      sourceOfFundsOptions: INDIVIDUAL_SOURCE_OF_FUNDS,
    });
  } catch (err: any) {
    console.error('Error reading deposit account status:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err?.message || 'Failed to read deposit account status',
      },
    });
  }
});

/**
 * POST /api/wallet/deposit-account
 * Stores the user's own source-of-funds declaration when supplied, then asks
 * WeWire to issue the virtual account. Issuance is asynchronous, so a PROVISIONING
 * response is expected and the client should poll the GET above.
 */
router.post('/deposit-account', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const raw = req.body?.sourceOfFunds;

    if (raw !== undefined) {
      if (!isSourceOfFunds(raw)) {
        res.status(400).json({
          error: {
            code: 'INVALID_SOURCE_OF_FUNDS',
            message: 'sourceOfFunds must be one of the supported values',
          },
        });
        return;
      }
      await prisma.user.update({
        where: { id: userId },
        data: { sourceOfFunds: raw },
      });
    }

    const status = await getDepositAccountStatus(userId, { provision: true });
    res.status(status.state === 'READY' ? 200 : 202).json({
      ...status,
      sourceOfFundsOptions: INDIVIDUAL_SOURCE_OF_FUNDS,
    });
  } catch (err: any) {
    console.error('Error provisioning deposit account:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err?.message || 'Failed to provision deposit account',
      },
    });
  }
});

/**
 * Bank coordinates for an issued virtual account, in the shape the app renders
 * them. Only an ACTIVE account has any: a REQUESTED one has every field null,
 * which would draw an empty details card.
 */
function formatDepositAccountDetails(depositAccount: any) {
  return {
    bankName: depositAccount.account.bankName ?? null,
    accountName: depositAccount.account.accountName ?? null,
    accountNumber: depositAccount.account.accountNumber ?? null,
    routingNumber: depositAccount.account.routingNumber ?? null,
    sortCode: depositAccount.account.sortCode ?? null,
    iban: depositAccount.account.iban ?? null,
    bic: depositAccount.account.bic ?? null,
    paymentRails: depositAccount.account.paymentRails ?? [],
    currency: depositAccount.currency,
    status: depositAccount.status,
  };
}

/**
 * The wire shape a top-up is reported in. Initiation and resume share it, so a
 * deposit picked back up later reads exactly like a freshly started one.
 */
function formatTopupResponse(fundingTx: any, depositAccount: any) {
  const accountReady = Boolean(depositAccount?.isActive);

  return {
    fundingTransactionId: fundingTx.id,
    checkoutId: fundingTx.checkoutId,
    checkoutUrl: fundingTx.checkoutId
      ? buildWeWireCheckoutUrl({
          checkoutId: fundingTx.checkoutId,
          amount: Number(fundingTx.amount),
          currency: fundingTx.currency,
        })
      : null,
    status: fundingTx.status,
    amount: Number(fundingTx.amount),
    currency: fundingTx.currency,
    accountDetails: accountReady
      ? formatDepositAccountDetails(depositAccount)
      : null,
    accountSource: accountReady ? 'wewire' : 'local',
    wewireAccountId: depositAccount?.accountId ?? null,
    accountReady,
    createdAt: fundingTx.createdAt.toISOString(),
  };
}

/**
 * The deposit a user still has in flight, newest first. Passing `amount`
 * narrows it to a transfer of the same size, which is what re-initiating the
 * same top-up is.
 */
function findPendingTopup(userId: string, currency: string, amount?: number) {
  return prisma.fundingTransaction.findFirst({
    where: {
      userId,
      currency,
      status: 'PENDING',
      ...(amount === undefined ? {} : { amount }),
    },
    orderBy: { createdAt: 'desc' },
  });
}

/**
 * How long an unfunded deposit intent stays current, in hours.
 *
 * A bank transfer that was going to arrive has arrived well inside a day, so a
 * deposit still unfunded after this is one the user walked away from.
 */
const TOPUP_EXPIRY_HOURS = 24;

function topupExpiryHours(): number {
  const raw = process.env.TOPUP_EXPIRY_HOURS;
  const parsed = raw ? parseFloat(raw) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : TOPUP_EXPIRY_HOURS;
}

/**
 * Retires deposit intents the user never funded.
 *
 * Without this, every abandoned deposit stays PENDING forever and Add Money
 * keeps restoring the oldest one, so a user works through a queue of stale
 * intents one cancellation at a time.
 *
 * EXPIRED is a UI state, not an accounting one: the row stays matchable by the
 * pay-in webhook. Someone who set up a transfer on Monday and actually sent it
 * on Wednesday must still be credited, so expiry stops us *offering* the
 * deposit, never stops us *receiving* it.
 */
async function expireStaleTopups(userId: string): Promise<number> {
  const cutoff = new Date(Date.now() - topupExpiryHours() * 60 * 60 * 1000);

  const { count } = await prisma.fundingTransaction.updateMany({
    where: {
      userId,
      status: 'PENDING',
      createdAt: { lt: cutoff },
    },
    data: { status: 'EXPIRED' },
  });

  if (count > 0) {
    console.log(
      `[Wallet] Expired ${count} unfunded deposit intent(s) for user ${userId} ` +
        `older than ${topupExpiryHours()}h. They remain creditable if the money still arrives.`
    );
  }

  return count;
}

/**
 * The user's WeWire virtual account for a currency, or null when there is none
 * to resolve. A deposit is still reportable without it, so an unreachable
 * WeWire is warned about rather than thrown.
 */
async function tryResolveDepositAccount(user: any, currency: string) {
  if (!user.wewireSubcustomerId) return null;

  try {
    return await resolveWeWireDepositAccount(user.wewireSubcustomerId, currency);
  } catch (err: any) {
    console.warn(
      `[Wallet] Could not resolve WeWire deposit account for ${user.id}: ${err?.message}`
    );
    return null;
  }
}

/**
 * POST /api/wallet/topup
 * Initiates funding workflow per Blueprint Section 7.
 * Body: { amount: number, currency?: string }
 * Returns: { checkoutUrl, checkoutId, fundingTransactionId, status, amount, currency, accountDetails }
 *
 * 201 when a new deposit was opened, 200 when an identical one was already
 * pending and is handed back instead.
 */
router.post('/topup', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    const { amount, currency: rawCurrency } = req.body;

    const numericAmount = typeof amount === 'string' ? parseFloat(amount) : Number(amount);
    if (isNaN(numericAmount) || numericAmount <= 0) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Amount must be a positive number',
        },
      });
      return;
    }

    const currency = (typeof rawCurrency === 'string' && rawCurrency.trim())
      ? rawCurrency.trim().toUpperCase()
      : (user.primaryCurrency || DEFAULT_WALLET_CURRENCY);

    // Resolve the virtual account before writing anything. Money can only
    // arrive on an ACTIVE account, so a top-up that cannot be funded must not
    // leave a PENDING deposit behind for a later pay-in to match against.
    const depositAccount = await tryResolveDepositAccount(user, currency);

    if (!depositAccount || !depositAccount.isActive) {
      res.status(409).json({
        error: {
          code: 'DEPOSIT_ACCOUNT_NOT_READY',
          message:
            'A deposit account has to be issued before money can be added. Complete verification and wait for the account to go live.',
          state: depositAccount ? depositAccount.status : 'NOT_REQUESTED',
        },
      });
      return;
    }

    const wallet = await prisma.wallet.findFirst({
      where: { userId: user.id, currency },
    });
    if (wallet) {
      await prisma.wallet.update({
        where: { id: wallet.id },
        data: { wewireAccountId: depositAccount.accountId },
      });
    }

    // One pending deposit per user, currency and amount. Asking again for a
    // transfer that is already expected resumes that record rather than
    // leaving a trail of PENDING rows, only the newest of which a pay-in
    // without a reference would be credited to.
    let fundingTx = await findPendingTopup(user.id, currency, numericAmount);
    const resumed = fundingTx !== null;

    if (!fundingTx) {
      const fundingInfo = initiateWeWireFunding({
        subCustomerId: user.wewireSubcustomerId,
        userName: `${user.firstName} ${user.lastName}`,
        userId: user.id,
        amount: numericAmount,
        currency,
      });

      fundingTx = await prisma.fundingTransaction.create({
        data: {
          userId: user.id,
          amount: numericAmount,
          currency,
          checkoutId: fundingInfo.checkoutId,
          status: 'PENDING',
        },
      });
    }

    res
      .status(resumed ? 200 : 201)
      .json(formatTopupResponse(fundingTx, depositAccount));
  } catch (err: any) {
    console.error('Error initiating wallet topup:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to initiate wallet topup',
      },
    });
  }
});

/**
 * GET /api/wallet/topup/pending
 * The deposit the user still has in flight, if any, in the same shape
 * initiation returns. An app that was closed mid-deposit picks the flow back
 * up from here instead of starting a second one.
 *
 * Declared before `/topup/:id` so that "pending" is not read as an id.
 */
router.get('/topup/pending', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    const rawCurrency = req.query.currency;
    const currency = (typeof rawCurrency === 'string' && rawCurrency.trim())
      ? rawCurrency.trim().toUpperCase()
      : (user.primaryCurrency || DEFAULT_WALLET_CURRENCY);

    // Retire anything the user walked away from before offering to resume it.
    await expireStaleTopups(user.id);

    const fundingTx = await findPendingTopup(user.id, currency);
    if (!fundingTx) {
      res.status(200).json({ pending: null });
      return;
    }

    const depositAccount = await tryResolveDepositAccount(user, currency);

    res.status(200).json({
      pending: formatTopupResponse(fundingTx, depositAccount),
    });
  } catch (err: any) {
    console.error('Error reading pending topup:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to read pending topup',
      },
    });
  }
});

/**
 * GET /api/wallet/topup/:id
 * Fetches status of a specific funding transaction.
 */
router.get('/topup/:id', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { id } = req.params;

    const fundingTx = await prisma.fundingTransaction.findFirst({
      where: {
        id,
        userId,
      },
    });

    if (!fundingTx) {
      res.status(404).json({
        error: {
          code: 'NOT_FOUND',
          message: 'Funding transaction not found',
        },
      });
      return;
    }

    res.status(200).json({
      fundingTransactionId: fundingTx.id,
      checkoutId: fundingTx.checkoutId,
      status: fundingTx.status,
      // `amount` is what the user sent; `settledAmount` is what the rails
      // actually delivered, and `fee` explains the difference.
      amount: Number(fundingTx.amount),
      settledAmount:
        fundingTx.settledAmount === null ? null : Number(fundingTx.settledAmount),
      fee: Number(fundingTx.fee),
      currency: fundingTx.currency,
      createdAt: fundingTx.createdAt.toISOString(),
      updatedAt: fundingTx.updatedAt.toISOString(),
    });
  } catch (err: any) {
    console.error('Error fetching funding transaction:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve funding transaction',
      },
    });
  }
});

/**
 * POST /api/wallet/topup/:id/cancel
 *
 * Abandons a deposit the user started but never funded.
 *
 * A pending top-up is restored every time Add Money opens, so without this a
 * user who changed their mind is stuck looking at a waiting screen for an
 * amount they no longer want, with no way to start a different one.
 *
 * Cancelling only abandons our intent to receive: it cannot stop money already
 * in flight. A transfer that lands afterwards still arrives on the virtual
 * account and is still credited by the pay-in webhook -- which is why only a
 * PENDING row can be cancelled, and why a cancelled one is left matchable.
 */
router.post('/topup/:id/cancel', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { id } = req.params;

    const fundingTx = await prisma.fundingTransaction.findFirst({
      where: { id, userId },
    });

    if (!fundingTx) {
      res.status(404).json({
        error: { code: 'NOT_FOUND', message: 'Funding transaction not found' },
      });
      return;
    }

    if (fundingTx.status === 'CANCELLED') {
      // Already where the caller wants it: report success rather than an error,
      // so a double tap is harmless.
      res.status(200).json({
        fundingTransactionId: fundingTx.id,
        status: fundingTx.status,
        amount: Number(fundingTx.amount),
        currency: fundingTx.currency,
      });
      return;
    }

    if (fundingTx.status !== 'PENDING') {
      res.status(409).json({
        error: {
          code: 'NOT_CANCELLABLE',
          message: `A ${fundingTx.status.toLowerCase()} deposit cannot be cancelled`,
        },
      });
      return;
    }

    const cancelled = await prisma.fundingTransaction.update({
      where: { id: fundingTx.id },
      data: { status: 'CANCELLED' },
    });

    console.log(
      `[Wallet] Funding transaction ${cancelled.id} cancelled by user ${userId} ` +
        `(${Number(cancelled.amount)} ${cancelled.currency} never funded).`
    );

    res.status(200).json({
      fundingTransactionId: cancelled.id,
      status: cancelled.status,
      amount: Number(cancelled.amount),
      currency: cancelled.currency,
    });
  } catch (err: any) {
    console.error('Error cancelling funding transaction:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to cancel the deposit',
      },
    });
  }
});

/**
 * POST /api/wallet/topup/:id/simulate
 * Sandbox only. Asks WeWire to drop a test deposit onto the user's virtual
 * account for this funding transaction. The wallet is NOT credited here: the
 * balance moves when WeWire delivers the resulting pay-in webhook, which is
 * the same path a real deposit takes.
 */
router.post('/topup/:id/simulate', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    const { id } = req.params;

    if (!user.wewireSubcustomerId) {
      res.status(409).json({
        error: {
          code: 'NO_SUBCUSTOMER',
          message: 'This account has no WeWire sub-customer to deposit into',
        },
      });
      return;
    }

    const fundingTx = await prisma.fundingTransaction.findFirst({
      where: { id, userId: user.id },
    });

    if (!fundingTx) {
      res.status(404).json({
        error: { code: 'NOT_FOUND', message: 'Funding transaction not found' },
      });
      return;
    }

    if (fundingTx.status === 'COMPLETED') {
      res.status(409).json({
        error: {
          code: 'ALREADY_COMPLETED',
          message: 'Funding transaction has already been credited',
        },
      });
      return;
    }

    const depositAccount = await resolveWeWireDepositAccount(
      user.wewireSubcustomerId,
      fundingTx.currency
    );

    if (!depositAccount) {
      res.status(503).json({
        error: {
          code: 'NO_DEPOSIT_ACCOUNT',
          message: `No WeWire virtual account available for ${fundingTx.currency}. The sub-customer must be KYC approved and have an ACTIVE account.`,
        },
      });
      return;
    }

    if (!depositAccount.isActive) {
      res.status(409).json({
        error: {
          code: 'ACCOUNT_NOT_ACTIVE',
          message: `Virtual account is ${depositAccount.status}. Issuance is asynchronous — retry once it reaches ACTIVE.`,
          accountId: depositAccount.accountId,
          status: depositAccount.status,
        },
      });
      return;
    }

    await simulateWeWireDeposit({
      subCustomerId: user.wewireSubcustomerId,
      accountId: depositAccount.accountId,
      amount: Number(fundingTx.amount),
      currency: fundingTx.currency,
    });

    res.status(202).json({
      status: 'DEPOSIT_SIMULATED',
      fundingTransactionId: fundingTx.id,
      amount: Number(fundingTx.amount),
      currency: fundingTx.currency,
      wewireAccountId: depositAccount.accountId,
      accountStatus: depositAccount.status,
      message:
        'WeWire accepted the test deposit. The wallet is credited when the pay-in webhook arrives.',
    });
  } catch (err: any) {
    console.error('Error simulating WeWire deposit:', err?.message || err);

    // Account issuance is gated on Enhanced Due Diligence. Hand back the hosted
    // verification link so the app can send the user straight to it.
    if (err instanceof WeWireApiError && err.code === 'SUBCUSTOMER_ENHANCED_KYC_REQUIRED') {
      let kycLinkUrl: string | null = null;
      try {
        kycLinkUrl = (await getHostedKycLink(req.user!.wewireSubcustomerId!)).url;
      } catch {
        // The link is a convenience; the 403 still stands without it.
      }
      res.status(403).json({
        error: {
          code: 'ENHANCED_KYC_REQUIRED',
          message:
            'Enhanced verification must be completed before a deposit account can be issued.',
          kycLinkUrl,
        },
      });
      return;
    }

    if (err instanceof WeWireApiError && err.code === 'MISSING_COMPLIANCE_DETAILS') {
      res.status(400).json({
        error: { code: err.code, message: err.message },
      });
      return;
    }

    // A 400 from WeWire here means production, or an account that cannot take one.
    const status = err?.status === 400 ? 400 : 502;
    res.status(status).json({
      error: {
        code: status === 400 ? 'DEPOSIT_REJECTED' : 'WEWIRE_UNAVAILABLE',
        message: err?.message || 'Failed to simulate deposit',
      },
    });
  }
});

/**
 * Formats a funding transaction as a unified transaction record, in the same
 * shape the payment history uses, so the app can render money coming in beside
 * money going out without a second presentation model.
 *
 * `amount` is what the user said they would send; `settledAmount` is what the
 * rails actually delivered. Until settlement they are the same figure, so a
 * pending deposit still reads sensibly.
 */
export function formatDepositTransaction(ft: any) {
  const amount = Number(ft.amount);
  const settledAmount = ft.settledAmount === null || ft.settledAmount === undefined
    ? null
    : Number(ft.settledAmount);
  const fee = Number(ft.fee ?? 0);
  const creditedAmount = settledAmount === null ? amount : settledAmount;
  const createdAtIso = ft.createdAt instanceof Date ? ft.createdAt.toISOString() : String(ft.createdAt);
  const updatedAtIso = ft.updatedAt instanceof Date ? ft.updatedAt.toISOString() : String(ft.updatedAt);
  const vesspayReference = `VP-DEP-${String(ft.id).replace(/-/g, '').slice(0, 12).toUpperCase()}`;

  return {
    id: ft.id,
    userId: ft.userId,
    type: 'deposit',
    status: ft.status,
    // A deposit does not cross currencies: it lands in the wallet it was sent to.
    sourceCurrency: ft.currency,
    sourceAmount: amount,
    destinationCurrency: ft.currency,
    destinationAmount: creditedAmount,
    settledAmount,
    fee,
    exchangeRate: 1,
    rate: 1,
    checkoutId: ft.checkoutId,
    vesspayReference,
    reference: vesspayReference,
    wewireReference: ft.checkoutId,
    createdAt: createdAtIso,
    updatedAt: updatedAtIso,
    timestamps: {
      createdAt: createdAtIso,
      updatedAt: updatedAtIso,
    },
  };
}

/**
 * GET /api/wallet/deposits
 * Lists the user's deposits, newest first, so the activity feed can show them
 * alongside payouts. Enforces user isolation: a user only sees their own.
 */
router.get('/deposits', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const deposits = await prisma.fundingTransaction.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.status(200).json(deposits.map(formatDepositTransaction));
  } catch (err: any) {
    console.error('Error fetching deposits:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve deposits',
      },
    });
  }
});

/**
 * GET /api/wallet/deposits/:id
 * Full detail for a single deposit, so a deposit row opened by id alone (from
 * the dashboard feed) resolves the same way a payout does.
 */
router.get('/deposits/:id', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { id } = req.params;

    const deposit = await prisma.fundingTransaction.findFirst({
      where: { id, userId },
    });

    if (!deposit) {
      res.status(404).json({
        error: {
          code: 'NOT_FOUND',
          message: 'Deposit not found',
        },
      });
      return;
    }

    res.status(200).json(formatDepositTransaction(deposit));
  } catch (err: any) {
    console.error('Error fetching deposit:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve deposit',
      },
    });
  }
});


/**
 * GET /api/wallet/crypto-chains
 * The networks a user can be given a deposit address on, and which assets each
 * one accepts. Public reference data, like GET /api/banks.
 *
 * `network` (MAINNET | TESTNET) is carried through from WeWire deliberately:
 * it is decided by the API key, and a client that renders a testnet address as
 * if it were mainnet would lose real funds.
 */
router.get('/crypto-chains', async (_req: Request, res: Response): Promise<void> => {
  try {
    res.status(200).json(await getSupportedCryptoChains());
  } catch (err: any) {
    console.error('Error listing crypto chains:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve supported crypto chains',
      },
    });
  }
});

/**
 * GET  /api/wallet/crypto-address?chain=BASE
 * POST /api/wallet/crypto-address   { chain: 'BASE' }
 *
 * Returns the user's deposit address for a chain, issuing one if they have
 * none. WeWire's endpoint is itself idempotent, so both verbs are safe to
 * repeat; GET is the pollable one, because issuance is asynchronous and an
 * address arrives a moment after it is requested.
 */
async function handleCryptoAddress(req: Request, res: Response): Promise<void> {
  try {
    const userId = req.user!.id;
    const rawChain = (req.method === 'GET' ? req.query.chain : req.body?.chain) ?? '';
    const chain = rawChain.toString().trim().toUpperCase();

    if (!chain) {
      res.status(400).json({
        error: {
          code: 'MISSING_CHAIN',
          message: `chain is required. Supported chains: ${await supportedChainCodes()}`,
        },
      });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { wewireSubcustomerId: true },
    });

    if (!user?.wewireSubcustomerId) {
      res.status(409).json({
        error: {
          code: 'SUBCUSTOMER_REQUIRED',
          message: 'Complete verification before requesting a crypto deposit address',
        },
      });
      return;
    }

    let issued;
    try {
      issued = await resolveCryptoDepositAddress(user.wewireSubcustomerId, chain);
    } catch (err: any) {
      res.status(400).json({
        error: { code: 'INVALID_CHAIN', message: err?.message || 'Invalid chain' },
      });
      return;
    }

    if (!issued) {
      res.status(503).json({
        error: {
          code: 'ADDRESS_UNAVAILABLE',
          message: 'Crypto deposit addresses are not available right now',
        },
      });
      return;
    }

    // Mirror the address locally: an inbound deposit carries no reference we
    // control, so this row is the only thing that attributes it to a user.
    const stored = await prisma.cryptoDepositAddress.upsert({
      where: { userId_chain: { userId, chain: issued.chain } },
      create: {
        userId,
        subCustomerId: user.wewireSubcustomerId,
        wewireAddressId: issued.id,
        chain: issued.chain,
        network: issued.network,
        address: issued.address,
        status: issued.status,
        supportedAssets: issued.supportedAssets,
      },
      update: {
        wewireAddressId: issued.id,
        network: issued.network,
        address: issued.address,
        status: issued.status,
        supportedAssets: issued.supportedAssets,
      },
    });

    res.status(issued.isActive ? 200 : 202).json({
      chain: stored.chain,
      network: stored.network,
      address: stored.address,
      status: stored.status,
      supportedAssets: stored.supportedAssets,
      isActive: issued.isActive,
      // Said plainly rather than left for the client to infer from `status`.
      state: issued.isActive ? 'READY' : 'PROVISIONING',
    });
  } catch (err: any) {
    console.error('Error resolving crypto deposit address:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err?.message || 'Failed to resolve crypto deposit address',
      },
    });
  }
}

router.get('/crypto-address', authenticate, handleCryptoAddress);
router.post('/crypto-address', authenticate, handleCryptoAddress);

export default router;
