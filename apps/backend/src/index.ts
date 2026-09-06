import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { checkDatabaseConnection, prisma } from './lib/db';
import authRouter from './routes/auth';
import travelRouter from './routes/travel';
import walletRouter from './routes/wallet';
import kycRouter from './routes/kyc';
import webhooksRouter from './routes/webhooks';
import ratesRouter from './routes/rates';
import paymentsRouter from './routes/payments';
import beneficiariesRouter from './routes/beneficiaries';
import banksRouter from './routes/banks';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(
  express.json({
    verify: (req: any, _res, buf) => {
      req.rawBody = buf;
    },
  })
);

app.get('/api/health', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'ok' });
});

app.use('/api/auth', authRouter);
app.use('/api/travel', travelRouter);
app.use('/api/wallet', walletRouter);
app.use('/api/kyc', kycRouter);
app.use('/api/webhooks', webhooksRouter);
app.use('/api/rates', ratesRouter);
app.use('/api/payments', paymentsRouter);
app.use('/api/beneficiaries', beneficiariesRouter);
app.use('/api/banks', banksRouter);

// Sandbox Checkout Web View for Browser & Simulation Testing
app.get('/checkout/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  const rawAmount = req.query.amount ? String(req.query.amount) : null;
  const rawCurrency = req.query.currency ? String(req.query.currency) : 'USD';

  const fundingTx = await prisma.fundingTransaction.findFirst({
    where: {
      OR: [{ id }, { checkoutId: id }],
    },
    include: { user: true },
  });

  const amount = fundingTx ? Number(fundingTx.amount).toFixed(2) : (rawAmount ? Number(rawAmount).toFixed(2) : '100.00');
  const currency = fundingTx ? fundingTx.currency : rawCurrency;
  const userName = fundingTx?.user ? `${fundingTx.user.firstName} ${fundingTx.user.lastName}` : 'VessPay User';
  const isAlreadyCompleted = fundingTx?.status === 'COMPLETED';

  res.setHeader('Content-Type', 'text/html');
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>WeWire Sandbox Checkout</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      background: #0D1117;
      color: #F0F6FC;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 16px;
    }
    .card {
      background: #161B22;
      border: 1px solid #30363D;
      border-radius: 20px;
      width: 100%;
      max-width: 420px;
      padding: 28px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.4);
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(245, 130, 32, 0.15);
      color: #F58220;
      border: 1px solid rgba(245, 130, 32, 0.3);
      padding: 4px 10px;
      border-radius: 100px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 16px;
    }
    .badge-dot {
      width: 6px;
      height: 6px;
      background: #F58220;
      border-radius: 50%;
    }
    h1 { font-size: 20px; font-weight: 700; margin-bottom: 4px; color: #FFFFFF; }
    p.sub { font-size: 13px; color: #8B949E; margin-bottom: 24px; }
    .amount-box {
      background: #0D1117;
      border: 1px solid #21262D;
      border-radius: 14px;
      padding: 18px;
      text-align: center;
      margin-bottom: 20px;
    }
    .amount-box .label { font-size: 12px; color: #8B949E; margin-bottom: 4px; }
    .amount-box .val { font-size: 32px; font-weight: 700; color: #58A6FF; }
    .info-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin-bottom: 24px;
      font-size: 13px;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      color: #8B949E;
    }
    .info-row span:last-child { color: #C9D1D9; font-weight: 500; }
    button.pay-btn {
      width: 100%;
      background: #238636;
      color: #FFFFFF;
      border: none;
      padding: 14px;
      border-radius: 12px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.2s;
      display: flex;
      justify-content: center;
      align-items: center;
      gap: 8px;
    }
    button.pay-btn:hover { background: #2EA043; }
    button.pay-btn:disabled { background: #21262D; color: #484F58; cursor: not-allowed; }
    .success-box {
      display: none;
      text-align: center;
      padding: 20px 0;
    }
    .success-icon {
      width: 56px;
      height: 56px;
      background: rgba(35, 134, 54, 0.2);
      color: #3FB950;
      border-radius: 50%;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      margin-bottom: 14px;
    }
    .footer {
      margin-top: 20px;
      text-align: center;
      font-size: 11px;
      color: #484F58;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">
      <div class="badge-dot"></div>
      WeWire Sandbox
    </div>
    <div id="checkout-view">
      <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px;">
        <span style="font-size: 24px;">🇺🇸</span>
        <h1 style="font-size: 20px; font-weight: 700; margin: 0; color: #FFFFFF;">Fund USD account</h1>
      </div>
      <p class="sub" style="font-size: 12px; color: #8B949E; margin-bottom: 18px; line-height: 1.4;">
        Conversion rates are guaranteed for 24 hours. Newer rates may apply for transfers received after this duration.
      </p>

      <div style="background: #0D1117; border: 1px solid #30363D; border-radius: 12px; padding: 14px; margin-bottom: 16px;">
        <div style="font-size: 12px; font-weight: 600; color: #F0F6FC; margin-bottom: 10px;">Account details</div>
        <div class="info-list" style="margin-bottom: 0; gap: 8px;">
          <div class="info-row">
            <span>Account number</span>
            <span style="color: #58A6FF; font-family: monospace;">0100892209</span>
          </div>
          <div class="info-row">
            <span>Account name</span>
            <span>WeWire Technologies Inc.</span>
          </div>
          <div class="info-row">
            <span>Bank</span>
            <span>STANDARD CHARTERED BANK</span>
          </div>
          <div class="info-row">
            <span>Swift code</span>
            <span style="font-family: monospace;">SCBLSG22XXX</span>
          </div>
          <div class="info-row">
            <span>Reference (Mandatory)</span>
            <span style="color: #F58220; font-weight: 700; font-family: monospace;">WA08919</span>
          </div>
        </div>
      </div>

      <div style="background: rgba(245, 130, 32, 0.1); border: 1px solid rgba(245, 130, 32, 0.3); border-radius: 8px; padding: 10px; font-size: 11px; color: #F58220; margin-bottom: 18px; line-height: 1.4;">
        ⓘ You will need to input the mandatory reference number with your transaction. Funds will be automatically credited to your account once we receive your transaction.
      </div>

      <div class="amount-box">
        <div class="label">How much are you depositing?</div>
        <div class="val">$${amount} <span style="font-size: 16px; color: #8B949E;">${currency}</span></div>
      </div>

      <button id="pay-btn" class="pay-btn" style="background: #FF6B4A;" onclick="submitPayment()">
        I have made the deposit
      </button>
    </div>

    <div id="success-view" class="success-box" style="${isAlreadyCompleted ? 'display: block;' : ''}">
      <div class="success-icon">✓</div>
      <h2 style="font-size: 18px; margin-bottom: 6px; color: #3FB950;">Deposit Confirmed!</h2>
      <p style="font-size: 13px; color: #8B949E; margin-bottom: 16px;">
        $${amount} ${currency} has been credited to your VessPay wallet.
      </p>
      <p style="font-size: 12px; color: #58A6FF;">You can close this tab and return to the VessPay app.</p>
    </div>

    <div class="footer">
      Secured by WeWire Africa Sandbox Engine • End-to-End Simulation
    </div>
  </div>

  <script>
    if (${isAlreadyCompleted}) {
      document.getElementById('checkout-view').style.display = 'none';
    }

    async function submitPayment() {
      const btn = document.getElementById('pay-btn');
      btn.disabled = true;
      btn.innerText = 'Processing...';

      try {
        const res = await fetch('/checkout/${id}/pay', { method: 'POST' });
        const data = await res.json();
        if (data.status === 'COMPLETED' || res.ok) {
          document.getElementById('checkout-view').style.display = 'none';
          document.getElementById('success-view').style.display = 'block';
        } else {
          alert('Error: ' + (data.error?.message || 'Payment failed'));
          btn.disabled = false;
          btn.innerText = 'Confirm $${amount} Deposit';
        }
      } catch (err) {
        alert('Network error confirming payment: ' + err.message);
        btn.disabled = false;
        btn.innerText = 'Confirm $${amount} Deposit';
      }
    }
  </script>
</body>
</html>`);
});

app.post('/checkout/:id/pay', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const fundingTx = await prisma.fundingTransaction.findFirst({
      where: {
        OR: [{ id }, { checkoutId: id }],
      },
    });

    if (!fundingTx) {
      res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Funding transaction not found' } });
      return;
    }

    if (fundingTx.status === 'COMPLETED') {
      res.status(200).json({ status: 'COMPLETED', fundingTransactionId: fundingTx.id });
      return;
    }

    await prisma.$transaction(async (tx) => {
      await tx.fundingTransaction.update({
        where: { id: fundingTx.id },
        data: { status: 'COMPLETED' },
      });

      const existingWallet = await tx.wallet.findFirst({
        where: { userId: fundingTx.userId, currency: fundingTx.currency },
      });

      if (existingWallet) {
        await tx.wallet.update({
          where: { id: existingWallet.id },
          data: { balance: { increment: fundingTx.amount } },
        });
      } else {
        await tx.wallet.create({
          data: {
            userId: fundingTx.userId,
            currency: fundingTx.currency,
            balance: fundingTx.amount,
          },
        });
      }

      await tx.webhookEvent.create({
        data: {
          provider: 'wewire',
          eventType: 'transaction.pay_in',
          eventId: `sim_payin_${Date.now()}_${fundingTx.id.slice(0, 8)}`,
          payload: {
            data: {
              fundingTransactionId: fundingTx.id,
              checkoutId: fundingTx.checkoutId,
              amount: Number(fundingTx.amount),
              currency: fundingTx.currency,
              status: 'SUCCESSFUL',
            },
            eventType: 'transaction.pay_in',
          },
          processed: true,
        },
      });
    });

    res.status(200).json({ status: 'COMPLETED', fundingTransactionId: fundingTx.id });
  } catch (err: any) {
    console.error('Error processing checkout pay:', err);
    res.status(500).json({ error: { code: 'INTERNAL_SERVER_ERROR', message: err.message } });
  }
});

async function start() {
  console.log('Checking database connection...');
  await checkDatabaseConnection();
  console.log('Database connection: OK');

  app.listen(port, () => {
    console.log(`VessPay backend running on port ${port}`);
  });
}

if (process.env.NODE_ENV !== 'test') {
  start().catch((err) => {
    console.error('Failed to start server:', err);
    process.exit(1);
  });
}

export { prisma };
export default app;