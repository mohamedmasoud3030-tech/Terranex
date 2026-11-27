-- Stream B / Standalone customer invoices.
--
-- A general (non-property, non-agriculture, non-livestock) sale to a customer
-- party, issued from the UI and collected into a project cash account. Reuses
-- the canonical S2/S4 journal, receivable, cash-account and idempotency core:
-- issue posts Dr CUSTOMER_RECEIVABLE / Cr GENERAL_SALE_REVENUE, collection
-- posts Dr BANK_CASH / Cr CUSTOMER_RECEIVABLE. No parallel ledger, no VAT or
-- tax invention, no mutable rows: corrections go through the existing
-- manual-adjustment / reversal machinery.

-- ===========================================================================
-- 1. Extend locked shared-core account/source registries
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','PREPAID_ASSET',
  'REAL_ESTATE_RENTAL_REVENUE','GENERAL_SALE_REVENUE'
));
insert into public.semantic_accounts(role,label_ar)
values ('GENERAL_SALE_REVENUE','إيراد مبيعات عامة')
on conflict (role) do nothing;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT','AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION',
  'LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION',
  'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION','SUPPLIER_ADVANCE_APPLICATION',
  'PROPERTY_RENTAL_RECOGNITION','PROPERTY_RENTAL_COLLECTION',
  'MANUAL_ADJUSTMENT','CUSTOMER_INVOICE_ISSUE','CUSTOMER_INVOICE_COLLECTION'
));

-- ===========================================================================
-- 2. Customer invoice aggregate and its collections. Append-only facts; the
--    journal batch is the accounting effect and stays reversal-aware.
-- ===========================================================================
create table public.customer_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  customer_party_id uuid not null,
  invoice_reference text not null check (char_length(trim(invoice_reference)) between 1 and 120),
  description text check (description is null or char_length(trim(description)) between 2 and 1000),
  invoice_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (customer_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create unique index customer_invoices_project_reference_key
  on public.customer_invoices(organization_id, project_id, lower(invoice_reference));
create index customer_invoices_project_idx on public.customer_invoices(project_id, invoice_date desc);
create index customer_invoices_party_idx on public.customer_invoices(customer_party_id);

create table public.customer_invoice_collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  invoice_id uuid not null,
  cash_account_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  collection_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  collected_by uuid not null references auth.users(id) on delete restrict,
  collected_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (invoice_id, organization_id, project_id)
    references public.customer_invoices(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index customer_invoice_collections_invoice_idx
  on public.customer_invoice_collections(invoice_id, collection_date);

-- ===========================================================================
-- 3. Insert guards: rows exist only with their exact journal effect.
-- ===========================================================================
create or replace function public.ci_guard_invoice_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_batch record; v_line_count integer; v_receivable_count integer; v_revenue_count integer;
begin
  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id
    and project_id=new.project_id and source_type='CUSTOMER_INVOICE_ISSUE'
    and source_id=new.id and reversal_of_batch_id is null;
  if not found then
    raise exception 'customer invoice requires its issue journal batch';
  end if;
  select count(*),
    count(*) filter (where sa.role='CUSTOMER_RECEIVABLE' and jl.debit_minor_units=new.amount_minor_units and jl.party_id=new.customer_party_id),
    count(*) filter (where sa.role='GENERAL_SALE_REVENUE' and jl.credit_minor_units=new.amount_minor_units)
  into v_line_count, v_receivable_count, v_revenue_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id;
  if v_line_count<>2 or v_receivable_count<>1 or v_revenue_count<>1 then
    raise exception 'customer invoice journal must be the exact receivable/revenue pair';
  end if;
  return new;
end $$;
create trigger customer_invoices_insert_guard
before insert on public.customer_invoices
for each row execute function public.ci_guard_invoice_insert();

create or replace function public.ci_guard_collection_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_batch record; v_invoice record;
  v_line_count integer; v_cash_count integer; v_receivable_count integer;
begin
  select * into v_invoice from public.customer_invoices
  where id=new.invoice_id and organization_id=new.organization_id and project_id=new.project_id;
  if not found then
    raise exception 'customer invoice not found';
  end if;
  if new.currency<>v_invoice.currency then
    raise exception 'collection currency must match the invoice currency';
  end if;
  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id
    and project_id=new.project_id and source_type='CUSTOMER_INVOICE_COLLECTION'
    and source_id=new.id and reversal_of_batch_id is null;
  if not found then
    raise exception 'customer invoice collection requires its journal batch';
  end if;
  select count(*),
    count(*) filter (where sa.role='BANK_CASH' and jl.debit_minor_units=new.amount_minor_units and jl.cash_account_id=new.cash_account_id),
    count(*) filter (where sa.role='CUSTOMER_RECEIVABLE' and jl.credit_minor_units=new.amount_minor_units)
  into v_line_count, v_cash_count, v_receivable_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id;
  if v_line_count<>2 or v_cash_count<>1 or v_receivable_count<>1 then
    raise exception 'customer invoice collection journal must be the exact cash/receivable pair';
  end if;
  return new;
end $$;
create trigger customer_invoice_collections_insert_guard
before insert on public.customer_invoice_collections
for each row execute function public.ci_guard_collection_insert();

create trigger customer_invoices_append_only
before update or delete on public.customer_invoices
for each row execute function public.s2_guard_append_only();
create trigger customer_invoice_collections_append_only
before update or delete on public.customer_invoice_collections
for each row execute function public.s2_guard_append_only();

-- ===========================================================================
-- 4. Commands: issue and collect. Owner-gated, idempotent, advisory-locked.
-- ===========================================================================
create or replace function public.issue_customer_invoice(
  p_organization_id uuid, p_project_id uuid, p_customer_party_id uuid,
  p_invoice_reference text, p_description text,
  p_amount_minor_units bigint, p_invoice_date date,
  p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_hash text; v_existing record;
  v_project_currency text; v_invoice_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_receivable uuid; v_revenue uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_invoice_reference is null or char_length(trim(p_invoice_reference)) not between 1 and 120 then raise exception 'invoice reference required'; end if;
  if p_description is not null and char_length(trim(p_description)) not between 2 and 1000 then raise exception 'invalid invoice description'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'invoice amount must be positive'; end if;
  if p_invoice_date is null or p_invoice_date>current_date then raise exception 'invoice date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'invoice evidence required'; end if;

  select reporting_currency into v_project_currency from public.investment_projects
  where id=p_project_id and organization_id=p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if not exists(select 1 from public.parties where id=p_customer_party_id and organization_id=p_organization_id) then
    raise exception 'customer party not found';
  end if;

  v_hash:=public.r5_sha256(jsonb_build_object(
    'project_id',p_project_id,'customer_party_id',p_customer_party_id,
    'invoice_reference',trim(p_invoice_reference),'description',nullif(trim(coalesce(p_description,'')),''),
    'amount_minor_units',p_amount_minor_units,'invoice_date',p_invoice_date,
    'evidence_reference',trim(p_evidence_reference)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ci-issue:'||trim(p_idempotency_key),0));
  select * into v_existing from public.customer_invoices
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':ci-ref:'||p_project_id::text||':'||lower(trim(p_invoice_reference)),0));
  if exists(select 1 from public.customer_invoices
    where organization_id=p_organization_id and project_id=p_project_id
      and lower(invoice_reference)=lower(trim(p_invoice_reference))) then
    raise exception 'customer invoice reference already exists in this project';
  end if;

  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  select id into v_revenue from public.semantic_accounts where role='GENERAL_SALE_REVENUE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,p_project_id,'CUSTOMER_INVOICE_ISSUE',v_invoice_id,
    p_invoice_date,'ci-issue-batch-'||v_invoice_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,p_project_id,v_receivable,p_amount_minor_units,0,v_project_currency,p_customer_party_id,p_invoice_date),
    (v_batch_id,p_organization_id,p_project_id,v_revenue,0,p_amount_minor_units,v_project_currency,p_customer_party_id,p_invoice_date);
  insert into public.customer_invoices(
    id,organization_id,project_id,customer_party_id,invoice_reference,description,
    invoice_date,currency,amount_minor_units,evidence_reference,journal_batch_id,
    issued_by,idempotency_key,request_hash
  ) values(
    v_invoice_id,p_organization_id,p_project_id,p_customer_party_id,trim(p_invoice_reference),
    nullif(trim(coalesce(p_description,'')),''),
    p_invoice_date,v_project_currency,p_amount_minor_units,trim(p_evidence_reference),v_batch_id,
    v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'CUSTOMER_INVOICE_ISSUED','customer_invoice',v_invoice_id,
    jsonb_build_object('project_id',p_project_id,'customer_party_id',p_customer_party_id,
      'invoice_reference',trim(p_invoice_reference),'amount_minor_units',p_amount_minor_units,
      'currency',v_project_currency,'journal_batch_id',v_batch_id));
  return v_invoice_id;
end $$;

create or replace function public.collect_customer_invoice(
  p_organization_id uuid, p_invoice_id uuid, p_cash_account_id uuid,
  p_amount_minor_units bigint, p_collection_date date, p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_invoice public.customer_invoices%rowtype;
  v_existing record; v_hash text; v_collection_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_cash_account record; v_cash uuid; v_receivable uuid; v_collected numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'collection amount must be positive'; end if;
  if p_collection_date is null or p_collection_date>current_date then raise exception 'collection date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'collection evidence required'; end if;
  v_hash:=public.r5_sha256(jsonb_build_object(
    'invoice_id',p_invoice_id,'cash_account_id',p_cash_account_id,
    'amount_minor_units',p_amount_minor_units,'collection_date',p_collection_date,
    'evidence_reference',trim(p_evidence_reference)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ci-collect:'||trim(p_idempotency_key),0));
  select * into v_existing from public.customer_invoice_collections
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.invoice_id<>p_invoice_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':ci-invoice:'||p_invoice_id::text,0));
  select * into v_invoice from public.customer_invoices
  where id=p_invoice_id and organization_id=p_organization_id for update;
  if not found then raise exception 'customer invoice not found'; end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_invoice.journal_batch_id) then
    raise exception 'cannot collect a reversed customer invoice';
  end if;
  if p_collection_date<v_invoice.invoice_date then raise exception 'collection cannot precede the invoice date'; end if;
  select id,project_id,currency into v_cash_account from public.project_cash_accounts
  where id=p_cash_account_id and organization_id=p_organization_id;
  if not found or v_cash_account.project_id<>v_invoice.project_id or v_cash_account.currency<>v_invoice.currency then
    raise exception 'collection cash account must belong to the same project and currency';
  end if;
  select coalesce(sum(c.amount_minor_units),0) into v_collected
  from public.customer_invoice_collections c
  join public.journal_batches jb on jb.id=c.journal_batch_id
  where c.invoice_id=p_invoice_id
    and jb.reversal_of_batch_id is null
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id);
  if v_collected+p_amount_minor_units>v_invoice.amount_minor_units then
    raise exception 'collection exceeds outstanding receivable';
  end if;

  select id into v_cash from public.semantic_accounts where role='BANK_CASH';
  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_invoice.project_id,'CUSTOMER_INVOICE_COLLECTION',v_collection_id,
    p_collection_date,'ci-collection-batch-'||v_collection_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,cash_account_id,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_invoice.project_id,v_cash,p_amount_minor_units,0,v_invoice.currency,p_cash_account_id,null,p_collection_date),
    (v_batch_id,p_organization_id,v_invoice.project_id,v_receivable,0,p_amount_minor_units,v_invoice.currency,null,v_invoice.customer_party_id,p_collection_date);
  insert into public.customer_invoice_collections(
    id,organization_id,project_id,invoice_id,cash_account_id,amount_minor_units,currency,
    collection_date,evidence_reference,journal_batch_id,collected_by,idempotency_key,request_hash
  ) values(
    v_collection_id,p_organization_id,v_invoice.project_id,p_invoice_id,p_cash_account_id,
    p_amount_minor_units,v_invoice.currency,p_collection_date,trim(p_evidence_reference),v_batch_id,
    v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'CUSTOMER_INVOICE_COLLECTION_POSTED','customer_invoice_collection',v_collection_id,
    jsonb_build_object('project_id',v_invoice.project_id,'invoice_id',p_invoice_id,
      'cash_account_id',p_cash_account_id,'amount_minor_units',p_amount_minor_units,
      'currency',v_invoice.currency,'journal_batch_id',v_batch_id));
  return v_collection_id;
