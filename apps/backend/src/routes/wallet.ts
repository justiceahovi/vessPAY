import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { authenticate } from '../middleware/auth';
import { getDepositAccountStatus } from '../lib/deposit-account';
import {
  getHostedKycLink,
  isSourceOfFunds,
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
 * POST /api/wallet/topup
 * Initiates funding workflow per Blueprint Section 7.
 * Body: { amount: number, currency?: string }
 * Returns: { checkoutUrl, checkoutId, fundingTransactionId, status, amount, currency, accountDetails }
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

    const fundingInfo = initiateWeWireFunding({
      subCustomerId: user.wewireSubcustomerId,
      userName: `${user.firstName} ${user.lastName}`,
      userId: user.id,
      amount: numericAmount,
      currency,
    });

    // Prefer the user's real WeWire virtual account for this currency. When
    // WeWire is unreachable or the sub-customer is not KYC-approved yet we
    // still hand back the local demo rails rather than blocking the top-up.
    let depositAccount = null;
    if (user.wewireSubcustomerId) {
      try {
        depositAccount = await resolveWeWireDepositAccount(
          user.wewireSubcustomerId,
          currency
        );
      } catch (err: any) {
        console.warn(
          `[Wallet] Could not resolve WeWire deposit account for ${user.id}: ${err?.message}`
        );
      }
    }

    const fundingTx = await prisma.fundingTransaction.create({
      data: {
        userId: user.id,
        amount: numericAmount,
        currency,
        checkoutId: fundingInfo.checkoutId,
        status: 'PENDING',
      },
    });

    if (depositAccount) {
      const wallet = await prisma.wallet.findFirst({
        where: { userId: user.id, currency },
      });
      if (wallet) {
        await prisma.wallet.update({
          where: { id: wallet.id },
          data: { wewireAccountId: depositAccount.accountId },
        });
      }
    }

    // Bank details only exist once the account is ACTIVE: a REQUESTED account
    // has every field null, which would render an empty details card. Fall back
    // to the local demo rails rather than showing blanks.
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

    const accountDetails =
      depositAccount && depositAccount.isActive
        ? {
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
          }
        : fundingInfo.accountDetails;

    res.status(201).json({
      fundingTransactionId: fundingTx.id,
      checkoutId: fundingInfo.checkoutId,
      checkoutUrl: fundingInfo.checkoutUrl,
      status: fundingTx.status,
      amount: Number(fundingTx.amount),
      currency: fundingTx.currency,
      accountDetails,
      accountSource:
        depositAccount && depositAccount.isActive ? 'wewire' : 'local',
      wewireAccountId: depositAccount?.accountId ?? null,
      accountReady: depositAccount?.isActive ?? false,
      createdAt: fundingTx.createdAt.toISOString(),
    });
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

export default router;
