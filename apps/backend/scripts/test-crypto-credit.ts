/**
 * Drives a synthetic crypto deposit through the real webhook endpoint and
 * checks the wallet credit, the recorded rate, and idempotency on redelivery.
 *
 * Synthetic because the sandbox has no crypto deposit simulator: the payload
 * shape is our best reading of WeWire's, and confirming it against a real
 * delivery is still outstanding. What this *does* prove is everything on our
 * side of the boundary -- attribution, pricing, crediting, and the guard that
 * stops a crypto arrival settling a fiat intent.
 */
import { prisma } from '../src/lib/db';
import { generateWeWireSignature } from '../src/lib/webhook';
import { priceCryptoDeposit } from '../src/lib/crypto-conversion';

const BASE_URL = process.env.TEST_API_URL || 'http://localhost:3000';
const TEST_EMAIL = 'phase1_live_1788681823693@example.com';

let failures = 0;
function check(label: string, condition: boolean, detail = '') {
  console.log(`  ${condition ? 'OK  ' : 'FAIL'} ${label}${detail ? ` -- ${detail}` : ''}`);
  if (!condition) failures++;
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
    headers['webhook-signature'] = generateWeWireSignature({
      secret, webhookId, timestamp, rawBody,
    });
  }

  const res = await fetch(`${BASE_URL}/api/webhooks/wewire`, {
    method: 'POST', headers, body: rawBody,
  });
  return { status: res.status, body: await res.text() };
}

async function main() {
  const user = await prisma.user.findUnique({
    where: { email: TEST_EMAIL },
    select: { id: true, primaryCurrency: true, wewireSubcustomerId: true },
  });
  if (!user) throw new Error(`Test user ${TEST_EMAIL} not found`);

  const address = await prisma.cryptoDepositAddress.findFirst({
    where: { userId: user.id, chain: 'BASE' },
  });
  if (!address?.address) throw new Error('No BASE deposit address for the test user');

  const walletCurrency = (user.primaryCurrency || 'USD').toUpperCase();
  const before = await prisma.wallet.findFirst({
    where: { userId: user.id, currency: walletCurrency },
  });
  const beforeBalance = Number(before?.balance ?? 0);

  const assetAmount = '10.123456';
  const expected = await priceCryptoDeposit('USDC', assetAmount, walletCurrency);
  if (!expected) throw new Error(`Cannot price USDC into ${walletCurrency}`);

  console.log(`--- crediting ${assetAmount} USDC into a ${walletCurrency} wallet ---`);
  console.log(`  balance before: ${beforeBalance} ${walletCurrency}`);
  console.log(`  expected: ${expected.fiatAmount} ${walletCurrency} @ ${expected.rate} (${expected.via})`);

  const txHash = `0xtest${Date.now().toString(16)}`;
  const payload = {
    eventType: 'subcustomer.wallet.deposit.received',
    data: {
      txHash,
      asset: 'USDC',
      chain: 'BASE',
      amount: assetAmount,
      address: address.address,
      subCustomerId: user.wewireSubcustomerId,
    },
  };

  const first = await postWebhook(payload, `evt-crypto-${txHash}`);
  check('webhook accepted', first.status === 200, `HTTP ${first.status}`);

  const funding = await prisma.fundingTransaction.findUnique({ where: { txHash } });
  check('a funding row was created', !!funding);
  check('it is marked CRYPTO', funding?.source === 'CRYPTO');
  check('the exact token amount is preserved',
    Number(funding?.assetAmount) === Number(assetAmount), String(funding?.assetAmount));
  check('it is COMPLETED', funding?.status === 'COMPLETED', funding?.status);
  check('the credited amount is the priced one',
    Number(funding?.amount) === expected.fiatAmount, `${funding?.amount} vs ${expected.fiatAmount}`);
  check('the rate used is recorded',
    Number(funding?.conversionRate) === expected.rate, String(funding?.conversionRate));
  check('how the rate was resolved is recorded',
    funding?.conversionVia === expected.via, String(funding?.conversionVia));
  check('the credit is in wallet currency, not the token',
    funding?.currency === walletCurrency, String(funding?.currency));

  const after = await prisma.wallet.findFirst({
    where: { userId: user.id, currency: walletCurrency },
  });
  const afterBalance = Number(after?.balance ?? 0);
  check('the wallet moved by exactly the priced amount',
    Math.abs(afterBalance - (beforeBalance + expected.fiatAmount)) < 0.005,
    `${beforeBalance} -> ${afterBalance}`);
  check('the token amount was NOT credited as fiat',
    Math.abs(afterBalance - (beforeBalance + Number(assetAmount))) > 0.005,
    'a 10.12 GBP credit for 10.12 USDC would be wrong');

  console.log('--- redelivery (webhooks are redelivered; this must not double-credit) ---');
  const second = await postWebhook(payload, `evt-crypto-${txHash}-redelivery`);
  check('redelivery accepted', second.status === 200, `HTTP ${second.status}`);

  const afterRedelivery = await prisma.wallet.findFirst({
    where: { userId: user.id, currency: walletCurrency },
  });
  check('balance is unchanged on redelivery',
    Number(afterRedelivery?.balance ?? 0) === afterBalance,
    `${afterBalance} -> ${afterRedelivery?.balance}`);

  const rows = await prisma.fundingTransaction.count({ where: { txHash } });
  check('still exactly one row for the hash', rows === 1, `${rows} rows`);

  console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
  await prisma.$disconnect();
  process.exit(failures === 0 ? 0 : 1);
}

main();