end $$;

-- ===========================================================================
-- 5. Read models. Reversed effects stay visible but never count as active.
-- ===========================================================================
create or replace view public.customer_invoices_read with (security_invoker=on) as
select
  i.id as invoice_id,i.organization_id,i.project_id,i.customer_party_id,
  p.legal_name as customer_name,
  i.invoice_reference,i.description,i.invoice_date,i.currency,
  i.amount_minor_units::text as amount_minor_units,i.evidence_reference,i.journal_batch_id,
  i.issued_by,i.issued_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=i.journal_batch_id) as is_reversed,
  coalesce((select sum(c.amount_minor_units) from public.customer_invoice_collections c
    join public.journal_batches cb on cb.id=c.journal_batch_id
    where c.invoice_id=i.id and cb.reversal_of_batch_id is null
      and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0)::text
    as collected_minor_units,
  (case when exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=i.journal_batch_id)
    then 0 else i.amount_minor_units-coalesce((select sum(c.amount_minor_units)
      from public.customer_invoice_collections c join public.journal_batches cb on cb.id=c.journal_batch_id
      where c.invoice_id=i.id and cb.reversal_of_batch_id is null
        and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0) end)::text
    as outstanding_minor_units
from public.customer_invoices i
join public.parties p on p.id=i.customer_party_id;

create or replace view public.customer_invoice_collections_read with (security_invoker=on) as
select
  c.id as collection_id,c.organization_id,c.project_id,c.invoice_id,c.cash_account_id,
  c.amount_minor_units::text as amount_minor_units,c.currency,c.collection_date,c.evidence_reference,
  c.journal_batch_id,c.collected_by,c.collected_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=c.journal_batch_id) as is_reversed
from public.customer_invoice_collections c;

-- ===========================================================================
-- 6. Reporting: GENERAL_SALE_REVENUE counts as recognized project revenue in
--    every existing read model (same reversal rules, same columns).
-- ===========================================================================
-- ---------------------------------------------------------------------------
-- Reporting widenings. The views and the roll-up body below are owned by the
-- finance core (F3/F4/F9/F10, R4/R5, H1, GF-013/GF-014). They are restated here
-- only to admit GENERAL_SALE_REVENUE and customer-invoice activity, so they are
-- applied only when the whole core is present. A partial schema that predates
-- that core (a forward-upgrade fixture) keeps its own definitions instead of
-- failing on a relation it never had.
-- ---------------------------------------------------------------------------
do $widen$
declare
  v_missing text;
begin
  select string_agg(sentinel, ', ' order by sentinel)
    into v_missing
  from unnest(array[
    'public.cost_obligation_due_read',
    'public.cost_obligations',
    'public.field_activities',
    'public.fx_rate_snapshots',
    'public.harvest_events',
    'public.input_applications',
    'public.journal_batches',
    'public.journal_lines',
    'public.livestock_cohort_movements',
    'public.policy_authority',
    'public.portfolio_project_assignments',
    'public.project_budgets',
    'public.property_cost_items',
    'public.purchase_orders',
    'public.semantic_accounts',
    'public.supplier_invoices'
  ]) as sentinel
  where to_regclass(sentinel) is null;

  if v_missing is not null then
    raise notice 'customer invoices: finance reporting core absent (%), reporting widenings skipped', v_missing;
    return;
  end if;

  execute $widen_ddl$
