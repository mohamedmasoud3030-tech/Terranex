# Terranex Launch Readiness — 2026-08-04

## Decision

- **Client demo and guided walkthrough:** GO.
- **Live-money production operations:** CONDITIONAL NO-GO until the three manual infrastructure gates below are closed.

This decision separates application correctness from external production controls. The application, database schema, and core financial lifecycles are running; the remaining blockers are password-breach protection, verified recovery, and real Odoo production configuration.

## Verified production snapshot

| Gate | Result | Evidence |
|---|---:|---|
| Git production revision | ✅ | `b8585f90176fa2d7862222e101659843396319d0` |
| Vercel production deployment | ✅ | `READY`, target `production` |
| Public application URL | ✅ | `https://terranex.vercel.app` returned HTTP 200 |
| Runtime errors | ✅ | No Vercel runtime errors in the preceding 24 hours |
| Security headers | ✅ | CSP, HSTS, frame denial, MIME protection, permissions policy |
| Supabase production schema | ✅ | Production project active with 45 applied migrations |
| Runtime schema contract | ✅ | CI compares frontend relations, order columns, and RPC names to migrations |
| Odoo server boundary | ✅ | `odoo-sync` and `odoo-investor-sync` Edge Functions are active |
| Odoo disabled-owner gate | ✅ | Both workers return before claim/client creation when `odoo_enabled=false` |
| Demo/test Odoo queue isolation | ✅ | 22 historical demo/test events moved to auditable `dead_letter`; zero `pending` remained |
| Anonymous elevated RPC execution | ✅ | Zero anonymous-executable `SECURITY DEFINER` functions |
| External trigger-function execution | ✅ | Zero trigger functions exposed to API roles |
| Authenticated elevated RPC boundary | ✅ | Exact 25-function allowlist documented and enforced in PostgreSQL CI |
| Demo workspace | ✅ | Connected project, partner, bank, invoice, inventory, journal, and distribution data |

## Production smoke evidence

The following operations were executed with the real authenticated owner and real RLS/RPC boundary inside a database transaction that ended with `ROLLBACK`; no smoke data was retained.

- Sales invoice payment updated the paid balance and created the payment audit row, bank movement, and Odoo outbox event.
- Purchase invoice payment updated the paid balance and created the payment audit row, bank movement, and Odoo outbox event.
- A balanced journal was created, posted, and reversed append-only; the original became `reversed`, the reversal remained `posted`, and Odoo events were queued.
- A due distribution allocation was paid and then reversed append-only; the bank and partner-ledger reversal rows were created and the allocation returned to `due`.
- Twenty-seven production read paths succeeded under the real account and RLS.

## Odoo safety action completed

The production demo owner and internal E2E owner had Odoo disabled but had accumulated 22 durable outbox events. On 2026-08-04 those rows were moved from `pending` to `dead_letter` with the reason:

> Intentionally suppressed: demo/test owner with Odoo disabled; never sync to a production Odoo target.

The rows were not deleted. Both claim workers exclude `dead_letter`, so these demo/test events cannot be synchronized after a later activation. The source contract in `tests/odoo-disabled-gate.test.cjs` also prevents either Edge Function from moving the disabled-owner check after the claim or Odoo client initialization.

## Manual blockers before live money

### 1. Enable leaked-password protection

Supabase Auth currently reports leaked-password protection as disabled. Enable it before admitting real users.

Remediation: [Supabase password security and leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)

Acceptance evidence:

- Supabase Security Advisor no longer reports `auth_leaked_password_protection`.
- A newly created or changed password known to be compromised is rejected.

### 2. Prove backup and restore

Repository exports do not constitute a PostgreSQL disaster-recovery plan. Before live money, record and test the production recovery mechanism.

Acceptance evidence:

- Point-in-time recovery or an equivalent managed backup is enabled for the production project.
- A restore drill is completed into a separate project/database.
- Projects, invoices, payments, bank movements, partner ledger, distribution allocations, and audit rows reconcile after restore.
- Recovery owner, frequency, retention, RPO, and RTO are documented.

### 3. Verify the real Odoo target

The bridge code and outbox lifecycle are implemented, but live accounting requires a real Odoo database and Egyptian chart configuration.

Execute [`docs/operations/ODOO_ENABLEMENT_RUNBOOK.md`](../operations/ODOO_ENABLEMENT_RUNBOOK.md) against a clean real-company owner. Never enable Odoo on the demo or E2E owner.

Acceptance evidence:

- `ODOO_URL`, `ODOO_DB`, integration user, API key, company ID, and journal IDs are configured in Supabase function secrets only.
- `l10n_eg` is installed in the selected company.
- Partner capital, retained earnings, and distribution payable account codes exist uniquely.
- Bank/cash journals have valid default accounts.
- One customer invoice/payment, one vendor bill/payment, one manual journal/reversal, and one investor lifecycle event reach Odoo and reconcile.
- Failed events remain retryable in the outbox and do not disappear silently.

## Non-blocking follow-up

- ETA e-invoicing onboarding remains a separate legal and operational phase.
- Reverse synchronization from Odoo and bank-statement reconciliation are future capabilities; the current UI must not imply they are complete.
- Demo data must remain clearly labelled and must never be sent to a real Odoo target.

## Release rule

Do not change the live-money decision to GO from a code-only PR. Attach evidence for all three manual blockers, rerun the production smoke/read checks, and record the final decision in a dated successor to this document.