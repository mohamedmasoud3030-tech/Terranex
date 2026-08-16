-- R5 target-company gap — basic held-property rental income.
--
-- This is deliberately NOT lease/property-management ERP. It records only the
-- investment-operating facts authorized by the Greenfield sector model:
--   held property + counterparty + contract/evidence + rental period
--   -> recognized rental revenue + receivable
--   -> cash collection
--   -> bank-statement reconciliation.
-- Posted money remains in the shared Project Financial Subledger. No rent roll,
-- lease administration, maintenance, tenant portal, deposits, escalations or
-- statutory lease-accounting policy is introduced here.

-- ===========================================================================
-- 1. Extend the locked shared Finance registries with a distinct rental role
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','PREPAID_ASSET',
  'REAL_ESTATE_RENTAL_REVENUE'
));
insert into public.semantic_accounts(role,label_ar)
values ('REAL_ESTATE_RENTAL_REVENUE','إيراد إيجار عقاري')
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
  'PROPERTY_RENTAL_RECOGNITION','PROPERTY_RENTAL_COLLECTION'
));

-- Rental collections participate in the existing cross-type one-bank-line
-- reservation primitive, so the same bank line can never satisfy a payment,
-- property sale collection and rental collection concurrently.
alter table public.bank_statement_reconciliation_allocations
  drop constraint if exists bank_statement_reconciliation_allocations_match_type_check;
alter table public.bank_statement_reconciliation_allocations
  add constraint bank_statement_reconciliation_allocations_match_type_check check (match_type in (
    'PAYMENT','PROPERTY_SALE_COLLECTION','PROPERTY_RENTAL_COLLECTION'
  ));

-- ===========================================================================
-- 2. Small hash helper that does not assume where pgcrypto is installed
-- ===========================================================================
create or replace function public.r5_sha256(p_payload text) returns text
language plpgsql stable set search_path=pg_catalog,public as $$
declare v_schema text; v_result text;
begin
  select n.nspname into v_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';
  if v_schema is null then raise exception 'R5 rental income requires pgcrypto'; end if;
  execute format('select encode(%I.digest($1,''sha256''),''hex'')',v_schema)
    into v_result using p_payload;
  return v_result;
end $$;
revoke all on function public.r5_sha256(text) from public,anon,authenticated;

