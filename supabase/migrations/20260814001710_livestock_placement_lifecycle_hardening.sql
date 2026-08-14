-- GF-020 review hardening — placement, lifecycle graph, and weight truth.
-- Forward-only repair. The reviewed 01700 migration remains immutable.

-- ---------------------------------------------------------------------------
-- 1. Cohort opening placement is an immutable fact; Herd is not a location.
-- ---------------------------------------------------------------------------
create table public.livestock_cohort_initial_placements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  site_id uuid not null,
  placed_by uuid not null references auth.users(id) on delete restrict,
  placed_at timestamptz not null default now(),
  unique (cohort_id),
  unique (id, organization_id, project_id),
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (site_id, organization_id, project_id)
    references public.livestock_sites(id, organization_id, project_id) on delete restrict
);
create index livestock_initial_placements_project_idx
  on public.livestock_cohort_initial_placements(project_id, site_id);

-- Preserve any rows created while the reviewed migration was under review.
insert into public.livestock_cohort_initial_placements(
  organization_id, project_id, cohort_id, site_id, placed_by, placed_at
)
select c.organization_id, c.project_id, c.id, h.site_id, c.created_by, c.created_at
from public.livestock_cohorts c
join public.livestock_herds h
  on (h.id, h.organization_id, h.project_id) =
     (c.herd_id, c.organization_id, c.project_id);

-- Rebuild reads before removing the obsolete Herd column.
drop view public.livestock_cohorts_read;
drop view public.livestock_herds_read;

-- Retire the old command signatures so new callers cannot keep treating Site
-- as Herd identity or omit opening placement.
drop function public.create_livestock_herd(uuid,uuid,uuid,text,text,text,text,text,text);
drop function public.create_livestock_cohort(uuid,uuid,uuid,text,text,date,integer,text,text,numeric,text,text,text,text,text);

do $drop_herd_site_fk$
declare
  v_name text;
begin
  select c.conname into v_name
  from pg_constraint c
  where c.conrelid = 'public.livestock_herds'::regclass
    and c.contype = 'f'
    and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (site_id,%';
  if v_name is null then
    raise exception 'livestock Herd-Site foreign key not found';
  end if;
  execute format('alter table public.livestock_herds drop constraint %I', v_name);
end
$drop_herd_site_fk$;

alter table public.livestock_herds drop column site_id;

-- ---------------------------------------------------------------------------
-- 2. Remove under-specified sampled averages from the bounded foundation.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from public.livestock_cohorts
    where opening_weight_basis = 'SAMPLED_AVERAGE'
  ) then
    raise exception 'GF-020 upgrade requires controlled correction of SAMPLED_AVERAGE opening weights';
  end if;
end $$;

alter table public.livestock_cohorts
  drop constraint livestock_cohorts_opening_weight_basis_check;
alter table public.livestock_cohorts
  add constraint livestock_cohorts_opening_weight_basis_check
  check (opening_weight_basis is null or opening_weight_basis in (
    'INDIVIDUAL_MEASURED', 'COHORT_TOTAL', 'ESTIMATED'
  ));

-- ---------------------------------------------------------------------------
-- 3. Lifecycle history is one database-enforced causal linked list.
-- ---------------------------------------------------------------------------
alter table public.livestock_cohort_state_history
  add constraint livestock_history_identity_scope_unique
  unique (id, organization_id, project_id, cohort_id);

do $replace_predecessor_fk$
declare
  v_name text;