-- widened from latest definition in 20260816060000_r5_basic_property_rental_income.sql
create or replace view public.project_financial_position_read with (security_invoker=on) as
with active_postings as (
  select jl.organization_id,jl.project_id,jl.account_id,sa.role,
         jl.debit_minor_units,jl.credit_minor_units,jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jb.reversal_of_batch_id is null
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
),
by_role as (
  select organization_id,project_id,currency,role,
         sum(debit_minor_units) as debits,sum(credit_minor_units) as credits
  from active_postings group by organization_id,project_id,currency,role
),
positions as (
  select organization_id,project_id,currency,
    coalesce(sum(case when role='BANK_CASH' then debits-credits else 0 end),0) as cash_balance_minor_units,
    coalesce(sum(case when role='CUSTOMER_RECEIVABLE' then debits-credits else 0 end),0) as receivable_open_minor_units,
    coalesce(sum(case when role in (
      'REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_RENTAL_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','GENERAL_SALE_REVENUE'
    ) then credits-debits else 0 end),0) as revenue_recognized_minor_units,
    coalesce(sum(case when role='REAL_ESTATE_COST_OF_SALE' then debits-credits else 0 end),0) as cost_of_sale_minor_units,
    coalesce(sum(case when role='PROJECT_EXPENSE' then debits-credits else 0 end),0) as expense_posted_minor_units,
    coalesce(sum(case when role='DEVELOPMENT_WIP' then debits-credits else 0 end),0) as wip_posted_minor_units,
    coalesce(sum(case when role='CONTRIBUTED_CAPITAL' then credits-debits else 0 end),0) as contributions_received_minor_units
  from by_role group by organization_id,project_id,currency
),
payable as (
  select organization_id,project_id,currency,
    sum(outstanding_minor_units::bigint) as payable_open_minor_units,
    sum(paid_minor_units::bigint) as paid_minor_units,
    sum(retention_remaining_minor_units::bigint) as retention_held_minor_units,
    sum(retention_minor_units::bigint) as retention_declared_minor_units,
    count(*) filter(where is_disputed) as disputed_obligations,
    count(*) filter(where aging_bucket like 'OVERDUE%' and outstanding_minor_units::bigint>0) as overdue_obligations,
    sum(case when aging_bucket like 'OVERDUE%' then outstanding_minor_units::bigint else 0 end) as overdue_outstanding_minor_units
  from public.cost_obligation_due_read
  where status='AUTHORIZED' and is_reversed=false
  group by organization_id,project_id,currency
),
budget as (
  select organization_id,project_id,currency,
    sum(budget_minor_units::bigint) filter(where cost_treatment='EXPENSE') as budget_expense_minor_units,
    sum(budget_minor_units::bigint) filter(where cost_treatment='CAPITALIZABLE_WIP') as budget_wip_minor_units,
    sum(committed_obligations_minor_units::bigint) filter(where cost_treatment='EXPENSE') as committed_expense_minor_units,
    sum(committed_obligations_minor_units::bigint) filter(where cost_treatment='CAPITALIZABLE_WIP') as committed_wip_minor_units,
    sum(effective_remaining_minor_units::bigint) filter(where cost_treatment='EXPENSE') as available_expense_minor_units,
    sum(effective_remaining_minor_units::bigint) filter(where cost_treatment='CAPITALIZABLE_WIP') as available_wip_minor_units
  from public.project_budget_consumption_read group by organization_id,project_id,currency
)
select
  p.id as project_id,p.organization_id,p.name as project_name,p.sector,p.reporting_currency as currency,
  coalesce(pos.cash_balance_minor_units,0)::text as cash_balance_minor_units,
  coalesce(pos.receivable_open_minor_units,0)::text as receivable_open_minor_units,
  coalesce(pos.revenue_recognized_minor_units,0)::text as revenue_recognized_minor_units,
  coalesce(pos.cost_of_sale_minor_units,0)::text as cost_of_sale_minor_units,
  coalesce(pos.expense_posted_minor_units,0)::text as expense_posted_minor_units,
  coalesce(pos.wip_posted_minor_units,0)::text as wip_posted_minor_units,
  coalesce(pos.contributions_received_minor_units,0)::text as contributions_received_minor_units,
  coalesce(py.payable_open_minor_units,0)::text as payable_open_minor_units,
  coalesce(py.paid_minor_units,0)::text as paid_minor_units,
  coalesce(py.retention_held_minor_units,0)::text as retention_held_minor_units,
  coalesce(py.retention_declared_minor_units,0)::text as retention_declared_minor_units,
  coalesce(py.disputed_obligations,0) as disputed_obligations,
  coalesce(py.overdue_obligations,0) as overdue_obligations,
  coalesce(py.overdue_outstanding_minor_units,0)::text as overdue_outstanding_minor_units
from public.investment_projects p
left join positions pos on pos.project_id=p.id and pos.currency=p.reporting_currency
left join payable py on py.project_id=p.id and py.currency=p.reporting_currency
left join budget bg on bg.project_id=p.id and bg.currency=p.reporting_currency
where pos.project_id is not null or py.project_id is not null or bg.project_id is not null
   or exists(select 1 from public.cost_obligations o where o.project_id=p.id)
   or exists(select 1 from public.project_budgets b where b.project_id=p.id and b.status='APPROVED');

