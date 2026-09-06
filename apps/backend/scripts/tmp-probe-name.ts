import dotenv from 'dotenv';
dotenv.config();
const apiKey = process.env.WEWIRE_API_KEY!;
const baseUrl = (process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com').replace(/\/$/, '');
async function call(method: string, path: string, body?: any) {
  try {
    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'ww-api-key': apiKey, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let data: any;
    try { data = JSON.parse(text); } catch { data = text; }
    const preview = typeof data === 'string' ? data.slice(0, 120).replace(/\s+/g, ' ') : JSON.stringify(data).slice(0, 400);
    console.log(`${method} ${path} -> ${res.status} ${preview}`);
  } catch (e: any) {
    console.log(`${method} ${path} -> ERROR ${e.message}`);
  }
}
async function main() {
  const paths = [
    '/v1/name-enquiry', '/v1/name-enquiries', '/v1/accounts/resolve', '/v1/account-lookup',
    '/v1/account-enquiry', '/v1/accounts/verify', '/v1/validate-account', '/v1/account-validation',
    '/v1/beneficiaries/validate', '/v1/beneficiaries/resolve', '/v1/lookup', '/v1/verify',
    '/v1/disbursements/validate', '/v1/banks/resolve', '/v1/account-name',
  ];
  for (const p of paths) {
    await call('GET', p);
    await call('POST', p, { accountNumber: '0240000001', accountCode: 'MTN', channel: 'MOBILE_MONEY', currency: 'GHS', bankCode: 'MTN' });
  }
}
main();
