-- GF-021 — Livestock movement, quantity rollforward foundation, and weight events.
--
-- Livestock operational state stays EVENT-DERIVED. This migration adds no
-- mutable `current_site_id`, `current_herd_id`, `current_headcount`,
-- `current_weight`, or any other authoritative derived counter. Current
-- placement is resolved from the immutable GF-020 opening placement plus an
-- append-only causal movement chain; current quantity is resolved from the
-- immutable GF-020 opening headcount plus an append-only quantity ledger.
--
-- GF-021 deliberately registers NO quantity event type. The ledger and its
-- rollforward are real and exact, and truthfully report `current = opening`
-- until GF-022 registers BIRTH / MORTALITY / SPLIT / MERGE additively. No
-- event type is fabricated here to make a table look populated.
--
-- No Finance artifact, valuation, IAS 41, COGS, or journal is produced.

-- ---------------------------------------------------------------------------
-- 0. Shared GF-021 helpers.
-- ---------------------------------------------------------------------------

-- Append-only guard with a GF-021-accurate message. The GF-020 guard stays
-- bound to origin/lifecycle facts; movement, quantity, and weight are events.
create function public.gf021_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'livestock movement, quantity, and weight events are append-only';
end $$;

-- Operational events belong to an ACTIVE Cohort. The canonical Livestock
-- lifecycle routes every operational event out of the Active state; a PLANNED
-- Cohort has not entered operations yet.
create function public.gf021_require_active_cohort(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid
) returns void language plpgsql stable security definer
set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1 from public.livestock_cohorts c
    where c.id = p_cohort_id
      and c.organization_id = p_organization_id
      and c.project_id = p_project_id
  ) then
    raise exception 'livestock cohort not found';
  end if;
  if public.livestock_current_cohort_state(p_cohort_id) <> 'ACTIVE' then
    raise exception 'livestock cohort is not active';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. GF-021.A — Movement event: one immutable causal placement chain.
-- ---------------------------------------------------------------------------
create table public.livestock_cohort_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  previous_movement_id uuid,
  effective_at timestamptz not null,
  source_site_id uuid not null,
  source_herd_id uuid not null,
  destination_site_id uuid not null,
  destination_herd_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  moved_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),

  -- A movement that changes neither Site nor Herd is not an operational fact.
  constraint livestock_movement_not_a_no_op check (
    source_site_id <> destination_site_id or source_herd_id <> destination_herd_id
  ),

  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, cohort_id),
  unique (organization_id, idempotency_key),
  -- No two movements may consume the same predecessor placement.
  unique (previous_movement_id),

  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (previous_movement_id, organization_id, project_id, cohort_id)
    references public.livestock_cohort_movements(id, organization_id, project_id, cohort_id)
    on delete restrict,
  foreign key (source_site_id, organization_id, project_id)
    references public.livestock_sites(id, organization_id, project_id) on delete restrict,
  foreign key (destination_site_id, organization_id, project_id)
    references public.livestock_sites(id, organization_id, project_id) on delete restrict,
  foreign key (source_herd_id, organization_id, project_id)
    references public.livestock_herds(id, organization_id, project_id) on delete restrict,
  foreign key (destination_herd_id, organization_id, project_id)
    references public.livestock_herds(id, organization_id, project_id) on delete restrict
);

-- At most one chain root per Cohort: the first movement after the opening fact.
create unique index livestock_movement_one_root_per_cohort
  on public.livestock_cohort_movements(cohort_id)
  where previous_movement_id is null;
create index livestock_movements_cohort_idx
  on public.livestock_cohort_movements(cohort_id, effective_at);
create index livestock_movements_project_idx
  on public.livestock_cohort_movements(project_id);

-- The stated source must equal the actual predecessor placement. This runs on
-- every insert, so privileged/import paths cannot forge a placement successor.
create function public.gf021_validate_movement_link() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_site uuid;
  v_herd uuid;
  v_previous_effective_at timestamptz;
