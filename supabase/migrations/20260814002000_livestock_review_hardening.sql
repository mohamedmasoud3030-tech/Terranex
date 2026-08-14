-- GF-022 review hardening — forward-only temporal, species, operation-shape,
-- lifecycle-boundary, weight-quality, and mortality-disposal invariants.
--
-- This migration deliberately does not edit or rebuild an applied ledger table.
-- It extends the GF-022 schema and replaces resolver/command function bodies in
-- place so existing data and function signatures remain forward-compatible.

-- ---------------------------------------------------------------------------
-- 1. Canonical metadata for mortality disposal and qualitative weight quality.
-- ---------------------------------------------------------------------------
alter table public.livestock_quantity_event_types
  add column if not exists requires_disposal boolean not null default false;
update public.livestock_quantity_event_types
   set requires_disposal = true
 where code = 'MORTALITY';

alter table public.livestock_quantity_events
  add column if not exists disposal_method text
    check (disposal_method is null or disposal_method in (
      'BURIAL', 'INCINERATION', 'RENDERING', 'COMPOSTING', 'OTHER', 'PENDING'
    ));

-- This is a qualitative operational confidence/quality level, not a fabricated
-- confidence interval. The default keeps the old GF-021 command arity truthful:
-- existing measurements are explicitly unassessed until an operator records a
-- quality level. Sampled averages display this value beside their sample size.
alter table public.livestock_weight_events
  add column if not exists confidence_level text not null default 'UNASSESSED'
    check (confidence_level in ('UNASSESSED', 'LOW', 'MEDIUM', 'HIGH'));

create or replace function public.gf022_validate_quantity_event() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_type record;
begin
  select * into v_type
    from public.livestock_quantity_event_types
   where code = new.event_type;
  if not found then
    raise exception 'unknown livestock quantity event type';
  end if;

  -- Legacy mortality callers did not have a disposal argument. PENDING is an
  -- explicit constrained state, never an omitted/unmodeled disposal method.
  if v_type.requires_disposal and new.disposal_method is null then
    new.disposal_method := 'PENDING';
  end if;

  if v_type.requires_operation and new.operation_id is null then
    raise exception 'livestock % requires an operation identity', new.event_type;
  end if;
  if not v_type.requires_operation and new.operation_id is not null then
    raise exception 'livestock % must not carry an operation identity', new.event_type;
  end if;
  if v_type.requires_cause and new.cause_category is null then
    raise exception 'livestock % requires a cause category', new.event_type;
  end if;
  if not v_type.requires_cause and new.cause_category is not null then
    raise exception 'livestock % must not carry a cause category', new.event_type;
  end if;
  if v_type.requires_disposal and new.disposal_method is null then
    raise exception 'livestock mortality requires a disposal method';
  end if;
  if not v_type.requires_disposal and new.disposal_method is not null then
    raise exception 'livestock % must not carry a disposal method', new.event_type;
  end if;
  if new.cause_detail is not null and new.cause_category is null then
    raise exception 'livestock cause detail requires a cause category';
  end if;

  if new.operation_id is not null then
    if not exists (
      select 1 from public.livestock_quantity_operations o
       where o.id = new.operation_id
         and o.organization_id = new.organization_id
         and o.project_id = new.project_id
         and o.operation_type = split_part(new.event_type, '_', 1)
    ) then
      raise exception 'livestock quantity operation does not match the event leg';
    end if;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 2. One authoritative quantity rule: opening + event buckets as of a time.
-- ---------------------------------------------------------------------------
-- `current` always means as of current_timestamp. Commands with an effective
-- time validate against that event's as-of balance. Events sharing one
-- effective_at form one atomic bucket; no recorded_at/UUID order is business
-- truth. A destructive event can use quantity available at the same timestamp,
-- but never quantity introduced by a later timestamp.
create or replace function public.livestock_cohort_quantity_as_of(
  p_cohort_id uuid,
  p_as_of_at timestamptz
) returns integer language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_opening bigint;
  v_delta bigint;
  v_quantity bigint;
begin
  if p_as_of_at is null then
    raise exception 'livestock quantity as-of time is required';
  end if;
  select c.opening_headcount::bigint
    into v_opening
    from public.livestock_cohorts c
   where c.id = p_cohort_id;
  if not found then
    raise exception 'livestock cohort not found';
  end if;

  select coalesce(sum(t.direction::bigint * q.quantity::bigint), 0::bigint)
    into v_delta
    from public.livestock_quantity_events q
    join public.livestock_quantity_event_types t on t.code = q.event_type
   where q.cohort_id = p_cohort_id
     and q.effective_at <= p_as_of_at;
  v_quantity := v_opening + v_delta;
  if v_quantity < 0 then
    raise exception 'invalid negative livestock derived quantity as of %: %', p_as_of_at, v_quantity;
  end if;
  if v_quantity > 2147483647 then
    raise exception 'livestock derived quantity exceeds integer range';
  end if;
  return v_quantity::integer;
end $$;

create or replace function public.livestock_current_cohort_quantity(p_cohort_id uuid)
returns integer language sql stable security invoker
set search_path=pg_catalog,public as $$
  select public.livestock_cohort_quantity_as_of($1, current_timestamp)