-- widened from latest definition in 20260816058100_f4_fac_f10_scope.sql
create or replace view public.portfolio_financial_rollup_read with (security_invoker=on) as
with project_converted as (
  select
    pp.*,
    pp.sector as project_sector,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    s.rate_date as fx_rate_date,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = pp.currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    coalesce(pc2.open_commitment_minor_units, 0) as open_commitment_minor_units,
    coalesce(fac.fac_minor_units, 0) as fac_minor_units,
    coalesce(exc.open_exception_count, 0) as open_exception_count,
    (pp.revenue_recognized_minor_units::bigint
      - pp.cost_of_sale_minor_units::bigint) as realized_result_minor_units,
    case
      when o.reporting_currency = pp.currency then pp.cash_balance_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cash_balance_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor,
    case
      when o.reporting_currency = pp.currency then pp.receivable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.receivable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_receivable_minor,
    case
      when o.reporting_currency = pp.currency then pp.revenue_recognized_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.revenue_recognized_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_revenue_minor,
    case
      when o.reporting_currency = pp.currency then pp.cost_of_sale_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.cost_of_sale_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cost_of_sale_minor,
    case
      when o.reporting_currency = pp.currency then pp.expense_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.expense_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_expense_minor,
    case
      when o.reporting_currency = pp.currency then pp.wip_posted_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.wip_posted_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_wip_minor,
    case
      when o.reporting_currency = pp.currency then pp.contributions_received_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.contributions_received_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_contributions_minor,
    case
      when o.reporting_currency = pp.currency then pp.payable_open_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.payable_open_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_payable_minor,
    case
      when o.reporting_currency = pp.currency then pp.paid_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.paid_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_paid_minor,
    case
      when o.reporting_currency = pp.currency then pp.retention_held_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pp.retention_held_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_retention_minor
  from public.project_financial_position_read pp
  join public.organizations o on o.id = pp.organization_id
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = pp.organization_id
      and s2.base_currency = pp.currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= current_date
    order by s2.rate_date desc
    limit 1
  ) s on true
  left join (
    select project_id, currency,
           sum(remaining_commitment_minor_units::bigint) as open_commitment_minor_units
    from public.project_procurement_commitments_read
    group by project_id, currency
  ) pc2 on pc2.project_id = pp.project_id and pc2.currency = pp.currency
  left join (
    select project_id, currency, sum(fac_minor_units::bigint) as fac_minor_units
    from public.project_budget_fac_read
    group by project_id, currency
  ) fac on fac.project_id = pp.project_id and fac.currency = pp.currency
  left join (
    select project_id, count(*) as open_exception_count
    from public.approval_exceptions
    where status = 'OPEN'
    group by project_id
  ) exc on exc.project_id = pp.project_id
),
sector_stats as (
  select pc.project_id, pc.currency, pc.project_sector,
         count(*) as sector_project_count,
         sum(pc.cash_balance_minor_units::bigint) as sector_cash_minor_units
  from project_converted pc
  group by pc.project_id, pc.currency, pc.project_sector
)
select
  pf.id as portfolio_id,
  pf.organization_id,
  pf.name as portfolio_name,
  pf.status as portfolio_status,
  pc.currency,
  pc.org_reporting_currency,
  count(pc.project_id) as project_count,
  sum(pc.cash_balance_minor_units::bigint)::text as cash_balance_minor_units,
  sum(pc.receivable_open_minor_units::bigint)::text as receivable_open_minor_units,
  sum(pc.revenue_recognized_minor_units::bigint)::text as revenue_recognized_minor_units,
  sum(pc.cost_of_sale_minor_units::bigint)::text as cost_of_sale_minor_units,
  sum(pc.expense_posted_minor_units::bigint)::text as expense_posted_minor_units,
  sum(pc.wip_posted_minor_units::bigint)::text as wip_posted_minor_units,
  sum(pc.contributions_received_minor_units::bigint)::text as contributions_received_minor_units,
  sum(pc.payable_open_minor_units::bigint)::text as payable_open_minor_units,
  sum(pc.paid_minor_units::bigint)::text as paid_minor_units,
  sum(pc.retention_held_minor_units::bigint)::text as retention_held_minor_units,
  sum(pc.disputed_obligations) as disputed_obligations,
  sum(pc.overdue_obligations) as overdue_obligations,
  (array_agg(pc.fx_rate_snapshot_id))[1] as fx_rate_snapshot_id,
  min(pc.fx_rate_date) as fx_rate_date,
  min(pc.fx_status) as fx_status,
  sum(pc.converted_cash_minor)::text as converted_cash_balance_minor_units,
  sum(pc.converted_receivable_minor)::text as converted_receivable_open_minor_units,
  sum(pc.converted_revenue_minor)::text as converted_revenue_recognized_minor_units,
  sum(pc.converted_cost_of_sale_minor)::text as converted_cost_of_sale_minor_units,
  sum(pc.converted_expense_minor)::text as converted_expense_posted_minor_units,
  sum(pc.converted_wip_minor)::text as converted_wip_posted_minor_units,
  sum(pc.converted_contributions_minor)::text as converted_contributions_received_minor_units,
  sum(pc.converted_payable_minor)::text as converted_payable_open_minor_units,
  sum(pc.converted_paid_minor)::text as converted_paid_minor_units,
  sum(pc.converted_retention_minor)::text as converted_retention_held_minor_units,
  sum(pc.open_commitment_minor_units)::text as open_commitment_minor_units,
  sum(pc.realized_result_minor_units)::text as realized_result_minor_units,
  sum(pc.fac_minor_units)::text as fac_minor_units,
  sum(pc.open_exception_count) as open_exception_count,
  jsonb_object_agg(
    ss.project_sector,
    jsonb_build_object(
      'project_count', ss.sector_project_count,
      'cash_balance_minor_units', ss.sector_cash_minor_units::text
    )
  ) as sector_exposure,
  (case when sum(pc.cash_balance_minor_units::bigint) > 0 then
     round((max(pc.cash_balance_minor_units::bigint)::numeric
       / sum(pc.cash_balance_minor_units::bigint)::numeric) * 100, 2)::text || '%'
   else null end) as cash_concentration_ratio
from public.investment_portfolios pf
join public.portfolio_project_assignments a
  on a.portfolio_id = pf.id and a.removed_at is null
join project_converted pc on pc.project_id = a.investment_project_id
join sector_stats ss on ss.project_id = pc.project_id and ss.currency = pc.currency
group by pf.id, pf.organization_id, pf.name, pf.status,
         pc.currency, pc.org_reporting_currency;

