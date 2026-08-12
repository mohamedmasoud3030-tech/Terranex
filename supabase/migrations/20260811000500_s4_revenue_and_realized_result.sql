-- GF-006 / S4 — Revenue & Realized Result.
--
-- Forward-only extension of the merged S0-S3 foundation. This slice keeps the
-- legal agreement, control transfer, accrual revenue, receivable, collection,
-- carrying amount, cost of sale, management valuation, and realized result as
-- separate facts. It reuses S2 journal/cash/reconciliation primitives and S3
-- whole-property cost dimensions; it does not create another subledger.

-- ===========================================================================
-- 1. Extend the locked S2 semantic roles and journal source registry.
--    DEVELOPMENT_WIP remains the authoritative carrying-cost account.
-- ===========================================================================
drop trigger semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE'
));
insert into public.semantic_accounts(role,label_ar) values
  ('CUSTOMER_RECEIVABLE','ذمم مدينة للعملاء'),
  ('REAL_ESTATE_SALE_REVENUE','إيراد بيع عقاري'),
  ('REAL_ESTATE_COST_OF_SALE','تكلفة بيع عقاري');
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

alter table public.journal_batches drop constraint journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION'
));

-- Selling cost is an S4 use of the existing S3 property-to-S2-obligation
-- dimension. It is an expense fact, never part of carrying cost.
alter table public.property_cost_items drop constraint property_cost_items_cost_category_check;
alter table public.property_cost_items add constraint property_cost_items_cost_category_check check (cost_category in (
  'ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION',
  'PROFESSIONAL_FEES','HOLDING','SELLING','OTHER'
));

