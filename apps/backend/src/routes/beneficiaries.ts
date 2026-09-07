import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../lib/db';
import {
  createWeWireBeneficiary,
  deleteWeWireBeneficiary,
  normalizePhone,
  normalizeBankAccountNumber,
  accountNumberRuleText,
  lookupAccountName,
  resolveInstitution,
  getCorridor,
} from '../lib/wewire';

const router = Router();

// Protect all beneficiary endpoints with JWT authentication
router.use(authenticate);

/**
 * GET /api/beneficiaries
 * Returns list of saved beneficiaries for the authenticated user.
 */
router.get('/', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({
        error: { code: 'UNAUTHORIZED', message: 'Authentication required' },
      });
    }

    const beneficiaries = await prisma.beneficiary.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        name: true,
        network: true,
        channel: true,
        institutionCode: true,
        phone: true,
        accountNumber: true,
        country: true,
        wewireBeneficiaryId: true,
        wewireAccountId: true,
        createdAt: true,
      },
    });

    return res.status(200).json(beneficiaries);
  } catch (err: any) {
    console.error('Error listing beneficiaries:', err);
    return res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to retrieve beneficiaries' },
    });
  }
});

/**
 * POST /api/beneficiaries
 * Creates a beneficiary row and the corresponding WeWire beneficiary + MoMo account.
 */
router.post('/', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({
        error: { code: 'UNAUTHORIZED', message: 'Authentication required' },
      });
    }

    const { name, network, phone, country, accountNumber } = req.body || {};

    // 1. Validation
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message: 'Recipient name is required (at least 2 characters)',
        },
      });
    }

    if (!network || typeof network !== 'string') {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message:
            'Network is required: a mobile money operator (MTN, Telecel, AirtelTigo) or a bank code from GET /api/banks',
        },
      });
    }

    // The corridor comes from an explicit currency, else the beneficiary's
    // country, else Ghana -- which is what this endpoint assumed outright
    // before a second corridor existed.
    const corridor = getCorridor(req.body?.currency?.toString() || country?.toString() || 'GH');
    const payoutCurrency = corridor.currency;

    let institution;
    try {
      institution = await resolveInstitution(network, payoutCurrency);
    } catch (err: any) {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message: err.message || 'Invalid network or bank',
        },
      });
    }

    const requestedChannel = (req.body?.channel || '').toString().trim().toUpperCase();
    const channel = requestedChannel === 'BANK' || requestedChannel === 'MOBILE_MONEY'
      ? requestedChannel
      : institution.channel;

    if (channel !== institution.channel) {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message: `${institution.name} is a ${institution.channel === 'BANK' ? 'bank' : 'mobile money'} institution and cannot be paid over the ${channel} channel`,
        },
      });
    }

    let msisdn: string | null = null;
    let bankAccount: string | null = null;

    if (channel === 'BANK') {
      if (!accountNumber || typeof accountNumber !== 'string') {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: 'Account number is required for a bank beneficiary',
          },
        });
      }

      bankAccount = normalizeBankAccountNumber(accountNumber, payoutCurrency);
      if (!bankAccount) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: `Please provide a valid ${corridor.name} bank account number (${accountNumberRuleText(payoutCurrency)})`,
          },
        });
      }
    } else {
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: 'Phone number is required',
          },
        });
      }

      const normalized = normalizePhone(phone, payoutCurrency);
      msisdn = normalized.msisdn;
      if (!normalized.isValid) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: `Please provide a valid 10-digit ${corridor.name} mobile money phone number (e.g. 024XXXXXXX)`,
          },
        });
      }
    }

    // 2. Fetch authenticated user details for subcustomer scoping
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { email: true, wewireSubcustomerId: true },
    });

    // 3. Create beneficiary + beneficiary account in WeWire
    const weWireResult = await createWeWireBeneficiary({
      name: name.trim(),
      network: institution.code,
      channel,
      phone: msisdn || undefined,
      accountNumber: bankAccount || undefined,
      country: country || corridor.country,
      currency: payoutCurrency,
      subCustomerId: user?.wewireSubcustomerId || null,
      email: user?.email || null,
    });

    // 4. Save beneficiary in local database
    const beneficiary = await prisma.beneficiary.create({
      data: {
        userId,
        name: name.trim(),
        network: institution.name,
        channel,
        institutionCode: institution.code,
        phone: msisdn,
        accountNumber: bankAccount,
        country: country || corridor.country,
        wewireBeneficiaryId: weWireResult.wewireBeneficiaryId,
        wewireAccountId: weWireResult.wewireAccountId,
      },
    });

    return res.status(201).json(beneficiary);
  } catch (err: any) {
    console.error('Error creating beneficiary:', err);
    return res.status(500).json({
      error: {
        code: 'BENEFICIARY_CREATION_FAILED',
        message: err.message || 'Failed to create beneficiary',
      },
    });
  }
});

