# Odoo 18 — Accounting Backend for Terranex

This directory holds the `docker-compose.yml` and configuration for running
**Odoo 18 Community** as Terranex's accounting backend.

## Why Odoo?

Terranex's core strength is its investment/operations layer (project ownership
with temporal slicing, immutable distribution snapshots, livestock/agriculture
operational events, partner ledger). These are not things any ERP does well
out of the box.

For everything accounting (chart of accounts, double-entry ledger, legal
invoices, VAT, bank reconciliation, fixed-asset depreciation, period close,
stock/warehouse, financial statements) we delegate to **Odoo 18 Community**
and integrate it via the built-in JSON-RPC API.

The React UI remains *Arabic-first, RTL, and purpose-built* for your
investment company. Odoo's UI is only used by the accountant for advanced
operations (bank reconciliation, tax reporting, year-end close).

## Setup (first time)

1. Install Docker + Docker Compose (or Docker Desktop).
2. Copy `config/odoo.conf.example` → `config/odoo.conf` if needed (already present).
3. Copy `.env.example` → `.env` and edit the passwords.
4. Run:
   ```bash
   cd external/odoo
   docker compose up -d
   ```
5. Open `http://localhost:8069` in your browser.
6. Create the first database:
   - **Master Password:** the value of `ODOO_MASTER_PASSWORD` from `.env`
   - **Database Name:** `terranex` (or your company short name)
   - **Language:** العربية (Arabic)
   - **Country:** Oman / Egypt / Saudi Arabia / UAE (loads IFRS chart of accounts + local VAT)
   - **Email/Password:** admin credentials for the accountant
7. After login, open **Apps** and install only the following modules:
   - `Accounting` (Invoicing & Accounting)
   - `Contacts`
   - `Inventory` (MRP/stock, needed for feed/fertilizer inventory later)
   - Do **not** install CRM, Sales, Purchase, Website, eCommerce, etc. (they add menu noise).
8. In Settings → Users, create an **API user** named `Terranex Sync` with:
   - Group: `Accounting / Advisor` (full read/write on accounting)
   - Copy the user ID and set an API key (Preferences → Account Security → API Keys → New).

## Configure Terranex to talk to Odoo

Add these variables to Terranex's `.env.local`:

```bash
VITE_ODOO_URL=http://localhost:8069
VITE_ODOO_DB=terranex
VITE_ODOO_USERNAME=terranex-sync@yourcompany.com
VITE_ODOO_API_KEY=xxxxxxxxxxxxxxxxxxxxx
```

Then open **Governance → Settings** in the app and enable the Odoo integration toggle
to activate real syncing.

## What syncs to Odoo

| Terranex action                                | Odoo side                                           |
| ---------------------------------------------- | --------------------------------------------------- |
| Create Partner (supplier/customer/equity)      | `res.partner` (contact)                             |
| Create Project                                 | `account.analytic.account` (cost center)            |
| Create Transaction (income/expense)            | `account.move` journal entry                        |
| Record Settlement (payment)                    | `account.payment` linked to outstanding invoices     |
| Record Distribution payment                    | Journal entry on equity / partner payable accounts  |
| Create Bank/Cash account (when added in Terranex) | `account.account` of type Bank/Cash                |

## What stays in Terranex only

- Project ownership history & equity changes
- Distribution snapshots and partner entitlements
- Operational events (birth, death, vaccination, planting, harvest, ...)
- Live asset quantity (headcount, acreage) derived from events
- The investor portal
- Sector-specific profitability dashboards
- Documents (kept in Supabase storage for now; attach to Odoo records via `ir.attachment` later)

## Backup

Odoo's Postgres volume is `odoo-db-data`. Back it up using:

```bash
docker exec terranex-odoo-db pg_dump -U odoo terranex | gzip > odoo_backup_$(date +%F).sql.gz
```

This should be added to the same daily backup cron as Supabase.

## Useful references

- Odoo JSON-RPC docs: https://www.odoo.com/documentation/18.0/developer/reference/external_api.html
- Odoo Community Association (OCA): https://github.com/OCA (ZATCA/e-invoicing modules, bank imports, etc.)
- Arabic chart of accounts: auto-loaded by country when the DB is created; can be customized later.
