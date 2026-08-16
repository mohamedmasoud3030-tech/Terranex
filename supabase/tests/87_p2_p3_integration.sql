-- P2/P3 database control-surface verification.
-- Functional settlement scenarios are exercised by the later R4/P3 suites;
-- this early gate intentionally has no fixture-order dependency.

-- Supplier stated total is an authoritative required field.
select 1/case when exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='supplier_invoices'
    and column_name='supplier_stated_total_minor_units' and is_nullable='NO'
) then 1 else 0 end as p2_supplier_total_required;

-- Exception resolution has its own replay identity.
select 1/case when exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='procurement_invoice_exceptions'
    and column_name='resolve_idempotency_key'
) and exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='procurement_invoice_exceptions'
    and column_name='resolve_request_hash'
) then 1 else 0 end as p2_exception_resolution_idempotent_contract;

-- Non-goods invoice/acceptance type coherence is enforced by a DB trigger.
select 1/case when exists (
  select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
  where c.relname='supplier_invoice_lines'
    and t.tgname='supplier_invoice_lines_acceptance_type_coherence'
    and not t.tgisinternal
) then 1 else 0 end as p2_acceptance_type_guard;

-- PREPAID_ASSET is explicit; supplier advances are not fake payables.
select 1/case when exists (
  select 1 from public.semantic_accounts where role='PREPAID_ASSET'
) then 1 else 0 end as p3_prepaid_asset_semantic_role;

-- P3 settlement facts and beneficiary attribution are present.
select 1/case when exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='unapplied_payments' and column_name='party_id' and is_nullable='NO'
) and exists (select 1 from information_schema.tables where table_schema='public' and table_name='payment_allocations')
  and exists (select 1 from information_schema.tables where table_schema='public' and table_name='supplier_advances')
  and exists (select 1 from information_schema.tables where table_schema='public' and table_name='supplier_advance_applications')
  and exists (select 1 from information_schema.tables where table_schema='public' and table_name='supplier_credit_notes')
then 1 else 0 end as p3_settlement_schema_present;

-- Mixed settlement shares one authoritative outstanding function and ordinary
-- payments are guarded at the DB boundary too.
select 1/case when to_regprocedure('public.obligation_active_outstanding_minor_units(uuid,uuid)') is not null
  and exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
    where c.relname='project_payments' and t.tgname='p3_project_payment_settlement_guard' and not t.tgisinternal
  ) then 1 else 0 end as p3_mixed_settlement_guard;

-- Posted settlement source types are registered in the authoritative journal.
select 1/case when pg_get_constraintdef(oid) like '%SUPPLIER_CREDIT_NOTE%'
  and pg_get_constraintdef(oid) like '%UNAPPLIED_PAYMENT%'
  and pg_get_constraintdef(oid) like '%PAYMENT_ALLOCATION%'
  and pg_get_constraintdef(oid) like '%SUPPLIER_ADVANCE_APPLICATION%'
  then 1 else 0 end as p3_journal_sources_registered
from pg_constraint
where conrelid='public.journal_batches'::regclass and conname='journal_batches_source_type_check';

-- New settlement tables are RLS-protected and not directly writable by authenticated.
select 1/case when not exists (
  select 1 from (values
    ('unapplied_payments'),('payment_allocations'),('supplier_advances'),
    ('supplier_advance_applications'),('supplier_credit_notes')
  ) v(name)
  join pg_class c on c.relname=v.name
  join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  where not c.relrowsecurity or not c.relforcerowsecurity
     or has_table_privilege('authenticated',format('public.%I',v.name),'INSERT,UPDATE,DELETE')
) then 1 else 0 end as p3_rls_and_no_direct_writes;

-- Journal truth remains immutable after the P3 extensions.
select 1/case when exists (
  select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
  where c.relname='journal_lines' and t.tgname='journal_lines_immutable' and not t.tgisinternal
) then 1 else 0 end as p3_journal_immutability_preserved;
