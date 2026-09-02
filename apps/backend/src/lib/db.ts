import { PrismaClient } from '@prisma/client';

// Singleton pattern -- reuse the same PrismaClient across hot-reloads in dev
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

/**
 * Runs a trivial SELECT 1 to verify the database connection is healthy.
 * Throws if the DB is unreachable.
 */
export async function checkDatabaseConnection(): Promise<void> {
  await prisma.$queryRaw`SELECT 1`;
}