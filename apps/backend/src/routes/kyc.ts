import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { getHostedKycLink, getSubCustomerStatus, createWeWireSubCustomer } from '../lib/wewire';
import { prisma } from '../lib/db';

const router = Router();

/**
 * GET /api/kyc/link
 * Returns the hosted KYC portal link for the authenticated user.
 */
router.get('/link', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    let subCustomerId = user.wewireSubcustomerId;

    // Resilient fallback: If user lacks wewireSubcustomerId, provision it now
    if (!subCustomerId) {
      const subCustomer = await createWeWireSubCustomer({
        firstName: user.firstName,
        lastName: user.lastName,
        email: user.email,
        country: user.country,
      });
      subCustomerId = subCustomer.id;

      await prisma.user.update({
        where: { id: user.id },
        data: { wewireSubcustomerId: subCustomerId },
      });
    }

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
      });
      return;
    }

    const status = await getSubCustomerStatus(subCustomerId);
    res.status(200).json(status);
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

export default router;
