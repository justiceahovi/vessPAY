import bcrypt from 'bcryptjs';
import { prisma } from '../src/lib/db';

/**
 * Test scripts run against whatever users already exist. On a freshly migrated
 * (or reset) database there are none, so this seeds the minimum the suites
 * need: two users, the first with a funded wallet.
 *
 * Existing users are never modified beyond topping up the wallet balance the
 * payment tests spend against.
 */
export async function ensureTestUsers(options: { count?: number; fundUsd?: number } = {}) {
  const count = options.count ?? 2;
  const fundUsd = options.fundUsd ?? 100;

  const existing = await prisma.user.findMany({
    orderBy: { createdAt: 'asc' },
    include: { wallets: true },
  });

  const users = [...existing];

  if (users.length < count) {
    const passwordHash = await bcrypt.hash('TestPassw0rd!', 10);

    for (let i = users.length; i < count; i++) {
      const created = await prisma.user.create({
        data: {
          firstName: 'Test',
          lastName: `User${i + 1}`,
          email: `test-user-${i + 1}-${Date.now()}@vesspay.internal`,
          passwordHash,
          country: 'GBR',
          nationality: 'British',
          primaryCurrency: 'USD',
        },
        include: { wallets: true },
      });
      console.log(`Seeded test user: ${created.email}`);
      users.push(created);
    }
  }

  // The first user is the one the payment suites spend from
  const payer = users[0];
  const usdWallet = payer.wallets.find((w) => w.currency === 'USD');
  if (usdWallet) {
    if (Number(usdWallet.balance) < fundUsd) {
      await prisma.wallet.update({
        where: { id: usdWallet.id },
        data: { balance: fundUsd },
      });
    }
  } else {
    await prisma.wallet.create({
      data: { userId: payer.id, currency: 'USD', balance: fundUsd },
    });
  }

  return prisma.user.findMany({
    orderBy: { createdAt: 'asc' },
    take: count,
    include: { wallets: true },
  });
}
