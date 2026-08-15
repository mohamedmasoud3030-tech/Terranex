-- GF-024 — Livestock Commercial, Profitability & Closeout.
--
-- Completes the Livestock commercial operating cycle on top of the merged
-- GF-020/GF-021/GF-022 boundary: bounded external purchase intake, sale with
-- control-transfer, shared Finance Core revenue/receivable/collection, posted
-- cost attribution to Cohort, reproducible profitability, and a technical
-- closeout layer that reuses S6 period-close/correction infrastructure.
--
-- Physical truth stays the exact-integer, event-derived quantity ledger.
-- Money lives only in the shared balanced journal under locked semantic roles.
-- No second ledger, no mutable balances, no guessed COGS, no IAS 41 posting.

-- ===========================================================================
-- 1. Extend the locked shared-core account/source registries (forward-only).
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE'
));
insert into public.semantic_accounts(role, label_ar)
values ('LIVESTOCK_SALE_REVENUE','إيراد بيع مواشي')
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
  'LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION'
));

-- ===========================================================================
-- 2. Register the two commercial quantity classes forward-only.
-- ===========================================================================
-- PURCHASE_IN is a later externally purchased addition, never the GF-020
-- opening quantity. SALE_OUT is the physical issue for a recognized sale.
-- Neither is an operation leg; neither requires a cause or a disposal method.
insert into public.livestock_quantity_event_types(
  code, direction, label_ar, introduced_in, requires_operation, requires_cause, requires_disposal
) values
  ('PURCHASE_IN',  1, 'شراء / إضافة خارجية', 'GF-024', false, false, false),
  ('SALE_OUT',    -1, 'صادر بيع',            'GF-024', false, false, false)
on conflict (code) do nothing;

-- The GF-022 rollforward view is left intact: its column list is canonical
-- and the GF-022 concurrency invariant reads it directly. GF-024 surfaces the
-- two commercial classes only through its own read models, computed from the
-- same immutable event ledger. The existing aggregate increase/decrease and
-- current_quantity columns already include PURCHASE_IN and SALE_OUT.

-- ===========================================================================
-- 3. SCOPE A — Bounded external purchase intake.
-- ===========================================================================
create table public.livestock_purchases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  supplier_party_id uuid not null,
  purchase_reference text not null check (char_length(trim(purchase_reference)) between 1 and 120),
  agreement_reference text
    check (agreement_reference is null or char_length(trim(agreement_reference)) between 2 and 200),
  effective_at timestamptz not null,
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict
);
create unique index livestock_purchases_project_reference_key
  on public.livestock_purchases(organization_id, project_id, lower(purchase_reference));
create index livestock_purchases_project_idx
  on public.livestock_purchases(project_id, effective_at desc);

create table public.livestock_purchase_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  purchase_id uuid not null,
  line_no integer not null check (line_no > 0),
  cohort_id uuid not null,
  quantity integer not null check (quantity > 0),
  -- Optional commercial agreement snapshot. Never posted; never a balance.
  agreed_unit_price_minor_units bigint check (agreed_unit_price_minor_units is null or agreed_unit_price_minor_units > 0),
  agreed_amount_minor_units bigint check (agreed_amount_minor_units is null or agreed_amount_minor_units > 0),
  constraint livestock_purchase_lines_amount_coherent check (
    (agreed_unit_price_minor_units is null and agreed_amount_minor_units is null)
    or (agreed_unit_price_minor_units is not null
        and agreed_amount_minor_units is not null
        and agreed_amount_minor_units = quantity::bigint * agreed_unit_price_minor_units)
  ),
  unique (purchase_id, line_no),
  unique (purchase_id, cohort_id),
  unique (id, organization_id, project_id),
  foreign key (purchase_id, organization_id, project_id)
    references public.livestock_purchases(id, organization_id, project_id) on delete restrict,
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_purchase_lines_purchase_idx
  on public.livestock_purchase_lines(purchase_id);
create index livestock_purchase_lines_cohort_idx
  on public.livestock_purchase_lines(cohort_id);