-- ===========================================================================
-- 3. Append-only rental recognition / collection / reconciliation facts
-- ===========================================================================
create table public.property_rental_income_recognitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  tenant_party_id uuid not null,
  contract_reference text not null check (char_length(trim(contract_reference)) between 2 and 160),
  rental_period_start date not null,
  rental_period_end date not null,
  recognized_amount_minor_units bigint not null check (recognized_amount_minor_units>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  recognition_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  business_key_hash text not null check (char_length(business_key_hash)=64),
  revision_no integer not null check (revision_no>0),
  replaces_recognition_id uuid,
  recognized_by uuid not null references auth.users(id) on delete restrict,
  recognized_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  check (rental_period_end>=rental_period_start),
  check (recognition_date>=rental_period_start),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  unique (organization_id,idempotency_key),
  unique (organization_id,business_key_hash,revision_no),
  unique (journal_batch_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (property_asset_id,organization_id,project_id)
    references public.property_assets(id,organization_id,project_id) on delete restrict,
  foreign key (tenant_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (replaces_recognition_id,organization_id,project_id)
    references public.property_rental_income_recognitions(id,organization_id,project_id) on delete restrict
);
create index property_rental_recognitions_project_idx
  on public.property_rental_income_recognitions(project_id,recognition_date desc);
create index property_rental_recognitions_property_idx
  on public.property_rental_income_recognitions(property_asset_id,rental_period_start desc);

create table public.property_rental_collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  recognition_id uuid not null,
  cash_account_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  collection_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  collected_by uuid not null references auth.users(id) on delete restrict,
  collected_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  foreign key (recognition_id,organization_id,project_id)
    references public.property_rental_income_recognitions(id,organization_id,project_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index property_rental_collections_recognition_idx
  on public.property_rental_collections(recognition_id,collection_date);

create table public.property_rental_collection_reconciliations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  collection_id uuid not null,
  statement_line_id uuid not null,
  cash_account_id uuid not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  matched_by uuid not null references auth.users(id) on delete restrict,
  matched_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (id,organization_id),
  unique (organization_id,idempotency_key),
  unique (collection_id),
  unique (statement_line_id),
  foreign key (collection_id,organization_id,project_id)
    references public.property_rental_collections(id,organization_id,project_id) on delete restrict,
  foreign key (statement_line_id,organization_id)
    references public.bank_statement_lines(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);

-- ===========================================================================
-- 4. Database invariants: journal coherence, duplicate-period revisioning,
--    collection ceiling, append-only truth and reversal dependency ordering
-- ===========================================================================
create or replace function public.r5_guard_rental_recognition_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_expected_key text; v_expected_revision integer; v_latest record;
  v_project_currency text; v_state text; v_batch record;
  v_line_count integer; v_receivable_count integer; v_revenue_count integer;
begin
  v_expected_key:=public.r5_sha256(jsonb_build_object(
    'property_asset_id',new.property_asset_id,
    'tenant_party_id',new.tenant_party_id,
    'contract_reference',lower(trim(new.contract_reference)),
    'rental_period_start',new.rental_period_start,
    'rental_period_end',new.rental_period_end
  )::text);
  if new.business_key_hash<>v_expected_key then
    raise exception 'rental recognition business key mismatch';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    new.organization_id::text||':r5-rental-business:'||v_expected_key,0));

  select r.id,r.revision_no,r.journal_batch_id into v_latest
  from public.property_rental_income_recognitions r
  where r.organization_id=new.organization_id and r.business_key_hash=v_expected_key
  order by r.revision_no desc limit 1;
  if found then
    if not exists(select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id=v_latest.journal_batch_id) then
      raise exception 'active rental recognition already exists for this contract period';
    end if;
    v_expected_revision:=v_latest.revision_no+1;
    if new.replaces_recognition_id is distinct from v_latest.id then
      raise exception 'replacement rental recognition must link the reversed prior revision';
    end if;
  else
    v_expected_revision:=1;
    if new.replaces_recognition_id is not null then
      raise exception 'first rental recognition revision cannot replace another recognition';
    end if;
  end if;
  if new.revision_no<>v_expected_revision then
    raise exception 'rental recognition revision is not the next append-only revision';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id=new.project_id and organization_id=new.organization_id and sector='REAL_ESTATE';
  if v_project_currency is null or v_project_currency<>new.currency then
    raise exception 'rental recognition must use the real-estate project reporting currency';
  end if;
  if not exists(select 1 from public.property_assets a
    where a.id=new.property_asset_id and a.organization_id=new.organization_id
      and a.project_id=new.project_id) then
    raise exception 'rental property must belong to the same organization and project';
  end if;
  if not exists(select 1 from public.parties p
    where p.id=new.tenant_party_id and p.organization_id=new.organization_id) then
    raise exception 'rental counterparty must belong to the same organization';
  end if;
  v_state:=public.s3_current_property_state(new.property_asset_id);
  if v_state is distinct from 'HELD' then
    raise exception 'rental income requires a property in HELD state';
  end if;

  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id;
  if not found or v_batch.project_id<>new.project_id
     or v_batch.source_type<>'PROPERTY_RENTAL_RECOGNITION'
     or v_batch.source_id<>new.id or v_batch.transaction_date<>new.recognition_date
     or v_batch.reversal_of_batch_id is not null then
    raise exception 'rental recognition journal source mismatch';
  end if;
  select count(*),
    count(*) filter(where sa.role='CUSTOMER_RECEIVABLE'
      and jl.debit_minor_units=new.recognized_amount_minor_units and jl.credit_minor_units=0
      and jl.currency=new.currency and jl.party_id=new.tenant_party_id),
    count(*) filter(where sa.role='REAL_ESTATE_RENTAL_REVENUE'
      and jl.credit_minor_units=new.recognized_amount_minor_units and jl.debit_minor_units=0
      and jl.currency=new.currency and jl.party_id=new.tenant_party_id)
    into v_line_count,v_receivable_count,v_revenue_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id;
  if v_line_count<>2 or v_receivable_count<>1 or v_revenue_count<>1 then
    raise exception 'rental recognition journal must be exact receivable/revenue pair';
  end if;
  return new;
end $$;
create trigger property_rental_recognition_insert_guard
before insert on public.property_rental_income_recognitions
for each row execute function public.r5_guard_rental_recognition_insert();

create or replace function public.r5_guard_rental_collection_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_rec public.property_rental_income_recognitions%rowtype; v_cash record; v_batch record;
  v_collected numeric; v_line_count integer; v_cash_count integer; v_receivable_count integer;
begin
  select * into v_rec from public.property_rental_income_recognitions
  where id=new.recognition_id and organization_id=new.organization_id
    and project_id=new.project_id for update;
  if not found then raise exception 'rental recognition not found'; end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_rec.journal_batch_id) then
    raise exception 'cannot collect a reversed rental recognition';
  end if;
  if new.currency<>v_rec.currency or new.collection_date<v_rec.recognition_date then
    raise exception 'rental collection currency/date does not match recognition';
  end if;
  select id,project_id,currency into v_cash from public.project_cash_accounts
  where id=new.cash_account_id and organization_id=new.organization_id;
  if not found or v_cash.project_id<>new.project_id or v_cash.currency<>new.currency then
    raise exception 'rental collection cash account must belong to the same project and currency';
  end if;

  select coalesce(sum(c.amount_minor_units),0) into v_collected
  from public.property_rental_collections c
  join public.journal_batches jb on jb.id=c.journal_batch_id
  where c.recognition_id=new.recognition_id
    and jb.reversal_of_batch_id is null
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id);
  if v_collected+new.amount_minor_units>v_rec.recognized_amount_minor_units then
    raise exception 'rental collection exceeds outstanding receivable';
  end if;

  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id;
  if not found or v_batch.project_id<>new.project_id
     or v_batch.source_type<>'PROPERTY_RENTAL_COLLECTION'
     or v_batch.source_id<>new.id or v_batch.transaction_date<>new.collection_date
     or v_batch.reversal_of_batch_id is not null then
    raise exception 'rental collection journal source mismatch';
  end if;
  select count(*),
    count(*) filter(where sa.role='BANK_CASH'
      and jl.debit_minor_units=new.amount_minor_units and jl.credit_minor_units=0
      and jl.currency=new.currency and jl.cash_account_id=new.cash_account_id),
    count(*) filter(where sa.role='CUSTOMER_RECEIVABLE'
      and jl.credit_minor_units=new.amount_minor_units and jl.debit_minor_units=0
      and jl.currency=new.currency and jl.party_id=v_rec.tenant_party_id)
    into v_line_count,v_cash_count,v_receivable_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id;
  if v_line_count<>2 or v_cash_count<>1 or v_receivable_count<>1 then
    raise exception 'rental collection journal must be exact cash/receivable pair';
  end if;
  return new;