-- widened from latest definition in 20260904010300_h1_result_deduction_naming.sql
create or replace view public.project_operating_result_read with (security_invoker=on) as
with active_postings as (
  select jl.id, jl.obligation_id, jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from active_postings
  group by organization_id, project_id, currency, role
),
revenue as (
  select organization_id, project_id, currency,
    coalesce(sum(credits - debits) filter (where role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','GENERAL_SALE_REVENUE'
    )), 0) as sale_revenue_minor,
    coalesce(sum(credits - debits) filter (where role = 'REAL_ESTATE_RENTAL_REVENUE'), 0)
      as rental_revenue_minor,
    coalesce(sum(debits - credits) filter (where role = 'REAL_ESTATE_COST_OF_SALE'), 0)
      as cogs_derecognized_minor
  from by_role
  group by organization_id, project_id, currency
),
re_disposal as (
  -- Sector-owned: the recognized disposal result of Real Estate assets.
  select r.organization_id, r.project_id, r.currency,
         sum(r.realized_result_minor_units::bigint) as realized_disposal_minor,
         sum(r.selling_costs_minor_units::bigint) as selling_costs_minor
  from public.property_realized_result_read r
  join public.journal_batches jb on jb.id = r.recognition_batch_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by r.organization_id, r.project_id, r.currency
),
classification as (
  select organization_id, project_id, currency,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'ATTRIBUTED_TO_OPERATING_UNIT'), 0) as attributed_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'PROJECT_OVERHEAD'), 0) as overhead_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXCLUDED_FROM_MANAGEMENT_RESULT'), 0) as excluded_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'UNCLASSIFIED'), 0) as unclassified_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE'), 0)
      as outside_scope_minor
  from public.project_cost_classification_read
  group by organization_id, project_id, currency
),
re_selling_attributed as (
  -- RE only: expense already netted inside the realized disposal result.
  select el.organization_id, el.project_id, el.currency,
         sum(el.expense_minor_units) as selling_attributed_minor
  from (
    select jl.organization_id, jl.project_id, jl.currency, jl.obligation_id,
           (jl.debit_minor_units - jl.credit_minor_units) as expense_minor_units
    from active_postings jl
    where jl.role = 'PROJECT_EXPENSE'
  ) el
  join public.property_cost_items pci
    on pci.cost_obligation_id = el.obligation_id and pci.cost_category = 'SELLING'
  group by el.organization_id, el.project_id, el.currency
),
evidence_facts as (
  -- Optional-evidence facts only. Facts with a mandatory evidence reference always
  -- score 100% and would dilute the measure, so they are deliberately out of scope.
  select organization_id, project_id, evidence_reference from public.unapplied_payments
  union all select organization_id, project_id, evidence_reference from public.supplier_advances
  union all select organization_id, project_id, evidence_reference from public.supplier_credit_notes
  union all select organization_id, project_id, evidence_reference from public.cost_payment_proposals
  union all select organization_id, project_id, evidence_reference from public.real_estate_events
  union all select organization_id, project_id, evidence_reference
    from public.property_asset_state_history
  union all select organization_id, project_id, evidence_reference from public.field_activities
  union all select organization_id, project_id, evidence_reference from public.input_applications
  union all select organization_id, project_id, evidence_reference from public.harvest_events
  union all select organization_id, project_id, evidence_reference
    from public.harvest_inventory_movements
  union all select organization_id, project_id, evidence_reference from public.livestock_health_events
  union all select organization_id, project_id, evidence_reference from public.livestock_feed_issues
  union all select organization_id, project_id, evidence_reference from public.livestock_weight_events
  union all select organization_id, project_id, evidence_reference
    from public.livestock_cohort_movements
  union all select organization_id, project_id, evidence_reference
    from public.livestock_quantity_events
),
evidence as (
  select organization_id, project_id,
         count(*) as subject_count,
         count(*) filter (
           where evidence_reference is not null and char_length(trim(evidence_reference)) > 0
         ) as evidenced_count
  from evidence_facts
  group by organization_id, project_id
),
-- NOTE: there is deliberately no global policy CTE here. ADR 0033's gate
-- (public.require_policy_activated) is scoped by ORGANIZATION and by SCOPE, and so
-- is this disclosure: one organization activating investor economics must never
-- change what another organization's result claims. The predicate is therefore
-- evaluated per row, in the jsonb object below.
components as (
  select
    p.id as project_id,
    p.organization_id,
    p.sector,
    p.reporting_currency as currency,
    coalesce(rev.sale_revenue_minor, 0) as sale_revenue_minor,
    coalesce(rev.rental_revenue_minor, 0) as rental_revenue_minor,
    coalesce(rev.cogs_derecognized_minor, 0) as cogs_derecognized_minor,
    coalesce(rd.realized_disposal_minor, 0) as realized_disposal_minor,
    coalesce(rd.selling_costs_minor, 0) as selling_costs_minor,
    coalesce(c.attributed_minor, 0) as attributed_minor,
    coalesce(rs.selling_attributed_minor, 0) as selling_attributed_minor,
    coalesce(c.overhead_minor, 0) as overhead_minor,
    coalesce(c.excluded_minor, 0) as excluded_minor,
    coalesce(c.unclassified_minor, 0) as unclassified_minor,
    coalesce(c.outside_scope_minor, 0) as outside_scope_minor,
    coalesce(e.subject_count, 0) as evidence_subject_count,
    coalesce(e.evidenced_count, 0) as evidence_evidenced_count
  from public.investment_projects p
  left join revenue rev
    on rev.project_id = p.id and rev.currency = p.reporting_currency
  left join re_disposal rd
    on rd.project_id = p.id and rd.currency = p.reporting_currency
  left join classification c
    on c.project_id = p.id and c.currency = p.reporting_currency
  left join re_selling_attributed rs
    on rs.project_id = p.id and rs.currency = p.reporting_currency
  left join evidence e on e.project_id = p.id
),
derived as (
  select
    c.*,
    (c.attributed_minor - case when c.sector = 'REAL_ESTATE' then c.selling_attributed_minor else 0 end)
      as deductible_attributed_minor,
    case c.sector
      when 'REAL_ESTATE' then
        c.realized_disposal_minor + c.rental_revenue_minor
        - (c.attributed_minor - c.selling_attributed_minor)
        - c.overhead_minor
      else
        c.sale_revenue_minor - c.attributed_minor - c.overhead_minor
    end as result_amount_minor,
    case c.sector
      when 'REAL_ESTATE' then 'REAL_ESTATE_DISPOSAL_AND_RENTAL'
      when 'AGRICULTURE' then 'AGRICULTURE_ENTERPRISE_OPERATING'
      when 'LIVESTOCK' then 'LIVESTOCK_ENTERPRISE_OPERATING'
      else 'UNKNOWN_SECTOR'
    end as result_basis,
    case
      when c.unclassified_minor > 0 and c.attributed_minor = 0 and c.overhead_minor = 0
        then 'NONE'
      when c.unclassified_minor > 0 then 'PARTIAL'
      when c.attributed_minor = 0 and c.overhead_minor = 0 and c.excluded_minor = 0
       and c.outside_scope_minor = 0 then 'NOT_APPLICABLE_NO_OPERATING_COST'
      else 'COMPLETE'
    end as cost_classification_status,
    case
      when c.evidence_subject_count = 0 then 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT'
      when c.evidence_evidenced_count = c.evidence_subject_count then 'COMPLETE'
      when c.evidence_evidenced_count > 0 then 'PARTIAL'
      else 'INCOMPLETE'
    end as evidence_status
  from components c
)
select
  d.project_id,
  d.organization_id,
  d.sector,
  d.currency,
  d.result_basis,
  d.cost_classification_status,
  d.evidence_status,

  -- The qualified result object. The amount exists only here.
  jsonb_build_object(
    'amount_minor_units', d.result_amount_minor::text,
    'currency', d.currency,
    'basis', d.result_basis,
    'cost_classification_status', d.cost_classification_status,
    'evidence_status', d.evidence_status,
    'policy_availability',
      case d.sector
        when 'REAL_ESTATE' then
          array['UNREALIZED_VALUATION_NOT_INCLUDED_IN_MANAGEMENT_RESULT']::text[]
        when 'AGRICULTURE' then
          array['COGS_NOT_RECOGNIZED','HARVEST_INVENTORY_VALUE_NOT_RECOGNIZED']::text[]
        when 'LIVESTOCK' then
          array['COGS_NOT_RECOGNIZED','BIOLOGICAL_ASSET_VALUE_NOT_RECOGNIZED']::text[]
        else array[]::text[]
      end
      || array['RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY']::text[]
      || case when exists (
                select 1 from public.policy_authority pa
                where pa.organization_id = d.organization_id
                  and pa.scope = 'INVESTOR_ECONOMICS'
                  and pa.status = 'APPROVED'
              ) then array[]::text[]
              else array['INVESTOR_ENTITLEMENT_NOT_ACTIVATED']::text[] end,
    'as_of', current_date
  ) as management_result,

  -- Components: exposed so any consumer can recompute the arithmetic.
  d.sale_revenue_minor::text as sale_revenue_minor_units,
  d.rental_revenue_minor::text as rental_revenue_minor_units,
  d.cogs_derecognized_minor::text as cogs_derecognized_minor_units,
  d.realized_disposal_minor::text as realized_disposal_minor_units,
  d.selling_costs_minor::text as selling_costs_minor_units,
  d.attributed_minor::text as attributed_operating_cost_minor_units,
  d.selling_attributed_minor::text as selling_cost_attributed_minor_units,
  d.overhead_minor::text as project_overhead_minor_units,
  d.excluded_minor::text as excluded_from_result_minor_units,
  d.unclassified_minor::text as unclassified_eligible_minor_units,
  d.outside_scope_minor::text as expense_outside_classification_scope_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of,
  -- The cost the management result actually DEDUCTS: attributed cost excluding
  -- SELLING for Real Estate, plus declared project overhead.
  --
  -- This is deliberately distinct from attributed_operating_cost_minor_units,
  -- which is a CLASSIFICATION / reconciliation bucket. A Real Estate SELLING
  -- cost is classified there exactly once while being deducted ZERO times,
  -- because its economic effect is already netted inside the sector-owned
  -- realized disposal result. Naming one in terms of the other is how a cost
  -- ends up counted twice or not at all.
  (d.deductible_attributed_minor + d.overhead_minor)::text as result_deducted_cost_minor_units
from derived d;