begin
  if new.previous_movement_id is null then
    -- Root movement: the source must be the immutable GF-020 opening placement.
    select p.site_id, c.herd_id into v_site, v_herd
    from public.livestock_cohorts c
    join public.livestock_cohort_initial_placements p
      on (p.cohort_id, p.organization_id, p.project_id) =
         (c.id, c.organization_id, c.project_id)
    where c.id = new.cohort_id
      and c.organization_id = new.organization_id
      and c.project_id = new.project_id;
    if not found then
      raise exception 'livestock opening placement not found';
    end if;
  else
    select m.destination_site_id, m.destination_herd_id, m.effective_at
      into v_site, v_herd, v_previous_effective_at
    from public.livestock_cohort_movements m
    where m.id = new.previous_movement_id
      and m.organization_id = new.organization_id
      and m.project_id = new.project_id
      and m.cohort_id = new.cohort_id;
    if not found then
      raise exception 'livestock movement predecessor must belong to the same cohort';
    end if;
    if new.effective_at < v_previous_effective_at then
      raise exception 'livestock movement effective time precedes its predecessor';
    end if;
  end if;

  if new.source_site_id <> v_site or new.source_herd_id <> v_herd then
    raise exception 'livestock movement source is not the current placement';
  end if;
  return new;
end $$;

create trigger livestock_movements_validate_link
  before insert on public.livestock_cohort_movements
  for each row execute function public.gf021_validate_movement_link();
create trigger livestock_movements_sector_guard
  before insert on public.livestock_cohort_movements
  for each row execute function public.gf020_sector_guard();
create trigger livestock_movements_no_change
  before update or delete on public.livestock_cohort_movements
  for each row execute function public.gf021_immutable();

-- ---------------------------------------------------------------------------
-- 2. GF-021.B — Derived current placement. Never persisted, never LIMIT 1.
-- ---------------------------------------------------------------------------

-- Returns the unique unconsumed movement tip, or NULL when the Cohort has
-- never moved. A Cohort with more than one tip is corrupt: the resolver
-- refuses to guess rather than masking ambiguity with an arbitrary pick.
create function public.livestock_current_placement_movement(p_cohort_id uuid)
returns uuid language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_tip uuid;
  v_count integer;
begin
  select max(m.id::text)::uuid, count(*) into v_tip, v_count
  from public.livestock_cohort_movements m
  where m.cohort_id = p_cohort_id
    and not exists (
      select 1 from public.livestock_cohort_movements child
      where child.cohort_id = m.cohort_id
        and child.previous_movement_id = m.id
    );
  if v_count > 1 then
    raise exception 'invalid livestock placement chain tip count: %', v_count;
  end if;
  return v_tip;
end $$;

create view public.livestock_cohort_current_placement
with (security_invoker=on) as
select
  c.id as cohort_id,
  c.organization_id,
  c.project_id,
  c.cohort_reference,
  coalesce(m.destination_site_id, p.site_id) as current_site_id,
  coalesce(m.destination_herd_id, c.herd_id) as current_herd_id,
  case when m.id is null then 'OPENING' else 'MOVEMENT' end as placement_source,
  coalesce(m.effective_at, p.placed_at) as effective_from,
  m.id as movement_id
from public.livestock_cohorts c
join public.livestock_cohort_initial_placements p
  on (p.cohort_id, p.organization_id, p.project_id) =
     (c.id, c.organization_id, c.project_id)
left join lateral (
  select mv.*
  from public.livestock_cohort_movements mv
  where mv.id = public.livestock_current_placement_movement(c.id)
) m on true;

create view public.livestock_cohort_current_placement_read
with (security_invoker=on) as
select
  cp.cohort_id,
  cp.organization_id,
  cp.project_id,
  cp.cohort_reference,
  cp.current_site_id,
  s.name as current_site_name,
  cp.current_herd_id,
  h.name as current_herd_name,
  h.species,
  h.purpose,
  cp.placement_source,
  cp.effective_from,
  cp.movement_id
from public.livestock_cohort_current_placement cp
join public.livestock_sites s
  on (s.id, s.organization_id, s.project_id) =
     (cp.current_site_id, cp.organization_id, cp.project_id)
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) =
     (cp.current_herd_id, cp.organization_id, cp.project_id);

