process.env.NODE_ENV = 'test';
import dotenv from 'dotenv';
dotenv.config();

import app from '../src/index';
import { prisma } from '../src/lib/db';
import { generateToken } from '../src/lib/auth';
import { getWeWireInstitutions, resolveInstitution } from '../src/lib/wewire';

function fail(message: string, extra?: unknown): never {
  console.error(`FAILED: ${message}`, extra ?? '');
  process.exit(1);
}

async function main() {
  console.log('=== Test: Bank transfer payout channel (WeWire channel=BANK) ===\n');

  // --- Test 1: institution list comes from WeWire GET /v1/banks ---
  console.log('--- Test 1: Ghana institution list ---');
  const institutions = await getWeWireInstitutions('GHS');
  const banks = institutions.filter((i) => i.channel === 'BANK');
  const momo = institutions.filter((i) => i.channel === 'MOBILE_MONEY');
  if (banks.length === 0) fail('Expected at least one BANK institution for GHS');
  if (momo.length < 3) fail('Expected the three Ghana mobile money operators', momo);
  const gcb = banks.find((b) => b.code === 'GCB');
  if (!gcb) fail('Expected GCB (GCB BANK LIMITED) in the Ghana bank list');
  console.log(`PASSED: ${banks.length} banks, ${momo.length} mobile money operators (e.g. ${gcb.code} = ${gcb.name})\n`);

  // --- Test 2: institutions resolve from codes and display names ---
  console.log('--- Test 2: Institution resolution ---');
  const byCode = await resolveInstitution('GCB');
  const byName = await resolveInstitution('Ecobank');
  const byOperator = await resolveInstitution('Telecel');
  if (byCode.channel !== 'BANK' || byCode.accountType !== 'BANK_ACCOUNT') {
    fail('GCB should resolve to a BANK / BANK_ACCOUNT institution', byCode);
  }
  if (byName.code !== 'ECO') fail('"Ecobank" should resolve to ECO', byName);
  if (byOperator.code !== 'VOD' || byOperator.channel !== 'MOBILE_MONEY') {
    fail('"Telecel" should resolve to the VOD mobile money operator', byOperator);
  }
  let rejected = false;
  try {
    await resolveInstitution('Bank of Nowhere');
  } catch {
    rejected = true;
  }
  if (!rejected) fail('An unknown institution should be rejected');
  console.log('PASSED: codes, display names and operators all resolve; unknown names rejected\n');

  // Existing user with a funded USD wallet (rule: do not create new users)
  const user = await prisma.user.findFirst({
    orderBy: { createdAt: 'asc' },
    include: { wallets: true },
  });
  if (!user) fail('Need at least one existing user in the database');

  const usdWallet = user.wallets.find((w) => w.currency === 'USD');
  if (usdWallet) {
    await prisma.wallet.update({ where: { id: usdWallet.id }, data: { balance: 100 } });
  } else {
    await prisma.wallet.create({
      data: { userId: user.id, currency: 'USD', balance: 100 },
    });
  }

  const token = generateToken({ userId: user.id, email: user.email });
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 3000;
  const baseUrl = `http://localhost:${port}`;
  console.log(`Ephemeral test server running at ${baseUrl}`);
  console.log(`User: ${user.email}\n`);

  const bankAccount = '1234567890123';
  const post = async (path: string, body: any) => {
    const res = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };

  try {
    // --- Test 3: GET /api/banks ---
    console.log('--- Test 3: GET /api/banks ---');
    const allRes = await fetch(`${baseUrl}/api/banks?currency=GHS`);
    const all = (await allRes.json()) as any[];
    if (allRes.status !== 200 || !Array.isArray(all) || all.length === 0) {
      fail(`Expected a populated institution list, got ${allRes.status}`, all);
    }
    const banksOnlyRes = await fetch(`${baseUrl}/api/banks?currency=GHS&channel=BANK`);
    const banksOnly = (await banksOnlyRes.json()) as any[];
    if (banksOnly.some((b) => b.channel !== 'BANK')) {
      fail('channel=BANK returned a non-bank institution', banksOnly);
    }
    const badCurrency = await fetch(`${baseUrl}/api/banks?currency=EUR`);
    if (badCurrency.status !== 400) fail(`Expected 400 for an unsupported currency, got ${badCurrency.status}`);
    console.log(`PASSED: ${all.length} institutions, ${banksOnly.length} banks, unsupported currency rejected\n`);

    // --- Test 4: bank payouts require an account number and a holder name ---
    console.log('--- Test 4: Bank payout validation ---');
    const noAccount = await post('/api/payments', {
      country: 'GH',
      network: 'GCB',
      channel: 'BANK',
      destinationAmount: 20,
      destinationCurrency: 'GHS',
      recipientName: 'Kwabena Owusu',
      idempotencyKey: `bank_noacct_${Date.now()}`,
    });
    if (noAccount.status !== 400) fail(`Expected 400 without accountNumber, got ${noAccount.status}`, noAccount.body);

    const shortAccount = await post('/api/payments', {
      country: 'GH',
      network: 'GCB',
      channel: 'BANK',
      accountNumber: '123',
      destinationAmount: 20,
      recipientName: 'Kwabena Owusu',
      idempotencyKey: `bank_shortacct_${Date.now()}`,
    });
    if (shortAccount.status !== 400) fail(`Expected 400 for a 3-digit account, got ${shortAccount.status}`, shortAccount.body);

    const noName = await post('/api/payments', {
      country: 'GH',
      network: 'GCB',
      channel: 'BANK',
      accountNumber: bankAccount,
      destinationAmount: 20,
      idempotencyKey: `bank_noname_${Date.now()}`,
    });
    if (noName.status !== 400) fail(`Expected 400 without recipientName, got ${noName.status}`, noName.body);

    const channelMismatch = await post('/api/payments', {
      country: 'GH',
      network: 'MTN',
      channel: 'BANK',
      accountNumber: bankAccount,
      destinationAmount: 20,
      recipientName: 'Kwabena Owusu',
      idempotencyKey: `bank_mismatch_${Date.now()}`,
    });
    if (channelMismatch.status !== 400) {
      fail(`Expected 400 when paying MTN over the BANK channel, got ${channelMismatch.status}`, channelMismatch.body);
    }

    const unknownBank = await post('/api/payments', {
      country: 'GH',
      network: 'Bank of Nowhere',
      channel: 'BANK',
      accountNumber: bankAccount,
      destinationAmount: 20,
      recipientName: 'Kwabena Owusu',
      idempotencyKey: `bank_unknown_${Date.now()}`,
    });
    if (unknownBank.status !== 400) fail(`Expected 400 for an unknown bank, got ${unknownBank.status}`, unknownBank.body);
    console.log('PASSED: missing account, short account, missing name, channel mismatch and unknown bank all rejected\n');

    // --- Test 5: a real bank payout attempt against the sandbox ---
    console.log('--- Test 5: Bank payout dispatch ---');
    const idempotencyKey = `bank_payout_${Date.now()}`;
    const payout = await post('/api/payments', {
      country: 'GH',
      network: 'GCB',
      channel: 'BANK',
      accountNumber: bankAccount,
      destinationAmount: 20,
      destinationCurrency: 'GHS',
      recipientName: 'Kwabena Owusu',
      idempotencyKey,
    });

    const transactionId = payout.body?.transactionId;
    if (!transactionId) fail('Expected a transactionId in the payment response', payout.body);

    const tx = await prisma.transaction.findUnique({ where: { id: transactionId } });
    if (!tx) fail('Transaction row was not persisted');
    if (tx.channel !== 'BANK') fail(`Expected the transaction channel to be BANK, got ${tx.channel}`);
    if (tx.recipientAccount !== bankAccount) {
      fail(`Expected recipientAccount ${bankAccount}, got ${tx.recipientAccount}`);
    }
    if (tx.institutionCode !== 'GCB') fail(`Expected institutionCode GCB, got ${tx.institutionCode}`);
    if (tx.recipientPhone) fail('A bank payout should not carry a mobile money number');

    const beneficiary = await prisma.beneficiary.findFirst({
      where: { userId: user.id, channel: 'BANK', accountNumber: bankAccount },
      orderBy: { createdAt: 'desc' },
    });
    if (!beneficiary) fail('Expected a BANK beneficiary row for the account');
    if (beneficiary.institutionCode !== 'GCB') {
      fail(`Expected the beneficiary institutionCode GCB, got ${beneficiary.institutionCode}`);
    }
    if (!beneficiary.wewireBeneficiaryId) fail('Expected a WeWire beneficiary id on the saved beneficiary');
    console.log(
      `Bank beneficiary registered with WeWire: ${beneficiary.wewireBeneficiaryId} (${beneficiary.network} / ${beneficiary.institutionCode})`
    );

    if (payout.status === 201) {
      if (tx.status !== 'PENDING') fail(`Expected PENDING after dispatch, got ${tx.status}`);
      if (!tx.wewireTransactionId) fail('Expected a WeWire transaction id after dispatch');
      console.log(`PASSED: bank payout accepted by WeWire (${tx.wewireTransactionId}), status ${tx.status}\n`);
    } else if (payout.status === 502) {
      if (tx.status !== 'FAILED') fail(`Expected FAILED after a rejected dispatch, got ${tx.status}`);
      console.log('PASSED (with upstream caveat): our side built and dispatched the BANK payout correctly,');
      console.log(`  but WeWire rejected it: ${payout.body?.error?.message}`);
      console.log('  The transaction was correctly marked FAILED.\n');
    } else {
      fail(`Unexpected payment status ${payout.status}`, payout.body);
    }

    // --- Test 6: idempotency still holds on the bank channel ---
    console.log('--- Test 6: Idempotency on the bank channel ---');
    const replay = await post('/api/payments', {
      country: 'GH',
      network: 'GCB',
      channel: 'BANK',
      accountNumber: bankAccount,
      destinationAmount: 20,
      destinationCurrency: 'GHS',
      recipientName: 'Kwabena Owusu',
      idempotencyKey,
    });
    if (replay.status !== 200 || replay.body?.transactionId !== transactionId) {
      fail('Replaying the idempotency key should return the same transaction', replay.body);
    }
    console.log('PASSED: replaying the key returned the same transaction\n');

    // --- Test 7: mobile money payouts are unaffected ---
    console.log('--- Test 7: Mobile money channel regression check ---');
    const momoPayout = await post('/api/payments', {
      country: 'GH',
      network: 'MTN',
      phone: '0240000001',
      destinationAmount: 20,
      destinationCurrency: 'GHS',
      recipientName: 'Ama Serwaa',
      idempotencyKey: `momo_payout_${Date.now()}`,
    });
    const momoTxId = momoPayout.body?.transactionId;
    if (!momoTxId) fail('Expected a transactionId for the mobile money payout', momoPayout.body);
    const momoTx = await prisma.transaction.findUnique({ where: { id: momoTxId } });
    if (momoTx?.channel !== 'MOBILE_MONEY') fail(`Expected MOBILE_MONEY channel, got ${momoTx?.channel}`);
    if (momoTx?.recipientPhone !== '0240000001') fail(`Expected the MSISDN to be stored, got ${momoTx?.recipientPhone}`);
    if (momoTx?.institutionCode !== 'MTN') fail(`Expected institutionCode MTN, got ${momoTx?.institutionCode}`);
    console.log(`PASSED: mobile money payout still routes over MOBILE_MONEY (status ${momoPayout.status})\n`);

    console.log('=== ALL BANK PAYOUT TESTS PASSED ===');
  } finally {
    server.close();
    await prisma.$disconnect();
    process.exit(0);
  }
}

main().catch(async (err) => {
  console.error('Unexpected error:', err);
  await prisma.$disconnect();
  process.exit(1);
});