-- widened from latest definition in 20260904010600_h1_project_result_by_currency.sql
create or replace view public.project_result_by_currency_read with (security_invoker=on) as
with active_postings as (
  -- Reversal-aware base population: a batch that is itself a reversal is
  -- excluded, and so is any batch that has been reversed. An original economic
  -- effect and its reversal therefore never both count.
  select jl.id, jl.obligation_id, jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from active_postings
  group by organization_id, project_id, currency, role
),
revenue as (
  select organization_id, project_id, currency,
    coalesce(sum(credits - debits) filter (where role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','GENERAL_SALE_REVENUE'
    )), 0) as sale_revenue_minor,
    coalesce(sum(credits - debits) filter (where role = 'REAL_ESTATE_RENTAL_REVENUE'), 0)
      as rental_revenue_minor,
    coalesce(sum(debits - credits) filter (where role = 'REAL_ESTATE_COST_OF_SALE'), 0)
      as cogs_derecognized_minor
  from by_role
  group by organization_id, project_id, currency
),
re_disposal as (
  -- Sector-owned: the recognized disposal result of Real Estate assets, in the
  -- currency of the recognition itself.
  select r.organization_id, r.project_id, r.currency,
         sum(r.realized_result_minor_units::bigint) as realized_disposal_minor,
         sum(r.selling_costs_minor_units::bigint) as selling_costs_minor
  from public.property_realized_result_read r
  join public.journal_batches jb on jb.id = r.recognition_batch_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by r.organization_id, r.project_id, r.currency
),
classification as (
  select organization_id, project_id, currency,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'ATTRIBUTED_TO_OPERATING_UNIT'), 0) as attributed_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'PROJECT_OVERHEAD'), 0) as overhead_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXCLUDED_FROM_MANAGEMENT_RESULT'), 0) as excluded_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'UNCLASSIFIED'), 0) as unclassified_minor,
    coalesce(sum(expense_minor_units::bigint)
      filter (where classification_state = 'EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE'), 0)
      as outside_scope_minor
  from public.project_cost_classification_read
  group by organization_id, project_id, currency
),
re_selling_attributed as (
  -- RE only: expense already netted inside the realized disposal result. It is
  -- reported as a CLASSIFICATION bucket but deducted ZERO times.
  select el.organization_id, el.project_id, el.currency,
         sum(el.expense_minor_units) as selling_attributed_minor
  from (
    select jl.organization_id, jl.project_id, jl.currency, jl.obligation_id,
           (jl.debit_minor_units - jl.credit_minor_units) as expense_minor_units
    from active_postings jl
    where jl.role = 'PROJECT_EXPENSE'
  ) el
  join public.property_cost_items pci
    on pci.cost_obligation_id = el.obligation_id and pci.cost_category = 'SELLING'
  group by el.organization_id, el.project_id, el.currency
),
evidence_facts as (
  -- Optional-evidence facts only. Facts with a mandatory evidence reference
  -- always score 100% and would dilute the measure.
  select organization_id, project_id, evidence_reference from public.unapplied_payments
  union all select organization_id, project_id, evidence_reference from public.supplier_advances
  union all select organization_id, project_id, evidence_reference from public.supplier_credit_notes
  union all select organization_id, project_id, evidence_reference from public.cost_payment_proposals
  union all select organization_id, project_id, evidence_reference from public.real_estate_events
  union all select organization_id, project_id, evidence_reference
    from public.property_asset_state_history
  union all select organization_id, project_id, evidence_reference from public.field_activities
  union all select organization_id, project_id, evidence_reference from public.input_applications
  union all select organization_id, project_id, evidence_reference from public.harvest_events
  union all select organization_id, project_id, evidence_reference
    from public.harvest_inventory_movements
  union all select organization_id, project_id, evidence_reference from public.livestock_health_events
  union all select organization_id, project_id, evidence_reference from public.livestock_feed_issues
  union all select organization_id, project_id, evidence_reference from public.livestock_weight_events
  union all select organization_id, project_id, evidence_reference
    from public.livestock_cohort_movements
  union all select organization_id, project_id, evidence_reference
    from public.livestock_quantity_events
),
evidence as (
  -- Project-level: evidence completeness has no currency dimension, so the same
  -- qualification is repeated on every currency row of the project.
  select organization_id, project_id,
         count(*) as subject_count,
         count(*) filter (
           where evidence_reference is not null and char_length(trim(evidence_reference)) > 0
         ) as evidenced_count
  from evidence_facts
  group by organization_id, project_id
),
currencies as (
  select organization_id, project_id, currency from revenue
  union
  select organization_id, project_id, currency from re_disposal
  union
  select organization_id, project_id, currency from classification
  union
  select organization_id, project_id, currency from re_selling_attributed
),
components as (
  select
    p.id as project_id,
    p.organization_id,
    p.sector,
    cur.currency,
    coalesce(rev.sale_revenue_minor, 0) as sale_revenue_minor,
    coalesce(rev.rental_revenue_minor, 0) as rental_revenue_minor,
    coalesce(rev.cogs_derecognized_minor, 0) as cogs_derecognized_minor,
    coalesce(rd.realized_disposal_minor, 0) as realized_disposal_minor,
    coalesce(rd.selling_costs_minor, 0) as selling_costs_minor,
    coalesce(c.attributed_minor, 0) as attributed_minor,
    coalesce(rs.selling_attributed_minor, 0) as selling_attributed_minor,
    coalesce(c.overhead_minor, 0) as overhead_minor,
    coalesce(c.excluded_minor, 0) as excluded_minor,
    coalesce(c.unclassified_minor, 0) as unclassified_minor,
    coalesce(c.outside_scope_minor, 0) as outside_scope_minor,
    coalesce(e.subject_count, 0) as evidence_subject_count,
    coalesce(e.evidenced_count, 0) as evidence_evidenced_count
  from public.investment_projects p
  -- INNER join: a project with no result fact of any kind gets no row. That is
  -- the whole point — "no realized result" must not become "result is zero".
  join currencies cur
    on cur.project_id = p.id
   and cur.organization_id = p.organization_id
  left join revenue rev
    on rev.project_id = p.id and rev.organization_id = p.organization_id
   and rev.currency = cur.currency
  left join re_disposal rd
    on rd.project_id = p.id and rd.organization_id = p.organization_id
   and rd.currency = cur.currency
  left join classification c
    on c.project_id = p.id and c.organization_id = p.organization_id
   and c.currency = cur.currency
  left join re_selling_attributed rs
    on rs.project_id = p.id and rs.organization_id = p.organization_id
   and rs.currency = cur.currency
  left join evidence e on e.project_id = p.id
),
derived as (
  select
    c.*,
    -- DEDUCTION. A Real Estate SELLING cost is classified (attributed_minor)
    -- once and deducted ZERO times, because its economic effect already sits
    -- inside the sector-owned realized disposal result.
    ((c.attributed_minor - case when c.sector = 'REAL_ESTATE'
                                then c.selling_attributed_minor else 0 end)
     + c.overhead_minor) as deducted_minor,
    case c.sector
      when 'REAL_ESTATE' then c.realized_disposal_minor + c.rental_revenue_minor
      else c.sale_revenue_minor
    end as result_revenue_minor,
    case c.sector
      when 'REAL_ESTATE' then 'REAL_ESTATE_DISPOSAL_AND_RENTAL'
      when 'AGRICULTURE' then 'AGRICULTURE_ENTERPRISE_OPERATING'
      when 'LIVESTOCK' then 'LIVESTOCK_ENTERPRISE_OPERATING'
      else 'UNKNOWN_SECTOR'
    end as result_basis,
    case
      when c.unclassified_minor > 0 and c.attributed_minor = 0 and c.overhead_minor = 0
        then 'NONE'
      when c.unclassified_minor > 0 then 'PARTIAL'
      when c.attributed_minor = 0 and c.overhead_minor = 0 and c.excluded_minor = 0
       and c.outside_scope_minor = 0 then 'NOT_APPLICABLE_NO_OPERATING_COST'
      else 'COMPLETE'
    end as cost_classification_status,
    case
      when c.evidence_subject_count = 0 then 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT'
      when c.evidence_evidenced_count = c.evidence_subject_count then 'COMPLETE'
      when c.evidence_evidenced_count > 0 then 'PARTIAL'
      else 'INCOMPLETE'
    end as evidence_status
  from components c
)
select
  d.project_id,
  d.organization_id,
  d.sector,
  d.currency,
  d.result_basis,
  d.cost_classification_status,
  d.evidence_status,

  -- The qualified result object. The amount exists only here, bound to its
  -- currency, basis, cost-classification status, evidence status, policy
  -- availability and as-of date. There is deliberately no bare result column.
  jsonb_build_object(
    'amount_minor_units',
      (d.result_revenue_minor - d.deducted_minor)::text,
    'currency', d.currency,
    'basis', d.result_basis,
    'cost_classification_status', d.cost_classification_status,
    'evidence_status', d.evidence_status,
    'policy_availability',
      case d.sector
        when 'REAL_ESTATE' then
          array['UNREALIZED_VALUATION_NOT_INCLUDED_IN_MANAGEMENT_RESULT']::text[]
        when 'AGRICULTURE' then
          array['COGS_NOT_RECOGNIZED','HARVEST_INVENTORY_VALUE_NOT_RECOGNIZED']::text[]
        when 'LIVESTOCK' then
          array['COGS_NOT_RECOGNIZED','BIOLOGICAL_ASSET_VALUE_NOT_RECOGNIZED']::text[]
        else array[]::text[]
      end
      || array['RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY']::text[]
      || case when exists (
                select 1 from public.policy_authority pa
                where pa.organization_id = d.organization_id
                  and pa.scope = 'INVESTOR_ECONOMICS'
                  and pa.status = 'APPROVED'
              ) then array[]::text[]
              else array['INVESTOR_ENTITLEMENT_NOT_ACTIVATED']::text[] end,
    'as_of', current_date
  ) as management_result,

  -- Components, exposed so the arithmetic can be recomputed and audited.
  d.sale_revenue_minor::text as sale_revenue_minor_units,
  d.rental_revenue_minor::text as rental_revenue_minor_units,
  d.cogs_derecognized_minor::text as cogs_derecognized_minor_units,
  d.realized_disposal_minor::text as realized_disposal_minor_units,
  d.selling_costs_minor::text as selling_costs_minor_units,
  d.attributed_minor::text as attributed_operating_cost_minor_units,
  d.selling_attributed_minor::text as selling_cost_attributed_minor_units,
  d.overhead_minor::text as project_overhead_minor_units,
  d.excluded_minor::text as excluded_from_result_minor_units,
  d.unclassified_minor::text as unclassified_eligible_minor_units,
  d.outside_scope_minor::text as expense_outside_classification_scope_minor_units,
  d.result_revenue_minor::text as result_revenue_minor_units,
  d.deducted_minor::text as result_deducted_cost_minor_units,
  d.evidence_evidenced_count as evidence_evidenced_count,
  d.evidence_subject_count as evidence_subject_count,
  current_date as as_of