create view public.livestock_cohort_movements_read
with (security_invoker=on) as
select
  m.id, m.organization_id, m.project_id, m.cohort_id, c.cohort_reference,
  m.previous_movement_id, m.effective_at,
  m.source_site_id, ss.name as source_site_name,
  m.source_herd_id, sh.name as source_herd_name,
  m.destination_site_id, ds.name as destination_site_name,
  m.destination_herd_id, dh.name as destination_herd_name,
  (m.source_site_id <> m.destination_site_id) as site_changed,
  (m.source_herd_id <> m.destination_herd_id) as herd_changed,
  m.reason, m.evidence_reference, m.notes, m.moved_by, m.recorded_at
from public.livestock_cohort_movements m
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) =
     (m.cohort_id, m.organization_id, m.project_id)
join public.livestock_sites ss
  on (ss.id, ss.organization_id, ss.project_id) =
     (m.source_site_id, m.organization_id, m.project_id)
join public.livestock_sites ds
  on (ds.id, ds.organization_id, ds.project_id) =
     (m.destination_site_id, m.organization_id, m.project_id)
join public.livestock_herds sh
  on (sh.id, sh.organization_id, sh.project_id) =
     (m.source_herd_id, m.organization_id, m.project_id)
join public.livestock_herds dh
  on (dh.id, dh.organization_id, dh.project_id) =
     (m.destination_herd_id, m.organization_id, m.project_id);

-- ---------------------------------------------------------------------------
-- 3. GF-021.C — Quantity rollforward foundation (architecture only).
-- ---------------------------------------------------------------------------

-- Registry of quantity-changing event classes. GF-021 registers none, because
-- GF-021 implements none. GF-022 inserts its classes here additively; no
-- destructive migration of the ledger is required to introduce them.
create table public.livestock_quantity_event_types (
  code text primary key check (code = upper(trim(code)) and char_length(code) between 3 and 40),
  direction smallint not null check (direction in (-1, 1)),
  label_ar text not null check (char_length(trim(label_ar)) between 2 and 120),
  introduced_in text not null check (char_length(trim(introduced_in)) between 2 and 20)
);

-- Exact integer headcount ledger. `quantity` is an unsigned magnitude; the
-- registered class supplies the sign, so no row can silently invert its effect.
create table public.livestock_quantity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  event_type text not null references public.livestock_quantity_event_types(code)
    on delete restrict,
  quantity integer not null check (quantity > 0),
  effective_at timestamptz not null,
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),

  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, cohort_id),
  unique (organization_id, idempotency_key),

  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_quantity_events_cohort_idx
  on public.livestock_quantity_events(cohort_id, effective_at);
create index livestock_quantity_events_project_idx
  on public.livestock_quantity_events(project_id);

create trigger livestock_quantity_events_sector_guard
  before insert on public.livestock_quantity_events
  for each row execute function public.gf020_sector_guard();
create trigger livestock_quantity_events_no_change
  before update or delete on public.livestock_quantity_events
  for each row execute function public.gf021_immutable();

-- Exact integer rollforward. No floating point anywhere on this path.
create view public.livestock_cohort_quantity_rollforward
with (security_invoker=on) as
select
  c.id as cohort_id,
  c.organization_id,
  c.project_id,
  c.cohort_reference,
  c.opening_headcount,
  coalesce(e.quantity_increase, 0)::integer as quantity_increase,
  coalesce(e.quantity_decrease, 0)::integer as quantity_decrease,
  (c.opening_headcount
     + coalesce(e.quantity_increase, 0)
     - coalesce(e.quantity_decrease, 0))::integer as current_quantity
from public.livestock_cohorts c
left join lateral (
  select
    sum(case when t.direction = 1 then q.quantity else 0 end) as quantity_increase,
    sum(case when t.direction = -1 then q.quantity else 0 end) as quantity_decrease
  from public.livestock_quantity_events q
  join public.livestock_quantity_event_types t on t.code = q.event_type
  where q.cohort_id = c.id
) e on true;