$$;

drop view public.livestock_cohort_quantity_rollforward;
create view public.livestock_cohort_quantity_rollforward
with (security_invoker=on) as
select
  c.id as cohort_id,
  c.organization_id,
  c.project_id,
  c.cohort_reference,
  c.opening_headcount,
  coalesce(e.births, 0)::integer as births,
  coalesce(e.mortality, 0)::integer as mortality,
  coalesce(e.split_in, 0)::integer as split_in,
  coalesce(e.split_out, 0)::integer as split_out,
  coalesce(e.merge_in, 0)::integer as merge_in,
  coalesce(e.merge_out, 0)::integer as merge_out,
  coalesce(e.quantity_increase, 0)::integer as quantity_increase,
  coalesce(e.quantity_decrease, 0)::integer as quantity_decrease,
  public.livestock_cohort_quantity_as_of(c.id, current_timestamp) as current_quantity
from public.livestock_cohorts c
left join lateral (
  select
    sum(case when q.event_type = 'BIRTH'     then q.quantity else 0 end) as births,
    sum(case when q.event_type = 'MORTALITY' then q.quantity else 0 end) as mortality,
    sum(case when q.event_type = 'SPLIT_IN'  then q.quantity else 0 end) as split_in,
    sum(case when q.event_type = 'SPLIT_OUT' then q.quantity else 0 end) as split_out,
    sum(case when q.event_type = 'MERGE_IN'  then q.quantity else 0 end) as merge_in,
    sum(case when q.event_type = 'MERGE_OUT' then q.quantity else 0 end) as merge_out,
    sum(case when t.direction = 1  then q.quantity else 0 end) as quantity_increase,
    sum(case when t.direction = -1 then q.quantity else 0 end) as quantity_decrease
  from public.livestock_quantity_events q
  join public.livestock_quantity_event_types t on t.code = q.event_type
  where q.cohort_id = c.id
    and q.effective_at <= current_timestamp
) e on true;

-- The event and lineage logs retain scheduled facts, but expose whether each
-- fact is part of the current as-of balance so the UI cannot call it current.
drop view public.livestock_quantity_events_read;
create view public.livestock_quantity_events_read
with (security_invoker=on) as
select
  q.id, q.organization_id, q.project_id, q.cohort_id, c.cohort_reference,
  q.event_type, t.label_ar as event_label, t.direction,
  q.quantity, (t.direction * q.quantity)::integer as signed_quantity,
  q.effective_at, (q.effective_at <= current_timestamp) as is_effective_as_of_now,
  q.operation_id, q.cause_category, q.cause_detail, q.disposal_method,
  q.evidence_reference, q.notes, q.recorded_by, q.recorded_at
from public.livestock_quantity_events q
join public.livestock_quantity_event_types t on t.code = q.event_type
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) =
     (q.cohort_id, q.organization_id, q.project_id);

drop view public.livestock_cohort_lineage_read;
create view public.livestock_cohort_lineage_read
with (security_invoker=on) as
select
  l.id, l.organization_id, l.project_id, l.operation_id,
  o.operation_type, o.effective_at, (o.effective_at <= current_timestamp) as is_effective_as_of_now,
  o.reason, o.evidence_reference,
  l.source_cohort_id, sc.cohort_reference as source_cohort_reference,
  l.destination_cohort_id, dc.cohort_reference as destination_cohort_reference,
  l.quantity, o.performed_by, l.created_at
from public.livestock_cohort_lineage l
join public.livestock_quantity_operations o
  on (o.id, o.organization_id, o.project_id) =
     (l.operation_id, l.organization_id, l.project_id)
join public.livestock_cohorts sc
  on (sc.id, sc.organization_id, sc.project_id) =
     (l.source_cohort_id, l.organization_id, l.project_id)
join public.livestock_cohorts dc
  on (dc.id, dc.organization_id, dc.project_id) =
     (l.destination_cohort_id, l.organization_id, l.project_id);

-- ---------------------------------------------------------------------------
-- 3. Temporal non-negative invariant and exact operation shape.
-- ---------------------------------------------------------------------------
create or replace function public.gf022_validate_non_negative_quantity() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_balance bigint;
  v_delta bigint;
  v_bucket record;
begin
  -- The row lock also serializes privileged/import inserts that do not use a
  -- command advisory lock. Commands take the same logical lock before reading.
  perform pg_advisory_xact_lock(hashtextextended(
    new.cohort_id::text || ':livestock-quantity', 0
  ));
  select c.opening_headcount::bigint into v_balance
    from public.livestock_cohorts c
   where c.id = new.cohort_id
   for update;
  if v_balance is null then
    raise exception 'livestock cohort not found';
  end if;

  for v_bucket in
    select q.effective_at,
           coalesce(sum(t.direction::bigint * q.quantity::bigint), 0::bigint) as delta
      from public.livestock_quantity_events q
      join public.livestock_quantity_event_types t on t.code = q.event_type
     where q.cohort_id = new.cohort_id
     group by q.effective_at
     order by q.effective_at
  loop
    v_balance := v_balance + v_bucket.delta;
    if v_balance < 0 then
      raise exception 'livestock as-of quantity cannot go below zero at % (%)',
        v_bucket.effective_at, v_balance;
    end if;
  end loop;
  return null;
