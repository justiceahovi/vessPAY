import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { authenticate } from '../middleware/auth';
import { initiateWeWireFunding } from '../lib/wewire';
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

    const fundingTx = await prisma.fundingTransaction.create({
      data: {
        userId: user.id,
        amount: numericAmount,
        currency,
        checkoutId: fundingInfo.checkoutId,
        status: 'PENDING',
      },
    });

    res.status(201).json({
      fundingTransactionId: fundingTx.id,
      checkoutId: fundingInfo.checkoutId,
      checkoutUrl: fundingInfo.checkoutUrl,
      status: fundingTx.status,
      amount: Number(fundingTx.amount),
      currency: fundingTx.currency,
      accountDetails: fundingInfo.accountDetails,
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
      amount: Number(fundingTx.amount),
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
 * POST /api/wallet/topup/:id/confirm
 * Confirms a sandbox funding transaction and atomically credits the user's wallet.
 */
router.post('/topup/:id/confirm', authenticate, async (req: Request, res: Response): Promise<void> => {
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

    if (fundingTx.status === 'COMPLETED') {
      const wallet = await prisma.wallet.findFirst({
        where: { userId, currency: fundingTx.currency },
      });
      res.status(200).json({
        status: 'COMPLETED',
        fundingTransactionId: fundingTx.id,
        amount: Number(fundingTx.amount),
        currency: fundingTx.currency,
        balance: Number(wallet?.balance ?? 0),
        message: 'Funding transaction already completed',
      });
      return;
    }

    // Atomically complete the funding and credit the user's wallet
    const updated = await prisma.$transaction(async (tx) => {
      const updatedTx = await tx.fundingTransaction.update({
        where: { id: fundingTx.id },
        data: { status: 'COMPLETED' },
      });

      // Credit wallet
      const existingWallet = await tx.wallet.findFirst({
        where: { userId, currency: fundingTx.currency },
      });

      let wallet;
      if (existingWallet) {
        wallet = await tx.wallet.update({
          where: { id: existingWallet.id },
          data: {
            balance: {
              increment: fundingTx.amount,
            },
          },
        });
      } else {
        wallet = await tx.wallet.create({
          data: {
            userId,
            currency: fundingTx.currency,
            balance: fundingTx.amount,
          },
        });
      }

      // Record in webhook_events as simulated pay_in
      await tx.webhookEvent.create({
        data: {
          provider: 'wewire',
          eventType: 'transaction.pay_in',
          eventId: `sim_payin_${Date.now()}_${fundingTx.id.slice(0, 8)}`,
          payload: {
            data: {
              fundingTransactionId: fundingTx.id,
              checkoutId: fundingTx.checkoutId,
              amount: Number(fundingTx.amount),
              currency: fundingTx.currency,
              status: 'SUCCESSFUL',
            },
            eventType: 'transaction.pay_in',
          },
          processed: true,
        },
      });

      return { fundingTx: updatedTx, wallet };
    });

    res.status(200).json({
      status: 'COMPLETED',
      fundingTransactionId: updated.fundingTx.id,
      amount: Number(updated.fundingTx.amount),
      currency: updated.fundingTx.currency,
      balance: Number(updated.wallet.balance),
    });
  } catch (err: any) {
    console.error('Error confirming funding transaction:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to confirm funding transaction',
      },
    });
  }
});

export default router;

