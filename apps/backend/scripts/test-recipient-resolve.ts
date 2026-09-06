process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';

function fail(message: string, extra?: unknown): never {
  console.error(`FAILED: ${message}`, extra ?? '');
  process.exit(1);
}

async function main() {
  console.log('=== Test: Recipient name resolution (GET /api/beneficiaries/resolve) ===\n');

  // Use existing users (rule: do not create new users for tests)
  const users = await prisma.user.findMany({ take: 2, orderBy: { createdAt: 'asc' } });
  if (users.length < 2) {
    fail('Need at least 2 existing users in the database to test user isolation.');
  }
  const [userA, userB] = users;
  console.log(`User A: ${userA.email}`);
  console.log(`User B: ${userB.email}\n`);

  // Fixture numbers (kept out of the way of other test scripts)
  const savedPhone = '0247000001'; // saved beneficiary of user A
  const historyPhone = '0507000002'; // only ever paid by user A
  const placeholderPhone = '0247000003'; // beneficiary with an auto-generated name
  const unknownPhone = '0247000009'; // never seen
  const otherUserPhone = '0247000004'; // belongs to user B only

  // Clean previous fixture rows so the script is repeatable
  const fixturePhones = [savedPhone, historyPhone, placeholderPhone, unknownPhone, otherUserPhone];
  await prisma.beneficiary.deleteMany({ where: { phone: { in: fixturePhones } } });
  await prisma.transaction.deleteMany({ where: { recipientPhone: { in: fixturePhones } } });

  await prisma.beneficiary.create({
    data: { userId: userA.id, name: 'Ama Serwaa', network: 'MTN', phone: savedPhone, country: 'GH' },
  });
  await prisma.beneficiary.create({
    data: {
      userId: userA.id,
      name: `Recipient ${placeholderPhone}`,
      network: 'MTN',
      phone: placeholderPhone,
      country: 'GH',
    },
  });
  await prisma.beneficiary.create({
    data: { userId: userB.id, name: 'Yaw Boateng', network: 'MTN', phone: otherUserPhone, country: 'GH' },
  });
  await prisma.transaction.create({
    data: {
      userId: userA.id,
      type: 'payout',
      status: 'COMPLETED',
      sourceCurrency: 'USD',
      sourceAmount: 12.0,
      destinationCurrency: 'GHS',
      destinationAmount: 139.0,
      fee: 0.12,
      exchangeRate: 11.58,
      recipientName: 'Kofi Mensah',
      recipientPhone: historyPhone,
      network: 'Telecel',
      country: 'GH',
      idempotencyKey: `idem_resolve_${Date.now()}`,
    },
  });

  const tokenA = generateToken({ userId: userA.id, email: userA.email });
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}\n`);

  const resolve = async (phone: string, network?: string) => {
    const query = new URLSearchParams({ phone, ...(network ? { network } : {}) });
    const res = await fetch(`${baseUrl}/api/beneficiaries/resolve?${query}`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };

  try {
    // --- Test 1: unauthenticated access rejected ---
    console.log('--- Test 1: Unauthenticated access rejection ---');
    const unauth = await fetch(`${baseUrl}/api/beneficiaries/resolve?phone=${savedPhone}`);
    if (unauth.status !== 401) fail(`Expected 401, got ${unauth.status}`);
    console.log('PASSED: 401 without a token\n');

    // --- Test 2: saved beneficiary resolves ---
    console.log('--- Test 2: Saved beneficiary resolves by number ---');
    const saved = await resolve(savedPhone, 'MTN');
    if (saved.status !== 200) fail(`Expected 200, got ${saved.status}`, saved.body);
    if (saved.body?.resolved !== true || saved.body?.name !== 'Ama Serwaa' || saved.body?.source !== 'beneficiary') {
      fail('Expected Ama Serwaa from source "beneficiary"', saved.body);
    }
    console.log(`PASSED: ${saved.body.name} (source: ${saved.body.source})\n`);

    // --- Test 3: number typed in international format still resolves ---
    console.log('--- Test 3: +233 format normalizes to the same recipient ---');
    const international = await resolve('+233247000001', 'MTN');
    if (international.body?.resolved !== true || international.body?.name !== 'Ama Serwaa') {
      fail('Expected +233 format to resolve to Ama Serwaa', international.body);
    }
    console.log('PASSED: international format normalized\n');

    // --- Test 4: falls back to a previously paid recipient ---
    console.log('--- Test 4: Previously paid recipient resolves from history ---');
    const history = await resolve(historyPhone, 'Telecel');
    if (history.body?.resolved !== true || history.body?.name !== 'Kofi Mensah' || history.body?.source !== 'history') {
      fail('Expected Kofi Mensah from source "history"', history.body);
    }
    console.log(`PASSED: ${history.body.name} (source: ${history.body.source})\n`);

    // --- Test 5: auto-generated placeholder names are not offered ---
    console.log('--- Test 5: Placeholder names are not returned ---');
    const placeholder = await resolve(placeholderPhone, 'MTN');
    if (placeholder.body?.resolved !== false || placeholder.body?.name !== null) {
      fail('Expected placeholder beneficiary name to be treated as unresolved', placeholder.body);
    }
    console.log('PASSED: placeholder name suppressed\n');

    // --- Test 6: unknown number ---
    console.log('--- Test 6: Unknown number returns resolved:false ---');
    const unknown = await resolve(unknownPhone, 'MTN');
    if (unknown.status !== 200 || unknown.body?.resolved !== false) {
      fail('Expected 200 with resolved:false', unknown.body);
    }
    console.log('PASSED: unknown number returns resolved:false\n');

    // --- Test 7: another user's recipient is not exposed ---
    console.log('--- Test 7: Recipients of other users are not exposed ---');
    const otherUser = await resolve(otherUserPhone, 'MTN');
    if (otherUser.body?.resolved !== false) {
      fail('Expected the beneficiary of user B to stay invisible to user A', otherUser.body);
    }
    console.log('PASSED: per-user isolation holds\n');

    // --- Test 8: invalid input ---
    console.log('--- Test 8: Invalid phone and network are rejected ---');
    const badPhone = await resolve('12345');
    if (badPhone.status !== 400) fail(`Expected 400 for a short number, got ${badPhone.status}`, badPhone.body);
    const badNetwork = await resolve(savedPhone, 'Orange');
    if (badNetwork.status !== 400) fail(`Expected 400 for an unsupported network, got ${badNetwork.status}`, badNetwork.body);
    const noPhone = await fetch(`${baseUrl}/api/beneficiaries/resolve`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    if (noPhone.status !== 400) fail(`Expected 400 when phone is missing, got ${noPhone.status}`);
    console.log('PASSED: invalid input rejected with 400\n');

    console.log('=== ALL RECIPIENT RESOLUTION TESTS PASSED ===');
  } finally {
    server.close();
    await prisma.beneficiary.deleteMany({ where: { phone: { in: fixturePhones } } });
    await prisma.transaction.deleteMany({ where: { recipientPhone: { in: fixturePhones } } });
    await prisma.$disconnect();
    process.exit(0);
  }
}

main().catch(async (err) => {
  console.error('Unexpected error:', err);
  await prisma.$disconnect();
  process.exit(1);
});