from derived d;
-- Widened body, same return shape. The public wrapper
-- portfolio_financial_rollup_asof() from 20260816058500 is the auth + membership
-- guard and delegates here, so customer-invoice revenue joins the roll-up
-- without re-opening the cross-tenant path.
create or replace function public.portfolio_financial_rollup_asof_impl(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_asof_date date
) returns table (
  portfolio_id uuid,
  organization_id uuid,
  portfolio_name text,
  currency text,
  org_reporting_currency text,
  project_count bigint,
  cash_balance_minor_units text,
  receivable_open_minor_units text,
  revenue_recognized_minor_units text,
  cost_of_sale_minor_units text,
  expense_posted_minor_units text,
  wip_posted_minor_units text,
  contributions_received_minor_units text,
  payable_open_minor_units text,
  paid_minor_units text,
  retention_held_minor_units text,
  disputed_obligations bigint,
  overdue_obligations bigint,
  open_commitment_minor_units text,
  realized_result_minor_units text,
  fac_minor_units text,
  open_exception_count bigint,
  fx_status text,
  converted_cash_balance_minor_units text,
  sector_exposure jsonb,
  cash_concentration_ratio text
)
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
with member_projects as (
  select a.investment_project_id as project_id
  from public.portfolio_project_assignments a
  where a.portfolio_id = p_portfolio_id
    and a.organization_id = p_organization_id
    and a.assigned_at::date <= p_asof_date
    and (a.removed_at is null or a.removed_at::date > p_asof_date)
),
asof_lines as (
  select jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and jl.transaction_date <= p_asof_date
    and not exists (
      select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from asof_lines
  group by organization_id, project_id, currency, role
),
positions as (
  select organization_id, project_id, currency,
    coalesce(sum(case when role = 'BANK_CASH' then debits - credits else 0 end), 0)
      as cash_balance_minor_units,
    coalesce(sum(case when role = 'CUSTOMER_RECEIVABLE' then debits - credits else 0 end), 0)
      as receivable_open_minor_units,
    coalesce(sum(case when role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','GENERAL_SALE_REVENUE'
    ) then credits - debits else 0 end), 0) as revenue_recognized_minor_units,
    coalesce(sum(case when role = 'REAL_ESTATE_COST_OF_SALE' then debits - credits else 0 end), 0)
      as cost_of_sale_minor_units,
    coalesce(sum(case when role = 'PROJECT_EXPENSE' then debits - credits else 0 end), 0)
      as expense_posted_minor_units,
    coalesce(sum(case when role = 'DEVELOPMENT_WIP' then debits - credits else 0 end), 0)
      as wip_posted_minor_units,
    coalesce(sum(case when role = 'CONTRIBUTED_CAPITAL' then credits - debits else 0 end), 0)
      as contributions_received_minor_units,
    coalesce(sum(case when role = 'SUPPLIER_PAYABLE' then credits - debits else 0 end), 0)
      as payable_open_minor_units,
    coalesce(sum(case when role = 'SUPPLIER_PAYABLE' then debits else 0 end), 0)
      as paid_minor_units
  from by_role
  group by organization_id, project_id, currency
),
projects_asof as (
  select
    p.id as project_id,
    p.organization_id,
    p.name as project_name,
    p.sector,
    p.reporting_currency as currency,
    coalesce(pos.cash_balance_minor_units, 0) as cash_balance_minor_units,
    coalesce(pos.receivable_open_minor_units, 0) as receivable_open_minor_units,
    coalesce(pos.revenue_recognized_minor_units, 0) as revenue_recognized_minor_units,
    coalesce(pos.cost_of_sale_minor_units, 0) as cost_of_sale_minor_units,
    coalesce(pos.expense_posted_minor_units, 0) as expense_posted_minor_units,
    coalesce(pos.wip_posted_minor_units, 0) as wip_posted_minor_units,
    coalesce(pos.contributions_received_minor_units, 0) as contributions_received_minor_units,
    coalesce(pos.payable_open_minor_units, 0) as payable_open_minor_units,
    coalesce(pos.paid_minor_units, 0) as paid_minor_units,
    coalesce(ret.retention_minor_units, 0) as retention_held_minor_units,
    coalesce(dis.disputed, 0) as disputed_obligations,
    coalesce(due.overdue, 0) as overdue_obligations,
    coalesce(pc.open_commitment_minor_units, 0) as open_commitment_minor_units,
    (pos.revenue_recognized_minor_units - pos.cost_of_sale_minor_units)
      as realized_result_minor_units,
    coalesce(fac.fac_minor_units, 0) as fac_minor_units,
    coalesce(exc.open_exception_count, 0) as open_exception_count,
    o.reporting_currency as org_reporting_currency,
    s.id as fx_rate_snapshot_id,
    case
      when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
      when o.reporting_currency = p.reporting_currency then 'SAME_CURRENCY'
      when s.id is null then 'NO_RATE_SNAPSHOT'
      else 'CONVERTED_AT_RATE'
    end as fx_status,
    case
      when o.reporting_currency = p.reporting_currency then pos.cash_balance_minor_units::bigint
      when s.id is not null then
        public.fx_convert_exact(pos.cash_balance_minor_units::bigint, s.rate_numerator, s.rate_denominator)
      else null
    end as converted_cash_minor
  from public.investment_projects p
  join member_projects mp on mp.project_id = p.id
  join public.organizations o on o.id = p.organization_id
  left join positions pos
    on pos.project_id = p.id and pos.currency = p.reporting_currency
  left join lateral (
    select s2.* from public.fx_rate_snapshots s2
    where s2.organization_id = p.organization_id
      and s2.base_currency = p.reporting_currency
      and s2.quote_currency = o.reporting_currency
      and s2.rate_date <= p_asof_date
    order by s2.rate_date desc
    limit 1
  ) s on true
  left join (
    select t.organization_id, o2.project_id,
           sum(t.retention_minor_units) as retention_minor_units
    from public.cost_obligation_terms t
    join public.cost_obligations o2 on o2.id = t.obligation_id
    where o2.status = 'AUTHORIZED'
      and o2.transaction_date <= p_asof_date
      and t.created_at::date <= p_asof_date
    group by t.organization_id, o2.project_id
  ) ret_decl on ret_decl.project_id = p.id
  left join (
    select r.organization_id, o2.project_id,
           sum(r.amount_minor_units) as released_minor_units
    from public.cost_obligation_retention_releases r
    join public.cost_obligations o2 on o2.id = r.obligation_id
    where r.release_date <= p_asof_date
    group by r.organization_id, o2.project_id
  ) ret_rel on ret_rel.project_id = p.id
  left join lateral (
    select greatest(0, ret_decl.retention_minor_units
      - coalesce(ret_rel.released_minor_units, 0)) as retention_minor_units,
      ret_rel.released_minor_units
  ) ret on true
  left join (
    select d.organization_id, o2.project_id, count(distinct o2.id) as disputed
    from public.cost_obligation_disputes d
    join public.cost_obligations o2 on o2.id = d.obligation_id
    where d.opened_at::date <= p_asof_date
      and (d.status = 'OPEN' or d.resolved_at::date > p_asof_date)
    group by d.organization_id, o2.project_id
  ) dis on dis.project_id = p.id
  left join (
    select o2.project_id, count(*) as overdue
    from public.cost_obligations o2
    join public.cost_obligation_terms t on t.obligation_id = o2.id
    where o2.status = 'AUTHORIZED'
      and o2.transaction_date <= p_asof_date
      and (
        (t.terms_type = 'FIXED_DATE' and t.due_date < p_asof_date)
        or (t.terms_type = 'NET_DAYS'
            and o2.transaction_date + t.net_days < p_asof_date)
        or (t.terms_type = 'MILESTONE_SCHEDULE'
            and exists (
              select 1 from public.cost_obligation_schedule_lines s3
              where s3.obligation_id = o2.id
                and s3.is_retention_line = false
                and s3.due_date < p_asof_date
            ))
      )
      and o2.amount_minor_units > coalesce((
        select sum(pp2.amount_minor_units)
        from public.project_payments pp2
        join public.journal_batches jb2
          on jb2.source_type = 'PAYMENT' and jb2.source_id = pp2.id
        where pp2.obligation_id = o2.id
          and jb2.transaction_date <= p_asof_date
          and jb2.reversal_of_batch_id is null
          and not exists (
            select 1 from public.journal_batches rb2
            where rb2.reversal_of_batch_id = jb2.id
          )
      ), 0)
    group by o2.project_id
  ) due on due.project_id = p.id
  left join (
    select po.project_id, po.currency,
           sum(po.committed_minor_units::bigint) as committed_minor_units
    from (
      select o3.id, o3.project_id, o3.currency,
             sum(ol.line_amount_minor_units) as committed_minor_units
      from public.purchase_orders o3
      join public.purchase_order_lines ol on ol.purchase_order_id = o3.id
      where o3.status = 'APPROVED'
        and o3.approved_at::date <= p_asof_date
      group by o3.id, o3.project_id, o3.currency
    ) po
    group by po.project_id, po.currency
  ) po_tot on po_tot.project_id = p.id and po_tot.currency = p.reporting_currency
  left join (
    select i.project_id, i.currency,
           sum(il.line_amount_minor_units) as invoiced_minor_units
    from public.supplier_invoices i
    join public.supplier_invoice_lines il on il.supplier_invoice_id = i.id
    where i.status = 'APPROVED'
      and i.invoice_date <= p_asof_date
    group by i.project_id, i.currency
  ) inv_tot on inv_tot.project_id = p.id and inv_tot.currency = p.reporting_currency
  left join lateral (
    select greatest(0, po_tot.committed_minor_units
      - coalesce(inv_tot.invoiced_minor_units, 0)) as open_commitment_minor_units
  ) pc on true
  left join (
    select f.project_id, f.currency, sum(f.fac_minor_units::bigint) as fac_minor_units
    from public.project_budget_fac_read f
    where f.period_start <= p_asof_date and f.period_end >= p_asof_date
    group by f.project_id, f.currency
  ) fac on fac.project_id = p.id and fac.currency = p.reporting_currency
  left join (
    select e.project_id, count(*) as open_exception_count
    from public.approval_exceptions e
    where e.opened_at::date <= p_asof_date
      and (e.status = 'OPEN' or e.decided_at::date > p_asof_date)
    group by e.project_id
  ) exc on exc.project_id = p.id
),
sector_stats2 as (
  select pa.currency, pa.sector,
         count(*) as sector_project_count,
         sum(pa.cash_balance_minor_units) as sector_cash_minor_units
  from projects_asof pa
  group by pa.currency, pa.sector
)
select
  p_portfolio_id as portfolio_id,
  pa.organization_id,
  pf2.name as portfolio_name,
  pa.currency,
  pa.org_reporting_currency,
  count(pa.project_id) as project_count,
  sum(pa.cash_balance_minor_units)::text as cash_balance_minor_units,
  sum(pa.receivable_open_minor_units)::text as receivable_open_minor_units,
  sum(pa.revenue_recognized_minor_units)::text as revenue_recognized_minor_units,
  sum(pa.cost_of_sale_minor_units)::text as cost_of_sale_minor_units,
  sum(pa.expense_posted_minor_units)::text as expense_posted_minor_units,
  sum(pa.wip_posted_minor_units)::text as wip_posted_minor_units,
  sum(pa.contributions_received_minor_units)::text as contributions_received_minor_units,
  sum(pa.payable_open_minor_units)::text as payable_open_minor_units,
  sum(pa.paid_minor_units)::text as paid_minor_units,
  sum(pa.retention_held_minor_units)::text as retention_held_minor_units,
  sum(pa.disputed_obligations) as disputed_obligations,
  sum(pa.overdue_obligations) as overdue_obligations,
  sum(pa.open_commitment_minor_units)::text as open_commitment_minor_units,
  sum(pa.realized_result_minor_units)::text as realized_result_minor_units,
  sum(pa.fac_minor_units)::text as fac_minor_units,
  sum(pa.open_exception_count) as open_exception_count,
  min(pa.fx_status) as fx_status,
  sum(pa.converted_cash_minor)::text as converted_cash_balance_minor_units,
  jsonb_object_agg(
    ss2.sector,
    jsonb_build_object(
      'project_count', ss2.sector_project_count,
      'cash_balance_minor_units', ss2.sector_cash_minor_units::text
    )
  ) filter (where ss2.sector is not null) as sector_exposure,
  (case when sum(pa.cash_balance_minor_units) > 0 then
     round((max(pa.cash_balance_minor_units)::numeric
       / sum(pa.cash_balance_minor_units)::numeric) * 100, 2)::text || '%'
   else null end) as cash_concentration_ratio
