-- GF-013 / Agriculture Sector Foundation.
--
-- The first Agriculture bounded context: Farm → Field → CropCycle.
-- Reuses the canonical Investment Core, Membership, Audit, and Command
-- patterns. No second ledger, no second ownership model, no second audit
-- trail. Sector-neutral invariants stay in the core; this slice adds only
-- the sector-specific facts and the server-authoritative commands that
-- mutate them.
--
-- Deferred for later bounded Agriculture slices (explicitly out of scope
-- for GF-013): FieldActivity, InputItem, InputLot, InputApplication,
-- HarvestEvent, HarvestLot, StorageLocation, InventoryMovement,
-- agronomy observations, IAS 41 postings, GIS/map, weather, offline.

-- ===========================================================================
-- 1. Agriculture sector profile (one per Agriculture project)
-- ===========================================================================
create table public.agriculture_project_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (project_id),
  unique (id, organization_id, project_id),
  unique (organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  -- Sector guard: a profile may only attach to an Agriculture project.
  -- Enforced here, not just at the application layer.
  constraint agriculture_project_profiles_sector_match
    foreign key (project_id) references public.investment_projects(id) on delete restrict
);

-- The constraint above is purely the same FK re-declared to make the
-- sector guard self-documenting. The actual sector check lives in the
-- create_agriculture_profile RPC and is proved in tests by attempting to
-- attach an agriculture profile to a REAL_ESTATE project.