-- Command-side resolver. Rejects an impossible negative derived balance
-- instead of returning it, so no command can build on corrupt state.
create function public.livestock_current_cohort_quantity(p_cohort_id uuid)
returns integer language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_quantity integer;
begin
  select r.current_quantity into v_quantity
  from public.livestock_cohort_quantity_rollforward r
  where r.cohort_id = p_cohort_id;
  if v_quantity is null then
    raise exception 'livestock cohort not found';
  end if;
  if v_quantity < 0 then
    raise exception 'invalid negative livestock derived quantity: %', v_quantity;
  end if;
  return v_quantity;
end $$;

-- ---------------------------------------------------------------------------
-- 4. GF-021.D — WeightEvent: an immutable measurement, not a Cohort property.
-- ---------------------------------------------------------------------------
create table public.livestock_weight_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  effective_at timestamptz not null,
  method text not null check (method in (
    'INDIVIDUAL_MEASURED', 'COHORT_TOTAL', 'SAMPLED_AVERAGE', 'ESTIMATED'
  )),
  weight_value numeric(18,3) not null check (weight_value > 0),
  weight_unit text not null check (weight_unit = 'KG'),
  -- INDIVIDUAL_MEASURED only: how many animals the measured total covers.
  measured_animal_count integer check (measured_animal_count is null or measured_animal_count > 0),
  -- SAMPLED_AVERAGE only: how many animals the average was measured across.
  sample_size integer check (sample_size is null or sample_size > 0),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),

  -- Method-specific required and forbidden metadata, enforced by the database
  -- so no privileged path can record a sampled average without a sample size
  -- or dress an estimate up as a measurement.
  constraint livestock_weight_method_metadata check (
    case method
      when 'INDIVIDUAL_MEASURED' then measured_animal_count is not null and sample_size is null
      when 'COHORT_TOTAL' then measured_animal_count is null and sample_size is null
      when 'SAMPLED_AVERAGE' then
        sample_size is not null and measured_animal_count is null
        and evidence_reference is not null
      when 'ESTIMATED' then measured_animal_count is null and sample_size is null
      else false
    end
  ),

  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),

  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_weight_events_cohort_idx
  on public.livestock_weight_events(cohort_id, effective_at);
create index livestock_weight_events_project_idx
  on public.livestock_weight_events(project_id);

-- A measured or sampled population can never exceed the derived headcount.
create function public.gf021_validate_weight_population() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_current integer := public.livestock_current_cohort_quantity(new.cohort_id);
begin
  if new.measured_animal_count is not null and new.measured_animal_count > v_current then
    raise exception 'livestock measured animal count exceeds current derived quantity';
  end if;
  if new.sample_size is not null and new.sample_size > v_current then
    raise exception 'livestock sample size exceeds current derived quantity';
  end if;
  return new;
end $$;

create trigger livestock_weight_events_population_guard
  before insert on public.livestock_weight_events
  for each row execute function public.gf021_validate_weight_population();
create trigger livestock_weight_events_sector_guard
  before insert on public.livestock_weight_events
  for each row execute function public.gf020_sector_guard();
create trigger livestock_weight_events_no_change
  before update or delete on public.livestock_weight_events
  for each row execute function public.gf021_immutable();

-- The read model states what the stored number MEANS per method, so a sampled
-- average is never presented as a measured cohort total.
create view public.livestock_weight_events_read
with (security_invoker=on) as
select
  w.id, w.organization_id, w.project_id, w.cohort_id, c.cohort_reference,
  w.effective_at, w.method,
  w.weight_value::text as weight_value,
  w.weight_unit,
  case w.method
    when 'INDIVIDUAL_MEASURED' then 'TOTAL_OF_MEASURED_ANIMALS'
    when 'COHORT_TOTAL' then 'COHORT_TOTAL_MEASURED'
    when 'SAMPLED_AVERAGE' then 'AVERAGE_PER_ANIMAL_SAMPLED'
    when 'ESTIMATED' then 'COHORT_TOTAL_ESTIMATED'
  end as value_meaning,
  (w.method = 'ESTIMATED') as is_estimate,
  w.measured_animal_count, w.sample_size,
  w.evidence_reference, w.notes, w.recorded_by, w.recorded_at
from public.livestock_weight_events w
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) =
     (w.cohort_id, w.organization_id, w.project_id);

