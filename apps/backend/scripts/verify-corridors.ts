import { resolveInstitution, normalizePhone, normalizeBankAccountNumber, getCorridor, processorFeeFor, lookupAccountName } from '../src/lib/wewire';

async function main() {
  console.log('--- institution resolution ---');
  const cases: [string, string][] = [
    ['MTN', 'GHS'], ['GCB', 'GHS'], ['Ecobank', 'GHS'], ['Telecel', 'GHS'],
    ['000013', 'NGN'], ['100004', 'NGN'], ['GTBANK PLC', 'NGN'], ['KUDA', 'NGN'],
  ];
  for (const [input, cur] of cases) {
    try {
      const i = await resolveInstitution(input, cur);
      console.log(`  OK   ${cur} "${input}" -> ${i.code} / ${i.name} / ${i.channel}`);
    } catch (e: any) { console.log(`  FAIL ${cur} "${input}": ${e.message}`); }
  }

  console.log('--- ambiguity is now rejected, not guessed ---');
  for (const [input, cur] of [['ACCESS', 'NGN'], ['Bank', 'NGN']] as [string, string][]) {
    try { const i = await resolveInstitution(input, cur); console.log(`  picked ${i.code} ${i.name}`); }
    catch (e: any) { console.log(`  rejected "${input}": ${e.message.slice(0, 110)}...`); }
  }

  console.log('--- phone normalization ---');
  for (const [p, c] of [['0241234567','GHS'], ['233241234567','GHS'], ['241234567','GHS'], ['08031234567','NGN']] as [string,string][]) {
    const r = normalizePhone(p, c);
    console.log(`  ${c} ${p} -> ${r.msisdn} / ${r.international} valid=${r.isValid}`);
  }

  console.log('--- account number rules ---');
  for (const [n, c] of [['1029384756123','GHS'], ['8012345678','NGN'], ['80123456','NGN'], ['801234567890','NGN']] as [string,string][]) {
    console.log(`  ${c} ${n} -> ${normalizeBankAccountNumber(n, c)}`);
  }

  console.log('--- corridors ---');
  for (const c of ['GH', 'NG']) {
    const k = getCorridor(c);
    console.log(`  ${k.country} ${k.currency} ${k.symbol} channels=${k.channels.join('|')} fee=${processorFeeFor(k.currency)} confirmed=${k.feeConfirmed}`);
  }

  console.log('--- live NGN account lookup ---');
  const l = await lookupAccountName({ accountCode: '100004', accountNumber: '8012345678', currency: 'NGN' });
  console.log('  OPay 8012345678 ->', l ? l.accountName : 'not confirmed');
}
main();

// Guard checks: each of these must throw *before* any WeWire write is attempted.
import { sendWeWireDisbursement, createWeWireBeneficiary } from '../src/lib/wewire';

async function guards() {
  console.log('--- guards (must throw before any network write) ---');

  try {
    await sendWeWireDisbursement({
      idempotencyKey: 'VP-GUARD-TEST', amount: 1000, currency: 'NGN',
      network: '000013', channel: 'MOBILE_MONEY', phone: '08031234567',
      recipientName: 'Guard Test',
    });
    console.log('  FAIL: NGN mobile money disbursement was allowed');
  } catch (e: any) { console.log(`  OK  NGN+MOBILE_MONEY rejected: ${e.message}`); }

  try {
    await createWeWireBeneficiary({
      name: 'Guard Test', network: '000013', channel: 'BANK',
      accountNumber: '80123456', country: 'NG', currency: 'NGN',
    });
    console.log('  FAIL: 8-digit NUBAN was accepted');
  } catch (e: any) { console.log(`  OK  short NUBAN rejected: ${e.message}`); }

  try {
    await createWeWireBeneficiary({
      name: 'Guard Test', network: '000013', channel: 'MOBILE_MONEY',
      phone: '08031234567', country: 'NG', currency: 'NGN',
    });
    console.log('  FAIL: NGN mobile money beneficiary was allowed');
  } catch (e: any) { console.log(`  OK  NGN momo beneficiary rejected: ${e.message}`); }
}
guards();
