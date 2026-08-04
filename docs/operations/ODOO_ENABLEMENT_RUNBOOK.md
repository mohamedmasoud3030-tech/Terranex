# Odoo Production Enablement Runbook

**Last verified:** 2026-08-04  
**Scope:** Egypt-first Odoo 18 bridge for Terranex

## Current state

- Both Supabase Edge Functions are deployed with JWT verification:
  - `odoo-sync`
  - `odoo-investor-sync`
- Both workers read `company_settings` and return `processed: 0, skipped: true` before claiming outbox rows when `odoo_enabled=false`.
- Worker claim/complete/fail RPCs are not authenticated browser endpoints.
- Production currently has no configured Odoo URL, database, username, company ID, or entity mappings.
- The demo account and internal E2E owner remain `odoo_enabled=false`.
- On 2026-08-04, 22 queued demo/test events were moved from `pending` to `dead_letter` with an explicit suppression reason. They were not deleted and cannot be claimed by either worker.

## Non-negotiable rule

Never enable Odoo on the demo owner `abdullah@teranex.com` or an `@terranex.internal` account. Use a separate clean real-company owner. Demo/test records must remain isolated and must not be copied into a production accounting database.

## Phase 1 — Prepare Odoo

1. Provision a supported Odoo 18 instance with HTTPS.
2. Create a dedicated integration user with only the models and companies required by the bridge.
3. Install and configure Egyptian localization `l10n_eg`.
4. Confirm EGP is active and the target company is correct.
5. Configure a miscellaneous journal and one journal per Terranex bank/cash account.
6. Confirm every bank/cash journal has a default account.
7. Confirm one unique account exists for each configured code:
   - partner capital;
   - retained earnings;
   - distribution payable.
8. Confirm the sale and purchase VAT rates used by Terranex exist and are active in the target company.
9. Create or identify an analytic plan for Terranex projects.

## Phase 2 — Configure Supabase secrets

Set secrets only in the Edge Function environment. Never add them to Vite variables, GitHub, browser storage, or `company_settings`.

Required:

- `ODOO_URL`
- `ODOO_DB`
- `ODOO_USERNAME`
- `ODOO_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Required for investor accounting:

- `ODOO_PARTNER_CAPITAL_ACCOUNT_CODE`
- `ODOO_RETAINED_EARNINGS_ACCOUNT_CODE`
- `ODOO_DISTRIBUTION_PAYABLE_ACCOUNT_CODE`

Recommended explicit identifiers:

- `ODOO_COMPANY_ID`
- `ODOO_ANALYTIC_PLAN_ID`
- `ODOO_MISC_JOURNAL_ID`

After changing secrets, redeploy both Edge Functions and keep `verify_jwt=true`.

## Phase 3 — Prepare the real Terranex owner

Use a clean owner with real company data.

1. Set `country='EG'`.
2. Set `base_currency='EGP'`.
3. Set `odoo_localization='l10n_eg'`.
4. Record the Odoo URL/database/username/company ID in `company_settings` for operational visibility. The API key still stays server-side only.
5. Keep `odoo_enabled=false` while validating configuration.
6. Confirm there are no demo labels or test domains attached to the owner.
7. Review the owner's outbox before enabling:
   - no unexplained `pending`/`failed` rows;
   - no old demo or fixture entities;
   - no duplicate stable references.

## Phase 4 — Controlled activation

1. Enable Odoo for the real owner only.
2. Trigger the general worker with a small limit, beginning with dependencies:
   - partners;
   - projects/analytic accounts;
   - bank accounts/journals.
3. Confirm `odoo_entity_mappings` contains exactly one mapping per Terranex entity.
4. Run the transactional lifecycles one at a time:
   - customer invoice → post → payment;
   - vendor bill → receive → payment;
   - manual journal → post → reversal;
   - capital contribution/withdrawal;
   - distribution approval → partner entitlement → payment → reversal.
5. Run `odoo-sync` before `odoo-investor-sync` so required partner, project, and bank mappings exist.
6. Stop immediately if an event becomes `failed` or `dead_letter`; inspect the exact error before retrying.

## Phase 5 — Reconciliation evidence

For each lifecycle, capture:

- Terranex entity ID and request ID;
- outbox event ID and final status;
- mapping model and Odoo record ID;
- Terranex bank movement and partner/payment audit row;
- Odoo journal, move, invoice/bill, and payment IDs;
- debit/credit totals in EGP;
- partner/project analytic assignment;
- reversal link where applicable.

Acceptance requires:

- no duplicate Odoo records after retrying the same Terranex request;
- no unbalanced moves;
- invoice/bill residuals match Terranex outstanding amounts;
- bank/cash movement direction matches the business event;
- distribution approval and payment use the reviewed Egyptian control accounts;
- reversals preserve both original and reversal records;
- all mappings are owner-scoped and stable.

## Safe outbox queries

Review status without mutating rows:

```sql
select owner_id, status, entity_type, operation, count(*)
from public.odoo_sync_outbox
group by owner_id, status, entity_type, operation
order by owner_id, status, entity_type, operation;
```

Review mappings:

```sql
select owner_id, entity_type, entity_id, odoo_model, odoo_record_id, last_synced_at
from public.odoo_entity_mappings
order by owner_id, entity_type, entity_id;
```

Do not delete failed events to make a dashboard look clean. Resolve the cause, retry through the worker lifecycle, or move an intentionally suppressed demo/test event to `dead_letter` with a clear audit reason.

## Rollback / stop procedure

If activation fails:

1. Set `odoo_enabled=false` for the affected owner.
2. Do not manually reset `processing` rows until the worker timeout and lock state are understood.
3. Preserve `last_error`, attempt count, mappings, and Odoo record IDs.
4. Reconcile any Odoo records already posted before retrying.
5. Never rerun with changed account codes against partially posted events without a documented correction plan.
6. Keep Terranex operational writes available only when their Odoo failure does not compromise the official ledger decision; otherwise pause live-money use.

## Final GO evidence

Odoo is not considered production-ready until this runbook has a dated execution record containing the real instance, company, configuration IDs, lifecycle results, reconciliations, and approver.