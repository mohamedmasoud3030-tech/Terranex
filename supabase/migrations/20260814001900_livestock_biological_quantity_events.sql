-- GF-022 — Livestock biological quantity events: births, mortality, split, merge.
--
-- Purely ADDITIVE on the GF-021 quantity architecture. The GF-021 ledger
-- (`livestock_quantity_events`) and its class registry
-- (`livestock_quantity_event_types`) are unchanged in shape; GF-022 registers
-- the six real operational classes and adds the operation identity that binds
-- the two sides of a split or a merge together.
--
-- Livestock stays EVENT-DERIVED. No mutable current_headcount, mortality_total,
-- births_total, or available_animals is introduced. Headcount is exact integer
-- arithmetic; no floating point touches this path.
--
-- No Finance artifact, valuation, IAS 41, biological-asset measurement, or COGS
-- is produced. Sale and removal remain out of scope.

-- ---------------------------------------------------------------------------
-- 1. GF-022.A — Register the real quantity event classes.
-- ---------------------------------------------------------------------------

-- Two additional facts about each class, so the rules stay data-driven rather
-- than hard-coded in every command:
--   * `requires_operation` — the class is one leg of a two-sided operation and
--     may never exist on its own;
--   * `requires_cause`     — the class must carry a cause category.
alter table public.livestock_quantity_event_types
  add column requires_operation boolean not null default false,
  add column requires_cause boolean not null default false;

insert into public.livestock_quantity_event_types(
  code, direction, label_ar, introduced_in, requires_operation, requires_cause
) values
  ('BIRTH',      1, 'ولادات',            'GF-022', false, false),
  ('MORTALITY', -1, 'نفوق',              'GF-022', false, true),
  ('SPLIT_OUT', -1, 'صادر إلى تقسيم',    'GF-022', true,  false),
  ('SPLIT_IN',   1, 'وارد من تقسيم',     'GF-022', true,  false),
  ('MERGE_OUT', -1, 'صادر إلى دمج',      'GF-022', true,  false),
  ('MERGE_IN',   1, 'وارد من دمج',       'GF-022', true,  false);

-- ---------------------------------------------------------------------------
-- 2. GF-022.D/E — One operation identity per split or merge.
-- ---------------------------------------------------------------------------
-- A split or merge is ONE operation with two sides. It is never two unrelated
-- +N / -N rows: both legs carry the same `operation_id`, and a deferred
-- constraint proves the operation conserves quantity exactly at commit.
create table public.livestock_quantity_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  operation_type text not null check (operation_type in ('SPLIT', 'MERGE')),
  effective_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  performed_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),

  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index livestock_quantity_operations_project_idx
  on public.livestock_quantity_operations(project_id, effective_at);

create trigger livestock_quantity_operations_sector_guard
  before insert on public.livestock_quantity_operations
  for each row execute function public.gf020_sector_guard();
create trigger livestock_quantity_operations_no_change
  before update or delete on public.livestock_quantity_operations
  for each row execute function public.gf021_immutable();

-- Bind quantity events to their operation and to a mortality cause.
alter table public.livestock_quantity_events
  add column operation_id uuid,
  add column cause_category text
    check (cause_category is null or cause_category in (
      'DISEASE', 'INJURY', 'PREDATION', 'WEATHER', 'BIRTH_COMPLICATION',
      'UNKNOWN', 'OTHER'
    )),
  add column cause_detail text
    check (cause_detail is null or char_length(trim(cause_detail)) between 3 and 500),
  add constraint livestock_quantity_events_operation_fk
    foreign key (operation_id, organization_id, project_id)
    references public.livestock_quantity_operations(id, organization_id, project_id)
    on delete restrict;
create index livestock_quantity_events_operation_idx
  on public.livestock_quantity_events(operation_id);

-- A class either belongs to an operation or never does; a cause is required
-- exactly where the class demands one. Enforced for EVERY insert, including
-- privileged and import paths.
create function public.gf022_validate_quantity_event() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_type record;
begin
  select * into v_type from public.livestock_quantity_event_types
  where code = new.event_type;
  if not found then
    raise exception 'unknown livestock quantity event type';
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
  if new.cause_detail is not null and new.cause_category is null then
    raise exception 'livestock cause detail requires a cause category';
  end if;

  -- The operation must agree with the leg: a SPLIT leg cannot hang off a MERGE.
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

create trigger livestock_quantity_events_validate
  before insert on public.livestock_quantity_events
  for each row execute function public.gf022_validate_quantity_event();

-- ---------------------------------------------------------------------------
-- 3. Conservation invariant: an operation creates and destroys nothing.
-- ---------------------------------------------------------------------------
-- Deferred to commit so the atomic command can write both legs in one
-- transaction, while any incomplete or unbalanced privileged write is refused.
create function public.gf022_validate_operation_conservation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_operation_id uuid;
  v_out integer;
  v_in integer;
  v_legs integer;
