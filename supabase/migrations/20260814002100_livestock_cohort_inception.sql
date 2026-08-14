-- GF-022 review hardening — Cohort inception and future-derived provenance.
-- Forward-only migration. Normal Cohorts have a date-only operational boundary;
-- derived Cohorts use the exact producing operation timestamp. No timestamp
-- precision is fabricated for legacy normal Cohorts whose origin is a DATE.

-- ---------------------------------------------------------------------------
-- 1. Authoritative Cohort inception helpers.
-- ---------------------------------------------------------------------------
create or replace function public.gf022_cohort_inception_at(p_cohort_id uuid)
returns timestamptz language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_origin_type text;
  v_origin_date date;
  v_operation_count integer;
  v_operation_type text;
  v_inception_at timestamptz;
begin
  select c.origin_type, c.origin_date
    into v_origin_type, v_origin_date
    from public.livestock_cohorts c
   where c.id = p_cohort_id;
  if not found then
    raise exception 'livestock cohort not found';
  end if;

  if v_origin_type not in ('SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS') then
    -- Origin dates are date-only facts. UTC midnight is the documented lower
    -- boundary, not a claim that the source recorded a time of day.
    return (v_origin_date::timestamp without time zone at time zone 'UTC');
  end if;

  select count(distinct l.operation_id)::integer,
         min(o.operation_type),
         min(o.effective_at)
    into v_operation_count, v_operation_type, v_inception_at
    from public.livestock_cohort_lineage l
    join public.livestock_quantity_operations o
      on (o.id, o.organization_id, o.project_id) =
         (l.operation_id, l.organization_id, l.project_id)
   where l.destination_cohort_id = p_cohort_id;
  if v_operation_count <> 1 or v_inception_at is null then
    raise exception 'livestock derived Cohort inception is not established';
  end if;
  if (v_origin_type = 'SPLIT_FROM_COHORT' and v_operation_type <> 'SPLIT')
     or (v_origin_type = 'MERGED_FROM_COHORTS' and v_operation_type <> 'MERGE') then
    raise exception 'livestock derived Cohort origin does not match its producing operation';
  end if;
  return v_inception_at;
end $$;

-- Event rows on a derived destination are written before the command inserts
-- its lineage row. The operation identity is therefore a provisional, atomic
-- provenance witness; the deferred lineage/provenance trigger completes the
-- database proof at commit.
create function public.gf022_event_inception_at(
  p_cohort_id uuid,
  p_operation_id uuid,
  p_event_type text
) returns timestamptz language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_origin_type text;
  v_origin_date date;
  v_operation_count integer;
  v_operation_type text;
  v_operation_effective_at timestamptz;
  v_expected_type text;
begin
  select c.origin_type, c.origin_date
    into v_origin_type, v_origin_date
    from public.livestock_cohorts c
   where c.id = p_cohort_id;
  if not found then
    raise exception 'livestock cohort not found';
  end if;
  if v_origin_type not in ('SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS') then
    return (v_origin_date::timestamp without time zone at time zone 'UTC');
  end if;

  select count(distinct l.operation_id)::integer,
         min(o.operation_type),
         min(o.effective_at)
    into v_operation_count, v_operation_type, v_operation_effective_at
    from public.livestock_cohort_lineage l
    join public.livestock_quantity_operations o
      on (o.id, o.organization_id, o.project_id) =
         (l.operation_id, l.organization_id, l.project_id)
   where l.destination_cohort_id = p_cohort_id;
  if v_operation_count = 1 then
    v_expected_type := case v_origin_type
      when 'SPLIT_FROM_COHORT' then 'SPLIT'
      when 'MERGED_FROM_COHORTS' then 'MERGE'
    end;
    if v_operation_type is distinct from v_expected_type then
      raise exception 'livestock derived Cohort origin does not match its producing operation';
    end if;
    return v_operation_effective_at;
  end if;

  if p_operation_id is null or p_event_type not in ('SPLIT_IN', 'MERGE_IN') then
    raise exception 'livestock derived Cohort inception is not established';
  end if;
  select o.operation_type, o.effective_at
    into v_operation_type, v_operation_effective_at
    from public.livestock_quantity_operations o
   where o.id = p_operation_id;
  v_expected_type := case v_origin_type
    when 'SPLIT_FROM_COHORT' then 'SPLIT'
    when 'MERGED_FROM_COHORTS' then 'MERGE'
  end;
  if v_operation_type is distinct from v_expected_type then
    raise exception 'livestock derived Cohort origin does not match its producing operation';
  end if;
  return v_operation_effective_at;
