import { Router, Request, Response } from 'express';
import { getWeWireInstitutions } from '../lib/wewire';

const router = Router();

/**
 * GET /api/banks?currency=GHS&channel=BANK
 * Reference list of payout institutions, sourced from WeWire's GET /v1/banks.
 * Returns both banks and mobile money operators unless `channel` narrows it.
 * Public reference data, like GET /api/travel/destinations.
 */
router.get('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const currency = (req.query.currency || 'GHS').toString().trim().toUpperCase();

    if (!['GHS', 'NGN'].includes(currency)) {
      res.status(400).json({
        error: {
          code: 'UNSUPPORTED_CURRENCY',
          message: `Currency '${currency}' is not supported. WeWire serves institution lists for GHS and NGN.`,
        },
      });
      return;
    }

    const rawChannel = (req.query.channel || '').toString().trim().toUpperCase();
    if (rawChannel && !['BANK', 'MOBILE_MONEY'].includes(rawChannel)) {
      res.status(400).json({
        error: {
          code: 'INVALID_CHANNEL',
          message: "channel must be 'BANK' or 'MOBILE_MONEY'",
        },
      });
      return;
    }

    const institutions = await getWeWireInstitutions(currency);
    const filtered = rawChannel
      ? institutions.filter((institution) => institution.channel === rawChannel)
      : institutions;

    res.status(200).json(filtered);
  } catch (err: any) {
    console.error('Error listing payout institutions:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve payout institutions',
      },
    });
  }
});

export default router;