end $$;
create trigger property_rental_collection_insert_guard
before insert on public.property_rental_collections
for each row execute function public.r5_guard_rental_collection_insert();

create trigger property_rental_recognitions_append_only
before update or delete on public.property_rental_income_recognitions
for each row execute function public.s2_guard_append_only();
create trigger property_rental_collections_append_only
before update or delete on public.property_rental_collections
for each row execute function public.s2_guard_append_only();
create trigger property_rental_reconciliations_append_only
before update or delete on public.property_rental_collection_reconciliations
for each row execute function public.s2_guard_append_only();

create or replace function public.r5_reserve_rental_statement_line() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  insert into public.bank_statement_reconciliation_allocations(
    statement_line_id,organization_id,match_type,match_id
  ) values(new.statement_line_id,new.organization_id,'PROPERTY_RENTAL_COLLECTION',new.id);
  return new;
end $$;
create trigger property_rental_reconciliation_reserve_statement
before insert on public.property_rental_collection_reconciliations
for each row execute function public.r5_reserve_rental_statement_line();

create or replace function public.r5_guard_rental_reversal_dependency() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_original record;
begin
  if new.reversal_of_batch_id is null then return new; end if;
  select source_type,source_id into v_original from public.journal_batches
  where id=new.reversal_of_batch_id and organization_id=new.organization_id;
  if not found then return new; end if;
  if v_original.source_type='PROPERTY_RENTAL_RECOGNITION' and exists(
    select 1 from public.property_rental_collections c
    join public.journal_batches cb on cb.id=c.journal_batch_id
    where c.recognition_id=v_original.source_id
      and cb.reversal_of_batch_id is null
      and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)
  ) then
    raise exception 'reverse active rental collections before reversing rental recognition';
  end if;
  if v_original.source_type='PROPERTY_RENTAL_COLLECTION' and exists(
    select 1 from public.property_rental_collection_reconciliations r
    where r.collection_id=v_original.source_id
  ) then
    raise exception 'reconciled rental collection cannot be reversed';
  end if;
  return new;