end $$;

create function public.gf022_validate_quantity_event_inception() returns trigger
language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_inception_at timestamptz;
  v_balance bigint;
  v_bucket record;
begin
  v_inception_at := public.gf022_event_inception_at(
    new.cohort_id, new.operation_id, new.event_type
  );
  if new.effective_at < v_inception_at then
    raise exception 'livestock event effective time precedes Cohort inception';
  end if;

  -- Validate the candidate row against the complete existing timeline before
  -- inserting it. This turns a stale backdated concurrency loser into a normal
  -- command error instead of allowing it to reach the deferred backstop.
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
    select x.effective_at, coalesce(sum(x.delta), 0::bigint) as delta
      from (
        select q.effective_at,
               t.direction::bigint * q.quantity::bigint as delta
          from public.livestock_quantity_events q
          join public.livestock_quantity_event_types t on t.code = q.event_type
         where q.cohort_id = new.cohort_id
        union all
        select new.effective_at,
               t.direction::bigint * new.quantity::bigint as delta
          from public.livestock_quantity_event_types t
         where t.code = new.event_type
      ) x
     group by x.effective_at
     order by x.effective_at
  loop
    if v_bucket.effective_at < v_inception_at then
      raise exception 'livestock event effective time precedes Cohort inception';
    end if;
    v_balance := v_balance + v_bucket.delta;
    if v_balance < 0 then
      raise exception 'livestock as-of quantity cannot go below zero for Cohort % at % (%)',
        new.cohort_id, v_bucket.effective_at, v_balance;
    end if;
  end loop;
  return new;
end $$;

create trigger livestock_quantity_events_inception_guard
  before insert on public.livestock_quantity_events
  for each row execute function public.gf022_validate_quantity_event_inception();

create function public.gf022_validate_movement_inception() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_inception_at timestamptz;
begin
  v_inception_at := public.gf022_cohort_inception_at(new.cohort_id);
  if new.effective_at < v_inception_at then
    raise exception 'livestock movement effective time precedes Cohort inception';
  end if;
  return new;
end $$;

create trigger livestock_movements_inception_guard
  before insert on public.livestock_cohort_movements
  for each row execute function public.gf022_validate_movement_inception();

-- A derived Cohort must be produced exactly by the operation family named by
-- its origin. Multiple producing operations are rejected, so inception is not
-- ambiguous even through privileged/import writes.
create function public.gf022_validate_derived_cohort_provenance() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_origin_type text;
  v_operation_count integer;
  v_operation_type text;
  v_expected_type text;
begin
  select c.origin_type into v_origin_type
    from public.livestock_cohorts c
   where c.id = new.destination_cohort_id;
  if v_origin_type not in ('SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS') then
    return null;
  end if;
  select count(distinct l.operation_id)::integer, min(o.operation_type)
    into v_operation_count, v_operation_type
    from public.livestock_cohort_lineage l
    join public.livestock_quantity_operations o
      on (o.id, o.organization_id, o.project_id) =
         (l.operation_id, l.organization_id, l.project_id)
   where l.destination_cohort_id = new.destination_cohort_id;
  v_expected_type := case v_origin_type
    when 'SPLIT_FROM_COHORT' then 'SPLIT'
    when 'MERGED_FROM_COHORTS' then 'MERGE'
  end;
  if v_operation_count <> 1 then
    raise exception 'livestock derived Cohort must have exactly one producing operation';
  end if;
  if v_operation_type <> v_expected_type then
    raise exception 'livestock derived Cohort origin does not match its producing operation';
  end if;
  return null;
end $$;

create constraint trigger livestock_derived_cohort_provenance_validate
  after insert on public.livestock_cohort_lineage
  deferrable initially deferred
  for each row execute function public.gf022_validate_derived_cohort_provenance();

drop view public.livestock_cohorts_read;
create view public.livestock_cohorts_read
with (security_invoker=on) as
select
  c.id, c.organization_id, c.project_id, c.herd_id,
  h.name herd_name, h.internal_reference herd_reference, h.species, h.purpose,
  p.site_id initial_site_id, s.name initial_site_name,
  c.cohort_reference, c.origin_type, c.origin_date, c.opening_headcount,
  c.sex_composition,
  coalesce(c.breed_descriptor, h.breed_descriptor) breed_descriptor,
  c.opening_weight_value::text opening_weight_value,
  c.opening_weight_unit, c.opening_weight_basis,
  c.origin_evidence_reference, c.notes, c.created_by, c.created_at,
  public.livestock_current_cohort_state(c.id) lifecycle_state,
  public.gf022_cohort_inception_at(c.id) operational_inception_at,
  (public.gf022_cohort_inception_at(c.id) <= current_timestamp) as is_operational_as_of_now
