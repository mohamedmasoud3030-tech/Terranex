-- GF-018 / Agriculture Sale, Dispatch & Revenue.
--
-- Extends GF-016 physical harvest output to an evidence-backed commercial
-- event and reuses the canonical S2/S4 journal, receivable, cash-account and
-- period-lock core. Sale agreement, physical SALE_ISSUE, control transfer,
-- revenue, receivable and collection remain separate facts. No Agriculture
-- ledger, payment engine, guessed inventory valuation, COGS or mutable stock
-- balance is introduced.

-- ===========================================================================
-- 1. Extend locked shared-core account/source registries
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE'
));
insert into public.semantic_accounts(role,label_ar)
values ('AGRICULTURE_SALE_REVENUE','إيراد بيع زراعي')
on conflict (role) do nothing;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT','AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION'
));

-- ===========================================================================
-- 2. Agriculture sale aggregate: one header with one or more immutable lines
-- ===========================================================================
create table public.agriculture_sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  buyer_party_id uuid not null,
  sale_reference text not null check (char_length(trim(sale_reference)) between 1 and 120),
  agreement_reference text check (agreement_reference is null or char_length(trim(agreement_reference)) between 2 and 200),
  sale_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  terms text check (terms is null or char_length(trim(terms)) between 2 and 1000),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','CONTROL_TRANSFERRED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash)=64),
  control_transfer_date date,
  control_transfer_evidence_reference text check (
    control_transfer_evidence_reference is null
    or char_length(trim(control_transfer_evidence_reference)) between 3 and 200
  ),
  control_transferred_by uuid references auth.users(id) on delete restrict,
  control_transferred_at timestamptz,
  transfer_idempotency_key text check (transfer_idempotency_key is null or char_length(transfer_idempotency_key) between 8 and 120),
  transfer_request_hash text check (transfer_request_hash is null or char_length(transfer_request_hash)=64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  check (
    (status='DRAFT' and approved_by is null and approved_at is null
      and approval_idempotency_key is null and approval_request_hash is null
      and control_transfer_date is null and control_transfer_evidence_reference is null
      and control_transferred_by is null and control_transferred_at is null
      and transfer_idempotency_key is null and transfer_request_hash is null)
    or
    (status='APPROVED' and approved_by is not null and approved_at is not null
      and approval_idempotency_key is not null and approval_request_hash is not null
      and control_transfer_date is null and control_transfer_evidence_reference is null
      and control_transferred_by is null and control_transferred_at is null
      and transfer_idempotency_key is null and transfer_request_hash is null)
    or
    (status='CONTROL_TRANSFERRED' and approved_by is not null and approved_at is not null
      and approval_idempotency_key is not null and approval_request_hash is not null
      and control_transfer_date is not null and control_transfer_date>=sale_date
      and control_transfer_evidence_reference is not null
      and control_transferred_by is not null and control_transferred_at is not null
      and transfer_idempotency_key is not null and transfer_request_hash is not null)
  ),
  unique (id,organization_id,project_id),
  unique (organization_id,idempotency_key),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (buyer_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict
);
create unique index agriculture_sales_project_reference_key
  on public.agriculture_sales(organization_id,project_id,lower(sale_reference));
create unique index agriculture_sales_approval_key
  on public.agriculture_sales(organization_id,approval_idempotency_key)
  where approval_idempotency_key is not null;
create unique index agriculture_sales_transfer_key
  on public.agriculture_sales(organization_id,transfer_idempotency_key)
  where transfer_idempotency_key is not null;
create index agriculture_sales_project_idx on public.agriculture_sales(project_id,sale_date desc);

create table public.agriculture_sale_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  sale_id uuid not null,
  line_no integer not null check (line_no>0),
  harvest_lot_id uuid not null,
  source_storage_id uuid not null,
  quantity numeric(20,6) not null check (quantity>0),
  unit text not null check (char_length(trim(unit)) between 1 and 40),
  unit_price_minor_units bigint not null check (unit_price_minor_units>0),
  line_amount_minor_units bigint not null check (line_amount_minor_units>0),
  constraint agriculture_sale_lines_amount_matches
    check (line_amount_minor_units::numeric=quantity*unit_price_minor_units::numeric),
  unique (sale_id,line_no),
  unique (sale_id,harvest_lot_id,source_storage_id),
  unique (id,organization_id,project_id),
  unique (id,organization_id,project_id,harvest_lot_id,source_storage_id,quantity,unit),
  foreign key (sale_id,organization_id,project_id)
    references public.agriculture_sales(id,organization_id,project_id) on delete restrict,
  foreign key (harvest_lot_id,organization_id,project_id,unit)
    references public.harvest_lots(id,organization_id,project_id,quantity_unit) on delete restrict,
  foreign key (source_storage_id,organization_id,project_id)
    references public.storage_locations(id,organization_id,project_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index agriculture_sale_lines_sale_idx on public.agriculture_sale_lines(sale_id);
create index agriculture_sale_lines_lot_idx on public.agriculture_sale_lines(harvest_lot_id);

create table public.agriculture_sale_recognitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  sale_id uuid not null,
  recognized_revenue_minor_units bigint not null check (recognized_revenue_minor_units>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  recognition_date date not null,
  journal_batch_id uuid not null,
  recognized_by uuid not null references auth.users(id) on delete restrict,
  recognized_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (sale_id),
  unique (journal_batch_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id,project_id),
  foreign key (sale_id,organization_id,project_id)
    references public.agriculture_sales(id,organization_id,project_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index agriculture_sale_recognitions_project_idx
  on public.agriculture_sale_recognitions(project_id,recognition_date desc);

create table public.agriculture_sale_collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  recognition_id uuid not null,
  sale_id uuid not null,
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
  unique (journal_batch_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id,project_id),
  foreign key (recognition_id,organization_id,project_id)
    references public.agriculture_sale_recognitions(id,organization_id,project_id) on delete restrict,
  foreign key (sale_id,organization_id,project_id)
    references public.agriculture_sales(id,organization_id,project_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index agriculture_sale_collections_recognition_idx
  on public.agriculture_sale_collections(recognition_id,collection_date);

-- ===========================================================================
-- 3. Add SALE_ISSUE to GF-016 append-only physical movement truth
-- ===========================================================================
alter table public.harvest_inventory_movements
  add column agriculture_sale_line_id uuid;
alter table public.harvest_inventory_movements
  drop constraint harvest_inventory_movements_movement_type_check;
alter table public.harvest_inventory_movements
  add constraint harvest_inventory_movements_movement_type_check check (movement_type in (
    'HARVEST_RECEIPT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','SPOILAGE','SALE_ISSUE'
  ));
alter table public.harvest_inventory_movements
  drop constraint harvest_inventory_movements_check;
alter table public.harvest_inventory_movements
  add constraint harvest_inventory_movements_check check (
    (movement_type='HARVEST_RECEIPT' and from_storage_id is null and to_storage_id is not null)
    or (movement_type='TRANSFER' and from_storage_id is not null and to_storage_id is not null and from_storage_id<>to_storage_id)
    or (movement_type='ADJUSTMENT_IN' and from_storage_id is null and to_storage_id is not null)
    or (movement_type in ('ADJUSTMENT_OUT','SPOILAGE','SALE_ISSUE') and from_storage_id is not null and to_storage_id is null)
  );
alter table public.harvest_inventory_movements
  add constraint harvest_inventory_movements_sale_line_presence check (
    (movement_type='SALE_ISSUE')=(agriculture_sale_line_id is not null)
  );
alter table public.harvest_inventory_movements
  add constraint harvest_inventory_movements_sale_line_scope_fk
  foreign key (
    agriculture_sale_line_id,organization_id,project_id,harvest_lot_id,
    from_storage_id,quantity,unit
  ) references public.agriculture_sale_lines(
    id,organization_id,project_id,harvest_lot_id,source_storage_id,quantity,unit
  ) on delete restrict;
create unique index harvest_inventory_movements_one_sale_issue_per_line
  on public.harvest_inventory_movements(agriculture_sale_line_id)
  where movement_type='SALE_ISSUE';

-- ===========================================================================
-- 4. Cross-fact integrity, immutability and controlled header transitions
-- ===========================================================================
create or replace function public.gf018_guard_sale_line_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_status text;
begin
  select status into v_status from public.agriculture_sales
  where id=new.sale_id and organization_id=new.organization_id and project_id=new.project_id;
  if v_status is distinct from 'DRAFT' then
    raise exception 'agriculture sale lines may only be added while the sale is draft';
  end if;
  return new;
end $$;
create trigger agriculture_sale_lines_insert_guard
before insert on public.agriculture_sale_lines
for each row execute function public.gf018_guard_sale_line_insert();

create or replace function public.gf018_guard_recognition_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_sale public.agriculture_sales%rowtype; v_batch public.journal_batches%rowtype;
  v_total numeric; v_line_count integer; v_receivable_count integer; v_revenue_count integer;
begin
  select * into v_sale from public.agriculture_sales
  where id=new.sale_id and organization_id=new.organization_id and project_id=new.project_id
  for update;
  if not found or v_sale.status<>'APPROVED' or new.currency<>v_sale.currency
     or new.recognition_date<v_sale.sale_date then
    raise exception 'agriculture sale recognition does not match the approved sale';
  end if;
  select sum(line_amount_minor_units::numeric) into v_total
  from public.agriculture_sale_lines where sale_id=new.sale_id;
  if v_total is null or v_total<>new.recognized_revenue_minor_units then
    raise exception 'agriculture sale recognition total does not match immutable lines';
  end if;
  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id;
  if not found or v_batch.project_id<>new.project_id
     or v_batch.source_type<>'AGRICULTURE_SALE_RECOGNITION'
     or v_batch.source_id<>new.id or v_batch.transaction_date<>new.recognition_date then
    raise exception 'agriculture sale recognition journal source mismatch';
  end if;
  select count(*),
    count(*) filter(where sa.role='CUSTOMER_RECEIVABLE'
      and jl.debit_minor_units=new.recognized_revenue_minor_units and jl.credit_minor_units=0
      and jl.currency=new.currency and jl.party_id=v_sale.buyer_party_id),
    count(*) filter(where sa.role='AGRICULTURE_SALE_REVENUE'
      and jl.credit_minor_units=new.recognized_revenue_minor_units and jl.debit_minor_units=0
      and jl.currency=new.currency and jl.party_id=v_sale.buyer_party_id)
    into v_line_count,v_receivable_count,v_revenue_count
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id and jl.transaction_date=new.recognition_date;
  if v_line_count<>2 or v_receivable_count<>1 or v_revenue_count<>1 then
    raise exception 'agriculture sale recognition journal is not the canonical receivable/revenue posting';
  end if;
  return new;
end $$;
create trigger agriculture_sale_recognitions_insert_guard
before insert on public.agriculture_sale_recognitions
for each row execute function public.gf018_guard_recognition_insert();

create or replace function public.gf018_guard_collection_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_rec public.agriculture_sale_recognitions%rowtype; v_sale public.agriculture_sales%rowtype;
  v_batch public.journal_batches%rowtype; v_account public.project_cash_accounts%rowtype;
  v_collected numeric; v_line_count integer; v_cash_count integer; v_receivable_count integer;
begin
  select * into v_rec from public.agriculture_sale_recognitions
  where id=new.recognition_id and organization_id=new.organization_id and project_id=new.project_id
  for update;
  if not found or new.sale_id<>v_rec.sale_id or new.currency<>v_rec.currency
     or new.collection_date<v_rec.recognition_date then
    raise exception 'agriculture sale collection does not match its recognition';
  end if;
  select * into v_sale from public.agriculture_sales where id=v_rec.sale_id;
  select * into v_account from public.project_cash_accounts
  where id=new.cash_account_id and organization_id=new.organization_id;
  if not found or v_account.project_id<>new.project_id or v_account.currency<>new.currency then
    raise exception 'agriculture sale collection cash account scope mismatch';
  end if;
  select coalesce(sum(amount_minor_units::numeric),0) into v_collected
  from public.agriculture_sale_collections where recognition_id=new.recognition_id;
  if v_collected+new.amount_minor_units>v_rec.recognized_revenue_minor_units then
    raise exception 'collection exceeds outstanding agriculture receivable';
  end if;
  select * into v_batch from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id;
  if not found or v_batch.project_id<>new.project_id
     or v_batch.source_type<>'AGRICULTURE_SALE_COLLECTION'
     or v_batch.source_id<>new.id or v_batch.transaction_date<>new.collection_date then
    raise exception 'agriculture sale collection journal source mismatch';
  end if;
  select count(*),
    count(*) filter(where sa.role='BANK_CASH' and jl.debit_minor_units=new.amount_minor_units
      and jl.credit_minor_units=0 and jl.currency=new.currency
      and jl.cash_account_id=new.cash_account_id),
    count(*) filter(where sa.role='CUSTOMER_RECEIVABLE' and jl.credit_minor_units=new.amount_minor_units
      and jl.debit_minor_units=0 and jl.currency=new.currency
      and jl.party_id=v_sale.buyer_party_id)
    into v_line_count,v_cash_count,v_receivable_count
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=new.journal_batch_id and jl.organization_id=new.organization_id
    and jl.project_id=new.project_id and jl.transaction_date=new.collection_date;
  if v_line_count<>2 or v_cash_count<>1 or v_receivable_count<>1 then
    raise exception 'agriculture sale collection journal is not the canonical cash/receivable posting';
  end if;
  return new;
end $$;
create trigger agriculture_sale_collections_insert_guard
before insert on public.agriculture_sale_collections
for each row execute function public.gf018_guard_collection_insert();

create or replace function public.gf018_guard_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'agriculture sale recognition, line and collection facts are immutable';
end $$;
create trigger agriculture_sale_lines_immutable
before update or delete on public.agriculture_sale_lines
for each row execute function public.gf018_guard_immutable();
create trigger agriculture_sale_recognitions_immutable
before update or delete on public.agriculture_sale_recognitions
for each row execute function public.gf018_guard_immutable();
create trigger agriculture_sale_collections_immutable
before update or delete on public.agriculture_sale_collections
for each row execute function public.gf018_guard_immutable();

create or replace function public.gf018_guard_sale_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.organization_id<>old.organization_id or new.project_id<>old.project_id
     or new.buyer_party_id<>old.buyer_party_id or new.sale_reference<>old.sale_reference
     or new.agreement_reference is distinct from old.agreement_reference
     or new.sale_date<>old.sale_date or new.currency<>old.currency
     or new.terms is distinct from old.terms
     or new.evidence_reference is distinct from old.evidence_reference
     or new.prepared_by<>old.prepared_by or new.prepared_at<>old.prepared_at
     or new.idempotency_key<>old.idempotency_key or new.request_hash<>old.request_hash then
    raise exception 'agriculture sale economics are immutable';
  end if;
  if old.status='DRAFT' and new.status='APPROVED' then
    if new.approved_by is null or new.approved_at is null
       or new.approval_idempotency_key is null or new.approval_request_hash is null
       or new.control_transfer_date is not null then
      raise exception 'invalid agriculture sale approval transition';
    end if;
  elsif old.status='APPROVED' and new.status='CONTROL_TRANSFERRED' then
    if new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.approval_idempotency_key is distinct from old.approval_idempotency_key
       or new.approval_request_hash is distinct from old.approval_request_hash
       or new.control_transfer_date is null
       or new.control_transfer_evidence_reference is null
       or new.control_transferred_by is null or new.control_transferred_at is null
       or new.transfer_idempotency_key is null or new.transfer_request_hash is null then
      raise exception 'invalid agriculture sale control-transfer transition';
    end if;
  else
    raise exception 'invalid agriculture sale lifecycle transition: % -> %',old.status,new.status;
  end if;
  return new;
end $$;
create trigger agriculture_sales_transition_only
before update on public.agriculture_sales
for each row execute function public.gf018_guard_sale_transition();
create trigger agriculture_sales_no_delete
before delete on public.agriculture_sales
for each row execute function public.gf018_guard_immutable();

-- Do not let a generic reversal detach the shared journal from immutable
-- physical SALE_ISSUE/control-transfer truth. GF-019 integrates controlled S6
-- correction semantics explicitly.
create or replace function public.gf018_guard_sale_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_target_type text;
begin
  if new.source_type<>'REVERSAL' then return new; end if;
  select source_type into v_target_type from public.journal_batches
  where id=new.source_id and organization_id=new.organization_id;
  if v_target_type in ('AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION') then
    raise exception 'Agriculture sale correction requires controlled S6 correction policy';
  end if;
  return new;
end $$;
create trigger journal_batches_gf018_sale_reversal_guard
before insert on public.journal_batches
for each row execute function public.gf018_guard_sale_reversal();

-- ===========================================================================
-- 5. Commands
-- ===========================================================================
create or replace function public.create_agriculture_sale(
  p_organization_id uuid,p_project_id uuid,p_buyer_party_id uuid,
  p_sale_reference text,p_agreement_reference text,p_sale_date date,
  p_currency text,p_terms text,p_evidence_reference text,
  p_harvest_lot_ids uuid[],p_source_storage_ids uuid[],
  p_quantities numeric[],p_unit_price_minor_units bigint[],
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_sale_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.agriculture_sales%rowtype; v_project_currency text;
  v_count integer; v_i integer; v_lot record; v_amount numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select reporting_currency into v_project_currency from public.investment_projects
  where id=p_project_id and organization_id=p_organization_id and sector='AGRICULTURE';
  if v_project_currency is null then raise exception 'agriculture project not found'; end if;
  if p_currency<>v_project_currency then raise exception 'sale currency must match project currency'; end if;
  if not exists(select 1 from public.parties where id=p_buyer_party_id and organization_id=p_organization_id) then
    raise exception 'buyer party not found';
  end if;
  if p_sale_reference is null or char_length(trim(p_sale_reference)) not between 1 and 120 then raise exception 'sale reference required'; end if;
  if p_agreement_reference is not null and char_length(trim(p_agreement_reference)) not between 2 and 200 then raise exception 'invalid sale agreement reference'; end if;
  if p_sale_date is null then raise exception 'sale date required'; end if;
  if p_terms is not null and char_length(trim(p_terms)) not between 2 and 1000 then raise exception 'invalid sale terms'; end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'invalid sale evidence'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_count:=coalesce(cardinality(p_harvest_lot_ids),0);
  if v_count<1 or v_count>50
     or cardinality(p_source_storage_ids)<>v_count
     or cardinality(p_quantities)<>v_count
     or cardinality(p_unit_price_minor_units)<>v_count then
    raise exception 'sale requires one to fifty coherent lines';
  end if;

  select encode(digest(jsonb_build_object(
    'project_id',p_project_id,'buyer_party_id',p_buyer_party_id,
    'sale_reference',trim(p_sale_reference),'agreement_reference',nullif(trim(p_agreement_reference),''),
    'sale_date',p_sale_date,'currency',p_currency,'terms',nullif(trim(p_terms),''),
    'evidence_reference',nullif(trim(p_evidence_reference),''),
    'harvest_lot_ids',p_harvest_lot_ids,'source_storage_ids',p_source_storage_ids,
    'quantities',p_quantities,'unit_price_minor_units',p_unit_price_minor_units
  )::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf018-sale:'||trim(p_idempotency_key),0));
  select * into v_existing from public.agriculture_sales
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':'||p_project_id::text||':gf018-sale-ref:'||lower(trim(p_sale_reference)),0));
  if exists(select 1 from public.agriculture_sales
    where organization_id=p_organization_id and project_id=p_project_id
      and lower(sale_reference)=lower(trim(p_sale_reference))) then
    raise exception 'agriculture sale reference already exists';
  end if;

  -- Validate every line before creating any part of the aggregate.
  for v_i in 1..v_count loop
    select l.*,public.harvest_lot_storage_balance(l.id,p_source_storage_ids[v_i]) as available
      into v_lot from public.harvest_lots l
      where l.id=p_harvest_lot_ids[v_i]
        and l.organization_id=p_organization_id and l.project_id=p_project_id;
    if not found then raise exception 'harvest lot not found for sale line %',v_i; end if;
    if not exists(select 1 from public.storage_locations s
      where s.id=p_source_storage_ids[v_i] and s.organization_id=p_organization_id and s.project_id=p_project_id) then
      raise exception 'source storage not found for sale line %',v_i;
    end if;
    if p_sale_date<v_lot.harvest_date then raise exception 'sale cannot precede harvest for line %',v_i; end if;
    if p_quantities[v_i] is null or p_quantities[v_i]<=0 then raise exception 'sale quantity must be positive'; end if;
    if p_unit_price_minor_units[v_i] is null or p_unit_price_minor_units[v_i]<=0 then raise exception 'sale unit price must be positive'; end if;
    v_amount:=(p_quantities[v_i]::numeric(20,6)*p_unit_price_minor_units[v_i]::numeric);
    if v_amount<>trunc(v_amount) or v_amount>9223372036854775807 then
      raise exception 'sale line amount must resolve to exact minor units';
    end if;
    if exists(select 1 from unnest(p_harvest_lot_ids,p_source_storage_ids) with ordinality
      as x(lot_id,storage_id,n) where n<v_i and lot_id=p_harvest_lot_ids[v_i]
        and storage_id=p_source_storage_ids[v_i]) then
      raise exception 'duplicate lot and storage in sale lines';
    end if;
  end loop;

  insert into public.agriculture_sales(
    id,organization_id,project_id,buyer_party_id,sale_reference,
    agreement_reference,sale_date,currency,terms,evidence_reference,
    prepared_by,idempotency_key,request_hash
  ) values(
    v_sale_id,p_organization_id,p_project_id,p_buyer_party_id,trim(p_sale_reference),
    nullif(trim(p_agreement_reference),''),p_sale_date,p_currency,
    nullif(trim(p_terms),''),nullif(trim(p_evidence_reference),''),
    v_actor,trim(p_idempotency_key),v_hash
  );
  for v_i in 1..v_count loop
    select * into v_lot from public.harvest_lots where id=p_harvest_lot_ids[v_i];
    v_amount:=(p_quantities[v_i]::numeric(20,6)*p_unit_price_minor_units[v_i]::numeric);
    insert into public.agriculture_sale_lines(
      organization_id,project_id,sale_id,line_no,harvest_lot_id,source_storage_id,
      quantity,unit,unit_price_minor_units,line_amount_minor_units
    ) values(
      p_organization_id,p_project_id,v_sale_id,v_i,p_harvest_lot_ids[v_i],
      p_source_storage_ids[v_i],p_quantities[v_i]::numeric(20,6),v_lot.quantity_unit,
      p_unit_price_minor_units[v_i],v_amount::bigint
    );
  end loop;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'AGRICULTURE_SALE_DRAFT_CREATED','agriculture_sale',v_sale_id,
    jsonb_build_object('project_id',p_project_id,'buyer_party_id',p_buyer_party_id,
      'line_count',v_count,'currency',p_currency,'accounting_effect','NONE','inventory_effect','NONE'));
  return v_sale_id;
end $$;

create or replace function public.approve_agriculture_sale(
  p_organization_id uuid,p_sale_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_sale public.agriculture_sales%rowtype; v_existing public.agriculture_sales%rowtype; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_sale_id::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf018-sale-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.agriculture_sales where organization_id=p_organization_id
    and approval_idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.id<>p_sale_id or v_existing.approval_request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_sale from public.agriculture_sales where id=p_sale_id and organization_id=p_organization_id for update;
  if not found then raise exception 'agriculture sale not found'; end if;
  if v_sale.status<>'DRAFT' then raise exception 'only a draft agriculture sale can be approved'; end if;
  update public.agriculture_sales set status='APPROVED',approved_by=v_actor,approved_at=now(),
    approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash where id=p_sale_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'AGRICULTURE_SALE_APPROVED','agriculture_sale',p_sale_id,
    jsonb_build_object('project_id',v_sale.project_id));
  return p_sale_id;
end $$;

create or replace function public.recognize_agriculture_sale(
  p_organization_id uuid,p_sale_id uuid,p_control_transfer_date date,
  p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_sale public.agriculture_sales%rowtype;
  v_existing public.agriculture_sale_recognitions%rowtype; v_hash text;
  v_recognition_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_line record; v_total numeric; v_receivable uuid; v_revenue uuid; v_movement_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_control_transfer_date is null or p_control_transfer_date>current_date then raise exception 'control transfer date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'control transfer evidence required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(jsonb_build_object('sale_id',p_sale_id,
    'control_transfer_date',p_control_transfer_date,'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf018-sale-recognize:'||trim(p_idempotency_key),0));
  select * into v_existing from public.agriculture_sale_recognitions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.sale_id<>p_sale_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_sale from public.agriculture_sales
  where id=p_sale_id and organization_id=p_organization_id for update;
  if not found then raise exception 'agriculture sale not found'; end if;
  if v_sale.status<>'APPROVED' then raise exception 'agriculture sale must be approved before control transfer'; end if;
  if p_control_transfer_date<v_sale.sale_date then raise exception 'control transfer cannot precede sale date'; end if;
  -- Lock every source lot in deterministic order before checking any balance.
  perform 1 from public.harvest_lots l
  join public.agriculture_sale_lines sl on sl.harvest_lot_id=l.id
  where sl.sale_id=p_sale_id order by l.id for update of l;
  for v_line in select * from public.agriculture_sale_lines where sale_id=p_sale_id order by line_no loop
    if p_control_transfer_date<(select harvest_date from public.harvest_lots where id=v_line.harvest_lot_id) then
      raise exception 'sale issue cannot precede harvest';
    end if;
    if public.harvest_lot_storage_balance(v_line.harvest_lot_id,v_line.source_storage_id)<v_line.quantity then
      raise exception 'insufficient inventory for agriculture sale line %',v_line.line_no;
    end if;
  end loop;
  select sum(line_amount_minor_units::numeric) into v_total from public.agriculture_sale_lines where sale_id=p_sale_id;
  if v_total is null or v_total<=0 or v_total>9223372036854775807 then raise exception 'invalid agriculture sale total'; end if;

  -- Physical dispatch, control-transfer sale fact and financial recognition are
  -- one transaction. Any later failure rolls back every SALE_ISSUE.
  for v_line in select * from public.agriculture_sale_lines where sale_id=p_sale_id order by line_no loop
    v_movement_id:=gen_random_uuid();
    insert into public.harvest_inventory_movements(
      id,organization_id,project_id,harvest_lot_id,movement_type,movement_date,
      quantity,unit,from_storage_id,to_storage_id,reason,evidence_reference,
      recorded_by,idempotency_key,request_hash,agriculture_sale_line_id
    ) values(
      v_movement_id,p_organization_id,v_sale.project_id,v_line.harvest_lot_id,'SALE_ISSUE',
      p_control_transfer_date,v_line.quantity,v_line.unit,v_line.source_storage_id,null,
      'بيع وتسليم '||v_sale.sale_reference,trim(p_evidence_reference),v_actor,
      'gf018-sale-issue-'||v_line.id::text,
      encode(digest(jsonb_build_object('sale_line_id',v_line.id,
        'control_transfer_date',p_control_transfer_date)::text,'sha256'),'hex'),v_line.id
    );
  end loop;
  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  select id into v_revenue from public.semantic_accounts where role='AGRICULTURE_SALE_REVENUE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,
    idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_sale.project_id,'AGRICULTURE_SALE_RECOGNITION',
    v_recognition_id,p_control_transfer_date,'gf018-sale-batch-'||v_recognition_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_sale.project_id,v_receivable,v_total::bigint,0,v_sale.currency,v_sale.buyer_party_id,p_control_transfer_date),
    (v_batch_id,p_organization_id,v_sale.project_id,v_revenue,0,v_total::bigint,v_sale.currency,v_sale.buyer_party_id,p_control_transfer_date);
  insert into public.agriculture_sale_recognitions(
    id,organization_id,project_id,sale_id,recognized_revenue_minor_units,currency,
    recognition_date,journal_batch_id,recognized_by,idempotency_key,request_hash
  ) values(
    v_recognition_id,p_organization_id,v_sale.project_id,p_sale_id,v_total::bigint,v_sale.currency,
    p_control_transfer_date,v_batch_id,v_actor,trim(p_idempotency_key),v_hash
  );
  update public.agriculture_sales set status='CONTROL_TRANSFERRED',
    control_transfer_date=p_control_transfer_date,
    control_transfer_evidence_reference=trim(p_evidence_reference),
    control_transferred_by=v_actor,control_transferred_at=now(),
    transfer_idempotency_key=trim(p_idempotency_key),transfer_request_hash=v_hash
  where id=p_sale_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'AGRICULTURE_SALE_RECOGNIZED','agriculture_sale_recognition',v_recognition_id,
    jsonb_build_object('project_id',v_sale.project_id,'sale_id',p_sale_id,
      'journal_batch_id',v_batch_id,'recognized_revenue_minor_units',v_total::bigint,
      'currency',v_sale.currency,'physical_issue','SALE_ISSUE','cogs_effect','NONE'));
  return v_recognition_id;
end $$;

create or replace function public.collect_agriculture_sale_receivable(
  p_organization_id uuid,p_recognition_id uuid,p_cash_account_id uuid,
  p_amount_minor_units bigint,p_collection_date date,p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_rec public.agriculture_sale_recognitions%rowtype;
  v_sale public.agriculture_sales%rowtype; v_existing public.agriculture_sale_collections%rowtype;
  v_hash text; v_collected numeric; v_collection_id uuid:=gen_random_uuid();
  v_batch_id uuid:=gen_random_uuid(); v_cash uuid; v_receivable uuid; v_account record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'collection amount must be positive'; end if;
  if p_collection_date is null or p_collection_date>current_date then raise exception 'collection date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'collection evidence required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(jsonb_build_object('recognition_id',p_recognition_id,
    'cash_account_id',p_cash_account_id,'amount_minor_units',p_amount_minor_units,
    'collection_date',p_collection_date,'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf018-collection:'||trim(p_idempotency_key),0));
  select * into v_existing from public.agriculture_sale_collections
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.recognition_id<>p_recognition_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_rec from public.agriculture_sale_recognitions
  where id=p_recognition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'agriculture sale recognition not found'; end if;
  select * into v_sale from public.agriculture_sales where id=v_rec.sale_id;
  if p_collection_date<v_rec.recognition_date then raise exception 'collection cannot precede recognition'; end if;
  select * into v_account from public.project_cash_accounts
  where id=p_cash_account_id and organization_id=p_organization_id;
  if not found or v_account.project_id<>v_rec.project_id or v_account.currency<>v_rec.currency then
    raise exception 'cash account must belong to the same project and currency';
  end if;
  select coalesce(sum(amount_minor_units::numeric),0) into v_collected
  from public.agriculture_sale_collections where recognition_id=p_recognition_id;
  if v_collected+p_amount_minor_units>v_rec.recognized_revenue_minor_units then
    raise exception 'collection exceeds outstanding agriculture receivable';
  end if;
  select id into v_cash from public.semantic_accounts where role='BANK_CASH';
  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,
    idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_rec.project_id,'AGRICULTURE_SALE_COLLECTION',
    v_collection_id,p_collection_date,'gf018-collection-batch-'||v_collection_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,cash_account_id,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_rec.project_id,v_cash,p_amount_minor_units,0,v_rec.currency,p_cash_account_id,null,p_collection_date),
    (v_batch_id,p_organization_id,v_rec.project_id,v_receivable,0,p_amount_minor_units,v_rec.currency,null,v_sale.buyer_party_id,p_collection_date);
  insert into public.agriculture_sale_collections(
    id,organization_id,project_id,recognition_id,sale_id,cash_account_id,
    amount_minor_units,currency,collection_date,evidence_reference,journal_batch_id,
    collected_by,idempotency_key,request_hash
  ) values(
    v_collection_id,p_organization_id,v_rec.project_id,p_recognition_id,v_rec.sale_id,
    p_cash_account_id,p_amount_minor_units,v_rec.currency,p_collection_date,
    trim(p_evidence_reference),v_batch_id,v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'AGRICULTURE_SALE_COLLECTION_POSTED','agriculture_sale_collection',v_collection_id,
    jsonb_build_object('project_id',v_rec.project_id,'sale_id',v_rec.sale_id,
      'recognition_id',p_recognition_id,'cash_account_id',p_cash_account_id,
      'journal_batch_id',v_batch_id,'amount_minor_units',p_amount_minor_units,
      'currency',v_rec.currency,'revenue_effect','NONE'));
  return v_collection_id;
end $$;

-- ===========================================================================
-- 6. Read models
-- ===========================================================================
create or replace view public.agriculture_sales_read with (security_invoker=on) as
select s.id as sale_id,s.organization_id,s.project_id,s.buyer_party_id,p.legal_name as buyer_name,
  s.sale_reference,s.agreement_reference,s.sale_date,s.currency,s.terms,s.evidence_reference,
  case when s.status='CONTROL_TRANSFERRED'
    and coalesce(c.collected,0)>=coalesce(r.recognized_revenue_minor_units,0)
    then 'SETTLED' else s.status end as state,
  s.status as control_state,s.prepared_by,s.prepared_at,s.approved_by,s.approved_at,
  s.control_transfer_date,s.control_transfer_evidence_reference,s.control_transferred_by,s.control_transferred_at,
  (select count(*) from public.agriculture_sale_lines sl where sl.sale_id=s.id) as line_count,
  case when (select count(distinct sl.unit) from public.agriculture_sale_lines sl where sl.sale_id=s.id)=1
    then (select sum(sl.quantity)::text from public.agriculture_sale_lines sl where sl.sale_id=s.id)
    else null end as aggregate_quantity,
  case when (select count(distinct sl.unit) from public.agriculture_sale_lines sl where sl.sale_id=s.id)=1
    then (select min(sl.unit) from public.agriculture_sale_lines sl where sl.sale_id=s.id) else null end as quantity_unit,
  coalesce((select sum(sl.line_amount_minor_units::numeric) from public.agriculture_sale_lines sl where sl.sale_id=s.id),0)::text as agreed_total_minor_units,
  r.id as recognition_id,r.recognition_date,r.journal_batch_id as revenue_journal_batch_id,
  coalesce(r.recognized_revenue_minor_units,0)::text as recognized_revenue_minor_units,
  coalesce(c.collected,0)::text as collected_minor_units,
  greatest(coalesce(r.recognized_revenue_minor_units,0)::numeric-coalesce(c.collected,0),0)::text as outstanding_receivable_minor_units
from public.agriculture_sales s
join public.parties p on p.id=s.buyer_party_id and p.organization_id=s.organization_id
left join public.agriculture_sale_recognitions r on r.sale_id=s.id
left join lateral (
  select coalesce(sum(sc.amount_minor_units::numeric),0) as collected
  from public.agriculture_sale_collections sc where sc.recognition_id=r.id
) c on true;

create or replace view public.agriculture_sale_lines_read with (security_invoker=on) as
select sl.id as sale_line_id,sl.organization_id,sl.project_id,sl.sale_id,sl.line_no,
  sl.harvest_lot_id,l.lot_reference,l.crop_cycle_id,l.field_id,l.harvest_date,
  sl.source_storage_id,st.name as source_storage_name,sl.quantity::text as quantity,
  sl.unit,sl.unit_price_minor_units::text as unit_price_minor_units,
  sl.line_amount_minor_units::text as line_amount_minor_units,
  m.id as sale_issue_movement_id,m.movement_date as dispatch_date
from public.agriculture_sale_lines sl
join public.harvest_lots l on l.id=sl.harvest_lot_id
join public.storage_locations st on st.id=sl.source_storage_id
left join public.harvest_inventory_movements m
  on m.agriculture_sale_line_id=sl.id and m.movement_type='SALE_ISSUE';

create or replace view public.agriculture_sale_collections_read with (security_invoker=on) as
select c.id as collection_id,c.organization_id,c.project_id,c.recognition_id,c.sale_id,
  c.cash_account_id,a.name as cash_account_name,c.amount_minor_units::text as amount_minor_units,
  c.currency,c.collection_date,c.evidence_reference,c.journal_batch_id,c.collected_by,c.collected_at
from public.agriculture_sale_collections c
join public.project_cash_accounts a on a.id=c.cash_account_id;

create or replace view public.harvest_lot_sale_traceability_read with (security_invoker=on) as
select l.id as harvest_lot_id,l.organization_id,l.project_id,l.lot_reference,l.crop_cycle_id,l.field_id,
  l.harvest_event_id,l.harvest_date,l.initial_quantity::text as initial_quantity,l.quantity_unit,
  sl.id as sale_line_id,sl.sale_id,s.sale_reference,s.buyer_party_id,p.legal_name as buyer_name,
  sl.source_storage_id,st.name as source_storage_name,sl.quantity::text as sold_quantity,
  sl.unit_price_minor_units::text as unit_price_minor_units,
  sl.line_amount_minor_units::text as line_amount_minor_units,
  m.id as sale_issue_movement_id,m.movement_date as dispatch_date,
  r.id as recognition_id,r.journal_batch_id as revenue_journal_batch_id
from public.harvest_lots l
left join public.agriculture_sale_lines sl on sl.harvest_lot_id=l.id
left join public.agriculture_sales s on s.id=sl.sale_id
left join public.parties p on p.id=s.buyer_party_id
left join public.storage_locations st on st.id=sl.source_storage_id
left join public.harvest_inventory_movements m
  on m.agriculture_sale_line_id=sl.id and m.movement_type='SALE_ISSUE'
left join public.agriculture_sale_recognitions r on r.sale_id=s.id;

-- Rebuild GF-016 movement projection to expose physical sale lineage.
create or replace view public.harvest_inventory_movements_read with (security_invoker=on) as
select m.id,m.organization_id,m.project_id,m.harvest_lot_id,m.movement_type,m.movement_date,
  m.quantity::text as quantity,m.unit,m.from_storage_id,m.to_storage_id,
  fs.name as from_storage_name,ts.name as to_storage_name,m.reason,m.evidence_reference,
  m.recorded_by,m.created_at,l.lot_reference,m.agriculture_sale_line_id,sl.sale_id,s.sale_reference
from public.harvest_inventory_movements m
join public.harvest_lots l on l.id=m.harvest_lot_id
left join public.storage_locations fs on fs.id=m.from_storage_id
left join public.storage_locations ts on ts.id=m.to_storage_id
left join public.agriculture_sale_lines sl on sl.id=m.agriculture_sale_line_id
left join public.agriculture_sales s on s.id=sl.sale_id;

-- ===========================================================================
-- 7. RLS, grants and portable pgcrypto qualification
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array[
    'agriculture_sales','agriculture_sale_lines','agriculture_sale_recognitions','agriculture_sale_collections'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;
grant select on public.agriculture_sales_read,public.agriculture_sale_lines_read,
  public.agriculture_sale_collections_read,public.harvest_lot_sale_traceability_read to authenticated;

revoke all on function public.create_agriculture_sale(
  uuid,uuid,uuid,text,text,date,text,text,text,uuid[],uuid[],numeric[],bigint[],text
) from public,anon;
revoke all on function public.approve_agriculture_sale(uuid,uuid,text) from public,anon;
revoke all on function public.recognize_agriculture_sale(uuid,uuid,date,text,text) from public,anon;
revoke all on function public.collect_agriculture_sale_receivable(uuid,uuid,uuid,bigint,date,text,text) from public,anon;
grant execute on function public.create_agriculture_sale(
  uuid,uuid,uuid,text,text,date,text,text,text,uuid[],uuid[],numeric[],bigint[],text
),public.approve_agriculture_sale(uuid,uuid,text),
  public.recognize_agriculture_sale(uuid,uuid,date,text,text),
  public.collect_agriculture_sale_receivable(uuid,uuid,uuid,bigint,date,text,text)
to authenticated;

do $pgcrypto_compat$ declare v_schema text; v record; d text; r text; begin
  select n.nspname into v_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_schema is null then raise exception 'GF-018 requires pgcrypto'; end if;
  for v in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname in (
      'create_agriculture_sale','approve_agriculture_sale','recognize_agriculture_sale','collect_agriculture_sale_receivable'
    ) loop
    d:=pg_get_functiondef(v.oid);
    if d~'(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      r:=regexp_replace(d,'(^|[^[:alnum:]_.])digest[[:space:]]*\(',E'\\1'||quote_ident(v_schema)||'.digest(','g');
      execute r;
    end if;
  end loop;
end $pgcrypto_compat$;
