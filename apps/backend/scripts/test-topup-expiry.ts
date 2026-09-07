/**
 * Expiry of unfunded deposit intents.
 *
 * The point of expiry is to stop Add Money restoring a queue of stale deposits.
 * The constraint is that it must not lose money: an expired intent is still
 * creditable, because a user can set up a transfer on Monday and send it on
 * Wednesday.
 */
import { prisma } from '../src/lib/db';
import { generateWeWireSignature } from '../src/lib/webhook';

const BASE_URL = process.env.TEST_API_URL || 'http://localhost:3000';
const TEST_EMAIL = 'phase1_live_1788681823693@example.com';

let failures = 0;
function check(label: string, condition: boolean, detail = '') {
  console.log(`  ${condition ? 'OK  ' : 'FAIL'} ${label}${detail ? ` -- ${detail}` : ''}`);
  if (!condition) failures++;
}

async function login(): Promise<string> {
  const res = await fetch(`${BASE_URL}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: TEST_EMAIL, password: 'Password123!' }),
  });
  return (await res.json()).token;
}

async function postWebhook(payload: any, webhookId: string) {
  const rawBody = JSON.stringify(payload);
  const timestamp = Math.floor(Date.now() / 1000);
  const secret = process.env.WEWIRE_WEBHOOK_SECRET;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'webhook-id': webhookId,
    'webhook-timestamp': String(timestamp),
  };
  if (secret) {
    headers['webhook-signature'] = generateWeWireSignature({ secret, webhookId, timestamp, rawBody });
  }
  const res = await fetch(`${BASE_URL}/api/webhooks/wewire`, {
    method: 'POST', headers, body: rawBody,
  });
  return res.status;
}

async function main() {
  const token = await login();
  const user = await prisma.user.findUnique({
    where: { email: TEST_EMAIL },
    select: { id: true, wewireSubcustomerId: true },
  });
  if (!user) throw new Error('test user missing');

  console.log('--- a deposit older than the window is retired ---');
  const stale = await prisma.fundingTransaction.create({
    data: {
      userId: user.id,
      amount: 77,
      currency: 'GBP',
      status: 'PENDING',
      source: 'FIAT',
      // Two days old: well past the 24h window.
      createdAt: new Date(Date.now() - 48 * 60 * 60 * 1000),
    },
  });

  const pendingRes = await fetch(`${BASE_URL}/api/wallet/topup/pending?currency=GBP`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const pendingBody = await pendingRes.json();

  const staleAfter = await prisma.fundingTransaction.findUnique({ where: { id: stale.id } });
  check('the stale intent is EXPIRED', staleAfter?.status === 'EXPIRED', String(staleAfter?.status));
  check('it is no longer offered for resume',
    pendingBody?.pending?.fundingTransactionId !== stale.id,
    `offered: ${pendingBody?.pending?.fundingTransactionId ?? 'none'}`);

  console.log('--- but money arriving late is still credited ---');
  const wallet = await prisma.wallet.findFirst({
    where: { userId: user.id, currency: 'GBP' },
  });
  const before = Number(wallet?.balance ?? 0);

  // Clear every other candidate so the expired row is the one matched. Both
  // PENDING and EXPIRED qualify, and the webhook takes the newest.
  const others = await prisma.fundingTransaction.findMany({
    where: {
      userId: user.id,
      status: { in: ['PENDING', 'EXPIRED'] },
      source: 'FIAT',
      id: { not: stale.id },
    },
    select: { id: true },
  });
  await prisma.fundingTransaction.updateMany({
    where: { id: { in: others.map((o) => o.id) } },
    data: { status: 'CANCELLED' },
  });

  const status = await postWebhook(
    {
      eventType: 'funding.completed',
      data: {
        subCustomerId: user.wewireSubcustomerId,
        amount: '77',
        currency: 'GBP',
        balanceBefore: '0',
        balanceAfter: '77',
      },
    },
    `evt-late-${stale.id}`
  );
  check('the late deposit webhook is accepted', status === 200, `HTTP ${status}`);

  const settled = await prisma.fundingTransaction.findUnique({ where: { id: stale.id } });
  check('the expired intent was still completed', settled?.status === 'COMPLETED', String(settled?.status));

  const walletAfter = await prisma.wallet.findFirst({
    where: { userId: user.id, currency: 'GBP' },
  });
  const after = Number(walletAfter?.balance ?? 0);
  check('the money was credited, not dropped', after > before, `${before} -> ${after}`);

  // Leave the account as found, pass or fail.
  await prisma.wallet.update({
    where: { id: walletAfter!.id },
    data: { balance: before },
  });
  await prisma.fundingTransaction.delete({ where: { id: stale.id } }).catch(() => {});
  console.log(`  (test deposit removed, balance restored to ${before})`);

  console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
  await prisma.$disconnect();
  process.exit(failures === 0 ? 0 : 1);
}

main();
