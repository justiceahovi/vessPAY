/**
 * Checks that a deposit credits what actually settled rather than what the user
 * asked to send. The rails take a fee on the way in, so the two differ.
 *
 * Run: npm run test:settled-amount
 */
import { parseSettlement, parseSettledAmount } from '../src/routes/webhooks';

let failures = 0;

function check(name: string, actual: number, expected: number) {
  const ok = Math.abs(actual - expected) < 0.0001;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name} -> ${actual} (expected ${expected})`);
  if (!ok) failures++;
}

// The real payload WeWire delivered for the 250.00 GBP sandbox deposit.
const realPayIn = {
  fee: '0.55',
  amount: '250',
  status: 'SUCCESSFUL',
  currency: 'GBP',
  balanceAfter: '249.45',
  balanceBefore: '0',
  channel: 'SUBCUSTOMER_FIAT_DEPOSIT',
};

check('real WeWire pay_in credits the net', parseSettledAmount(realPayIn, 250), 249.45);

check(
  'balance delta wins over gross amount',
  parseSettledAmount({ amount: '100', balanceBefore: '10', balanceAfter: '109.5' }, 100),
  99.5
);

check(
  'falls back to gross minus fee without balances',
  parseSettledAmount({ amount: '100', fee: '1.25' }, 100),
  98.75
);

check(
  'a zero fee credits the full amount',
  parseSettledAmount({ amount: '75', fee: '0' }, 75),
  75
);

check(
  'numeric fields work as well as strings',
  parseSettledAmount({ amount: 40, fee: 0.4 }, 40),
  39.6
);

check(
  'an empty payload falls back to the requested amount',
  parseSettledAmount({}, 500),
  500
);

check(
  'a nonsensical balance delta is ignored',
  parseSettledAmount({ amount: '100', fee: '2', balanceBefore: '50', balanceAfter: '50' }, 100),
  98
);

// The fee has to be recorded too, so a user can be told why 250 became 249.45.
function checkFee(name: string, actual: number, expected: number) {
  const ok = Math.abs(actual - expected) < 0.0001;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name} -> ${actual} (expected ${expected})`);
  if (!ok) failures++;
}

checkFee('real pay_in records the 0.55 fee', parseSettlement(realPayIn, 250).fee, 0.55);

checkFee(
  'fee is derived from the balance delta when both are present',
  parseSettlement({ amount: '100', fee: '0', balanceBefore: '0', balanceAfter: '98' }, 100).fee,
  2
);

checkFee('no fee reported means no fee recorded', parseSettlement({ amount: '75' }, 75).fee, 0);

console.log(
  failures === 0 ? '\nAll settled-amount checks passed.' : `\n${failures} check(s) failed.`
);
process.exit(failures === 0 ? 0 : 1);
