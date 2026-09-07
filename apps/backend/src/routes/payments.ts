import { Router, Request, Response } from 'express';
import {
  getExchangeRate,
  createWeWireBeneficiary,
  normalizeGhanaPhone,
  normalizeBankAccountNumber,
  resolveInstitution,
  sendWeWireDisbursement,
  type PayoutChannel,
} from '../lib/wewire';
import { verifyToken } from '../lib/auth';
import { prisma } from '../lib/db';
import { authenticate } from '../middleware/auth';
import { DEFAULT_WALLET_CURRENCY } from '../lib/currencies';

const router = Router();

// Hackathon payment fee model: 1% of source amount (USD)
export const PAYMENT_FEE_PERCENT = 0.01; // 1%

export function getPaymentFee(sourceAmountUsd: number): number {
  const envFee = process.env.PAYMENT_FEE_PERCENT;
  const percent = envFee && !isNaN(parseFloat(envFee)) ? parseFloat(envFee) : PAYMENT_FEE_PERCENT;
  const calculated = Number((sourceAmountUsd * percent).toFixed(2));
  return sourceAmountUsd > 0 ? Math.max(0.01, calculated) : 0;
}


/**
 * Optional authentication helper: attaches req.user if valid token provided.
 */
async function attachUserIfPresent(req: Request): Promise<void> {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.substring(7).trim();
    if (token) {
      const payload = verifyToken(token);
      if (payload && payload.userId) {
        try {
          const user = await prisma.user.findUnique({
            where: { id: payload.userId },
          });
          if (user) {
            req.user = user;
          }
        } catch {
          // Ignore DB error for optional auth
        }
      }
    }
  }
}

/**
 * POST /api/payments/quote
 * Per VESSPAY_BLUEPRINT.md Section 7:
 *   body: { country, network, phone, destinationAmount, destinationCurrency }
 *   res:  { sourceCurrency, sourceAmount, destinationCurrency, destinationAmount, exchangeRate, fee, total }
 */
router.post('/quote', async (req: Request, res: Response): Promise<void> => {
  try {
    await attachUserIfPresent(req);

    const body = req.body || {};
    const { country, network, phone } = body;
    let rawDestAmount = body.destinationAmount;
    let rawSourceAmount = body.sourceAmount;

    // Resolve currencies (source defaults to the wallet the user holds, destination = GHS)
    let sourceCurrency = (
      body.sourceCurrency || req.user?.primaryCurrency || DEFAULT_WALLET_CURRENCY
    ).toString().trim().toUpperCase();
    let destinationCurrency = body.destinationCurrency
      ? body.destinationCurrency.toString().trim().toUpperCase()
      : country && (country.toString().toUpperCase() === 'GH' || country.toString().toUpperCase() === 'GHANA')
      ? 'GHS'
      : 'GHS';

    // Validate amount
    let destinationAmount: number | null = null;
    let sourceAmount: number | null = null;

    if (rawDestAmount !== undefined && rawDestAmount !== null && rawDestAmount !== '') {
      const parsed = typeof rawDestAmount === 'number' ? rawDestAmount : parseFloat(rawDestAmount);
      if (isNaN(parsed) || parsed <= 0) {
        res.status(400).json({
          error: {
            code: 'INVALID_AMOUNT',
            message: 'destinationAmount must be a positive number greater than 0',
          },
        });
        return;
      }
      destinationAmount = Number(parsed.toFixed(2));
    } else if (rawSourceAmount !== undefined && rawSourceAmount !== null && rawSourceAmount !== '') {
      const parsed = typeof rawSourceAmount === 'number' ? rawSourceAmount : parseFloat(rawSourceAmount);
      if (isNaN(parsed) || parsed <= 0) {
        res.status(400).json({
          error: {
            code: 'INVALID_AMOUNT',
            message: 'sourceAmount must be a positive number greater than 0',
          },
        });
        return;
      }
      sourceAmount = Number(parsed.toFixed(2));
    } else {
      res.status(400).json({
        error: {
          code: 'INVALID_AMOUNT',
          message: 'destinationAmount (or sourceAmount) is required and must be greater than 0',
        },
      });
      return;
    }

    // Look up exchange rate via T4.1 rates integration
    const rateResult = await getExchangeRate(sourceCurrency, destinationCurrency);

    if (!rateResult) {
      res.status(400).json({
        error: {
          code: 'UNSUPPORTED_CURRENCY_PAIR',
          message: `Currency pair ${sourceCurrency}/${destinationCurrency} is not supported`,
        },
      });
      return;
    }

    const exchangeRate = rateResult.rate;

    // Calculate source and destination amounts
    if (destinationAmount !== null) {
      sourceAmount = Number((destinationAmount / exchangeRate).toFixed(2));
    } else if (sourceAmount !== null) {
      destinationAmount = Number((sourceAmount * exchangeRate).toFixed(2));
    }

    const fee = getPaymentFee(sourceAmount!);
    const total = Number((sourceAmount! + fee).toFixed(2));

    res.status(200).json({
      sourceCurrency,
      sourceAmount,
      destinationCurrency,
      destinationAmount,
      exchangeRate,
      fee,
      total,
      ...(country ? { country: country.toString().toUpperCase() } : {}),
      ...(network ? { network } : {}),
      ...(phone ? { phone } : {}),
    });
  } catch (err: any) {
    console.error('Error calculating payment quote:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to calculate payment quote',
      },
    });
  }
});

