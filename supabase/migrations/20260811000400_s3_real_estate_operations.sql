-- GF-005 / S3 — Real Estate sector operation.
--
-- This forward-only migration extends the S2 financial core; it does not edit
-- or duplicate S0-S2 facts. Real-estate state is command-driven history,
-- approved/open commitments and posted actuals remain S2 facts, and management
-- valuations never post accounting entries.

-- ===========================================================================
-- 1. Real Estate hierarchy
-- ===========================================================================
create table public.real_estate_project_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  strategy text not null check (strategy in ('ACQUIRE_HOLD','DEVELOP_SELL','LAND_TRADE')),
  jurisdiction text check (jurisdiction is null or char_length(trim(jurisdiction)) between 2 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (project_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

create table public.property_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  profile_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 160),
  asset_reference text check (asset_reference is null or char_length(trim(asset_reference)) between 1 and 80),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (profile_id, organization_id, project_id)
    references public.real_estate_project_profiles(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index property_assets_project_idx on public.property_assets(project_id);

create table public.parcels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  identifier text not null check (char_length(trim(identifier)) between 1 and 100),
  cadastral_reference text check (cadastral_reference is null or char_length(trim(cadastral_reference)) between 1 and 120),
  legal_description text check (legal_description is null or char_length(trim(legal_description)) between 1 and 1000),
  area_quantity numeric(20,6) not null check (area_quantity > 0),
  area_unit text not null check (area_unit in ('M2','HECTARE','FEDDAN')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, property_asset_id, identifier),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id, property_asset_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index parcels_property_idx on public.parcels(property_asset_id);

-- ===========================================================================
-- 2. Authoritative property lifecycle history
-- ===========================================================================
create table public.property_asset_state_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  previous_history_id uuid,
  previous_state text check (previous_state is null or previous_state in (
    'CANDIDATE','DUE_DILIGENCE','ACQUIRING','HELD','DEVELOPING'
  )),
  new_state text not null check (new_state in (
    'CANDIDATE','DUE_DILIGENCE','ACQUIRING','HELD','DEVELOPING'
  )),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (property_asset_id, previous_history_id),
  check ((previous_state is null and previous_history_id is null)
      or (previous_state is not null and previous_history_id is not null)),
  foreign key (previous_history_id, organization_id)
    references public.property_asset_state_history(id, organization_id) on delete restrict,
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create unique index property_asset_one_initial_state
  on public.property_asset_state_history(property_asset_id) where previous_state is null;
create index property_asset_state_timeline_idx
  on public.property_asset_state_history(property_asset_id, changed_at, id);

-- ===========================================================================
-- 3. Acquisition and typed control/evidence records
-- ===========================================================================
create table public.property_acquisitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  seller_party_id uuid not null,
  contract_reference text not null check (char_length(trim(contract_reference)) between 2 and 120),
  consideration_minor_units bigint not null check (consideration_minor_units > 0),
  closing_costs_minor_units bigint not null default 0 check (closing_costs_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  contract_date date not null,
  consideration_obligation_id uuid,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (property_asset_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id, property_asset_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (seller_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  foreign key (consideration_obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

create table public.property_control_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  parcel_id uuid,
  record_type text not null check (record_type in (
    'ACQUISITION_CHECK','TITLE','POSSESSION','PERMIT','INSPECTION'
  )),
  control_type text not null check (char_length(trim(control_type)) between 2 and 120),
  status text not null check (status in ('PENDING','PASSED','FAILED','EXPIRED')),
  effective_date date,
  expiry_date date,
  result text check (result is null or char_length(trim(result)) between 1 and 1000),
  responsible_actor_id uuid not null references auth.users(id) on delete restrict,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 1000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (expiry_date is null or effective_date is null or expiry_date >= effective_date),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (parcel_id, organization_id, project_id, property_asset_id)
    references public.parcels(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index property_controls_asset_idx
  on public.property_control_records(property_asset_id, record_type, recorded_at);

-- ===========================================================================
-- 4. Development phases and milestones (no task-management subsystem)
-- ===========================================================================
create table public.development_phases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  parcel_id uuid,
  name text not null check (char_length(trim(name)) between 2 and 160),
  sequence_no integer not null check (sequence_no > 0),
  planned_start_date date,
  planned_end_date date,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (planned_end_date is null or planned_start_date is null or planned_end_date >= planned_start_date),
  unique (property_asset_id, sequence_no),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id, property_asset_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (parcel_id, organization_id, project_id, property_asset_id)
    references public.parcels(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index development_phases_property_idx on public.development_phases(property_asset_id, sequence_no);

create table public.development_phase_state_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  phase_id uuid not null,
  previous_history_id uuid,
  previous_state text check (previous_state is null or previous_state in ('PLANNED','ACTIVE','COMPLETED','CANCELLED')),
  new_state text not null check (new_state in ('PLANNED','ACTIVE','COMPLETED','CANCELLED')),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (phase_id, previous_history_id),
  check ((previous_state is null and previous_history_id is null)
      or (previous_state is not null and previous_history_id is not null)),
  foreign key (previous_history_id, organization_id)
    references public.development_phase_state_history(id, organization_id) on delete restrict,
  foreign key (phase_id, organization_id, project_id, property_asset_id)
    references public.development_phases(id, organization_id, project_id, property_asset_id) on delete restrict
);
create unique index development_phase_one_initial_state
  on public.development_phase_state_history(phase_id) where previous_state is null;
create index development_phase_state_timeline_idx
  on public.development_phase_state_history(phase_id, changed_at, id);

create table public.development_milestones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  phase_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 160),
  sequence_no integer not null check (sequence_no > 0),
  planned_date date,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (phase_id, sequence_no),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id, property_asset_id, phase_id),
  foreign key (phase_id, organization_id, project_id, property_asset_id)
    references public.development_phases(id, organization_id, project_id, property_asset_id) on delete restrict
);
create index development_milestones_phase_idx on public.development_milestones(phase_id, sequence_no);

create table public.development_milestone_state_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  phase_id uuid not null,
  milestone_id uuid not null,
  previous_history_id uuid,
  previous_state text check (previous_state is null or previous_state in ('PLANNED','ACTIVE','COMPLETED','CANCELLED')),
  new_state text not null check (new_state in ('PLANNED','ACTIVE','COMPLETED','CANCELLED')),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (milestone_id, previous_history_id),
  check ((previous_state is null and previous_history_id is null)
      or (previous_state is not null and previous_history_id is not null)),
  foreign key (previous_history_id, organization_id)
    references public.development_milestone_state_history(id, organization_id) on delete restrict,
  foreign key (milestone_id, organization_id, project_id, property_asset_id, phase_id)
    references public.development_milestones(id, organization_id, project_id, property_asset_id, phase_id) on delete restrict
);
create unique index development_milestone_one_initial_state
  on public.development_milestone_state_history(milestone_id) where previous_state is null;
create index development_milestone_state_timeline_idx
  on public.development_milestone_state_history(milestone_id, changed_at, id);

-- ===========================================================================
-- 5. Versioned budget, operational cost dimensions, valuation, sector events
-- ===========================================================================
create table public.property_budget_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  version_no integer not null check (version_no > 0),
  status text not null default 'PROPOSED' check (status in ('PROPOSED','APPROVED')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  basis_notes text not null check (char_length(trim(basis_notes)) between 3 and 1000),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check ((status = 'PROPOSED' and approved_by is null and approved_at is null and approval_idempotency_key is null and approval_request_hash is null)
      or (status = 'APPROVED' and approved_by is not null and approved_at is not null and approval_idempotency_key is not null and approval_request_hash is not null)),
  unique (property_asset_id, version_no),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id, property_asset_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict
);
create unique index property_budget_approval_key
  on public.property_budget_versions(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;

create table public.property_budget_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  budget_version_id uuid not null,
  parcel_id uuid,
  phase_id uuid,
  cost_category text not null check (cost_category in (
    'ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION',
    'PROFESSIONAL_FEES','HOLDING','OTHER'
  )),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  unique (budget_version_id, parcel_id, phase_id, cost_category),
  unique (id, organization_id),
  foreign key (budget_version_id, organization_id, project_id, property_asset_id)
    references public.property_budget_versions(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (parcel_id, organization_id, project_id, property_asset_id)
    references public.parcels(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (phase_id, organization_id, project_id, property_asset_id)
    references public.development_phases(id, organization_id, project_id, property_asset_id) on delete restrict
);

create table public.property_cost_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  parcel_id uuid,
  phase_id uuid,
  cost_obligation_id uuid not null,
  cost_category text not null check (cost_category in (
    'ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION',
    'PROFESSIONAL_FEES','HOLDING','OTHER'
  )),
  policy_reference text not null check (char_length(trim(policy_reference)) between 3 and 200),
  classified_by uuid not null references auth.users(id) on delete restrict,
  classified_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (cost_obligation_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (cost_obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (parcel_id, organization_id, project_id, property_asset_id)
    references public.parcels(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (phase_id, organization_id, project_id, property_asset_id)
    references public.development_phases(id, organization_id, project_id, property_asset_id) on delete restrict
);
create index property_cost_items_dimensions_idx
  on public.property_cost_items(property_asset_id, parcel_id, phase_id, cost_category);

create table public.property_valuations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null,
  effective_date date not null,
  valuer_source text not null check (char_length(trim(valuer_source)) between 2 and 160),
  method text not null check (char_length(trim(method)) between 2 and 120),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  assumptions_notes text not null check (char_length(trim(assumptions_notes)) between 3 and 2000),
  confidence text check (confidence is null or confidence in ('LOW','MEDIUM','HIGH')),
  status text not null default 'PROPOSED' check (status in ('PROPOSED','APPROVED')),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check ((status = 'PROPOSED' and reviewed_by is null and reviewed_at is null and approval_idempotency_key is null and approval_request_hash is null)
      or (status = 'APPROVED' and reviewed_by is not null and reviewed_at is not null and approval_idempotency_key is not null and approval_request_hash is not null)),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict
);
create unique index property_valuation_approval_key
  on public.property_valuations(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;

create table public.real_estate_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid,
  parcel_id uuid,
  phase_id uuid,
  milestone_id uuid,
  event_type text not null check (event_type in (
    'SITE_VISIT','DEVELOPMENT_PROGRESS','CONTROL_OBSERVATION','MILESTONE_NOTE','OTHER'
  )),
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  quantity numeric(20,6),
  unit text check (unit is null or char_length(trim(unit)) between 1 and 40),
  responsible_actor_id uuid not null references auth.users(id) on delete restrict,
  location text check (location is null or char_length(trim(location)) between 1 and 300),
  notes text not null check (char_length(trim(notes)) between 3 and 1000),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  confirmed_by uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check ((quantity is null and unit is null) or (quantity is not null and quantity > 0 and unit is not null)),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (property_asset_id, organization_id, project_id)
    references public.property_assets(id, organization_id, project_id) on delete restrict,
  foreign key (parcel_id, organization_id, project_id, property_asset_id)
    references public.parcels(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (phase_id, organization_id, project_id, property_asset_id)
    references public.development_phases(id, organization_id, project_id, property_asset_id) on delete restrict,
  foreign key (milestone_id, organization_id, project_id, property_asset_id, phase_id)
    references public.development_milestones(id, organization_id, project_id, property_asset_id, phase_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index real_estate_events_project_timeline_idx on public.real_estate_events(project_id, occurred_at desc);

-- ===========================================================================
-- 6. Database guards: immutable facts, hierarchy, and transitions
-- ===========================================================================
create or replace function public.s3_guard_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'confirmed S3 facts and history are immutable';
end $$;

create trigger real_estate_profiles_immutable before update or delete on public.real_estate_project_profiles
for each row execute function public.s3_guard_immutable();
create trigger property_assets_immutable before update or delete on public.property_assets
for each row execute function public.s3_guard_immutable();
create trigger parcels_immutable before update or delete on public.parcels
for each row execute function public.s3_guard_immutable();
create trigger property_asset_history_immutable before update or delete on public.property_asset_state_history
for each row execute function public.s3_guard_immutable();
create trigger property_acquisitions_immutable before update or delete on public.property_acquisitions
for each row execute function public.s3_guard_immutable();
create trigger property_controls_immutable before update or delete on public.property_control_records
for each row execute function public.s3_guard_immutable();
create trigger development_phases_immutable before update or delete on public.development_phases
for each row execute function public.s3_guard_immutable();
create trigger development_phase_history_immutable before update or delete on public.development_phase_state_history
for each row execute function public.s3_guard_immutable();
create trigger development_milestones_immutable before update or delete on public.development_milestones
for each row execute function public.s3_guard_immutable();
create trigger development_milestone_history_immutable before update or delete on public.development_milestone_state_history
for each row execute function public.s3_guard_immutable();
create trigger property_budget_lines_immutable before update or delete on public.property_budget_lines
for each row execute function public.s3_guard_immutable();
create trigger property_cost_items_immutable before update or delete on public.property_cost_items
for each row execute function public.s3_guard_immutable();
create trigger real_estate_events_immutable before update or delete on public.real_estate_events
for each row execute function public.s3_guard_immutable();

create or replace function public.s3_guard_budget_approval_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status <> 'PROPOSED' or new.status <> 'APPROVED'
     or new.id <> old.id or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id or new.property_asset_id <> old.property_asset_id
     or new.version_no <> old.version_no or new.currency <> old.currency
     or new.basis_notes <> old.basis_notes or new.prepared_by <> old.prepared_by
     or new.prepared_at <> old.prepared_at or new.idempotency_key <> old.idempotency_key
     or new.request_hash <> old.request_hash
     or new.approved_by is null or new.approved_at is null
     or new.approval_idempotency_key is null or new.approval_request_hash is null then
    raise exception 'budget versions are immutable except controlled approval';
  end if;
  return new;
end $$;
create trigger property_budget_approval_only before update on public.property_budget_versions
for each row execute function public.s3_guard_budget_approval_only();
create trigger property_budget_no_delete before delete on public.property_budget_versions
for each row execute function public.s3_guard_immutable();

create or replace function public.s3_guard_valuation_approval_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status <> 'PROPOSED' or new.status <> 'APPROVED'
     or new.id <> old.id or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id or new.property_asset_id <> old.property_asset_id
     or new.effective_date <> old.effective_date or new.valuer_source <> old.valuer_source
     or new.method <> old.method or new.amount_minor_units <> old.amount_minor_units
     or new.currency <> old.currency or new.assumptions_notes <> old.assumptions_notes
     or new.confidence is distinct from old.confidence
     or new.evidence_reference <> old.evidence_reference
     or new.prepared_by <> old.prepared_by or new.prepared_at <> old.prepared_at
     or new.idempotency_key <> old.idempotency_key or new.request_hash <> old.request_hash
     or new.reviewed_by is null or new.reviewed_at is null
     or new.approval_idempotency_key is null or new.approval_request_hash is null then
    raise exception 'valuations are immutable except controlled approval';
  end if;
  return new;
end $$;
create trigger property_valuation_approval_only before update on public.property_valuations
for each row execute function public.s3_guard_valuation_approval_only();
create trigger property_valuation_no_delete before delete on public.property_valuations
for each row execute function public.s3_guard_immutable();

create or replace function public.s3_current_property_state(p_property_asset_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state from public.property_asset_state_history h
  where h.property_asset_id = p_property_asset_id
  order by h.changed_at desc, h.id desc limit 1
$$;

create or replace function public.s3_current_phase_state(p_phase_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state from public.development_phase_state_history h
  where h.phase_id = p_phase_id order by h.changed_at desc, h.id desc limit 1
$$;

create or replace function public.s3_current_milestone_state(p_milestone_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state from public.development_milestone_state_history h
  where h.milestone_id = p_milestone_id order by h.changed_at desc, h.id desc limit 1
$$;

-- Baseline control policy used by the stable lifecycle orchestrator. Later
-- forward migrations refine how whole-asset/current evidence is resolved by
-- replacing this policy helper without duplicating lifecycle behavior.
create or replace function public.s3_has_current_effective_control(
  p_property_asset_id uuid,
  p_record_type text
) returns boolean language sql stable set search_path=pg_catalog,public as $$
  select exists (
    select 1 from public.property_control_records c
    where c.property_asset_id=p_property_asset_id
      and c.record_type=p_record_type
      and c.status='PASSED'
      and c.effective_date is not null
      and c.effective_date<=current_date
      and (c.expiry_date is null or c.expiry_date>=current_date)
  )
$$;

create or replace function public.s3_validate_history_predecessor(
  p_current_history uuid, p_current_state text, p_previous_history uuid,
  p_previous_state text, p_new_state text, p_initial_state text
) returns boolean language plpgsql immutable set search_path=pg_catalog,public as $$
begin
  if p_current_state is null then
    if p_previous_state is not null or p_previous_history is not null or p_new_state <> p_initial_state then
      raise exception 'lifecycle must begin at %', p_initial_state;
    end if;
    return true;
  end if;
  if p_previous_state is null or p_previous_state <> p_current_state
     or p_previous_history is distinct from p_current_history then
    raise exception 'lifecycle expected state mismatch';
  end if;
  return false;
end $$;

create or replace function public.s3_validate_property_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_current text; v_current_history uuid;
begin
  perform 1 from public.property_assets a where a.id = new.property_asset_id for update;
  select h.id,h.new_state into v_current_history,v_current
  from public.property_asset_state_history h where h.property_asset_id=new.property_asset_id
  order by h.changed_at desc,h.id desc limit 1;

  if public.s3_validate_history_predecessor(
    v_current_history,v_current,new.previous_history_id,new.previous_state,new.new_state,'CANDIDATE'
  ) then return new; end if;

  if not ((v_current = 'CANDIDATE' and new.new_state = 'DUE_DILIGENCE')
       or (v_current = 'DUE_DILIGENCE' and new.new_state = 'ACQUIRING')
       or (v_current = 'ACQUIRING' and new.new_state = 'HELD')
       or (v_current = 'HELD' and new.new_state = 'DEVELOPING')
       or (v_current = 'DEVELOPING' and new.new_state = 'HELD')) then
    raise exception 'invalid property lifecycle transition: % -> %', v_current, new.new_state;
  end if;

  if v_current = 'DUE_DILIGENCE' and new.new_state = 'ACQUIRING' then
    if not exists (
      select 1 from public.property_acquisitions a
      where a.property_asset_id = new.property_asset_id
    ) then
      raise exception 'acquiring requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'ACQUISITION_CHECK') then
      raise exception 'acquiring requires current effective passed acquisition due-diligence coverage';
    end if;
  end if;

  if v_current = 'ACQUIRING' and new.new_state = 'HELD' then
    if not exists (
      select 1 from public.property_acquisitions a
      where a.property_asset_id = new.property_asset_id
    ) then
      raise exception 'held requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE') then
      raise exception 'held requires current effective passed title coverage';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'held requires current effective passed possession coverage';
    end if;
  end if;

  if v_current = 'HELD' and new.new_state = 'DEVELOPING' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'development requires current effective title and possession coverage';
    end if;
    if not exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'ACTIVE'
    ) then raise exception 'developing requires an active development phase'; end if;
  end if;

  if v_current = 'DEVELOPING' and new.new_state = 'HELD' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'returning to held requires current effective title and possession coverage';
    end if;
    if exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'ACTIVE'
    ) then raise exception 'returning to held requires no active development phase'; end if;
    if not exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'COMPLETED'
    ) then raise exception 'returning to held requires a completed development phase'; end if;
  end if;

  return new;
end $$;
create trigger property_transition_guard before insert on public.property_asset_state_history
for each row execute function public.s3_validate_property_transition();

create or replace function public.s3_validate_phase_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_current text; v_asset_state text; v_current_history uuid;
begin
  perform 1 from public.development_phases p where p.id = new.phase_id for update;
  select h.id,h.new_state into v_current_history,v_current
  from public.development_phase_state_history h where h.phase_id=new.phase_id
  order by h.changed_at desc,h.id desc limit 1;
  if public.s3_validate_history_predecessor(
    v_current_history,v_current,new.previous_history_id,new.previous_state,new.new_state,'PLANNED'
  ) then return new; end if;
  if not ((v_current = 'PLANNED' and new.new_state in ('ACTIVE','CANCELLED'))
       or (v_current = 'ACTIVE' and new.new_state in ('COMPLETED','CANCELLED'))) then
    raise exception 'invalid phase lifecycle transition: % -> %', v_current, new.new_state;
  end if;
  v_asset_state := public.s3_current_property_state(new.property_asset_id);
  if new.new_state = 'ACTIVE' and v_asset_state not in ('HELD','DEVELOPING') then
    raise exception 'a phase can start only while the property is held or developing';
  end if;
  if new.new_state = 'COMPLETED' and v_asset_state <> 'DEVELOPING' then
    raise exception 'a phase can complete only while the property is developing';
  end if;
  if new.new_state = 'COMPLETED' and exists (
    select 1 from public.development_milestones m
    where m.phase_id = new.phase_id and public.s3_current_milestone_state(m.id) = 'ACTIVE'
  ) then raise exception 'phase completion requires no active milestones'; end if;
  return new;
end $$;
create trigger phase_transition_guard before insert on public.development_phase_state_history
for each row execute function public.s3_validate_phase_transition();

create or replace function public.s3_validate_milestone_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_current text; v_phase_state text; v_current_history uuid;
begin
  perform 1 from public.development_milestones m where m.id = new.milestone_id for update;
  select h.id,h.new_state into v_current_history,v_current
  from public.development_milestone_state_history h where h.milestone_id=new.milestone_id
  order by h.changed_at desc,h.id desc limit 1;
  if public.s3_validate_history_predecessor(
    v_current_history,v_current,new.previous_history_id,new.previous_state,new.new_state,'PLANNED'
  ) then return new; end if;
  if not ((v_current = 'PLANNED' and new.new_state in ('ACTIVE','CANCELLED'))
       or (v_current = 'ACTIVE' and new.new_state in ('COMPLETED','CANCELLED'))) then
    raise exception 'invalid milestone lifecycle transition: % -> %', v_current, new.new_state;
  end if;
  v_phase_state := public.s3_current_phase_state(new.phase_id);
  if new.new_state in ('ACTIVE','COMPLETED') and v_phase_state <> 'ACTIVE' then
    raise exception 'active/completed milestone requires an active phase';
  end if;
  return new;
end $$;
create trigger milestone_transition_guard before insert on public.development_milestone_state_history
for each row execute function public.s3_validate_milestone_transition();

create or replace function public.s3_validate_acquisition_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_obligation record;
begin
  if new.consideration_obligation_id is not null then
    select * into v_obligation from public.cost_obligations
    where id = new.consideration_obligation_id and organization_id = new.organization_id;
    if not found or v_obligation.project_id <> new.project_id
       or v_obligation.party_id <> new.seller_party_id
       or v_obligation.amount_minor_units <> new.consideration_minor_units
       or v_obligation.currency <> new.currency then
      raise exception 'consideration obligation must match acquisition project, seller, amount, and currency';
    end if;
  end if;
  return new;
end $$;
create trigger property_acquisition_scope_guard before insert on public.property_acquisitions
for each row execute function public.s3_validate_acquisition_scope();

create or replace function public.s3_validate_control_actor() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1 from public.memberships m where m.organization_id = new.organization_id
      and m.user_id = new.responsible_actor_id and m.status = 'ACTIVE'
  ) then raise exception 'responsible actor must be an active organization member'; end if;
  return new;
end $$;
create trigger property_control_actor_guard before insert on public.property_control_records
for each row execute function public.s3_validate_control_actor();

create or replace function public.s3_validate_event_hierarchy() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.property_asset_id is null and (new.parcel_id is not null or new.phase_id is not null or new.milestone_id is not null) then
    raise exception 'parcel, phase, and milestone events require a property asset';
  end if;
  if new.phase_id is null and new.milestone_id is not null then
    raise exception 'milestone events require their phase';
  end if;
  if not exists (
    select 1 from public.memberships m where m.organization_id = new.organization_id
      and m.user_id = new.responsible_actor_id and m.status = 'ACTIVE'
  ) then raise exception 'responsible actor must be an active organization member'; end if;
  return new;
end $$;
create trigger real_estate_event_hierarchy_guard before insert on public.real_estate_events
for each row execute function public.s3_validate_event_hierarchy();

create or replace function public.s3_validate_cost_item_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_project uuid;
begin
  select project_id into v_project from public.cost_obligations
  where id = new.cost_obligation_id and organization_id = new.organization_id;
  if v_project is null or v_project <> new.project_id then
    raise exception 'cost obligation must belong to the real-estate project';
  end if;
  return new;
end $$;
create trigger property_cost_item_scope_guard before insert on public.property_cost_items
for each row execute function public.s3_validate_cost_item_scope();

-- ===========================================================================
-- 7. RLS: active members read; browser table DML remains denied
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'real_estate_project_profiles','property_assets','parcels','property_asset_state_history',
    'property_acquisitions','property_control_records','development_phases',
    'development_phase_state_history','development_milestones',
    'development_milestone_state_history','property_budget_versions','property_budget_lines',
    'property_cost_items','property_valuations','real_estate_events'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t || '_read', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ===========================================================================
-- 8. Server-authoritative commands
-- ===========================================================================
create or replace function public.create_real_estate_profile(
  p_organization_id uuid, p_project_id uuid, p_strategy text,
  p_jurisdiction text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_id uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_strategy not in ('ACQUIRE_HOLD','DEVELOP_SELL','LAND_TRADE') then raise exception 'invalid real-estate strategy'; end if;
  if p_jurisdiction is not null and char_length(trim(p_jurisdiction)) not between 2 and 120 then raise exception 'invalid jurisdiction'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if not exists (select 1 from public.investment_projects p where p.id=p_project_id and p.organization_id=p_organization_id and p.sector='REAL_ESTATE') then raise exception 'real-estate project not found'; end if;
  select encode(digest(p_project_id::text||'|'||p_strategy||'|'||coalesce(trim(p_jurisdiction),''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-profile:'||trim(p_idempotency_key),0));
  select * into v_existing from public.real_estate_project_profiles where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  if exists (select 1 from public.real_estate_project_profiles where project_id=p_project_id) then raise exception 'real-estate profile already exists for project'; end if;
  insert into public.real_estate_project_profiles(organization_id,project_id,strategy,jurisdiction,created_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,p_strategy,nullif(trim(p_jurisdiction),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'REAL_ESTATE_PROFILE_CREATED','real_estate_project_profile',v_id,jsonb_build_object('project_id',p_project_id,'strategy',p_strategy));
  return v_id;
end $$;

create or replace function public.create_property_asset(
  p_organization_id uuid, p_project_id uuid, p_name text,
  p_asset_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_profile uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid property name'; end if;
  if p_asset_reference is not null and char_length(trim(p_asset_reference)) not between 1 and 80 then raise exception 'invalid property reference'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select id into v_profile from public.real_estate_project_profiles where project_id=p_project_id and organization_id=p_organization_id;
  if v_profile is null then raise exception 'create the real-estate project profile first'; end if;
  select encode(digest(p_project_id::text||'|'||trim(p_name)||'|'||coalesce(trim(p_asset_reference),''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-asset:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_assets where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_assets(organization_id,project_id,profile_id,name,asset_reference,created_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,v_profile,trim(p_name),nullif(trim(p_asset_reference),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.property_asset_state_history(organization_id,project_id,property_asset_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,v_id,null,'CANDIDATE','إنشاء الأصل المرشح',v_actor,'initial-'||v_id::text,encode(digest(v_id::text||'|CANDIDATE','sha256'),'hex'));
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_ASSET_CREATED','property_asset',v_id,jsonb_build_object('project_id',p_project_id,'initial_state','CANDIDATE'));
  return v_id;
end $$;

create or replace function public.create_parcel(
  p_organization_id uuid, p_property_asset_id uuid, p_identifier text,
  p_cadastral_reference text, p_legal_description text, p_area_quantity numeric,
  p_area_unit text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select project_id into v_project from public.property_assets where id=p_property_asset_id and organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_identifier is null or char_length(trim(p_identifier)) not between 1 and 100 then raise exception 'invalid parcel identifier'; end if;
  if p_area_quantity is null or p_area_quantity<=0 then raise exception 'parcel area must be positive'; end if;
  if p_area_unit not in ('M2','HECTARE','FEDDAN') then raise exception 'invalid parcel area unit'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||trim(p_identifier)||'|'||coalesce(trim(p_cadastral_reference),'')||'|'||coalesce(trim(p_legal_description),'')||'|'||p_area_quantity::text||'|'||p_area_unit,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-parcel:'||trim(p_idempotency_key),0));
  select * into v_existing from public.parcels where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.parcels(organization_id,project_id,property_asset_id,identifier,cadastral_reference,legal_description,area_quantity,area_unit,created_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,trim(p_identifier),nullif(trim(p_cadastral_reference),''),nullif(trim(p_legal_description),''),p_area_quantity,p_area_unit,v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PARCEL_CREATED','parcel',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'area_quantity',p_area_quantity,'area_unit',p_area_unit));
  return v_id;
end $$;

create or replace function public.record_property_acquisition(
  p_organization_id uuid, p_property_asset_id uuid, p_seller_party_id uuid,
  p_contract_reference text, p_consideration_minor_units bigint,
  p_closing_costs_minor_units bigint, p_currency text, p_contract_date date,
  p_consideration_obligation_id uuid, p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_project_currency text; v_hash text; v_existing record; v_obligation record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  select a.project_id,p.reporting_currency into v_project,v_project_currency from public.property_assets a join public.investment_projects p on p.id=a.project_id where a.id=p_property_asset_id and a.organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_contract_reference is null or char_length(trim(p_contract_reference)) not between 2 and 120 then raise exception 'invalid acquisition contract reference'; end if;
  if p_consideration_minor_units is null or p_consideration_minor_units<=0 or coalesce(p_closing_costs_minor_units,-1)<0 then raise exception 'invalid acquisition money'; end if;
  if p_currency<>v_project_currency then raise exception 'acquisition currency must match project currency'; end if;
  if p_contract_date is null then raise exception 'acquisition contract date required'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'acquisition evidence reference required'; end if;
  if not exists(select 1 from public.parties where id=p_seller_party_id and organization_id=p_organization_id) then raise exception 'seller party not found'; end if;
  if p_consideration_obligation_id is not null then
    select * into v_obligation from public.cost_obligations where id=p_consideration_obligation_id and organization_id=p_organization_id;
    if not found or v_obligation.project_id<>v_project or v_obligation.party_id<>p_seller_party_id or v_obligation.amount_minor_units<>p_consideration_minor_units or v_obligation.currency<>p_currency then
      raise exception 'consideration obligation must match acquisition project, seller, amount, and currency';
    end if;
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||p_seller_party_id::text||'|'||trim(p_contract_reference)||'|'||p_consideration_minor_units::text||'|'||p_closing_costs_minor_units::text||'|'||p_currency||'|'||p_contract_date::text||'|'||coalesce(p_consideration_obligation_id::text,'')||'|'||trim(p_evidence_reference),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-acquisition:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_acquisitions where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_acquisitions(organization_id,project_id,property_asset_id,seller_party_id,contract_reference,consideration_minor_units,closing_costs_minor_units,currency,contract_date,consideration_obligation_id,evidence_reference,recorded_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,p_seller_party_id,trim(p_contract_reference),p_consideration_minor_units,p_closing_costs_minor_units,p_currency,p_contract_date,p_consideration_obligation_id,trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_ACQUISITION_RECORDED','property_acquisition',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'seller_party_id',p_seller_party_id,'consideration_minor_units',p_consideration_minor_units,'currency',p_currency,'obligation_id',p_consideration_obligation_id));
  return v_id;
end $$;

create or replace function public.record_property_control(
  p_organization_id uuid, p_property_asset_id uuid, p_parcel_id uuid,
  p_record_type text, p_control_type text, p_status text, p_effective_date date,
  p_expiry_date date, p_result text, p_responsible_actor_id uuid,
  p_evidence_reference text, p_notes text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select project_id into v_project from public.property_assets where id=p_property_asset_id and organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_record_type not in ('ACQUISITION_CHECK','TITLE','POSSESSION','PERMIT','INSPECTION') or p_status not in ('PENDING','PASSED','FAILED','EXPIRED') then raise exception 'invalid control record type or status'; end if;
  if p_control_type is null or char_length(trim(p_control_type)) not between 2 and 120 then raise exception 'invalid control type'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'control evidence reference required'; end if;
  if p_expiry_date is not null and p_effective_date is not null and p_expiry_date<p_effective_date then raise exception 'control expiry cannot precede effective date'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||coalesce(p_parcel_id::text,'')||'|'||p_record_type||'|'||trim(p_control_type)||'|'||p_status||'|'||coalesce(p_effective_date::text,'')||'|'||coalesce(p_expiry_date::text,'')||'|'||coalesce(trim(p_result),'')||'|'||p_responsible_actor_id::text||'|'||trim(p_evidence_reference)||'|'||coalesce(trim(p_notes),''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-control:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_control_records where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_control_records(organization_id,project_id,property_asset_id,parcel_id,record_type,control_type,status,effective_date,expiry_date,result,responsible_actor_id,evidence_reference,notes,recorded_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,p_parcel_id,p_record_type,trim(p_control_type),p_status,p_effective_date,p_expiry_date,nullif(trim(p_result),''),p_responsible_actor_id,trim(p_evidence_reference),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_CONTROL_RECORDED','property_control_record',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'record_type',p_record_type,'status',p_status,'evidence_reference',trim(p_evidence_reference)));
  return v_id;
end $$;

create or replace function public.transition_property_asset(
  p_organization_id uuid, p_property_asset_id uuid, p_expected_state text,
  p_new_state text, p_reason text, p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  select project_id into v_project from public.property_assets where id=p_property_asset_id and organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'transition reason required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||p_expected_state||'|'||p_new_state||'|'||trim(p_reason)||'|'||coalesce(trim(p_evidence_reference),''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-property-transition:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_asset_state_history where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_asset_state_history(organization_id,project_id,property_asset_id,previous_history_id,previous_state,new_state,reason,evidence_reference,changed_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,
    (select h.id from public.property_asset_state_history h where h.property_asset_id=p_property_asset_id order by h.changed_at desc,h.id desc limit 1),
    p_expected_state,p_new_state,trim(p_reason),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_STATE_CHANGED','property_asset',p_property_asset_id,jsonb_build_object('project_id',v_project,'previous_state',p_expected_state,'new_state',p_new_state,'reason',trim(p_reason),'history_id',v_id));
  return v_id;
end $$;

create or replace function public.create_development_phase(
  p_organization_id uuid, p_property_asset_id uuid, p_parcel_id uuid,
  p_name text, p_sequence_no integer, p_planned_start_date date,
  p_planned_end_date date, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select project_id into v_project from public.property_assets where id=p_property_asset_id and organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 or p_sequence_no is null or p_sequence_no<=0 then raise exception 'invalid phase name or sequence'; end if;
  if p_planned_end_date is not null and p_planned_start_date is not null and p_planned_end_date<p_planned_start_date then raise exception 'planned phase end cannot precede start'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||coalesce(p_parcel_id::text,'')||'|'||trim(p_name)||'|'||p_sequence_no::text||'|'||coalesce(p_planned_start_date::text,'')||'|'||coalesce(p_planned_end_date::text,''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-phase:'||trim(p_idempotency_key),0));
  select * into v_existing from public.development_phases where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.development_phases(organization_id,project_id,property_asset_id,parcel_id,name,sequence_no,planned_start_date,planned_end_date,created_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,p_parcel_id,trim(p_name),p_sequence_no,p_planned_start_date,p_planned_end_date,v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.development_phase_state_history(organization_id,project_id,property_asset_id,phase_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,v_id,null,'PLANNED','إنشاء مرحلة التطوير',v_actor,'initial-'||v_id::text,encode(digest(v_id::text||'|PLANNED','sha256'),'hex'));
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'DEVELOPMENT_PHASE_CREATED','development_phase',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'sequence_no',p_sequence_no));
  return v_id;
end $$;

create or replace function public.transition_development_phase(
  p_organization_id uuid, p_phase_id uuid, p_expected_state text,
  p_new_state text, p_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_phase record; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select * into v_phase from public.development_phases where id=p_phase_id and organization_id=p_organization_id;
  if not found then raise exception 'development phase not found'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'transition reason required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_phase_id::text||'|'||p_expected_state||'|'||p_new_state||'|'||trim(p_reason),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-phase-transition:'||trim(p_idempotency_key),0));
  select * into v_existing from public.development_phase_state_history where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.development_phase_state_history(organization_id,project_id,property_asset_id,phase_id,previous_history_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
  values(p_organization_id,v_phase.project_id,v_phase.property_asset_id,p_phase_id,
    (select h.id from public.development_phase_state_history h where h.phase_id=p_phase_id order by h.changed_at desc,h.id desc limit 1),
    p_expected_state,p_new_state,trim(p_reason),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'DEVELOPMENT_PHASE_STATE_CHANGED','development_phase',p_phase_id,jsonb_build_object('previous_state',p_expected_state,'new_state',p_new_state,'reason',trim(p_reason),'history_id',v_id));
  return v_id;
end $$;

create or replace function public.create_development_milestone(
  p_organization_id uuid, p_phase_id uuid, p_name text,
  p_sequence_no integer, p_planned_date date, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_phase record; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select * into v_phase from public.development_phases where id=p_phase_id and organization_id=p_organization_id;
  if not found then raise exception 'development phase not found'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 or p_sequence_no is null or p_sequence_no<=0 then raise exception 'invalid milestone name or sequence'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_phase_id::text||'|'||trim(p_name)||'|'||p_sequence_no::text||'|'||coalesce(p_planned_date::text,''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-milestone:'||trim(p_idempotency_key),0));
  select * into v_existing from public.development_milestones where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.development_milestones(organization_id,project_id,property_asset_id,phase_id,name,sequence_no,planned_date,created_by,idempotency_key,request_hash)
  values(p_organization_id,v_phase.project_id,v_phase.property_asset_id,p_phase_id,trim(p_name),p_sequence_no,p_planned_date,v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.development_milestone_state_history(organization_id,project_id,property_asset_id,phase_id,milestone_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
  values(p_organization_id,v_phase.project_id,v_phase.property_asset_id,p_phase_id,v_id,null,'PLANNED','إنشاء علامة مرحلة',v_actor,'initial-'||v_id::text,encode(digest(v_id::text||'|PLANNED','sha256'),'hex'));
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'DEVELOPMENT_MILESTONE_CREATED','development_milestone',v_id,jsonb_build_object('phase_id',p_phase_id,'sequence_no',p_sequence_no));
  return v_id;
end $$;

create or replace function public.transition_development_milestone(
  p_organization_id uuid, p_milestone_id uuid, p_expected_state text,
  p_new_state text, p_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_m record; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select * into v_m from public.development_milestones where id=p_milestone_id and organization_id=p_organization_id;
  if not found then raise exception 'development milestone not found'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'transition reason required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_milestone_id::text||'|'||p_expected_state||'|'||p_new_state||'|'||trim(p_reason),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-milestone-transition:'||trim(p_idempotency_key),0));
  select * into v_existing from public.development_milestone_state_history where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.development_milestone_state_history(organization_id,project_id,property_asset_id,phase_id,milestone_id,previous_history_id,previous_state,new_state,reason,changed_by,idempotency_key,request_hash)
  values(p_organization_id,v_m.project_id,v_m.property_asset_id,v_m.phase_id,p_milestone_id,
    (select h.id from public.development_milestone_state_history h where h.milestone_id=p_milestone_id order by h.changed_at desc,h.id desc limit 1),
    p_expected_state,p_new_state,trim(p_reason),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'DEVELOPMENT_MILESTONE_STATE_CHANGED','development_milestone',p_milestone_id,jsonb_build_object('previous_state',p_expected_state,'new_state',p_new_state,'reason',trim(p_reason),'history_id',v_id));
  return v_id;
end $$;

create or replace function public.propose_property_budget(
  p_organization_id uuid, p_property_asset_id uuid, p_currency text,
  p_basis_notes text, p_parcel_ids uuid[], p_phase_ids uuid[],
  p_cost_categories text[], p_amount_minor_units bigint[], p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_project_currency text; v_hash text; v_existing record; v_version integer; v_n integer; i integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select a.project_id,p.reporting_currency into v_project,v_project_currency from public.property_assets a join public.investment_projects p on p.id=a.project_id where a.id=p_property_asset_id and a.organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_currency<>v_project_currency then raise exception 'budget currency must match project currency'; end if;
  if p_basis_notes is null or char_length(trim(p_basis_notes)) not between 3 and 1000 then raise exception 'budget basis notes required'; end if;
  v_n:=array_length(p_cost_categories,1);
  if v_n is null or v_n<1 or array_length(p_amount_minor_units,1)<>v_n or coalesce(array_length(p_parcel_ids,1),v_n)<>v_n or coalesce(array_length(p_phase_ids,1),v_n)<>v_n then raise exception 'budget line arrays must have equal non-zero length'; end if;
  for i in 1..v_n loop
    if p_cost_categories[i] not in ('ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION','PROFESSIONAL_FEES','HOLDING','OTHER') or p_amount_minor_units[i] is null or p_amount_minor_units[i]<=0 then raise exception 'invalid budget line at position %',i; end if;
  end loop;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||p_currency||'|'||trim(p_basis_notes)||'|'||coalesce(array_to_string(p_parcel_ids,','),'')||'|'||coalesce(array_to_string(p_phase_ids,','),'')||'|'||array_to_string(p_cost_categories,',')||'|'||array_to_string(p_amount_minor_units,','),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-budget:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_budget_versions where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  perform 1 from public.property_assets where id=p_property_asset_id for update;
  select coalesce(max(version_no),0)+1 into v_version from public.property_budget_versions where property_asset_id=p_property_asset_id;
  insert into public.property_budget_versions(organization_id,project_id,property_asset_id,version_no,currency,basis_notes,prepared_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,v_version,p_currency,trim(p_basis_notes),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  for i in 1..v_n loop
    insert into public.property_budget_lines(organization_id,project_id,property_asset_id,budget_version_id,parcel_id,phase_id,cost_category,amount_minor_units)
    values(p_organization_id,v_project,p_property_asset_id,v_id,p_parcel_ids[i],p_phase_ids[i],p_cost_categories[i],p_amount_minor_units[i]);
  end loop;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_BUDGET_PROPOSED','property_budget_version',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'version_no',v_version,'line_count',v_n,'currency',p_currency));
  return v_id;
end $$;

create or replace function public.approve_property_budget(
  p_organization_id uuid, p_budget_version_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_budget record; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_budget_version_id::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-budget-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_budget_versions where organization_id=p_organization_id and approval_idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.id<>p_budget_version_id or v_existing.approval_request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  select * into v_budget from public.property_budget_versions where id=p_budget_version_id and organization_id=p_organization_id for update;
  if not found then raise exception 'budget version not found'; end if;
  if v_budget.status<>'PROPOSED' then raise exception 'only a proposed budget can be approved'; end if;
  update public.property_budget_versions set status='APPROVED',approved_by=v_actor,approved_at=now(),approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash where id=p_budget_version_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_BUDGET_APPROVED','property_budget_version',p_budget_version_id,jsonb_build_object('project_id',v_budget.project_id,'property_asset_id',v_budget.property_asset_id,'version_no',v_budget.version_no));
  return p_budget_version_id;
end $$;

create or replace function public.classify_property_cost(
  p_organization_id uuid, p_cost_obligation_id uuid, p_property_asset_id uuid,
  p_parcel_id uuid, p_phase_id uuid, p_cost_category text,
  p_policy_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_obligation record; v_asset_project uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select * into v_obligation from public.cost_obligations where id=p_cost_obligation_id and organization_id=p_organization_id;
  if not found then raise exception 'cost obligation not found'; end if;
  if v_obligation.status<>'DRAFT' then perform public.s2_require_owner(p_organization_id); end if;
  select project_id into v_asset_project from public.property_assets where id=p_property_asset_id and organization_id=p_organization_id;
  if v_asset_project is null or v_asset_project<>v_obligation.project_id then raise exception 'property and obligation must belong to the same project'; end if;
  if p_cost_category not in ('ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION','PROFESSIONAL_FEES','HOLDING','OTHER') then raise exception 'invalid property cost category'; end if;
  if p_policy_reference is null or char_length(trim(p_policy_reference)) not between 3 and 200 then raise exception 'cost policy reference required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_cost_obligation_id::text||'|'||p_property_asset_id::text||'|'||coalesce(p_parcel_id::text,'')||'|'||coalesce(p_phase_id::text,'')||'|'||p_cost_category||'|'||trim(p_policy_reference),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-cost-classify:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_cost_items where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_cost_items(organization_id,project_id,property_asset_id,parcel_id,phase_id,cost_obligation_id,cost_category,policy_reference,classified_by,idempotency_key,request_hash)
  values(p_organization_id,v_obligation.project_id,p_property_asset_id,p_parcel_id,p_phase_id,p_cost_obligation_id,p_cost_category,trim(p_policy_reference),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROPERTY_COST_CLASSIFIED','property_cost_item',v_id,jsonb_build_object('project_id',v_obligation.project_id,'property_asset_id',p_property_asset_id,'obligation_id',p_cost_obligation_id,'cost_category',p_cost_category,'policy_reference',trim(p_policy_reference)));
  return v_id;
end $$;

create or replace function public.propose_property_valuation(
  p_organization_id uuid, p_property_asset_id uuid, p_effective_date date,
  p_valuer_source text, p_method text, p_amount_minor_units bigint,
  p_currency text, p_assumptions_notes text, p_confidence text,
  p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_project uuid; v_project_currency text; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select a.project_id,p.reporting_currency into v_project,v_project_currency from public.property_assets a join public.investment_projects p on p.id=a.project_id where a.id=p_property_asset_id and a.organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_effective_date is null or p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'valuation date and positive amount required'; end if;
  if p_currency<>v_project_currency then raise exception 'valuation currency must match project currency'; end if;
  if p_valuer_source is null or char_length(trim(p_valuer_source)) not between 2 and 160 or p_method is null or char_length(trim(p_method)) not between 2 and 120 then raise exception 'valuation source and method required'; end if;
  if p_assumptions_notes is null or char_length(trim(p_assumptions_notes)) not between 3 and 2000 then raise exception 'valuation assumptions required'; end if;
  if p_confidence is not null and p_confidence not in ('LOW','MEDIUM','HIGH') then raise exception 'invalid valuation confidence'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'valuation evidence reference required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_property_asset_id::text||'|'||p_effective_date::text||'|'||trim(p_valuer_source)||'|'||trim(p_method)||'|'||p_amount_minor_units::text||'|'||p_currency||'|'||trim(p_assumptions_notes)||'|'||coalesce(p_confidence,'')||'|'||trim(p_evidence_reference),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-valuation:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_valuations where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.property_valuations(organization_id,project_id,property_asset_id,effective_date,valuer_source,method,amount_minor_units,currency,assumptions_notes,confidence,evidence_reference,prepared_by,idempotency_key,request_hash)
  values(p_organization_id,v_project,p_property_asset_id,p_effective_date,trim(p_valuer_source),trim(p_method),p_amount_minor_units,p_currency,trim(p_assumptions_notes),p_confidence,trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'MANAGEMENT_VALUATION_PROPOSED','property_valuation',v_id,jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'effective_date',p_effective_date,'amount_minor_units',p_amount_minor_units,'currency',p_currency,'accounting_effect','NONE'));
  return v_id;
end $$;

create or replace function public.approve_property_valuation(
  p_organization_id uuid, p_valuation_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_valuation record; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_valuation_id::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-valuation-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.property_valuations where organization_id=p_organization_id and approval_idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.id<>p_valuation_id or v_existing.approval_request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  select * into v_valuation from public.property_valuations where id=p_valuation_id and organization_id=p_organization_id for update;
  if not found then raise exception 'valuation not found'; end if;
  if v_valuation.status<>'PROPOSED' then raise exception 'only a proposed valuation can be approved'; end if;
  update public.property_valuations set status='APPROVED',reviewed_by=v_actor,reviewed_at=now(),approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash where id=p_valuation_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'MANAGEMENT_VALUATION_APPROVED','property_valuation',p_valuation_id,jsonb_build_object('project_id',v_valuation.project_id,'property_asset_id',v_valuation.property_asset_id,'effective_date',v_valuation.effective_date,'amount_minor_units',v_valuation.amount_minor_units,'currency',v_valuation.currency,'accounting_effect','NONE'));
  return p_valuation_id;
end $$;

create or replace function public.confirm_real_estate_event(
  p_organization_id uuid, p_project_id uuid, p_property_asset_id uuid,
  p_parcel_id uuid, p_phase_id uuid, p_milestone_id uuid,
  p_event_type text, p_occurred_at timestamptz, p_quantity numeric,
  p_unit text, p_responsible_actor_id uuid, p_location text, p_notes text,
  p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists(select 1 from public.investment_projects where id=p_project_id and organization_id=p_organization_id and sector='REAL_ESTATE') then raise exception 'real-estate project not found'; end if;
  if p_event_type not in ('SITE_VISIT','DEVELOPMENT_PROGRESS','CONTROL_OBSERVATION','MILESTONE_NOTE','OTHER') or p_occurred_at is null then raise exception 'invalid event type or occurred time'; end if;
  if (p_quantity is null)<>(p_unit is null) or (p_quantity is not null and p_quantity<=0) then raise exception 'event quantity requires a positive value and explicit unit'; end if;
  if p_notes is null or char_length(trim(p_notes)) not between 3 and 1000 then raise exception 'event notes required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select encode(digest(p_project_id::text||'|'||coalesce(p_property_asset_id::text,'')||'|'||coalesce(p_parcel_id::text,'')||'|'||coalesce(p_phase_id::text,'')||'|'||coalesce(p_milestone_id::text,'')||'|'||p_event_type||'|'||p_occurred_at::text||'|'||coalesce(p_quantity::text,'')||'|'||coalesce(trim(p_unit),'')||'|'||p_responsible_actor_id::text||'|'||coalesce(trim(p_location),'')||'|'||trim(p_notes)||'|'||coalesce(trim(p_evidence_reference),''),'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-event:'||trim(p_idempotency_key),0));
  select * into v_existing from public.real_estate_events where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_existing.id; end if;
  insert into public.real_estate_events(organization_id,project_id,property_asset_id,parcel_id,phase_id,milestone_id,event_type,occurred_at,quantity,unit,responsible_actor_id,location,notes,evidence_reference,confirmed_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,p_property_asset_id,p_parcel_id,p_phase_id,p_milestone_id,p_event_type,p_occurred_at,p_quantity,nullif(trim(p_unit),''),p_responsible_actor_id,nullif(trim(p_location),''),trim(p_notes),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'REAL_ESTATE_EVENT_CONFIRMED','real_estate_event',v_id,jsonb_build_object('project_id',p_project_id,'property_asset_id',p_property_asset_id,'event_type',p_event_type,'occurred_at',p_occurred_at,'quantity',p_quantity,'unit',p_unit));
  return v_id;
end $$;

-- ===========================================================================
-- 9. Read models: state, separation, budget/commitment/actual, and drilldown
-- ===========================================================================
create or replace view public.property_asset_workspace_read with (security_invoker=on) as
select a.id as property_asset_id,a.organization_id,a.project_id,a.name,a.asset_reference,
       p.strategy,p.jurisdiction,s.new_state as operational_state,s.changed_at as state_changed_at,
       title.status as title_status,title.effective_date as title_effective_date,title.evidence_reference as title_evidence_reference,
       possession.status as possession_status,possession.effective_date as possession_effective_date,possession.evidence_reference as possession_evidence_reference,
       acq.id as acquisition_id,case when acq.id is null then 'NOT_RECORDED' else 'CONTRACT_RECORDED' end as acquisition_state,
       acq.contract_reference,acq.contract_date,acq.consideration_minor_units::text as consideration_minor_units,
       acq.closing_costs_minor_units::text as closing_costs_minor_units,acq.currency as acquisition_currency,
       acq.consideration_obligation_id,
       case when acq.consideration_obligation_id is null then 'NOT_LINKED'
            when op.is_reversed then 'OBLIGATION_REVERSED'
            when op.status='DRAFT' then 'OBLIGATION_DRAFT'
            when op.paid_minor_units::bigint=0 then 'UNPAID'
            when op.outstanding_minor_units::bigint=0 then 'PAID'
            else 'PARTIALLY_PAID' end as acquisition_payment_status
from public.property_assets a
join public.real_estate_project_profiles p on p.id=a.profile_id
left join lateral (select h.new_state,h.changed_at from public.property_asset_state_history h where h.property_asset_id=a.id order by h.changed_at desc,h.id desc limit 1) s on true
left join lateral (select c.status,c.effective_date,c.evidence_reference from public.property_control_records c where c.property_asset_id=a.id and c.record_type='TITLE' order by c.recorded_at desc,c.id desc limit 1) title on true
left join lateral (select c.status,c.effective_date,c.evidence_reference from public.property_control_records c where c.property_asset_id=a.id and c.record_type='POSSESSION' order by c.recorded_at desc,c.id desc limit 1) possession on true
left join public.property_acquisitions acq on acq.property_asset_id=a.id
left join public.cost_obligation_position_read op on op.obligation_id=acq.consideration_obligation_id;

create or replace view public.parcels_read with (security_invoker=on) as
select id,organization_id,project_id,property_asset_id,identifier,cadastral_reference,legal_description,
       area_quantity::text as area_quantity,area_unit,created_by,created_at
from public.parcels;

create or replace view public.development_phases_read with (security_invoker=on) as
select p.id as phase_id,p.organization_id,p.project_id,p.property_asset_id,p.parcel_id,p.name,p.sequence_no,
       p.planned_start_date,p.planned_end_date,s.new_state as operational_state,
       active.changed_at as actual_start_at,completed.changed_at as actual_end_at,p.created_at
from public.development_phases p
left join lateral (select h.new_state from public.development_phase_state_history h where h.phase_id=p.id order by h.changed_at desc,h.id desc limit 1) s on true
left join lateral (select min(h.changed_at) as changed_at from public.development_phase_state_history h where h.phase_id=p.id and h.new_state='ACTIVE') active on true
left join lateral (select min(h.changed_at) as changed_at from public.development_phase_state_history h where h.phase_id=p.id and h.new_state='COMPLETED') completed on true;

create or replace view public.development_milestones_read with (security_invoker=on) as
select m.id as milestone_id,m.organization_id,m.project_id,m.property_asset_id,m.phase_id,m.name,m.sequence_no,m.planned_date,
       s.new_state as operational_state,completed.changed_at as completed_at,m.created_at
from public.development_milestones m
left join lateral (select h.new_state from public.development_milestone_state_history h where h.milestone_id=m.id order by h.changed_at desc,h.id desc limit 1) s on true
left join lateral (select min(h.changed_at) as changed_at from public.development_milestone_state_history h where h.milestone_id=m.id and h.new_state='COMPLETED') completed on true;

create or replace view public.property_controls_read with (security_invoker=on) as
select id,organization_id,project_id,property_asset_id,parcel_id,record_type,control_type,status,effective_date,expiry_date,result,
       responsible_actor_id,evidence_reference,notes,recorded_by,recorded_at
from public.property_control_records;

create or replace view public.property_budget_versions_read with (security_invoker=on) as
select v.id as budget_version_id,v.organization_id,v.project_id,v.property_asset_id,v.version_no,v.status,v.currency,v.basis_notes,
       coalesce(sum(l.amount_minor_units),0)::text as total_minor_units,v.prepared_by,v.prepared_at,v.approved_by,v.approved_at
from public.property_budget_versions v join public.property_budget_lines l on l.budget_version_id=v.id
group by v.id;

create or replace view public.property_valuations_read with (security_invoker=on) as
select id as valuation_id,organization_id,project_id,property_asset_id,effective_date,valuer_source,method,
       amount_minor_units::text as amount_minor_units,currency,assumptions_notes,confidence,status,evidence_reference,
       prepared_by,prepared_at,reviewed_by,reviewed_at
from public.property_valuations;

create or replace view public.real_estate_events_read with (security_invoker=on) as
select id as event_id,organization_id,project_id,property_asset_id,parcel_id,phase_id,milestone_id,event_type,
       occurred_at,recorded_at,quantity::text as quantity,unit,responsible_actor_id,location,notes,evidence_reference,confirmed_by
from public.real_estate_events;

create or replace view public.property_cost_drilldown_read with (security_invoker=on) as
select pci.id as property_cost_item_id,pci.organization_id,pci.project_id,pci.property_asset_id,pci.parcel_id,pci.phase_id,
       pci.cost_category,pci.policy_reference,o.id as obligation_id,o.description,o.cost_treatment,o.status as obligation_status,
       o.amount_minor_units::text as obligation_minor_units,o.currency,
       case when auth.id is not null and rev.id is null then (o.amount_minor_units-coalesce(paid.amount_minor_units,0)) else 0 end::text as committed_minor_units,
       coalesce(actual.amount_minor_units,0)::text as actual_minor_units,
       auth.id as originating_batch_id,(rev.id is not null) as is_reversed,o.authorized_at,pci.classified_at
from public.property_cost_items pci
join public.cost_obligations o on o.id=pci.cost_obligation_id
left join public.journal_batches auth on auth.organization_id=o.organization_id and auth.source_type='COST_OBLIGATION' and auth.source_id=o.id
left join public.journal_batches rev on rev.reversal_of_batch_id=auth.id
left join lateral (
  select coalesce(sum(pp.amount_minor_units),0) as amount_minor_units
  from public.project_payments pp join public.journal_batches pb on pb.source_type='PAYMENT' and pb.source_id=pp.id
  where pp.obligation_id=o.id and not exists(select 1 from public.journal_batches pr where pr.reversal_of_batch_id=pb.id)
) paid on true
left join lateral (
  select coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0) as amount_minor_units
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.obligation_id=o.id and sa.role in ('PROJECT_EXPENSE','DEVELOPMENT_WIP')
) actual on true;

create or replace view public.property_cost_control_read with (security_invoker=on) as
with latest_budget as (
  select distinct on (property_asset_id) id,property_asset_id,currency
  from public.property_budget_versions where status='APPROVED'
  order by property_asset_id,version_no desc
), keys as (
  select bl.organization_id,bl.project_id,bl.property_asset_id,bl.parcel_id,bl.phase_id,bl.cost_category,bv.currency
  from public.property_budget_lines bl join latest_budget lb on lb.id=bl.budget_version_id join public.property_budget_versions bv on bv.id=bl.budget_version_id
  union
  select pci.organization_id,pci.project_id,pci.property_asset_id,pci.parcel_id,pci.phase_id,pci.cost_category,o.currency
  from public.property_cost_items pci join public.cost_obligations o on o.id=pci.cost_obligation_id
)
select k.organization_id,k.project_id,k.property_asset_id,k.parcel_id,k.phase_id,k.cost_category,k.currency,
       coalesce((select sum(bl.amount_minor_units) from public.property_budget_lines bl join latest_budget lb on lb.id=bl.budget_version_id where bl.property_asset_id=k.property_asset_id and bl.parcel_id is not distinct from k.parcel_id and bl.phase_id is not distinct from k.phase_id and bl.cost_category=k.cost_category),0)::text as budget_minor_units,
       coalesce((select sum(d.committed_minor_units::bigint) from public.property_cost_drilldown_read d where d.property_asset_id=k.property_asset_id and d.parcel_id is not distinct from k.parcel_id and d.phase_id is not distinct from k.phase_id and d.cost_category=k.cost_category and d.currency=k.currency),0)::text as committed_minor_units,
       coalesce((select sum(d.actual_minor_units::bigint) from public.property_cost_drilldown_read d where d.property_asset_id=k.property_asset_id and d.parcel_id is not distinct from k.parcel_id and d.phase_id is not distinct from k.phase_id and d.cost_category=k.cost_category and d.currency=k.currency),0)::text as actual_minor_units,
       (coalesce((select sum(bl.amount_minor_units) from public.property_budget_lines bl join latest_budget lb on lb.id=bl.budget_version_id where bl.property_asset_id=k.property_asset_id and bl.parcel_id is not distinct from k.parcel_id and bl.phase_id is not distinct from k.phase_id and bl.cost_category=k.cost_category),0)
        -coalesce((select sum(d.actual_minor_units::bigint) from public.property_cost_drilldown_read d where d.property_asset_id=k.property_asset_id and d.parcel_id is not distinct from k.parcel_id and d.phase_id is not distinct from k.phase_id and d.cost_category=k.cost_category and d.currency=k.currency),0))::text as variance_minor_units
from keys k;

create or replace view public.real_estate_timeline_read with (security_invoker=on) as
select id,organization_id,project_id,property_asset_id,changed_at as occurred_at,changed_by as actor_id,
       'PROPERTY_STATE_CHANGED'::text as event_type,new_state as state,reason,evidence_reference
from public.property_asset_state_history
union all
select h.id,h.organization_id,h.project_id,h.property_asset_id,h.changed_at,h.changed_by,
       'PHASE_STATE_CHANGED',h.new_state,h.reason,null
from public.development_phase_state_history h
union all
select h.id,h.organization_id,h.project_id,h.property_asset_id,h.changed_at,h.changed_by,
       'MILESTONE_STATE_CHANGED',h.new_state,h.reason,null
from public.development_milestone_state_history h
union all
select c.id,c.organization_id,c.project_id,c.property_asset_id,c.recorded_at,c.recorded_by,
       'CONTROL_RECORDED',c.status,c.record_type||': '||c.control_type,c.evidence_reference
from public.property_control_records c
union all
select e.id,e.organization_id,e.project_id,e.property_asset_id,e.occurred_at,e.confirmed_by,
       'SECTOR_EVENT_CONFIRMED',null,e.event_type||': '||e.notes,e.evidence_reference
from public.real_estate_events e
union all
select v.id,v.organization_id,v.project_id,v.property_asset_id,coalesce(v.reviewed_at,v.prepared_at),coalesce(v.reviewed_by,v.prepared_by),
       case when v.status='APPROVED' then 'VALUATION_APPROVED' else 'VALUATION_PROPOSED' end,v.status,'Management valuation: '||v.method,v.evidence_reference
from public.property_valuations v;

-- Views use underlying RLS and transport all money/quantity as text.
grant select on public.property_asset_workspace_read,public.parcels_read,
  public.development_phases_read,public.development_milestones_read,
  public.property_controls_read,public.property_budget_versions_read,
  public.property_valuations_read,public.real_estate_events_read,
  public.property_cost_drilldown_read,public.property_cost_control_read,
  public.real_estate_timeline_read to authenticated;

-- Internal current-state helpers are not callable by browser roles.
revoke all on function public.s3_current_property_state(uuid),public.s3_current_phase_state(uuid),public.s3_current_milestone_state(uuid),
  public.s3_validate_history_predecessor(uuid,text,uuid,text,text,text) from public,anon,authenticated;

-- Commands are the only authenticated write path. Keep one explicit command
-- registry so revoke/grant scopes cannot drift apart as the bounded slice grows.
do $$
declare
  v_command regprocedure;
begin
  foreach v_command in array array[
    'public.create_real_estate_profile(uuid,uuid,text,text,text)'::regprocedure,
    'public.create_property_asset(uuid,uuid,text,text,text)'::regprocedure,
    'public.create_parcel(uuid,uuid,text,text,text,numeric,text,text)'::regprocedure,
    'public.record_property_acquisition(uuid,uuid,uuid,text,bigint,bigint,text,date,uuid,text,text)'::regprocedure,
    'public.record_property_control(uuid,uuid,uuid,text,text,text,date,date,text,uuid,text,text,text)'::regprocedure,
    'public.transition_property_asset(uuid,uuid,text,text,text,text,text)'::regprocedure,
    'public.create_development_phase(uuid,uuid,uuid,text,integer,date,date,text)'::regprocedure,
    'public.transition_development_phase(uuid,uuid,text,text,text,text)'::regprocedure,
    'public.create_development_milestone(uuid,uuid,text,integer,date,text)'::regprocedure,
    'public.transition_development_milestone(uuid,uuid,text,text,text,text)'::regprocedure,
    'public.propose_property_budget(uuid,uuid,text,text,uuid[],uuid[],text[],bigint[],text)'::regprocedure,
    'public.approve_property_budget(uuid,uuid,text)'::regprocedure,
    'public.classify_property_cost(uuid,uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
    'public.propose_property_valuation(uuid,uuid,date,text,text,bigint,text,text,text,text,text)'::regprocedure,
    'public.approve_property_valuation(uuid,uuid,text)'::regprocedure,
    'public.confirm_real_estate_event(uuid,uuid,uuid,uuid,uuid,uuid,text,timestamptz,numeric,text,uuid,text,text,text,text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon',v_command);
    execute format('grant execute on function %s to authenticated',v_command);
  end loop;
end $$;