-- ---------------------------------------------------------------------------
-- 5. Server-authoritative commands.
-- ---------------------------------------------------------------------------
create function public.record_livestock_movement(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_source_site_id uuid,
  p_source_herd_id uuid,
  p_destination_site_id uuid,
  p_destination_herd_id uuid,
  p_effective_at timestamptz,
  p_reason text,
  p_evidence_reference text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_row record;
  v_id uuid;
  v_tip uuid;
  v_current record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|' ||
    p_source_site_id::text || '|' || p_source_herd_id::text || '|' ||
    p_destination_site_id::text || '|' || p_destination_herd_id::text || '|' ||
    coalesce(p_effective_at::text, '') || '|' || trim(coalesce(p_reason, '')) || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-movement:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_cohort_movements
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);

  -- Serialize every placement command for this Cohort so two operators cannot
  -- read the same current placement and both append a successor to it.
  perform pg_advisory_xact_lock(hashtextextended(
    p_cohort_id::text || ':livestock-placement', 0
  ));

  if p_effective_at is null then raise exception 'invalid livestock movement effective time'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid livestock movement reason';
  end if;
  if p_destination_site_id = p_source_site_id
     and p_destination_herd_id = p_source_herd_id then
    raise exception 'livestock movement must change site or herd';
  end if;
  if not exists (
    select 1 from public.livestock_sites
    where id = p_destination_site_id and organization_id = p_organization_id
      and project_id = p_project_id
  ) then raise exception 'livestock site not found'; end if;
  if not exists (
    select 1 from public.livestock_herds
    where id = p_destination_herd_id and organization_id = p_organization_id
      and project_id = p_project_id
  ) then raise exception 'livestock herd not found'; end if;

  -- The browser never supplies authoritative placement: the client-declared
  -- source is compared against the server-derived current placement.
  select * into v_current from public.livestock_cohort_current_placement
  where cohort_id = p_cohort_id;
  if not found then raise exception 'livestock opening placement not found'; end if;
  if v_current.current_site_id <> p_source_site_id
     or v_current.current_herd_id <> p_source_herd_id then
    raise exception 'livestock movement source is not the current placement';
  end if;

  v_tip := public.livestock_current_placement_movement(p_cohort_id);

  insert into public.livestock_cohort_movements(
    organization_id, project_id, cohort_id, previous_movement_id, effective_at,
    source_site_id, source_herd_id, destination_site_id, destination_herd_id,
    reason, evidence_reference, notes, moved_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, v_tip, p_effective_at,
    p_source_site_id, p_source_herd_id, p_destination_site_id, p_destination_herd_id,
    trim(p_reason), nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_COHORT_MOVED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object(
      'project_id', p_project_id, 'movement_id', v_id,
      'source_site_id', p_source_site_id, 'source_herd_id', p_source_herd_id,
      'destination_site_id', p_destination_site_id,
      'destination_herd_id', p_destination_herd_id,
      'previous_movement_id', v_tip
    )
  );
  return v_id;
end $$;

