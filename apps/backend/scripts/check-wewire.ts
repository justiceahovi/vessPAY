import dotenv from 'dotenv';
dotenv.config();

async function checkWeWire() {
  const apiKey = process.env.WEWIRE_API_KEY;
  const baseUrl = process.env.WEWIRE_BASE_URL || 'https://stage-capi.wewireafrica.com';

  console.log('Checking WeWire sandbox connectivity...');
  console.log(`Base URL: ${baseUrl}`);
  console.log(`API Key set: ${Boolean(apiKey)} (${apiKey ? apiKey.slice(0, 12) + '...' : 'NONE'})`);

  if (!apiKey) {
    console.error('ERROR: WEWIRE_API_KEY is not set in apps/backend/.env');
    process.exit(1);
  }

  const url = `${baseUrl.replace(/\/$/, '')}/v1/subcustomers`;
  console.log(`Sending GET ${url}...`);

  try {
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'ww-api-key': apiKey,
        'Content-Type': 'application/json',
      },
    });

    console.log(`Response Status: ${res.status} ${res.statusText}`);
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
    console.log('Response Body:', JSON.stringify(data, null, 2));

    if (res.status === 401 || res.status === 403) {
      console.error('AUTHENTICATION FAILED: Sandbox rejected API key.');
      process.exit(1);
    }

    if (res.ok) {
      console.log('SUCCESS: WeWire sandbox connectivity and auth header confirmed working!');
    } else {
      console.log(`Received non-auth response status ${res.status}`);
    }
  } catch (err) {
    console.error('Network / fetch error:', err);
    process.exit(1);
  }
}

checkWeWire();