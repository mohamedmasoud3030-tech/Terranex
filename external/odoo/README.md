# Odoo 18 — Accounting Backend for Terranex (Egypt First)

This directory runs **Odoo 18 Community** as the accounting engine beneath
Terranex. Terranex remains the source of truth for projects, operations,
investors, ownership history, partner capital and distributions.

## First deployment target

The first supported market is **Egypt**:

- Company country: `EG`
- Base currency: `EGP`
- Fiscal localization: `l10n_eg`
- ETA integration later: `l10n_eg_edi_eta`
- One-branch ETA code: `0`

Do not configure Oman localization for this deployment.

## Responsibility split

| Terranex owns | Odoo owns |
| --- | --- |
| Projects and sector operations | Chart of accounts and double-entry ledger |
| Investors, ownership and capital workflows | Official customer/vendor accounting |
| Partner ledger and distribution logic | Tax, period close and financial statements |
| Operational documents and analytics | Egyptian accounting localization and ETA workflow |

There must never be two competing official ledgers. Terranex financial tables
are operational subledgers; Odoo becomes the accounting source of truth.

## Secure integration architecture

The browser never calls Odoo and never receives an Odoo API key.

```text
Terranex browser
  -> Supabase business RPC / table write
  -> PostgreSQL transactional outbox
  -> Supabase Edge Function: odoo-sync
  -> Odoo 18 JSON-RPC
```

The outbox row is created in the same database transaction as the Partner,
Project or Invoice lifecycle change. Failed Odoo calls remain retryable and do
not disappear silently.

## Setup

1. Install Docker and Docker Compose.
2. Copy `.env.example` to `.env` and set strong database/master passwords.
3. Start the stack:
   ```bash
   cd external/odoo
   docker compose up -d
   ```
4. Open `http://localhost:8069`.
5. Create the database with:
   - Database name: `terranex_egypt`
   - Language: Arabic or English
   - Country: **Egypt**
   - Company currency: **EGP**
6. Install:
   - Accounting / Invoicing
   - Contacts
   - `l10n_eg` (Egypt - Accounting)
7. Create a dedicated integration user named `Terranex Sync` with only the
   permissions needed for contacts, analytic accounting and invoices.
8. Create an API key for that integration user.

Do not install `l10n_eg_edi_eta` until the company has valid ETA registration,
branch/activity codes, product coding and signing requirements ready.

## Supabase Edge Function secrets

Set secrets on Supabase, never in Vite or Git:

```bash
supabase secrets set \
  ODOO_URL=https://odoo.example.com \
  ODOO_DB=terranex_egypt \
  ODOO_USERNAME=terranex-sync@company.com \
  ODOO_API_KEY=replace-me \
  ODOO_COMPANY_ID=1 \
  ODOO_ANALYTIC_PLAN_ID=1
```

Deploy the function:

```bash
supabase functions deploy odoo-sync
```

Then open **Governance -> Settings**, keep country `Egypt`, base currency `EGP`,
enter ETA branch code (`0` for one branch), and enable the Odoo bridge.

## Current bridge scope

Implemented in the first slice:

| Terranex lifecycle | Odoo model |
| --- | --- |
| Partner create/update | `res.partner` |
| Project create/update | `account.analytic.account` |
| Sales invoice issue | posted `account.move` / customer invoice |
| Purchase invoice receipt | posted `account.move` / vendor bill |
| Invoice void request | attempts Odoo cancellation and records failure if not allowed |

Not yet claimed as implemented:

- Sales/purchase payment posting and reconciliation
- Bank journals and statement imports
- Operational transactions as automatic journal entries
- Partner capital calls, contributions and distributions accounting entries
- ETA production submission/signing
- Reverse synchronization from Odoo to Terranex

Those are the next bridge slices and must use the same outbox/idempotency boundary.

## Backups

Odoo uses a separate PostgreSQL volume. Back it up independently from Supabase:

```bash
docker exec terranex-odoo-db \
  pg_dump -U odoo terranex_egypt | gzip > odoo_backup_$(date +%F).sql.gz
```

A release is not production-ready until both Supabase and Odoo backups have
been restored successfully in a clean environment.
