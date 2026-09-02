# VessPay — Engineering Blueprint

**This is the single source of truth for any AI agent working on VessPay.**
Read this document in full before starting any task in `VESSPAY_AGENT_PROMPTS.md`. If a prompt and this blueprint ever disagree, this blueprint wins — flag the conflict instead of silently picking one.

Companion files:
- `VESSPAY_AGENT_PROMPTS.md` — atomic, ordered build tasks
- `VESSPAY_PROGRESS.md` — checklist to update after every task

---

## 1. Product Summary

**One-liner:** Pay in Africa without a local SIM.

**Hackathon MVP corridor:** `USD → GHS → Ghana Mobile Money`

**Core story:** A foreign visitor lands in Ghana with no Ghanaian SIM and no Mobile Money account. They fund a VessPay wallet in USD, enter any Ghanaian MoMo number, and VessPay converts and pays it out — no local SIM, no local MoMo registration required.

**Hero feature:** "Pay Anyone" — country → payment type → network → recipient → amount → quote → confirm → payout.

**Explicitly out of scope for this hackathon** (do not build, do not suggest building):
Full KYC platform, AI assistant, lending, savings, crypto, insurance, loyalty system, complex referrals, merchant portal, full accounting system, physical cards, full African country coverage beyond Ghana, complex support ticketing, QR/merchant payments (unless WeWire's sandbox trivially exposes it), multi-currency funding beyond USD.

If a task seems to require any of the above, stop and flag it rather than building a workaround.

---

## 2. Repository Structure

```
vesspay/
├── apps/
│   ├── mobile/          # Flutter app
│   └── backend/         # Node.js + TypeScript API
├── VESSPAY_BLUEPRINT.md
├── VESSPAY_AGENT_PROMPTS.md
└── VESSPAY_PROGRESS.md
```

If the actual repo is split into two separate repos instead of a monorepo, that's fine — just keep this blueprint and the two companion files accessible to whichever repo the agent is working in, and note the actual layout in `VESSPAY_PROGRESS.md` under Phase 0.

---

## 3. Tech Stack (decided — do not swap without flagging why)

| Layer | Choice | Notes |
|---|---|---|
| Mobile | Flutter / Dart | Riverpod (state), Dio (HTTP client), GoRouter (navigation), flutter_secure_storage (tokens) |
| Backend | Node.js + TypeScript, **Express** | Chosen over NestJS/Fastify for hackathon simplicity — don't introduce a heavier framework mid-build |
| Database | PostgreSQL via Supabase | Use Supabase's connection string + client library, or plain `pg`/Prisma — pick one ORM in Phase 1 and stick to it |
| Hosting | Backend: Railway or Render. DB: Supabase. Landing: Vercel (already live at vesspay.vercel.app) | |

---

## 4. Backend Architecture

```
                  Flutter App
                       |
                       v
                VessPay Backend
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
    Database      WeWire API     Notification
   (Postgres)     (sandbox)        (in-app)
                       |
                       v
                 Payment Rails
```

**Rule:** Flutter never calls WeWire directly and never holds a WeWire credential. Every WeWire call is proxied through the VessPay backend.

Backend owns: authentication, user records, wallet records, transaction records, rate retrieval, payment calculation, beneficiary handling, all WeWire requests, idempotency, webhook handling, transaction state, audit trail.

---

## 5. Environment Variables

| Name | Purpose |
|---|---|
| `WEWIRE_API_KEY` | Sandbox `ww-api-key` header value |
| `WEWIRE_BASE_URL` | `https://stage-capi.wewireafrica.com` (confirm exact host against current docs — it may differ) |
| `WEWIRE_WEBHOOK_SECRET` | Used to verify inbound webhook signatures |
| `DATABASE_URL` | Supabase Postgres connection string |
| `JWT_SECRET` | Backend auth token signing |
| `JWT_EXPIRES_IN` | e.g. `7d` |
| `PORT` | Backend port |
| `NODE_ENV` | `development` / `production` |

Never commit real values. Ship a `.env.example` with these keys and blank/placeholder values.

**Important:** the WeWire base URL, header names, and exact endpoint paths in this blueprint are drawn from the product plan and public docs research — they have **not** been verified against the live sandbox. Before wiring any real WeWire call (Phase 3 and Phase 5 tasks), the agent must fetch the current spec at `https://docs.wewire.com/api-reference` (and adjacent pages) and correct field/endpoint names as needed. Do not hallucinate a field name that isn't confirmed.

---

## 6. Database Schema

```sql
-- users
id                      uuid primary key
first_name              text
last_name               text
email                   text unique
password_hash           text
country                 text        -- country of residence
nationality             text
wewire_subcustomer_id   text
created_at              timestamptz
updated_at              timestamptz

-- travel_profiles
id                      uuid primary key
user_id                 uuid references users(id)
destination_country     text        -- e.g. 'GH'
destination_currency    text        -- e.g. 'GHS'
is_active               boolean
created_at              timestamptz
updated_at              timestamptz

-- wallets
id                      uuid primary key
user_id                 uuid references users(id)
currency                text        -- e.g. 'USD'
balance                 numeric(14,2)
wewire_wallet_id        text
created_at              timestamptz
updated_at              timestamptz

-- beneficiaries
id                      uuid primary key
user_id                 uuid references users(id)
name                    text
country                 text
network                 text        -- MTN | Telecel | AirtelTigo
phone                   text
wewire_beneficiary_id   text
wewire_account_id       text
created_at              timestamptz
updated_at              timestamptz

-- transactions
id                        uuid primary key
user_id                   uuid references users(id)
type                      text        -- 'payout' | 'topup'
status                    text        -- see Section 9
source_currency           text
source_amount             numeric(14,2)
destination_currency      text
destination_amount        numeric(14,2)
fee                       numeric(14,2)
exchange_rate             numeric(14,6)
recipient_name            text
recipient_phone           text
network                   text
country                   text
wewire_transaction_id     text
idempotency_key           text unique
created_at                timestamptz
updated_at                timestamptz

-- funding_transactions
id                      uuid primary key
user_id                 uuid references users(id)
amount                  numeric(14,2)
currency                text
checkout_id             text
status                  text
created_at              timestamptz
updated_at              timestamptz

-- webhook_events
id                      uuid primary key
provider                text        -- 'wewire'
event_type              text
event_id                text unique  -- for idempotency
payload                 jsonb
processed               boolean
created_at              timestamptz
```

---

## 7. VessPay API Contract

Standard error shape for all endpoints:
```json
{ "error": { "code": "STRING_CODE", "message": "human readable" } }
```

**Auth**
```
POST /api/auth/register   { firstName, lastName, email, password, country, nationality } -> { user, token }
POST /api/auth/login      { email, password } -> { user, token }
GET  /api/auth/me         (auth required) -> { user }
```

**Travel**
```
GET  /api/travel/destinations       -> [{ country, currency }]   -- Ghana only for MVP, shaped for more
GET  /api/travel/current            -> { destinationCountry, destinationCurrency, isActive }
PUT  /api/travel/current            { destinationCountry } -> updated profile
```

**Wallet**
```
GET  /api/wallet                    -> { id, currency, balance }
GET  /api/wallet/balances           -> [{ currency, balance }]
POST /api/wallet/topup              { amount, currency } -> { checkoutUrl | checkoutId, fundingTransactionId }
```

**Rates**
```
GET /api/rates?from=USD&to=GHS      -> { from, to, rate, asOf }
```

**Beneficiaries**
```
GET    /api/beneficiaries           -> [{ id, name, network, phone }]
POST   /api/beneficiaries           { name, network, phone, country } -> beneficiary
GET    /api/beneficiaries/:id       -> beneficiary
DELETE /api/beneficiaries/:id       -> 204
```

**Payments**
```
POST /api/payments/quote
  body: { country, network, phone, destinationAmount, destinationCurrency }
  res:  { sourceCurrency, sourceAmount, destinationCurrency, destinationAmount, exchangeRate, fee, total }

POST /api/payments
  body: { country, network, phone, destinationAmount, destinationCurrency, idempotencyKey, beneficiaryId? }
  res:  { transactionId, status }

GET  /api/payments                  -> [transaction]
GET  /api/payments/:id              -> transaction
```

**Webhook**
```
POST /api/webhooks/wewire           -- verify signature, store event, update ledger, idempotent
```

The quote endpoint is intentionally separate from the payment-creation endpoint — the frontend always shows a quote before the user confirms, and the backend recalculates the quote server-side at confirmation time rather than trusting whatever the client last displayed.

---

## 8. WeWire Integration Map

| VessPay concept | WeWire concept | Stored reference |
|---|---|---|
| VessPay user | Sub-customer | `wewire_subcustomer_id` |
| VessPay wallet | Wallet | `wewire_wallet_id` |
| Add Money | Checkout / virtual account funding | via webhook |
| USD→GHS conversion | Rates endpoint | not stored, fetched live |
| Saved recipient | Beneficiary + beneficiary account | `wewire_beneficiary_id`, `wewire_account_id` |
| Payment | Disbursement/payout → transaction | `wewire_transaction_id` |

Flow for a payment: create/reuse beneficiary → get quote (rates) → create payout with idempotency key → poll or wait on webhook → update transaction status → notify user.

---

## 9. Transaction Status Lifecycle

```
CREATED → PENDING → PROCESSING → COMPLETED
                  ↘ FAILED
```
Additional terminal/edge states: `CANCELLED`, `EXPIRED`, `REVERSED`.

**Rule:** never mark a transaction `COMPLETED` just because WeWire accepted the payout request. Wait for the definitive status via webhook (or an explicit status-check call) before showing success to the user.

---

## 10. Security Rules (non-negotiable)

1. WeWire secret key lives only on the backend — never shipped to Flutter, never logged in full.
2. Every payout carries a unique idempotency key (`VP-PAY-<uuid>`) — a duplicate tap or retried request must not create a duplicate payout.
3. Amount, fee, and exchange rate are always recalculated server-side at confirmation time — never trust a quote value sent back from the client.
4. Webhook handler verifies the signature and is idempotent — reprocessing the same `event_id` must not double-credit a wallet or duplicate a transaction.
5. Passwords are hashed (bcrypt or equivalent) — never stored or logged in plaintext.

---

## 11. UX Principles

1. **Hide complexity** — the user sees "Pay Kwame," never "create beneficiary account" or any WeWire terminology.
2. **Always show both currencies** — "You pay $10.90 / Recipient gets GH₵150," never just one side.
3. **Confirm before money moves** — full breakdown shown before the "Confirm Payment" tap.
4. **Unambiguous status** — use Pending / Processing / Completed / Failed. Avoid vague copy like "Request sent."

---

## 12. Screen Inventory (Flutter)

Splash → Onboarding (3 slides) → Sign Up / Login → Travel Mode setup (destination picker) → Home Dashboard → Wallet → Add Money → Pay Anyone (country → type → network → recipient → amount) → Payment Review → Payment Processing → Payment Success/Failure → Transactions (list + detail) → Saved Recipients → Profile & Settings.

---

## 13. Definition of Done (hackathon MVP)

The MVP is done when this entire journey works, live, against the WeWire sandbox:

```
Sign up → choose Ghana → see wallet → fund wallet → balance updates →
Pay Anyone → Ghana → Mobile Money → network → MoMo number → amount →
quote shown → confirm → WeWire payout created → webhook received →
transaction becomes Completed → success screen → appears in transaction history
```

---

## 14. Demo Script (for final QA and the live pitch)

Alex Johnson (UK, visiting Accra, $500 wallet) needs to pay a taxi driver GH₵150 to MTN MoMo `024 123 4567`. He has no Ghana SIM, no MoMo wallet, no cash. Demo: open VessPay → Ghana Travel Mode active → wallet shows $500 → Pay Anyone → Ghana → MTN → enter number → GH₵150 → review shows ~$10.90 total → confirm → success → transaction shows Completed in history. This is the centerpiece of the presentation — every Phase 6 polish task should serve making this specific sequence smooth and fast.
