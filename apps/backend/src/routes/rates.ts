import { Router, Request, Response } from 'express';
import { getExchangeRate, getWeWireRates } from '../lib/wewire';

const router = Router();

// Standard 3-5 character alphabetical currency code pattern (e.g. USD, GHS, NGN, USDT, USDC)
const CURRENCY_CODE_REGEX = /^[A-Z]{3,5}$/;

/**
 * GET /api/rates/pairs
 * Returns all currently available currency pairs from WeWire.
 */
router.get('/pairs', async (_req: Request, res: Response): Promise<void> => {
  try {
    const rawRates = await getWeWireRates();
    const pairs = rawRates.map((item) => ({
      from: item.from,
      to: item.to,
      rate: parseFloat(item.bid) > 0 ? parseFloat(item.bid) : parseFloat(item.ask),
      updatedAt: item.updatedAt,
    }));
    res.status(200).json(pairs);
  } catch (err: any) {
    console.error('Error fetching rate pairs:', err);
    res.status(500).json({
      error: {
        code: 'RATES_FETCH_FAILED',
        message: 'Failed to retrieve available currency pairs',
      },
    });
  }
});

/**
 * GET /api/rates?from=USD&to=GHS
 * Per VESSPAY_BLUEPRINT.md Section 7:
 * GET /api/rates?from=USD&to=GHS -> { from, to, rate, asOf }
 */
router.get('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const rawFrom = req.query.from;
    const rawTo = req.query.to;
    const forceRefresh = req.query.refresh === 'true';

    // 1. Missing query parameters validation
    if (!rawFrom || !rawTo || typeof rawFrom !== 'string' || typeof rawTo !== 'string') {
      res.status(400).json({
        error: {
          code: 'MISSING_CURRENCY_PARAMETER',
          message: "Both 'from' and 'to' currency parameters are required (e.g. /api/rates?from=USD&to=GHS)",
        },
      });
      return;
    }

    const from = rawFrom.trim().toUpperCase();
    const to = rawTo.trim().toUpperCase();

    // 2. Currency code format validation
    if (!CURRENCY_CODE_REGEX.test(from) || !CURRENCY_CODE_REGEX.test(to)) {
      res.status(400).json({
        error: {
          code: 'INVALID_CURRENCY_CODE',
          message: 'Currency codes must be 3-5 alphabetical characters (e.g. USD, GHS, NGN)',
        },
      });
      return;
    }

    // 3. Same currency validation
    if (from === to) {
      res.status(400).json({
        error: {
          code: 'INVALID_CURRENCY_PAIR',
          message: 'Source and destination currencies cannot be the same',
        },
      });
      return;
    }

    // 4. Rate lookup
    const rateResult = await getExchangeRate(from, to, forceRefresh);

    if (!rateResult) {
      res.status(400).json({
        error: {
          code: 'UNSUPPORTED_CURRENCY_PAIR',
          message: `Currency pair ${from}/${to} is not supported`,
        },
      });
      return;
    }

    // 5. Success response adhering to blueprint Section 7
    res.status(200).json({
      from: rateResult.from,
      to: rateResult.to,
      rate: rateResult.rate,
      asOf: rateResult.asOf,
    });
  } catch (err: any) {
    console.error('Error in /api/rates endpoint:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to retrieve exchange rate',
      },
    });
  }
});

export default router;