begin
  -- A CASE expression would resolve `new.operation_id` for both branches and
  -- fail on the operations table, which has no such field.
  if tg_table_name = 'livestock_quantity_operations' then
    v_operation_id := new.id;
  else
    v_operation_id := new.operation_id;
  end if;
  if v_operation_id is null then
    return null;
  end if;

  select
    coalesce(sum(case when t.direction = -1 then q.quantity else 0 end), 0),
    coalesce(sum(case when t.direction = 1 then q.quantity else 0 end), 0),
    count(*)
  into v_out, v_in, v_legs
  from public.livestock_quantity_events q
  join public.livestock_quantity_event_types t on t.code = q.event_type
  where q.operation_id = v_operation_id;

  if v_legs < 2 then
    raise exception 'livestock quantity operation requires both an outgoing and an incoming leg';
  end if;
  if v_out <> v_in then
    raise exception
      'livestock quantity operation does not conserve quantity: out=%, in=%',
      v_out, v_in;
  end if;
  return null;
end $$;

create constraint trigger livestock_operation_conserves_quantity
  after insert on public.livestock_quantity_operations
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_conservation();
create constraint trigger livestock_operation_leg_conserves_quantity
  after insert on public.livestock_quantity_events
  deferrable initially deferred
  for each row execute function public.gf022_validate_operation_conservation();

-- ---------------------------------------------------------------------------
-- 4. Derived quantity can never go negative.
-- ---------------------------------------------------------------------------
-- A last-resort deferred guard. The commands already refuse to overdraw under
-- a per-Cohort lock; this makes an overdrawn balance unreachable even through
-- a privileged path.
create function public.gf022_validate_non_negative_quantity() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_quantity integer;
begin
  select r.current_quantity into v_quantity
  from public.livestock_cohort_quantity_rollforward r
  where r.cohort_id = new.cohort_id;
  if v_quantity is null then
    raise exception 'livestock cohort not found';
  end if;
  if v_quantity < 0 then
    raise exception 'livestock derived quantity cannot go below zero (%)', v_quantity;
  end if;
  return null;
end $$;

create constraint trigger livestock_quantity_never_negative
  after insert on public.livestock_quantity_events
  deferrable initially deferred
  for each row execute function public.gf022_validate_non_negative_quantity();

-- ---------------------------------------------------------------------------
-- 5. GF-022.D/E — Cohorts created by an operation have no opening balance.
-- ---------------------------------------------------------------------------
-- A Cohort produced by a split or a merge did not "open" with a headcount: its
-- entire quantity arrives through the lineage event, and recording an opening
-- balance as well would double-count it. Its opening headcount is therefore
-- exactly zero, and only for these two explicit origins.
alter table public.livestock_cohorts
  drop constraint livestock_cohorts_opening_headcount_check;
alter table public.livestock_cohorts
  drop constraint livestock_cohorts_origin_type_check;
alter table public.livestock_cohorts
  add constraint livestock_cohorts_origin_type_check
  check (origin_type in (
    'PURCHASED', 'BORN', 'CONTRIBUTED_IN_KIND', 'TRANSFERRED_IN',
    'OPENING_BALANCE', 'SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS'
  ));
alter table public.livestock_cohorts
  add constraint livestock_cohorts_opening_headcount_check
  check (
    case
      when origin_type in ('SPLIT_FROM_COHORT', 'MERGED_FROM_COHORTS')
        then opening_headcount = 0
      else opening_headcount > 0
    end
  );