end $$;

create or replace function public.gf022_validate_operation_conservation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_operation_id uuid;
  v_operation_type text;
  v_operation_effective_at timestamptz;
  v_event_count integer;
  v_out_count integer;
  v_in_count integer;
  v_distinct_source_count integer;
  v_lineage_count integer;
  v_matching_lineage_count integer;
  v_out_cohort uuid;
  v_in_cohort uuid;
  v_out_quantity bigint;
  v_in_quantity bigint;
  v_out_effective_at timestamptz;
  v_in_effective_at timestamptz;
  v_out_total bigint;
begin
  if tg_table_name = 'livestock_quantity_operations' then
    v_operation_id := new.id;
  else
    v_operation_id := new.operation_id;
  end if;
  if v_operation_id is null then
    return null;
  end if;

  select o.operation_type, o.effective_at
    into v_operation_type, v_operation_effective_at
    from public.livestock_quantity_operations o
   where o.id = v_operation_id;
  if not found then
    raise exception 'livestock quantity operation not found';
  end if;

  select count(*)::integer,
         count(*) filter (where q.event_type in ('SPLIT_OUT','MERGE_OUT'))::integer,
         count(*) filter (where q.event_type in ('SPLIT_IN','MERGE_IN'))::integer
    into v_event_count, v_out_count, v_in_count
    from public.livestock_quantity_events q
   where q.operation_id = v_operation_id;

  if v_event_count < 2 then
    -- Preserve the original incomplete-operation contract while making the
    -- stronger shape checks below explicit for complete-looking forgeries.
    raise exception 'livestock quantity operation requires both an outgoing and an incoming leg';
  end if;
  if exists (
    select 1 from public.livestock_quantity_events q
     where q.operation_id = v_operation_id
       and q.effective_at is distinct from v_operation_effective_at
  ) then
    raise exception 'livestock operation effective time does not match its legs';
  end if;

  select count(*)::integer into v_lineage_count
    from public.livestock_cohort_lineage l
   where l.operation_id = v_operation_id;

  if v_operation_type = 'SPLIT' then
    if v_out_count <> 1 or v_in_count <> 1 or v_event_count <> 2 then
      raise exception 'livestock SPLIT operation requires exactly one SPLIT_OUT leg and one SPLIT_IN leg';
    end if;
    if v_lineage_count <> 1 then
      raise exception 'livestock SPLIT operation requires exactly one lineage row';
    end if;

    select q.cohort_id, q.quantity, q.effective_at
      into v_out_cohort, v_out_quantity, v_out_effective_at
      from public.livestock_quantity_events q
     where q.operation_id = v_operation_id and q.event_type = 'SPLIT_OUT';
    select q.cohort_id, q.quantity, q.effective_at
      into v_in_cohort, v_in_quantity, v_in_effective_at
      from public.livestock_quantity_events q
     where q.operation_id = v_operation_id and q.event_type = 'SPLIT_IN';

    if v_out_cohort = v_in_cohort then
      raise exception 'livestock SPLIT operation source and destination must be distinct';
    end if;
    if v_out_quantity <> v_in_quantity then
      raise exception 'livestock SPLIT operation leg quantities must match';
    end if;
    if v_out_effective_at is distinct from v_operation_effective_at
       or v_in_effective_at is distinct from v_operation_effective_at then
      raise exception 'livestock operation effective time does not match its legs';
    end if;
    select count(*)::integer into v_matching_lineage_count
      from public.livestock_cohort_lineage l
      join public.livestock_quantity_events q
        on q.operation_id = l.operation_id
       and q.event_type = 'SPLIT_OUT'
       and q.cohort_id = l.source_cohort_id
       and q.quantity = l.quantity
      join public.livestock_quantity_events i
        on i.operation_id = l.operation_id
       and i.event_type = 'SPLIT_IN'
       and i.cohort_id = l.destination_cohort_id
       and i.quantity = l.quantity
     where l.operation_id = v_operation_id;
    if v_matching_lineage_count <> 1 then
      raise exception 'livestock SPLIT lineage does not match its legs';
    end if;
  elsif v_operation_type = 'MERGE' then
    if v_out_count < 2 or v_in_count <> 1 or v_event_count <> v_out_count + 1 then
      raise exception 'livestock MERGE operation requires at least two MERGE_OUT legs and exactly one MERGE_IN leg';
    end if;
    select count(distinct q.cohort_id)::integer into v_distinct_source_count
      from public.livestock_quantity_events q
     where q.operation_id = v_operation_id and q.event_type = 'MERGE_OUT';
    if v_distinct_source_count <> v_out_count then
      raise exception 'livestock MERGE operation requires distinct source Cohorts';
    end if;
    select q.cohort_id, q.quantity, q.effective_at
      into v_in_cohort, v_in_quantity, v_in_effective_at
      from public.livestock_quantity_events q
     where q.operation_id = v_operation_id and q.event_type = 'MERGE_IN';
    if exists (
      select 1 from public.livestock_quantity_events q
       where q.operation_id = v_operation_id
         and q.event_type = 'MERGE_OUT'
         and q.cohort_id = v_in_cohort
    ) then
      raise exception 'livestock MERGE destination must differ from every source';
    end if;
    select coalesce(sum(q.quantity::bigint), 0::bigint)
      into v_out_total
      from public.livestock_quantity_events q
     where q.operation_id = v_operation_id and q.event_type = 'MERGE_OUT';
    if v_out_total <> v_in_quantity then
      raise exception 'livestock MERGE_IN quantity must equal the source total';
    end if;
    if v_in_effective_at is distinct from v_operation_effective_at then
      raise exception 'livestock operation effective time does not match its legs';
    end if;
    select count(*)::integer into v_matching_lineage_count
      from public.livestock_cohort_lineage l
      join public.livestock_quantity_events q
        on q.operation_id = l.operation_id
       and q.event_type = 'MERGE_OUT'
       and q.cohort_id = l.source_cohort_id
       and q.quantity = l.quantity
      join public.livestock_quantity_events i
        on i.operation_id = l.operation_id
       and i.event_type = 'MERGE_IN'
       and i.cohort_id = l.destination_cohort_id
     where l.operation_id = v_operation_id
       and i.quantity = v_in_quantity;
    if v_lineage_count <> v_out_count or v_matching_lineage_count <> v_out_count then
      raise exception 'livestock MERGE lineage does not match its legs';
    end if;
  else
    raise exception 'unknown livestock quantity operation type';
  end if;

  return null;
