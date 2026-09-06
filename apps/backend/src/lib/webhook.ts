import crypto from 'crypto';

export interface VerifySignatureOptions {
  secret: string;
  headers: Record<string, string | string[] | undefined>;
  rawBody: Buffer | string;
  toleranceSeconds?: number;
}

/**
 * Generates a valid WeWire / Standard Webhook signature header string.
 * Used for testing and signature validation.
 */
export function generateWeWireSignature(params: {
  secret: string;
  webhookId: string;
  timestamp: number;
  rawBody: Buffer | string;
}): string {
  const rawBodyString = Buffer.isBuffer(params.rawBody)
    ? params.rawBody.toString('utf8')
    : params.rawBody;

  const signedContent = `${params.webhookId}.${params.timestamp}.${rawBodyString}`;

  const secretKeyPart = params.secret.includes('_')
    ? params.secret.split('_')[1]
    : params.secret;
  const key = Buffer.from(secretKeyPart, 'base64');

  const signature = crypto
    .createHmac('sha256', key)
    .update(signedContent)
    .digest('base64');

  return `v1,${signature}`;
}

/**
 * Verifies a WeWire webhook signature following the Standard Webhooks specification.
 * 
 * Header requirements:
 *   - webhook-id: unique event delivery ID
 *   - webhook-timestamp: unix timestamp in seconds
 *   - webhook-signature: space-separated 'v1,<base64>' signatures
 */
export function verifyWeWireSignature({
  secret,
  headers,
  rawBody,
  toleranceSeconds = 300,
}: VerifySignatureOptions): boolean {
  try {
    const id = headers['webhook-id'] || headers['Webhook-Id'];
    const timestamp = headers['webhook-timestamp'] || headers['Webhook-Timestamp'];
    const signatures = headers['webhook-signature'] || headers['Webhook-Signature'];

    if (!id || !timestamp || !signatures) {
      return false;
    }

    const idStr = Array.isArray(id) ? id[0] : id;
    const tsStr = Array.isArray(timestamp) ? timestamp[0] : timestamp;
    const sigStr = Array.isArray(signatures) ? signatures[0] : signatures;

    // Tolerance check to protect against replay attacks
    const now = Math.floor(Date.now() / 1000);
    const tsNum = Number(tsStr);
    if (isNaN(tsNum) || Math.abs(now - tsNum) > toleranceSeconds) {
      return false;
    }

    const rawBodyString = Buffer.isBuffer(rawBody)
      ? rawBody.toString('utf8')
      : typeof rawBody === 'string'
      ? rawBody
      : JSON.stringify(rawBody);

    const signedContent = `${idStr}.${tsNum}.${rawBodyString}`;

    const secretKeyPart = secret.includes('_') ? secret.split('_')[1] : secret;
    const key = Buffer.from(secretKeyPart, 'base64');

    const expected = crypto
      .createHmac('sha256', key)
      .update(signedContent)
      .digest('base64');

    const signatureEntries = sigStr.split(' ');
    return signatureEntries.some((entry) => {
      const candidateStr = entry.includes(',') ? entry.split(',')[1] : entry;
      const candidate = Buffer.from(candidateStr, 'utf8');
      const reference = Buffer.from(expected, 'utf8');
      return (
        candidate.length === reference.length &&
        crypto.timingSafeEqual(candidate, reference)
      );
    });
  } catch (err) {
    console.error('Error verifying WeWire signature:', err);
    return false;
  }
}
