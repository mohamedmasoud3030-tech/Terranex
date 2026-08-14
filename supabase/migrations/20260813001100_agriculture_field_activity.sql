-- GF-014 / Agriculture Field Activity Foundation.
--
-- Bounded operational record against an existing CropCycle-to-Field
-- assignment. Records what happened in the field. Does not create
-- inventory, accounting, harvest lots, or agronomy automation, and
-- does not advance CropCycle lifecycle state.
--
-- Deferred (explicitly out of scope): InputItem, InputLot,
-- InputApplication, HarvestEvent, HarvestLot, StorageLocation,
-- InventoryMovement, AgronomyObservation, IAS 41, sales/receivables,
-- weather/GIS/maps, offline/PWA, livestock, generic workflow/rules.

create table public.field_activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid not null,
  assignment_id uuid not null,
  activity_date date not null,
  activity_type text not null check (activity_type in (
    'PREPARE','PLANT','IRRIGATE','FERTILIZE','SPRAY','SCOUT','WEED','OTHER'
  )),
  quantity numeric(20,6) check (quantity is null or quantity > 0),
  unit text check (unit is null or char_length(trim(unit)) between 1 and 40),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check ((quantity is null) = (unit is null)),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (crop_cycle_id, organization_id, project_id)
    references public.crop_cycles(id, organization_id, project_id) on delete restrict,
  foreign key (field_id, organization_id, project_id)
    references public.fields(id, organization_id, project_id) on delete restrict,
  foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id)
    references public.crop_cycle_field_assignments(id, organization_id, project_id, crop_cycle_id, field_id)
    on delete restrict
);
create index field_activities_project_idx on public.field_activities(project_id, activity_date desc);
create index field_activities_assignment_idx on public.field_activities(assignment_id);

create or replace function public.s8a_guard_field_activities_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'field activities are append-only';
end $$;
drop trigger if exists field_activities_no_change on public.field_activities;
create trigger field_activities_no_change
  before update or delete on public.field_activities
  for each row execute function public.s8a_guard_field_activities_append_only();

create or replace function public.create_field_activity(
  p_organization_id uuid,
  p_project_id uuid,
  p_crop_cycle_id uuid,
  p_field_id uuid,
  p_assignment_id uuid,
  p_activity_date date,
  p_activity_type text,
  p_quantity numeric,
  p_unit text,
  p_notes text,
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
  v_assignment record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;
  if p_activity_date is null then
    raise exception 'invalid activity date';
  end if;
  if p_activity_type is null or p_activity_type not in (
    'PREPARE','PLANT','IRRIGATE','FERTILIZE','SPRAY','SCOUT','WEED','OTHER'
  ) then
    raise exception 'invalid activity type';
  end if;
  if (p_quantity is null) <> (p_unit is null) then
    raise exception 'quantity and unit must be provided together';
  end if;
  if p_quantity is not null and p_quantity <= 0 then
    raise exception 'quantity must be positive';
  end if;
  if p_unit is not null and char_length(trim(p_unit)) not between 1 and 40 then
    raise exception 'invalid unit';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 1 and 2000 then
    raise exception 'invalid notes';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  select * into v_assignment
    from public.crop_cycle_field_assignments a
   where a.id = p_assignment_id
     and a.organization_id = p_organization_id
     and a.project_id = p_project_id
     and a.crop_cycle_id = p_crop_cycle_id
     and a.field_id = p_field_id;
  if not found then
    raise exception 'crop cycle field assignment not found';
  end if;

  select encode(digest(
    p_project_id::text || '|' || p_crop_cycle_id::text || '|' || p_field_id::text || '|'
    || p_assignment_id::text || '|' || p_activity_date::text || '|' || p_activity_type || '|'
    || coalesce(p_quantity::text, '') || '|' || coalesce(trim(p_unit), '') || '|'
    || coalesce(trim(p_notes), '') || '|' || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s8a-field-activity:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.field_activities
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.field_activities(
    organization_id, project_id, crop_cycle_id, field_id, assignment_id,
    activity_date, activity_type, quantity, unit, notes, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_crop_cycle_id, p_field_id, p_assignment_id,
    p_activity_date, p_activity_type,
    p_quantity, nullif(trim(p_unit), ''),
    nullif(trim(p_notes), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'FIELD_ACTIVITY_CREATED', 'field_activity', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'crop_cycle_id', p_crop_cycle_id,
      'field_id', p_field_id,
      'assignment_id', p_assignment_id,
      'activity_date', p_activity_date,
      'activity_type', p_activity_type
    )
  );
  return v_id;
end $$;

alter table public.field_activities enable row level security;
alter table public.field_activities force row level security;
create policy field_activities_read on public.field_activities
  for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.field_activities from public, anon, authenticated;
grant select on public.field_activities to authenticated;

create or replace view public.field_activities_read with (security_invoker=on) as
select id, organization_id, project_id, crop_cycle_id, field_id, assignment_id,
       activity_date, activity_type,
       quantity::text as quantity, unit, notes, evidence_reference,
       recorded_by, created_at
from public.field_activities;

grant select on public.field_activities_read to authenticated;

revoke all on function public.create_field_activity(
  uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text,text,text
) from public, anon;
grant execute on function public.create_field_activity(
  uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text,text,text
) to authenticated;

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
    raise exception 'GF-014 requires the pgcrypto extension';
  end if;

  for v_record in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname = 'create_field_activity'
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten := regexp_replace(
        v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
        'g'
      );
      if v_rewritten = v_definition then
        raise exception 'failed to qualify pgcrypto digest in create_field_activity';
      end if;
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