end $$;

-- A lineage row is also a privileged/import entry point; it cannot rely on an
-- operation/event trigger having been queued by the same writer.
create constraint trigger livestock_lineage_shape_validate
  after insert on public.livestock_cohort_lineage
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_conservation();

-- ---------------------------------------------------------------------------
-- 4. Species continuity at the database invariant layer.
-- ---------------------------------------------------------------------------
create function public.gf022_validate_cohort_species() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_species text;
begin
  select h.species into v_species
    from public.livestock_herds h
   where h.id = new.herd_id
     and h.organization_id = new.organization_id
     and h.project_id = new.project_id;
  if not found then
    raise exception 'livestock cohort herd not found';
  end if;
  return new;
end $$;

create trigger livestock_cohorts_species_guard
  before insert on public.livestock_cohorts
  for each row execute function public.gf022_validate_cohort_species();

create function public.gf022_validate_herd_species_update() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.species is distinct from old.species
     and exists (
       select 1 from public.livestock_cohorts c
        where c.herd_id = old.id
          and c.organization_id = old.organization_id
          and c.project_id = old.project_id
     ) then
    raise exception 'livestock Herd species cannot change while Cohorts reference it';
  end if;
  return new;
end $$;

create trigger livestock_herds_species_update_guard
  before update of species on public.livestock_herds
  for each row execute function public.gf022_validate_herd_species_update();

create function public.gf022_validate_movement_species() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_cohort_species text;
  v_source_species text;
  v_destination_species text;
begin
  select cohort_herd.species, source_herd.species, destination_herd.species
    into v_cohort_species, v_source_species, v_destination_species
    from public.livestock_cohorts c
    join public.livestock_herds cohort_herd
      on (cohort_herd.id, cohort_herd.organization_id, cohort_herd.project_id) =
         (c.herd_id, c.organization_id, c.project_id)
    join public.livestock_herds source_herd
      on (source_herd.id, source_herd.organization_id, source_herd.project_id) =
         (new.source_herd_id, new.organization_id, new.project_id)
    join public.livestock_herds destination_herd
      on (destination_herd.id, destination_herd.organization_id, destination_herd.project_id) =
         (new.destination_herd_id, new.organization_id, new.project_id)
   where c.id = new.cohort_id
     and c.organization_id = new.organization_id
     and c.project_id = new.project_id;
  if not found then
    raise exception 'livestock movement species context not found';
  end if;
  if v_source_species is distinct from v_cohort_species
     or v_destination_species is distinct from v_cohort_species then
    raise exception 'livestock movement Herd species must match the Cohort species';
  end if;
  return new;
end $$;

create trigger livestock_movements_species_guard
  before insert on public.livestock_cohort_movements
  for each row execute function public.gf022_validate_movement_species();

create function public.gf022_validate_lineage_species() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_source_species text;
  v_destination_species text;
begin
  select source_herd.species, destination_herd.species
    into v_source_species, v_destination_species
    from public.livestock_cohorts source_cohort
    join public.livestock_herds source_herd
      on (source_herd.id, source_herd.organization_id, source_herd.project_id) =
         (source_cohort.herd_id, source_cohort.organization_id, source_cohort.project_id)
    join public.livestock_cohorts destination_cohort
      on (destination_cohort.id, destination_cohort.organization_id, destination_cohort.project_id) =
         (new.destination_cohort_id, new.organization_id, new.project_id)
    join public.livestock_herds destination_herd
      on (destination_herd.id, destination_herd.organization_id, destination_herd.project_id) =
         (destination_cohort.herd_id, destination_cohort.organization_id, destination_cohort.project_id)
   where source_cohort.id = new.source_cohort_id
     and source_cohort.organization_id = new.organization_id
     and source_cohort.project_id = new.project_id;
  if not found then
    raise exception 'livestock lineage species context not found';
  end if;
  if v_source_species is distinct from v_destination_species then
    raise exception 'livestock operation Cohorts require a compatible species';
  end if;
  return new;
