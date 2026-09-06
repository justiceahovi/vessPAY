/**
 * Replays the KYC and sweep webhooks WeWire actually sends, and checks that the
 * mirrored compliance state and the sweep audit trail are written.
 *
 * Run: npm run test:kyc-sweep-webhooks
 */
import 'dotenv/config';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const BASE = `http://localhost:${process.env.PORT || 3000}`;
const EMAIL = 'ama@vesspay.com';

let failures = 0;
function check(name: string, ok: boolean, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` -> ${detail}` : ''}`);
  if (!ok) failures++;
}

async function send(eventType: string, data: Record<string, unknown>) {
  const eventId = `test_${eventType}_${Date.now()}`;
  const body = JSON.stringify({ eventType, eventId, data });
  const secret = process.env.WEWIRE_WEBHOOK_SECRET!;
  const keyPart = secret.includes('_') ? secret.split('_')[1] : secret;
  const key = Buffer.from(keyPart, 'base64');
  const ts = Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac('sha256', key).update(`${eventId}.${ts}.${body}`).digest('base64');

  const res = await fetch(`${BASE}/api/webhooks/wewire`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'webhook-id': eventId,
      'webhook-timestamp': String(ts),
      'webhook-signature': `v1,${sig}`,
    },
    body,
  });
  return res.status;
}

(async () => {
  const user = await prisma.user.findFirstOrThrow({ where: { email: EMAIL } });
  const sub = user.wewireSubcustomerId!;

  // Reset the mirror so the test observes the webhook doing the work.
  await prisma.user.update({
    where: { id: user.id },
    data: { onboardingStatus: null, enhancedKycStatus: null },
  });

  check('onboarding webhook accepted', (await send('subcustomer.kyc_status_updated', {
    subCustomerId: sub, onboardingStatus: 'APPROVED', status: 'ACTIVE', email: EMAIL,
  })) === 200);

  check('enhanced webhook accepted', (await send('subcustomer.enhanced_kyc_status_updated', {
    subCustomerId: sub, enhancedKycStatus: 'APPROVED', previousEnhancedKycStatus: 'REQUESTED',
  })) === 200);

  const after = await prisma.user.findFirstOrThrow({ where: { id: user.id } });
  check('onboarding status mirrored', after.onboardingStatus === 'APPROVED', `${after.onboardingStatus}`);
  check('enhanced status mirrored', after.enhancedKycStatus === 'APPROVED', `${after.enhancedKycStatus}`);
  check('mirror timestamped', after.kycStatusUpdatedAt !== null);

  // A sweep, twice, to prove redelivery does not duplicate the audit row.
  const depositTransactionId = `test_deposit_${Date.now()}`;
  const sweep = {
    subCustomerId: sub, amount: '249.45', currency: 'GBP', direction: 'AUTO',
    fromWalletId: 'wallet_from', toWalletId: 'wallet_to',
    depositTransactionId, debitTransactionId: 'debit_1', creditTransactionId: 'credit_1',
    sweptAt: new Date().toISOString(),
  };
  check('sweep accepted', (await send('subcustomer.wallet.swept', sweep)) === 200);
  check('sweep redelivery accepted', (await send('subcustomer.wallet.swept', sweep)) === 200);

  const rows = await prisma.walletSweep.findMany({ where: { depositTransactionId } });
  check('sweep recorded exactly once', rows.length === 1, `${rows.length} row(s)`);
  if (rows[0]) {
    check('sweep amount recorded', Number(rows[0].amount) === 249.45, `${rows[0].amount}`);
    check('sweep attributed to the user', rows[0].userId === user.id);
  }

  await prisma.walletSweep.deleteMany({ where: { depositTransactionId } });
  console.log(failures === 0 ? '\nAll webhook checks passed.' : `\n${failures} check(s) failed.`);
  await prisma.$disconnect();
  process.exit(failures === 0 ? 0 : 1);
})();