-- ===========================================================================
-- 2. Whole-property disposition agreement and explicit control transfer.
--    One row per property is an intentional MVP database boundary: there is no
--    parcel/percentage scope and therefore no unsupported partial allocation.
-- ===========================================================================
create table public.property_dispositions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  buyer_party_id uuid not null,
  agreement_reference text not null check (char_length(trim(agreement_reference)) between 2 and 120),
  agreement_evidence_reference text not null check (char_length(trim(agreement_evidence_reference)) between 3 and 200),
  agreed_proceeds_minor_units bigint not null check (agreed_proceeds_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  agreement_date date not null,
  expected_control_transfer_date date,
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','CONTROL_TRANSFERRED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  control_transfer_date date,
  control_transfer_evidence_reference text check (control_transfer_evidence_reference is null or char_length(trim(control_transfer_evidence_reference)) between 3 and 200),
  control_transferred_by uuid references auth.users(id) on delete restrict,
  control_transferred_at timestamptz,
  transfer_idempotency_key text check (transfer_idempotency_key is null or char_length(transfer_idempotency_key) between 8 and 120),
  transfer_request_hash text check (transfer_request_hash is null or char_length(transfer_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (expected_control_transfer_date is null or expected_control_transfer_date >= agreement_date),
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
      and control_transfer_date is not null and control_transfer_date >= agreement_date
      and control_transfer_evidence_reference is not null
      and control_transferred_by is not null and control_transferred_at is not null
      and transfer_idempotency_key is not null and transfer_request_hash is not null)
  ),
  unique (property_asset_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  unique (id,organization_id,project_id,property_asset_id),
  foreign key (property_asset_id,organization_id,project_id)
    references public.property_assets(id,organization_id,project_id) on delete restrict,
  foreign key (buyer_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create unique index property_disposition_approval_key
  on public.property_dispositions(organization_id,approval_idempotency_key)
  where approval_idempotency_key is not null;
create unique index property_disposition_transfer_key
  on public.property_dispositions(organization_id,transfer_idempotency_key)
  where transfer_idempotency_key is not null;
create index property_dispositions_project_idx on public.property_dispositions(project_id);

-- ===========================================================================
-- 3. Recognition, immutable carrying-cost provenance, collection, and reuse of
--    S2 bank-statement reconciliation facts.
-- ===========================================================================
create table public.property_sale_recognitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  disposition_id uuid not null,
  recognized_proceeds_minor_units bigint not null check (recognized_proceeds_minor_units > 0),
  carrying_cost_minor_units bigint not null check (carrying_cost_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  recognition_date date not null,
  journal_batch_id uuid not null,
  recognized_by uuid not null references auth.users(id) on delete restrict,
  recognized_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (disposition_id),
  unique (property_asset_id),
  unique (journal_batch_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  foreign key (disposition_id,organization_id,project_id,property_asset_id)
    references public.property_dispositions(id,organization_id,project_id,property_asset_id) on delete restrict,
  foreign key (property_asset_id,organization_id,project_id)
    references public.property_assets(id,organization_id,project_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index property_sale_recognitions_project_idx on public.property_sale_recognitions(project_id);

-- Snapshot only provenance, not another monetary ledger. Every row points to
-- the existing S2 WIP debit and S3 property classification used by recognition.
create table public.property_sale_carrying_cost_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  recognition_id uuid not null,
  property_cost_item_id uuid not null references public.property_cost_items(id) on delete restrict,
  obligation_id uuid not null references public.cost_obligations(id) on delete restrict,
  journal_batch_id uuid not null references public.journal_batches(id) on delete restrict,
  journal_line_id uuid not null references public.journal_lines(id) on delete restrict,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  policy_reference text not null check (char_length(trim(policy_reference)) between 3 and 200),
  created_at timestamptz not null default now(),
  unique (recognition_id,journal_line_id),
  unique (id,organization_id),
  foreign key (recognition_id,organization_id,project_id)
    references public.property_sale_recognitions(id,organization_id,project_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index property_sale_carrying_sources_recognition_idx
  on public.property_sale_carrying_cost_sources(recognition_id);

create table public.property_sale_collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  recognition_id uuid not null,
  disposition_id uuid not null,
  cash_account_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  collection_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid,
  collected_by uuid not null references auth.users(id) on delete restrict,
  collected_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  unique (id,organization_id),
  foreign key (recognition_id,organization_id,project_id)
    references public.property_sale_recognitions(id,organization_id,project_id) on delete restrict,
  foreign key (disposition_id,organization_id)
    references public.property_dispositions(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);
create index property_sale_collections_recognition_idx on public.property_sale_collections(recognition_id);

create table public.property_sale_collection_reconciliations (
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
  request_hash text not null check (char_length(request_hash) = 64),
  unique (collection_id),
  unique (statement_line_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  foreign key (collection_id,organization_id)
    references public.property_sale_collections(id,organization_id) on delete restrict,
  foreign key (statement_line_id,organization_id)
    references public.bank_statement_lines(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);

-- One bank line can be reserved by either the existing payment reconciliation
-- or an S4 customer collection, never both. This single unique row is the
-- cross-table concurrency boundary.
create table public.bank_statement_reconciliation_allocations (
  statement_line_id uuid primary key references public.bank_statement_lines(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  match_type text not null check (match_type in ('PAYMENT','PROPERTY_SALE_COLLECTION')),
  match_id uuid not null unique,
  allocated_at timestamptz not null default now(),
  foreign key (statement_line_id,organization_id)
    references public.bank_statement_lines(id,organization_id) on delete restrict
);
insert into public.bank_statement_reconciliation_allocations(statement_line_id,organization_id,match_type,match_id,allocated_at)
select statement_line_id,organization_id,'PAYMENT',id,matched_at
from public.reconciliation_matches where voided_at is null;

-- ===========================================================================
-- 4. Immutability, transition, source uniqueness, and database-backed ceilings.
-- ===========================================================================
create or replace function public.s4_guard_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'confirmed S4 financial facts are immutable';
end $$;

create trigger property_sale_recognitions_immutable
before update or delete on public.property_sale_recognitions
for each row execute function public.s4_guard_immutable();
create trigger property_sale_carrying_sources_immutable
before update or delete on public.property_sale_carrying_cost_sources
for each row execute function public.s4_guard_immutable();
create trigger property_sale_collections_immutable
before delete on public.property_sale_collections
for each row execute function public.s4_guard_immutable();
create trigger property_sale_collection_reconciliations_immutable
before update or delete on public.property_sale_collection_reconciliations
for each row execute function public.s4_guard_immutable();

-- Collection rows permit exactly one internal command completion update: the
-- generated journal batch id changes NULL -> non-NULL; economics never change.
create or replace function public.s4_guard_collection_batch_link_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.journal_batch_id is not null or new.journal_batch_id is null
     or new.id<>old.id or new.organization_id<>old.organization_id
     or new.project_id<>old.project_id or new.recognition_id<>old.recognition_id
     or new.disposition_id<>old.disposition_id or new.cash_account_id<>old.cash_account_id
     or new.amount_minor_units<>old.amount_minor_units or new.currency<>old.currency
     or new.collection_date<>old.collection_date or new.evidence_reference<>old.evidence_reference
     or new.collected_by<>old.collected_by or new.collected_at<>old.collected_at
     or new.idempotency_key<>old.idempotency_key or new.request_hash<>old.request_hash then
    raise exception 'collection economics are immutable';
  end if;
  return new;
end $$;
create trigger property_sale_collection_batch_link_only
before update on public.property_sale_collections
for each row execute function public.s4_guard_collection_batch_link_only();

create or replace function public.s4_guard_disposition_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.id<>old.id or new.organization_id<>old.organization_id
     or new.project_id<>old.project_id or new.property_asset_id<>old.property_asset_id
     or new.buyer_party_id<>old.buyer_party_id
     or new.agreement_reference<>old.agreement_reference
     or new.agreement_evidence_reference<>old.agreement_evidence_reference
     or new.agreed_proceeds_minor_units<>old.agreed_proceeds_minor_units
     or new.currency<>old.currency or new.agreement_date<>old.agreement_date
     or new.expected_control_transfer_date is distinct from old.expected_control_transfer_date
     or new.prepared_by<>old.prepared_by or new.prepared_at<>old.prepared_at
     or new.idempotency_key<>old.idempotency_key or new.request_hash<>old.request_hash then
    raise exception 'disposition agreement economics are immutable';
  end if;

  if old.status='DRAFT' and new.status='APPROVED' then
    if new.approved_by is null or new.approved_at is null
       or new.approval_idempotency_key is null or new.approval_request_hash is null
       or new.control_transfer_date is not null or new.control_transfer_evidence_reference is not null
       or new.control_transferred_by is not null or new.control_transferred_at is not null
       or new.transfer_idempotency_key is not null or new.transfer_request_hash is not null then
      raise exception 'invalid disposition approval transition';
    end if;
  elsif old.status='APPROVED' and new.status='CONTROL_TRANSFERRED' then
    if new.approved_by<>old.approved_by or new.approved_at<>old.approved_at
       or new.approval_idempotency_key<>old.approval_idempotency_key
       or new.approval_request_hash<>old.approval_request_hash
       or new.control_transfer_date is null or new.control_transfer_evidence_reference is null
       or new.control_transferred_by is null or new.control_transferred_at is null
       or new.transfer_idempotency_key is null or new.transfer_request_hash is null then
      raise exception 'invalid disposition control-transfer transition';
    end if;
  else
    raise exception 'invalid disposition lifecycle transition: % -> %',old.status,new.status;
  end if;
  return new;
end $$;
create trigger property_disposition_transition_only
before update on public.property_dispositions
for each row execute function public.s4_guard_disposition_transition();
create trigger property_disposition_no_delete
before delete on public.property_dispositions
for each row execute function public.s4_guard_immutable();

-- Any writer of an S4 journal source receives the same source-scoped lock and
-- one-active-posting protection as S2 sources.
create or replace function public.s4_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION') then
    perform pg_advisory_xact_lock(hashtextextended(
      's4-active-source:'||new.organization_id::text||':'||new.source_type||':'||new.source_id::text,0));
    if exists (
      select 1 from public.journal_batches jb
      where jb.organization_id=new.organization_id
        and jb.source_type=new.source_type and jb.source_id=new.source_id
        and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
    ) then raise exception 'source already has an active posting'; end if;
  end if;
  return new;
end $$;
create trigger journal_batches_s4_one_active_source_guard
before insert on public.journal_batches
for each row execute function public.s4_guard_one_active_source_posting();

-- S4 corrections belong to S6. Until then, generic S2 reversal cannot leave a
-- recognized disposition/collection or its carrying source in a half-state.
create or replace function public.s4_guard_deferred_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_target record; v_disposition_status text;
begin
  if new.source_type<>'REVERSAL' then return new; end if;
  select * into v_target from public.journal_batches
  where id=new.source_id and organization_id=new.organization_id;
  if not found then return new; end if;
  if v_target.source_type in ('PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION') then
    raise exception 'S4 sale and collection correction is deferred to the controlled correction slice';
  end if;
  if v_target.source_type='COST_OBLIGATION' then
    -- The disposition row is the pre-existing serialization boundary shared
    -- with control transfer. Once transfer commits, no carrying source can be
    -- reversed while recognition is deriving its snapshot.
    select d.status into v_disposition_status
    from public.property_cost_items pci
    join public.property_dispositions d on d.property_asset_id=pci.property_asset_id
    where pci.cost_obligation_id=v_target.source_id
    for update of d;
    if v_disposition_status='CONTROL_TRANSFERRED' then
      raise exception 'control-transferred property carrying-cost sources cannot be reversed';
    end if;
  end if;
  return new;
end $$;
create trigger journal_batches_s4_deferred_reversal_guard
before insert on public.journal_batches
for each row execute function public.s4_guard_deferred_reversal();

-- A carrying-cost mapping and WIP posting cannot be added after sale
-- recognition. Selling expenses remain possible because they are separate
-- PROJECT_EXPENSE facts.
create or replace function public.s4_guard_no_post_sale_cost_mapping() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_disposition_status text;
begin
  if new.cost_category='SELLING' then return new; end if;
  select d.status into v_disposition_status
  from public.property_dispositions d
  where d.property_asset_id=new.property_asset_id
  for update;
  if v_disposition_status='CONTROL_TRANSFERRED' then
    raise exception 'cannot add carrying-cost classifications after control transfer';
  end if;
  return new;
end $$;
create trigger property_cost_items_no_post_sale_mapping
before insert on public.property_cost_items
for each row execute function public.s4_guard_no_post_sale_cost_mapping();

create or replace function public.s4_guard_no_post_sale_wip() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_disposition_status text;
begin
  if new.obligation_id is null
     or not exists(select 1 from public.semantic_accounts sa where sa.id=new.account_id and sa.role='DEVELOPMENT_WIP') then
    return new;
  end if;
  -- Lock the same disposition row updated by control transfer. If posting wins,
  -- transfer waits and recognition includes it; if transfer wins, posting sees
  -- CONTROL_TRANSFERRED and fails. No WIP can race into the carrying snapshot.
  select d.status into v_disposition_status
  from public.property_cost_items pci
  join public.property_dispositions d on d.property_asset_id=pci.property_asset_id
  where pci.cost_obligation_id=new.obligation_id
  for update of d;
  if v_disposition_status='CONTROL_TRANSFERRED' then
    raise exception 'cannot post carrying cost after property control transfer';
  end if;
  return new;
end $$;
create trigger journal_lines_no_post_sale_wip
before insert on public.journal_lines
for each row execute function public.s4_guard_no_post_sale_wip();

-- Locking the recognition row serializes every collection ceiling calculation,
-- including privileged inserts outside the RPC.
create or replace function public.s4_validate_collection() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_rec record; v_disp record; v_cash record; v_collected bigint;
begin
  select * into v_rec from public.property_sale_recognitions
  where id=new.recognition_id and organization_id=new.organization_id for update;
  if not found then raise exception 'sale recognition not found'; end if;
  select * into v_disp from public.property_dispositions
  where id=v_rec.disposition_id and organization_id=new.organization_id;
  if new.project_id<>v_rec.project_id or new.disposition_id<>v_rec.disposition_id
     or new.currency<>v_rec.currency then
    raise exception 'collection must match the recognized sale scope and currency';
  end if;
  select project_id,currency into v_cash from public.project_cash_accounts
  where id=new.cash_account_id and organization_id=new.organization_id;
  if not found or v_cash.project_id<>new.project_id or v_cash.currency<>new.currency then
    raise exception 'collection cash account must belong to the sale project and currency';
  end if;
  select coalesce(sum(c.amount_minor_units),0) into v_collected
  from public.property_sale_collections c where c.recognition_id=new.recognition_id;
  if v_collected+new.amount_minor_units>v_rec.recognized_proceeds_minor_units then
    raise exception 'collection exceeds outstanding receivable';
  end if;
  return new;
end $$;
create trigger property_sale_collection_scope_and_ceiling
before insert on public.property_sale_collections
for each row execute function public.s4_validate_collection();

-- Reconciliation allocation hooks make payment-vs-collection competition safe
-- under concurrency through one unique statement-line reservation.
create or replace function public.s4_reserve_payment_statement_line() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  insert into public.bank_statement_reconciliation_allocations(
    statement_line_id,organization_id,match_type,match_id
  ) values(new.statement_line_id,new.organization_id,'PAYMENT',new.id);
  return new;
end $$;
create trigger reconciliation_matches_reserve_statement
before insert on public.reconciliation_matches
for each row execute function public.s4_reserve_payment_statement_line();

create or replace function public.s4_release_voided_payment_statement_line() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.voided_at is null and new.voided_at is not null then
    delete from public.bank_statement_reconciliation_allocations
    where statement_line_id=new.statement_line_id and match_type='PAYMENT' and match_id=new.id;
  end if;
  return new;
end $$;
create trigger reconciliation_matches_release_voided_statement
after update on public.reconciliation_matches
for each row execute function public.s4_release_voided_payment_statement_line();

create or replace function public.s4_reserve_collection_statement_line() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  insert into public.bank_statement_reconciliation_allocations(
    statement_line_id,organization_id,match_type,match_id
  ) values(new.statement_line_id,new.organization_id,'PROPERTY_SALE_COLLECTION',new.id);
  return new;
end $$;
create trigger property_collection_reconciliation_reserve_statement
before insert on public.property_sale_collection_reconciliations
for each row execute function public.s4_reserve_collection_statement_line();

-- ===========================================================================
-- 5. Minimal S3 lifecycle extension. Existing transitions and evidence checks
--    are preserved; EXITING and DISPOSED are explicit operational facts and do
--    not post journals.
-- ===========================================================================
alter table public.property_asset_state_history drop constraint property_asset_state_history_previous_state_check;
alter table public.property_asset_state_history drop constraint property_asset_state_history_new_state_check;
alter table public.property_asset_state_history add constraint property_asset_state_history_previous_state_check
  check (previous_state is null or previous_state in (
    'CANDIDATE','DUE_DILIGENCE','ACQUIRING','HELD','DEVELOPING','EXITING','DISPOSED'
  ));
alter table public.property_asset_state_history add constraint property_asset_state_history_new_state_check
  check (new_state in (
    'CANDIDATE','DUE_DILIGENCE','ACQUIRING','HELD','DEVELOPING','EXITING','DISPOSED'
  ));

create or replace function public.s3_validate_property_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_current text; v_current_history uuid;
begin
  perform 1 from public.property_assets a where a.id=new.property_asset_id for update;
  select h.id,h.new_state into v_current_history,v_current
  from public.property_asset_state_history h where h.property_asset_id=new.property_asset_id
  order by h.changed_at desc,h.id desc limit 1;

  if public.s3_validate_history_predecessor(
    v_current_history,v_current,new.previous_history_id,new.previous_state,new.new_state,'CANDIDATE'
  ) then return new; end if;

  if not ((v_current='CANDIDATE' and new.new_state='DUE_DILIGENCE')
       or (v_current='DUE_DILIGENCE' and new.new_state='ACQUIRING')
       or (v_current='ACQUIRING' and new.new_state='HELD')
       or (v_current='HELD' and new.new_state='DEVELOPING')
       or (v_current='DEVELOPING' and new.new_state='HELD')
       or (v_current='HELD' and new.new_state='EXITING')
       or (v_current='EXITING' and new.new_state='DISPOSED')) then
    raise exception 'invalid property lifecycle transition: % -> %',v_current,new.new_state;
  end if;

  if v_current='DUE_DILIGENCE' and new.new_state='ACQUIRING' then
    if not exists(select 1 from public.property_acquisitions a where a.property_asset_id=new.property_asset_id) then
      raise exception 'acquiring requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'ACQUISITION_CHECK') then
      raise exception 'acquiring requires current effective passed acquisition due-diligence coverage';
    end if;
  end if;

  if v_current='ACQUIRING' and new.new_state='HELD' then
    if not exists(select 1 from public.property_acquisitions a where a.property_asset_id=new.property_asset_id) then
      raise exception 'held requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE') then
      raise exception 'held requires current effective passed title coverage';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'held requires current effective passed possession coverage';
    end if;
  end if;

  if v_current='HELD' and new.new_state='DEVELOPING' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'development requires current effective title and possession coverage';
    end if;
    if not exists(
      select 1 from public.development_phases p where p.property_asset_id=new.property_asset_id
        and public.s3_current_phase_state(p.id)='ACTIVE'
    ) then raise exception 'developing requires an active development phase'; end if;
  end if;

  if v_current='DEVELOPING' and new.new_state='HELD' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'returning to held requires current effective title and possession coverage';
    end if;
    if exists(
      select 1 from public.development_phases p where p.property_asset_id=new.property_asset_id
        and public.s3_current_phase_state(p.id)='ACTIVE'
    ) then raise exception 'returning to held requires no active development phase'; end if;
    if not exists(
      select 1 from public.development_phases p where p.property_asset_id=new.property_asset_id
        and public.s3_current_phase_state(p.id)='COMPLETED'
    ) then raise exception 'returning to held requires a completed development phase'; end if;
  end if;

  if v_current='HELD' and new.new_state='EXITING' then
    if not exists(
      select 1 from public.property_dispositions d
      where d.property_asset_id=new.property_asset_id and d.status in ('APPROVED','CONTROL_TRANSFERRED')
    ) then raise exception 'exiting requires an approved disposition agreement'; end if;
    if exists(
      select 1 from public.development_phases p where p.property_asset_id=new.property_asset_id
        and public.s3_current_phase_state(p.id)='ACTIVE'
    ) then raise exception 'exiting requires no active development phase'; end if;
  end if;

  if v_current='EXITING' and new.new_state='DISPOSED' then
    if not exists(
      select 1 from public.property_dispositions d
      join public.property_sale_recognitions r on r.disposition_id=d.id
      where d.property_asset_id=new.property_asset_id and d.status='CONTROL_TRANSFERRED'
    ) then raise exception 'disposed requires a control-transferred recognized sale'; end if;
  end if;
  return new;
end $$;

-- ===========================================================================
-- 6. Server-authoritative S4 commands.
-- ===========================================================================
create or replace function public.create_property_disposition(
  p_organization_id uuid,p_project_id uuid,p_property_asset_id uuid,p_buyer_party_id uuid,
  p_agreement_reference text,p_agreement_evidence_reference text,
  p_agreed_proceeds_minor_units bigint,p_currency text,p_agreement_date date,
  p_expected_control_transfer_date date,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_existing record; v_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_agreement_reference is null or char_length(trim(p_agreement_reference)) not between 2 and 120 then raise exception 'agreement reference required'; end if;
  if p_agreement_evidence_reference is null or char_length(trim(p_agreement_evidence_reference)) not between 3 and 200 then raise exception 'agreement evidence required'; end if;
  if p_agreed_proceeds_minor_units is null or p_agreed_proceeds_minor_units<=0 then raise exception 'agreed proceeds must be positive'; end if;
  if p_agreement_date is null then raise exception 'agreement date required'; end if;
  if p_expected_control_transfer_date is not null and p_expected_control_transfer_date<p_agreement_date then raise exception 'expected transfer cannot precede agreement'; end if;
  select p.reporting_currency into v_currency
  from public.property_assets a join public.investment_projects p on p.id=a.project_id
  where a.id=p_property_asset_id and a.organization_id=p_organization_id and a.project_id=p_project_id;
  if v_currency is null then raise exception 'property does not belong to the project'; end if;
  if p_currency<>v_currency then raise exception 'disposition currency must match project currency'; end if;
  if not exists(select 1 from public.parties p where p.id=p_buyer_party_id and p.organization_id=p_organization_id) then raise exception 'buyer party not found'; end if;

  select encode(digest(jsonb_build_object(
    'project_id',p_project_id,'property_asset_id',p_property_asset_id,'buyer_party_id',p_buyer_party_id,
    'agreement_reference',trim(p_agreement_reference),'agreement_evidence_reference',trim(p_agreement_evidence_reference),
    'agreed_proceeds_minor_units',p_agreed_proceeds_minor_units,'currency',p_currency,
    'agreement_date',p_agreement_date,'expected_control_transfer_date',p_expected_control_transfer_date
  )::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-disposition:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_dispositions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  perform 1 from public.property_assets where id=p_property_asset_id for update;
  if exists(select 1 from public.property_dispositions where property_asset_id=p_property_asset_id) then
    raise exception 'a whole-property disposition already exists for this asset';
  end if;
  insert into public.property_dispositions(
    organization_id,project_id,property_asset_id,buyer_party_id,agreement_reference,
    agreement_evidence_reference,agreed_proceeds_minor_units,currency,agreement_date,
    expected_control_transfer_date,prepared_by,idempotency_key,request_hash
  ) values(
    p_organization_id,p_project_id,p_property_asset_id,p_buyer_party_id,trim(p_agreement_reference),
    trim(p_agreement_evidence_reference),p_agreed_proceeds_minor_units,p_currency,p_agreement_date,
    p_expected_control_transfer_date,v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_DISPOSITION_DRAFTED','property_disposition',v_id,
    jsonb_build_object('project_id',p_project_id,'property_asset_id',p_property_asset_id,
      'buyer_party_id',p_buyer_party_id,'agreed_proceeds_minor_units',p_agreed_proceeds_minor_units,
      'currency',p_currency,'accounting_effect','NONE'));
  return v_id;
end $$;

create or replace function public.approve_property_disposition(
  p_organization_id uuid,p_disposition_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_disp record; v_existing record; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_disposition_id::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-disposition-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_dispositions
  where organization_id=p_organization_id and approval_idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.id<>p_disposition_id or v_existing.approval_request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_disp from public.property_dispositions
  where id=p_disposition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'disposition not found'; end if;
  if v_disp.status<>'DRAFT' then raise exception 'only a draft disposition can be approved'; end if;
  if public.s3_current_property_state(v_disp.property_asset_id) not in ('HELD','DEVELOPING') then
    raise exception 'disposition approval requires a held or developing property';
  end if;
  update public.property_dispositions set status='APPROVED',approved_by=v_actor,approved_at=now(),
    approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash
  where id=p_disposition_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_DISPOSITION_APPROVED','property_disposition',p_disposition_id,
    jsonb_build_object('project_id',v_disp.project_id,'property_asset_id',v_disp.property_asset_id,
      'accounting_effect','NONE'));
  return p_disposition_id;
end $$;

create or replace function public.confirm_property_control_transfer(
  p_organization_id uuid,p_disposition_id uuid,p_control_transfer_date date,
  p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_disp record; v_existing record; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_control_transfer_date is null or p_control_transfer_date>current_date then raise exception 'control transfer date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'control transfer evidence required'; end if;
  select encode(digest(jsonb_build_object('disposition_id',p_disposition_id,
    'control_transfer_date',p_control_transfer_date,'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-control-transfer:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_dispositions
  where organization_id=p_organization_id and transfer_idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.id<>p_disposition_id or v_existing.transfer_request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_disp from public.property_dispositions
  where id=p_disposition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'disposition not found'; end if;
  if v_disp.status<>'APPROVED' then raise exception 'control transfer requires an approved disposition'; end if;
  if p_control_transfer_date<v_disp.agreement_date then raise exception 'control transfer cannot precede agreement'; end if;
  if public.s3_current_property_state(v_disp.property_asset_id)<>'EXITING' then
    raise exception 'control transfer requires the property to be explicitly EXITING';
  end if;
  if not public.s3_has_current_effective_control(v_disp.property_asset_id,'TITLE')
     or not public.s3_has_current_effective_control(v_disp.property_asset_id,'POSSESSION') then
    raise exception 'control transfer requires current effective title and possession evidence';
  end if;
  if exists(
    select 1 from public.development_phases p where p.property_asset_id=v_disp.property_asset_id
      and public.s3_current_phase_state(p.id)='ACTIVE'
  ) then raise exception 'control transfer requires no active development phase'; end if;
  update public.property_dispositions set status='CONTROL_TRANSFERRED',
    control_transfer_date=p_control_transfer_date,
    control_transfer_evidence_reference=trim(p_evidence_reference),
    control_transferred_by=v_actor,control_transferred_at=now(),
    transfer_idempotency_key=trim(p_idempotency_key),transfer_request_hash=v_hash
  where id=p_disposition_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_CONTROL_TRANSFERRED','property_disposition',p_disposition_id,
    jsonb_build_object('project_id',v_disp.project_id,'property_asset_id',v_disp.property_asset_id,
      'control_transfer_date',p_control_transfer_date,'evidence_reference',trim(p_evidence_reference),
      'accounting_effect','NONE'));
  return p_disposition_id;
end $$;

-- Atomic four-line posting:
--   Dr CUSTOMER_RECEIVABLE / Cr REAL_ESTATE_SALE_REVENUE
--   Dr REAL_ESTATE_COST_OF_SALE / Cr DEVELOPMENT_WIP
create or replace function public.recognize_property_sale(
  p_organization_id uuid,p_disposition_id uuid,p_recognition_date date,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_disp record; v_existing record; v_hash text;
  v_recognition_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_receivable uuid; v_revenue uuid; v_cost_of_sale uuid; v_wip uuid;
  v_carrying bigint; v_source_count bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_recognition_date is null or p_recognition_date>current_date then raise exception 'recognition date must be effective'; end if;
  select encode(digest(jsonb_build_object('disposition_id',p_disposition_id,'recognition_date',p_recognition_date)::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-sale-recognize:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_sale_recognitions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.disposition_id<>p_disposition_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_disp from public.property_dispositions
  where id=p_disposition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'disposition not found'; end if;
  if v_disp.status<>'CONTROL_TRANSFERRED' then raise exception 'sale recognition requires confirmed control transfer'; end if;
  if p_recognition_date<v_disp.control_transfer_date then raise exception 'recognition cannot precede control transfer'; end if;
  if public.s3_current_property_state(v_disp.property_asset_id)<>'EXITING' then
    raise exception 'sale recognition requires the property to remain EXITING';
  end if;
  if exists(select 1 from public.property_sale_recognitions where disposition_id=p_disposition_id or property_asset_id=v_disp.property_asset_id) then
    raise exception 'property sale is already recognized';
  end if;

  select coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0),count(*)
    into v_carrying,v_source_count
  from public.property_cost_items pci
  join public.cost_obligations o on o.id=pci.cost_obligation_id and o.cost_treatment='CAPITALIZABLE_WIP'
  join public.journal_batches jb on jb.organization_id=o.organization_id
    and jb.source_type='COST_OBLIGATION' and jb.source_id=o.id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
  join public.journal_lines jl on jl.batch_id=jb.id and jl.obligation_id=o.id
  join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='DEVELOPMENT_WIP'
  where pci.property_asset_id=v_disp.property_asset_id
    and pci.organization_id=p_organization_id and jl.currency=v_disp.currency;
  if v_source_count=0 or v_carrying<=0 then
    raise exception 'authoritative posted carrying cost cannot be derived for this property';
  end if;

  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  select id into v_revenue from public.semantic_accounts where role='REAL_ESTATE_SALE_REVENUE';
  select id into v_cost_of_sale from public.semantic_accounts where role='REAL_ESTATE_COST_OF_SALE';
  select id into v_wip from public.semantic_accounts where role='DEVELOPMENT_WIP';

  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_disp.project_id,'PROPERTY_SALE_RECOGNITION',v_recognition_id,
    p_recognition_date,'s4-sale-batch-'||v_recognition_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_disp.project_id,v_receivable,v_disp.agreed_proceeds_minor_units,0,v_disp.currency,v_disp.buyer_party_id,p_recognition_date),
    (v_batch_id,p_organization_id,v_disp.project_id,v_revenue,0,v_disp.agreed_proceeds_minor_units,v_disp.currency,v_disp.buyer_party_id,p_recognition_date),
    (v_batch_id,p_organization_id,v_disp.project_id,v_cost_of_sale,v_carrying,0,v_disp.currency,null,p_recognition_date),
    (v_batch_id,p_organization_id,v_disp.project_id,v_wip,0,v_carrying,v_disp.currency,null,p_recognition_date);

  insert into public.property_sale_recognitions(
    id,organization_id,project_id,property_asset_id,disposition_id,
    recognized_proceeds_minor_units,carrying_cost_minor_units,currency,recognition_date,
    journal_batch_id,recognized_by,idempotency_key,request_hash
  ) values(
    v_recognition_id,p_organization_id,v_disp.project_id,v_disp.property_asset_id,p_disposition_id,
    v_disp.agreed_proceeds_minor_units,v_carrying,v_disp.currency,p_recognition_date,
    v_batch_id,v_actor,trim(p_idempotency_key),v_hash
  );

  insert into public.property_sale_carrying_cost_sources(
    organization_id,project_id,recognition_id,property_cost_item_id,obligation_id,
    journal_batch_id,journal_line_id,amount_minor_units,currency,policy_reference
  )
  select p_organization_id,v_disp.project_id,v_recognition_id,pci.id,o.id,jb.id,jl.id,
    jl.debit_minor_units-jl.credit_minor_units,jl.currency,pci.policy_reference
  from public.property_cost_items pci
  join public.cost_obligations o on o.id=pci.cost_obligation_id and o.cost_treatment='CAPITALIZABLE_WIP'
  join public.journal_batches jb on jb.organization_id=o.organization_id
    and jb.source_type='COST_OBLIGATION' and jb.source_id=o.id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
  join public.journal_lines jl on jl.batch_id=jb.id and jl.obligation_id=o.id
    and jl.debit_minor_units>jl.credit_minor_units
  join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='DEVELOPMENT_WIP'
  where pci.property_asset_id=v_disp.property_asset_id
    and pci.organization_id=p_organization_id and jl.currency=v_disp.currency;

  if (select sum(amount_minor_units) from public.property_sale_carrying_cost_sources where recognition_id=v_recognition_id)<>v_carrying then
    raise exception 'carrying-cost provenance does not reconcile to derecognition';
  end if;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_SALE_RECOGNIZED','property_sale_recognition',v_recognition_id,
    jsonb_build_object('project_id',v_disp.project_id,'property_asset_id',v_disp.property_asset_id,
      'disposition_id',p_disposition_id,'journal_batch_id',v_batch_id,
      'recognized_proceeds_minor_units',v_disp.agreed_proceeds_minor_units,
      'carrying_cost_minor_units',v_carrying,'currency',v_disp.currency));
  return v_recognition_id;
end $$;

create or replace function public.collect_property_sale_receivable(
  p_organization_id uuid,p_recognition_id uuid,p_cash_account_id uuid,
  p_amount_minor_units bigint,p_collection_date date,p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_rec record; v_disp record; v_existing record; v_hash text;
  v_collection_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid();
  v_cash uuid; v_receivable uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'collection amount must be positive'; end if;
  if p_collection_date is null or p_collection_date>current_date then raise exception 'collection date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'collection evidence required'; end if;
  select encode(digest(jsonb_build_object(
    'recognition_id',p_recognition_id,'cash_account_id',p_cash_account_id,
    'amount_minor_units',p_amount_minor_units,'collection_date',p_collection_date,
    'evidence_reference',trim(p_evidence_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-sale-collection:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_sale_collections
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.recognition_id<>p_recognition_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_rec from public.property_sale_recognitions
  where id=p_recognition_id and organization_id=p_organization_id for update;
  if not found then raise exception 'sale recognition not found'; end if;
  select * into v_disp from public.property_dispositions where id=v_rec.disposition_id;
  if p_collection_date<v_rec.recognition_date then raise exception 'collection cannot precede recognition'; end if;

  insert into public.property_sale_collections(
    id,organization_id,project_id,recognition_id,disposition_id,cash_account_id,
    amount_minor_units,currency,collection_date,evidence_reference,collected_by,
    idempotency_key,request_hash
  ) values(
    v_collection_id,p_organization_id,v_rec.project_id,p_recognition_id,v_rec.disposition_id,p_cash_account_id,
    p_amount_minor_units,v_rec.currency,p_collection_date,trim(p_evidence_reference),v_actor,
    trim(p_idempotency_key),v_hash
  );
  select id into v_cash from public.semantic_accounts where role='BANK_CASH';
  select id into v_receivable from public.semantic_accounts where role='CUSTOMER_RECEIVABLE';
  insert into public.journal_batches(
    id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    v_batch_id,p_organization_id,v_rec.project_id,'PROPERTY_SALE_COLLECTION',v_collection_id,
    p_collection_date,'s4-collection-batch-'||v_collection_id::text,v_hash,v_actor
  );
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
    currency,cash_account_id,party_id,transaction_date
  ) values
    (v_batch_id,p_organization_id,v_rec.project_id,v_cash,p_amount_minor_units,0,v_rec.currency,p_cash_account_id,null,p_collection_date),
    (v_batch_id,p_organization_id,v_rec.project_id,v_receivable,0,p_amount_minor_units,v_rec.currency,null,v_disp.buyer_party_id,p_collection_date);
  update public.property_sale_collections set journal_batch_id=v_batch_id where id=v_collection_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_SALE_COLLECTION_POSTED','property_sale_collection',v_collection_id,
    jsonb_build_object('project_id',v_rec.project_id,'property_asset_id',v_rec.property_asset_id,
      'recognition_id',p_recognition_id,'cash_account_id',p_cash_account_id,'journal_batch_id',v_batch_id,
      'amount_minor_units',p_amount_minor_units,'currency',v_rec.currency));
  return v_collection_id;
end $$;

create or replace function public.reconcile_property_sale_collection(
  p_organization_id uuid,p_collection_id uuid,p_statement_line_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_collection record; v_line record; v_existing record; v_id uuid; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_collection_id::text||'|'||p_statement_line_id::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-collection-reconcile:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_sale_collection_reconciliations
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.collection_id<>p_collection_id or v_existing.statement_line_id<>p_statement_line_id or v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_collection from public.property_sale_collections
  where id=p_collection_id and organization_id=p_organization_id for update;
  if not found or v_collection.journal_batch_id is null then raise exception 'posted collection not found'; end if;
  select * into v_line from public.bank_statement_lines
  where id=p_statement_line_id and organization_id=p_organization_id for update;
  if not found then raise exception 'bank statement line not found'; end if;
  if v_collection.project_id<>v_line.project_id or v_collection.cash_account_id<>v_line.cash_account_id
     or v_collection.currency<>v_line.currency then
    raise exception 'collection and statement line must use the same project cash account and currency';
  end if;
  if v_line.amount_minor_units<>v_collection.amount_minor_units then
    raise exception 'positive statement amount must equal the collection';
  end if;
  insert into public.property_sale_collection_reconciliations(
    organization_id,project_id,collection_id,statement_line_id,cash_account_id,currency,
    matched_by,idempotency_key,request_hash
  ) values(
    p_organization_id,v_collection.project_id,p_collection_id,p_statement_line_id,
    v_collection.cash_account_id,v_collection.currency,v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_SALE_COLLECTION_RECONCILED','property_sale_collection_reconciliation',v_id,
    jsonb_build_object('project_id',v_collection.project_id,'collection_id',p_collection_id,
      'statement_line_id',p_statement_line_id,'accounting_effect','NONE'));
  return v_id;
end $$;

create or replace function public.classify_property_selling_cost(
  p_organization_id uuid,p_cost_obligation_id uuid,p_property_asset_id uuid,
  p_parcel_id uuid,p_phase_id uuid,p_policy_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_obligation record; v_project uuid; v_existing record; v_hash text; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select * into v_obligation from public.cost_obligations
  where id=p_cost_obligation_id and organization_id=p_organization_id;
  if not found then raise exception 'cost obligation not found'; end if;
  if v_obligation.cost_treatment<>'EXPENSE' then raise exception 'selling cost must be an S2 EXPENSE obligation'; end if;
  if v_obligation.status<>'DRAFT' then perform public.s2_require_owner(p_organization_id); end if;
  select project_id into v_project from public.property_assets
  where id=p_property_asset_id and organization_id=p_organization_id;
  if v_project is null or v_project<>v_obligation.project_id then raise exception 'property and obligation must belong to the same project'; end if;
  if p_policy_reference is null or char_length(trim(p_policy_reference)) not between 3 and 200 then raise exception 'selling-cost policy reference required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(jsonb_build_object('obligation_id',p_cost_obligation_id,'property_asset_id',p_property_asset_id,
    'parcel_id',p_parcel_id,'phase_id',p_phase_id,'cost_category','SELLING','policy_reference',trim(p_policy_reference))::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s4-selling-cost:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_cost_items
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  insert into public.property_cost_items(
    organization_id,project_id,property_asset_id,parcel_id,phase_id,cost_obligation_id,
    cost_category,policy_reference,classified_by,idempotency_key,request_hash
  ) values(
    p_organization_id,v_project,p_property_asset_id,p_parcel_id,p_phase_id,p_cost_obligation_id,
    'SELLING',trim(p_policy_reference),v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_SELLING_COST_CLASSIFIED','property_cost_item',v_id,
    jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,
      'obligation_id',p_cost_obligation_id,'accounting_effect','SOURCE_POSTING_ONLY'));
  return v_id;
end $$;

-- ===========================================================================
-- 7. Read models. Every monetary output is text on the wire and every material
--    total carries source IDs for drill-down. Valuation is deliberately separate.
-- ===========================================================================
create or replace view public.property_dispositions_read with (security_invoker=on) as
select d.id as disposition_id,d.organization_id,d.project_id,d.property_asset_id,d.buyer_party_id,
  d.agreement_reference,d.agreement_evidence_reference,d.agreed_proceeds_minor_units::text as agreed_proceeds_minor_units,
  d.currency,d.agreement_date,d.expected_control_transfer_date,d.status,d.prepared_by,d.prepared_at,
  d.approved_by,d.approved_at,d.control_transfer_date,d.control_transfer_evidence_reference,
  d.control_transferred_by,d.control_transferred_at,
  r.id as recognition_id,r.recognition_date,r.journal_batch_id as recognition_batch_id,
  r.recognized_proceeds_minor_units::text as recognized_revenue_minor_units,
  r.carrying_cost_minor_units::text as carrying_cost_minor_units,
  coalesce(c.collected_minor_units,0)::text as collected_minor_units,
  case when r.id is null then '0' else (r.recognized_proceeds_minor_units-coalesce(c.collected_minor_units,0))::text end as outstanding_receivable_minor_units
from public.property_dispositions d
left join public.property_sale_recognitions r on r.disposition_id=d.id
left join lateral (
  select sum(sc.amount_minor_units) as collected_minor_units
  from public.property_sale_collections sc where sc.recognition_id=r.id and sc.journal_batch_id is not null
) c on true;

create or replace view public.property_sale_collections_read with (security_invoker=on) as
select c.id as collection_id,c.organization_id,c.project_id,c.recognition_id,c.disposition_id,
  c.cash_account_id,c.amount_minor_units::text as amount_minor_units,c.currency,c.collection_date,
  c.evidence_reference,c.journal_batch_id,c.collected_by,c.collected_at,
  (m.id is not null) as is_reconciled,m.id as reconciliation_id,m.statement_line_id,m.matched_at
from public.property_sale_collections c
left join public.property_sale_collection_reconciliations m on m.collection_id=c.id
where c.journal_batch_id is not null;

create or replace view public.property_realized_result_read with (security_invoker=on) as
with sale_posting as (
  select r.id as recognition_id,
    coalesce(sum(case when sa.role='REAL_ESTATE_SALE_REVENUE' then jl.credit_minor_units-jl.debit_minor_units else 0 end),0) as revenue,
    coalesce(sum(case when sa.role='REAL_ESTATE_COST_OF_SALE' then jl.debit_minor_units-jl.credit_minor_units else 0 end),0) as carrying
  from public.property_sale_recognitions r
  join public.journal_lines jl on jl.batch_id=r.journal_batch_id
  join public.semantic_accounts sa on sa.id=jl.account_id
  group by r.id
), collection_posting as (
  select c.recognition_id,
    coalesce(sum(case when sa.role='BANK_CASH' then jl.debit_minor_units-jl.credit_minor_units else 0 end),0) as collected
  from public.property_sale_collections c
  join public.journal_lines jl on jl.batch_id=c.journal_batch_id
  join public.semantic_accounts sa on sa.id=jl.account_id
  group by c.recognition_id
), selling_posting as (
  select pci.property_asset_id,
    coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0) as selling_costs
  from public.property_cost_items pci
  join public.journal_lines jl on jl.obligation_id=pci.cost_obligation_id
  join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='PROJECT_EXPENSE'
  where pci.cost_category='SELLING'
  group by pci.property_asset_id
)
select d.organization_id,d.project_id,d.property_asset_id,d.id as disposition_id,r.id as recognition_id,
  d.buyer_party_id,d.currency,r.recognition_date,r.journal_batch_id as recognition_batch_id,
  coalesce(sp.revenue,0)::text as recognized_revenue_minor_units,
  coalesce(sp.carrying,0)::text as carrying_cost_derecognized_minor_units,
  coalesce(sell.selling_costs,0)::text as selling_costs_minor_units,
  (coalesce(sp.revenue,0)-coalesce(sp.carrying,0)-coalesce(sell.selling_costs,0))::text as realized_result_minor_units,
  coalesce(cp.collected,0)::text as collected_cash_minor_units,
  (coalesce(sp.revenue,0)-coalesce(cp.collected,0))::text as outstanding_receivable_minor_units,
  val.valuation_id as latest_management_valuation_id,
  val.amount_minor_units::text as latest_management_valuation_minor_units,
  val.effective_date as latest_management_valuation_date,val.valuer_source as latest_management_valuation_source,
  val.method as latest_management_valuation_method,val.evidence_reference as latest_management_valuation_evidence_reference
from public.property_dispositions d
join public.property_sale_recognitions r on r.disposition_id=d.id
left join sale_posting sp on sp.recognition_id=r.id
left join collection_posting cp on cp.recognition_id=r.id
left join selling_posting sell on sell.property_asset_id=d.property_asset_id
left join lateral (
  select v.id as valuation_id,v.amount_minor_units,v.effective_date,v.valuer_source,v.method,v.evidence_reference
  from public.property_valuations v
  where v.property_asset_id=d.property_asset_id and v.status='APPROVED'
  order by v.effective_date desc,v.reviewed_at desc,v.id desc limit 1
) val on true;

create or replace view public.property_realized_result_drilldown_read with (security_invoker=on) as
select d.organization_id,d.project_id,d.property_asset_id,d.id as disposition_id,
  case when sa.role in ('REAL_ESTATE_SALE_REVENUE','CUSTOMER_RECEIVABLE') then 'SALE_RECOGNITION'
       else 'CARRYING_COST_DERECOGNITION' end as fact_type,
  r.id as source_entity_id,r.journal_batch_id,jl.id as journal_line_id,sa.role as account_role,
  jl.debit_minor_units::text as debit_minor_units,jl.credit_minor_units::text as credit_minor_units,
  jl.currency,jl.transaction_date,d.control_transfer_evidence_reference as evidence_reference
from public.property_dispositions d
join public.property_sale_recognitions r on r.disposition_id=d.id
join public.journal_lines jl on jl.batch_id=r.journal_batch_id
join public.semantic_accounts sa on sa.id=jl.account_id
union all
select d.organization_id,d.project_id,d.property_asset_id,d.id,'CARRYING_COST_SOURCE',
  src.obligation_id,src.journal_batch_id,src.journal_line_id,'DEVELOPMENT_WIP',
  src.amount_minor_units::text,'0',src.currency,jl.transaction_date,src.policy_reference
from public.property_dispositions d
join public.property_sale_recognitions r on r.disposition_id=d.id
join public.property_sale_carrying_cost_sources src on src.recognition_id=r.id
join public.journal_lines jl on jl.id=src.journal_line_id
union all
select d.organization_id,d.project_id,d.property_asset_id,d.id,'COLLECTION',
  c.id,c.journal_batch_id,jl.id,sa.role,jl.debit_minor_units::text,jl.credit_minor_units::text,
  jl.currency,jl.transaction_date,c.evidence_reference
from public.property_dispositions d
join public.property_sale_collections c on c.disposition_id=d.id and c.journal_batch_id is not null
join public.journal_lines jl on jl.batch_id=c.journal_batch_id
join public.semantic_accounts sa on sa.id=jl.account_id
union all
select d.organization_id,d.project_id,d.property_asset_id,d.id,'SELLING_COST',
  pci.cost_obligation_id,jb.id,jl.id,sa.role,jl.debit_minor_units::text,jl.credit_minor_units::text,
  jl.currency,jl.transaction_date,pci.policy_reference
from public.property_dispositions d
join public.property_cost_items pci on pci.property_asset_id=d.property_asset_id and pci.cost_category='SELLING'
join public.journal_lines jl on jl.obligation_id=pci.cost_obligation_id
join public.journal_batches jb on jb.id=jl.batch_id
join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='PROJECT_EXPENSE';

-- Preserve the S2 read shape while exposing customer-collection matching.
create or replace view public.bank_statement_line_status_read with (security_invoker=on) as
select l.id as line_id,l.organization_id,l.project_id,l.cash_account_id,l.import_id,
  l.provider_reference,l.transaction_date,l.amount_minor_units::text as amount_minor_units,
  l.currency,l.description,l.fingerprint,l.created_at,
  (pm.id is not null or cm.id is not null) as is_reconciled,
  coalesce(pm.id,cm.id) as match_id,pm.payment_id as matched_payment_id,
  coalesce(pm.matched_at,cm.matched_at) as matched_at,
  cm.collection_id as matched_collection_id
from public.bank_statement_lines l
left join public.reconciliation_matches pm on pm.statement_line_id=l.id and pm.voided_at is null
left join public.property_sale_collection_reconciliations cm on cm.statement_line_id=l.id;

-- ===========================================================================
-- 8. RLS/default-deny and command registry.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'property_dispositions','property_sale_recognitions','property_sale_carrying_cost_sources',
    'property_sale_collections','property_sale_collection_reconciliations',
    'bank_statement_reconciliation_allocations'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
  end loop;
end $$;

grant select on public.property_dispositions,public.property_sale_recognitions,
  public.property_sale_carrying_cost_sources,public.property_sale_collections,
  public.property_sale_collection_reconciliations to authenticated;
grant select on public.property_dispositions_read,public.property_sale_collections_read,
  public.property_realized_result_read,public.property_realized_result_drilldown_read to authenticated;

-- Allocation rows are an internal uniqueness primitive, not a browser read model.
revoke all on public.bank_statement_reconciliation_allocations from authenticated;

revoke all on function public.create_property_disposition(uuid,uuid,uuid,uuid,text,text,bigint,text,date,date,text) from public,anon;
revoke all on function public.approve_property_disposition(uuid,uuid,text) from public,anon;
revoke all on function public.confirm_property_control_transfer(uuid,uuid,date,text,text) from public,anon;
revoke all on function public.recognize_property_sale(uuid,uuid,date,text) from public,anon;
revoke all on function public.collect_property_sale_receivable(uuid,uuid,uuid,bigint,date,text,text) from public,anon;
revoke all on function public.reconcile_property_sale_collection(uuid,uuid,uuid,text) from public,anon;
revoke all on function public.classify_property_selling_cost(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;

grant execute on function public.create_property_disposition(uuid,uuid,uuid,uuid,text,text,bigint,text,date,date,text),
  public.approve_property_disposition(uuid,uuid,text),
  public.confirm_property_control_transfer(uuid,uuid,date,text,text),
  public.recognize_property_sale(uuid,uuid,date,text),
  public.collect_property_sale_receivable(uuid,uuid,uuid,bigint,date,text,text),
  public.reconcile_property_sale_collection(uuid,uuid,uuid,text),
  public.classify_property_selling_cost(uuid,uuid,uuid,uuid,uuid,text,text)
to authenticated;