end $$;

create trigger livestock_lineage_species_guard
  before insert on public.livestock_cohort_lineage
  for each row execute function public.gf022_validate_lineage_species();

-- ---------------------------------------------------------------------------
-- 5. Weight population is checked at the weight's effective time.
-- ---------------------------------------------------------------------------
create or replace function public.gf021_validate_weight_population() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_current integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    new.cohort_id::text || ':livestock-quantity', 0
  ));
  v_current := public.livestock_cohort_quantity_as_of(new.cohort_id, new.effective_at);
  if v_current <= 0 then
    raise exception 'livestock cohort has no positive quantity at the weight effective time';
  end if;
  if new.measured_animal_count is not null and new.measured_animal_count > v_current then
    raise exception 'livestock measured animal count exceeds current derived quantity';
  end if;
  if new.sample_size is not null and new.sample_size > v_current then
    raise exception 'livestock sample size exceeds current derived quantity';
  end if;
  return new;
end $$;

drop view public.livestock_weight_events_read;
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
  w.confidence_level,
  w.evidence_reference, w.notes, w.recorded_by, w.recorded_at
from public.livestock_weight_events w
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) =
     (w.cohort_id, w.organization_id, w.project_id);

-- ---------------------------------------------------------------------------
-- 6. Replace command bodies with event-time as-of validation.
-- ---------------------------------------------------------------------------
create or replace function public.record_livestock_birth(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_quantity integer,
  p_effective_at timestamptz,
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
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|BIRTH|' ||
    coalesce(p_quantity::text, '') || '|' || coalesce(p_effective_at::text, '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-quantity:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_quantity_events
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid livestock quantity';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock event effective time'; end if;
  perform public.gf022_lock_cohort_quantity(p_cohort_id);

  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    evidence_reference, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, 'BIRTH', p_quantity, p_effective_at,
    nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_BIRTH_RECORDED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object('project_id', p_project_id, 'quantity_event_id', v_id,
                       'quantity', p_quantity)
  );
  return v_id;
end $$;
create or replace function public.record_livestock_mortality(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_quantity integer,
  p_effective_at timestamptz,
  p_cause_category text,
  p_cause_detail text,
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
  v_cause text := upper(trim(coalesce(p_cause_category, '')));
  v_current integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|MORTALITY|' ||
    coalesce(p_quantity::text, '') || '|' || coalesce(p_effective_at::text, '') || '|' ||
    v_cause || '|' || coalesce(trim(p_cause_detail), '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-quantity:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_quantity_events
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid livestock quantity';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock event effective time'; end if;
  if v_cause not in ('DISEASE','INJURY','PREDATION','WEATHER','BIRTH_COMPLICATION','UNKNOWN','OTHER') then
    raise exception 'invalid livestock mortality cause';
  end if;

  -- Read the derived balance under the per-Cohort lock so two concurrent
  -- mortality commands cannot both consume the same animals.
  perform public.gf022_lock_cohort_quantity(p_cohort_id);
  v_current := public.livestock_cohort_quantity_as_of(p_cohort_id, p_effective_at);
  if p_quantity > v_current then
    raise exception 'livestock quantity exceeds the current derived quantity (% available)', v_current;
  end if;

  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    cause_category, cause_detail, evidence_reference, notes, recorded_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, 'MORTALITY', p_quantity, p_effective_at,
    v_cause, nullif(trim(p_cause_detail), ''), nullif(trim(p_evidence_reference), ''),
    nullif(trim(p_notes), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_MORTALITY_RECORDED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object('project_id', p_project_id, 'quantity_event_id', v_id,
                       'quantity', p_quantity, 'cause_category', v_cause)
  );
  return v_id;
end $$;
create or replace function public.split_livestock_cohort(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_cohort_id uuid,
  p_quantity integer,
  p_effective_at timestamptz,
  p_destination_cohort_reference text,
  p_destination_herd_id uuid,
  p_destination_site_id uuid,
  p_destination_sex_composition text,
  p_destination_breed_descriptor text,
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
  v_operation uuid;
  v_destination uuid;
  v_current integer;
  v_sex text := nullif(upper(trim(coalesce(p_destination_sex_composition, ''))), '');
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|SPLIT|' || p_source_cohort_id::text || '|' ||
    coalesce(p_quantity::text, '') || '|' || coalesce(p_effective_at::text, '') || '|' ||
    upper(trim(coalesce(p_destination_cohort_reference, ''))) || '|' ||
    p_destination_herd_id::text || '|' || p_destination_site_id::text || '|' ||
    coalesce(v_sex, '') || '|' || coalesce(trim(p_destination_breed_descriptor), '') || '|' ||
    trim(coalesce(p_reason, '')) || '|' || coalesce(trim(p_evidence_reference), '') || '|' ||
    coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-operation:' || trim(p_idempotency_key), 0
  ));
  -- Replay returns the SAME operation without creating a second destination
  -- Cohort, a second pair of legs, or a second audit event.
  select * into v_row from public.livestock_quantity_operations
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_source_cohort_id);
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid livestock quantity';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock event effective time'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid livestock operation reason';
  end if;
  if v_sex is not null and v_sex not in ('MALE','FEMALE','MIXED') then
    raise exception 'invalid livestock sex composition';
  end if;

  perform public.gf022_lock_cohort_quantity(p_source_cohort_id);
  v_current := public.livestock_cohort_quantity_as_of(p_source_cohort_id, p_effective_at);
  if p_quantity > v_current then
    raise exception 'livestock quantity exceeds the current derived quantity (% available)', v_current;
  end if;

  if exists (
    select 1
    from public.livestock_cohorts c
    join public.livestock_herds source_herd
      on (source_herd.id, source_herd.organization_id, source_herd.project_id) =
         (c.herd_id, c.organization_id, c.project_id)
    join public.livestock_herds destination_herd
      on destination_herd.id = p_destination_herd_id
     and destination_herd.organization_id = p_organization_id
     and destination_herd.project_id = p_project_id
    where c.id = p_source_cohort_id
      and c.organization_id = p_organization_id
      and c.project_id = p_project_id
      and source_herd.species is distinct from destination_herd.species
  ) then
    raise exception 'livestock split requires a compatible species';
  end if;

  insert into public.livestock_quantity_operations(
    organization_id, project_id, operation_type, effective_at, reason,
    evidence_reference, notes, performed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, 'SPLIT', p_effective_at, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_operation;

  v_destination := public.gf022_create_derived_cohort(
    p_organization_id, p_project_id, p_destination_herd_id, p_destination_site_id,
    p_destination_cohort_reference, 'SPLIT_FROM_COHORT', p_effective_at,
    v_sex, p_destination_breed_descriptor, p_evidence_reference, p_notes,
    v_actor, 'split-' || v_operation::text
  );

  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    operation_id, evidence_reference, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_source_cohort_id, 'SPLIT_OUT', p_quantity,
    p_effective_at, v_operation, nullif(trim(p_evidence_reference), ''), null,
    v_actor, 'split-out-' || v_operation::text,
    public.gf020_hash(v_operation::text || '|SPLIT_OUT')
  );
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    operation_id, evidence_reference, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_destination, 'SPLIT_IN', p_quantity,
    p_effective_at, v_operation, nullif(trim(p_evidence_reference), ''), null,
    v_actor, 'split-in-' || v_operation::text,
    public.gf020_hash(v_operation::text || '|SPLIT_IN')
  );

  insert into public.livestock_cohort_lineage(
    organization_id, project_id, operation_id, source_cohort_id,
    destination_cohort_id, quantity
  ) values (
    p_organization_id, p_project_id, v_operation, p_source_cohort_id,
    v_destination, p_quantity
  );

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_COHORT_SPLIT', 'livestock_quantity_operation',
    v_operation,
    jsonb_build_object('project_id', p_project_id, 'source_cohort_id', p_source_cohort_id,
                       'destination_cohort_id', v_destination, 'quantity', p_quantity)
  );
  return v_operation;