end $$;
create trigger journal_batches_rental_reversal_dependency
before insert on public.journal_batches
for each row execute function public.r5_guard_rental_reversal_dependency();

-- ===========================================================================
-- 5. Material command RPCs
-- ===========================================================================
create or replace function public.recognize_property_rental_income(
  p_organization_id uuid,p_project_id uuid,p_property_asset_id uuid,p_tenant_party_id uuid,
  p_contract_reference text,p_rental_period_start date,p_rental_period_end date,
  p_amount_minor_units bigint,p_currency text,p_recognition_date date,
  p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_hash text; v_business_key text; v_existing record; v_latest record;
  v_project_currency text; v_recognition_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_receivable uuid; v_revenue uuid; v_revision integer; v_replaces uuid; v_state text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_contract_reference is null or char_length(trim(p_contract_reference)) not between 2 and 160 then raise exception 'rental contract reference required'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'rental evidence required'; end if;
  if p_rental_period_start is null or p_rental_period_end is null or p_rental_period_end<p_rental_period_start then raise exception 'invalid rental period'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'rental amount must be positive'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid rental currency'; end if;
  if p_recognition_date is null or p_recognition_date<p_rental_period_start or p_recognition_date>current_date then raise exception 'rental recognition date must be effective and not precede the rental period'; end if;

  select reporting_currency into v_project_currency from public.investment_projects
  where id=p_project_id and organization_id=p_organization_id and sector='REAL_ESTATE';
  if v_project_currency is null then raise exception 'real-estate project not found'; end if;
  if p_currency<>v_project_currency then raise exception 'rental currency must match project reporting currency'; end if;
  if not exists(select 1 from public.property_assets where id=p_property_asset_id
    and organization_id=p_organization_id and project_id=p_project_id) then
    raise exception 'rental property not found in project';
  end if;
  v_state:=public.s3_current_property_state(p_property_asset_id);
  if v_state is distinct from 'HELD' then raise exception 'rental income requires a property in HELD state'; end if;
  if not exists(select 1 from public.parties where id=p_tenant_party_id and organization_id=p_organization_id) then
    raise exception 'rental counterparty not found';
  end if;

  v_business_key:=public.r5_sha256(jsonb_build_object(
    'property_asset_id',p_property_asset_id,'tenant_party_id',p_tenant_party_id,
    'contract_reference',lower(trim(p_contract_reference)),
    'rental_period_start',p_rental_period_start,'rental_period_end',p_rental_period_end
  )::text);
  v_hash:=public.r5_sha256(jsonb_build_object(
    'project_id',p_project_id,'property_asset_id',p_property_asset_id,'tenant_party_id',p_tenant_party_id,
    'contract_reference',trim(p_contract_reference),'rental_period_start',p_rental_period_start,
    'rental_period_end',p_rental_period_end,'amount_minor_units',p_amount_minor_units,
    'currency',p_currency,'recognition_date',p_recognition_date,
    'evidence_reference',trim(p_evidence_reference)
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r5-rental-recognize:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_rental_income_recognitions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r5-rental-business:'||v_business_key,0));
  select r.* into v_latest from public.property_rental_income_recognitions r
  where r.organization_id=p_organization_id and r.business_key_hash=v_business_key
  order by r.revision_no desc limit 1;
  if found then
    if not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_latest.journal_batch_id) then
      raise exception 'active rental recognition already exists for this contract period';
    end if;
    v_revision:=v_latest.revision_no+1; v_replaces:=v_latest.id;
  else
    v_revision:=1; v_replaces:=null;
  end if;

  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  select id into v_revenue from public.semantic_accounts where role='REAL_ESTATE_RENTAL_REVENUE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,p_project_id,'PROPERTY_RENTAL_RECOGNITION',v_recognition_id,
    p_recognition_date,'r5-rental-recognition-batch-'||v_recognition_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,p_project_id,v_receivable,p_amount_minor_units,0,p_currency,p_tenant_party_id,p_recognition_date),
    (v_batch_id,p_organization_id,p_project_id,v_revenue,0,p_amount_minor_units,p_currency,p_tenant_party_id,p_recognition_date);
  insert into public.property_rental_income_recognitions(
    id,organization_id,project_id,property_asset_id,tenant_party_id,contract_reference,
    rental_period_start,rental_period_end,recognized_amount_minor_units,currency,recognition_date,
    evidence_reference,journal_batch_id,business_key_hash,revision_no,replaces_recognition_id,
    recognized_by,idempotency_key,request_hash
  ) values(
    v_recognition_id,p_organization_id,p_project_id,p_property_asset_id,p_tenant_party_id,
    trim(p_contract_reference),p_rental_period_start,p_rental_period_end,p_amount_minor_units,p_currency,
    p_recognition_date,trim(p_evidence_reference),v_batch_id,v_business_key,v_revision,v_replaces,
    v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_RENTAL_INCOME_RECOGNIZED','property_rental_income_recognition',v_recognition_id,
    jsonb_build_object('project_id',p_project_id,'property_asset_id',p_property_asset_id,
      'tenant_party_id',p_tenant_party_id,'rental_period_start',p_rental_period_start,
      'rental_period_end',p_rental_period_end,'amount_minor_units',p_amount_minor_units,
      'currency',p_currency,'journal_batch_id',v_batch_id,'revision_no',v_revision));
  return v_recognition_id;
end $$;

create or replace function public.collect_property_rental_receivable(
  p_organization_id uuid,p_recognition_id uuid,p_cash_account_id uuid,
  p_amount_minor_units bigint,p_collection_date date,p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_rec public.property_rental_income_recognitions%rowtype;
  v_existing record; v_hash text; v_collection_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_cash_account record; v_cash uuid; v_receivable uuid; v_collected numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'rental collection amount must be positive'; end if;
  if p_collection_date is null or p_collection_date>current_date then raise exception 'rental collection date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'rental collection evidence required'; end if;
  v_hash:=public.r5_sha256(jsonb_build_object(
    'recognition_id',p_recognition_id,'cash_account_id',p_cash_account_id,
    'amount_minor_units',p_amount_minor_units,'collection_date',p_collection_date,
    'evidence_reference',trim(p_evidence_reference)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r5-rental-collection:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_rental_collections
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.recognition_id<>p_recognition_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_rec from public.property_rental_income_recognitions
  where id=p_recognition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'rental recognition not found'; end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_rec.journal_batch_id) then
    raise exception 'cannot collect a reversed rental recognition';
  end if;
  if p_collection_date<v_rec.recognition_date then raise exception 'rental collection cannot precede recognition'; end if;
  select id,project_id,currency into v_cash_account from public.project_cash_accounts
  where id=p_cash_account_id and organization_id=p_organization_id;
  if not found or v_cash_account.project_id<>v_rec.project_id or v_cash_account.currency<>v_rec.currency then
    raise exception 'rental collection cash account must belong to the same project and currency';
  end if;
  select coalesce(sum(c.amount_minor_units),0) into v_collected
  from public.property_rental_collections c
  join public.journal_batches jb on jb.id=c.journal_batch_id
  where c.recognition_id=p_recognition_id
    and jb.reversal_of_batch_id is null
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id);
  if v_collected+p_amount_minor_units>v_rec.recognized_amount_minor_units then
    raise exception 'rental collection exceeds outstanding receivable';
  end if;

  select id into v_cash from public.semantic_accounts where role='BANK_CASH';
  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_rec.project_id,'PROPERTY_RENTAL_COLLECTION',v_collection_id,
    p_collection_date,'r5-rental-collection-batch-'||v_collection_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,cash_account_id,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_rec.project_id,v_cash,p_amount_minor_units,0,v_rec.currency,p_cash_account_id,null,p_collection_date),
    (v_batch_id,p_organization_id,v_rec.project_id,v_receivable,0,p_amount_minor_units,v_rec.currency,null,v_rec.tenant_party_id,p_collection_date);
  insert into public.property_rental_collections(
    id,organization_id,project_id,recognition_id,cash_account_id,amount_minor_units,currency,
    collection_date,evidence_reference,journal_batch_id,collected_by,idempotency_key,request_hash
  ) values(
    v_collection_id,p_organization_id,v_rec.project_id,p_recognition_id,p_cash_account_id,
    p_amount_minor_units,v_rec.currency,p_collection_date,trim(p_evidence_reference),v_batch_id,
    v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_RENTAL_COLLECTION_POSTED','property_rental_collection',v_collection_id,
    jsonb_build_object('project_id',v_rec.project_id,'property_asset_id',v_rec.property_asset_id,
      'recognition_id',p_recognition_id,'cash_account_id',p_cash_account_id,
      'amount_minor_units',p_amount_minor_units,'currency',v_rec.currency,'journal_batch_id',v_batch_id));
  return v_collection_id;
end $$;

create or replace function public.reconcile_property_rental_collection(
  p_organization_id uuid,p_collection_id uuid,p_statement_line_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_collection public.property_rental_collections%rowtype;
  v_line record; v_existing record; v_hash text; v_id uuid:=gen_random_uuid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=public.r5_sha256(p_collection_id::text||'|'||p_statement_line_id::text);
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r5-rental-reconcile:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_rental_collection_reconciliations
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.collection_id<>p_collection_id or v_existing.statement_line_id<>p_statement_line_id
       or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_collection from public.property_rental_collections
  where id=p_collection_id and organization_id=p_organization_id for update;
  if not found then raise exception 'rental collection not found'; end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_collection.journal_batch_id) then
    raise exception 'reversed rental collection cannot be reconciled';
  end if;
  select * into v_line from public.bank_statement_lines
  where id=p_statement_line_id and organization_id=p_organization_id for update;
  if not found then raise exception 'bank statement line not found'; end if;
  if v_line.project_id<>v_collection.project_id or v_line.cash_account_id<>v_collection.cash_account_id
     or v_line.currency<>v_collection.currency then
    raise exception 'rental collection and bank line must use the same project cash account and currency';
  end if;
  if v_line.amount_minor_units<>v_collection.amount_minor_units or v_line.amount_minor_units<=0 then
    raise exception 'positive bank statement amount must equal the rental collection';
  end if;
  insert into public.property_rental_collection_reconciliations(
    id,organization_id,project_id,collection_id,statement_line_id,cash_account_id,currency,
    matched_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,v_collection.project_id,p_collection_id,p_statement_line_id,
    v_collection.cash_account_id,v_collection.currency,v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_RENTAL_COLLECTION_RECONCILED','property_rental_collection_reconciliation',v_id,
    jsonb_build_object('project_id',v_collection.project_id,'collection_id',p_collection_id,
      'statement_line_id',p_statement_line_id,'accounting_effect','NONE'));
  return v_id;
end $$;

-- ===========================================================================
-- 6. Read models. Reversals stay visible as history but never count as active
-- ===========================================================================
create or replace view public.property_rental_income_read with (security_invoker=on) as
select
  r.id as recognition_id,r.organization_id,r.project_id,r.property_asset_id,r.tenant_party_id,
  r.contract_reference,r.rental_period_start,r.rental_period_end,
  r.recognized_amount_minor_units::text as recognized_amount_minor_units,r.currency,
  r.recognition_date,r.evidence_reference,r.journal_batch_id,r.revision_no,r.replaces_recognition_id,
  r.recognized_by,r.recognized_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=r.journal_batch_id) as is_reversed,
  coalesce((select sum(c.amount_minor_units) from public.property_rental_collections c
    join public.journal_batches cb on cb.id=c.journal_batch_id
    where c.recognition_id=r.id and cb.reversal_of_batch_id is null
      and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0)::text
    as collected_minor_units,
  (case when exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=r.journal_batch_id)
    then 0 else r.recognized_amount_minor_units-coalesce((select sum(c.amount_minor_units)
      from public.property_rental_collections c join public.journal_batches cb on cb.id=c.journal_batch_id
      where c.recognition_id=r.id and cb.reversal_of_batch_id is null
        and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0) end)::text
    as outstanding_receivable_minor_units,
  current_date as as_of_date
from public.property_rental_income_recognitions r;

create or replace view public.property_rental_collections_read with (security_invoker=on) as
select
  c.id as collection_id,c.organization_id,c.project_id,c.recognition_id,c.cash_account_id,
  c.amount_minor_units::text as amount_minor_units,c.currency,c.collection_date,c.evidence_reference,
  c.journal_batch_id,c.collected_by,c.collected_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=c.journal_batch_id) as is_reversed,
  (rr.id is not null) as is_reconciled,rr.id as reconciliation_id,rr.statement_line_id,rr.matched_at
