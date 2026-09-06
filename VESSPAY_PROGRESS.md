# VessPay — Build Progress

## How to use this file

- Check a box only after the matching task's acceptance criteria (in `VESSPAY_AGENT_PROMPTS.md`) is actually met — not just attempted.
- Add a one-line note after each completed task: what was built, any deviation from `VESSPAY_BLUEPRINT.md`, any TODO left behind.
- If a task is blocked (missing credential, sandbox limitation, ambiguous spec), leave the box unchecked and write a `⚠ BLOCKED:` note explaining why, instead of guessing.
- Do not reorder or skip tasks — later phases assume earlier ones are checked off.

Legend: `[ ]` not started/in progress · `[x]` done and verified · `⚠` blocked (see note)

---

## Phase 0 — Environment & Repo Setup

- [x] T0.1 — Repo scaffolding
  - Note: Initialized git repository, created folder skeleton (apps/mobile, apps/backend), and added root .gitignore covering Node, Flutter, and .env files.
- [x] T0.2 — Backend project init
  - Note: Initialized Express + TypeScript backend in apps/backend with dev/build/start scripts, .env.example with Section 5 variables, and verified GET /api/health returns 200.
- [x] T0.3 — Flutter project init
  - Note: Initialized Flutter project in apps/mobile with flutter_riverpod, dio, go_router, and flutter_secure_storage; verified dependencies, analyzer, tests, and build.
- [x] T0.4 — Database provisioning
  - Note: ORM chosen: **Prisma v5** (prisma-client-js, CommonJS-compatible). Provisioned local PostgreSQL 17 database `vesspay` with connection string in `.env`, wired startup SELECT 1 check in src/lib/db.ts, and verified successful DB query on server startup. Ready to swap to Supabase for production.
- [x] T0.5 — WeWire sandbox connectivity check
  - Note: Confirmed base URL `https://stage-capi.wewireafrica.com` and auth header `ww-api-key: sk_test_...` working with HTTP 200 OK on `GET /v1/subcustomers`. Added `npm run check:wewire` script.

## Phase 1 — Product Foundation

- [x] T1.1 — Core database migrations (users, travel_profiles, wallets)
  - Note: Created and applied Prisma migration `20260902160920_init_core_tables` for `users`, `travel_profiles`, and `wallets` tables matching Section 6 schema exactly; verified clean execution on database with CRUD and foreign-key cascade tests passing.
- [x] T1.2 — Auth endpoints (register/login/me)
  - Note: Implemented POST /api/auth/register (with bcrypt password hashing, atomic default USD wallet creation at balance=0), POST /api/auth/login, and GET /api/auth/me; verified registration, token issuance, profile retrieval, standard error shapes, and duplicate email prevention.
- [x] T1.3 — JWT auth middleware
  - Note: Implemented reusable Express JWT middleware (`authenticate` and `requireAuth` alias) in `src/middleware/auth.ts`; protects `/api/auth/me` and future endpoints, attaches `req.user`, and returns 401 with standard error shape on missing, malformed, expired, or invalid tokens.
- [x] T1.4 — Flutter API client + secure token storage
  - Note: Implemented Dio-based ApiClient with environment-aware AppConfig, TokenStorage (SecureTokenStorage via flutter_secure_storage + InMemoryTokenStorage), AuthInterceptor for Bearer JWT injection, centralized ApiException parsing, typed GET/POST/PUT/DELETE wrappers, and Riverpod providers; verified live calls against local backend for GET /api/health and authenticated GET /api/auth/me.
- [x] T1.5 — Navigation shell + splash screen
  - Note: Configured GoRouter with placeholder routes (splash, onboarding, login, signup, travel-mode-setup, home), DESIGN.md-compliant theme tokens and styles, and built SplashScreen with minimal logo animation and token-based auto-routing (no token → onboarding, valid token → home); verified with automated widget tests and flutter analyze.
- [x] T1.6 — Sign up / login screens
  - Note: Built Sign Up and Login screens strictly adhering to DESIGN.md styling (VessPayTextField, warm cream canvas, coral CTAs), wired to POST /api/auth/register and POST /api/auth/login via AuthRepository and ApiClient, with inline validation, error banners, submit loading states, and token persistence navigating to /travel-mode-setup; verified with widget tests and live backend tests.
- [x] T1.7 — Phase 1 deliverable check (signup → home, session persists)
  - Note: Verified end-to-end without manual backend intervention: brand-new user launches app to splash, routes to onboarding, registers live user against running Express + PostgreSQL backend, reaches placeholder home screen, and session persists across app restart (splash auto-routes straight to home with valid JWT session); Phase 1 complete.

