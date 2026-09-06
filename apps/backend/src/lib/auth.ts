import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { User } from '@prisma/client';

const SALT_ROUNDS = 10;

export interface TokenPayload {
  userId: string;
  email: string;
}

export interface SanitizedUser {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  country: string | null;
  nationality: string | null;
  /** Wallet currency chosen on first sign-on; null until the user picks one. */
  primaryCurrency: string | null;
  wewireSubcustomerId?: string | null;
  createdAt: string;
  updatedAt: string;
}

/**
 * Hashes a plaintext password using bcrypt.
 */
export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

/**
 * Compares a plaintext password against a bcrypt hash.
 */
export async function comparePassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

/**
 * Generates a signed JWT for the given user payload.
 */
export function generateToken(payload: TokenPayload): string {
  const secret = process.env.JWT_SECRET || 'dev_vesspay_jwt_secret_super_secure_key_2026';
  const expiresIn = process.env.JWT_EXPIRES_IN || '7d';
  return jwt.sign(payload, secret, { expiresIn: expiresIn as any });
}

/**
 * Verifies a JWT and extracts the token payload.
 */
export function verifyToken(token: string): TokenPayload {
  const secret = process.env.JWT_SECRET || 'dev_vesspay_jwt_secret_super_secure_key_2026';
  return jwt.verify(token, secret) as TokenPayload;
}

/**
 * Sanitizes a User object for API responses, ensuring sensitive fields like
 * password_hash are never exposed.
 */
export function formatUser(user: User): SanitizedUser {
  return {
    id: user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    country: user.country,
    nationality: user.nationality,
    primaryCurrency: user.primaryCurrency || null,
    wewireSubcustomerId: user.wewireSubcustomerId || null,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}