/**
 * POST /api/payments
 * Per VESSPAY_BLUEPRINT.md Section 7:
 *   body: { country, network, phone, destinationAmount, destinationCurrency, idempotencyKey, beneficiaryId? }
 *   res:  { transactionId, status }
 * 
 * Enforces idempotency, recalculates quote server-side, verifies wallet balance,
 * reuses/creates beneficiary, and records a transaction in CREATED status.
 */
router.post('/', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const body = req.body || {};

    // 1. Idempotency Key check (Section 10 & T5.2 acceptance criteria)
    const idempotencyKey = (
      body.idempotencyKey ||
      req.headers['idempotency-key'] ||
      req.headers['x-idempotency-key'] ||
      ''
    )
      .toString()
      .trim();

    if (!idempotencyKey) {
      res.status(400).json({
        error: {
          code: 'MISSING_IDEMPOTENCY_KEY',
          message: 'idempotencyKey is required for payment creation',
        },
      });
      return;
    }

    const existingTx = await prisma.transaction.findUnique({
      where: { idempotencyKey },
    });

    if (existingTx) {
      if (existingTx.userId === userId) {
        // Idempotent hit: return existing transaction
        res.status(200).json({
          transactionId: existingTx.id,
          status: existingTx.status,
          wewireTransactionId: existingTx.wewireTransactionId,
        });
        return;
      } else {
        res.status(409).json({
          error: {
            code: 'IDEMPOTENCY_CONFLICT',
            message: 'This idempotency key has already been used by another account',
          },
        });
        return;
      }
    }

    // 2. Validate destination amount
    const rawDestAmount = body.destinationAmount;
    const parsedAmount = typeof rawDestAmount === 'number' ? rawDestAmount : parseFloat(rawDestAmount);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      res.status(400).json({
        error: {
          code: 'INVALID_AMOUNT',
          message: 'destinationAmount is required and must be greater than 0',
        },
      });
      return;
    }
    const destinationAmount = Number(parsedAmount.toFixed(2));

    // Resolve currencies & country
    const destinationCurrency = (body.destinationCurrency || 'GHS').toString().trim().toUpperCase();
    const sourceCurrency = (
      body.sourceCurrency || req.user?.primaryCurrency || DEFAULT_WALLET_CURRENCY
    ).toString().trim().toUpperCase();
    const country = (body.country || 'GH').toString().trim().toUpperCase();

    // 3. Resolve recipient / beneficiary
    let beneficiaryId = body.beneficiaryId?.toString().trim();
    let recipientName = (body.recipientName || body.name || '').toString().trim();
    let network = (body.network || body.bankCode || '').toString().trim();
    let phone = body.phone?.toString().trim();
    let accountNumber = (body.accountNumber || '').toString().trim();
    let channel: PayoutChannel =
      (body.channel || '').toString().trim().toUpperCase() === 'BANK'
        ? 'BANK'
        : 'MOBILE_MONEY';
    let institutionCode = '';

    let beneficiary: any = null;

    if (beneficiaryId) {
      beneficiary = await prisma.beneficiary.findFirst({
        where: { id: beneficiaryId, userId },
      });
      if (!beneficiary) {
        res.status(404).json({
          error: {
            code: 'BENEFICIARY_NOT_FOUND',
            message: `Beneficiary with ID ${beneficiaryId} not found`,
          },
        });
        return;
      }
      recipientName = beneficiary.name;
      network = beneficiary.network;
      phone = beneficiary.phone;
      accountNumber = beneficiary.accountNumber || '';
      channel = beneficiary.channel === 'BANK' ? 'BANK' : 'MOBILE_MONEY';
      institutionCode = beneficiary.institutionCode || '';
    } else {
      if (!network) {
        res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message:
              'network is required: a mobile money operator (MTN, Telecel, AirtelTigo) or a bank code from GET /api/banks',
          },
        });
        return;
      }

      // Resolve the operator or bank against WeWire's institution list
      let institution;
      try {
        institution = await resolveInstitution(network, destinationCurrency);
      } catch (err: any) {
        res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: err.message || 'Invalid network or bank',
          },
        });
        return;
      }

      // An explicit channel wins, otherwise the institution decides
      channel = ((body.channel || '').toString().trim().toUpperCase() === 'BANK'
        ? 'BANK'
        : (body.channel || '').toString().trim().toUpperCase() === 'MOBILE_MONEY'
        ? 'MOBILE_MONEY'
        : institution.channel) as PayoutChannel;

      if (channel !== institution.channel) {
        res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: `${institution.name} is a ${institution.channel === 'BANK' ? 'bank' : 'mobile money'} institution and cannot be paid over the ${channel} channel`,
          },
        });
        return;
      }

      institutionCode = institution.code;
      network = institution.name;

      let destinationAccount: string;

      if (channel === 'BANK') {
        if (!accountNumber) {
          res.status(400).json({
            error: {
              code: 'INVALID_INPUT',
              message: 'accountNumber is required for a bank payout',
            },
          });
          return;
        }

        const normalizedAccount = normalizeBankAccountNumber(accountNumber);
        if (!normalizedAccount) {
          res.status(400).json({
            error: {
              code: 'INVALID_INPUT',
              message: 'Please provide a valid bank account number (8-20 digits)',
            },
          });
          return;
        }

        // A bank credits by account name, so it is not optional here
        if (!recipientName || recipientName.length < 2) {
          res.status(400).json({
            error: {
              code: 'INVALID_INPUT',
              message: 'recipientName is required for a bank payout (the account holder name)',
            },
          });
          return;
        }

        accountNumber = normalizedAccount;
        destinationAccount = normalizedAccount;
        phone = undefined;
      } else {
        if (!phone) {
          res.status(400).json({
            error: {
              code: 'INVALID_INPUT',
              message: 'phone number is required',
            },
          });
          return;
        }

        const { msisdn } = normalizeGhanaPhone(phone);
        if (!/^0[235]\d{8}$/.test(msisdn)) {
          res.status(400).json({
            error: {
              code: 'INVALID_INPUT',
              message: 'Please provide a valid 10-digit Ghana mobile money phone number (e.g. 024XXXXXXX)',
            },
          });
          return;
        }

        phone = msisdn;
        accountNumber = '';
        destinationAccount = msisdn;
      }

      // Reuse an existing beneficiary for the same destination account.
      // Rows created before the bank channel existed carry no institutionCode,
      // so match those on their stored network name and backfill the code --
      // otherwise WeWire rejects the re-registration as a duplicate.
      const candidates = await prisma.beneficiary.findMany({
        where: {
          userId,
          ...(channel === 'BANK'
            ? { accountNumber: destinationAccount }
            : { phone: destinationAccount }),
        },
        orderBy: { createdAt: 'desc' },
      });

      beneficiary = candidates.find((row) => row.institutionCode === institution.code) || null;

      if (!beneficiary) {
        for (const row of candidates.filter((r) => !r.institutionCode)) {
          try {
            const rowInstitution = await resolveInstitution(row.network, destinationCurrency);
            if (rowInstitution.code === institution.code) {
              beneficiary = row;
              break;
            }
          } catch {
            // A network we can no longer resolve is not a match
          }
        }
      }

      if (beneficiary && (!beneficiary.institutionCode || beneficiary.channel !== channel)) {
        beneficiary = await prisma.beneficiary.update({
          where: { id: beneficiary.id },
          data: {
            institutionCode: institution.code,
            channel,
            network: institution.name,
          },
        });
      }

      if (!beneficiary) {
        // Create new beneficiary via T5.1 integration
        const finalName = recipientName || `Recipient ${destinationAccount}`;
        const weWireRes = await createWeWireBeneficiary({
          name: finalName,
          network: institution.code,
          channel,
          phone: channel === 'MOBILE_MONEY' ? destinationAccount : undefined,
          accountNumber: channel === 'BANK' ? destinationAccount : undefined,
          country,
          subCustomerId: req.user?.wewireSubcustomerId || null,
          email: req.user?.email || null,
        });

        beneficiary = await prisma.beneficiary.create({
          data: {
            userId,
            name: finalName,
            network: institution.name,
            channel,
            institutionCode: institution.code,
            phone: channel === 'MOBILE_MONEY' ? destinationAccount : null,
            accountNumber: channel === 'BANK' ? destinationAccount : null,
            country,
            wewireBeneficiaryId: weWireRes.wewireBeneficiaryId,
            wewireAccountId: weWireRes.wewireAccountId,
          },
        });
      }

      recipientName = recipientName || beneficiary.name;
      network = beneficiary.network;
      phone = beneficiary.phone || undefined;
      accountNumber = beneficiary.accountNumber || '';
      institutionCode = beneficiary.institutionCode || institution.code;
    }

    // 4. Server-side quote recalculation (Section 10 non-negotiable rule)
    const rateResult = await getExchangeRate(sourceCurrency, destinationCurrency);
    if (!rateResult) {
      res.status(400).json({
        error: {
          code: 'UNSUPPORTED_CURRENCY_PAIR',
          message: `Currency pair ${sourceCurrency}/${destinationCurrency} is not supported`,
        },
      });
      return;
    }

    const exchangeRate = rateResult.rate;
    const sourceAmount = Number((destinationAmount / exchangeRate).toFixed(2));
    const fee = getPaymentFee(sourceAmount);
    const total = Number((sourceAmount + fee).toFixed(2));

    // 5. Wallet balance verification
    const wallet = await prisma.wallet.findFirst({
      where: { userId, currency: sourceCurrency },
    });
    const balance = Number(wallet?.balance ?? 0);

    if (balance < total) {
      res.status(400).json({
        error: {
          code: 'INSUFFICIENT_FUNDS',
          message: `Insufficient wallet balance. Required: $${total.toFixed(2)}, Available: $${balance.toFixed(2)}`,
        },
      });
      return;
    }

    // 6. Create transaction record in CREATED status
    const transaction = await prisma.transaction.create({
      data: {
        userId,
        type: 'payout',
        status: 'CREATED',
        sourceCurrency,
        sourceAmount,
        destinationCurrency,
        destinationAmount,
        fee,
        exchangeRate,
        recipientName: recipientName || beneficiary?.name || 'Recipient',
        recipientPhone: phone || beneficiary?.phone,
        recipientAccount: accountNumber || beneficiary?.accountNumber || null,
        channel,
        institutionCode: institutionCode || beneficiary?.institutionCode || null,
        network: network || beneficiary?.network,
        country: country || beneficiary?.country || 'GH',
        idempotencyKey,
      },
    });

    // 7. Call WeWire real disbursement endpoint (T5.3)
    let disbursementResult;
    try {
      disbursementResult = await sendWeWireDisbursement({
        idempotencyKey: `VP-DISB-${transaction.id}`,
        amount: destinationAmount,
        currency: destinationCurrency,
        network: institutionCode || beneficiary?.institutionCode || network || 'MTN',
        channel,
        phone: channel === 'MOBILE_MONEY' ? phone || beneficiary?.phone || '' : undefined,
        accountNumber:
          channel === 'BANK' ? accountNumber || beneficiary?.accountNumber || '' : undefined,
        recipientName: recipientName || beneficiary?.name || 'Recipient',
        reference: `VP-PAY-${transaction.id.replace(/-/g, '').slice(0, 12)}`,
        memo: 'VessPay Payout',
      });
    } catch (err: any) {
      console.error('WeWire disbursement request failed:', err);
      // Move transaction to FAILED if WeWire rejected the request synchronously
      await prisma.transaction.update({
        where: { id: transaction.id },
        data: { status: 'FAILED' },
      });

      res.status(502).json({
        error: {
          code: 'WEWIRE_PAYOUT_FAILED',
          message: err.message || 'WeWire payout dispatch failed',
        },
        transactionId: transaction.id,
        status: 'FAILED',
      });
      return;
    }

    // 8. Store returned wewire_transaction_id and move local transaction to PENDING
    // Per Section 9: Do NOT mark COMPLETED here — that only happens via webhook (T5.4)
    // Wallet ledger debit also happens on transition to COMPLETED via webhook (T5.4)
    // WeWire's own disbursement fee (only known once they've processed the request)
    // is recorded here so it gets passed on to the user's debit instead of vessPay
    // absorbing it -- see webhooks.ts totalDebit calculation.
    const wewireFee = disbursementResult.fee ? Number(disbursementResult.fee) : 0;
    const updatedTx = await prisma.transaction.update({
      where: { id: transaction.id },
      data: {
        wewireTransactionId: disbursementResult.wewireTransactionId,
        wewireFee: isNaN(wewireFee) ? 0 : wewireFee,
        status: 'PENDING',
      },
    });

    res.status(201).json({
      transactionId: updatedTx.id,
      status: updatedTx.status,
      wewireTransactionId: updatedTx.wewireTransactionId,
    });
  } catch (err: any) {
    console.error('Error creating payment:', err);
    res.status(500).json({
      error: {
        code: 'PAYMENT_CREATION_FAILED',
        message: err.message || 'Failed to create payment',
      },
    });
  }
});