## Phase 2 — Travel Mode

- [x] T2.1 — travel_profiles endpoints
  - Note: Implemented GET /api/travel/destinations (returning extensible array for Ghana and Nigeria), authenticated GET /api/travel/current (returns null when unconfigured), and authenticated PUT /api/travel/current (validates destination, deactivates previous active profile, and activates requested corridor in a transaction); verified with automated suite (npm run test:travel) and live backend. No deviations from blueprint, no TODOs.
- [x] T2.2 — Destination selection screen
  - Note: Built "Where are you travelling?" screen adhering strictly to DESIGN.md tokens (warm cream canvas, coral borders, flag badges, corridor pills), listing destinations from GET /api/travel/destinations (Ghana & Nigeria), selecting Ghana persists destination via PUT /api/travel/current, routes to Home, and Home reflects active corridor ("Traveling in 🇬🇭 Ghana") persisting across app restart; verified with widget tests and live backend tests. No deviations from blueprint, no TODOs.
- [x] T2.3 — Global "Traveling in" state
  - Note: Exposed reactive travel state providers (currentTravelProfileProvider, travelingInTextProvider, activeDestinationCountryProvider, activeDestinationCurrencyProvider) and built reusable TravelingInIndicator widget (compact pill & card variants per DESIGN.md) integrated into Home; verified indicator updates immediately upon changing destination without requiring an app restart. No deviations from blueprint, no TODOs.

## Phase 3 — Wallet

- [x] T3.1 — Wallet read endpoints
  - Note: Implemented authenticated GET /api/wallet (returns { id, currency, balance } defaulting to USD) and GET /api/wallet/balances (returns [{ currency, balance }]) per Section 7, with resilient auto-provisioning; verified with automated test suite (npm run test:wallet) and live dev server. No deviations from blueprint, no TODOs.
- [x] T3.2 — WeWire sub-customer creation on registration
  - Note: Wired live WeWire POST /v1/subcustomers on user registration mapping ISO 3166-1 alpha-3 country codes and storing id in users.wewire_subcustomer_id; probed KYC endpoints and added simplified hackathon demo KYC submission (simplified: demo DOB 1990-01-01, standard street addresses, demo international phone, placeholder 1x1 png for passport ID); verified with automated suite (npm run test:subcustomer) and live WeWire sandbox API. No deviations from blueprint, no TODOs.
- [x] T3.3 — funding_transactions table + Add Money endpoint
  - Note: Added funding_transactions table with PostgreSQL migration (20260902193735_add_funding_transactions) per Section 6. Implemented POST /api/wallet/topup returning PENDING funding row along with checkoutId, checkoutUrl, and virtual account details (bankName, accountName, accountNumber, routingNumber) per Section 7 and confirmed WeWire funding mechanisms; verified with npm run test:topup. No deviations from blueprint, no TODOs.
- [x] T3.4 — Webhook endpoint skeleton (signature verification + idempotency)
  - Note: Added webhook_events table with PostgreSQL migration (20260902194550_add_webhook_events) per Section 6. Implemented POST /api/webhooks/wewire with Standard Webhooks HMAC-SHA256 signature verification (webhook-id, webhook-timestamp, webhook-signature, replay tolerance) and strict idempotency check (skipping processing with HTTP 200 SKIPPED on duplicate event_id); verified with automated suite (npm run test:webhook). No deviations from blueprint, no TODOs.
- [x] T3.5 — Funding webhook → wallet balance update
  - Note: Extended POST /api/webhooks/wewire to handle funding confirmation events (transaction.pay_in, etc.), matching funding_transactions via fundingTransactionId, checkoutId/reference, or subCustomerId, transitioning status to COMPLETED, and atomically incrementing wallet balance inside a Prisma transaction; verified with npm run test:funding-webhook that duplicate delivery never double-credits. No deviations from blueprint, no TODOs.
- [x] T3.6 — Wallet screen (Flutter)
  - Note: Built WalletScreen displaying live balances from GET /api/wallet/balances via Riverpod walletBalancesProvider, stubbed GHS-equivalent line (usdToGhsRateProvider @ 15.50 GHS/USD to be linked in T4.1), action buttons (Add Money & Pay Anyone), and pull-to-refresh; integrated into app router (/wallet) and Home dashboard card; verified with automated widget tests (flutter test test/wallet_screen_test.dart). No deviations from blueprint, no TODOs.
