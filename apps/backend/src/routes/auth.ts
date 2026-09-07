import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import {
  hashPassword,
  comparePassword,
  generateToken,
  formatUser,
} from '../lib/auth';
import { authenticate } from '../middleware/auth';
import { createWeWireSubCustomer } from '../lib/wewire';
import {
  DEFAULT_WALLET_CURRENCY,
  normalizeWalletCurrency,
  supportedCurrencyCodes,
} from '../lib/currencies';
import { isEnhancedApproved } from '../lib/deposit-account';

const router = Router();

/**
 * POST /api/auth/register
 * Registers a new user, hashes password, creates their wallet with balance = 0,
 * and returns the user profile with JWT token.
 *
 * `primaryCurrency` is optional: when the client sends the currency the user picked,
 * the wallet is opened in it and the choice is persisted on the user. When it is
 * omitted the wallet falls back to USD and primaryCurrency stays null, which is how
 * the app knows to prompt for a currency on first sign-on.
 */
router.post('/register', async (req: Request, res: Response): Promise<void> => {
  try {
    const {
      firstName,
      lastName,
      email,
      password,
      country,
      nationality,
      primaryCurrency: rawPrimaryCurrency,
    } = req.body;

    if (!firstName || typeof firstName !== 'string' || !firstName.trim()) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'First name is required',
        },
      });
      return;
    }

    if (!lastName || typeof lastName !== 'string' || !lastName.trim()) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Last name is required',
        },
      });
      return;
    }

    if (!email || typeof email !== 'string' || !email.includes('@')) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'A valid email address is required',
        },
      });
      return;
    }

    if (!password || typeof password !== 'string' || password.length < 6) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Password must be at least 6 characters long',
        },
      });
      return;
    }

    // Currency is optional at registration, but must be supported when supplied
    let primaryCurrency: string | null = null;
    if (rawPrimaryCurrency !== undefined && rawPrimaryCurrency !== null && rawPrimaryCurrency !== '') {
      primaryCurrency = normalizeWalletCurrency(rawPrimaryCurrency);
      if (!primaryCurrency) {
        res.status(400).json({
          error: {
            code: 'UNSUPPORTED_CURRENCY',
            message: `Wallet currency must be one of: ${supportedCurrencyCodes()}`,
          },
        });
        return;
      }
    }

    const normalizedEmail = email.trim().toLowerCase();

    // Check for existing user with this email
    const existingUser = await prisma.user.findUnique({
      where: { email: normalizedEmail },
    });

    if (existingUser) {
      res.status(409).json({
        error: {
          code: 'DUPLICATE_EMAIL',
          message: 'A user with this email already exists',
        },
      });
      return;
    }

    const passwordHash = await hashPassword(password);

    // Create WeWire sub-customer for the new user (T3.2)
    let wewireSubcustomerId: string | null = null;
    try {
      const subCustomer = await createWeWireSubCustomer({
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: normalizedEmail,
        country: country ? String(country).trim() : null,
      });
      wewireSubcustomerId = subCustomer.id;
    } catch (weWireErr: any) {
      console.error('WeWire sub-customer creation failed:', weWireErr);
      res.status(502).json({
        error: {
          code: 'WEWIRE_ERROR',
          message: 'Failed to create payment provider sub-customer: ' + (weWireErr.message || 'Unknown error'),
        },
      });
      return;
    }

    // Create user and their wallet row in a transaction
    const newUser = await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          email: normalizedEmail,
          passwordHash,
          country: country ? String(country).trim() : null,
          nationality: nationality ? String(nationality).trim() : null,
          primaryCurrency,
          wewireSubcustomerId,
        },
      });

      // Wallet in the chosen currency (USD until the user picks one), balance = 0
      await tx.wallet.create({
        data: {
          userId: user.id,
          currency: primaryCurrency ?? DEFAULT_WALLET_CURRENCY,
          balance: 0.0,
        },
      });

      return user;
    });

    const token = generateToken({
      userId: newUser.id,
      email: newUser.email,
    });

    res.status(201).json({
      user: formatUser(newUser),
      token,
    });
  } catch (err: any) {
    // Handle Prisma unique constraint error just in case
    if (err.code === 'P2002') {
      res.status(409).json({
        error: {
          code: 'DUPLICATE_EMAIL',
          message: 'A user with this email already exists',
        },
      });
      return;
    }

    console.error('Registration error:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to complete registration',
      },
    });
  }
});