/**
 * GET /api/beneficiaries/resolve?phone=...&network=...
 * Resolves a recipient name for a Ghana mobile money number so the Pay Anyone
 * flow can auto-fill it as the user types. Looks at the user's saved
 * beneficiaries first, then falls back to a previously paid recipient.
 * Always 200 with { resolved: false } when nothing is known about the number.
 */
router.get('/resolve', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({
        error: { code: 'UNAUTHORIZED', message: 'Authentication required' },
      });
    }

    const phoneInput = (req.query.phone || '').toString().trim();
    const accountInput = (req.query.accountNumber || '').toString().trim();
    const networkInput = (req.query.network || '').toString().trim();
    const currency = (req.query.currency || 'GHS').toString().trim().toUpperCase();

    if (!phoneInput && !accountInput) {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message: 'phone (mobile money) or accountNumber (bank) is required',
        },
      });
    }

    // Resolve the operator or bank, so the lookup is addressed to the right rail
    let institution = null;
    if (networkInput) {
      try {
        institution = await resolveInstitution(networkInput, currency);
      } catch (err: any) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: err.message || 'Invalid network or bank',
          },
        });
      }
    }

    const isBank = accountInput.length > 0 && institution?.channel === 'BANK';

    const resolveCorridor = getCorridor(currency);

    let destinationAccount: string;
    if (isBank) {
      const normalized = normalizeBankAccountNumber(accountInput, currency);
      if (!normalized) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: `Please provide a valid ${resolveCorridor.name} bank account number (${accountNumberRuleText(currency)})`,
          },
        });
      }
      destinationAccount = normalized;
    } else {
      const normalized = normalizePhone(phoneInput, currency);
      if (!normalized.isValid) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: resolveCorridor.channels.includes('MOBILE_MONEY')
              ? `Please provide a valid 10-digit ${resolveCorridor.name} mobile money phone number (e.g. 024XXXXXXX)`
              : `${resolveCorridor.name} has no mobile money channel -- look up a bank account number instead`,
          },
        });
      }
      destinationAccount = normalized.msisdn;
    }

    const network = institution?.name ?? null;
    const channel = institution?.channel ?? (isBank ? 'BANK' : 'MOBILE_MONEY');

    // Placeholder names auto-generated for unnamed recipients are not real names.
    const isPlaceholderName = (name?: string | null) =>
      !name || name.trim().length < 2 || /^Recipient\s+\d+$/i.test(name.trim());

    // 1. Name enquiry with the operator or bank. This is the only source that
    // actually confirms who owns the account, so it wins over local history.
    if (institution) {
      const lookup = await lookupAccountName({
        accountCode: institution.code,
        accountNumber: destinationAccount,
        currency,
      });

      if (lookup && !isPlaceholderName(lookup.accountName)) {
        return res.status(200).json({
          resolved: true,
          verified: true,
          phone: isBank ? null : destinationAccount,
          accountNumber: isBank ? destinationAccount : null,
          network,
          institutionCode: institution.code,
          channel,
          name: lookup.accountName,
          source: 'provider',
        });
      }
    }

    // 2. Saved beneficiaries -- same institution first, then the account on any.
    const beneficiaries = await prisma.beneficiary.findMany({
      where: {
        userId,
        ...(isBank ? { accountNumber: destinationAccount } : { phone: destinationAccount }),
      },
      orderBy: { createdAt: 'desc' },
      select: { name: true, network: true, institutionCode: true },
    });

    const beneficiaryMatch =
      (institution
        ? beneficiaries.find(
            (b) => b.institutionCode === institution.code && !isPlaceholderName(b.name)
          )
        : undefined) || beneficiaries.find((b) => !isPlaceholderName(b.name));

    if (beneficiaryMatch) {
      return res.status(200).json({
        resolved: true,
        verified: false,
        phone: isBank ? null : destinationAccount,
        accountNumber: isBank ? destinationAccount : null,
        network: beneficiaryMatch.network,
        institutionCode: beneficiaryMatch.institutionCode ?? institution?.code ?? null,
        channel,
        name: beneficiaryMatch.name.trim(),
        source: 'beneficiary',
      });
    }

    // 3. Previously paid recipient with the same destination account.
    const transactions = await prisma.transaction.findMany({
      where: {
        userId,
        type: 'payout',
        ...(isBank
          ? { recipientAccount: destinationAccount }
          : { recipientPhone: destinationAccount }),
      },
      orderBy: { createdAt: 'desc' },
      take: 10,
      select: { recipientName: true, network: true, institutionCode: true },
    });

    const transactionMatch =
      (institution
        ? transactions.find(
            (t) => t.institutionCode === institution.code && !isPlaceholderName(t.recipientName)
          )
        : undefined) || transactions.find((t) => !isPlaceholderName(t.recipientName));

    if (transactionMatch) {
      return res.status(200).json({
        resolved: true,
        verified: false,
        phone: isBank ? null : destinationAccount,
        accountNumber: isBank ? destinationAccount : null,
        network: transactionMatch.network || network,
        institutionCode: transactionMatch.institutionCode ?? institution?.code ?? null,
        channel,
        name: (transactionMatch.recipientName || '').trim(),
        source: 'history',
      });
    }

    // 4. Nothing known and nothing confirmed -- the user names the recipient.
    return res.status(200).json({
      resolved: false,
      verified: false,
      phone: isBank ? null : destinationAccount,
      accountNumber: isBank ? destinationAccount : null,
      network,
      institutionCode: institution?.code ?? null,
      channel,
      name: null,
      source: null,
    });
  } catch (err: any) {
    console.error('Error resolving recipient name:', err);
    return res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to resolve recipient name' },
    });
  }
});