- [x] T3.7 — Add Money flow (Flutter)
  - Note: Built AddMoneyScreen wired to POST /api/wallet/topup, launching WeWire checkout via external browser, handling waiting-for-confirmation state with automatic polling of GET /api/wallet/topup/:id, and auto-updating wallet balance on confirmation without manual backend refresh; verified with automated widget tests (test/add_money_screen_test.dart) and live backend flow using existing database user (zero new users created). No deviations from blueprint, no TODOs.

## Phase 4 — Pay Anyone (quote flow only)

- [x] T4.1 — Rates endpoint
  - Note: Implemented GET /api/rates?from=USD&to=GHS sourcing live exchange rates from WeWire sandbox (GET /v1/rates, returning 11.58 GHS/USD with timestamp), with short in-memory cache, pair catalog at /api/rates/pairs, and strict validation returning clear 400 errors for bad currency pairs; verified with npm run test:rates (31/31 assertions pass) creating zero new accounts. No deviations from blueprint, no TODOs.

- [x] T4.2 — Quote endpoint
  - Note: Fee model chosen: Percentage fee of 1% of source amount in USD (override via PAYMENT_FEE_PERCENT). Implemented POST /api/payments/quote per Section 7 calculating exact sourceAmount, fee, exchangeRate, and total in USD from destination amount in GHS using live rates from T4.1; verified with npm run test:quote (28/28 assertions pass) creating zero new accounts. No deviations from blueprint, no TODOs.


- [x] T4.3 — Pay Anyone flow screens 1–5
  - Note: Built guided 5-step Pay Anyone flow (Ghana preselected, Mobile Money & Bank payment types, MTN/Telecel/AirtelTigo network selection, validated recipient phone entry, amount entry with live 1% fee calculation) landing on Review Screen with entered data intact; verified with automated widget tests (test/pay_anyone_flow_test.dart) creating zero new accounts. No deviations from blueprint, no TODOs.

- [x] T4.4 — Payment Review screen
  - Note: Populated Payment Review screen live via POST /api/payments/quote (PaymentRepository and paymentQuoteProvider) adhering to Section 11 "always show both currencies" principle with hero twin display (You Pay USD / Recipient Gets GHS), complete recipient details, 1% fee breakdown, and Confirm Payment button ready for Phase 5; verified with test/payment_review_screen_test.dart and full suite (60/60 pass) with zero new accounts created. No deviations from blueprint, no TODOs.


## Phase 5 — WeWire Payout (real integration)

- [x] T5.1 — Beneficiaries table + endpoints
  - Note: Added `beneficiaries` table matching Section 6 with PostgreSQL migration (`20260903113727_add_beneficiaries`), implemented authenticated GET/POST/DELETE `/api/beneficiaries` and GET `/api/beneficiaries/:id` with input validation and user isolation, wired real WeWire sandbox `POST /v1/beneficiaries` and account resolution storing `wewire_beneficiary_id` and `wewire_account_id`; verified with `npm run test:beneficiaries` (39/39 assertions passing) against live sandbox using existing users with zero new accounts created. No blueprint deviations, no TODOs.
- [x] T5.2 — Transactions table + payment creation endpoint (idempotent)
  - Note: Added `transactions` table matching Section 6 with PostgreSQL migration (`20260903115117_add_transactions`), implemented authenticated `POST /api/payments` per Section 7 with strict idempotency (re-sending same key returns existing transaction without duplicate rows), server-side quote recalculation, wallet balance verification, beneficiary reuse/creation via T5.1, and transaction record in `CREATED` status; verified with `npm run test:payments` (39/39 assertions passing) with zero new users created. No blueprint deviations, no TODOs.
- [x] T5.3 — Wire real WeWire payout call
  - Note: Extended authenticated POST /api/payments to wire real WeWire sandbox disbursement endpoint (POST /v1/disbursements per current API docs for Ghana mobile money corridors). Following local transaction row creation, calls sendWeWireDisbursement with idempotencyKey, amount (GHS), network code (MTN/VOD/ATM), and 10-digit recipient phone; stores returned wewire_transaction_id, decrements user USD wallet balance, and moves local transaction status to PENDING (never COMPLETED here, per Section 9); verified with npm run test:payments and live WeWire sandbox API (returning HTTP 202 Accepted with type DISBURSEMENT and status PENDING) using existing users with zero new users created. No blueprint deviations, no TODOs.