/**
 * POST /api/auth/login
 * Validates user credentials and issues a JWT token.
 */
router.post('/login', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Email and password are required',
        },
      });
      return;
    }

    const normalizedEmail = String(email).trim().toLowerCase();

    const user = await prisma.user.findUnique({
      where: { email: normalizedEmail },
    });

    if (!user) {
      res.status(401).json({
        error: {
          code: 'INVALID_CREDENTIALS',
          message: 'Invalid email or password',
        },
      });
      return;
    }

    const isValidPassword = await comparePassword(String(password), user.passwordHash);

    if (!isValidPassword) {
      res.status(401).json({
        error: {
          code: 'INVALID_CREDENTIALS',
          message: 'Invalid email or password',
        },
      });
      return;
    }

    const token = generateToken({
      userId: user.id,
      email: user.email,
    });

    res.status(200).json({
      user: formatUser(user),
      token,
    });
  } catch (err: any) {
    console.error('Login error:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to process login',
      },
    });
  }
});

/**
 * GET /api/auth/me
 * Retrieves current authenticated user profile.
 */
router.get('/me', authenticate, async (req: Request, res: Response): Promise<void> => {
  res.status(200).json({
    user: formatUser(req.user!),
  });
});

/**
 * PUT /api/auth/me
 * Updates a subset of the authenticated user's own profile details.
 *
 * `country`/`nationality` are only editable before identity verification is
 * approved: once WeWire has an enhanced-KYC-approved sub-customer on file for
 * this user, those fields must not silently diverge from what was verified.
 */
router.put('/me', authenticate, async (req: Request, res: Response): Promise<void> => {
  try {
    const user = req.user!;
    const { firstName, lastName, country, nationality } = req.body;

    const data: {
      firstName?: string;
      lastName?: string;
      country?: string | null;
      nationality?: string | null;
    } = {};

    if (firstName !== undefined) {
      if (typeof firstName !== 'string' || !firstName.trim()) {
        res.status(400).json({
          error: { code: 'VALIDATION_ERROR', message: 'First name cannot be empty' },
        });
        return;
      }
      data.firstName = firstName.trim();
    }

    if (lastName !== undefined) {
      if (typeof lastName !== 'string' || !lastName.trim()) {
        res.status(400).json({
          error: { code: 'VALIDATION_ERROR', message: 'Last name cannot be empty' },
        });
        return;
      }
      data.lastName = lastName.trim();
    }

    const changingCountry = country !== undefined && String(country ?? '').trim() !== (user.country ?? '');
    const changingNationality =
      nationality !== undefined && String(nationality ?? '').trim() !== (user.nationality ?? '');

    if (changingCountry || changingNationality) {
      if (isEnhancedApproved(user.enhancedKycStatus ?? '')) {
        res.status(409).json({
          error: {
            code: 'KYC_LOCKED',
            message:
              'Country and nationality cannot be changed after identity verification. Contact support if these are incorrect.',
          },
        });
        return;
      }
      if (country !== undefined) {
        data.country = String(country ?? '').trim() || null;
      }
      if (nationality !== undefined) {
        data.nationality = String(nationality ?? '').trim() || null;
      }
    }

    const updated = await prisma.user.update({
      where: { id: user.id },
      data,
    });

    res.status(200).json({ user: formatUser(updated) });
  } catch (err: any) {
    console.error('Error updating profile:', err);
    res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to update profile' },
    });
  }
});

export default router;
