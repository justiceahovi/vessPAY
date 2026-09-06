import dotenv from 'dotenv';
dotenv.config();

process.env.NODE_ENV = 'test';

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateWeWireSignature } from '../src/lib/webhook';

async function main() {
  console.log('=== T5.4 Test: Payout Webhook & Transaction State Machine ===\n');

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

  const initialBalance = Number(usdWallet.balance);
  console.log(`Initial USD wallet balance: $${initialBalance.toFixed(2)}`);

  // 2. Start local ephemeral test server
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}`);

  const secret = process.env.WEWIRE_WEBHOOK_SECRET || 'whsec_MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4NdevTestSecretKeyForWebhooks1234567890=';

  try {
    // 3. Create test transaction in PENDING status
    console.log('\n--- Step 1: Create Local PENDING Payout Transaction ---');
    const wewireTxId = `ww_test_disb_${Date.now()}`;
    const idempotencyKey = `payout-wh-test-${Date.now()}`;
    const sourceAmount = 5.0;
    const fee = 0.05;
    const expectedDebit = Number((sourceAmount + fee).toFixed(2));

    const testTx = await prisma.transaction.create({
      data: {
        userId: user.id,
        type: 'payout',
        status: 'PENDING',
        sourceCurrency: 'USD',
        sourceAmount: sourceAmount,
        destinationCurrency: 'GHS',
        destinationAmount: 58.0,
        fee: fee,
        exchangeRate: 11.6,
        recipientName: 'Kwame Mensah',
        recipientPhone: '0240000001',
        network: 'MTN',
        country: 'GH',
        wewireTransactionId: wewireTxId,
        idempotencyKey,
      },
    });

    console.log(`Created test transaction: id=${testTx.id}, status=${testTx.status}, wewireTxId=${wewireTxId}`);

    // Helper to send signed webhook
    async function sendWebhook(body: any, eventId: string) {
      const rawBody = JSON.stringify(body);
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = generateWeWireSignature({
        secret,
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

    // 4. Test Step 2: Simulate disbursement.initiated -> PROCESSING
    console.log('\n--- Step 2: Send disbursement.initiated Event ---');
    const initEventId = `evt_init_${Date.now()}`;
    const initPayload = {
      eventType: 'disbursement.initiated',
      id: initEventId,
      data: {
        id: wewireTxId,
        reference: `VP-PAY-${testTx.id.slice(0, 8)}`,
        type: 'DISBURSEMENT',
        status: 'PENDING',
        amount: '58.00',
        fee: '2.00',
        currency: 'GHS',
      },
    };

    const initRes = await sendWebhook(initPayload, initEventId);
    console.log(`Initiated webhook status: ${initRes.status}`);
    const initData: any = await initRes.json();
    console.log('Initiated webhook response:', initData);

    if (initRes.status !== 200) {
      console.error(`FAILED: Expected 200, got ${initRes.status}`);
      process.exit(1);
    }

    const txAfterInit = await prisma.transaction.findUnique({
      where: { id: testTx.id },
    });
    console.log(`Transaction status after initiated event: ${txAfterInit?.status}`);
    if (txAfterInit?.status !== 'PROCESSING') {
      console.error(`FAILED: Expected status PROCESSING, got ${txAfterInit?.status}`);
      process.exit(1);
    }

    // Verify wallet balance is UNCHANGED on initiated
    const walletAfterInit = await prisma.wallet.findUnique({
      where: { id: usdWallet.id },
    });
    console.log(`Wallet balance after initiated: $${Number(walletAfterInit?.balance).toFixed(2)} (expected: $${initialBalance.toFixed(2)})`);
    if (Number(walletAfterInit?.balance) !== initialBalance) {
      console.error('FAILED: Wallet should NOT be debited on initiated');
      process.exit(1);
    }
    console.log('SUCCESS: Payout successfully moved to PROCESSING without wallet debit.');

    // 5. Test Step 3: Simulate disbursement.completed -> COMPLETED + Debit
    console.log('\n--- Step 3: Send disbursement.completed Event ---');
    const compEventId = `evt_comp_${Date.now()}`;
    const compPayload = {
      eventType: 'disbursement.completed',
      id: compEventId,
      data: {
        id: wewireTxId,
        reference: `VP-PAY-${testTx.id.slice(0, 8)}`,
        type: 'DISBURSEMENT',
        status: 'SUCCESSFUL',
        amount: '58.00',
        fee: '2.00',
        currency: 'GHS',
      },
    };

    const compRes = await sendWebhook(compPayload, compEventId);
    console.log(`Completed webhook status: ${compRes.status}`);
    const compData: any = await compRes.json();
    console.log('Completed webhook response:', compData);

    if (compRes.status !== 200) {
      console.error(`FAILED: Expected 200, got ${compRes.status}`);
      process.exit(1);
    }

    const txAfterComp = await prisma.transaction.findUnique({
      where: { id: testTx.id },
    });
    console.log(`Transaction status after completed event: ${txAfterComp?.status}`);
    if (txAfterComp?.status !== 'COMPLETED') {
      console.error(`FAILED: Expected status COMPLETED, got ${txAfterComp?.status}`);
      process.exit(1);
    }

    // Verify wallet was debited exactly once
    const walletAfterComp = await prisma.wallet.findUnique({
      where: { id: usdWallet.id },
    });
    const balanceAfterComp = Number(walletAfterComp?.balance);
    const expectedBalanceAfterComp = Number((initialBalance - expectedDebit).toFixed(2));
    console.log(`Wallet balance after completed: $${balanceAfterComp.toFixed(2)} (expected: $${expectedBalanceAfterComp.toFixed(2)})`);

    if (Math.abs(balanceAfterComp - expectedBalanceAfterComp) > 0.01) {
      console.error(`FAILED: Expected balance $${expectedBalanceAfterComp.toFixed(2)}, got $${balanceAfterComp.toFixed(2)}`);
      process.exit(1);
    }
    console.log('SUCCESS: Transaction moved to COMPLETED and wallet debited exactly once.');

    // 6. Test Step 4: Simulate duplicate delivery of completed webhook (same eventId)
    console.log('\n--- Step 4: Duplicate Webhook Delivery (Same Event ID) ---');
    const dupRes = await sendWebhook(compPayload, compEventId);
    console.log(`Duplicate webhook status: ${dupRes.status}`);
    const dupData: any = await dupRes.json();
    console.log('Duplicate webhook response:', dupData);

    if (dupRes.status !== 200 || dupData.status !== 'SKIPPED') {
      console.error(`FAILED: Expected HTTP 200 with status SKIPPED, got ${dupRes.status} / ${dupData.status}`);
      process.exit(1);
    }

    const walletAfterDup = await prisma.wallet.findUnique({
      where: { id: usdWallet.id },
    });
    if (Number(walletAfterDup?.balance) !== balanceAfterComp) {
      console.error('FAILED: Wallet was debited again on duplicate webhook!');
      process.exit(1);
    }
    console.log('SUCCESS: Duplicate event skipped at gateway, wallet balance untouched.');

    // 7. Test Step 5: Simulate redelivery with different event ID (inner state machine idempotency)
    console.log('\n--- Step 5: Redelivery with New Event ID (Inner State Defense) ---');
    const newEventId = `evt_comp_resend_${Date.now()}`;
    const resendRes = await sendWebhook(compPayload, newEventId);
    console.log(`Resend webhook status: ${resendRes.status}`);

    const walletAfterResend = await prisma.wallet.findUnique({
      where: { id: usdWallet.id },
    });
    if (Number(walletAfterResend?.balance) !== balanceAfterComp) {
      console.error('FAILED: Wallet was debited again on re-sent event!');
      process.exit(1);
    }
    console.log('SUCCESS: State machine prevented double-debit even with new event ID.');

    // 8. Test Step 6: Simulate disbursement.failed scenario
    console.log('\n--- Step 6: Simulate Failed Payout Webhook ---');
    const failTxId = `ww_test_fail_${Date.now()}`;
    const failTx = await prisma.transaction.create({
      data: {
        userId: user.id,
        type: 'payout',
        status: 'PENDING',
        sourceCurrency: 'USD',
        sourceAmount: 10.0,
        destinationCurrency: 'GHS',
        destinationAmount: 116.0,
        fee: 0.1,
        exchangeRate: 11.6,
        recipientName: 'Kwame Mensah',
        recipientPhone: '0240000002', // Failure test phone
        network: 'MTN',
        country: 'GH',
        wewireTransactionId: failTxId,
        idempotencyKey: `payout-fail-test-${Date.now()}`,
      },
    });

    const currentBalanceBeforeFail = Number((await prisma.wallet.findUnique({ where: { id: usdWallet.id } }))?.balance);

    const failEventId = `evt_fail_${Date.now()}`;
    const failPayload = {
      eventType: 'disbursement.failed',
      id: failEventId,
      data: {
        id: failTxId,
        reference: `VP-PAY-${failTx.id.slice(0, 8)}`,
        type: 'DISBURSEMENT',
        status: 'FAILED',
        reason: 'Operator rejected transaction',
        amount: '116.00',
        currency: 'GHS',
      },
    };

    const failRes = await sendWebhook(failPayload, failEventId);
    console.log(`Failed webhook status: ${failRes.status}`);

    const txAfterFail = await prisma.transaction.findUnique({
      where: { id: failTx.id },
    });
    console.log(`Transaction status after failure event: ${txAfterFail?.status}`);
    if (txAfterFail?.status !== 'FAILED') {
      console.error(`FAILED: Expected status FAILED, got ${txAfterFail?.status}`);
      process.exit(1);
    }

    const balanceAfterFail = Number((await prisma.wallet.findUnique({ where: { id: usdWallet.id } }))?.balance);
    if (balanceAfterFail !== currentBalanceBeforeFail) {
      console.error('FAILED: Wallet balance changed on failed payout!');
      process.exit(1);
    }
    console.log('SUCCESS: Failed payout moved to FAILED and wallet was not debited.');

    console.log('\n=== ALL T5.4 ACCEPTANCE CRITERIA SATISFIED! ===');
    server.close();
    process.exit(0);
  } catch (err) {
    console.error('Error during test-payout-webhook:', err);
    server.close();
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
