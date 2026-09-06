import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import {
  getHostedKycLink,
  getSubCustomerStatus,
  createWeWireSubCustomer,
  submitSimplifiedKyc,
} from '../lib/wewire';
import { User } from '@prisma/client';
import { prisma } from '../lib/db';

const router = Router();

/**
 * Whether the demo "auto-submit KYC" shortcut is offered.
 *
 * It posts a canned identity dossier on the user's behalf, so it must never be
 * reachable in production: `ENABLE_DEMO_KYC` decides explicitly when set, and
 * otherwise it is on everywhere except production.
 */
function isDemoKycEnabled(): boolean {
  const flag = process.env.ENABLE_DEMO_KYC;
  if (flag !== undefined && flag.trim() !== '') {
    return flag.trim().toLowerCase() === 'true';
  }
  return process.env.NODE_ENV !== 'production';
}

/**
 * Returns the user's WeWire sub-customer id, provisioning one on the fly if the
 * account predates sub-customer creation or registration failed part-way.
 */
async function ensureSubCustomerId(user: User): Promise<string> {
  if (user.wewireSubcustomerId) return user.wewireSubcustomerId;

  const subCustomer = await createWeWireSubCustomer({
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    country: user.country,
  });

  await prisma.user.update({
    where: { id: user.id },
    data: { wewireSubcustomerId: subCustomer.id },
  });

  return subCustomer.id;
}

/**
 * GET /api/kyc/link
 * Returns the hosted KYC portal link for the authenticated user.
 */
router.get('/link', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const subCustomerId = await ensureSubCustomerId(req.user!);
    const kycLink = await getHostedKycLink(subCustomerId);
    res.status(200).json(kycLink);
  } catch (err: any) {
    console.error('Error getting KYC link:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err.message || 'Failed to retrieve hosted KYC link',
      },
    });
  }
});

/**
 * GET /api/kyc/status
 * Returns the current KYC onboarding status of the authenticated user.
 */
router.get('/status', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    const subCustomerId = user.wewireSubcustomerId;

    if (!subCustomerId) {
      res.status(200).json({
        onboardingStatus: 'DRAFT',
        enhancedKycStatus: 'NOT_STARTED',
        demoKycAvailable: isDemoKycEnabled(),
      });
      return;
    }

    const status = await getSubCustomerStatus(subCustomerId);
    res.status(200).json({
      ...status,
      demoKycAvailable: isDemoKycEnabled(),
    });
  } catch (err: any) {
    console.error('Error getting KYC status:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: err.message || 'Failed to retrieve KYC status',
      },
    });
  }
});

/**
 * POST /api/kyc/demo-submit
 *
 * Demo-only shortcut: submits the canned simplified KYC dossier for the
 * authenticated user so a sandbox account can reach APPROVED without anyone
 * walking through the hosted portal. Deliberately explicit — registration no
 * longer does this on the user's behalf, it only happens when a human taps the
 * button. Returns the freshly re-read status.
 */
router.post('/demo-submit', authenticate, async (req: Request, res: Response): Promise<void> => {
  if (!isDemoKycEnabled()) {
    res.status(403).json({
      error: {
        code: 'DEMO_KYC_DISABLED',
        message: 'Demo KYC submission is disabled in this environment',
      },
    });
    return;
  }

  try {
    const user = req.user!;
    const subCustomerId = await ensureSubCustomerId(user);

    const result = await submitSimplifiedKyc(subCustomerId, {
      firstName: user.firstName,
      lastName: user.lastName,
      country: user.country,
    });

    if (!result.submitted) {
      res.status(503).json({
        error: {
          code: 'DEMO_KYC_UNAVAILABLE',
          message: result.reason || 'Demo KYC submission is not available right now',
        },
      });
      return;
    }

    const status = await getSubCustomerStatus(subCustomerId);
    res.status(200).json({
      ...status,
      demoKycAvailable: true,
    });
  } catch (err: any) {
    console.error('Error submitting demo KYC:', err);
    res.status(502).json({
      error: {
        code: 'WEWIRE_ERROR',
        message: err.message || 'Failed to submit demo KYC',
      },
    });
  }
});

export default router;
