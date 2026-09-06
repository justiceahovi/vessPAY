process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';

async function main() {
  console.log('=== T5.5 Test: Payment History Endpoints (GET /api/payments & GET /api/payments/:id) ===\n');

  // 1. Fetch two existing users (Rule: Don't create new users for the test)
  const users = await prisma.user.findMany({
    take: 2,
    orderBy: { createdAt: 'asc' },
    include: { wallets: true },
  });

  if (users.length < 2) {
    console.error('FAILED: Need at least 2 existing users in the database to test user isolation.');
    process.exit(1);
  }

  const userA = users[0];
  const userB = users[1];

  console.log(`User A: ${userA.email} (ID: ${userA.id})`);
  console.log(`User B: ${userB.email} (ID: ${userB.id})`);

  // Ensure User A has at least one transaction
  let txA = await prisma.transaction.findFirst({
    where: { userId: userA.id },
    orderBy: { createdAt: 'desc' },
  });

  if (!txA) {
    console.log('Creating a sample transaction for existing User A...');
    txA = await prisma.transaction.create({
      data: {
        userId: userA.id,
        type: 'payout',
        status: 'COMPLETED',
        sourceCurrency: 'USD',
        sourceAmount: 25.0,
        destinationCurrency: 'GHS',
        destinationAmount: 290.0,
        fee: 0.25,
        exchangeRate: 11.6,
        recipientName: 'Kofi Annan',
        recipientPhone: '0241112233',
        network: 'MTN',
        country: 'GH',
        wewireTransactionId: `ww_tx_hist_a_${Date.now()}`,
        idempotencyKey: `idem_hist_a_${Date.now()}`,
      },
    });
  }

  // Ensure User B has at least one transaction
  let txB = await prisma.transaction.findFirst({
    where: { userId: userB.id },
    orderBy: { createdAt: 'desc' },
  });

  if (!txB) {
    console.log('Creating a sample transaction for existing User B...');
    txB = await prisma.transaction.create({
      data: {
        userId: userB.id,
        type: 'payout',
        status: 'PENDING',
        sourceCurrency: 'USD',
        sourceAmount: 15.0,
        destinationCurrency: 'GHS',
        destinationAmount: 174.0,
        fee: 0.15,
        exchangeRate: 11.6,
        recipientName: 'Ama Serwaa',
        recipientPhone: '0509988776',
        network: 'Telecel',
        country: 'GH',
        wewireTransactionId: `ww_tx_hist_b_${Date.now()}`,
        idempotencyKey: `idem_hist_b_${Date.now()}`,
      },
    });
  }

  console.log(`Sample Tx for User A: ${txA.id} (${txA.recipientName}, $${txA.sourceAmount})`);
  console.log(`Sample Tx for User B: ${txB.id} (${txB.recipientName}, $${txB.sourceAmount})`);

  // Generate tokens
  const tokenA = generateToken({ userId: userA.id, email: userA.email });
  const tokenB = generateToken({ userId: userB.id, email: userB.email });

  // Start local ephemeral test server
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}`);

  try {
    // --- TEST 1: Unauthenticated request should return 401 ---
    console.log('\n--- Test 1: Unauthenticated access rejection ---');
    const unauthListRes = await fetch(`${baseUrl}/api/payments`);
    if (unauthListRes.status !== 401) {
      console.error(`FAILED: Expected 401 for unauthenticated GET /api/payments, got ${unauthListRes.status}`);
      process.exit(1);
    }
    const unauthDetailRes = await fetch(`${baseUrl}/api/payments/${txA.id}`);
    if (unauthDetailRes.status !== 401) {
      console.error(`FAILED: Expected 401 for unauthenticated GET /api/payments/:id, got ${unauthDetailRes.status}`);
      process.exit(1);
    }
    console.log('PASSED: Unauthenticated requests correctly rejected with 401');

    // --- TEST 2: GET /api/payments for User A ---
    console.log('\n--- Test 2: GET /api/payments (List History for User A) ---');
    const listResA = await fetch(`${baseUrl}/api/payments`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });

    if (listResA.status !== 200) {
      const err = await listResA.text();
      console.error(`FAILED: GET /api/payments returned ${listResA.status}:`, err);
      process.exit(1);
    }

    const listDataA = await listResA.json();
    if (!Array.isArray(listDataA)) {
      console.error('FAILED: Response is not an array:', listDataA);
      process.exit(1);
    }

    console.log(`Retrieved ${listDataA.length} transactions for User A`);
    if (listDataA.length === 0) {
      console.error('FAILED: Expected at least 1 transaction for User A');
      process.exit(1);
    }

    // Verify user isolation: NONE of the returned transactions should belong to User B
    const leakedTx = listDataA.find((t: any) => t.userId === userB.id || t.id === txB.id);
    if (leakedTx) {
      console.error('FAILED: Security violation! User B transaction found in User A list:', leakedTx);
      process.exit(1);
    }

    // Verify all transactions in list belong to User A
    for (const t of listDataA) {
      if (t.userId !== userA.id) {
        console.error(`FAILED: Transaction ${t.id} has userId ${t.userId}, expected ${userA.id}`);
        process.exit(1);
      }
    }
    console.log('PASSED: All listed transactions strictly belong to User A (User isolation verified)');

    // Verify detail fields in the first transaction
    const firstTx = listDataA[0];
    console.log('\nVerifying transaction detail fields on listed item:');
    console.log(JSON.stringify(firstTx, null, 2));

    const requiredFields = [
      'id',
      'userId',
      'type',
      'status',
      'sourceCurrency',
      'sourceAmount',
      'destinationCurrency',
      'destinationAmount',
      'fee',
      'exchangeRate',
      'rate',
      'recipient',
      'network',
      'country',
      'vesspayReference',
      'reference',
      'timestamps',
      'createdAt',
      'updatedAt',
    ];

    for (const field of requiredFields) {
      if (firstTx[field] === undefined) {
        console.error(`FAILED: Missing required field "${field}" in transaction item`);
        process.exit(1);
      }
    }

    // Verify numeric types
    if (typeof firstTx.sourceAmount !== 'number' || isNaN(firstTx.sourceAmount)) {
      console.error('FAILED: sourceAmount must be a valid number, got:', firstTx.sourceAmount);
      process.exit(1);
    }
    if (typeof firstTx.destinationAmount !== 'number' || isNaN(firstTx.destinationAmount)) {
      console.error('FAILED: destinationAmount must be a valid number, got:', firstTx.destinationAmount);
      process.exit(1);
    }
    if (typeof firstTx.fee !== 'number' || isNaN(firstTx.fee)) {
      console.error('FAILED: fee must be a valid number, got:', firstTx.fee);
      process.exit(1);
    }
    if (typeof firstTx.rate !== 'number' || isNaN(firstTx.rate)) {
      console.error('FAILED: rate must be a valid number, got:', firstTx.rate);
      process.exit(1);
    }

    // Verify recipient structure
    if (!firstTx.recipient || typeof firstTx.recipient !== 'object') {
      console.error('FAILED: recipient must be an object, got:', firstTx.recipient);
      process.exit(1);
    }
    if (!firstTx.recipient.network || !firstTx.recipient.country) {
      console.error('FAILED: recipient object missing network or country:', firstTx.recipient);
      process.exit(1);
    }

    // Verify reference format
    if (!firstTx.vesspayReference.startsWith('VP-PAY-')) {
      console.error('FAILED: vesspayReference must start with "VP-PAY-", got:', firstTx.vesspayReference);
      process.exit(1);
    }

    // Verify timestamps structure
    if (!firstTx.timestamps.createdAt || !firstTx.timestamps.updatedAt) {
      console.error('FAILED: timestamps missing createdAt or updatedAt:', firstTx.timestamps);
      process.exit(1);
    }

    console.log('PASSED: All required transaction detail fields present and correctly formatted with clean numeric types');

    // --- TEST 3: GET /api/payments/:id for User A's own transaction ---
    console.log('\n--- Test 3: GET /api/payments/:id (User A fetching their own transaction) ---');
    const detailResA = await fetch(`${baseUrl}/api/payments/${txA.id}`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });

    if (detailResA.status !== 200) {
      const err = await detailResA.text();
      console.error(`FAILED: Expected 200 for User A's own transaction, got ${detailResA.status}:`, err);
      process.exit(1);
    }

    const detailDataA = await detailResA.json();
    if (detailDataA.id !== txA.id) {
      console.error(`FAILED: Expected transaction ID ${txA.id}, got ${detailDataA.id}`);
      process.exit(1);
    }
    if (detailDataA.userId !== userA.id) {
      console.error(`FAILED: Expected userId ${userA.id}, got ${detailDataA.userId}`);
      process.exit(1);
    }
    console.log('PASSED: User A successfully fetched their own transaction with complete detail');

    // --- TEST 4: GET /api/payments/:id for User B's transaction as User A (User Isolation Enforcement) ---
    console.log('\n--- Test 4: User Isolation - User A attempting to fetch User B\'s transaction ---');
    const isolationRes = await fetch(`${baseUrl}/api/payments/${txB.id}`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });

    if (isolationRes.status !== 404) {
      console.error(`FAILED: Expected 404 NOT_FOUND when User A accesses User B's transaction, got ${isolationRes.status}`);
      process.exit(1);
    }

    const isolationData = await isolationRes.json();
    if (isolationData.error?.code !== 'NOT_FOUND') {
      console.error('FAILED: Expected error code NOT_FOUND, got:', isolationData);
      process.exit(1);
    }
    console.log('PASSED: Accessing another user\'s transaction returns 404 NOT_FOUND (Strict user isolation enforced)');

    // --- TEST 5: GET /api/payments/:id for non-existent ID ---
    console.log('\n--- Test 5: Non-existent transaction ID returns 404 ---');
    const nonExistentRes = await fetch(`${baseUrl}/api/payments/00000000-0000-0000-0000-000000000000`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });

    if (nonExistentRes.status !== 404) {
      console.error(`FAILED: Expected 404 for non-existent transaction, got ${nonExistentRes.status}`);
      process.exit(1);
    }
    console.log('PASSED: Non-existent transaction ID returns 404 NOT_FOUND');

    // --- TEST 6: GET /api/payments for User B ---
    console.log('\n--- Test 6: GET /api/payments for User B ---');
    const listResB = await fetch(`${baseUrl}/api/payments`, {
      headers: { Authorization: `Bearer ${tokenB}` },
    });

    if (listResB.status !== 200) {
      const err = await listResB.text();
      console.error(`FAILED: GET /api/payments for User B returned ${listResB.status}:`, err);
      process.exit(1);
    }

    const listDataB = await listResB.json();
    const leakedFromA = listDataB.find((t: any) => t.userId === userA.id || t.id === txA.id);
    if (leakedFromA) {
      console.error('FAILED: Security violation! User A transaction found in User B list:', leakedFromA);
      process.exit(1);
    }
    console.log(`PASSED: User B retrieved ${listDataB.length} transactions, zero leakage from User A`);

    console.log('\n======================================================');
    console.log('ALL T5.5 PAYMENT HISTORY TESTS PASSED SUCCESSFULLY! ✅');
    console.log('======================================================');
  } catch (error) {
    console.error('Error during test execution:', error);
    process.exit(1);
  } finally {
    server.close();
    await prisma.$disconnect();
    process.exit(0);
  }
}

main();
