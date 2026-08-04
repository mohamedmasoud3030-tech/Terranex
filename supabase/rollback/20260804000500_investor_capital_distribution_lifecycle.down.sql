-- Roll back the investor capital/distribution lifecycle and restore the prior
-- ownership + Odoo manual-journal boundaries.

drop trigger if exists trg_odoo_mapping_release_investor_dependents on odoo_entity_mappings;
drop function if exists terranex_release_odoo_investor_dependents();
drop trigger if exists trg_partner_ledger_odoo_investor_event on partner_ledger_entries;
drop trigger if exists trg_distributions_odoo_investor_event on distributions;
drop function if exists terranex_enqueue_odoo_investor_event();

delete from odoo_entity_mappings where entity_type in ('distribution','partner_ledger_entry');
delete from odoo_sync_outbox where entity_type in ('distribution','partner_ledger_entry');

-- Restore the immediately preceding Odoo vocabulary/queue/trigger definitions.
\ir ../migrations/20260804000400_odoo_manual_journals.sql

drop function if exists reverse_partner_ledger_entry_atomic(uuid,uuid,date,text);
drop function if exists pay_distribution_allocation_atomic(uuid,uuid,uuid,date,uuid,text);
drop function if exists record_partner_capital_movement_atomic(
  uuid,uuid,uuid,terranex_ledger_entry_type,numeric,terranex_currency,numeric,date,uuid,uuid,uuid,text
);
drop function if exists approve_distribution_atomic(uuid,uuid,text);

drop trigger if exists trg_partner_ledger_source_guard on partner_ledger_entries;
drop function if exists terranex_guard_partner_ledger_source();

alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance',
    'invoice_payment','bill_payment','journal_posting','journal_reversal'
  ));

alter table partner_ledger_entries drop constraint if exists partner_ledger_entries_bank_tx_owner_fk;
alter table partner_ledger_entries drop constraint if exists partner_ledger_entries_bank_owner_fk;
drop index if exists partner_ledger_entries_bank_tx_unique;
alter table partner_ledger_entries drop column if exists bank_transaction_id;
alter table partner_ledger_entries drop column if exists bank_account_id;

alter table distributions drop constraint if exists distributions_approved_by_owner_fk;
alter table distributions drop column if exists paid_at;
alter table distributions drop column if exists approved_by;
alter table distributions drop column if exists approved_at;

-- Restore the previous distribution RPC, which created entitlement rows at
-- distribution creation time. Later rollback files remove this function.
\ir ../migrations/20260801000700_ownership_distribution_entitlements_and_immutability.sql