process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';
import { generateWeWireSignature } from '../src/lib/webhook';

async function main() {
  console.log('=== T5.7 Acceptance Criteria Test: Transaction List & Detail Live Endpoints ===\n');

  // 1. Fetch existing users (Rule: Don't create new users for the test)
  const users = await prisma.user.findMany({
    take: 2,
    orderBy: { createdAt: 'asc' },
    include: { wallets: true },
  });

  if (users.length < 2) {
    console.error('FAILED: Need at least 2 existing users in database for isolation test.');
    process.exit(1);
  }

  const userA = users[0];
  const userB = users[1];

  console.log(`User A: ${userA.email} (ID: ${userA.id})`);
  console.log(`User B: ${userB.email} (ID: ${userB.id})`);

  let usdWalletA = userA.wallets.find((w) => w.currency === 'USD');
  if (!usdWalletA) {
    usdWalletA = await prisma.wallet.create({
      data: {
        userId: userA.id,
        currency: 'USD',
        balance: 100.0,
      },
    });
  } else if (Number(usdWalletA.balance) < 20) {
    usdWalletA = await prisma.wallet.update({
      where: { id: usdWalletA.id },
      data: { balance: 100.0 },
    });
  }

  const tokenA = generateToken({ userId: userA.id, email: userA.email });
  const tokenB = generateToken({ userId: userB.id, email: userB.email });

  // 2. Start ephemeral test server
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}\n`);

  const webhookSecret =
    process.env.WEWIRE_WEBHOOK_SECRET ||
    'whsec_MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4NdevTestSecretKeyForWebhooks1234567890=';

  try {
    // 3. Step 1: Query initial transactions for User A
    console.log('--- Step 1: Fetch initial transaction list for User A ---');
    const initialListRes = await fetch(`${baseUrl}/api/payments`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    if (!initialListRes.ok) {
      throw new Error(`Failed to fetch transactions: ${initialListRes.status} ${await initialListRes.text()}`);
    }
    const initialListData = await initialListRes.json();
    const paymentsInitial = Array.isArray(initialListData) ? initialListData : (initialListData.payments ?? []);
    const initialCount = paymentsInitial.length;
    console.log(`User A currently has ${initialCount} transactions.\n`);

    // 4. Step 2: Create a completed demo payment
    console.log('--- Step 2: Create a demo payout transaction and move to COMPLETED via webhook ---');
    const idempotencyKey = `idem_t57_${Date.now()}`;
    const wewireTxId = `ww_disb_t57_${Date.now()}`;
    const destinationAmount = 180.0;
    const sourceAmount = 12.0;
    const fee = 0.12;
    const exchangeRate = 15.0;

    const newTx = await prisma.transaction.create({
      data: {
        userId: userA.id,
        type: 'payout',
        status: 'PENDING',
        sourceCurrency: 'USD',
        sourceAmount,
        destinationCurrency: 'GHS',
        destinationAmount,
        fee,
        exchangeRate,
        recipientName: 'Abena Osei',
        recipientPhone: '0244123987',
        network: 'MTN',
        country: 'GH',
        wewireTransactionId: wewireTxId,
        idempotencyKey,
      },
    });
    console.log(`Created PENDING transaction ${newTx.id} with WeWire ID: ${wewireTxId}`);

    // Fire webhook to transition transaction to COMPLETED
    const eventId = `evt_comp_${Date.now()}`;
    const timestamp = Math.floor(Date.now() / 1000);
    const webhookPayload = {
      eventType: 'disbursement.completed',
      id: eventId,
      data: {
        id: wewireTxId,
        reference: `VP-PAY-${newTx.id.slice(0, 8)}`,
        type: 'DISBURSEMENT',
        status: 'SUCCESSFUL',
        amount: destinationAmount.toFixed(2),
        fee: fee.toFixed(2),
        currency: 'GHS',
      },
    };

    const webhookBody = JSON.stringify(webhookPayload);
    const signature = generateWeWireSignature({
      secret: webhookSecret,
      webhookId: eventId,
      timestamp,
      rawBody: webhookBody,
    });

    const webhookRes = await fetch(`${baseUrl}/api/webhooks/wewire`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'webhook-id': eventId,
        'webhook-timestamp': timestamp.toString(),
        'webhook-signature': signature,
      },
      body: webhookBody,
    });

    if (!webhookRes.ok) {
      throw new Error(`Webhook failed: ${webhookRes.status} ${await webhookRes.text()}`);
    }
    console.log('Webhook processed successfully. Transaction moved to COMPLETED.\n');

    // 5. Step 3: Verify immediate appearance in GET /api/payments
    console.log('--- Step 3: Verify completed demo payment appears immediately in list ---');
    const updatedListRes = await fetch(`${baseUrl}/api/payments`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    if (!updatedListRes.ok) {
      throw new Error(`Failed to fetch updated transactions: ${updatedListRes.status}`);
    }
    const updatedListData = await updatedListRes.json();
    const payments = Array.isArray(updatedListData) ? updatedListData : (updatedListData.payments ?? []);

    if (payments.length !== initialCount + 1) {
      throw new Error(`Expected ${initialCount + 1} transactions, but found ${payments.length}`);
    }

    const firstTx = payments[0];
    console.log(`First transaction in list:`);
    console.log(`  - ID: ${firstTx.id}`);
    console.log(`  - Status: ${firstTx.status}`);
    console.log(`  - Type: ${firstTx.type}`);
    console.log(`  - Recipient: ${firstTx.recipientName}`);
    console.log(`  - Destination Amount: ${firstTx.destinationCurrency} ${firstTx.destinationAmount}`);
    console.log(`  - Source Amount: ${firstTx.sourceCurrency} ${firstTx.sourceAmount}`);
    console.log(`  - Reference: ${firstTx.vesspayReference}`);
    console.log(`  - WeWire ID: ${firstTx.wewireTransactionId}`);

    if (firstTx.id !== newTx.id) {
      throw new Error(`Expected newly completed transaction ${newTx.id} at top of list, but found ${firstTx.id}`);
    }
    if (firstTx.status !== 'COMPLETED') {
      throw new Error(`Expected status COMPLETED, got ${firstTx.status}`);
    }
    if (firstTx.recipientName !== 'Abena Osei') {
      throw new Error(`Expected recipient Abena Osei, got ${firstTx.recipientName}`);
    }
    console.log('PASS: Completed demo payment appears immediately at the top of the transaction list!\n');

    // 6. Step 4: Verify full detail view via GET /api/payments/:id
    console.log('--- Step 4: Verify full transaction detail via GET /api/payments/:id ---');
    const detailRes = await fetch(`${baseUrl}/api/payments/${newTx.id}`, {
      headers: { Authorization: `Bearer ${tokenA}` },
    });
    if (!detailRes.ok) {
      throw new Error(`Failed to fetch transaction detail: ${detailRes.status} ${await detailRes.text()}`);
    }
    const detailData = await detailRes.json();
    const payment = detailData.payment ?? detailData;

    console.log('Detail returned:');
    console.log(JSON.stringify(payment, null, 2));

    const requiredFields = [
      'id',
      'type',
      'status',
      'sourceAmount',
      'sourceCurrency',
      'destinationAmount',
      'destinationCurrency',
      'fee',
      'exchangeRate',
      'recipientName',
      'recipientPhone',
      'network',
      'country',
      'vesspayReference',
      'wewireTransactionId',
      'createdAt',
      'updatedAt',
    ];

    for (const field of requiredFields) {
      if (payment[field] === undefined || payment[field] === null) {
        throw new Error(`Missing required field in detail response: ${field}`);
      }
    }

    if (payment.status !== 'COMPLETED') {
      throw new Error(`Detail status mismatch: expected COMPLETED, got ${payment.status}`);
    }
    if (payment.destinationAmount !== destinationAmount) {
      throw new Error(`Destination amount mismatch: expected ${destinationAmount}, got ${payment.destinationAmount}`);
    }
    if (payment.exchangeRate !== exchangeRate) {
      throw new Error(`Exchange rate mismatch: expected ${exchangeRate}, got ${payment.exchangeRate}`);
    }
    console.log('PASS: Detail endpoint returns all blueprint fields accurately.\n');

    // 7. Step 5: User Isolation Check
    console.log('--- Step 5: Verify User Isolation ---');
    const userBListRes = await fetch(`${baseUrl}/api/payments`, {
      headers: { Authorization: `Bearer ${tokenB}` },
    });
    const userBListData = await userBListRes.json();
    const userBPayments = Array.isArray(userBListData) ? userBListData : (userBListData.payments ?? []);
    const userBHasTx = userBPayments.some((p: any) => p.id === newTx.id);
    if (userBHasTx) {
      throw new Error('Security Violation: User B can see User A transaction in list!');
    }

    const userBDetailRes = await fetch(`${baseUrl}/api/payments/${newTx.id}`, {
      headers: { Authorization: `Bearer ${tokenB}` },
    });
    if (userBDetailRes.status !== 404 && userBDetailRes.status !== 403) {
      throw new Error(`Security Violation: User B fetched User A transaction detail with status ${userBDetailRes.status}`);
    }
    console.log('PASS: User isolation verified. User B cannot see or access User A transaction.\n');

    console.log('========================================================================');
    console.log('SUCCESS: All T5.7 backend acceptance criteria verified!');
    console.log('  - GET /api/payments immediately shows completed demo payment');
    console.log('  - GET /api/payments/:id includes all Section 7 detail fields');
    console.log('  - Multi-tenant user isolation strictly enforced');
    console.log('========================================================================');
  } finally {
    server.close();
    await prisma.$disconnect();
    process.exit(0);
  }
}

main().catch((err) => {
  console.error('Test failed with error:', err);
  process.exit(1);
});