/**
 * GET /api/beneficiaries/:id
 * Retrieves a single beneficiary by ID.
 */
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { id } = req.params;

    if (!userId) {
      return res.status(401).json({
        error: { code: 'UNAUTHORIZED', message: 'Authentication required' },
      });
    }

    const beneficiary = await prisma.beneficiary.findFirst({
      where: {
        id,
        userId,
      },
    });

    if (!beneficiary) {
      return res.status(404).json({
        error: { code: 'NOT_FOUND', message: 'Beneficiary not found' },
      });
    }

    return res.status(200).json(beneficiary);
  } catch (err: any) {
    console.error('Error fetching beneficiary:', err);
    return res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to retrieve beneficiary' },
    });
  }
});

/**
 * DELETE /api/beneficiaries/:id
 * Deletes a beneficiary from WeWire and the local database. Returns 204.
 */
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { id } = req.params;

    if (!userId) {
      return res.status(401).json({
        error: { code: 'UNAUTHORIZED', message: 'Authentication required' },
      });
    }

    const beneficiary = await prisma.beneficiary.findFirst({
      where: {
        id,
        userId,
      },
    });

    if (!beneficiary) {
      return res.status(404).json({
        error: { code: 'NOT_FOUND', message: 'Beneficiary not found' },
      });
    }

    // Clean up from WeWire sandbox if present
    if (beneficiary.wewireBeneficiaryId) {
      await deleteWeWireBeneficiary(beneficiary.wewireBeneficiaryId);
    }

    // Delete from local database
    await prisma.beneficiary.delete({
      where: { id },
    });

    return res.status(204).send();
  } catch (err: any) {
    console.error('Error deleting beneficiary:', err);
    return res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to delete beneficiary' },
    });
  }
});

export default router;
