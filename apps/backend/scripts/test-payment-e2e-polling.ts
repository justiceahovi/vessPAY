process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';
import { generateWeWireSignature } from '../src/lib/webhook';

async function main() {
  console.log('=== T5.6 Test: Payment E2E Polling & State Transition (Backend Live Verification) ===\n');

  // 1. Select existing user (Rule: Don't create new users for this test)
  let user = await prisma.user.findFirst({
    where: {
      wallets: {
        some: {
          currency: 'USD',
          balance: { gte: 10 },
        },
      },
    },
    include: {
      wallets: true,
    },
  });

  if (!user) {
    user = await prisma.user.findFirst({
      include: { wallets: true },
    });
    if (!user) {
      console.error('FAILED: No existing users found.');
      process.exit(1);
    }
  }

  console.log(`Using existing user: ${user.email} (ID: ${user.id})`);
  const usdWallet = user.wallets.find((w) => w.currency === 'USD');
  if (!usdWallet) {
    console.error('FAILED: User has no USD wallet.');
    process.exit(1);
  }

  // Generate auth token
  const authToken = generateToken({
    userId: user.id,
    email: user.email,
  });

  // Start ephemeral test server
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}`);

  const webhookSecret =
    process.env.WEWIRE_WEBHOOK_SECRET ||
    'whsec_MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4NdevTestSecretKeyForWebhooks1234567890=';

  try {
    // Step 1: Create a payment via POST /api/payments
    console.log('\n--- Step 1: POST /api/payments (Initiate Payment) ---');
    const idempotencyKey = `e2e-poll-test-${Date.now()}`;
    const createRes = await fetch(`${baseUrl}/api/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({
        country: 'GH',
        network: 'MTN',
        phone: '0240000001',
        destinationAmount: 10.0,
        destinationCurrency: 'GHS',
        recipientName: 'Kwame Mensah',
        idempotencyKey,
      }),
    });

    if (createRes.status !== 201) {
      const err = await createRes.text();
      console.error(`FAILED: POST /api/payments returned ${createRes.status}:`, err);
      process.exit(1);
    }

    const createData = await createRes.json();
    console.log('Payment created:', createData);
    const txId = createData.transactionId;
    const wewireTxId = createData.wewireTransactionId;

    if (!txId) {
      console.error('FAILED: Missing transactionId in creation response');
      process.exit(1);
    }

    // Step 2: Poll GET /api/payments/:id in PENDING status
    console.log('\n--- Step 2: GET /api/payments/:id (Poll PENDING Status) ---');
    const poll1Res = await fetch(`${baseUrl}/api/payments/${txId}`, {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    if (poll1Res.status !== 200) {
      console.error(`FAILED: GET /api/payments/${txId} returned ${poll1Res.status}`);
      process.exit(1);
    }
    const poll1Data = await poll1Res.json();
    console.log(`Initial Polled Status: ${poll1Data.status}`);
    if (poll1Data.status !== 'PENDING') {
      console.error(`FAILED: Expected initial status PENDING, got ${poll1Data.status}`);
      process.exit(1);
    }
    console.log('PASSED: Status is PENDING. Mobile screen will show Processing (not Success).');

    // Helper to send signed webhook
    async function sendWebhook(body: any, eventId: string) {
      const rawBody = JSON.stringify(body);
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = generateWeWireSignature({
        secret: webhookSecret,
        webhookId: eventId,
        timestamp,
        rawBody,
      });

      return fetch(`${baseUrl}/api/webhooks/wewire`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'webhook-id': eventId,
          'webhook-timestamp': timestamp.toString(),
          'webhook-signature': signature,
        },
        body: rawBody,
      });
    }

    // Step 3: Trigger disbursement.initiated webhook
    console.log('\n--- Step 3: Send disbursement.initiated Webhook ---');
    const initEventId = `evt_poll_init_${Date.now()}`;
    const initPayload = {
      eventType: 'disbursement.initiated',
      id: initEventId,
      data: {
        id: wewireTxId,
        type: 'DISBURSEMENT',
        status: 'PENDING',
      },
    };

    const initRes = await sendWebhook(initPayload, initEventId);
    console.log(`Initiated webhook response status: ${initRes.status}`);

    // Step 4: Poll GET /api/payments/:id in PROCESSING status
    console.log('\n--- Step 4: GET /api/payments/:id (Poll PROCESSING Status) ---');
    const poll2Res = await fetch(`${baseUrl}/api/payments/${txId}`, {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    const poll2Data = await poll2Res.json();
    console.log(`Second Polled Status: ${poll2Data.status}`);
    if (poll2Data.status !== 'PROCESSING') {
      console.error(`FAILED: Expected status PROCESSING, got ${poll2Data.status}`);
      process.exit(1);
    }
    console.log('PASSED: Status moved to PROCESSING. Mobile screen reflects real progress step.');

    // Step 5: Trigger disbursement.completed webhook
    console.log('\n--- Step 5: Send disbursement.completed Webhook ---');
    const compEventId = `evt_poll_comp_${Date.now()}`;
    const compPayload = {
      eventType: 'disbursement.completed',
      id: compEventId,
      data: {
        id: wewireTxId,
        type: 'DISBURSEMENT',
        status: 'SUCCESSFUL',
      },
    };

    const compRes = await sendWebhook(compPayload, compEventId);
    console.log(`Completed webhook response status: ${compRes.status}`);

    // Step 6: Poll GET /api/payments/:id in COMPLETED status
    console.log('\n--- Step 6: GET /api/payments/:id (Poll COMPLETED Status) ---');
    const poll3Res = await fetch(`${baseUrl}/api/payments/${txId}`, {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    const poll3Data = await poll3Res.json();
    console.log(`Final Polled Status: ${poll3Data.status}`);
    if (poll3Data.status !== 'COMPLETED') {
      console.error(`FAILED: Expected final status COMPLETED, got ${poll3Data.status}`);
      process.exit(1);
    }
    console.log('PASSED: Status confirmed COMPLETED. Mobile screen now routes to Success screen.');
    console.log('Transaction details for Success screen:');
    console.log({
      id: poll3Data.id,
      vesspayReference: poll3Data.vesspayReference,
      status: poll3Data.status,
      sourceAmount: poll3Data.sourceAmount,
      destinationAmount: poll3Data.destinationAmount,
      fee: poll3Data.fee,
      recipient: poll3Data.recipient,
    });

    console.log('\n======================================================');
    console.log('ALL T5.6 E2E POLLING & STATE MACHINE TESTS PASSED! ✅');
    console.log('======================================================');
  } catch (err) {
    console.error('Test error:', err);
    process.exit(1);
  } finally {
    server.close();
    await prisma.$disconnect();
    process.exit(0);
  }
}

main();
