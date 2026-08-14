-- GF-021 / GF-022 review hardening.
--
-- Forward-only repair on top of the already-reviewable GF-021 and GF-022
-- migrations. This migration closes five integrity gaps without rewriting any
-- historical migration or introducing Finance side effects:
--   1. quantity is resolved as-of business time, not all-time;
--   2. confirmed operational facts may not be future-dated;
--   3. species is continuous across movement/split/merge;
--   4. split/merge operation shape and lineage are exact DB invariants;
--   5. operational facts require ACTIVE, positive-quantity Cohorts where the
--      operation consumes/observes an existing population.
--
-- Reaching zero remains an explicit derived fact. GF-020's bounded lifecycle
-- only implements PLANNED -> ACTIVE, so this repair deliberately does not invent
-- an implicit SPLIT/MERGED/CLOSED transition. A later lifecycle slice may add an
-- explicit causal close/split state command.

-- ---------------------------------------------------------------------------
-- 1. Business-time lower boundary and as-of quantity resolver.
-- ---------------------------------------------------------------------------

-- For ordinary Cohorts the business opening boundary is the recorded origin
-- date (UTC midnight, deterministic and country-neutral). For a Cohort created
-- by split/merge, the operation time is authoritative; the immutable opening
-- placement is a fallback for the tiny interval before lineage is inserted in
-- the same atomic command and for pre-hardening rows.
create or replace function public.livestock_cohort_opening_effective_at(
  p_cohort_id uuid
) returns timestamptz
language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_origin text;
  v_origin_date date;
  v_placed_at timestamptz;
  v_operation_at timestamptz;
begin
  select c.origin_type, c.origin_date, p.placed_at
    into v_origin, v_origin_date, v_placed_at
  from public.livestock_cohorts c
  join public.livestock_cohort_initial_placements p on p.cohort_id = c.id
  where c.id = p_cohort_id;

  if not found then
    raise exception 'livestock cohort not found';
  end if;

  if v_origin in ('SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS') then
    select min(o.effective_at) into v_operation_at
    from public.livestock_cohort_lineage l
    join public.livestock_quantity_operations o on o.id = l.operation_id
    where l.destination_cohort_id = p_cohort_id;
    return coalesce(v_operation_at, v_placed_at);
  end if;

  return v_origin_date::timestamp at time zone 'UTC';
end $$;

-- Exact quantity at a requested business instant. Later inflows are excluded,
-- so a backdated outflow can never borrow quantity that did not yet exist.
create or replace function public.livestock_cohort_quantity_as_of(
  p_cohort_id uuid,
  p_as_of timestamptz
) returns integer
language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_opening integer;
  v_opening_at timestamptz;
  v_quantity bigint;
begin
  if p_as_of is null then
    raise exception 'invalid livestock event effective time';
  end if;

  select c.opening_headcount into v_opening
  from public.livestock_cohorts c
  where c.id = p_cohort_id;
  if not found then
    raise exception 'livestock cohort not found';
  end if;

  v_opening_at := public.livestock_cohort_opening_effective_at(p_cohort_id);
  if p_as_of < v_opening_at then
    raise exception 'livestock event effective time precedes cohort opening';
  end if;

  select v_opening::bigint + coalesce(sum(t.direction::bigint * q.quantity::bigint), 0)
    into v_quantity
  from public.livestock_quantity_events q
  join public.livestock_quantity_event_types t on t.code = q.event_type
  where q.cohort_id = p_cohort_id
    and q.effective_at <= p_as_of;

  if v_quantity < 0 then
    raise exception 'invalid negative livestock derived quantity: %', v_quantity;
  end if;
  if v_quantity > 2147483647 then
    raise exception 'livestock derived quantity exceeds supported integer range';
  end if;
  return v_quantity::integer;
end $$;

-- Current truth is now explicitly an as-of-now projection. This also makes any
-- pre-hardening future rows harmless to current operational truth.
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
  (c.opening_headcount
     + coalesce(e.quantity_increase, 0)
     - coalesce(e.quantity_decrease, 0))::integer as current_quantity
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

create or replace function public.livestock_current_cohort_quantity(p_cohort_id uuid)
returns integer language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
begin
  return public.livestock_cohort_quantity_as_of(p_cohort_id, current_timestamp);
end $$;

-- Shared lock + as-of resolver for authoritative availability checks.
create function public.gf022_lock_cohort_quantity_as_of(
  p_cohort_id uuid,
  p_as_of timestamptz
) returns integer language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_cohort_id::text || ':livestock-quantity', 0
  ));
  return public.livestock_cohort_quantity_as_of(p_cohort_id, p_as_of);
