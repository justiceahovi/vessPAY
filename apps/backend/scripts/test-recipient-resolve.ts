process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';
import { ensureTestUsers } from './seed-test-users';
import { lookupAccountName } from '../src/lib/wewire';

function fail(message: string, extra?: unknown): never {
  console.error(`FAILED: ${message}`, extra ?? '');
  process.exit(1);
}

async function main() {
  console.log('=== Test: Recipient name resolution (GET /api/beneficiaries/resolve) ===\n');

  // Uses whatever users exist, seeding only when the database is empty
  const users = await ensureTestUsers({ count: 2 });
  if (users.length < 2) {
    fail('Could not obtain two users to test user isolation.');
  }
  const [userA, userB] = users;
  console.log(`User A: ${userA.email}`);
  console.log(`User B: ${userB.email}\n`);

  // The operator is authoritative, so a number it recognises always resolves to
  // the real account holder. To exercise the local fallbacks we need numbers the
  // operator does NOT know -- which ones those are depends on sandbox data, so
  // find them rather than assuming.
  // A wide spread of numbers, since sandbox coverage varies from run to run
  const candidates = ['0247000001'];
  for (let i = 0; i < 40; i++) {
    candidates.push(`02479${(100000 + i * 7919).toString().slice(-5)}`);
  }

  const unknownToOperator: string[] = [];
  let knownToOperator: { phone: string; name: string } | null = null;

  for (const candidate of candidates) {
    const lookup = await lookupAccountName({
      accountCode: 'MTN',
      accountNumber: candidate,
      currency: 'GHS',
    });
    if (lookup) {
      knownToOperator ??= { phone: candidate, name: lookup.accountName };
    } else {
      unknownToOperator.push(candidate);
    }
    if (unknownToOperator.length >= 5 && knownToOperator) break;
  }

  if (unknownToOperator.length < 5) {
    fail('Could not find five numbers the operator does not recognise', unknownToOperator);
  }

  const [savedPhone, placeholderPhone, unknownPhone, otherUserPhone, historyPhone] =
      unknownToOperator;
  console.log(`Numbers unknown to the operator: ${unknownToOperator.slice(0, 4).join(', ')}`);
  console.log(
    knownToOperator
      ? `Number the operator confirms: ${knownToOperator.phone} -> ${knownToOperator.name}\n`
      : 'No sandbox number resolved with the operator right now\n'
  );

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
      network: 'MTN Mobile Money',
      institutionCode: 'MTN',
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

  const resolveAccount = async (accountNumber: string, network: string) => {
    const query = new URLSearchParams({ accountNumber, network });
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
    const international = await resolve(`+233${savedPhone.slice(1)}`, 'MTN');
    if (international.body?.resolved !== true || international.body?.name !== 'Ama Serwaa') {
      fail('Expected +233 format to resolve to Ama Serwaa', international.body);
    }
    console.log('PASSED: international format normalized\n');

    // --- Test 4: falls back to a previously paid recipient ---
    console.log('--- Test 4: Previously paid recipient resolves from history ---');
    const history = await resolve(historyPhone, 'MTN');
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

    // --- Test 9: the operator confirms the account holder name ---
    console.log('--- Test 9: Provider name confirmation ---');
    if (knownToOperator) {
      const confirmed = await resolve(knownToOperator.phone, 'MTN');
      if (confirmed.status !== 200) fail(`Expected 200, got ${confirmed.status}`, confirmed.body);
      if (confirmed.body?.source !== 'provider' || confirmed.body?.verified !== true) {
        fail('A number the operator recognises must come back verified from the provider', confirmed.body);
      }
      if (confirmed.body?.name !== knownToOperator.name) {
        fail(`Expected the operator name "${knownToOperator.name}"`, confirmed.body);
      }
      console.log(
        `PASSED: MTN confirmed ${knownToOperator.phone} as "${confirmed.body.name}" (verified: true)`
      );

      // The operator wins over anything we have stored locally
      await prisma.beneficiary.deleteMany({ where: { phone: knownToOperator.phone } });
      await prisma.beneficiary.create({
        data: {
          userId: userA.id,
          name: 'Stale Local Name',
          network: 'MTN',
          institutionCode: 'MTN',
          phone: knownToOperator.phone,
          country: 'GH',
        },
      });
      const overridden = await resolve(knownToOperator.phone, 'MTN');
      if (overridden.body?.name !== knownToOperator.name || overridden.body?.source !== 'provider') {
        fail('The operator name must take precedence over a stored one', overridden.body);
      }
      await prisma.beneficiary.deleteMany({ where: { phone: knownToOperator.phone } });
      console.log('PASSED: the operator name overrides a stale saved name');
    } else {
      console.log('SKIPPED: no sandbox number resolved with the operator during this run');
    }

    // A name that only we know is never presented as provider-verified
    const localOnly = await resolve(savedPhone, 'MTN');
    if (localOnly.body?.verified !== false || localOnly.body?.source !== 'beneficiary') {
      fail('A locally known name must not be marked verified', localOnly.body);
    }
    console.log('PASSED: locally known names are returned with verified: false\n');

    // --- Test 10: an unconfirmable number stays unresolved, not an error ---
    console.log('--- Test 10: Unconfirmable accounts degrade gracefully ---');
    const unconfirmable = await resolve(unknownPhone, 'MTN');
    if (unconfirmable.status !== 200 || unconfirmable.body?.resolved !== false) {
      fail('An account WeWire cannot resolve should return 200 resolved:false', unconfirmable.body);
    }
    if (unconfirmable.body?.verified !== false) {
      fail('An unresolved account must not be marked verified', unconfirmable.body);
    }
    console.log('PASSED: unconfirmable numbers return 200 with resolved:false\n');

    // --- Test 11: bank accounts are looked up by account number ---
    console.log('--- Test 11: Bank account name confirmation ---');
    const bankLookup = await resolveAccount('1234567890123', 'GCB');
    if (bankLookup.status !== 200) fail(`Expected 200, got ${bankLookup.status}`, bankLookup.body);
    if (bankLookup.body?.channel !== 'BANK') {
      fail('A bank lookup should report the BANK channel', bankLookup.body);
    }
    if (bankLookup.body?.accountNumber !== '1234567890123') {
      fail('The normalized account number should be echoed back', bankLookup.body);
    }
    console.log(
      `PASSED: bank lookup routed to GCB (resolved: ${bankLookup.body.resolved}, verified: ${bankLookup.body.verified})\n`
    );

    // --- Test 12: input validation ---
    console.log('--- Test 12: Lookups require an account to look up ---');
    const noTarget = await fetch(`${baseUrl}/api/beneficiaries/resolve?network=MTN`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    if (noTarget.status !== 400) fail(`Expected 400 with neither phone nor accountNumber, got ${noTarget.status}`);
    const badBankAccount = await resolveAccount('123', 'GCB');
    if (badBankAccount.status !== 400) {
      fail(`Expected 400 for a 3-digit bank account, got ${badBankAccount.status}`, badBankAccount.body);
    }
    console.log('PASSED: missing and malformed accounts rejected with 400\n');

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