create function public.record_livestock_weight_event(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_effective_at timestamptz,
  p_method text,
  p_weight_value numeric,
  p_weight_unit text,
  p_measured_animal_count integer,
  p_sample_size integer,
  p_evidence_reference text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_row record;
  v_id uuid;
  v_method text := upper(trim(coalesce(p_method, '')));
  v_unit text := upper(trim(coalesce(p_weight_unit, '')));
  v_current integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|' ||
    coalesce(p_effective_at::text, '') || '|' || v_method || '|' ||
    coalesce(p_weight_value::text, '') || '|' || v_unit || '|' ||
    coalesce(p_measured_animal_count::text, '') || '|' || coalesce(p_sample_size::text, '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-weight:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_weight_events
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);

  if p_effective_at is null then raise exception 'invalid livestock weight effective time'; end if;
  if v_method not in ('INDIVIDUAL_MEASURED','COHORT_TOTAL','SAMPLED_AVERAGE','ESTIMATED') then
    raise exception 'invalid livestock weight method';
  end if;
  if p_weight_value is null or p_weight_value <= 0 then
    raise exception 'invalid livestock weight value';
  end if;
  if v_unit <> 'KG' then raise exception 'invalid livestock weight unit'; end if;

  if v_method = 'INDIVIDUAL_MEASURED' then
    if p_measured_animal_count is null or p_measured_animal_count <= 0 then
      raise exception 'livestock individual measurement requires a measured animal count';
    end if;
    if p_sample_size is not null then
      raise exception 'livestock individual measurement does not take a sample size';
    end if;
  elsif v_method = 'SAMPLED_AVERAGE' then
    if p_sample_size is null or p_sample_size <= 0 then
      raise exception 'livestock sampled average requires a sample size';
    end if;
    if p_measured_animal_count is not null then
      raise exception 'livestock sampled average does not take a measured animal count';
    end if;
    if p_evidence_reference is null or char_length(trim(p_evidence_reference)) < 2 then
      raise exception 'livestock sampled average requires an evidence reference';
    end if;
  else
    if p_measured_animal_count is not null or p_sample_size is not null then
      raise exception 'livestock weight method does not take population metadata';
    end if;
  end if;

  -- Serialize against concurrent quantity change so the population check is
  -- taken against a stable derived headcount.
  perform pg_advisory_xact_lock(hashtextextended(
    p_cohort_id::text || ':livestock-quantity', 0
  ));
  v_current := public.livestock_current_cohort_quantity(p_cohort_id);
  if p_measured_animal_count is not null and p_measured_animal_count > v_current then
    raise exception 'livestock measured animal count exceeds current derived quantity';
  end if;
  if p_sample_size is not null and p_sample_size > v_current then
    raise exception 'livestock sample size exceeds current derived quantity';
  end if;

  insert into public.livestock_weight_events(
    organization_id, project_id, cohort_id, effective_at, method,
    weight_value, weight_unit, measured_animal_count, sample_size,
    evidence_reference, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, p_effective_at, v_method,
    p_weight_value, v_unit, p_measured_animal_count, p_sample_size,
    nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_WEIGHT_RECORDED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object(
      'project_id', p_project_id, 'weight_event_id', v_id, 'method', v_method,
      'weight_unit', v_unit, 'sample_size', p_sample_size,
      'measured_animal_count', p_measured_animal_count
    )
  );
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Default-deny security: RLS, FORCE RLS, and no authenticated table DML.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'livestock_cohort_movements',
    'livestock_quantity_events',
    'livestock_weight_events'
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
end $$;

-- The event-class registry is non-tenant reference data: readable, never
-- writable from the browser.
alter table public.livestock_quantity_event_types enable row level security;
alter table public.livestock_quantity_event_types force row level security;
create policy livestock_quantity_event_types_read
  on public.livestock_quantity_event_types for select to authenticated using (true);
revoke all on public.livestock_quantity_event_types from public, anon, authenticated;
grant select on public.livestock_quantity_event_types to authenticated;

revoke all on
  public.livestock_cohort_current_placement,
  public.livestock_cohort_current_placement_read,
  public.livestock_cohort_movements_read,
  public.livestock_cohort_quantity_rollforward,
  public.livestock_weight_events_read
  from public, anon;
grant select on
  public.livestock_cohort_current_placement,
  public.livestock_cohort_current_placement_read,
  public.livestock_cohort_movements_read,
  public.livestock_cohort_quantity_rollforward,
  public.livestock_weight_events_read
  to authenticated;

revoke all on function
  public.gf021_immutable(),
  public.gf021_require_active_cohort(uuid,uuid,uuid),
  public.gf021_validate_movement_link(),
  public.gf021_validate_weight_population()
  from public, anon, authenticated;

revoke all on function
  public.livestock_current_placement_movement(uuid),
  public.livestock_current_cohort_quantity(uuid)
  from public, anon;
grant execute on function
  public.livestock_current_placement_movement(uuid),
  public.livestock_current_cohort_quantity(uuid)
  to authenticated;

revoke all on function
  public.record_livestock_movement(uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text)
  from public, anon;
grant execute on function
  public.record_livestock_movement(uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text)
  to authenticated;