end $$;

-- Keep the original helper contract, but make "current" explicitly as-of-now.
create or replace function public.gf022_lock_cohort_quantity(p_cohort_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  return public.gf022_lock_cohort_quantity_as_of(p_cohort_id, current_timestamp);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Temporal, ACTIVE, zero-quantity and species guards on every write path.
-- ---------------------------------------------------------------------------

create function public.gf022_review_reject_future_actual(p_effective_at timestamptz)
returns void language plpgsql stable
set search_path=pg_catalog as $$
begin
  if p_effective_at is null then
    raise exception 'invalid livestock event effective time';
  end if;
  if p_effective_at > clock_timestamp() then
    raise exception 'future livestock actual event is not allowed';
  end if;
end $$;

create function public.gf022_review_cohort_species(p_cohort_id uuid)
returns text language sql stable security invoker
set search_path=pg_catalog,public as $$
  select h.species
  from public.livestock_cohorts c
  join public.livestock_herds h
    on (h.id, h.organization_id, h.project_id) =
       (c.herd_id, c.organization_id, c.project_id)
  where c.id = p_cohort_id
$$;

create function public.gf022_review_movement_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_opening_at timestamptz;
  v_quantity integer;
  v_species text;
  v_source_species text;
  v_destination_species text;
begin
  perform public.gf022_review_reject_future_actual(new.effective_at);
  perform public.gf021_require_active_cohort(
    new.organization_id, new.project_id, new.cohort_id
  );
  v_opening_at := public.livestock_cohort_opening_effective_at(new.cohort_id);
  if new.effective_at < v_opening_at then
    raise exception 'livestock movement effective time precedes cohort opening';
  end if;

  v_quantity := public.gf022_lock_cohort_quantity_as_of(
    new.cohort_id, new.effective_at
  );
  if v_quantity <= 0 then
    raise exception 'livestock cohort has zero quantity for this operation';
  end if;

  v_species := public.gf022_review_cohort_species(new.cohort_id);
  select species into v_source_species from public.livestock_herds
   where id = new.source_herd_id and organization_id = new.organization_id
     and project_id = new.project_id;
  select species into v_destination_species from public.livestock_herds
   where id = new.destination_herd_id and organization_id = new.organization_id
     and project_id = new.project_id;
  if v_species is null
     or v_source_species is distinct from v_species
     or v_destination_species is distinct from v_species then
    raise exception 'livestock movement must preserve cohort species';
  end if;
  return new;
end $$;

create trigger z_gf022_review_movement_guard
  before insert on public.livestock_cohort_movements
  for each row execute function public.gf022_review_movement_guard();

create function public.gf022_review_weight_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_opening_at timestamptz;
  v_quantity integer;
begin
  perform public.gf022_review_reject_future_actual(new.effective_at);
  perform public.gf021_require_active_cohort(
    new.organization_id, new.project_id, new.cohort_id
  );
  v_opening_at := public.livestock_cohort_opening_effective_at(new.cohort_id);
  if new.effective_at < v_opening_at then
    raise exception 'livestock weight effective time precedes cohort opening';
  end if;

  v_quantity := public.gf022_lock_cohort_quantity_as_of(
    new.cohort_id, new.effective_at
  );
  if v_quantity <= 0 then
    raise exception 'livestock cohort has zero quantity for this operation';
  end if;
  if new.measured_animal_count is not null
     and new.measured_animal_count > v_quantity then
    raise exception 'livestock measured animal count exceeds quantity as of effective time';
  end if;
  if new.sample_size is not null and new.sample_size > v_quantity then
    raise exception 'livestock sample size exceeds quantity as of effective time';
  end if;
  return new;
end $$;

create trigger z_gf022_review_weight_guard
  before insert on public.livestock_weight_events
  for each row execute function public.gf022_review_weight_guard();

create function public.gf022_review_quantity_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_opening_at timestamptz;
  v_quantity integer;
  v_direction smallint;
  v_species text;
begin
  perform public.gf022_review_reject_future_actual(new.effective_at);
  perform public.gf021_require_active_cohort(
    new.organization_id, new.project_id, new.cohort_id
  );
  v_opening_at := public.livestock_cohort_opening_effective_at(new.cohort_id);
  if new.effective_at < v_opening_at then
    raise exception 'livestock quantity effective time precedes cohort opening';
  end if;

  v_quantity := public.gf022_lock_cohort_quantity_as_of(
    new.cohort_id, new.effective_at
  );
  select direction into v_direction
  from public.livestock_quantity_event_types where code = new.event_type;
  if v_direction is null then
    raise exception 'unknown livestock quantity event type';
  end if;

  if v_direction = -1 then
    if v_quantity <= 0 then
      raise exception 'livestock cohort has zero quantity for this operation';
    end if;
    if new.quantity > v_quantity then
      raise exception
        'livestock quantity exceeds quantity as of effective time (% available)',
        v_quantity;
    end if;
  end if;

  -- Command insertion order writes all OUT legs before the single IN leg.
  -- This gives command callers an immediate species error. The deferred exact
  -- shape invariant below also catches privileged writes in any insertion order.
  if new.event_type in ('SPLIT_IN', 'MERGE_IN') and new.operation_id is not null then
    v_species := public.gf022_review_cohort_species(new.cohort_id);
    if exists (
      select 1
      from public.livestock_quantity_events source_event
      where source_event.operation_id = new.operation_id
        and source_event.event_type in ('SPLIT_OUT', 'MERGE_OUT')
        and public.gf022_review_cohort_species(source_event.cohort_id)
            is distinct from v_species
    ) then
      raise exception 'livestock quantity operation must preserve species';
    end if;
  end if;
  return new;
end $$;

create trigger z_gf022_review_quantity_guard
  before insert on public.livestock_quantity_events
  for each row execute function public.gf022_review_quantity_guard();

create function public.gf022_review_operation_time_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  perform public.gf022_review_reject_future_actual(new.effective_at);
  return new;
end $$;

create trigger z_gf022_review_operation_time_guard
  before insert on public.livestock_quantity_operations
  for each row execute function public.gf022_review_operation_time_guard();

-- A Herd's species becomes immutable once any Cohort has adopted that Herd as
-- its identity. Otherwise an owner/import path could retroactively rewrite the
-- species semantics of historical movement and lineage facts.
create function public.gf022_review_herd_species_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.species is distinct from old.species and exists (
    select 1 from public.livestock_cohorts c where c.herd_id = old.id
  ) then
    raise exception 'livestock herd species is immutable after cohort use';
  end if;
  return new;
end $$;

create trigger z_gf022_review_herd_species_guard
  before update of species on public.livestock_herds
  for each row execute function public.gf022_review_herd_species_guard();

-- ---------------------------------------------------------------------------
-- 3. Prefix non-negativity: later inflow never repairs an earlier deficit.
-- ---------------------------------------------------------------------------

create function public.gf022_validate_quantity_timeline() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_min_balance bigint;
  v_opening integer;
begin
  select opening_headcount into v_opening
  from public.livestock_cohorts where id = new.cohort_id;
  if not found then raise exception 'livestock cohort not found'; end if;

  with event_deltas as (
    select q.effective_at,
           sum(t.direction::bigint * q.quantity::bigint) as delta
    from public.livestock_quantity_events q
    join public.livestock_quantity_event_types t on t.code = q.event_type
    where q.cohort_id = new.cohort_id
    group by q.effective_at
  ), running as (
    select v_opening::bigint
           + sum(delta) over (
               order by effective_at
               rows between unbounded preceding and current row
             ) as balance
    from event_deltas
  )
  select min(balance) into v_min_balance from running;

  if coalesce(v_min_balance, v_opening) < 0 then
    raise exception 'livestock quantity timeline cannot go below zero';
  end if;
  return null;
end $$;

create constraint trigger livestock_quantity_timeline_non_negative
  after insert on public.livestock_quantity_events
  deferrable initially deferred
  for each row execute function public.gf022_validate_quantity_timeline();

-- ---------------------------------------------------------------------------
-- 4. Exact split/merge operation shape and lineage invariant.
-- ---------------------------------------------------------------------------

create function public.gf022_assert_operation_shape(p_operation_id uuid)
returns void language plpgsql set search_path=pg_catalog,public as $$
declare
  v_operation public.livestock_quantity_operations%rowtype;
  v_out_count integer;
  v_in_count integer;
  v_leg_count integer;
  v_lineage_count integer;
  v_out_total bigint;
  v_in_total bigint;
  v_destination uuid;
  v_destination_species text;
begin
  select * into v_operation
  from public.livestock_quantity_operations where id = p_operation_id;
  if not found then
    raise exception 'livestock quantity operation not found';
  end if;

  select
    count(*) filter (where q.event_type in ('SPLIT_OUT','MERGE_OUT')),
    count(*) filter (where q.event_type in ('SPLIT_IN','MERGE_IN')),
    count(*),
    coalesce(sum(q.quantity) filter (where q.event_type in ('SPLIT_OUT','MERGE_OUT')), 0),
    coalesce(sum(q.quantity) filter (where q.event_type in ('SPLIT_IN','MERGE_IN')), 0)
    into v_out_count, v_in_count, v_leg_count, v_out_total, v_in_total
  from public.livestock_quantity_events q
  where q.operation_id = p_operation_id;

  select count(*) into v_lineage_count
  from public.livestock_cohort_lineage l where l.operation_id = p_operation_id;

  if exists (
    select 1 from public.livestock_quantity_events q
    where q.operation_id = p_operation_id
      and q.effective_at is distinct from v_operation.effective_at
  ) then
    raise exception 'livestock operation legs must share the operation effective time';
  end if;

  if v_operation.operation_type = 'SPLIT' then
    if v_leg_count <> 2 or v_out_count <> 1 or v_in_count <> 1
       or v_lineage_count <> 1 then
      raise exception 'livestock split requires exactly one out leg, one in leg and one lineage row';
    end if;
    if not exists (
      select 1
      from public.livestock_quantity_events out_q
      join public.livestock_quantity_events in_q
        on in_q.operation_id = out_q.operation_id and in_q.event_type = 'SPLIT_IN'
      join public.livestock_cohort_lineage l
        on l.operation_id = out_q.operation_id
       and l.source_cohort_id = out_q.cohort_id
       and l.destination_cohort_id = in_q.cohort_id
       and l.quantity = out_q.quantity
      where out_q.operation_id = p_operation_id
        and out_q.event_type = 'SPLIT_OUT'
        and out_q.quantity = in_q.quantity
    ) then
      raise exception 'livestock split lineage must exactly match both quantity legs';
    end if;
  elsif v_operation.operation_type = 'MERGE' then
    if v_out_count < 2 or v_in_count <> 1
       or v_leg_count <> v_out_count + 1
       or v_lineage_count <> v_out_count then
      raise exception 'livestock merge requires distinct out legs, one in leg and one lineage row per source';
    end if;
    if (select count(distinct q.cohort_id)
        from public.livestock_quantity_events q
        where q.operation_id = p_operation_id and q.event_type = 'MERGE_OUT')
       <> v_out_count then
      raise exception 'livestock merge source legs must be distinct';
    end if;
    select q.cohort_id into v_destination
    from public.livestock_quantity_events q
    where q.operation_id = p_operation_id and q.event_type = 'MERGE_IN';
    if v_out_total <> v_in_total then
      raise exception 'livestock merge does not conserve quantity';
    end if;
    if exists (
      select 1
      from public.livestock_quantity_events out_q
      where out_q.operation_id = p_operation_id
        and out_q.event_type = 'MERGE_OUT'
        and not exists (
          select 1 from public.livestock_cohort_lineage l
          where l.operation_id = p_operation_id
            and l.source_cohort_id = out_q.cohort_id
            and l.destination_cohort_id = v_destination
            and l.quantity = out_q.quantity
        )
    ) or exists (
      select 1 from public.livestock_cohort_lineage l
      where l.operation_id = p_operation_id
        and l.destination_cohort_id is distinct from v_destination
    ) then
      raise exception 'livestock merge lineage must exactly match every source leg and the sole destination';
    end if;
  else
    raise exception 'invalid livestock quantity operation type';
  end if;

  if v_out_total <> v_in_total then
    raise exception 'livestock quantity operation does not conserve quantity: out=%, in=%',
      v_out_total, v_in_total;
  end if;

  select public.gf022_review_cohort_species(q.cohort_id)
    into v_destination_species
  from public.livestock_quantity_events q
  where q.operation_id = p_operation_id
    and q.event_type in ('SPLIT_IN','MERGE_IN');

  if exists (
    select 1
    from public.livestock_quantity_events q
    where q.operation_id = p_operation_id
      and q.event_type in ('SPLIT_OUT','MERGE_OUT')
      and public.gf022_review_cohort_species(q.cohort_id)
          is distinct from v_destination_species
  ) then
    raise exception 'livestock quantity operation must preserve species';
  end if;
end $$;

create function public.gf022_validate_operation_shape_trigger() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_operation_id uuid;
begin
  if tg_table_name = 'livestock_quantity_operations' then
    v_operation_id := new.id;
  else
    v_operation_id := new.operation_id;
  end if;
  if v_operation_id is not null then
    perform public.gf022_assert_operation_shape(v_operation_id);
  end if;
  return null;
end $$;

create constraint trigger livestock_operation_shape_exact
  after insert on public.livestock_quantity_operations
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_shape_trigger();
create constraint trigger livestock_operation_leg_shape_exact
  after insert on public.livestock_quantity_events
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_shape_trigger();
create constraint trigger livestock_operation_lineage_shape_exact
  after insert on public.livestock_cohort_lineage
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_shape_trigger();

-- ---------------------------------------------------------------------------
-- 5. Derived Cohort opening placement is effective at the operation time.
-- ---------------------------------------------------------------------------

create or replace function public.gf022_create_derived_cohort(
  p_organization_id uuid,
  p_project_id uuid,
  p_herd_id uuid,
  p_site_id uuid,
  p_cohort_reference text,
  p_origin_type text,
  p_effective_at timestamptz,
  p_sex_composition text,
  p_breed_descriptor text,
  p_evidence_reference text,
  p_notes text,
  p_actor uuid,
  p_key_prefix text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_id uuid;
  v_root uuid;
  v_reference text := upper(trim(coalesce(p_cohort_reference, '')));
begin
  if v_reference = '' or char_length(v_reference) > 100 then
    raise exception 'invalid livestock cohort reference';
  end if;
  if p_effective_at is null then
    raise exception 'invalid livestock event effective time';
  end if;
  if not exists (
    select 1 from public.livestock_herds
    where id = p_herd_id and organization_id = p_organization_id
      and project_id = p_project_id
  ) then raise exception 'livestock herd not found'; end if;
  if not exists (
    select 1 from public.livestock_sites
    where id = p_site_id and organization_id = p_organization_id
      and project_id = p_project_id
  ) then raise exception 'livestock site not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_project_id::text || ':livestock-cohort-ref:' || v_reference, 0
  ));
  if exists (
    select 1 from public.livestock_cohorts
    where organization_id = p_organization_id and project_id = p_project_id
      and cohort_reference = v_reference
  ) then raise exception 'livestock cohort reference already exists'; end if;

  insert into public.livestock_cohorts(
    organization_id, project_id, herd_id, cohort_reference, origin_type,
    origin_date, opening_headcount, sex_composition, breed_descriptor,
    origin_evidence_reference, notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_herd_id, v_reference, p_origin_type,
    p_effective_at::date, 0, p_sex_composition, nullif(trim(p_breed_descriptor), ''),
    nullif(trim(p_evidence_reference), ''), nullif(trim(p_notes), ''),
    p_actor, p_key_prefix || '-cohort',
    public.gf020_hash(p_key_prefix || '|' || v_reference)
  ) returning id into v_id;

  insert into public.livestock_cohort_initial_placements(
    organization_id, project_id, cohort_id, site_id, placed_by, placed_at
  ) values (
    p_organization_id, p_project_id, v_id, p_site_id, p_actor, p_effective_at
  );

  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_id, null, null, 'PLANNED',
    'إنشاء الدفعة من عملية تقسيم أو دمج', p_actor,
    'initial-' || v_id::text, public.gf020_hash(v_id::text || '|PLANNED')
  ) returning id into v_root;

  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_id, v_root, 'PLANNED', 'ACTIVE',
    'تفعيل الدفعة الناتجة عن العملية', p_actor,
    'active-' || v_id::text, public.gf020_hash(v_id::text || '|ACTIVE')
  );

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Security and callable surface.
-- ---------------------------------------------------------------------------

revoke all on function
  public.livestock_cohort_opening_effective_at(uuid),
  public.livestock_cohort_quantity_as_of(uuid,timestamptz),
  public.gf022_lock_cohort_quantity_as_of(uuid,timestamptz),
  public.gf022_review_reject_future_actual(timestamptz),
  public.gf022_review_cohort_species(uuid),
  public.gf022_review_movement_guard(),
  public.gf022_review_weight_guard(),
  public.gf022_review_quantity_guard(),
  public.gf022_review_operation_time_guard(),
  public.gf022_review_herd_species_guard(),
  public.gf022_validate_quantity_timeline(),
  public.gf022_assert_operation_shape(uuid),
  public.gf022_validate_operation_shape_trigger()
  from public, anon, authenticated;

grant execute on function
  public.livestock_cohort_opening_effective_at(uuid),
  public.livestock_cohort_quantity_as_of(uuid,timestamptz)
  to authenticated;