begin
  select c.conname into v_name
  from pg_constraint c
  where c.conrelid = 'public.livestock_cohort_state_history'::regclass
    and c.contype = 'f'
    and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (previous_history_id,%';
  if v_name is null then
    raise exception 'livestock predecessor foreign key not found';
  end if;
  execute format(
    'alter table public.livestock_cohort_state_history drop constraint %I',
    v_name
  );
end
$replace_predecessor_fk$;

alter table public.livestock_cohort_state_history
  add constraint livestock_history_predecessor_same_cohort_fk
  foreign key (previous_history_id, organization_id, project_id, cohort_id)
  references public.livestock_cohort_state_history(
    id, organization_id, project_id, cohort_id
  ) on delete restrict;

alter table public.livestock_cohort_state_history
  add constraint livestock_history_root_or_child_check
  check (
    (previous_history_id is null and previous_state is null and new_state = 'PLANNED')
    or
    (previous_history_id is not null and previous_state is not null)
  );

create unique index livestock_history_one_root_per_cohort
  on public.livestock_cohort_state_history(cohort_id)
  where previous_history_id is null;

-- The existing UNIQUE(previous_history_id) prevents branching for non-null
-- predecessors. This validator additionally binds the stated prior state to
-- the actual same-cohort predecessor and rejects malformed privileged writes.
create function public.gf020_validate_history_link() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_predecessor_state text;
begin
  if new.previous_history_id is null then
    if new.previous_state is not null or new.new_state <> 'PLANNED' then
      raise exception 'invalid livestock lifecycle root';
    end if;
    return new;
  end if;

  select h.new_state into v_predecessor_state
  from public.livestock_cohort_state_history h
  where h.id = new.previous_history_id
    and h.organization_id = new.organization_id
    and h.project_id = new.project_id
    and h.cohort_id = new.cohort_id;

  if not found then
    raise exception 'livestock lifecycle predecessor must belong to the same cohort';
  end if;
  if new.previous_state is distinct from v_predecessor_state then
    raise exception 'livestock lifecycle previous state mismatch';
  end if;
  if not (v_predecessor_state = 'PLANNED' and new.new_state = 'ACTIVE') then
    raise exception 'invalid livestock cohort transition';
  end if;
  return new;
end $$;

create trigger livestock_history_validate_link
  before insert on public.livestock_cohort_state_history
  for each row execute function public.gf020_validate_history_link();

-- A Cohort is complete only with exactly one opening placement, one lifecycle
-- root, and one causal tip. Deferred execution permits the atomic create command
-- to insert all three facts in one transaction while rejecting incomplete
-- privileged/import writes at commit.
create function public.gf020_validate_cohort_foundation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_cohort_id uuid := case when tg_table_name = 'livestock_cohorts' then new.id else new.cohort_id end;
  v_roots integer;
  v_tips integer;
  v_placements integer;
begin
  select count(*) into v_roots
  from public.livestock_cohort_state_history
  where cohort_id = v_cohort_id and previous_history_id is null;

  select count(*) into v_tips
  from public.livestock_cohort_state_history h
  where h.cohort_id = v_cohort_id
    and not exists (
      select 1 from public.livestock_cohort_state_history child
      where child.cohort_id = h.cohort_id
        and child.previous_history_id = h.id
    );

  select count(*) into v_placements
  from public.livestock_cohort_initial_placements
  where cohort_id = v_cohort_id;

  if v_roots <> 1 or v_tips <> 1 or v_placements <> 1 then
    raise exception 'invalid livestock cohort foundation: roots=%, tips=%, placements=%',
      v_roots, v_tips, v_placements;
  end if;
  return null;
end $$;

create constraint trigger livestock_cohort_foundation_complete
  after insert on public.livestock_cohorts
  deferrable initially deferred
  for each row execute function public.gf020_validate_cohort_foundation();
create constraint trigger livestock_history_foundation_complete
  after insert on public.livestock_cohort_state_history
  deferrable initially deferred
  for each row execute function public.gf020_validate_cohort_foundation();
create constraint trigger livestock_placement_foundation_complete
  after insert on public.livestock_cohort_initial_placements
  deferrable initially deferred
  for each row execute function public.gf020_validate_cohort_foundation();

create or replace function public.livestock_current_cohort_tip(p_cohort_id uuid)
returns uuid language plpgsql stable security invoker
set search_path=pg_catalog,public as $$
declare
  v_tip uuid;
  v_count integer;
begin
  select max(h.id::text)::uuid, count(*) into v_tip, v_count
  from public.livestock_cohort_state_history h
  where h.cohort_id = p_cohort_id
    and not exists (
      select 1 from public.livestock_cohort_state_history child
      where child.cohort_id = h.cohort_id
        and child.previous_history_id = h.id
    );
  if v_count <> 1 then
    raise exception 'invalid livestock lifecycle tip count: %', v_count;
  end if;
  return v_tip;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Corrected commands: Herd has no Site; Cohort requires opening Site.
-- ---------------------------------------------------------------------------
create function public.create_livestock_herd(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_internal_reference text,
  p_species text,
  p_purpose text,
  p_breed_descriptor text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_row record;
  v_id uuid;
  v_species text := upper(trim(coalesce(p_species, '')));
  v_purpose text := upper(trim(coalesce(p_purpose, '')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || trim(coalesce(p_name, '')) || '|' ||
    upper(trim(coalesce(p_internal_reference, ''))) || '|' || v_species || '|' ||
    v_purpose || '|' || coalesce(trim(p_breed_descriptor), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-herd:' || trim(p_idempotency_key), 0
  ));

  select * into v_row from public.livestock_herds
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform pg_advisory_xact_lock(hashtextextended(
    p_project_id::text || ':livestock-herd-ref:' ||
    upper(trim(coalesce(p_internal_reference, ''))), 0
  ));
  if v_species not in ('CATTLE','BUFFALO','SHEEP','GOAT') then raise exception 'invalid livestock species'; end if;
  if v_purpose not in ('MEAT','BREEDING','MIXED') then raise exception 'invalid livestock purpose'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then raise exception 'invalid livestock herd name'; end if;
  if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then raise exception 'invalid livestock herd reference'; end if;
  if exists (
    select 1 from public.livestock_herds
    where organization_id = p_organization_id and project_id = p_project_id
      and internal_reference = upper(trim(p_internal_reference))
  ) then raise exception 'livestock herd reference already exists'; end if;

  insert into public.livestock_herds(
    organization_id, project_id, name, internal_reference, species, purpose,
    breed_descriptor, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_name), upper(trim(p_internal_reference)),
    v_species, v_purpose, nullif(trim(p_breed_descriptor), ''), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_HERD_CREATED', 'livestock_herd', v_id,
    jsonb_build_object('project_id', p_project_id, 'species', v_species, 'purpose', v_purpose)
  );
  return v_id;
end $$;

create function public.create_livestock_cohort(
  p_organization_id uuid,
  p_project_id uuid,
  p_herd_id uuid,
  p_site_id uuid,
  p_cohort_reference text,
  p_origin_type text,
  p_origin_date date,
  p_opening_headcount integer,
  p_sex_composition text,
  p_breed_descriptor text,
  p_opening_weight_value numeric,
  p_opening_weight_unit text,
  p_opening_weight_basis text,
  p_origin_evidence_reference text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_row record;
  v_id uuid;
  v_origin text := upper(trim(coalesce(p_origin_type, '')));
  v_sex text := nullif(upper(trim(coalesce(p_sex_composition, ''))), '');
  v_unit text := nullif(upper(trim(coalesce(p_opening_weight_unit, ''))), '');
  v_basis text := nullif(upper(trim(coalesce(p_opening_weight_basis, ''))), '');
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  v_hash := public.gf020_hash(
    p_project_id::text || '|' || p_herd_id::text || '|' || p_site_id::text || '|' ||
    upper(trim(coalesce(p_cohort_reference, ''))) || '|' || v_origin || '|' ||
    coalesce(p_origin_date::text, '') || '|' || coalesce(p_opening_headcount::text, '') || '|' ||
    coalesce(v_sex, '') || '|' || coalesce(trim(p_breed_descriptor), '') || '|' ||
    coalesce(p_opening_weight_value::text, '') || '|' || coalesce(v_unit, '') || '|' ||
    coalesce(v_basis, '') || '|' || coalesce(trim(p_origin_evidence_reference), '') || '|' ||
    coalesce(trim(p_notes), '')
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':ls-cohort:' || trim(p_idempotency_key), 0
  ));

  select * into v_row from public.livestock_cohorts
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_row.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_row.id;
  end if;

  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform pg_advisory_xact_lock(hashtextextended(
    p_project_id::text || ':livestock-cohort-ref:' ||
    upper(trim(coalesce(p_cohort_reference, ''))), 0
  ));
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
  if v_origin not in ('PURCHASED','BORN','CONTRIBUTED_IN_KIND','TRANSFERRED_IN','OPENING_BALANCE') then raise exception 'invalid livestock cohort origin'; end if;
  if p_origin_date is null then raise exception 'invalid livestock cohort origin date'; end if;
  if p_opening_headcount is null or p_opening_headcount <= 0 then raise exception 'invalid livestock opening headcount'; end if;
  if v_sex is not null and v_sex not in ('MALE','FEMALE','MIXED') then raise exception 'invalid livestock sex composition'; end if;
  if (p_opening_weight_value is null) <> (v_unit is null)
     or (p_opening_weight_value is null) <> (v_basis is null) then
    raise exception 'invalid livestock opening weight';
  end if;
  if p_opening_weight_value is not null and (
    p_opening_weight_value <= 0 or v_unit <> 'KG'
    or v_basis not in ('INDIVIDUAL_MEASURED','COHORT_TOTAL','ESTIMATED')
  ) then raise exception 'invalid livestock opening weight'; end if;
  if p_cohort_reference is null or char_length(trim(p_cohort_reference)) not between 1 and 100 then raise exception 'invalid livestock cohort reference'; end if;
  if exists (
    select 1 from public.livestock_cohorts
    where organization_id = p_organization_id and project_id = p_project_id
      and cohort_reference = upper(trim(p_cohort_reference))
  ) then raise exception 'livestock cohort reference already exists'; end if;

  insert into public.livestock_cohorts(
    organization_id, project_id, herd_id, cohort_reference, origin_type,
    origin_date, opening_headcount, sex_composition, breed_descriptor,
    opening_weight_value, opening_weight_unit, opening_weight_basis,
    origin_evidence_reference, notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_herd_id,
    upper(trim(p_cohort_reference)), v_origin, p_origin_date,
    p_opening_headcount, v_sex, nullif(trim(p_breed_descriptor), ''),
    p_opening_weight_value, v_unit, v_basis,
    nullif(trim(p_origin_evidence_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.livestock_cohort_initial_placements(
    organization_id, project_id, cohort_id, site_id, placed_by
  ) values (p_organization_id, p_project_id, v_id, p_site_id, v_actor);

  insert into public.livestock_cohort_state_history(
    organization_id, project_id, cohort_id, previous_history_id,
    previous_state, new_state, reason, changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_id, null, null, 'PLANNED',
    'إنشاء الدفعة', v_actor, 'initial-' || v_id::text,
    public.gf020_hash(v_id::text || '|PLANNED')
  );

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'LIVESTOCK_COHORT_CREATED', 'livestock_cohort', v_id,
    jsonb_build_object(
      'project_id', p_project_id, 'herd_id', p_herd_id, 'initial_site_id', p_site_id,
      'origin_type', v_origin, 'opening_headcount', p_opening_headcount,
      'initial_state', 'PLANNED'
    )
  );
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Read models and least privilege for opening placement.
-- ---------------------------------------------------------------------------
create view public.livestock_herds_read with (security_invoker=on) as
select h.id, h.organization_id, h.project_id, h.name, h.internal_reference,
       h.species, h.purpose, h.breed_descriptor, h.created_by, h.created_at
from public.livestock_herds h;

create view public.livestock_cohorts_read with (security_invoker=on) as
select c.id, c.organization_id, c.project_id, c.herd_id,
       h.name as herd_name, h.internal_reference as herd_reference,
       h.species, h.purpose,
       p.site_id as initial_site_id, s.name as initial_site_name,
       c.cohort_reference, c.origin_type, c.origin_date, c.opening_headcount,
       c.sex_composition, coalesce(c.breed_descriptor, h.breed_descriptor) as breed_descriptor,
       c.opening_weight_value::text as opening_weight_value,
       c.opening_weight_unit, c.opening_weight_basis,
       c.origin_evidence_reference, c.notes, c.created_by, c.created_at,
       public.livestock_current_cohort_state(c.id) as lifecycle_state
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

alter table public.livestock_cohort_initial_placements enable row level security;
alter table public.livestock_cohort_initial_placements force row level security;
create policy livestock_initial_placements_read
  on public.livestock_cohort_initial_placements for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.livestock_cohort_initial_placements from public, anon, authenticated;
grant select on public.livestock_cohort_initial_placements to authenticated;

create view public.livestock_cohort_initial_placements_read
with (security_invoker=on) as
select p.id, p.organization_id, p.project_id, p.cohort_id, p.site_id,
       s.name as site_name, p.placed_by, p.placed_at
from public.livestock_cohort_initial_placements p
join public.livestock_sites s
  on (s.id, s.organization_id, s.project_id) =
     (p.site_id, p.organization_id, p.project_id);

revoke all on public.livestock_cohort_initial_placements_read from public, anon;
grant select on public.livestock_herds_read, public.livestock_cohorts_read,
  public.livestock_cohort_initial_placements_read to authenticated;

create trigger livestock_initial_placements_no_change
  before update or delete on public.livestock_cohort_initial_placements
  for each row execute function public.gf020_immutable();
create trigger livestock_initial_placements_sector_guard
  before insert on public.livestock_cohort_initial_placements
  for each row execute function public.gf020_sector_guard();

revoke all on function public.gf020_validate_history_link(),
  public.gf020_validate_cohort_foundation()
  from public, anon, authenticated;
revoke all on function public.create_livestock_herd(uuid,uuid,text,text,text,text,text,text),
  public.create_livestock_cohort(uuid,uuid,uuid,uuid,text,text,date,integer,text,text,numeric,text,text,text,text,text)
  from public, anon;
grant execute on function public.create_livestock_herd(uuid,uuid,text,text,text,text,text,text),
  public.create_livestock_cohort(uuid,uuid,uuid,uuid,text,text,date,integer,text,text,numeric,text,text,text,text,text)
  to authenticated;
