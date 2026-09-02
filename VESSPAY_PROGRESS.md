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
- [ ] T0.2 — Backend project init
  - Note:
- [ ] T0.3 — Flutter project init
  - Note:
- [ ] T0.4 — Database provisioning
  - Note: (record which DB client/ORM was chosen here)
- [ ] T0.5 — WeWire sandbox connectivity check
  - Note: (record actual base URL / auth header confirmed working)

## Phase 1 — Product Foundation

- [ ] T1.1 — Core database migrations (users, travel_profiles, wallets)
  - Note:
- [ ] T1.2 — Auth endpoints (register/login/me)
  - Note:
- [ ] T1.3 — JWT auth middleware
  - Note:
- [ ] T1.4 — Flutter API client + secure token storage
  - Note:
- [ ] T1.5 — Navigation shell + splash screen
  - Note:
- [ ] T1.6 — Sign up / login screens
  - Note:
- [ ] T1.7 — Phase 1 deliverable check (signup → home, session persists)
  - Note:

## Phase 2 — Travel Mode

- [ ] T2.1 — travel_profiles endpoints
  - Note:
- [ ] T2.2 — Destination selection screen
  - Note:
- [ ] T2.3 — Global "Traveling in" state
  - Note:

## Phase 3 — Wallet

- [ ] T3.1 — Wallet read endpoints
  - Note:
- [ ] T3.2 — WeWire sub-customer creation on registration
  - Note: (record any KYC fields simplified for the hackathon)
- [ ] T3.3 — funding_transactions table + Add Money endpoint
  - Note:
- [ ] T3.4 — Webhook endpoint skeleton (signature verification + idempotency)
  - Note:
- [ ] T3.5 — Funding webhook → wallet balance update
  - Note:
- [ ] T3.6 — Wallet screen (Flutter)
  - Note:
- [ ] T3.7 — Add Money flow (Flutter)
  - Note:

## Phase 4 — Pay Anyone (quote flow only)

- [ ] T4.1 — Rates endpoint
  - Note:
- [ ] T4.2 — Quote endpoint
  - Note: (record the fee model chosen — flat or percentage, and the value)
- [ ] T4.3 — Pay Anyone flow screens 1–5
  - Note:
- [ ] T4.4 — Payment Review screen
  - Note:

## Phase 5 — WeWire Payout (real integration)

- [ ] T5.1 — Beneficiaries table + endpoints
  - Note:
- [ ] T5.2 — Transactions table + payment creation endpoint (idempotent)
  - Note:
- [ ] T5.3 — Wire real WeWire payout call
  - Note:
- [ ] T5.4 — Payout webhook → transaction state machine
  - Note:
- [ ] T5.5 — Payment history endpoints
  - Note:
- [ ] T5.6 — Payment processing / success / failure screens
  - Note:
- [ ] T5.7 — Transaction list + detail screens (Flutter)
  - Note:

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
