import { getExchangeRate } from '../src/lib/wewire';

const pairs: [string, string][] = [
  ['USD', 'GHS'], ['GBP', 'GHS'], ['EUR', 'GHS'],   // Ghana: all published direct
  ['USD', 'NGN'],                                    // Nigeria: published direct
  ['GBP', 'NGN'], ['EUR', 'NGN'],                    // Nigeria: only reachable by cross
  ['GHS', 'NGN'],                                    // published direct
  ['USD', 'GBP'], ['GBP', 'USD'],                    // one published, one inverse
  ['USD', 'XAF'],                                    // genuinely unavailable
];

async function main() {
  for (const [from, to] of pairs) {
    const r = await getExchangeRate(from, to);
    if (!r) { console.log(`  ${from}->${to}`.padEnd(14), 'unavailable'); continue; }
    console.log(`  ${from}->${to}`.padEnd(14), String(r.rate).padStart(12), (r.via || '').padEnd(9), r.asOf.slice(0, 10));
  }

  // Sanity: a cross must stay anchored to the USD leg it is built from.
  const usdNgn = await getExchangeRate('USD', 'NGN');
  const gbpNgn = await getExchangeRate('GBP', 'NGN');
  const usdGbp = await getExchangeRate('USD', 'GBP');
  if (usdNgn && gbpNgn && usdGbp) {
    const implied = gbpNgn.rate * usdGbp.rate;
    console.log(`\n  GBP/NGN x USD/GBP = ${implied.toFixed(2)} vs published USD/NGN ${usdNgn.rate}`);
    console.log(`  consistent: ${Math.abs(implied - usdNgn.rate) < 0.01}`);
  }
}
main();
