/**
 * Verifies the wallet-currency choice end to end against a running backend:
 *  1. GET  /api/wallet/currencies lists the supported catalog
 *  2. POST /api/auth/register without a currency leaves the choice unmade
 *  3. PUT  /api/wallet/currency stores it and repoints the empty starter wallet
 *  4. GET  /api/auth/me returns the stored choice (it survives a fresh sign-in)
 *  5. POST /api/auth/register with a currency opens the wallet in it directly
 *
 * Usage: npm run test:wallet-currency   (backend must be running)
 */
const BASE_URL = process.env.API_BASE_URL || 'http://localhost:3000';

let failures = 0;

function check(label: string, passed: boolean, detail?: unknown): void {
  if (passed) {
    console.log(`  PASS  ${label}`);
  } else {
    failures++;
    console.error(`  FAIL  ${label}`, detail ?? '');
  }
}

async function api(
  path: string,
  init: RequestInit & { token?: string } = {}
): Promise<{ status: number; body: any }> {
  const { token, ...rest } = init;
  const res = await fetch(`${BASE_URL}${path}`, {
    ...rest,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(rest.headers || {}),
    },
  });
  let body: any = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
}

function newEmail(tag: string): string {
  return `currency_${tag}_${Date.now()}@vesspay.test`;
}

async function register(email: string, primaryCurrency?: string) {
  return api('/api/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      firstName: 'Currency',
      lastName: 'Tester',
      email,
      password: 'password123',
      country: 'United Kingdom',
      nationality: 'British',
      ...(primaryCurrency ? { primaryCurrency } : {}),
    }),
  });
}

async function main(): Promise<void> {
  console.log(`Wallet currency checks against ${BASE_URL}\n`);

  // 1. Catalog
  const catalog = await api('/api/wallet/currencies');
  check('GET /api/wallet/currencies returns 200', catalog.status === 200, catalog.body);
  const codes: string[] = (catalog.body?.currencies || []).map((c: any) => c.code);
  check('catalog offers USD, GBP and EUR',
    ['USD', 'GBP', 'EUR'].every((c) => codes.includes(c)), codes);

  // 2. Register without a choice
  const email = newEmail('unset');
  const registered = await register(email);
  check('register succeeds', registered.status === 201, registered.body);
  if (registered.status !== 201) {
    console.error('\nCannot continue without a registered user.');
    process.exit(1);
  }
  const token: string = registered.body.token;
  check('a user who did not choose has primaryCurrency null',
    registered.body.user.primaryCurrency === null, registered.body.user);

  const starterBalances = await api('/api/wallet/balances', { token });
  check('starter wallet defaults to USD with a zero balance',
    starterBalances.body?.length === 1 &&
    starterBalances.body[0].currency === 'USD' &&
    Number(starterBalances.body[0].balance) === 0,
    starterBalances.body);

  // 3. Choose GBP
  const chosen = await api('/api/wallet/currency', {
    method: 'PUT',
    token,
    body: JSON.stringify({ currency: 'gbp' }),
  });
  check('PUT /api/wallet/currency accepts and normalizes the choice',
    chosen.status === 200 && chosen.body?.primaryCurrency === 'GBP', chosen.body);
  check('the wallet is now held in GBP',
    chosen.body?.wallet?.currency === 'GBP', chosen.body?.wallet);

  const afterChoice = await api('/api/wallet/balances', { token });
  check('the empty starter wallet was repointed, not duplicated',
    afterChoice.body?.length === 1 && afterChoice.body[0].currency === 'GBP',
    afterChoice.body);

  const wallet = await api('/api/wallet', { token });
  check('GET /api/wallet defaults to the chosen currency',
    wallet.body?.currency === 'GBP', wallet.body);

  // 4. The choice persists for the account, not just the device
  const me = await api('/api/auth/me', { token });
  check('GET /api/auth/me reports the stored currency',
    me.body?.user?.primaryCurrency === 'GBP', me.body?.user);

  const signedInAgain = await api('/api/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password: 'password123' }),
  });
  check('signing in again returns the stored currency',
    signedInAgain.body?.user?.primaryCurrency === 'GBP', signedInAgain.body?.user);

  const rejected = await api('/api/wallet/currency', {
    method: 'PUT',
    token,
    body: JSON.stringify({ currency: 'XYZ' }),
  });
  check('an unsupported currency is rejected',
    rejected.status === 400 && rejected.body?.error?.code === 'UNSUPPORTED_CURRENCY',
    rejected.body);

  // 5. Choosing during registration
  const eurEmail = newEmail('eur');
  const eurUser = await register(eurEmail, 'EUR');
  check('register accepts a currency chosen up front',
    eurUser.status === 201 && eurUser.body?.user?.primaryCurrency === 'EUR',
    eurUser.body?.user);

  const eurBalances = await api('/api/wallet/balances', { token: eurUser.body?.token });
  check('the wallet opens directly in the chosen currency',
    eurBalances.body?.length === 1 && eurBalances.body[0].currency === 'EUR',
    eurBalances.body);

  const badRegister = await register(newEmail('bad'), 'XYZ');
  check('register rejects an unsupported currency',
    badRegister.status === 400 &&
    badRegister.body?.error?.code === 'UNSUPPORTED_CURRENCY',
    badRegister.body);

  console.log(failures === 0 ? '\nAll wallet currency checks passed.' : `\n${failures} check(s) failed.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('Wallet currency checks crashed:', err);
  process.exit(1);
});