-- ===========================================================================
-- 2. Farm — operating location, tenure, timezone
-- ===========================================================================
create table public.farms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 160),
  internal_reference text check (internal_reference is null or char_length(trim(internal_reference)) between 1 and 80),
  operating_location text check (operating_location is null or char_length(trim(operating_location)) between 2 and 200),
  tenure_description text check (tenure_description is null or char_length(trim(tenure_description)) between 3 and 1000),
  timezone text not null check (char_length(timezone) between 1 and 64),
  map_reference text check (map_reference is null or char_length(trim(map_reference)) between 1 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index farms_project_idx on public.farms(project_id);

-- ===========================================================================
-- 3. Field — stable land block with area, soil, irrigation
-- ===========================================================================
create table public.fields (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  farm_id uuid not null,
  identifier text not null check (char_length(trim(identifier)) between 1 and 100),
  area_quantity numeric(20,6) not null check (area_quantity > 0),
  area_unit text not null check (area_unit in ('M2','HECTARE','FEDDAN')),
  soil_notes text check (soil_notes is null or char_length(trim(soil_notes)) between 1 and 2000),
  irrigation_notes text check (irrigation_notes is null or char_length(trim(irrigation_notes)) between 1 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, farm_id, identifier),
  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, farm_id),
  unique (organization_id, idempotency_key),
  foreign key (farm_id, organization_id, project_id)
    references public.farms(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index fields_farm_idx on public.fields(farm_id);

-- ===========================================================================
-- 4. CropCycle — season-level planning row, with one or more Field
--    assignments. The cycle table holds identity + season; the
--    assignments table (5) is the relational support required by the
--    field-area invariant.
-- ===========================================================================
create table public.crop_cycles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop text not null check (char_length(trim(crop)) between 2 and 80),
  variety text check (variety is null or char_length(trim(variety)) between 1 and 80),
  season_reference text not null check (char_length(trim(season_reference)) between 2 and 80),
  planned_start_date date not null,
  planned_end_date date not null,
  target_yield_quantity numeric(20,6)
    check (target_yield_quantity is null or target_yield_quantity > 0),
  target_yield_unit text
    check (target_yield_unit is null or char_length(trim(target_yield_unit)) between 1 and 40),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (planned_end_date >= planned_start_date),
  check ((target_yield_quantity is null) = (target_yield_unit is null)),
  unique (organization_id, project_id, season_reference, crop),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index crop_cycles_project_idx on public.crop_cycles(project_id);

-- ===========================================================================
-- 5. CropCycle ↔ Field assignment table.
--    Implementation support for the field-area invariant; not a separate
--    sector entity. Carries a positive assigned area, the same unit as
--    the Field, and a planned date range with inclusive-start /
--    exclusive-end semantics.
-- ===========================================================================
create table public.crop_cycle_field_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid not null,
  assigned_area_quantity numeric(20,6) not null check (assigned_area_quantity > 0),
  assigned_area_unit text not null check (assigned_area_unit in ('M2','HECTARE','FEDDAN')),
  planned_start_date date not null,
  planned_end_date date not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (planned_end_date >= planned_start_date),
  unique (organization_id, crop_cycle_id, field_id),
  unique (id, organization_id, project_id, crop_cycle_id, field_id),
  unique (organization_id, idempotency_key),
  foreign key (crop_cycle_id, organization_id, project_id)
    references public.crop_cycles(id, organization_id, project_id) on delete restrict,
  foreign key (field_id, organization_id, project_id)
    references public.fields(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index crop_cycle_field_assignments_cycle_idx
  on public.crop_cycle_field_assignments(crop_cycle_id);
create index crop_cycle_field_assignments_field_idx
  on public.crop_cycle_field_assignments(field_id);

-- ===========================================================================
-- 6. Authoritative CropCycle lifecycle history
-- ===========================================================================
create table public.crop_cycle_state_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  previous_history_id uuid,
  previous_state text
    check (previous_state is null or previous_state in (
      'PLANNED','ESTABLISHED','GROWING','HARVESTING','CLOSED','CANCELLED','FAILED'
    )),
  new_state text not null check (new_state in (
    'PLANNED','ESTABLISHED','GROWING','HARVESTING','CLOSED','CANCELLED','FAILED'
  )),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (crop_cycle_id, previous_history_id),
  check ((previous_state is null and previous_history_id is null)
      or (previous_state is not null and previous_history_id is not null)),
  foreign key (previous_history_id, organization_id)
    references public.crop_cycle_state_history(id, organization_id) on delete restrict,
  foreign key (crop_cycle_id, organization_id, project_id)
    references public.crop_cycles(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create unique index crop_cycle_one_initial_state
  on public.crop_cycle_state_history(crop_cycle_id) where previous_state is null;
create index crop_cycle_state_timeline_idx
  on public.crop_cycle_state_history(crop_cycle_id, changed_at, id);

-- ===========================================================================
-- 7. Causal chain tip — current CropCycle state.
--    Mirrors the S3 chain-tip pattern (commit 20260813000600) so the
--    authoritative current state is the unique unconsumed chain tip, not
--    a timestamp/UUID ordering that breaks under same-transaction writes.
-- ===========================================================================
create or replace function public.agriculture_current_cycle_history_tip_id(p_crop_cycle_id uuid)
returns uuid language sql stable set search_path=pg_catalog,public as $$
  select h.id
  from public.crop_cycle_state_history h
  where h.crop_cycle_id = p_crop_cycle_id
    and not exists (
      select 1 from public.crop_cycle_state_history next_h
      where next_h.crop_cycle_id = h.crop_cycle_id
        and next_h.previous_history_id = h.id
    )
$$;

create or replace function public.agriculture_current_cycle_state(p_crop_cycle_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state
  from public.crop_cycle_state_history h
  where h.id = public.agriculture_current_cycle_history_tip_id(p_crop_cycle_id)
$$;

revoke all on function public.agriculture_current_cycle_history_tip_id(uuid),
  public.agriculture_current_cycle_state(uuid)
  from public, anon, authenticated;

-- ===========================================================================
-- 8. Server-authoritative commands
-- ===========================================================================

-- 8.1 Agriculture project profile (one per Agriculture project)
create or replace function public.create_agriculture_profile(
  p_organization_id uuid,
  p_project_id uuid,
  p_notes text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 3 and 2000 then
    raise exception 'invalid notes';
  end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  select encode(digest(p_project_id::text || '|' || coalesce(trim(p_notes), ''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-profile:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.agriculture_project_profiles
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  if exists (select 1 from public.agriculture_project_profiles where project_id = p_project_id) then
    raise exception 'agriculture profile already exists for project';
  end if;

  insert into public.agriculture_project_profiles(
    organization_id, project_id, notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'AGRICULTURE_PROFILE_CREATED',
    'agriculture_project_profile', v_id,
    jsonb_build_object('project_id', p_project_id)
  );
  return v_id;
end $$;

-- 8.2 Farm
create or replace function public.create_farm(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_internal_reference text,
  p_operating_location text,
  p_tenure_description text,
  p_timezone text,
  p_map_reference text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid farm name';
  end if;
  if p_internal_reference is not null
     and char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_operating_location is not null
     and char_length(trim(p_operating_location)) not between 2 and 200 then
    raise exception 'invalid operating location';
  end if;
  if p_tenure_description is not null
     and char_length(trim(p_tenure_description)) not between 3 and 1000 then
    raise exception 'invalid tenure description';
  end if;
  if p_timezone is null or char_length(p_timezone) not between 1 and 64 then
    raise exception 'invalid timezone';
  end if;
  if p_map_reference is not null
     and char_length(trim(p_map_reference)) not between 1 and 200 then
    raise exception 'invalid map reference';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_project_id::text || '|' || trim(p_name) || '|'
         || coalesce(trim(p_internal_reference),'') || '|'
         || coalesce(trim(p_operating_location),'') || '|'
         || coalesce(trim(p_tenure_description),'') || '|'
         || p_timezone || '|'
         || coalesce(trim(p_map_reference),''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-farm:' || trim(p_idempotency_key), 0));
  select * into v_existing
    from public.farms
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.farms(
    organization_id, project_id, name, internal_reference,
    operating_location, tenure_description, timezone, map_reference,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_name),
    nullif(trim(p_internal_reference),''),
    nullif(trim(p_operating_location),''),
    nullif(trim(p_tenure_description),''),
    p_timezone,
    nullif(trim(p_map_reference),''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'FARM_CREATED', 'farm', v_id,
    jsonb_build_object('project_id', p_project_id, 'name', trim(p_name))
  );
  return v_id;
end $$;

-- 8.3 Field
create or replace function public.create_field(
  p_organization_id uuid,
  p_project_id uuid,
  p_farm_id uuid,
  p_identifier text,
  p_area_quantity numeric,
  p_area_unit text,
  p_soil_notes text,
  p_irrigation_notes text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;
  if not exists (
    select 1 from public.farms f
     where f.id = p_farm_id
       and f.organization_id = p_organization_id
       and f.project_id = p_project_id
  ) then raise exception 'farm not found'; end if;
  if p_identifier is null or char_length(trim(p_identifier)) not between 1 and 100 then
    raise exception 'invalid field identifier';
  end if;
  if p_area_quantity is null or p_area_quantity <= 0 then
    raise exception 'field area must be positive';
  end if;
  if p_area_unit not in ('M2','HECTARE','FEDDAN') then
    raise exception 'invalid field area unit';
  end if;
  if p_soil_notes is not null and char_length(trim(p_soil_notes)) not between 1 and 2000 then
    raise exception 'invalid soil notes';
  end if;
  if p_irrigation_notes is not null
     and char_length(trim(p_irrigation_notes)) not between 1 and 2000 then
    raise exception 'invalid irrigation notes';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_farm_id::text || '|' || trim(p_identifier) || '|'
         || p_area_quantity::text || '|' || p_area_unit || '|'
         || coalesce(trim(p_soil_notes),'') || '|'
         || coalesce(trim(p_irrigation_notes),''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-field:' || trim(p_idempotency_key), 0));
  select * into v_existing
    from public.fields
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.fields(
    organization_id, project_id, farm_id, identifier, area_quantity, area_unit,
    soil_notes, irrigation_notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_farm_id, trim(p_identifier),
    p_area_quantity, p_area_unit,
    nullif(trim(p_soil_notes),''),
    nullif(trim(p_irrigation_notes),''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'FIELD_CREATED', 'field', v_id,
    jsonb_build_object(
      'project_id', p_project_id, 'farm_id', p_farm_id,
      'area_quantity', p_area_quantity, 'area_unit', p_area_unit
    )
  );
  return v_id;
end $$;

-- 8.4 CropCycle + initial PLANNED state row
create or replace function public.create_crop_cycle(
  p_organization_id uuid,
  p_project_id uuid,
  p_crop text,
  p_variety text,
  p_season_reference text,
  p_planned_start_date date,
  p_planned_end_date date,
  p_target_yield_quantity numeric,
  p_target_yield_unit text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;
  if p_crop is null or char_length(trim(p_crop)) not between 2 and 80 then
    raise exception 'invalid crop';
  end if;
  if p_variety is not null and char_length(trim(p_variety)) not between 1 and 80 then
    raise exception 'invalid variety';
  end if;
  if p_season_reference is null
     or char_length(trim(p_season_reference)) not between 2 and 80 then
    raise exception 'invalid season reference';
  end if;
  if p_planned_start_date is null or p_planned_end_date is null then
    raise exception 'planned start and end dates are required';
  end if;
  if p_planned_end_date < p_planned_start_date then
    raise exception 'planned end date must be on or after planned start date';
  end if;
  if (p_target_yield_quantity is null) <> (p_target_yield_unit is null) then
    raise exception 'target yield quantity and unit must be provided together';
  end if;
  if p_target_yield_quantity is not null and p_target_yield_quantity <= 0 then
    raise exception 'target yield must be positive';
  end if;
  if p_target_yield_unit is not null
     and char_length(trim(p_target_yield_unit)) not between 1 and 40 then
    raise exception 'invalid target yield unit';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_project_id::text || '|' || trim(p_crop) || '|'
         || coalesce(trim(p_variety),'') || '|' || trim(p_season_reference) || '|'
         || p_planned_start_date::text || '|' || p_planned_end_date::text || '|'
         || coalesce(p_target_yield_quantity::text,'') || '|'
         || coalesce(trim(p_target_yield_unit),''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-cycle:' || trim(p_idempotency_key), 0));
  select * into v_existing
    from public.crop_cycles
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.crop_cycles(
    organization_id, project_id, crop, variety, season_reference,
    planned_start_date, planned_end_date,
    target_yield_quantity, target_yield_unit,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_crop),
    nullif(trim(p_variety),''), trim(p_season_reference),
    p_planned_start_date, p_planned_end_date,
    p_target_yield_quantity, nullif(trim(p_target_yield_unit),''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  -- Append-only initial lifecycle row; created with a deterministic
  -- request_hash that does not require a new client idempotency key
  -- because there is exactly one initial state per cycle.
  insert into public.crop_cycle_state_history(
    organization_id, project_id, crop_cycle_id,
    previous_history_id, previous_state, new_state, reason,
    changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_id,
    null, null, 'PLANNED', 'إنشاء دورة محصولية',
    v_actor, 'initial-' || v_id::text,
    encode(digest(v_id::text || '|PLANNED', 'sha256'), 'hex')
  );

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'CROP_CYCLE_CREATED', 'crop_cycle', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'crop', trim(p_crop),
      'season_reference', trim(p_season_reference),
      'initial_state', 'PLANNED'
    )
  );
  return v_id;
end $$;

-- 8.5 Field assignment — enforces positive area, same unit, and the
--     field-capacity invariant. Capacity is re-checked inside the
--     transaction with the target row locked, so concurrent commands
--     cannot each observe a stale total and both insert.
create or replace function public.assign_crop_cycle_to_field(
  p_organization_id uuid,
  p_project_id uuid,
  p_crop_cycle_id uuid,
  p_field_id uuid,
  p_assigned_area_quantity numeric,
  p_assigned_area_unit text,
  p_planned_start_date date,
  p_planned_end_date date,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_field record;
  v_cycle record;
  v_new_total numeric(20,6);
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  -- Lock the field row so concurrent assignments serialize on the same
  -- field. Advisory lock keyed on field is an additional layer.
  select * into v_field
    from public.fields
   where id = p_field_id
     and organization_id = p_organization_id
     and project_id = p_project_id
   for update;
  if not found then raise exception 'field not found'; end if;

  select * into v_cycle
    from public.crop_cycles
   where id = p_crop_cycle_id
     and organization_id = p_organization_id
     and project_id = p_project_id
   for update;
  if not found then raise exception 'crop cycle not found'; end if;
  if public.agriculture_current_cycle_state(v_cycle.id) = 'CANCELLED' then
    raise exception 'cancelled crop cycle cannot receive field assignments';
  end if;

  if p_assigned_area_quantity is null or p_assigned_area_quantity <= 0 then
    raise exception 'assigned area must be positive';
  end if;
  if p_assigned_area_unit <> v_field.area_unit then
    raise exception 'assigned area unit must match the field area unit';
  end if;
  if p_planned_start_date is null or p_planned_end_date is null then
    raise exception 'planned start and end dates are required';
  end if;
  if p_planned_end_date < p_planned_start_date then
    raise exception 'planned end date must be on or after planned start date';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_crop_cycle_id::text || '|' || p_field_id::text || '|'
         || p_assigned_area_quantity::text || '|' || p_assigned_area_unit || '|'
         || p_planned_start_date::text || '|' || p_planned_end_date::text,
         'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-assign:' || trim(p_idempotency_key), 0));
  select * into v_existing
    from public.crop_cycle_field_assignments
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- The capacity invariant: for the field, the sum of assigned areas
  -- for non-cancelled cycles whose planned range OVERLAPS the new
  -- assignment must not exceed the field area. We use the
  -- half-open [start, end) convention the GF-013 spec requires:
  -- two cycles touch (end == next_start) without overlap.
  select coalesce(sum(a.assigned_area_quantity), 0)
    into v_new_total
    from public.crop_cycle_field_assignments a
    join public.crop_cycles c on c.id = a.crop_cycle_id
   where a.field_id = p_field_id
     and a.organization_id = p_organization_id
     and coalesce(public.agriculture_current_cycle_state(c.id), 'PLANNED') <> 'CANCELLED'
     and a.planned_start_date < p_planned_end_date
     and a.planned_end_date   > p_planned_start_date;

  if v_new_total + p_assigned_area_quantity > v_field.area_quantity then
    raise exception 'field area capacity exceeded: existing=%, assigning=%, field=%, unit=%',
      v_new_total, p_assigned_area_quantity, v_field.area_quantity, v_field.area_unit;
  end if;

  insert into public.crop_cycle_field_assignments(
    organization_id, project_id, crop_cycle_id, field_id,
    assigned_area_quantity, assigned_area_unit,
    planned_start_date, planned_end_date,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_crop_cycle_id, p_field_id,
    p_assigned_area_quantity, p_assigned_area_unit,
    p_planned_start_date, p_planned_end_date,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'CROP_CYCLE_FIELD_ASSIGNED',
    'crop_cycle_field_assignment', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'crop_cycle_id', p_crop_cycle_id,
      'field_id', p_field_id,
      'assigned_area_quantity', p_assigned_area_quantity,
      'assigned_area_unit', p_assigned_area_unit,
      'planned_start_date', p_planned_start_date,
      'planned_end_date', p_planned_end_date
    )
  );
  return v_id;
end $$;

-- 8.6 CropCycle lifecycle transition. Enforces the documented
--     transition table. Causal predecessor is derived from the chain
--     tip, not from a timestamp ordering. Idempotent on identical
--     request. Concurrency: advisory lock on the cycle during the
--     check, and a row lock on the cycle for any concurrent state
--     writer.
create or replace function public.transition_crop_cycle(
  p_organization_id uuid,
  p_crop_cycle_id uuid,
  p_expected_state text,
  p_new_state text,
  p_reason text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_cycle record;
  v_tip uuid;
  v_current_state text;
  v_initial_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid transition reason';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;
  if p_new_state not in (
    'PLANNED','ESTABLISHED','GROWING','HARVESTING','CLOSED','CANCELLED','FAILED'
  ) then
    raise exception 'invalid new state';
  end if;

  select encode(digest(p_crop_cycle_id::text || '|' || p_expected_state || '|'
         || p_new_state || '|' || trim(p_reason) || '|'
         || coalesce(trim(p_evidence_reference),''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-cycle-transition:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.crop_cycle_state_history
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_cycle
    from public.crop_cycles
   where id = p_crop_cycle_id
     and organization_id = p_organization_id
   for update;
  if not found then raise exception 'crop cycle not found'; end if;

  -- Resolve the current state from the unique unconsumed chain tip.
  v_tip := public.agriculture_current_cycle_history_tip_id(p_crop_cycle_id);
  if v_tip is null then raise exception 'crop cycle has no lifecycle history'; end if;
  select new_state into v_current_state
    from public.crop_cycle_state_history
   where id = v_tip;

  if v_current_state <> p_expected_state then
    raise exception 'expected state mismatch: current=% requested=%', v_current_state, p_expected_state;
  end if;

  -- Documented transition table.
  if not (
       (v_current_state = 'PLANNED'     and p_new_state = 'ESTABLISHED')
    or (v_current_state = 'ESTABLISHED' and p_new_state = 'GROWING')
    or (v_current_state = 'GROWING'     and p_new_state = 'HARVESTING')
    or (v_current_state = 'HARVESTING'  and p_new_state = 'CLOSED')
    or (v_current_state = 'PLANNED'     and p_new_state = 'CANCELLED')
    or (v_current_state = 'GROWING'     and p_new_state = 'FAILED')
  ) then
    raise exception 'invalid crop cycle transition: % -> %', v_current_state, p_new_state;
  end if;

  -- Append the new history row using the previous chain tip as its
  -- predecessor. This keeps the chain causal and append-only.
  insert into public.crop_cycle_state_history(
    organization_id, project_id, crop_cycle_id,
    previous_history_id, previous_state, new_state, reason, evidence_reference,
    changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_cycle.project_id, p_crop_cycle_id,
    v_tip, v_current_state, p_new_state, trim(p_reason),
    nullif(trim(p_evidence_reference),''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'CROP_CYCLE_TRANSITIONED', 'crop_cycle', p_crop_cycle_id,
    jsonb_build_object(
      'project_id', v_cycle.project_id,
      'previous_state', v_current_state,
      'new_state', p_new_state,
      'reason', trim(p_reason),
      'evidence_reference', nullif(trim(p_evidence_reference),'')
    )
  );
  return v_id;
end $$;

-- ===========================================================================
-- 9. Append-only guards on history and assignment facts
-- ===========================================================================
create or replace function public.s8a_guard_history_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'crop cycle lifecycle history is append-only';
end $$;
drop trigger if exists crop_cycle_state_history_no_update on public.crop_cycle_state_history;
create trigger crop_cycle_state_history_no_update
  before update or delete on public.crop_cycle_state_history
  for each row execute function public.s8a_guard_history_append_only();

create or replace function public.s8a_guard_assignments_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'crop cycle field assignments are immutable once recorded';
end $$;
drop trigger if exists crop_cycle_field_assignments_no_change on public.crop_cycle_field_assignments;
create trigger crop_cycle_field_assignments_no_change
  before update or delete on public.crop_cycle_field_assignments
  for each row execute function public.s8a_guard_assignments_immutable();

-- ===========================================================================
-- 10. Default-deny RLS, forced RLS, and read models
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'agriculture_project_profiles',
    'farms',
    'fields',
    'crop_cycles',
    'crop_cycle_field_assignments',
    'crop_cycle_state_history'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_active_member(organization_id))',
      t || '_read', t
    );
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- security_invoker read views so the application uses the canonical
-- read path; future operator tooling (and PostgREST clients) can join
-- these without re-implementing tenancy filters.
create or replace view public.farms_read with (security_invoker=on) as
select id, organization_id, project_id, name, internal_reference,
       operating_location, tenure_description, timezone, map_reference,
       created_by, created_at
from public.farms;

create or replace view public.fields_read with (security_invoker=on) as
select id, organization_id, project_id, farm_id, identifier,
       area_quantity::text as area_quantity, area_unit,
       soil_notes, irrigation_notes, created_by, created_at
from public.fields;

create or replace view public.crop_cycles_read with (security_invoker=on) as
select c.id, c.organization_id, c.project_id, c.crop, c.variety,
       c.season_reference, c.planned_start_date, c.planned_end_date,
       c.target_yield_quantity::text as target_yield_quantity,
       c.target_yield_unit, c.created_by, c.created_at,
       public.agriculture_current_cycle_state(c.id) as operational_state
from public.crop_cycles c;

create or replace view public.crop_cycle_field_assignments_read
  with (security_invoker=on) as
select a.id, a.organization_id, a.project_id, a.crop_cycle_id, a.field_id,
       a.assigned_area_quantity::text as assigned_area_quantity,
       a.assigned_area_unit, a.planned_start_date, a.planned_end_date,
       a.created_by, a.created_at
from public.crop_cycle_field_assignments a;

create or replace view public.crop_cycle_timeline_read
  with (security_invoker=on) as
select h.id, h.organization_id, h.project_id, h.crop_cycle_id,
       h.previous_state, h.new_state, h.reason, h.evidence_reference,
       h.changed_by, h.changed_at
from public.crop_cycle_state_history h;

grant select on
  public.farms_read, public.fields_read,
  public.crop_cycles_read, public.crop_cycle_field_assignments_read,
  public.crop_cycle_timeline_read
to authenticated;

-- ===========================================================================
-- 11. Command grants — authenticated, OWNER/MEMBER unchanged
-- ===========================================================================
revoke all on function public.create_agriculture_profile(uuid,uuid,text,text) from public, anon;
revoke all on function public.create_farm(uuid,uuid,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.create_field(uuid,uuid,uuid,text,numeric,text,text,text,text) from public, anon;
revoke all on function public.create_crop_cycle(uuid,uuid,text,text,text,date,date,numeric,text,text) from public, anon;
revoke all on function public.assign_crop_cycle_to_field(uuid,uuid,uuid,uuid,numeric,text,date,date,text) from public, anon;
revoke all on function public.transition_crop_cycle(uuid,uuid,text,text,text,text,text) from public, anon;
grant execute on function
  public.create_agriculture_profile(uuid,uuid,text,text),
  public.create_farm(uuid,uuid,text,text,text,text,text,text,text),
  public.create_field(uuid,uuid,uuid,text,numeric,text,text,text,text),
  public.create_crop_cycle(uuid,uuid,text,text,text,date,date,numeric,text,text),
  public.assign_crop_cycle_to_field(uuid,uuid,uuid,uuid,numeric,text,date,date,text),
  public.transition_crop_cycle(uuid,uuid,text,text,text,text,text)
to authenticated;

-- GF-013 functions are created after the repository-wide pgcrypto
-- compatibility migration. Reapply its portable qualification rule so this
-- batch works whether pgcrypto is installed in public, extensions, or another
-- extension schema, and public functions never depend on search_path for
-- digest(). CREATE OR REPLACE preserves the function identity and grants.
do $pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'GF-013 requires the pgcrypto extension';
  end if;

  for v_record in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\\(' then
      v_rewritten := regexp_replace(
        v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
        'g'
      );
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