end $$;
create or replace function public.merge_livestock_cohorts(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_cohort_ids uuid[],
  p_quantities integer[],
  p_effective_at timestamptz,
  p_destination_cohort_reference text,
  p_destination_herd_id uuid,
  p_destination_site_id uuid,
  p_destination_sex_composition text,
  p_destination_breed_descriptor text,
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
  v_operation uuid;
  v_destination uuid;
  v_total integer := 0;
  v_current integer;
  v_species text;
  v_source_species text;
  v_source uuid;
  v_quantity integer;
  v_index integer;
  v_sex text := nullif(upper(trim(coalesce(p_destination_sex_composition, ''))), '');
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|MERGE|' ||
    coalesce(array_to_string(p_source_cohort_ids, ','), '') || '|' ||
    coalesce(array_to_string(p_quantities, ','), '') || '|' ||
    coalesce(p_effective_at::text, '') || '|' ||
    upper(trim(coalesce(p_destination_cohort_reference, ''))) || '|' ||
    p_destination_herd_id::text || '|' || p_destination_site_id::text || '|' ||
    coalesce(v_sex, '') || '|' || coalesce(trim(p_destination_breed_descriptor), '') || '|' ||
    trim(coalesce(p_reason, '')) || '|' || coalesce(trim(p_evidence_reference), '') || '|' ||
    coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-operation:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_quantity_operations
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  if p_source_cohort_ids is null or array_length(p_source_cohort_ids, 1) < 2 then
    raise exception 'livestock merge requires at least two source cohorts';
  end if;
  if p_quantities is null
     or array_length(p_quantities, 1) <> array_length(p_source_cohort_ids, 1) then
    raise exception 'livestock merge quantities must match the source cohorts';
  end if;
  if (select count(distinct s) from unnest(p_source_cohort_ids) s)
     <> array_length(p_source_cohort_ids, 1) then
    raise exception 'livestock merge sources must be distinct';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock event effective time'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid livestock operation reason';
  end if;
  if v_sex is not null and v_sex not in ('MALE','FEMALE','MIXED') then
    raise exception 'invalid livestock sex composition';
  end if;

  -- The destination Herd fixes the species. Every source must match it, so a
  -- cross-species merge can never happen by accident.
  select h.species into v_species from public.livestock_herds h
  where h.id = p_destination_herd_id and h.organization_id = p_organization_id
    and h.project_id = p_project_id;
  if v_species is null then raise exception 'livestock herd not found'; end if;

  -- Lock sources in a deterministic order so two concurrent merges sharing a
  -- source cannot deadlock, and neither can overdraw it.
  for v_source in
    select s from unnest(p_source_cohort_ids) s order by s::text
  loop
    perform public.gf022_lock_cohort_quantity(v_source);
  end loop;

  for v_index in 1 .. array_length(p_source_cohort_ids, 1) loop
    v_source := p_source_cohort_ids[v_index];
    v_quantity := p_quantities[v_index];
    perform public.gf021_require_active_cohort(p_organization_id, p_project_id, v_source);
    if v_quantity is null or v_quantity <= 0 then
      raise exception 'invalid livestock quantity';
    end if;
    select h.species into v_source_species
    from public.livestock_cohorts c
    join public.livestock_herds h
      on (h.id, h.organization_id, h.project_id) =
         (c.herd_id, c.organization_id, c.project_id)
    where c.id = v_source and c.organization_id = p_organization_id
      and c.project_id = p_project_id;
    if v_source_species is distinct from v_species then
      raise exception 'livestock merge requires a compatible species';
    end if;
    v_current := public.livestock_cohort_quantity_as_of(v_source, p_effective_at);
    if v_quantity > v_current then
      raise exception 'livestock quantity exceeds the current derived quantity (% available)', v_current;
    end if;
    v_total := v_total + v_quantity;
  end loop;

  insert into public.livestock_quantity_operations(
    organization_id, project_id, operation_type, effective_at, reason,
    evidence_reference, notes, performed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, 'MERGE', p_effective_at, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_operation;

  v_destination := public.gf022_create_derived_cohort(
    p_organization_id, p_project_id, p_destination_herd_id, p_destination_site_id,
    p_destination_cohort_reference, 'MERGED_FROM_COHORTS', p_effective_at,
    v_sex, p_destination_breed_descriptor, p_evidence_reference, p_notes,
    v_actor, 'merge-' || v_operation::text
  );

  for v_index in 1 .. array_length(p_source_cohort_ids, 1) loop
    v_source := p_source_cohort_ids[v_index];
    v_quantity := p_quantities[v_index];
    insert into public.livestock_quantity_events(
      organization_id, project_id, cohort_id, event_type, quantity, effective_at,
      operation_id, evidence_reference, notes, recorded_by, idempotency_key, request_hash
    ) values (
      p_organization_id, p_project_id, v_source, 'MERGE_OUT', v_quantity,
      p_effective_at, v_operation, nullif(trim(p_evidence_reference), ''), null,
      v_actor, 'merge-out-' || v_operation::text || '-' || v_index::text,
      public.gf020_hash(v_operation::text || '|MERGE_OUT|' || v_index::text)
    );
    insert into public.livestock_cohort_lineage(
      organization_id, project_id, operation_id, source_cohort_id,
      destination_cohort_id, quantity
    ) values (
      p_organization_id, p_project_id, v_operation, v_source, v_destination, v_quantity
    );
  end loop;

  -- The destination receives exactly the sum of the merged quantities.
  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    operation_id, evidence_reference, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_destination, 'MERGE_IN', v_total,
    p_effective_at, v_operation, nullif(trim(p_evidence_reference), ''), null,
    v_actor, 'merge-in-' || v_operation::text,
    public.gf020_hash(v_operation::text || '|MERGE_IN')
  );

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_COHORTS_MERGED', 'livestock_quantity_operation',
    v_operation,
    jsonb_build_object('project_id', p_project_id, 'source_cohort_ids', p_source_cohort_ids,
                       'destination_cohort_id', v_destination, 'total_quantity', v_total)
  );
  return v_operation;