-- ===========================================================================
-- 4. SCOPE B/C — Sale aggregate, immutable lines, recognition, collection.
-- ===========================================================================
create table public.livestock_sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  buyer_party_id uuid not null,
  sale_reference text not null check (char_length(trim(sale_reference)) between 1 and 120),
  agreement_reference text
    check (agreement_reference is null or char_length(trim(agreement_reference)) between 2 and 200),
  sale_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  terms text check (terms is null or char_length(trim(terms)) between 2 and 1000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'DRAFT'
    check (status in ('DRAFT','APPROVED','CONTROL_TRANSFERRED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text
    check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text
    check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  control_transfer_date date,
  control_transfer_evidence_reference text check (
    control_transfer_evidence_reference is null
    or char_length(trim(control_transfer_evidence_reference)) between 3 and 200
  ),
  control_transferred_by uuid references auth.users(id) on delete restrict,
  control_transferred_at timestamptz,
  transfer_idempotency_key text
    check (transfer_idempotency_key is null or char_length(transfer_idempotency_key) between 8 and 120),
  transfer_request_hash text
    check (transfer_request_hash is null or char_length(transfer_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (
    (status = 'DRAFT' and approved_by is null and approved_at is null
      and approval_idempotency_key is null and approval_request_hash is null
      and control_transfer_date is null and control_transfer_evidence_reference is null
      and control_transferred_by is null and control_transferred_at is null
      and transfer_idempotency_key is null and transfer_request_hash is null)
    or
    (status = 'APPROVED' and approved_by is not null and approved_at is not null
      and approval_idempotency_key is not null and approval_request_hash is not null
      and control_transfer_date is null and control_transfer_evidence_reference is null
      and control_transferred_by is null and control_transferred_at is null
      and transfer_idempotency_key is null and transfer_request_hash is null)
    or
    (status = 'CONTROL_TRANSFERRED' and approved_by is not null and approved_at is not null
      and approval_idempotency_key is not null and approval_request_hash is not null
      and control_transfer_date is not null and control_transfer_date >= sale_date
      and control_transfer_evidence_reference is not null
      and control_transferred_by is not null and control_transferred_at is not null
      and transfer_idempotency_key is not null and transfer_request_hash is not null)
  ),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (buyer_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict
);
create unique index livestock_sales_project_reference_key
  on public.livestock_sales(organization_id, project_id, lower(sale_reference));
create unique index livestock_sales_approval_key
  on public.livestock_sales(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;
create unique index livestock_sales_transfer_key
  on public.livestock_sales(organization_id, transfer_idempotency_key)
  where transfer_idempotency_key is not null;
create index livestock_sales_project_idx
  on public.livestock_sales(project_id, sale_date desc);

create table public.livestock_sale_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  sale_id uuid not null,
  line_no integer not null check (line_no > 0),
  cohort_id uuid not null,
  quantity integer not null check (quantity > 0),
  unit_price_minor_units bigint not null check (unit_price_minor_units > 0),
  line_amount_minor_units bigint not null check (line_amount_minor_units > 0),
  -- Exact integer money: headcount is an integer, so amount = qty × price is
  -- an exact bigint with no rounding residual.
  constraint livestock_sale_lines_amount_matches
    check (line_amount_minor_units = quantity::bigint * unit_price_minor_units),
  unique (sale_id, line_no),
  unique (sale_id, cohort_id),
  unique (id, organization_id, project_id),
  foreign key (sale_id, organization_id, project_id)
    references public.livestock_sales(id, organization_id, project_id) on delete restrict,
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_sale_lines_sale_idx on public.livestock_sale_lines(sale_id);
create index livestock_sale_lines_cohort_idx on public.livestock_sale_lines(cohort_id);

create table public.livestock_sale_recognitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  sale_id uuid not null,
  recognized_revenue_minor_units bigint not null check (recognized_revenue_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  recognition_date date not null,
  journal_batch_id uuid not null,
  recognized_by uuid not null references auth.users(id) on delete restrict,
  recognized_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (sale_id),
  unique (journal_batch_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (sale_id, organization_id, project_id)
    references public.livestock_sales(id, organization_id, project_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index livestock_sale_recognitions_project_idx
  on public.livestock_sale_recognitions(project_id, recognition_date desc);

create table public.livestock_sale_collections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  recognition_id uuid not null,
  sale_id uuid not null,
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
  unique (journal_batch_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (recognition_id, organization_id, project_id)
    references public.livestock_sale_recognitions(id, organization_id, project_id) on delete restrict,
  foreign key (sale_id, organization_id, project_id)
    references public.livestock_sales(id, organization_id, project_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index livestock_sale_collections_recognition_idx
  on public.livestock_sale_collections(recognition_id, collection_date);

-- ===========================================================================
-- 5. SCOPE D — Posted-cost attribution to Cohort (Finance Core truth only).
-- ===========================================================================
create table public.livestock_cohort_cost_attributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  source_journal_line_id uuid not null,
  attributed_amount_minor_units bigint not null check (attributed_amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  cost_category text not null check (cost_category in (
    'ACQUISITION','FEED','HEALTH','LABOR','FACILITIES','TRANSPORT','OTHER'
  )),
  policy_reference text not null check (char_length(trim(policy_reference)) between 3 and 200),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  reversal_of_attribution_id uuid,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  unique (reversal_of_attribution_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (source_journal_line_id, organization_id)
    references public.journal_lines(id, organization_id) on delete restrict,
  foreign key (reversal_of_attribution_id, organization_id)
    references public.livestock_cohort_cost_attributions(id, organization_id) on delete restrict
);
create index livestock_cost_attributions_cohort_idx
  on public.livestock_cohort_cost_attributions(cohort_id, recorded_at);
create index livestock_cost_attributions_source_idx
  on public.livestock_cohort_cost_attributions(source_journal_line_id);

-- ===========================================================================
-- 6. SCOPE E — Technical closeout metadata (no lifecycle mutation).
-- ===========================================================================
create table public.livestock_cohort_closeouts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  close_reason text not null check (char_length(trim(close_reason)) between 3 and 500),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  closed_by uuid not null references auth.users(id) on delete restrict,
  closed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (cohort_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_cohort_closeouts_project_idx
  on public.livestock_cohort_closeouts(project_id, closed_at desc);

-- ===========================================================================
-- 7. Cross-fact integrity, immutability and controlled header transitions.
-- ===========================================================================

create function public.gf024_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'livestock commercial, profitability and closeout facts are append-only';
end $$;

create function public.gf024_guard_sale_line_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_status text;
begin
  select status into v_status from public.livestock_sales
  where id = new.sale_id and organization_id = new.organization_id
    and project_id = new.project_id;
  if v_status is distinct from 'DRAFT' then
    raise exception 'livestock sale lines may only be added while the sale is draft';
  end if;
  return new;
end $$;

create function public.gf024_guard_recognition_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_sale public.livestock_sales%rowtype;
  v_batch public.journal_batches%rowtype;
  v_total numeric;
  v_line_count integer;
  v_receivable_count integer;
  v_revenue_count integer;
begin
  select * into v_sale from public.livestock_sales
  where id = new.sale_id and organization_id = new.organization_id
    and project_id = new.project_id for update;
  if not found or v_sale.status <> 'APPROVED' or new.currency <> v_sale.currency
     or new.recognition_date < v_sale.sale_date then
    raise exception 'livestock sale recognition does not match the approved sale';
  end if;
  select sum(line_amount_minor_units::numeric) into v_total
  from public.livestock_sale_lines where sale_id = new.sale_id;
  if v_total is null or v_total <> new.recognized_revenue_minor_units then
    raise exception 'livestock sale recognition total does not match immutable lines';
  end if;
  select * into v_batch from public.journal_batches
  where id = new.journal_batch_id and organization_id = new.organization_id;
  if not found or v_batch.project_id <> new.project_id
     or v_batch.source_type <> 'LIVESTOCK_SALE_RECOGNITION'
     or v_batch.source_id <> new.id or v_batch.transaction_date <> new.recognition_date then
    raise exception 'livestock sale recognition journal source mismatch';
  end if;
  select count(*),
    count(*) filter (where sa.role = 'CUSTOMER_RECEIVABLE'
      and jl.debit_minor_units = new.recognized_revenue_minor_units
      and jl.credit_minor_units = 0 and jl.currency = new.currency
      and jl.party_id = v_sale.buyer_party_id),
    count(*) filter (where sa.role = 'LIVESTOCK_SALE_REVENUE'
      and jl.credit_minor_units = new.recognized_revenue_minor_units
      and jl.debit_minor_units = 0 and jl.currency = new.currency
      and jl.party_id = v_sale.buyer_party_id)
    into v_line_count, v_receivable_count, v_revenue_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jl.batch_id = new.journal_batch_id and jl.organization_id = new.organization_id
    and jl.project_id = new.project_id and jl.transaction_date = new.recognition_date;
  if v_line_count <> 2 or v_receivable_count <> 1 or v_revenue_count <> 1 then
    raise exception 'livestock sale recognition journal is not the canonical receivable/revenue posting';
  end if;
  return new;
end $$;

create function public.gf024_guard_collection_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_rec public.livestock_sale_recognitions%rowtype;
  v_sale public.livestock_sales%rowtype;
  v_batch public.journal_batches%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_collected numeric;
  v_line_count integer;
  v_cash_count integer;
  v_receivable_count integer;
begin
  select * into v_rec from public.livestock_sale_recognitions
  where id = new.recognition_id and organization_id = new.organization_id
    and project_id = new.project_id for update;
  if not found or new.sale_id <> v_rec.sale_id or new.currency <> v_rec.currency
     or new.collection_date < v_rec.recognition_date then
    raise exception 'livestock sale collection does not match its recognition';
  end if;
  select * into v_sale from public.livestock_sales where id = v_rec.sale_id;
  select * into v_account from public.project_cash_accounts
  where id = new.cash_account_id and organization_id = new.organization_id;
  if not found or v_account.project_id <> new.project_id or v_account.currency <> new.currency then
    raise exception 'livestock sale collection cash account scope mismatch';
  end if;
  select coalesce(sum(amount_minor_units::numeric), 0) into v_collected
  from public.livestock_sale_collections where recognition_id = new.recognition_id;
  if v_collected + new.amount_minor_units > v_rec.recognized_revenue_minor_units then
    raise exception 'collection exceeds outstanding livestock receivable';
  end if;
  select * into v_batch from public.journal_batches
  where id = new.journal_batch_id and organization_id = new.organization_id;
  if not found or v_batch.project_id <> new.project_id
     or v_batch.source_type <> 'LIVESTOCK_SALE_COLLECTION'
     or v_batch.source_id <> new.id or v_batch.transaction_date <> new.collection_date then
    raise exception 'livestock sale collection journal source mismatch';
  end if;
  select count(*),
    count(*) filter (where sa.role = 'BANK_CASH'
      and jl.debit_minor_units = new.amount_minor_units
      and jl.credit_minor_units = 0 and jl.currency = new.currency
      and jl.cash_account_id = new.cash_account_id),
    count(*) filter (where sa.role = 'CUSTOMER_RECEIVABLE'
      and jl.credit_minor_units = new.amount_minor_units
      and jl.debit_minor_units = 0 and jl.currency = new.currency
      and jl.party_id = v_sale.buyer_party_id)
    into v_line_count, v_cash_count, v_receivable_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jl.batch_id = new.journal_batch_id and jl.organization_id = new.organization_id
    and jl.project_id = new.project_id and jl.transaction_date = new.collection_date;
  if v_line_count <> 2 or v_cash_count <> 1 or v_receivable_count <> 1 then
    raise exception 'livestock sale collection journal is not the canonical cash/receivable posting';
  end if;
  return new;
end $$;

create function public.gf024_guard_sale_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.organization_id <> old.organization_id or new.project_id <> old.project_id
     or new.buyer_party_id <> old.buyer_party_id or new.sale_reference <> old.sale_reference
     or new.agreement_reference is distinct from old.agreement_reference
     or new.sale_date <> old.sale_date or new.currency <> old.currency
     or new.terms is distinct from old.terms
     or new.evidence_reference is distinct from old.evidence_reference
     or new.prepared_by <> old.prepared_by or new.prepared_at <> old.prepared_at
     or new.idempotency_key <> old.idempotency_key or new.request_hash <> old.request_hash then
    raise exception 'livestock sale economics are immutable';
  end if;
  if old.status = 'DRAFT' and new.status = 'APPROVED' then
    if new.approved_by is null or new.approved_at is null
       or new.approval_idempotency_key is null or new.approval_request_hash is null
       or new.control_transfer_date is not null then
      raise exception 'invalid livestock sale approval transition';
    end if;
  elsif old.status = 'APPROVED' and new.status = 'CONTROL_TRANSFERRED' then
    if new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
       or new.approval_idempotency_key is distinct from old.approval_idempotency_key
       or new.approval_request_hash is distinct from old.approval_request_hash
       or new.control_transfer_date is null
       or new.control_transfer_evidence_reference is null
       or new.control_transferred_by is null or new.control_transferred_at is null
       or new.transfer_idempotency_key is null or new.transfer_request_hash is null then
      raise exception 'invalid livestock sale control-transfer transition';
    end if;
  else
    raise exception 'invalid livestock sale lifecycle transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;

-- A generic journal-only reversal must not detach Finance Core from immutable
-- SALE_OUT/control-transfer truth. Correction travels the controlled S6 path.
create function public.gf024_guard_sale_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_target_type text;
begin
  if new.source_type <> 'REVERSAL' then return new; end if;
  select source_type into v_target_type from public.journal_batches
  where id = new.source_id and organization_id = new.organization_id;
  if v_target_type in ('LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION') then
    raise exception 'Livestock sale correction requires controlled S6 correction policy';
  end if;
  return new;
end $$;

-- Cost attribution: source authority, ceiling, and append-only offset.
create function public.gf024_guard_cost_attribution_insert() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_line public.journal_lines%rowtype;
  v_batch public.journal_batches%rowtype;
  v_role text;
  v_existing_amount numeric;
  v_original public.livestock_cohort_cost_attributions%rowtype;
begin
  select * into v_line from public.journal_lines
  where id = new.source_journal_line_id and organization_id = new.organization_id
  for update;
  if not found then raise exception 'authoritative posted cost source not found'; end if;
  select * into v_batch from public.journal_batches
  where id = v_line.batch_id and organization_id = new.organization_id;
  select role into v_role from public.semantic_accounts where id = v_line.account_id;

  if v_line.project_id <> new.project_id or v_batch.project_id <> new.project_id then
    raise exception 'posted cost source does not belong to livestock cohort project';
  end if;
  if v_batch.source_type <> 'COST_OBLIGATION' or v_role <> 'PROJECT_EXPENSE'
     or v_line.debit_minor_units <= 0 or v_line.credit_minor_units <> 0
     or v_line.currency <> new.currency then
    raise exception 'source is not an authoritative posted operating expense';
  end if;
  if exists (select 1 from public.journal_batches r
             where r.reversal_of_batch_id = v_batch.id) then
    raise exception 'posted cost source has been reversed';
  end if;

  if new.reversal_of_attribution_id is not null then
    select * into v_original from public.livestock_cohort_cost_attributions
    where id = new.reversal_of_attribution_id and organization_id = new.organization_id
    for update;
    if not found or v_original.reversal_of_attribution_id is not null then
      raise exception 'livestock cost attribution reversal target is invalid';
    end if;
    if exists (select 1 from public.livestock_cohort_cost_attributions
               where reversal_of_attribution_id = v_original.id) then
      raise exception 'livestock cost attribution is already reversed';
    end if;
    if new.project_id <> v_original.project_id
       or new.cohort_id <> v_original.cohort_id
       or new.source_journal_line_id <> v_original.source_journal_line_id
       or new.attributed_amount_minor_units <> v_original.attributed_amount_minor_units
       or new.currency <> v_original.currency
       or new.cost_category <> v_original.cost_category then
      raise exception 'livestock cost attribution reversal must exactly offset the original attribution';
    end if;
    return new;
  end if;

  select coalesce(sum(a.attributed_amount_minor_units::numeric), 0)
    into v_existing_amount
  from public.livestock_cohort_cost_attributions a
  where a.source_journal_line_id = new.source_journal_line_id
    and a.reversal_of_attribution_id is null
    and not exists (select 1 from public.livestock_cohort_cost_attributions r
                    where r.reversal_of_attribution_id = a.id);
  if v_existing_amount + new.attributed_amount_minor_units > v_line.debit_minor_units then
    raise exception 'livestock cohort cost attribution exceeds authoritative source amount';
  end if;
  return new;
end $$;

-- An attributed Finance source cannot be reversed until its active attributions
-- are offset; otherwise the dimension would silently point at reversed truth.
create function public.gf024_guard_attributed_cost_source_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type = 'REVERSAL' and exists (
    select 1
    from public.livestock_cohort_cost_attributions a
    join public.journal_lines jl on jl.id = a.source_journal_line_id
    where jl.batch_id = new.source_id
      and a.reversal_of_attribution_id is null
      and not exists (select 1 from public.livestock_cohort_cost_attributions r
                      where r.reversal_of_attribution_id = a.id)
  ) then
    raise exception 'reverse active livestock cohort cost attributions before reversing the Finance source';
  end if;
  return new;
end $$;

-- Attach all the guards.
do $gf024_guards$
declare t text;
begin
  foreach t in array array[
    'livestock_purchases','livestock_purchase_lines',
    'livestock_sales','livestock_sale_lines',
    'livestock_sale_recognitions','livestock_sale_collections',
    'livestock_cohort_cost_attributions','livestock_cohort_closeouts'
  ] loop
    execute format('create trigger %I_sector_guard before insert on public.%I for each row execute function public.gf020_sector_guard()', t, t);
    execute format('create trigger %I_no_change before update or delete on public.%I for each row execute function public.gf024_immutable()', t, t);
  end loop;
end
$gf024_guards$;

-- The sale header is the one exception to full append-only: only the
-- DRAFT->APPROVED->CONTROL_TRANSFERRED chain may update it.
drop trigger if exists livestock_sales_no_change on public.livestock_sales;
create trigger livestock_sales_transition_only
before update on public.livestock_sales
for each row execute function public.gf024_guard_sale_transition();
create trigger livestock_sales_no_delete
before delete on public.livestock_sales
for each row execute function public.gf024_immutable();

create trigger livestock_sale_lines_insert_guard
before insert on public.livestock_sale_lines
for each row execute function public.gf024_guard_sale_line_insert();
create trigger livestock_sale_recognitions_insert_guard
before insert on public.livestock_sale_recognitions
for each row execute function public.gf024_guard_recognition_insert();
create trigger livestock_sale_collections_insert_guard
before insert on public.livestock_sale_collections
for each row execute function public.gf024_guard_collection_insert();
create trigger journal_batches_gf024_sale_reversal_guard
before insert on public.journal_batches
for each row execute function public.gf024_guard_sale_reversal();
create trigger livestock_cost_attributions_insert_guard
before insert on public.livestock_cohort_cost_attributions
for each row execute function public.gf024_guard_cost_attribution_insert();
create trigger journal_batches_gf024_attributed_cost_reversal_guard
before insert on public.journal_batches
for each row execute function public.gf024_guard_attributed_cost_source_reversal();

-- ===========================================================================
-- 8. Commands.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 8.A — Atomic external purchase intake: header + lines + PURCHASE_IN events.
-- ---------------------------------------------------------------------------
create function public.record_livestock_purchase(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_purchase_reference text,
  p_agreement_reference text,
  p_effective_at timestamptz,
  p_evidence_reference text,
  p_notes text,
  p_cohort_ids uuid[],
  p_quantities integer[],
  p_agreed_unit_price_minor_units bigint[],
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_purchase_id uuid := gen_random_uuid();
  v_hash text;
  v_existing public.livestock_purchases%rowtype;
  v_count integer;
  v_i integer;
  v_line_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_supplier_party_id::text || '|' ||
    trim(coalesce(p_purchase_reference, '')) || '|' ||
    coalesce(trim(p_agreement_reference), '') || '|' ||
    coalesce(p_effective_at::text, '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' ||
    coalesce(trim(p_notes), '') || '|' ||
    coalesce(array_to_string(p_cohort_ids, ','), '') || '|' ||
    coalesce(array_to_string(p_quantities, ','), '') || '|' ||
    coalesce(array_to_string(p_agreed_unit_price_minor_units, ','), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-purchase:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_purchases
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  if not exists (
    select 1 from public.parties
    where id = p_supplier_party_id and organization_id = p_organization_id
  ) then raise exception 'supplier party not found'; end if;
  if p_purchase_reference is null or char_length(trim(p_purchase_reference)) not between 1 and 120 then
    raise exception 'livestock purchase reference required';
  end if;
  if p_agreement_reference is not null and char_length(trim(p_agreement_reference)) not between 2 and 200 then
    raise exception 'invalid purchase agreement reference';
  end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid purchase evidence';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 3 and 2000 then
    raise exception 'invalid purchase notes';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock purchase effective time'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_count := coalesce(cardinality(p_cohort_ids), 0);
  if v_count < 1 or v_count > 50
     or coalesce(cardinality(p_quantities), 0) <> v_count
     or (p_agreed_unit_price_minor_units is not null
         and cardinality(p_agreed_unit_price_minor_units) <> v_count) then
    raise exception 'livestock purchase requires one to fifty coherent lines';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_project_id::text || ':gf024-purchase-ref:' ||
    lower(trim(p_purchase_reference)), 0
  ));
  if exists (
    select 1 from public.livestock_purchases
    where organization_id = p_organization_id and project_id = p_project_id
      and lower(purchase_reference) = lower(trim(p_purchase_reference))
  ) then raise exception 'livestock purchase reference already exists'; end if;

  -- Validate every line before creating any part of the aggregate.
  for v_i in 1..v_count loop
    if p_quantities[v_i] is null or p_quantities[v_i] <= 0 then
      raise exception 'livestock purchase quantity must be positive';
    end if;
    if not exists (
      select 1 from public.livestock_cohorts
      where id = p_cohort_ids[v_i] and organization_id = p_organization_id
        and project_id = p_project_id
    ) then raise exception 'livestock cohort not found for purchase line %', v_i; end if;
    if p_agreed_unit_price_minor_units is not null
       and (p_agreed_unit_price_minor_units[v_i] is null
            or p_agreed_unit_price_minor_units[v_i] <= 0) then
      raise exception 'agreed purchase unit price must be positive for line %', v_i;
    end if;
    if exists (
      select 1 from unnest(p_cohort_ids) with ordinality as x(c, n)
      where n < v_i and c = p_cohort_ids[v_i]
    ) then raise exception 'duplicate cohort in livestock purchase lines'; end if;
  end loop;

  insert into public.livestock_purchases(
    id, organization_id, project_id, supplier_party_id, purchase_reference,
    agreement_reference, effective_at, evidence_reference, notes,
    prepared_by, idempotency_key, request_hash
  ) values (
    v_purchase_id, p_organization_id, p_project_id, p_supplier_party_id,
    trim(p_purchase_reference), nullif(trim(p_agreement_reference), ''),
    p_effective_at, nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  );

  -- Lock Cohorts in a deterministic order so two concurrent purchases sharing
  -- a Cohort cannot deadlock; then serialize each against concurrent quantity
  -- change so the PURCHASE_IN lands on a stable derived timeline.
  perform 1 from public.livestock_cohorts c
  where c.id = any(p_cohort_ids) order by c.id for update of c;

  for v_i in 1..v_count loop
    perform public.gf022_lock_cohort_quantity(p_cohort_ids[v_i]);
    perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_ids[v_i]);

    insert into public.livestock_purchase_lines(
      organization_id, project_id, purchase_id, line_no, cohort_id, quantity,
      agreed_unit_price_minor_units, agreed_amount_minor_units
    ) values (
      p_organization_id, p_project_id, v_purchase_id, v_i, p_cohort_ids[v_i],
      p_quantities[v_i],
      case when p_agreed_unit_price_minor_units is null then null
           else p_agreed_unit_price_minor_units[v_i] end,
      case when p_agreed_unit_price_minor_units is null then null
           else p_quantities[v_i]::bigint * p_agreed_unit_price_minor_units[v_i] end
    ) returning id into v_line_id;

    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      evidence_reference, notes, recorded_by, idempotency_key, request_hash
    ) values (
      p_organization_id, p_project_id, p_cohort_ids[v_i], 'PURCHASE_IN', p_quantities[v_i],
      p_effective_at, nullif(trim(p_evidence_reference), ''), null,
      v_actor, 'gf024-purchase-in-' || v_line_id::text,
      public.gf020_hash(v_line_id::text || '|PURCHASE_IN')
    );
  end loop;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_PURCHASE_RECORDED', 'livestock_purchase',
    v_purchase_id,
    jsonb_build_object('project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
                       'line_count', v_count, 'effective_at', p_effective_at,
                       'accounting_effect', 'NONE', 'quantity_effect', 'PURCHASE_IN')
  );
  return v_purchase_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.B — Draft a bounded livestock sale (no quantity or accounting effect).
-- ---------------------------------------------------------------------------
create function public.create_livestock_sale(
  p_organization_id uuid,
  p_project_id uuid,
  p_buyer_party_id uuid,
  p_sale_reference text,
  p_agreement_reference text,
  p_sale_date date,
  p_currency text,
  p_terms text,
  p_evidence_reference text,
  p_cohort_ids uuid[],
  p_quantities integer[],
  p_unit_price_minor_units bigint[],
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_sale_id uuid := gen_random_uuid();
  v_hash text;
  v_existing public.livestock_sales%rowtype;
  v_project_currency text;
  v_count integer;
  v_i integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  select reporting_currency into v_project_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id and sector = 'LIVESTOCK';
  if v_project_currency is null then raise exception 'livestock project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'sale currency must match project currency'; end if;
  if not exists (select 1 from public.parties
                 where id = p_buyer_party_id and organization_id = p_organization_id) then
    raise exception 'buyer party not found';
  end if;
  if p_sale_reference is null or char_length(trim(p_sale_reference)) not between 1 and 120 then
    raise exception 'livestock sale reference required';
  end if;
  if p_agreement_reference is not null and char_length(trim(p_agreement_reference)) not between 2 and 200 then
    raise exception 'invalid sale agreement reference';
  end if;
  if p_terms is not null and char_length(trim(p_terms)) not between 2 and 1000 then
    raise exception 'invalid sale terms';
  end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid sale evidence';
  end if;
  if p_sale_date is null then raise exception 'sale date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_count := coalesce(cardinality(p_cohort_ids), 0);
  if v_count < 1 or v_count > 50
     or coalesce(cardinality(p_quantities), 0) <> v_count
     or coalesce(cardinality(p_unit_price_minor_units), 0) <> v_count then
    raise exception 'livestock sale requires one to fifty coherent lines';
  end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_buyer_party_id::text || '|' ||
    trim(p_sale_reference) || '|' || coalesce(trim(p_agreement_reference), '') || '|' ||
    p_sale_date::text || '|' || p_currency || '|' || coalesce(trim(p_terms), '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' ||
    coalesce(array_to_string(p_cohort_ids, ','), '') || '|' ||
    coalesce(array_to_string(p_quantities, ','), '') || '|' ||
    coalesce(array_to_string(p_unit_price_minor_units, ','), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-sale:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_sales
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_project_id::text || ':gf024-sale-ref:' ||
    lower(trim(p_sale_reference)), 0
  ));
  if exists (
    select 1 from public.livestock_sales
    where organization_id = p_organization_id and project_id = p_project_id
      and lower(sale_reference) = lower(trim(p_sale_reference))
  ) then raise exception 'livestock sale reference already exists'; end if;

  for v_i in 1..v_count loop
    if p_quantities[v_i] is null or p_quantities[v_i] <= 0 then
      raise exception 'livestock sale quantity must be positive';
    end if;
    if p_unit_price_minor_units[v_i] is null or p_unit_price_minor_units[v_i] <= 0 then
      raise exception 'livestock sale unit price must be positive';
    end if;
    if not exists (
      select 1 from public.livestock_cohorts
      where id = p_cohort_ids[v_i] and organization_id = p_organization_id
        and project_id = p_project_id
    ) then raise exception 'livestock cohort not found for sale line %', v_i; end if;
    if exists (
      select 1 from unnest(p_cohort_ids) with ordinality as x(c, n)
      where n < v_i and c = p_cohort_ids[v_i]
    ) then raise exception 'duplicate cohort in livestock sale lines'; end if;
  end loop;

  insert into public.livestock_sales(
    id, organization_id, project_id, buyer_party_id, sale_reference,
    agreement_reference, sale_date, currency, terms, evidence_reference,
    prepared_by, idempotency_key, request_hash
  ) values (
    v_sale_id, p_organization_id, p_project_id, p_buyer_party_id, trim(p_sale_reference),
    nullif(trim(p_agreement_reference), ''), p_sale_date, p_currency,
    nullif(trim(p_terms), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  );

  for v_i in 1..v_count loop
    insert into public.livestock_sale_lines(
      organization_id, project_id, sale_id, line_no, cohort_id, quantity,
      unit_price_minor_units, line_amount_minor_units
    ) values (
      p_organization_id, p_project_id, v_sale_id, v_i, p_cohort_ids[v_i],
      p_quantities[v_i], p_unit_price_minor_units[v_i],
      p_quantities[v_i]::bigint * p_unit_price_minor_units[v_i]
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_SALE_DRAFT_CREATED', 'livestock_sale', v_sale_id,
    jsonb_build_object('project_id', p_project_id, 'buyer_party_id', p_buyer_party_id,
      'line_count', v_count, 'currency', p_currency, 'accounting_effect', 'NONE',
      'quantity_effect', 'NONE'));
  return v_sale_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.C — OWNER approval of a draft sale (control, not recognition).
-- ---------------------------------------------------------------------------
create function public.approve_livestock_sale(
  p_organization_id uuid,
  p_sale_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_sale public.livestock_sales%rowtype;
  v_existing public.livestock_sales%rowtype;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  v_hash := public.gf020_hash(p_sale_id::text || '|APPROVE');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-sale-approve:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_sales
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_sale_id or v_existing.approval_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_sale from public.livestock_sales
  where id = p_sale_id and organization_id = p_organization_id for update;
  if not found then raise exception 'livestock sale not found'; end if;
  if v_sale.status <> 'DRAFT' then raise exception 'only a draft livestock sale can be approved'; end if;

  update public.livestock_sales
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
   where id = p_sale_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_SALE_APPROVED', 'livestock_sale', p_sale_id,
    jsonb_build_object('project_id', v_sale.project_id, 'accounting_effect', 'NONE',
                       'quantity_effect', 'NONE'));
  return p_sale_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.D — Atomic control transfer: SALE_OUT issue + Finance revenue recognition.
-- ---------------------------------------------------------------------------
create function public.recognize_livestock_sale(
  p_organization_id uuid,
  p_sale_id uuid,
  p_control_transfer_date date,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_sale public.livestock_sales%rowtype;
  v_existing public.livestock_sale_recognitions%rowtype;
  v_hash text;
  v_recognition_id uuid := gen_random_uuid();
  v_batch_id uuid := gen_random_uuid();
  v_line record;
  v_total bigint;
  v_receivable uuid;
  v_revenue uuid;
  v_effective_at timestamptz;
  v_current integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_control_transfer_date is null or p_control_transfer_date > current_date then
    raise exception 'control transfer date must be effective';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'control transfer evidence required';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := public.gf020_hash(
    p_sale_id::text || '|' || p_control_transfer_date::text || '|' || trim(p_evidence_reference)
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-sale-recognize:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_sale_recognitions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.sale_id <> p_sale_id or v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_sale from public.livestock_sales
  where id = p_sale_id and organization_id = p_organization_id for update;
  if not found then raise exception 'livestock sale not found'; end if;
  if v_sale.status <> 'APPROVED' then
    raise exception 'livestock sale must be approved before control transfer';
  end if;
  if p_control_transfer_date < v_sale.sale_date then
    raise exception 'control transfer cannot precede sale date';
  end if;

  -- The control-transfer quantity instant is the transfer date at UTC midnight,
  -- the same date-only boundary the GF-022 inception resolver uses. A sale can
  -- therefore never consume animals supplied only by a later event.
  v_effective_at := p_control_transfer_date::timestamp without time zone at time zone 'UTC';

  -- Lock every source Cohort (row lock and advisory lock) in deterministic id
  -- order, then recheck the as-of derived quantity under that lock so
  -- concurrent sales/mortality/split serialize without deadlock and cannot
  -- oversell.
  perform 1 from public.livestock_cohorts c
  join public.livestock_sale_lines sl on sl.cohort_id = c.id
  where sl.sale_id = p_sale_id order by c.id for update of c;
  for v_line in
    select distinct sl.cohort_id from public.livestock_sale_lines sl
    where sl.sale_id = p_sale_id order by sl.cohort_id
  loop
    perform public.gf022_lock_cohort_quantity(v_line.cohort_id);
  end loop;
  for v_line in
    select * from public.livestock_sale_lines where sale_id = p_sale_id order by line_no
  loop
    v_current := public.livestock_cohort_quantity_as_of(v_line.cohort_id, v_effective_at);
    if v_line.quantity > v_current then
      raise exception 'insufficient livestock quantity for sale line % (% available)',
        v_line.line_no, v_current;
    end if;
  end loop;

  select sum(line_amount_minor_units::numeric)::bigint into v_total
  from public.livestock_sale_lines where sale_id = p_sale_id;
  if v_total is null or v_total <= 0 then raise exception 'invalid livestock sale total'; end if;

  -- Physical SALE_OUT issue and financial recognition are one transaction.
  for v_line in
    select * from public.livestock_sale_lines where sale_id = p_sale_id order by line_no
  loop
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      evidence_reference, notes, recorded_by, idempotency_key, request_hash
    ) values (
      p_organization_id, v_sale.project_id, v_line.cohort_id, 'SALE_OUT', v_line.quantity,
      v_effective_at, trim(p_evidence_reference), null, v_actor,
      'gf024-sale-out-' || v_line.id::text,
      public.gf020_hash(v_line.id::text || '|SALE_OUT')
    );
  end loop;

  select id into v_receivable from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE';
  select id into v_revenue from public.semantic_accounts where role = 'LIVESTOCK_SALE_REVENUE';

  insert into public.journal_batches(
    id, organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    v_batch_id, p_organization_id, v_sale.project_id, 'LIVESTOCK_SALE_RECOGNITION',
    v_recognition_id, p_control_transfer_date, 'gf024-sale-batch-' || v_recognition_id::text,
    v_hash, v_actor
  );
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units, credit_minor_units,
    currency, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_sale.project_id, v_receivable, v_total, 0,
     v_sale.currency, v_sale.buyer_party_id, p_control_transfer_date),
    (v_batch_id, p_organization_id, v_sale.project_id, v_revenue, 0, v_total,
     v_sale.currency, v_sale.buyer_party_id, p_control_transfer_date);

  insert into public.livestock_sale_recognitions(
    id, organization_id, project_id, sale_id, recognized_revenue_minor_units, currency,
    recognition_date, journal_batch_id, recognized_by, idempotency_key, request_hash
  ) values (
    v_recognition_id, p_organization_id, v_sale.project_id, p_sale_id, v_total,
    v_sale.currency, p_control_transfer_date, v_batch_id, v_actor,
    trim(p_idempotency_key), v_hash
  );

  update public.livestock_sales
     set status = 'CONTROL_TRANSFERRED',
         control_transfer_date = p_control_transfer_date,
         control_transfer_evidence_reference = trim(p_evidence_reference),
         control_transferred_by = v_actor, control_transferred_at = now(),
         transfer_idempotency_key = trim(p_idempotency_key), transfer_request_hash = v_hash
   where id = p_sale_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_SALE_RECOGNIZED', 'livestock_sale_recognition',
    v_recognition_id,
    jsonb_build_object('project_id', v_sale.project_id, 'sale_id', p_sale_id,
      'journal_batch_id', v_batch_id, 'recognized_revenue_minor_units', v_total,
      'currency', v_sale.currency, 'physical_issue', 'SALE_OUT', 'cogs_effect', 'NONE'));
  return v_recognition_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.E — Collection against the recognized receivable (shared Finance Core).
-- ---------------------------------------------------------------------------
create function public.collect_livestock_sale_receivable(
  p_organization_id uuid,
  p_recognition_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_collection_date date,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_rec public.livestock_sale_recognitions%rowtype;
  v_sale public.livestock_sales%rowtype;
  v_existing public.livestock_sale_collections%rowtype;
  v_hash text;
  v_collected numeric;
  v_collection_id uuid := gen_random_uuid();
  v_batch_id uuid := gen_random_uuid();
  v_cash uuid;
  v_receivable uuid;
  v_account record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'collection amount must be positive';
  end if;
  if p_collection_date is null or p_collection_date > current_date then
    raise exception 'collection date must be effective';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'collection evidence required';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := public.gf020_hash(
    p_recognition_id::text || '|' || p_cash_account_id::text || '|' ||
    p_amount_minor_units::text || '|' || p_collection_date::text || '|' ||
    trim(p_evidence_reference)
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-collection:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_sale_collections
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.recognition_id <> p_recognition_id or v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_rec from public.livestock_sale_recognitions
  where id = p_recognition_id and organization_id = p_organization_id for update;
  if not found then raise exception 'livestock sale recognition not found'; end if;
  select * into v_sale from public.livestock_sales where id = v_rec.sale_id;
  if p_collection_date < v_rec.recognition_date then
    raise exception 'collection cannot precede recognition';
  end if;
  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id;
  if not found or v_account.project_id <> v_rec.project_id or v_account.currency <> v_rec.currency then
    raise exception 'cash account must belong to the same project and currency';
  end if;
  select coalesce(sum(amount_minor_units::numeric), 0) into v_collected
  from public.livestock_sale_collections where recognition_id = p_recognition_id;
  if v_collected + p_amount_minor_units > v_rec.recognized_revenue_minor_units then
    raise exception 'collection exceeds outstanding livestock receivable';
  end if;

  select id into v_cash from public.semantic_accounts where role = 'BANK_CASH';
  select id into v_receivable from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE';

  insert into public.journal_batches(
    id, organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    v_batch_id, p_organization_id, v_rec.project_id, 'LIVESTOCK_SALE_COLLECTION',
    v_collection_id, p_collection_date, 'gf024-collection-batch-' || v_collection_id::text,
    v_hash, v_actor
  );
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units, credit_minor_units,
    currency, cash_account_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_rec.project_id, v_cash, p_amount_minor_units, 0,
     v_rec.currency, p_cash_account_id, null, p_collection_date),
    (v_batch_id, p_organization_id, v_rec.project_id, v_receivable, 0, p_amount_minor_units,
     v_rec.currency, null, v_sale.buyer_party_id, p_collection_date);

  insert into public.livestock_sale_collections(
    id, organization_id, project_id, recognition_id, sale_id, cash_account_id,
    amount_minor_units, currency, collection_date, evidence_reference, journal_batch_id,
    collected_by, idempotency_key, request_hash
  ) values (
    v_collection_id, p_organization_id, v_rec.project_id, p_recognition_id, v_rec.sale_id,
    p_cash_account_id, p_amount_minor_units, v_rec.currency, p_collection_date,
    trim(p_evidence_reference), v_batch_id, v_actor, trim(p_idempotency_key), v_hash
  );

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_SALE_COLLECTION_POSTED',
    'livestock_sale_collection', v_collection_id,
    jsonb_build_object('project_id', v_rec.project_id, 'sale_id', v_rec.sale_id,
      'recognition_id', p_recognition_id, 'cash_account_id', p_cash_account_id,
      'journal_batch_id', v_batch_id, 'amount_minor_units', p_amount_minor_units,
      'currency', v_rec.currency, 'revenue_effect', 'NONE'));
  return v_collection_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.F — Attribute a posted Finance expense to a Cohort (no posting).
-- ---------------------------------------------------------------------------
create function public.attribute_livestock_cohort_cost(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_source_journal_line_id uuid,
  p_amount_minor_units bigint,
  p_cost_category text,
  p_policy_reference text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing public.livestock_cohort_cost_attributions%rowtype;
  v_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'attributed cost amount must be positive';
  end if;
  if p_cost_category not in ('ACQUISITION','FEED','HEALTH','LABOR','FACILITIES','TRANSPORT','OTHER') then
    raise exception 'invalid livestock cost category';
  end if;
  if p_policy_reference is null or char_length(trim(p_policy_reference)) not between 3 and 200 then
    raise exception 'cost attribution policy reference is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'cost attribution evidence is required';
  end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|' ||
    p_source_journal_line_id::text || '|' || p_amount_minor_units::text || '|' ||
    p_cost_category || '|' || trim(p_policy_reference) || '|' || trim(p_evidence_reference)
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-cost:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_cohort_cost_attributions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if not exists (select 1 from public.investment_projects p
                 where p.id = p_project_id and p.organization_id = p_organization_id
                   and p.sector = 'LIVESTOCK') then
    raise exception 'livestock project not found';
  end if;
  if not exists (select 1 from public.livestock_cohorts c
                 where c.id = p_cohort_id and c.organization_id = p_organization_id
                   and c.project_id = p_project_id) then
    raise exception 'livestock cohort not found in project';
  end if;
  select jl.currency into v_currency from public.journal_lines jl
  where jl.id = p_source_journal_line_id and jl.organization_id = p_organization_id;
  if v_currency is null then raise exception 'authoritative posted cost source not found'; end if;

  insert into public.livestock_cohort_cost_attributions(
    organization_id, project_id, cohort_id, source_journal_line_id,
    attributed_amount_minor_units, currency, cost_category, policy_reference,
    evidence_reference, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, p_source_journal_line_id,
    p_amount_minor_units, v_currency, p_cost_category, trim(p_policy_reference),
    trim(p_evidence_reference), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_COHORT_COST_ATTRIBUTED',
    'livestock_cohort_cost_attribution', v_id,
    jsonb_build_object('project_id', p_project_id, 'cohort_id', p_cohort_id,
      'source_journal_line_id', p_source_journal_line_id,
      'attributed_amount_minor_units', p_amount_minor_units, 'currency', v_currency,
      'cost_category', p_cost_category, 'monetary_effect', 'NONE'));
  return v_id;
end $$;

create function public.reverse_livestock_cohort_cost_attribution(
  p_organization_id uuid,
  p_attribution_id uuid,
  p_reason text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_original public.livestock_cohort_cost_attributions%rowtype;
  v_existing public.livestock_cohort_cost_attributions%rowtype;
  v_hash text;
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'cost attribution reversal reason is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'cost attribution reversal evidence is required';
  end if;

  v_hash := public.gf020_hash(
    p_attribution_id::text || '|' || trim(p_reason) || '|' || trim(p_evidence_reference)
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-cost-reverse:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_cohort_cost_attributions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_original from public.livestock_cohort_cost_attributions
  where id = p_attribution_id and organization_id = p_organization_id for update;
  if not found or v_original.reversal_of_attribution_id is not null then
    raise exception 'livestock cost attribution not found';
  end if;

  insert into public.livestock_cohort_cost_attributions(
    organization_id, project_id, cohort_id, source_journal_line_id,
    attributed_amount_minor_units, currency, cost_category, policy_reference,
    evidence_reference, reversal_of_attribution_id, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_original.project_id, v_original.cohort_id,
    v_original.source_journal_line_id, v_original.attributed_amount_minor_units,
    v_original.currency, v_original.cost_category,
    'عكس: ' || left(trim(p_reason), 194), trim(p_evidence_reference), v_original.id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_COHORT_COST_ATTRIBUTION_REVERSED',
    'livestock_cohort_cost_attribution', v_id,
    jsonb_build_object('project_id', v_original.project_id, 'cohort_id', v_original.cohort_id,
      'reversal_of_attribution_id', v_original.id, 'reason', trim(p_reason),
      'monetary_effect', 'NONE'));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 8.G — Technical closeout (no lifecycle mutation; S6 stays authoritative).
-- ---------------------------------------------------------------------------
create function public.close_livestock_cohort(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_close_reason text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.livestock_cohort_closeouts%rowtype;
  v_hash text;
  v_id uuid;
  v_issue record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_close_reason is null or char_length(trim(p_close_reason)) not between 3 and 500 then
    raise exception 'livestock close reason is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'livestock close evidence is required';
  end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|' ||
    trim(p_close_reason) || '|' || trim(p_evidence_reference)
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf024-close:' || trim(p_idempotency_key), 0
  ));
  select * into v_existing from public.livestock_cohort_closeouts
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform 1 from public.livestock_cohorts c
  where c.id = p_cohort_id and c.organization_id = p_organization_id
    and c.project_id = p_project_id for update;
  if not found then raise exception 'livestock cohort not found in project'; end if;

  select * into v_issue from public.livestock_cohort_integrity_issues_read i
  where i.cohort_id = p_cohort_id and i.severity = 'HARD' order by i.code limit 1;
  if found then raise exception 'livestock cohort close blocked: %', v_issue.code; end if;

  insert into public.livestock_cohort_closeouts(
    organization_id, project_id, cohort_id, close_reason, evidence_reference,
    closed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, trim(p_close_reason),
    trim(p_evidence_reference), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'LIVESTOCK_COHORT_TECHNICALLY_CLOSED',
    'livestock_cohort_closeout', v_id,
    jsonb_build_object('project_id', p_project_id, 'cohort_id', p_cohort_id,
      'close_reason', trim(p_close_reason), 'lifecycle_effect', 'NONE'));
  return v_id;
end $$;

-- ===========================================================================
-- 9. Read models.
-- ===========================================================================

create view public.livestock_purchases_read with (security_invoker=on) as
select
  p.id as purchase_id, p.organization_id, p.project_id, p.supplier_party_id,
  s.legal_name as supplier_name, p.purchase_reference, p.agreement_reference,
  p.effective_at, p.evidence_reference, p.notes, p.prepared_by, p.prepared_at,
  (select count(*) from public.livestock_purchase_lines l where l.purchase_id = p.id) as line_count,
  (select sum(l.quantity)::bigint from public.livestock_purchase_lines l where l.purchase_id = p.id) as total_quantity,
  case when exists (
    select 1 from public.livestock_purchase_lines l
    where l.purchase_id = p.id and l.agreed_amount_minor_units is null
  ) then null
  else (select sum(l.agreed_amount_minor_units)::text
        from public.livestock_purchase_lines l where l.purchase_id = p.id)
  end as agreed_total_minor_units
from public.livestock_purchases p
join public.parties s on s.id = p.supplier_party_id and s.organization_id = p.organization_id;

create view public.livestock_purchase_lines_read with (security_invoker=on) as
select
  l.id as purchase_line_id, l.organization_id, l.project_id, l.purchase_id, l.line_no,
  l.cohort_id, c.cohort_reference, h.species, h.purpose,
  l.quantity, l.agreed_unit_price_minor_units::text as agreed_unit_price_minor_units,
  l.agreed_amount_minor_units::text as agreed_amount_minor_units,
  q.id as purchase_in_event_id, q.effective_at as purchase_in_effective_at
from public.livestock_purchase_lines l
join public.livestock_cohorts c on c.id = l.cohort_id
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) = (c.herd_id, c.organization_id, c.project_id)
left join public.livestock_quantity_events q
  on q.idempotency_key = 'gf024-purchase-in-' || l.id::text
 and q.event_type = 'PURCHASE_IN';

create view public.livestock_sales_read with (security_invoker=on) as
select
  s.id as sale_id, s.organization_id, s.project_id, s.buyer_party_id,
  p.legal_name as buyer_name, s.sale_reference, s.agreement_reference, s.sale_date,
  s.currency, s.terms, s.evidence_reference,
  case when s.status = 'CONTROL_TRANSFERRED'
    and coalesce(c.collected, 0) >= coalesce(r.recognized_revenue_minor_units, 0)
    then 'SETTLED' else s.status end as state,
  s.status as control_state, s.prepared_by, s.prepared_at, s.approved_by, s.approved_at,
  s.control_transfer_date, s.control_transfer_evidence_reference,
  s.control_transferred_by, s.control_transferred_at,
  (select count(*) from public.livestock_sale_lines sl where sl.sale_id = s.id) as line_count,
  (select sum(sl.quantity)::bigint from public.livestock_sale_lines sl where sl.sale_id = s.id) as total_quantity,
  coalesce((select sum(sl.line_amount_minor_units::numeric)
            from public.livestock_sale_lines sl where sl.sale_id = s.id), 0)::text as agreed_total_minor_units,
  r.id as recognition_id, r.recognition_date, r.journal_batch_id as revenue_journal_batch_id,
  coalesce(r.recognized_revenue_minor_units, 0)::text as recognized_revenue_minor_units,
  coalesce(c.collected, 0)::text as collected_minor_units,
  greatest(coalesce(r.recognized_revenue_minor_units, 0)::numeric - coalesce(c.collected, 0), 0)::text
    as outstanding_receivable_minor_units
from public.livestock_sales s
join public.parties p on p.id = s.buyer_party_id and p.organization_id = s.organization_id
left join public.livestock_sale_recognitions r on r.sale_id = s.id
left join lateral (
  select coalesce(sum(sc.amount_minor_units::numeric), 0) as collected
  from public.livestock_sale_collections sc where sc.recognition_id = r.id
) c on true;

create view public.livestock_sale_lines_read with (security_invoker=on) as
select
  sl.id as sale_line_id, sl.organization_id, sl.project_id, sl.sale_id, sl.line_no,
  sl.cohort_id, c.cohort_reference, h.species, h.purpose,
  sl.quantity, sl.unit_price_minor_units::text as unit_price_minor_units,
  sl.line_amount_minor_units::text as line_amount_minor_units,
  q.id as sale_out_event_id, q.effective_at as sale_out_effective_at
from public.livestock_sale_lines sl
join public.livestock_cohorts c on c.id = sl.cohort_id
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) = (c.herd_id, c.organization_id, c.project_id)
left join public.livestock_quantity_events q
  on q.idempotency_key = 'gf024-sale-out-' || sl.id::text
 and q.event_type = 'SALE_OUT';

create view public.livestock_sale_collections_read with (security_invoker=on) as
select
  c.id as collection_id, c.organization_id, c.project_id, c.recognition_id, c.sale_id,
  c.cash_account_id, a.name as cash_account_name, c.amount_minor_units::text as amount_minor_units,
  c.currency, c.collection_date, c.evidence_reference, c.journal_batch_id,
  c.collected_by, c.collected_at
from public.livestock_sale_collections c
join public.project_cash_accounts a on a.id = c.cash_account_id;

create view public.livestock_cohort_sale_traceability_read with (security_invoker=on) as
select
  c.id as cohort_id, c.organization_id, c.project_id, c.cohort_reference,
  sl.id as sale_line_id, sl.sale_id, s.sale_reference, s.buyer_party_id,
  p.legal_name as buyer_name, sl.quantity as sold_quantity,
  sl.unit_price_minor_units::text as unit_price_minor_units,
  sl.line_amount_minor_units::text as line_amount_minor_units,
  q.id as sale_out_event_id, q.effective_at as sale_out_effective_at,
  r.id as recognition_id, r.journal_batch_id as revenue_journal_batch_id
from public.livestock_cohorts c
left join public.livestock_sale_lines sl on sl.cohort_id = c.id
left join public.livestock_sales s on s.id = sl.sale_id
left join public.parties p on p.id = s.buyer_party_id
left join public.livestock_quantity_events q
  on q.idempotency_key = 'gf024-sale-out-' || sl.id::text
 and q.event_type = 'SALE_OUT'
left join public.livestock_sale_recognitions r on r.sale_id = s.id;

create view public.livestock_cohort_cost_sources_read with (security_invoker=on) as
select
  jl.id as source_journal_line_id, jl.organization_id, jl.project_id, jl.batch_id,
  jb.source_id as cost_obligation_id, o.description, o.transaction_date, o.party_id,
  jl.debit_minor_units::text as posted_amount_minor_units, jl.currency,
  coalesce((select sum(a.attributed_amount_minor_units::numeric)
    from public.livestock_cohort_cost_attributions a
    where a.source_journal_line_id = jl.id and a.reversal_of_attribution_id is null
      and not exists (select 1 from public.livestock_cohort_cost_attributions r
                      where r.reversal_of_attribution_id = a.id)), 0)::text
    as attributed_amount_minor_units,
  (jl.debit_minor_units::numeric - coalesce((select sum(a.attributed_amount_minor_units::numeric)
    from public.livestock_cohort_cost_attributions a
    where a.source_journal_line_id = jl.id and a.reversal_of_attribution_id is null
      and not exists (select 1 from public.livestock_cohort_cost_attributions r
                      where r.reversal_of_attribution_id = a.id)), 0))::text
    as available_amount_minor_units,
  'FINANCE_CORE_POSTED_JOURNAL_LINE'::text as authoritative_source
from public.journal_lines jl
join public.journal_batches jb on jb.id = jl.batch_id and jb.organization_id = jl.organization_id
join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'PROJECT_EXPENSE'
join public.cost_obligations o on o.id = jb.source_id and o.organization_id = jl.organization_id
where jb.source_type = 'COST_OBLIGATION' and jl.debit_minor_units > 0 and jl.credit_minor_units = 0
  and not exists (select 1 from public.journal_batches r where r.reversal_of_batch_id = jb.id);

create view public.livestock_cohort_cost_attributions_read with (security_invoker=on) as
select
  a.id, a.organization_id, a.project_id, a.cohort_id,
  a.source_journal_line_id, jl.batch_id as source_journal_batch_id, jl.obligation_id,
  o.description as source_description, o.transaction_date as source_transaction_date,
  a.attributed_amount_minor_units::text as attributed_amount_minor_units, a.currency,
  a.cost_category, a.policy_reference, a.evidence_reference, a.reversal_of_attribution_id,
  (a.reversal_of_attribution_id is null and not exists (
    select 1 from public.livestock_cohort_cost_attributions r
    where r.reversal_of_attribution_id = a.id
  ) and not exists (
    select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jl.batch_id
  )) as is_active,
  a.recorded_by, a.recorded_at, 'FINANCE_CORE_POSTED_JOURNAL_LINE'::text as authoritative_source
from public.livestock_cohort_cost_attributions a
join public.journal_lines jl on jl.id = a.source_journal_line_id
left join public.cost_obligations o on o.id = jl.obligation_id;

-- ---------------------------------------------------------------------------
-- 9.I — Reproducible closeout controls. HARD blocks close; WARN stays visible.
-- ---------------------------------------------------------------------------
create view public.livestock_cohort_integrity_issues_read with (security_invoker=on) as
-- Quantity rollforward must reconcile exactly per class (including the two
-- commercial classes). A Cohort whose operational inception is still in the
-- future contributes zero as-of opening quantity.
select r.organization_id, r.project_id, r.cohort_id, 'ROLLFORWARD_MISMATCH'::text as code,
  'HARD'::text as severity, 'الرصيد العددي المشتق لا يطابق مجموع الأحداث الثابتة.'::text as message_ar
from public.livestock_cohort_quantity_rollforward r
join public.livestock_cohorts_read c on c.id = r.cohort_id
where r.current_quantity <>
      (case when c.is_operational_as_of_now then r.opening_headcount else 0 end)
      + r.births
      + coalesce((select sum(q.quantity) from public.livestock_quantity_events q
                  where q.cohort_id = c.id and q.event_type = 'PURCHASE_IN'
                    and q.effective_at >= public.gf022_cohort_inception_at(c.id)
                    and q.effective_at <= current_timestamp), 0)
      + r.split_in + r.merge_in
      - r.mortality
      - coalesce((select sum(q.quantity) from public.livestock_quantity_events q
                  where q.cohort_id = c.id and q.event_type = 'SALE_OUT'
                    and q.effective_at >= public.gf022_cohort_inception_at(c.id)
                    and q.effective_at <= current_timestamp), 0)
      - r.split_out - r.merge_out
union all
-- No negative derived quantity.
select r.organization_id, r.project_id, r.cohort_id, 'NEGATIVE_QUANTITY'::text as code,
  'HARD'::text as severity, 'الرصيد العددي المشتق سالب.'::text as message_ar
from public.livestock_cohort_quantity_rollforward r
where r.current_quantity < 0
union all
-- Lifecycle chain must have exactly one unconsumed tip.
select c.organization_id, c.project_id, c.id as cohort_id, 'BROKEN_LIFECYCLE_CHAIN'::text as code,
  'HARD'::text as severity, 'سلسلة حالة الدفعة غير مكتملة أو متفرعة.'::text as message_ar
from public.livestock_cohorts c
where (select count(*) from public.livestock_cohort_state_history h
       where h.cohort_id = c.id
         and not exists (select 1 from public.livestock_cohort_state_history n
                         where n.previous_history_id = h.id)) <> 1
union all
-- Split/merge conservation must hold for every operation touching the Cohort.
select l.organization_id, l.project_id, l.destination_cohort_id as cohort_id,
  'CONSERVATION_BROKEN'::text as code, 'HARD'::text as severity,
  'عملية تقسيم/دمج لا تحافظ على العدد.'::text as message_ar
from public.livestock_cohort_lineage l
join public.livestock_quantity_operations o on o.id = l.operation_id
where (select coalesce(sum(case when t.direction = -1 then q.quantity else 0 end), 0)
         from public.livestock_quantity_events q
         join public.livestock_quantity_event_types t on t.code = q.event_type
        where q.operation_id = l.operation_id)
   <> (select coalesce(sum(case when t.direction = 1 then q.quantity else 0 end), 0)
         from public.livestock_quantity_events q
         join public.livestock_quantity_event_types t on t.code = q.event_type
        where q.operation_id = l.operation_id)
union all
-- Every recognized sale line must have exactly one matching SALE_OUT issue.
select sl.organization_id, sl.project_id, sl.cohort_id, 'BROKEN_SALE_ISSUE'::text as code,
  'HARD'::text as severity, 'كمية البيع لا تتطابق مع واقعة صادر SALE_OUT.'::text as message_ar
from public.livestock_sale_lines sl
join public.livestock_sale_recognitions r on r.sale_id = sl.sale_id
where not exists (
  select 1 from public.livestock_quantity_events q
  where q.idempotency_key = 'gf024-sale-out-' || sl.id::text
    and q.event_type = 'SALE_OUT' and q.cohort_id = sl.cohort_id
    and q.quantity = sl.quantity
)
union all
-- Recognized revenue must equal the immutable lines and reference its batch.
select r.organization_id, r.project_id, sl.cohort_id, 'BROKEN_REVENUE_SOURCE'::text as code,
  'HARD'::text as severity, 'الإيراد المعترف به لا يطابق سطور البيع أو القيد المشترك.'::text as message_ar
from public.livestock_sale_recognitions r
join public.livestock_sale_lines sl on sl.sale_id = r.sale_id
where r.recognized_revenue_minor_units <>
      (select sum(x.line_amount_minor_units) from public.livestock_sale_lines x where x.sale_id = r.sale_id)
   or not exists (select 1 from public.journal_batches jb
                  where jb.id = r.journal_batch_id
                    and jb.source_type = 'LIVESTOCK_SALE_RECOGNITION' and jb.source_id = r.id)
union all
-- Collection ceiling must hold against the recognized receivable.
select r.organization_id, r.project_id, sl.cohort_id, 'COLLECTION_CEILING_BROKEN'::text as code,
  'HARD'::text as severity, 'التحصيل يتجاوز الذمة المعترف بها.'::text as message_ar
from public.livestock_sale_recognitions r
join public.livestock_sale_lines sl on sl.sale_id = r.sale_id
where (select coalesce(sum(c.amount_minor_units), 0)
       from public.livestock_sale_collections c where c.recognition_id = r.id)
      > r.recognized_revenue_minor_units
union all
-- Cost attribution ceiling must hold against its posted Finance source.
select a.organization_id, a.project_id, a.cohort_id, 'COST_ATTRIBUTION_CEILING_BROKEN'::text as code,
  'HARD'::text as severity, 'تحميل التكلفة يتجاوز مصدره المالي المعتمد.'::text as message_ar
from public.livestock_cohort_cost_attributions a
join public.journal_lines jl on jl.id = a.source_journal_line_id
where a.reversal_of_attribution_id is null
  and (select coalesce(sum(x.attributed_amount_minor_units), 0)
       from public.livestock_cohort_cost_attributions x
       where x.source_journal_line_id = a.source_journal_line_id
         and x.reversal_of_attribution_id is null
         and not exists (select 1 from public.livestock_cohort_cost_attributions z
                         where z.reversal_of_attribution_id = x.id))
      > jl.debit_minor_units
union all
-- Open receivable is a visible commercial position, not a close blocker.
select r.organization_id, r.project_id, sl.cohort_id, 'OPEN_RECEIVABLE'::text as code,
  'WARN'::text as severity, 'توجد ذمة بيع متبقية للتحصيل.'::text as message_ar
from public.livestock_sale_recognitions r
join public.livestock_sale_lines sl on sl.sale_id = r.sale_id
where (select coalesce(sum(c.amount_minor_units), 0)
       from public.livestock_sale_collections c where c.recognition_id = r.id)
      < r.recognized_revenue_minor_units
union all
-- A draft or approved (not yet transferred) sale is a visible open position.
select s.organization_id, s.project_id, sl.cohort_id, 'OPEN_SALE'::text as code,
  'WARN'::text as severity, 'توجد مسودة/عملية بيع لم تنتقل السيطرة فيها بعد.'::text as message_ar
from public.livestock_sales s
join public.livestock_sale_lines sl on sl.sale_id = s.id
where s.status in ('DRAFT','APPROVED')
union all
-- A zero-quantity Cohort remains ACTIVE: informational, never a close blocker.
select r.organization_id, r.project_id, r.cohort_id, 'ZERO_QUANTITY_ACTIVE'::text as code,
  'WARN'::text as severity, 'رصيد الدفعة صفر مع بقائها نشطة تشغيليًا.'::text as message_ar
from public.livestock_cohort_quantity_rollforward r
join public.livestock_cohorts c on c.id = r.cohort_id
where r.current_quantity = 0
  and public.livestock_current_cohort_state(r.cohort_id) = 'ACTIVE';

-- ---------------------------------------------------------------------------
-- 9.II — Reproducible Cohort result: revenue, cash, cost, quantities.
-- ---------------------------------------------------------------------------
create view public.livestock_cohort_results_read with (security_invoker=on) as
with commercial_summary as (
  select sl.cohort_id,
    sum(sl.line_amount_minor_units)::bigint as recognized_revenue,
    count(distinct sl.sale_id) as sale_count
  from public.livestock_sale_lines sl
  join public.livestock_sale_recognitions r on r.sale_id = sl.sale_id
  group by sl.cohort_id
), sale_line_share as (
  select sl.sale_id, sl.cohort_id, sl.line_amount_minor_units,
         r.recognized_revenue_minor_units as sale_total
  from public.livestock_sale_lines sl
  join public.livestock_sale_recognitions r on r.sale_id = sl.sale_id
), collection_rows as (
  select c.id as collection_id, c.amount_minor_units, r.sale_id
  from public.livestock_sale_collections c
  join public.livestock_sale_recognitions r on r.id = c.recognition_id
), collection_line_base as (
  select cr.collection_id, cr.amount_minor_units, sls.cohort_id, sls.sale_total,
    floor(cr.amount_minor_units::numeric * sls.line_amount_minor_units / sls.sale_total) as base_amount,
    (cr.amount_minor_units::numeric * sls.line_amount_minor_units / sls.sale_total
      - floor(cr.amount_minor_units::numeric * sls.line_amount_minor_units / sls.sale_total)) as fraction
  from collection_rows cr
  join sale_line_share sls on sls.sale_id = cr.sale_id
), collection_line_ranked as (
  select clb.*,
    row_number() over (partition by collection_id order by fraction desc, cohort_id) as fraction_rank,
    amount_minor_units - sum(base_amount) over (partition by collection_id) as remainder
  from collection_line_base clb
), collection_summary as (
  select clr.cohort_id,
    sum(clr.base_amount + case when clr.fraction_rank <= clr.remainder then 1 else 0 end)::bigint
      as collected
  from collection_line_ranked clr
  group by clr.cohort_id
), cost_summary as (
  select a.cohort_id, sum(a.attributed_amount_minor_units)::bigint as operating_cost,
    sum(a.attributed_amount_minor_units) filter (where a.cost_category = 'ACQUISITION')::bigint
      as acquisition_attributed_cost
  from public.livestock_cohort_cost_attributions a
  join public.journal_lines jl on jl.id = a.source_journal_line_id
  where a.reversal_of_attribution_id is null
    and not exists (select 1 from public.livestock_cohort_cost_attributions r
                    where r.reversal_of_attribution_id = a.id)
    and not exists (select 1 from public.journal_batches rb
                    where rb.reversal_of_batch_id = jl.batch_id)
  group by a.cohort_id
)
select
  c.id as cohort_id, c.organization_id, c.project_id, c.cohort_reference,
  h.name as herd_name, h.species, h.purpose,
  public.livestock_current_cohort_state(c.id) as lifecycle_state,
  r.opening_headcount,
  r.births, coalesce(comm.purchase_in, 0)::integer as purchase_in,
  r.split_in, r.merge_in,
  r.mortality, coalesce(comm.sale_out, 0)::integer as sale_out,
  r.split_out, r.merge_out,
  r.current_quantity as unsold_live_quantity,
  coalesce(cs.sale_count, 0) as sale_count,
  coalesce(cs.recognized_revenue, 0)::text as recognized_revenue_minor_units,
  coalesce(cc.collected, 0)::text as cash_collected_minor_units,
  greatest(coalesce(cs.recognized_revenue, 0) - coalesce(cc.collected, 0), 0)::text
    as receivable_outstanding_minor_units,
  coalesce(cost.operating_cost, 0)::text as attributed_operating_cost_minor_units,
  coalesce(cost.acquisition_attributed_cost, 0)::text as acquisition_attributed_cost_minor_units,
  (coalesce(cs.recognized_revenue, 0) - coalesce(cost.operating_cost, 0))::text
    as operating_result_to_date_minor_units,
  p.reporting_currency as currency,
  case when coalesce(comm.sale_out, 0) > 0
       then round(coalesce(cs.recognized_revenue, 0)::numeric / coalesce(comm.sale_out, 0))::bigint::text
       else null end as realized_average_selling_price_minor_units,
  'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text as unsold_live_quantity_value_status,
  'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'::text as biological_asset_value_status,
  'NOT_GUESSED'::text as cogs_status,
  co.closed_by, co.closed_at, co.close_reason
from public.livestock_cohorts c
join public.investment_projects p on p.id = c.project_id and p.organization_id = c.organization_id
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) = (c.herd_id, c.organization_id, c.project_id)
join public.livestock_cohort_quantity_rollforward r on r.cohort_id = c.id
left join lateral (
  select
    coalesce(sum(q.quantity) filter (where q.event_type = 'PURCHASE_IN'), 0) as purchase_in,
    coalesce(sum(q.quantity) filter (where q.event_type = 'SALE_OUT'), 0) as sale_out
  from public.livestock_quantity_events q
  where q.cohort_id = c.id
    and q.effective_at >= public.gf022_cohort_inception_at(c.id)
    and q.effective_at <= current_timestamp
) comm on true
left join commercial_summary cs on cs.cohort_id = c.id
left join collection_summary cc on cc.cohort_id = c.id
left join cost_summary cost on cost.cohort_id = c.id
left join public.livestock_cohort_closeouts co on co.cohort_id = c.id;

create view public.livestock_cohort_closeouts_read with (security_invoker=on) as
select
  co.id, co.organization_id, co.project_id, co.cohort_id, co.close_reason,
  co.evidence_reference, co.closed_by, co.closed_at,
  r.lifecycle_state, r.unsold_live_quantity,
  r.recognized_revenue_minor_units, r.cash_collected_minor_units,
  r.receivable_outstanding_minor_units, r.attributed_operating_cost_minor_units,
  r.operating_result_to_date_minor_units,
  r.unsold_live_quantity_value_status,
  (select count(*) from public.livestock_cohort_integrity_issues_read i
   where i.cohort_id = co.cohort_id and i.severity = 'WARN') as open_warning_count
from public.livestock_cohort_closeouts co
join public.livestock_cohort_results_read r on r.cohort_id = co.cohort_id;

-- ===========================================================================
-- 10. Security: RLS, FORCE RLS, default deny, no authenticated table DML.
-- ===========================================================================
do $gf024_rls$
declare t text;
begin
  foreach t in array array[
    'livestock_purchases','livestock_purchase_lines',
    'livestock_sales','livestock_sale_lines',
    'livestock_sale_recognitions','livestock_sale_collections',
    'livestock_cohort_cost_attributions','livestock_cohort_closeouts'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',
      t || '_read', t
    );
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end
$gf024_rls$;

revoke all on
  public.livestock_cohort_quantity_rollforward,
  public.livestock_purchases_read,
  public.livestock_purchase_lines_read,
  public.livestock_sales_read,
  public.livestock_sale_lines_read,
  public.livestock_sale_collections_read,
  public.livestock_cohort_sale_traceability_read,
  public.livestock_cohort_cost_sources_read,
  public.livestock_cohort_cost_attributions_read,
  public.livestock_cohort_integrity_issues_read,
  public.livestock_cohort_results_read,
  public.livestock_cohort_closeouts_read
  from public, anon;
grant select on
  public.livestock_cohort_quantity_rollforward,
  public.livestock_purchases_read,
  public.livestock_purchase_lines_read,
  public.livestock_sales_read,
  public.livestock_sale_lines_read,
  public.livestock_sale_collections_read,
  public.livestock_cohort_sale_traceability_read,
  public.livestock_cohort_cost_sources_read,
  public.livestock_cohort_cost_attributions_read,
  public.livestock_cohort_integrity_issues_read,
  public.livestock_cohort_results_read,
  public.livestock_cohort_closeouts_read
  to authenticated;

-- Trigger/helper functions are internal only.
revoke all on function
  public.gf024_immutable(),
  public.gf024_guard_sale_line_insert(),
  public.gf024_guard_recognition_insert(),
  public.gf024_guard_collection_insert(),
  public.gf024_guard_sale_transition(),
  public.gf024_guard_sale_reversal(),
  public.gf024_guard_cost_attribution_insert(),
  public.gf024_guard_attributed_cost_source_reversal()
  from public, anon, authenticated;

revoke all on function
  public.record_livestock_purchase(uuid,uuid,uuid,text,text,timestamptz,text,text,uuid[],integer[],bigint[],text),
  public.create_livestock_sale(uuid,uuid,uuid,text,text,date,text,text,text,uuid[],integer[],bigint[],text),
  public.approve_livestock_sale(uuid,uuid,text),
  public.recognize_livestock_sale(uuid,uuid,date,text,text),
  public.collect_livestock_sale_receivable(uuid,uuid,uuid,bigint,date,text,text),
  public.attribute_livestock_cohort_cost(uuid,uuid,uuid,uuid,bigint,text,text,text,text),
  public.reverse_livestock_cohort_cost_attribution(uuid,uuid,text,text,text),
  public.close_livestock_cohort(uuid,uuid,uuid,text,text,text)
  from public, anon;
grant execute on function
  public.record_livestock_purchase(uuid,uuid,uuid,text,text,timestamptz,text,text,uuid[],integer[],bigint[],text),
  public.create_livestock_sale(uuid,uuid,uuid,text,text,date,text,text,text,uuid[],integer[],bigint[],text),
  public.approve_livestock_sale(uuid,uuid,text),
  public.recognize_livestock_sale(uuid,uuid,date,text,text),
  public.collect_livestock_sale_receivable(uuid,uuid,uuid,bigint,date,text,text),
  public.attribute_livestock_cohort_cost(uuid,uuid,uuid,uuid,bigint,text,text,text,text),
  public.reverse_livestock_cohort_cost_attribution(uuid,uuid,text,text,text),
  public.close_livestock_cohort(uuid,uuid,uuid,text,text,text)
  to authenticated;

-- GF-024 commands hash with the canonical `gf020_hash` helper (md5-based, a
-- built-in), so no pgcrypto re-qualification pass is required for them. The
-- `digest`-based re-qualification used by GF-018/GF-019 remains applicable
-- only to those slices' commands.
