import { Request, Response, NextFunction } from 'express';
import { User } from '@prisma/client';
import { verifyToken } from '../lib/auth';
import { prisma } from '../lib/db';

declare global {
  namespace Express {
    interface Request {
      user?: User;
    }
  }
}

export interface AuthenticatedRequest extends Request {
  user: User;
}

/**
 * Authentication middleware that validates Bearer JWT in the Authorization header
 * and attaches the authenticated Prisma User to req.user.
 *
 * Emits standard error shape: { error: { code: "UNAUTHORIZED", message: "..." } }
 */
export async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authorization token required',
      },
    });
    return;
  }

  const token = authHeader.substring(7).trim();

  if (!token) {
    res.status(401).json({
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authorization token required',
      },
    });
    return;
  }

  try {
    const payload = verifyToken(token);

    if (!payload || !payload.userId) {
      res.status(401).json({
        error: {
          code: 'UNAUTHORIZED',
          message: 'Invalid or expired authorization token',
        },
      });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
    });

    if (!user) {
      res.status(401).json({
        error: {
          code: 'UNAUTHORIZED',
          message: 'User no longer exists',
        },
      });
      return;
    }

    req.user = user;
    next();
  } catch (err: any) {
    res.status(401).json({
      error: {
        code: 'UNAUTHORIZED',
        message: 'Invalid or expired authorization token',
      },
    });
  }
}

/**
 * Convenience alias for `authenticate` middleware.
 */
export const requireAuth = authenticate;