end $$;
create or replace function public.record_livestock_weight_event(
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
  v_current := public.livestock_cohort_quantity_as_of(p_cohort_id, p_effective_at);
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
create function public.record_livestock_mortality(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_quantity integer,
  p_effective_at timestamptz,
  p_cause_category text,
  p_cause_detail text,
  p_evidence_reference text,
  p_disposal_method text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_row record;
  v_id uuid;
  v_cause text := upper(trim(coalesce(p_cause_category, '')));
  v_disposal text := upper(trim(coalesce(p_disposal_method, 'PENDING')));
  v_current integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|MORTALITY|' ||
    coalesce(p_quantity::text, '') || '|' || coalesce(p_effective_at::text, '') || '|' ||
    v_cause || '|' || coalesce(trim(p_cause_detail), '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || v_disposal || '|' ||
    coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-quantity:' || trim(p_idempotency_key), 0
  ));
  select * into v_row from public.livestock_quantity_events
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid livestock quantity';
  end if;
  if p_effective_at is null then raise exception 'invalid livestock event effective time'; end if;
  if v_cause not in ('DISEASE','INJURY','PREDATION','WEATHER','BIRTH_COMPLICATION','UNKNOWN','OTHER') then
    raise exception 'invalid livestock mortality cause';
  end if;

  if v_disposal not in ('BURIAL','INCINERATION','RENDERING','COMPOSTING','OTHER','PENDING') then
    raise exception 'invalid livestock mortality disposal method';
  end if;

  -- Read the derived balance under the per-Cohort lock so two concurrent
  -- mortality commands cannot both consume the same animals.
  perform public.gf022_lock_cohort_quantity(p_cohort_id);
  v_current := public.livestock_cohort_quantity_as_of(p_cohort_id, p_effective_at);
  if p_quantity > v_current then
    raise exception 'livestock quantity exceeds the current derived quantity (% available)', v_current;
  end if;

  insert into public.livestock_quantity_events(
    organization_id, project_id, cohort_id, event_type, quantity, effective_at,
    cause_category, cause_detail, evidence_reference, disposal_method, notes, recorded_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, 'MORTALITY', p_quantity, p_effective_at,
    v_cause, nullif(trim(p_cause_detail), ''), nullif(trim(p_evidence_reference), ''),
    v_disposal, nullif(trim(p_notes), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_MORTALITY_RECORDED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object('project_id', p_project_id, 'quantity_event_id', v_id,
                       'quantity', p_quantity, 'cause_category', v_cause,
                       'disposal_method', v_disposal)
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
  p_confidence_level text,
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
  v_confidence text := upper(trim(coalesce(p_confidence_level, 'UNASSESSED')));
  v_current integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_cohort_id::text || '|' ||
    coalesce(p_effective_at::text, '') || '|' || v_method || '|' ||
    coalesce(p_weight_value::text, '') || '|' || v_unit || '|' ||
    coalesce(p_measured_animal_count::text, '') || '|' || coalesce(p_sample_size::text, '') || '|' ||
    coalesce(trim(p_evidence_reference), '') || '|' || v_confidence || '|' ||
    coalesce(trim(p_notes), '')
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

  if v_confidence not in ('UNASSESSED','LOW','MEDIUM','HIGH') then
    raise exception 'invalid livestock weight confidence level';
  end if;

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
  v_current := public.livestock_cohort_quantity_as_of(p_cohort_id, p_effective_at);
  if p_measured_animal_count is not null and p_measured_animal_count > v_current then
    raise exception 'livestock measured animal count exceeds current derived quantity';
  end if;
  if p_sample_size is not null and p_sample_size > v_current then
    raise exception 'livestock sample size exceeds current derived quantity';
  end if;

  insert into public.livestock_weight_events(
    organization_id, project_id, cohort_id, effective_at, method,
    weight_value, weight_unit, measured_animal_count, sample_size,
    evidence_reference, confidence_level, notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cohort_id, p_effective_at, v_method,
    p_weight_value, v_unit, p_measured_animal_count, p_sample_size,
    nullif(trim(p_evidence_reference), ''), v_confidence, nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_WEIGHT_RECORDED', 'livestock_cohort', p_cohort_id,
    jsonb_build_object(
      'project_id', p_project_id, 'weight_event_id', v_id, 'method', v_method,
      'weight_unit', v_unit, 'sample_size', p_sample_size,
      'measured_animal_count', p_measured_animal_count,
      'confidence_level', v_confidence
    )
  );
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Security for the new read columns, triggers, and overloads.
-- ---------------------------------------------------------------------------
revoke all on
  public.livestock_cohort_quantity_rollforward,
  public.livestock_quantity_events_read,
  public.livestock_cohort_lineage_read,
  public.livestock_weight_events_read
  from public, anon;
grant select on
  public.livestock_cohort_quantity_rollforward,
  public.livestock_quantity_events_read,
  public.livestock_cohort_lineage_read,
  public.livestock_weight_events_read
  to authenticated;

revoke all on function
  public.livestock_cohort_quantity_as_of(uuid,timestamptz),
  public.gf022_validate_quantity_event(),
  public.gf022_validate_non_negative_quantity(),
  public.gf022_validate_operation_conservation(),
  public.gf022_validate_cohort_species(),
  public.gf022_validate_herd_species_update(),
  public.gf022_validate_movement_species(),
  public.gf022_validate_lineage_species(),
  public.gf021_validate_weight_population()
  from public, anon, authenticated;
grant execute on function public.livestock_cohort_quantity_as_of(uuid,timestamptz)
  to authenticated;

-- Keep the original arities for older clients; the new overloads are the
-- disposal/confidence-aware application paths.
grant execute on function
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text),
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text,text)
  to authenticated;

comment on column public.livestock_weight_events.confidence_level is
  'Qualitative operational quality only; not a statistical confidence interval.';
comment on column public.livestock_quantity_events.disposal_method is
  'Constrained mortality disposal state; PENDING means the method is not yet recorded.';