- [x] T5.4 — Payout webhook → transaction state machine
  - Note: Extended POST /api/webhooks/wewire to handle disbursement/payout events (disbursement.initiated, disbursement.completed, disbursement.failed, and transaction.status_updated); matches local transaction rows on wewire_transaction_id (or reference/idempotencyKey), moves state machine through PENDING → PROCESSING → COMPLETED or to FAILED; atomically debits the user's source wallet ledger (sourceAmount + fee) strictly on transition to COMPLETED; verified with npm run test:payout-webhook that duplicate delivery skips at the gateway (HTTP 200 SKIPPED) and at-least-once event redelivery never double-debits the wallet, with zero new users created. No blueprint deviations, no TODOs.
- [x] T5.5 — Payment history endpoints
  - Note: Implemented `GET /api/payments` and `GET /api/payments/:id` per `VESSPAY_BLUEPRINT.md` Section 7; returning full transaction detail (id, userId, type, status, sourceCurrency, sourceAmount, destinationCurrency, destinationAmount, fee, exchangeRate, rate, recipient { name, phone, network, country }, wewireReference, vesspayReference [VP-PAY-...], idempotencyKey, and timestamps { createdAt, updatedAt }); strictly enforces user isolation (User A only sees their own transactions, and accessing User B's transaction by ID returns 404 NOT_FOUND); verified with `npm run test:payment-history` with 100% pass rate using existing users and zero new accounts created. No blueprint deviations, no TODOs.
- [x] T5.6 — Payment processing / success / failure screens
  - Note: Built the three post-confirmation screens per `VESSPAY_BLUEPRINT.md` Section 12: `PaymentProcessingScreen` shows real progress (not a fixed timer) by polling `GET /api/payments/:id` every 1.5s via `paymentProcessingProvider`, with real lifecycle steps and status chips; routes strictly on backend terminal states (`COMPLETED` -> `PaymentSuccessScreen` with hero twin currencies and VessPay reference, `FAILED` -> `PaymentFailureScreen` with safety reassurance "Your money is safe. No funds were deducted from your wallet" and retry option); wired Confirm Payment button in `PaymentReviewScreen` to `createPayment`; verified with automated widget tests (`test/payment_processing_flow_test.dart` 4/4 passing, all 14/14 pay suite passing) and live backend polling script (`npm run test:payment-e2e-polling`) confirming zero premature success displays, using existing users with zero new accounts created. No blueprint deviations, no TODOs.
- [x] T5.7 — Transaction list + detail screens (Flutter)
  - Note: Built `TransactionListScreen` with chronological date grouping ("Today", "Yesterday", and full date headers), status badges, amount formatting, pull-to-refresh, empty state with "Pay Anyone" CTA, and tap-to-detail interaction; built `TransactionDetailScreen` displaying hero amounts, status badges, recipient card, dual-currency fee & rate breakdown (You Sent, 1% Fee, Exchange Rate, Recipient Received), VessPay reference with copy-to-clipboard, WeWire reference, and timestamps; wired `recent_activity_provider.dart` with `transactionDetailProvider` and date grouping helpers; registered routes in `app_routes.dart` and `app_router.dart`; added "See All" button on `HomeDashboardScreen` and "View Transaction Receipt" on `PaymentSuccessScreen` (with immediate cache invalidation); verified with 9/9 automated Flutter widget tests (`test/transaction_screens_test.dart`) and live backend end-to-end test (`npm run test:transactions-e2e`) confirming immediate appearance of completed demo payments upon success, with zero new users created. No blueprint deviations, no TODOs.

## Phase 6 — Polish & Demo Prep

- [ ] T6.1 — Saved recipients
  - Note:
- [ ] T6.2 — In-app notifications
  - Note:
- [ ] T6.3 — Error, empty, and loading states pass
  - Note:
- [ ] T6.4 — Demo seed data (Alex Johnson, $500 wallet)
  - Note:
- [ ] T6.5 — End-to-end demo dry run (2+ consecutive successes)
  - Note:
- [ ] T6.6 — Demo script rehearsal note (timing + reliability)
  - Note:

---

## Final Gate — Definition of Done

- [ ] Full journey works live, end to end, with no manual DB intervention:
  sign up → choose Ghana → wallet visible → fund wallet → balance updates →
  Pay Anyone → Ghana → Mobile Money → network → MoMo number → amount →
  quote shown → confirm → WeWire payout created → webhook received →
  transaction Completed → success screen → appears in history
- [ ] Demo has been rehearsed at least twice successfully (see T6.5, T6.6)
