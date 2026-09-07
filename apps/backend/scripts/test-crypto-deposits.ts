/**
 * Crypto deposit support: reference data, address issuance, and the webhook
 * attribution rules.
 *
 * The webhook cases matter most. A crypto deposit arrives unannounced, so the
 * old "match this user's newest PENDING deposit" fallback would have settled an
 * unrelated fiat top-up with it.
 */
import { parseCryptoDeposit } from '../src/routes/webhooks';
import {
  getSupportedCryptoAssets,
  getSupportedCryptoChains,
  isSupportedChain,
  resolveCryptoDepositAddress,
} from '../src/lib/crypto-assets';

const SUB_CUSTOMER = 'f3dadcef-8b9c-49f8-aa76-9037d5772c3c';

let failures = 0;
function check(label: string, condition: boolean, detail = '') {
  console.log(`  ${condition ? 'OK  ' : 'FAIL'} ${label}${detail ? ` -- ${detail}` : ''}`);
  if (!condition) failures++;
}

async function main() {
  console.log('--- supported assets (live) ---');
  const assets = await getSupportedCryptoAssets();
  assets.forEach((a) => console.log(`  ${a.asset.padEnd(6)} ${a.chain.padEnd(8)} ${a.network.padEnd(8)} ${a.label}`));
  check('at least one asset is served', assets.length > 0);
  check('USDT is not offered while the provider does not list it',
    !assets.some((a) => a.asset === 'USDT'));

  console.log('--- chains (one address serves every asset on it) ---');
  const chains = await getSupportedCryptoChains();
  chains.forEach((c) => console.log(`  ${c.chain.padEnd(8)} ${c.network.padEnd(8)} ${c.displayName.padEnd(10)} assets=${c.assets.join(',')}`));
  const base = chains.find((c) => c.chain === 'BASE');
  check('BASE carries more than one asset', !!base && base.assets.length > 1,
    base ? base.assets.join(',') : 'no BASE chain');
  check('an unknown chain is rejected', !(await isSupportedChain('DOGECOIN')));

  console.log('--- address issuance (live, idempotent) ---');
  const first = await resolveCryptoDepositAddress(SUB_CUSTOMER, 'BASE');
  const second = await resolveCryptoDepositAddress(SUB_CUSTOMER, 'BASE');
  console.log(`  ${first?.chain} ${first?.network} ${first?.status} ${first?.address ?? '(provisioning)'}`);
  check('an address is returned', !!first);
  check('repeat calls return the same address', first?.id === second?.id,
    `${first?.id} vs ${second?.id}`);
  check('network is read from the provider, never assumed',
    first?.network === 'TESTNET' || first?.network === 'MAINNET', first?.network);

  try {
    await resolveCryptoDepositAddress(SUB_CUSTOMER, 'DOGECOIN');
    check('an unsupported chain throws rather than returning empty', false);
  } catch (e: any) {
    check('an unsupported chain throws rather than returning empty', true, e.message.slice(0, 60));
  }

  console.log('--- webhook payload recognition ---');
  const crypto = parseCryptoDeposit({
    txHash: '0xabc123', asset: 'USDC', chain: 'BASE', amount: '10.123456',
    address: '0x14030e34D166D37203D561A6ECea0c8C609b7909',
  });
  check('a crypto deposit is recognised', crypto !== null);
  check('the exact token amount survives as a string', crypto?.amount === '10.123456', crypto?.amount);

  const alt = parseCryptoDeposit({
    transactionHash: '0xdef456', token: 'GHST', amount: '5', toAddress: '0xabc',
  });
  check('alternate field spellings are accepted', alt?.asset === 'GHST' && alt?.txHash === '0xdef456');

  check('a fiat payload is not mistaken for crypto',
    parseCryptoDeposit({ amount: '250', currency: 'GBP', balanceBefore: '0', balanceAfter: '249.45' }) === null);
  check('a hash without an asset is not credited',
    parseCryptoDeposit({ txHash: '0xaaa', amount: '1' }) === null);
  check('an asset without a hash is not credited (nothing to dedupe on)',
    parseCryptoDeposit({ asset: 'USDC', amount: '1' }) === null);

  console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