-- Lineage: which operation produced this Cohort, and from which sources.
create table public.livestock_cohort_lineage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  operation_id uuid not null,
  source_cohort_id uuid not null,
  destination_cohort_id uuid not null,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),

  unique (operation_id, source_cohort_id, destination_cohort_id),
  constraint livestock_lineage_distinct_cohorts
    check (source_cohort_id <> destination_cohort_id),
  foreign key (operation_id, organization_id, project_id)
    references public.livestock_quantity_operations(id, organization_id, project_id)
    on delete restrict,
  foreign key (source_cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (destination_cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_lineage_destination_idx
  on public.livestock_cohort_lineage(destination_cohort_id);
create index livestock_lineage_source_idx
  on public.livestock_cohort_lineage(source_cohort_id);

create trigger livestock_lineage_sector_guard
  before insert on public.livestock_cohort_lineage
  for each row execute function public.gf020_sector_guard();
create trigger livestock_lineage_no_change
  before update or delete on public.livestock_cohort_lineage
  for each row execute function public.gf021_immutable();

-- ---------------------------------------------------------------------------
-- 6. GF-022.G — Full quantity rollforward, per class, exact integers.
-- ---------------------------------------------------------------------------
-- The GF-021 rollforward exposed only aggregate increase/decrease. GF-022 adds
-- a per-class breakdown, which changes the column list, so the view is dropped
-- and rebuilt rather than replaced in place.
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
) e on true;

create view public.livestock_quantity_events_read
with (security_invoker=on) as
select
  q.id, q.organization_id, q.project_id, q.cohort_id, c.cohort_reference,
  q.event_type, t.label_ar as event_label, t.direction,
  q.quantity, (t.direction * q.quantity)::integer as signed_quantity,
  q.effective_at, q.operation_id, q.cause_category, q.cause_detail,
  q.evidence_reference, q.notes, q.recorded_by, q.recorded_at
from public.livestock_quantity_events q
join public.livestock_quantity_event_types t on t.code = q.event_type
join public.livestock_cohorts c
  on (c.id, c.organization_id, c.project_id) =
     (q.cohort_id, q.organization_id, q.project_id);

create view public.livestock_cohort_lineage_read
with (security_invoker=on) as
select
  l.id, l.organization_id, l.project_id, l.operation_id,
  o.operation_type, o.effective_at, o.reason, o.evidence_reference,
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
-- 7. Shared command helpers.
-- ---------------------------------------------------------------------------

-- Serializes every quantity command for a Cohort and returns the derived
-- balance read under that lock, so two sessions cannot both spend it.
create function public.gf022_lock_cohort_quantity(p_cohort_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_cohort_id::text || ':livestock-quantity', 0
  ));
  return public.livestock_current_cohort_quantity(p_cohort_id);
end $$;

-- Creates the destination Cohort of a split/merge with an explicitly chosen
-- (never blindly copied) identity, its immutable opening placement, and an
-- ACTIVE lifecycle chain so it can immediately carry operational events.
create function public.gf022_create_derived_cohort(
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

  -- opening_headcount is 0 by construction: the quantity arrives as lineage.
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
    organization_id, project_id, cohort_id, site_id, placed_by
  ) values (p_organization_id, p_project_id, v_id, p_site_id, p_actor);

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
-- 8. GF-022.B — Birth.
-- ---------------------------------------------------------------------------
create function public.record_livestock_birth(
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

-- ---------------------------------------------------------------------------
-- 9. GF-022.C — Mortality.
-- ---------------------------------------------------------------------------
create function public.record_livestock_mortality(
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
  v_current := public.gf022_lock_cohort_quantity(p_cohort_id);
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

-- ---------------------------------------------------------------------------
-- 10. GF-022.D — Atomic split.
-- ---------------------------------------------------------------------------
create function public.split_livestock_cohort(
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

  v_current := public.gf022_lock_cohort_quantity(p_source_cohort_id);
  if p_quantity > v_current then
    raise exception 'livestock quantity exceeds the current derived quantity (% available)', v_current;
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

-- ---------------------------------------------------------------------------
-- 11. GF-022.E — Atomic merge.
-- ---------------------------------------------------------------------------
create function public.merge_livestock_cohorts(
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
    v_current := public.livestock_current_cohort_quantity(v_source);
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

-- ---------------------------------------------------------------------------
-- 12. Security: RLS, FORCE RLS, default deny, no authenticated table DML.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'livestock_quantity_operations',
    'livestock_cohort_lineage'
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

revoke all on
  public.livestock_quantity_events_read,
  public.livestock_cohort_lineage_read
  from public, anon;
grant select on
  public.livestock_quantity_events_read,
  public.livestock_cohort_lineage_read
  to authenticated;
revoke all on public.livestock_cohort_quantity_rollforward from public, anon;
grant select on public.livestock_cohort_quantity_rollforward to authenticated;

revoke all on function
  public.gf022_validate_quantity_event(),
  public.gf022_validate_operation_conservation(),
  public.gf022_validate_non_negative_quantity(),
  public.gf022_lock_cohort_quantity(uuid),
  public.gf022_create_derived_cohort(uuid,uuid,uuid,uuid,text,text,timestamptz,text,text,text,text,uuid,text)
  from public, anon, authenticated;

revoke all on function
  public.record_livestock_birth(uuid,uuid,uuid,integer,timestamptz,text,text,text),
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text),
  public.split_livestock_cohort(uuid,uuid,uuid,integer,timestamptz,text,uuid,uuid,text,text,text,text,text,text),
  public.merge_livestock_cohorts(uuid,uuid,uuid[],integer[],timestamptz,text,uuid,uuid,text,text,text,text,text,text)
  from public, anon;
grant execute on function
  public.record_livestock_birth(uuid,uuid,uuid,integer,timestamptz,text,text,text),
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text),
  public.split_livestock_cohort(uuid,uuid,uuid,integer,timestamptz,text,uuid,uuid,text,text,text,text,text,text),
  public.merge_livestock_cohorts(uuid,uuid,uuid[],integer[],timestamptz,text,uuid,uuid,text,text,text,text,text,text)
  to authenticated;
