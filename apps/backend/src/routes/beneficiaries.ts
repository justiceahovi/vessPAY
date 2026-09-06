import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../lib/db';
import {
  createWeWireBeneficiary,
  deleteWeWireBeneficiary,
  normalizeGhanaPhone,
  normalizeBankAccountNumber,
  mapGhanaNetwork,
  resolveInstitution,
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

    let institution;
    try {
      institution = await resolveInstitution(network);
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

      bankAccount = normalizeBankAccountNumber(accountNumber);
      if (!bankAccount) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: 'Please provide a valid bank account number (8-20 digits)',
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

      msisdn = normalizeGhanaPhone(phone).msisdn;
      if (!/^0[235]\d{8}$/.test(msisdn)) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: 'Please provide a valid 10-digit Ghana mobile money phone number (e.g. 024XXXXXXX)',
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
      country: country || 'GH',
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
        country: country || 'GH',
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
    const networkInput = (req.query.network || '').toString().trim();

    if (!phoneInput) {
      return res.status(400).json({
        error: { code: 'INVALID_INPUT', message: 'phone query parameter is required' },
      });
    }

    const { msisdn } = normalizeGhanaPhone(phoneInput);
    if (!/^0[235]\d{8}$/.test(msisdn)) {
      return res.status(400).json({
        error: {
          code: 'INVALID_INPUT',
          message: 'Please provide a valid 10-digit Ghana mobile money phone number (e.g. 024XXXXXXX)',
        },
      });
    }

    let network: string | null = null;
    if (networkInput) {
      try {
        network = mapGhanaNetwork(networkInput).network;
      } catch (err: any) {
        return res.status(400).json({
          error: {
            code: 'INVALID_INPUT',
            message: err.message || 'Invalid network. Supported networks are MTN, Telecel, or AirtelTigo',
          },
        });
      }
    }

    // Placeholder names auto-generated for unnamed recipients are not real names.
    const isPlaceholderName = (name?: string | null) =>
      !name || name.trim().length < 2 || /^Recipient\s+\d+$/i.test(name.trim());

    // 1. Saved beneficiaries -- same network first, then the number on any network.
    const beneficiaries = await prisma.beneficiary.findMany({
      where: { userId, phone: msisdn },
      orderBy: { createdAt: 'desc' },
      select: { name: true, network: true },
    });

    const beneficiaryMatch =
      (network ? beneficiaries.find((b) => b.network === network && !isPlaceholderName(b.name)) : undefined) ||
      beneficiaries.find((b) => !isPlaceholderName(b.name));

    if (beneficiaryMatch) {
      return res.status(200).json({
        resolved: true,
        phone: msisdn,
        network: beneficiaryMatch.network,
        name: beneficiaryMatch.name.trim(),
        source: 'beneficiary',
      });
    }

    // 2. Previously paid recipient with the same number.
    const transactions = await prisma.transaction.findMany({
      where: { userId, recipientPhone: msisdn, type: 'payout' },
      orderBy: { createdAt: 'desc' },
      take: 10,
      select: { recipientName: true, network: true },
    });

    const transactionMatch =
      (network ? transactions.find((t) => t.network === network && !isPlaceholderName(t.recipientName)) : undefined) ||
      transactions.find((t) => !isPlaceholderName(t.recipientName));

    if (transactionMatch) {
      return res.status(200).json({
        resolved: true,
        phone: msisdn,
        network: transactionMatch.network || network,
        name: (transactionMatch.recipientName || '').trim(),
        source: 'history',
      });
    }

    // 3. Unknown number -- the user types the name manually.
    return res.status(200).json({
      resolved: false,
      phone: msisdn,
      network,
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