/**
 * Formats a transaction record to return full detail per Blueprint Section 7 & T5.5:
 * type, status, amounts, currencies, fee, rate, recipient, network, WeWire reference, VessPay reference, timestamps.
 */
export function formatTransactionDetail(tx: any) {
  const sourceAmount = typeof tx.sourceAmount === 'number' ? tx.sourceAmount : Number(tx.sourceAmount);
  const destinationAmount = typeof tx.destinationAmount === 'number' ? tx.destinationAmount : Number(tx.destinationAmount);
  const fee = typeof tx.fee === 'number' ? tx.fee : Number(tx.fee);
  const wewireFee = tx.wewireFee !== undefined && tx.wewireFee !== null
    ? (typeof tx.wewireFee === 'number' ? tx.wewireFee : Number(tx.wewireFee))
    : 0;
  const totalFee = Number((fee + wewireFee).toFixed(2));
  const exchangeRate = typeof tx.exchangeRate === 'number' ? tx.exchangeRate : Number(tx.exchangeRate);
  const createdAtIso = tx.createdAt instanceof Date ? tx.createdAt.toISOString() : String(tx.createdAt);
  const updatedAtIso = tx.updatedAt instanceof Date ? tx.updatedAt.toISOString() : String(tx.updatedAt);
  const vesspayReference = `VP-PAY-${tx.id.replace(/-/g, '').slice(0, 12).toUpperCase()}`;

  return {
    id: tx.id,
    userId: tx.userId,
    type: tx.type,
    status: tx.status,
    sourceCurrency: tx.sourceCurrency,
    sourceAmount,
    destinationCurrency: tx.destinationCurrency,
    destinationAmount,
    fee,
    wewireFee,
    totalFee,
    exchangeRate,
    rate: exchangeRate,
    recipient: {
      name: tx.recipientName,
      phone: tx.recipientPhone,
      accountNumber: tx.recipientAccount,
      network: tx.network,
      channel: tx.channel || 'MOBILE_MONEY',
      institutionCode: tx.institutionCode,
      country: tx.country,
    },
    recipientName: tx.recipientName,
    recipientPhone: tx.recipientPhone,
    recipientAccount: tx.recipientAccount,
    channel: tx.channel || 'MOBILE_MONEY',
    institutionCode: tx.institutionCode,
    network: tx.network,
    country: tx.country,
    wewireTransactionId: tx.wewireTransactionId,
    wewireReference: tx.wewireTransactionId,
    vesspayReference,
    reference: vesspayReference,
    idempotencyKey: tx.idempotencyKey,
    createdAt: createdAtIso,
    updatedAt: updatedAtIso,
    timestamps: {
      createdAt: createdAtIso,
      updatedAt: updatedAtIso,
    },
  };
}

/**
 * GET /api/payments
 * Lists all transactions for the authenticated user, ordered by creation date descending.
 * Enforces strict user isolation: a user only sees their own transactions.
 */
router.get('/', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const transactions = await prisma.transaction.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.status(200).json(transactions.map(formatTransactionDetail));
  } catch (err: any) {
    console.error('Error fetching transactions:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve transactions',
      },
    });
  }
});

/**
 * GET /api/payments/:id
 * Retrieves full detail for a single transaction by ID.
 * Enforces user isolation: returns 404 if the transaction belongs to another user.
 */
router.get('/:id', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { id } = req.params;

    const transaction = await prisma.transaction.findFirst({
      where: { id, userId },
    });

    if (!transaction) {
      res.status(404).json({
        error: {
          code: 'NOT_FOUND',
          message: 'Transaction not found',
        },
      });
      return;
    }

    res.status(200).json(formatTransactionDetail(transaction));
  } catch (err: any) {
    console.error('Error fetching transaction:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve transaction',
      },
    });
  }
});

export default router;