from public.investment_portfolios pf2
left join projects_asof pa
  on pa.organization_id = pf2.organization_id
left join sector_stats2 ss2
  on ss2.currency = pa.currency and ss2.sector = pa.sector
where pf2.id = p_portfolio_id and pf2.organization_id = p_organization_id
group by pa.organization_id, pf2.name, pa.currency, pa.org_reporting_currency;
$$;
  $widen_ddl$;
end
$widen$;

-- ===========================================================================
-- 7. RLS / grants. Browser users read authorized tenant facts; all writes go
--    through the two command RPCs above.
-- ===========================================================================
alter table public.customer_invoices enable row level security;
alter table public.customer_invoices force row level security;
alter table public.customer_invoice_collections enable row level security;
alter table public.customer_invoice_collections force row level security;

create policy customer_invoices_read
  on public.customer_invoices for select to authenticated
  using (public.is_active_member(organization_id));
create policy customer_invoice_collections_read
  on public.customer_invoice_collections for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.customer_invoices from public,anon,authenticated;
revoke all on public.customer_invoice_collections from public,anon,authenticated;
grant select on public.customer_invoices,public.customer_invoice_collections to authenticated;

revoke all on public.customer_invoices_read,public.customer_invoice_collections_read from public,anon;
grant select on public.customer_invoices_read,public.customer_invoice_collections_read to authenticated;

revoke all on function public.issue_customer_invoice(uuid,uuid,uuid,text,text,bigint,date,text,text) from public,anon;
revoke all on function public.collect_customer_invoice(uuid,uuid,uuid,bigint,date,text,text) from public,anon;
grant execute on function public.issue_customer_invoice(uuid,uuid,uuid,text,text,bigint,date,text,text),
  public.collect_customer_invoice(uuid,uuid,uuid,bigint,date,text,text) to authenticated;

-- Trigger helpers are not browser command surfaces.
revoke all on function public.ci_guard_invoice_insert(),public.ci_guard_collection_insert() from public,anon,authenticated;