from public.livestock_cohorts c
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) =
     (c.herd_id, c.organization_id, c.project_id)
join public.livestock_cohort_initial_placements p
  on (p.cohort_id, p.organization_id, p.project_id) =
     (c.id, c.organization_id, c.project_id)
join public.livestock_sites s
  on (s.id, s.organization_id, s.project_id) =
     (p.site_id, p.organization_id, p.project_id);

revoke all on public.livestock_cohorts_read from public, anon;
grant select on public.livestock_cohorts_read to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Replace the shared resolvers/guards with inception-aware definitions.
-- ---------------------------------------------------------------------------
create or replace function public.livestock_cohort_quantity_as_of(
  p_cohort_id uuid,
  p_as_of_at timestamptz
) returns integer language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_opening bigint;
  v_delta bigint;
  v_quantity bigint;
  v_inception_at timestamptz;
begin
  if p_as_of_at is null then
    raise exception 'livestock quantity as-of time is required';
  end if;
  v_inception_at := public.gf022_cohort_inception_at(p_cohort_id);
  -- The date-only normal-Cohort boundary is UTC midnight. A derived Cohort's
  -- boundary is the exact producing operation timestamp.
  if p_as_of_at < v_inception_at then
    return 0;
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
     and q.effective_at >= v_inception_at
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

-- Keep the rollforward breakdown on the same inception boundary as its
-- current_quantity resolver. The view shape is unchanged, so this is a
-- non-destructive definition replacement rather than a ledger rebuild.
create or replace view public.livestock_cohort_quantity_rollforward
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
    and q.effective_at >= public.gf022_cohort_inception_at(c.id)
    and q.effective_at <= current_timestamp
) e on true;

create or replace function public.gf022_validate_non_negative_quantity() returns trigger
language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_balance bigint;
  v_delta bigint;
  v_bucket record;
  v_inception_at timestamptz;
begin
  v_inception_at := public.gf022_cohort_inception_at(new.cohort_id);
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
    if v_bucket.effective_at < v_inception_at then
      raise exception 'livestock event effective time precedes Cohort inception';
    end if;
    v_balance := v_balance + v_bucket.delta;
    if v_balance < 0 then
      raise exception 'livestock as-of quantity cannot go below zero for Cohort % at % (%)',
        new.cohort_id, v_bucket.effective_at, v_balance;
    end if;
  end loop;
  return null;
end $$;



create or replace function public.gf021_validate_weight_population() returns trigger
language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_current integer;
  v_inception_at timestamptz;
begin
  v_inception_at := public.gf022_cohort_inception_at(new.cohort_id);
  if new.effective_at < v_inception_at then
    raise exception 'livestock weight effective time precedes Cohort inception';
  end if;
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



-- Add a row lock alongside the advisory lock. The row lock is the database
-- serialization point for sessions that race through the SECURITY DEFINER
-- commands, while the advisory lock also covers privileged/import validators.
create or replace function public.gf022_lock_cohort_quantity(p_cohort_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_cohort_id::text || ':livestock-quantity', 0
  ));
  perform 1
    from public.livestock_cohorts c
   where c.id = p_cohort_id
   for update;
  if not found then
    raise exception 'livestock cohort not found';
  end if;
  return public.livestock_current_cohort_quantity(p_cohort_id);
end $$;

-- The resolver is used by all existing command bodies, so mortality, split,
-- merge, and birth now inherit the inception boundary without changing their
-- public signatures. Weight and movement have dedicated trigger backstops.

revoke all on function
  public.gf022_cohort_inception_at(uuid),
  public.gf022_event_inception_at(uuid,uuid,text),
  public.gf022_validate_quantity_event_inception(),
  public.gf022_validate_movement_inception(),
  public.gf022_validate_derived_cohort_provenance()
  from public, anon, authenticated;
grant execute on function public.gf022_cohort_inception_at(uuid)
  to authenticated;

comment on function public.gf022_cohort_inception_at(uuid) is
  'Normal Cohort inception is origin_date at UTC midnight; derived Cohort inception is the exact producing operation effective_at.';
comment on column public.livestock_cohorts.origin_date is
  'Date-only normal-Cohort inception boundary; no time-of-day precision is implied.';
