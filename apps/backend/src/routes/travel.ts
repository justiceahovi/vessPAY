import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { authenticate } from '../middleware/auth';
import { TravelProfile } from '@prisma/client';
import { CORRIDORS } from '../lib/corridors';

const router = Router();

export interface DestinationInfo {
  country: string;
  name: string;
  currency: string;
  /** Display symbol for amounts in this corridor, e.g. 'GH₵'. */
  symbol: string;
  /** Channels this corridor can be paid over: MOBILE_MONEY and/or BANK. */
  channels: string[];
  /**
   * Whether a payout can actually be sent. False for a corridor whose
   * reference data works (banks, account lookup, beneficiaries) but for which
   * the provider exposes no payout rail -- Nigeria today. The app uses this to
   * offer the destination without letting a user reach a dead Send button.
   */
  payoutAvailable: boolean;
}

/**
 * Supported destinations, derived from the corridor table so the app never
 * carries its own copy of which rails are live.
 */
export const SUPPORTED_DESTINATIONS: DestinationInfo[] = CORRIDORS.map((corridor) => ({
  country: corridor.country,
  name: corridor.name,
  currency: corridor.currency,
  symbol: corridor.symbol,
  channels: [...corridor.channels],
  payoutAvailable: corridor.payoutEndpoint !== 'UNSUPPORTED',
}));

/// Built from the corridor list rather than indexed by hand, so adding a
/// corridor cannot leave a destination unresolvable.
const DESTINATION_LOOKUP: Record<string, DestinationInfo> = {};
for (const destination of SUPPORTED_DESTINATIONS) {
  for (const alias of [
    destination.country,
    destination.currency,
    destination.name.toUpperCase(),
  ]) {
    DESTINATION_LOOKUP[alias] = destination;
  }
}

export function resolveDestination(input: string): DestinationInfo | null {
  if (!input || typeof input !== 'string') return null;
  const key = input.trim().toUpperCase();
  return DESTINATION_LOOKUP[key] || null;
}

export function formatTravelProfile(profile: TravelProfile) {
  return {
    id: profile.id,
    userId: profile.userId,
    destinationCountry: profile.destinationCountry,
    destinationCurrency: profile.destinationCurrency,
    isActive: profile.isActive,
    createdAt: profile.createdAt.toISOString(),
    updatedAt: profile.updatedAt.toISOString(),
  };
}

/**
 * GET /api/travel/destinations
 * Returns supported travel destinations array [{ country, currency, name }].
 */
router.get('/destinations', (_req: Request, res: Response): void => {
  res.status(200).json(SUPPORTED_DESTINATIONS);
});

/**
 * GET /api/travel/current
 * Returns the authenticated user's active travel profile, or null if not yet set.
 */
router.get('/current', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    const profile = await prisma.travelProfile.findFirst({
      where: {
        userId,
        isActive: true,
      },
      orderBy: {
        updatedAt: 'desc',
      },
    });

    if (!profile) {
      res.status(200).json(null);
      return;
    }

    res.status(200).json(formatTravelProfile(profile));
  } catch (err: any) {
    console.error('Error fetching current travel profile:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve current travel profile',
      },
    });
  }
});

/**
 * PUT /api/travel/current
 * Sets or updates the active travel destination profile for the authenticated user.
 * Body: { destinationCountry: 'GH' | 'Ghana' | 'NG' | 'Nigeria' }
 */
router.put('/current', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const rawDestination = req.body?.destinationCountry || req.body?.country;

    if (!rawDestination || typeof rawDestination !== 'string' || !rawDestination.trim()) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'destinationCountry is required',
        },
      });
      return;
    }

    const destination = resolveDestination(rawDestination);
    if (!destination) {
      res.status(400).json({
        error: {
          code: 'INVALID_DESTINATION',
          message: `Destination '${rawDestination}' is not supported. Supported destinations: ${SUPPORTED_DESTINATIONS.map((d) => `${d.country} (${d.name})`).join(', ')}`,
        },
      });
      return;
    }

    const activeProfile = await prisma.$transaction(async (tx) => {
      // Deactivate any currently active profiles for this user
      await tx.travelProfile.updateMany({
        where: {
          userId,
          isActive: true,
        },
        data: {
          isActive: false,
        },
      });

      // Check if a profile record already exists for this destination
      const existing = await tx.travelProfile.findFirst({
        where: {
          userId,
          destinationCountry: destination.country,
        },
      });

      if (existing) {
        return tx.travelProfile.update({
          where: { id: existing.id },
          data: {
            isActive: true,
            destinationCurrency: destination.currency,
          },
        });
      } else {
        return tx.travelProfile.create({
          data: {
            userId,
            destinationCountry: destination.country,
            destinationCurrency: destination.currency,
            isActive: true,
          },
        });
      }
    });

    res.status(200).json(formatTravelProfile(activeProfile));
  } catch (err: any) {
    console.error('Error updating current travel profile:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to update current travel profile',
      },
    });
  }
});

export default router;
