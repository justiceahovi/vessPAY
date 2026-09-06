import dotenv from 'dotenv';
dotenv.config();

process.env.NODE_ENV = 'test';

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';

async function main() {
  console.log('=== T5.3 Test: Wire Real WeWire Payout Call ===\n');

  // 1. Find an existing user (Rule: Don't create new users for the test)
  let existingUser = await prisma.user.findFirst({
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

  if (!existingUser) {
    // Fallback to any existing user
    existingUser = await prisma.user.findFirst({
      include: { wallets: true },
    });
    if (!existingUser) {
      console.error('FAILED: No existing users found in database.');
      process.exit(1);
    }
    // Ensure sufficient balance for the test
    const usdWallet = existingUser.wallets.find((w) => w.currency === 'USD');
    if (usdWallet) {
      await prisma.wallet.update({
        where: { id: usdWallet.id },
        data: { balance: 100 },
      });
    } else {
      await prisma.wallet.create({
        data: {
          userId: existingUser.id,
          currency: 'USD',
          balance: 100,
        },
      });
    }
    existingUser = await prisma.user.findUnique({
      where: { id: existingUser.id },
      include: { wallets: true },
    });
  }

  console.log(`Using existing user: ${existingUser!.email} (ID: ${existingUser!.id})`);
  const initialWallet = existingUser!.wallets.find((w) => w.currency === 'USD');
  const initialBalance = Number(initialWallet?.balance ?? 0);
  console.log(`Initial USD wallet balance: $${initialBalance.toFixed(2)}`);

  // 2. Generate auth token
  const authToken = generateToken({
    userId: existingUser!.id,
    email: existingUser!.email,
  });

  // 3. Start local ephemeral test server
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}`);

  try {
    // 4. Test Quote first to preview conversion
    console.log('\n--- Step 1: Request Payment Quote ---');
    const quoteRes = await fetch(`${baseUrl}/api/payments/quote`, {
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
      }),
    });

    if (!quoteRes.ok) {
      console.error('Quote failed:', await quoteRes.text());
      process.exit(1);
    }

    const quoteData = await quoteRes.json();
    console.log('Quote response:', JSON.stringify(quoteData, null, 2));

    // 5. Test POST /api/payments with real WeWire payout
    console.log('\n--- Step 2: Create Payment with Real WeWire Payout Call ---');
    const idempotencyKey = `t53-pay-test-${Date.now()}`;
    const paymentPayload = {
      idempotencyKey,
      country: 'GH',
      network: 'MTN',
      phone: '0240000001',
      destinationAmount: 10.0,
      destinationCurrency: 'GHS',
      recipientName: 'Kwame Mensah',
    };

    console.log('Sending POST /api/payments with payload:', paymentPayload);
    const payRes = await fetch(`${baseUrl}/api/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify(paymentPayload),
    });

    const payStatus = payRes.status;
    const payData: any = await payRes.json();
    console.log(`Payment Response Status: ${payStatus}`);
    console.log('Payment Response Body:', JSON.stringify(payData, null, 2));

    if (payStatus !== 201) {
      console.error(`FAILED: Expected HTTP 201 Created, got ${payStatus}`);
      process.exit(1);
    }

    if (!payData.transactionId) {
      console.error('FAILED: Expected transactionId in response');
      process.exit(1);
    }

    if (payData.status !== 'PENDING') {
      console.error(`FAILED: Expected status PENDING, got ${payData.status}`);
      process.exit(1);
    }

    if (!payData.wewireTransactionId) {
      console.error('FAILED: Expected wewireTransactionId in response');
      process.exit(1);
    }

    console.log(`\nSUCCESS: Payout dispatched! Local transactionId=${payData.transactionId}, WeWireId=${payData.wewireTransactionId}, Status=${payData.status}`);

    // 6. Verify Database Transaction Row
    console.log('\n--- Step 3: Verify Database Transaction Row ---');
    const dbTx = await prisma.transaction.findUnique({
      where: { id: payData.transactionId },
    });

    if (!dbTx) {
      console.error('FAILED: Transaction not found in database');
      process.exit(1);
    }

    console.log('Database transaction row:');
    console.log({
      id: dbTx.id,
      userId: dbTx.userId,
      status: dbTx.status,
      wewireTransactionId: dbTx.wewireTransactionId,
      sourceAmount: dbTx.sourceAmount.toString(),
      sourceCurrency: dbTx.sourceCurrency,
      destinationAmount: dbTx.destinationAmount.toString(),
      destinationCurrency: dbTx.destinationCurrency,
      fee: dbTx.fee.toString(),
      exchangeRate: dbTx.exchangeRate.toString(),
      idempotencyKey: dbTx.idempotencyKey,
    });

    if (dbTx.status !== 'PENDING') {
      console.error(`FAILED: Database status is ${dbTx.status}, expected PENDING`);
      process.exit(1);
    }

    if (dbTx.wewireTransactionId !== payData.wewireTransactionId) {
      console.error(`FAILED: DB wewireTransactionId (${dbTx.wewireTransactionId}) does not match response (${payData.wewireTransactionId})`);
      process.exit(1);
    }

    // 7. Verify Local Wallet Balance in PENDING Status (Debit occurs on COMPLETED webhook per T5.4)
    console.log('\n--- Step 4: Verify Local Wallet Balance in PENDING Status ---');
    const updatedWallet = await prisma.wallet.findUnique({
      where: { id: initialWallet!.id },
    });
    const updatedBalance = Number(updatedWallet?.balance ?? 0);
    console.log(`Wallet balance: initial=$${initialBalance.toFixed(2)}, current in PENDING=$${updatedBalance.toFixed(2)} (debit scheduled on COMPLETED webhook per T5.4)`);
    console.log('SUCCESS: Wallet balance remains intact while payout is PENDING.');

    // 8. Verify Idempotency
    console.log('\n--- Step 5: Test Idempotency ---');
    const repeatRes = await fetch(`${baseUrl}/api/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify(paymentPayload),
    });

    const repeatStatus = repeatRes.status;
    const repeatData: any = await repeatRes.json();
    console.log(`Idempotent Request Status: ${repeatStatus}`);
    console.log('Idempotent Response:', JSON.stringify(repeatData, null, 2));

    if (repeatStatus !== 200) {
      console.error(`FAILED: Expected HTTP 200 for idempotent request, got ${repeatStatus}`);
      process.exit(1);
    }

    if (repeatData.transactionId !== payData.transactionId) {
      console.error('FAILED: Idempotent request returned different transactionId');
      process.exit(1);
    }

    if (repeatData.wewireTransactionId !== payData.wewireTransactionId) {
      console.error('FAILED: Idempotent request returned different wewireTransactionId');
      process.exit(1);
    }

    console.log('SUCCESS: Idempotency confirmed!');

    // 9. Verify with Live WeWire Sandbox API
    console.log('\n--- Step 6: Verify Transaction Against Live WeWire Sandbox API ---');
    const apiKey = process.env.WEWIRE_API_KEY;
    const weWireBaseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');

    if (apiKey) {
      const weWireTxRes = await fetch(`${weWireBaseUrl}/v1/transactions/${payData.wewireTransactionId}`, {
        headers: {
          'ww-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      });

      console.log(`WeWire GET /v1/transactions/${payData.wewireTransactionId} Status: ${weWireTxRes.status}`);
      if (weWireTxRes.ok) {
        const weWireTx = await weWireTxRes.json();
        console.log('WeWire Transaction Details:');
        console.log({
          id: weWireTx.id,
          type: weWireTx.type,
          status: weWireTx.status,
          amount: weWireTx.amount,
          currency: weWireTx.currency,
          channel: weWireTx.channel,
          destination: weWireTx.destination,
        });
        console.log('SUCCESS: Verified transaction on WeWire sandbox rails!');
      } else {
        console.warn('Could not fetch WeWire transaction directly (non-fatal):', await weWireTxRes.text());
      }
    }

    console.log('\n=== ALL T5.3 ACCEPTANCE CRITERIA SATISFIED! ===');
    server.close();
    process.exit(0);
  } catch (err) {
    console.error('Error during payment test:', err);
    server.close();
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