from public.property_rental_collections c
left join public.property_rental_collection_reconciliations rr on rr.collection_id=c.id;

-- F9/F10/R8 must see rent as recognized Project revenue. Keep every existing
-- F9 column and reversal rule; only the revenue-role set is widened.
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
      'REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_RENTAL_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE'
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

-- ===========================================================================
-- 7. RLS / grants. Browser users can read authorized tenant facts; all writes
--    go through the three material command RPCs above.
-- ===========================================================================
alter table public.property_rental_income_recognitions enable row level security;
alter table public.property_rental_income_recognitions force row level security;
alter table public.property_rental_collections enable row level security;
alter table public.property_rental_collections force row level security;
alter table public.property_rental_collection_reconciliations enable row level security;
alter table public.property_rental_collection_reconciliations force row level security;

create policy property_rental_income_recognitions_read
  on public.property_rental_income_recognitions for select to authenticated
  using (public.is_active_member(organization_id));
create policy property_rental_collections_read_policy
  on public.property_rental_collections for select to authenticated
  using (public.is_active_member(organization_id));
create policy property_rental_collection_reconciliations_read
  on public.property_rental_collection_reconciliations for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.property_rental_income_recognitions from public,anon,authenticated;
revoke all on public.property_rental_collections from public,anon,authenticated;
revoke all on public.property_rental_collection_reconciliations from public,anon,authenticated;
grant select on public.property_rental_income_recognitions,public.property_rental_collections,
  public.property_rental_collection_reconciliations to authenticated;

revoke all on public.property_rental_income_read,public.property_rental_collections_read from public,anon;
grant select on public.property_rental_income_read,public.property_rental_collections_read to authenticated;

revoke all on function public.recognize_property_rental_income(
  uuid,uuid,uuid,uuid,text,date,date,bigint,text,date,text,text
) from public,anon;
revoke all on function public.collect_property_rental_receivable(
  uuid,uuid,uuid,bigint,date,text,text
) from public,anon;
revoke all on function public.reconcile_property_rental_collection(
  uuid,uuid,uuid,text
) from public,anon;
grant execute on function public.recognize_property_rental_income(
  uuid,uuid,uuid,uuid,text,date,date,bigint,text,date,text,text
),public.collect_property_rental_receivable(uuid,uuid,uuid,bigint,date,text,text),
  public.reconcile_property_rental_collection(uuid,uuid,uuid,text)
to authenticated;

-- Trigger helpers are not browser command surfaces.
revoke all on function public.r5_guard_rental_recognition_insert(),
  public.r5_guard_rental_collection_insert(),public.r5_reserve_rental_statement_line(),
  public.r5_guard_rental_reversal_dependency() from public,anon,authenticated;
