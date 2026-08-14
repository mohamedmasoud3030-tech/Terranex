-- GF-015 / Agriculture Field Input Application Foundation.
--
-- Bounded operational slice that lets an Agriculture operator record
-- that a real agricultural input was actually applied to an existing
-- CropCycle-to-Field assignment through an existing FieldActivity.
--
-- The operational chain completed by this migration is:
--
--   Farm → Field → CropCycle → CropCycle-Field Assignment
--        → Field Activity → Input Item → Input Lot → Input Application
--
-- Intentional boundary (this is architecture, not missing work):
--
--   GF-015 proves identity, lot traceability, field/application
--   quantity, expiry, and project/assignment coherence.
--   Available-stock validation begins only when the canonical
--   InventoryMovement slice exists.
--
-- Therefore there is deliberately NO received quantity, available
-- quantity, on-hand balance, warehouse balance, inventory valuation, or
-- purchase accounting column anywhere in this migration. An InputLot
-- here is an identity/traceability record, not inventory.
--
-- Recording an Input Item, an Input Lot, or an Input Application never
-- creates or mutates obligations, payments, journal batches, journal
-- lines, investor balances, project cost postings, inventory
-- valuation, IAS 41 facts, distributions, or accounting periods, and
-- never advances CropCycle lifecycle state.
--
-- Deferred (explicitly out of scope): stock-on-hand, warehouse
-- balances, InventoryMovement, StorageLocation, purchase orders,
-- procurement, receiving, supplier accounting, costing/valuation,
-- automatic financial postings, IAS 41 posting, HarvestEvent,
-- HarvestLot, crop output inventory, sale/dispatch, receivables,
-- weather provider integration, GIS/maps, offline synchronization,
-- generic workflow/rules engine, generic unit-conversion engine,
-- a second audit framework, a second approval engine, livestock, and
-- production deployment.

-- ===========================================================================
-- 0. Additive composite keys on already-merged GF-013 / GF-014 tables
--
--    These are the referential targets GF-015 needs so coherence is
--    guaranteed by the database, not only by application checks. They
--    are additive constraints in a new forward migration; no applied
--    migration is edited.
-- ===========================================================================
alter table public.crop_cycle_field_assignments
  add constraint crop_cycle_field_assignments_area_scope_key
  unique (id, organization_id, project_id, crop_cycle_id, field_id, assigned_area_unit);

alter table public.field_activities
  add constraint field_activities_input_scope_key
  unique (id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_type);

-- ===========================================================================
-- 1. Input Item — a controlled Agriculture input definition.
--
--    Not a global cross-sector product catalog and not an ERP item
--    master: it is scoped to one Agriculture project, carries no
--    price, supplier, accounting mapping, stock balance, or valuation.
-- ===========================================================================
create table public.input_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  category text not null check (category in ('SEED','FERTILIZER','CHEMICAL')),
  name text not null check (char_length(trim(name)) between 2 and 160),
  internal_reference text
    check (internal_reference is null or char_length(trim(internal_reference)) between 1 and 80),
  application_unit text not null check (char_length(trim(application_unit)) between 1 and 40),
  manufacturer text check (manufacturer is null or char_length(trim(manufacturer)) between 2 and 160),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  -- Referential targets used by input_lots and input_applications so
  -- unit and category coherence is enforced by the database.
  unique (id, organization_id, project_id, application_unit),
  unique (id, organization_id, project_id, category, application_unit),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create unique index input_items_project_name_key
  on public.input_items(organization_id, project_id, category, lower(trim(name)));
create index input_items_project_idx on public.input_items(project_id, category);

-- ===========================================================================
-- 2. Input Lot — a traceable lot/batch of an Input Item.
--
--    Identity and traceability only. `unit` is a stored copy of the
--    Input Item application unit and is held coherent by a composite
--    foreign key, not by an application-layer check.
-- ===========================================================================
create table public.input_lots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  input_item_id uuid not null,
  lot_reference text not null check (char_length(trim(lot_reference)) between 1 and 120),
  supplier_reference text
    check (supplier_reference is null or char_length(trim(supplier_reference)) between 2 and 200),
  manufactured_on date,
  expires_on date,
  unit text not null check (char_length(trim(unit)) between 1 and 40),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (manufactured_on is null or expires_on is null or manufactured_on <= expires_on),
  unique (organization_id, idempotency_key),
  unique (organization_id, input_item_id, lot_reference),
  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, input_item_id, unit),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  -- Database-enforced item/unit coherence: a lot cannot exist with a
  -- unit that differs from its Input Item application unit, and cannot
  -- point at an item in another organization or project.
  foreign key (input_item_id, organization_id, project_id, unit)
    references public.input_items(id, organization_id, project_id, application_unit)
    on delete restrict
);
create index input_lots_item_idx on public.input_lots(input_item_id);
create index input_lots_project_idx on public.input_lots(project_id, expires_on);

-- ===========================================================================
-- 3. Input Application — the immutable operational fact.
--
--    Proves a specific Input Lot was applied to a specific existing
--    Agriculture field assignment through a specific existing
--    FieldActivity whose type semantically applies an input.
--
--    Every scope column participates in a composite foreign key, so a
--    guessed id from another organization, project, crop cycle, field,
--    assignment, field activity, input item, or input lot cannot be
--    stored even by privileged SQL.
-- ===========================================================================
create table public.input_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid not null,
  assignment_id uuid not null,
  field_activity_id uuid not null,
  input_item_id uuid not null,
  input_lot_id uuid not null,
  input_category text not null check (input_category in ('SEED','FERTILIZER','CHEMICAL')),
  activity_type text not null check (activity_type in ('PLANT','FERTILIZE','SPRAY')),
  application_date date not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 40),
  applied_area_quantity numeric(20,6) not null check (applied_area_quantity > 0),
  applied_area_unit text not null check (applied_area_unit in ('M2','HECTARE','FEDDAN')),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  safety_note text check (safety_note is null or char_length(trim(safety_note)) between 1 and 2000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  -- Controlled category/activity mapping. SCOUT, IRRIGATE, WEED,
  -- PREPARE and OTHER can never consume an input application because
  -- activity_type is constrained above and must equal the referenced
  -- FieldActivity type through the composite foreign key below.
  constraint input_applications_category_activity_map check (
    (input_category = 'SEED'       and activity_type = 'PLANT')
    or (input_category = 'FERTILIZER' and activity_type = 'FERTILIZE')
    or (input_category = 'CHEMICAL'   and activity_type = 'SPRAY')
  ),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (crop_cycle_id, organization_id, project_id)
    references public.crop_cycles(id, organization_id, project_id) on delete restrict,
  foreign key (field_id, organization_id, project_id)
    references public.fields(id, organization_id, project_id) on delete restrict,
  -- Assignment coherence AND applied-area unit coherence in one key:
  -- the applied area unit must be the assignment's own area unit.
  foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id, applied_area_unit)
    references public.crop_cycle_field_assignments(
      id, organization_id, project_id, crop_cycle_id, field_id, assigned_area_unit
    ) on delete restrict,
  -- Field activity coherence AND activity-type coherence in one key.
  foreign key (
    field_activity_id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_type
  ) references public.field_activities(
    id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_type
  ) on delete restrict,
  -- Item coherence AND category/unit coherence in one key.
  foreign key (input_item_id, organization_id, project_id, input_category, unit)
    references public.input_items(id, organization_id, project_id, category, application_unit)
    on delete restrict,
  -- Lot coherence AND item/unit coherence in one key.
  foreign key (input_lot_id, organization_id, project_id, input_item_id, unit)
    references public.input_lots(id, organization_id, project_id, input_item_id, unit)
    on delete restrict
);
create index input_applications_project_idx
  on public.input_applications(project_id, application_date desc);
create index input_applications_activity_idx on public.input_applications(field_activity_id);
create index input_applications_lot_idx on public.input_applications(input_lot_id);

-- ===========================================================================
-- 4. Table-boundary invariants that a foreign key cannot express.
--
--    Defence in depth: the commands below already enforce these, but a
--    BEFORE INSERT trigger keeps them true for any direct INSERT.
-- ===========================================================================
create or replace function public.gf015_guard_input_application_invariants()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_assignment record;
  v_lot record;
begin
  select * into v_assignment
    from public.crop_cycle_field_assignments a
   where a.id = new.assignment_id
     and a.organization_id = new.organization_id
   for share;
  if not found then
    raise exception 'crop cycle field assignment not found for input application';
  end if;
  if new.applied_area_unit <> v_assignment.assigned_area_unit then
    raise exception 'applied area unit (%) must match the assignment area unit (%)',
      new.applied_area_unit, v_assignment.assigned_area_unit;
  end if;
  if new.applied_area_quantity > v_assignment.assigned_area_quantity then
    raise exception 'applied area exceeds the assigned area: applied=%, assigned=%, unit=%',
      new.applied_area_quantity, v_assignment.assigned_area_quantity, v_assignment.assigned_area_unit;
  end if;

  select * into v_lot
    from public.input_lots l
   where l.id = new.input_lot_id
     and l.organization_id = new.organization_id
   for share;
  if not found then
    raise exception 'input lot not found for input application';
  end if;
  if v_lot.expires_on is not null and new.application_date > v_lot.expires_on then
    raise exception 'input lot expired on % and cannot be applied on %',
      v_lot.expires_on, new.application_date;
  end if;
  return new;
end $$;

drop trigger if exists input_applications_invariants on public.input_applications;
create trigger input_applications_invariants
  before insert on public.input_applications
  for each row execute function public.gf015_guard_input_application_invariants();

-- Append-only / immutable facts. GF-015 keeps the catalog surface as
-- narrow as possible: correction of an Input Item or Input Lot
-- definition is not required by this slice and is therefore not
-- implemented. When a correction workflow is genuinely needed it will
-- be added as an explicit slice with its own reversal semantics.
create or replace function public.gf015_guard_input_applications_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'input applications are append-only';
end $$;
drop trigger if exists input_applications_no_change on public.input_applications;
create trigger input_applications_no_change
  before update or delete on public.input_applications
  for each row execute function public.gf015_guard_input_applications_append_only();

create or replace function public.gf015_guard_input_catalog_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'input catalog definitions are immutable once recorded';
end $$;
drop trigger if exists input_items_no_change on public.input_items;
create trigger input_items_no_change
  before update or delete on public.input_items
  for each row execute function public.gf015_guard_input_catalog_immutable();
drop trigger if exists input_lots_no_change on public.input_lots;
create trigger input_lots_no_change
  before update or delete on public.input_lots
  for each row execute function public.gf015_guard_input_catalog_immutable();

-- ===========================================================================
-- 5. Server-authoritative commands
--
--    Numeric values are normalized to the stored precision before
--    hashing (`::numeric(20,6)::text`) so the request hash represents
--    the payload that is actually stored. '2.5' and '2.500' are the
--    same canonical payload and replay idempotently; they are not a
--    false mismatch caused by presentation formatting.
-- ===========================================================================

-- 5.1 create_input_item
create or replace function public.create_input_item(
  p_organization_id uuid,
  p_project_id uuid,
  p_category text,
  p_name text,
  p_internal_reference text,
  p_application_unit text,
  p_manufacturer text,
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
  if p_category is null or p_category not in ('SEED','FERTILIZER','CHEMICAL') then
    raise exception 'invalid input category';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid input name';
  end if;
  if p_internal_reference is not null
     and char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_application_unit is null
     or char_length(trim(p_application_unit)) not between 1 and 40 then
    raise exception 'invalid application unit';
  end if;
  if p_manufacturer is not null
     and char_length(trim(p_manufacturer)) not between 2 and 160 then
    raise exception 'invalid manufacturer';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 1 and 2000 then
    raise exception 'invalid notes';
  end if;

  select encode(digest(
    p_project_id::text || '|' || p_category || '|' || trim(p_name) || '|'
    || coalesce(trim(p_internal_reference), '') || '|' || trim(p_application_unit) || '|'
    || coalesce(trim(p_manufacturer), '') || '|' || coalesce(trim(p_notes), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf015-input-item:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.input_items
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Explicit natural-key check so a genuine duplicate definition is
  -- reported as a domain error instead of leaking a constraint name.
  if exists (
    select 1 from public.input_items
     where organization_id = p_organization_id
       and project_id = p_project_id
       and category = p_category
       and lower(trim(name)) = lower(trim(p_name))
  ) then
    raise exception 'input item already exists for this project and category';
  end if;

  insert into public.input_items(
    organization_id, project_id, category, name, internal_reference,
    application_unit, manufacturer, notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_category, trim(p_name),
    nullif(trim(p_internal_reference), ''), trim(p_application_unit),
    nullif(trim(p_manufacturer), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'INPUT_ITEM_CREATED', 'input_item', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'category', p_category,
      'application_unit', trim(p_application_unit)
    )
  );
  return v_id;
end $$;

-- 5.2 create_input_lot
--
-- The organization is supplied and membership-checked; the project and
-- the unit are derived from the referenced Input Item so the browser
-- can never assert a project, tenant, or unit of its own.
create or replace function public.create_input_lot(
  p_organization_id uuid,
  p_input_item_id uuid,
  p_lot_reference text,
  p_supplier_reference text,
  p_manufactured_on date,
  p_expires_on date,
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
  v_item record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select * into v_item
    from public.input_items i
   where i.id = p_input_item_id
     and i.organization_id = p_organization_id;
  if not found then raise exception 'input item not found'; end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = v_item.project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  if p_lot_reference is null
     or char_length(trim(p_lot_reference)) not between 1 and 120 then
    raise exception 'invalid lot reference';
  end if;
  if p_supplier_reference is not null
     and char_length(trim(p_supplier_reference)) not between 2 and 200 then
    raise exception 'invalid supplier reference';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;
  if p_manufactured_on is not null and p_expires_on is not null
     and p_manufactured_on > p_expires_on then
    raise exception 'manufacture date must not be after the expiry date';
  end if;

  select encode(digest(
    v_item.project_id::text || '|' || p_input_item_id::text || '|' || trim(p_lot_reference) || '|'
    || coalesce(trim(p_supplier_reference), '') || '|' || coalesce(p_manufactured_on::text, '') || '|'
    || coalesce(p_expires_on::text, '') || '|' || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf015-input-lot:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.input_lots
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Explicit natural-key check so a genuine duplicate lot reference is
  -- reported as a domain error instead of leaking a constraint name.
  if exists (
    select 1 from public.input_lots
     where organization_id = p_organization_id
       and input_item_id = p_input_item_id
       and lot_reference = trim(p_lot_reference)
  ) then
    raise exception 'input lot reference already exists for this input item';
  end if;

  insert into public.input_lots(
    organization_id, project_id, input_item_id, lot_reference, supplier_reference,
    manufactured_on, expires_on, unit, evidence_reference,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_item.project_id, p_input_item_id, trim(p_lot_reference),
    nullif(trim(p_supplier_reference), ''), p_manufactured_on, p_expires_on,
    v_item.application_unit, nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'INPUT_LOT_CREATED', 'input_lot', v_id,
    jsonb_build_object(
      'project_id', v_item.project_id,
      'input_item_id', p_input_item_id,
      'lot_reference', trim(p_lot_reference),
      'expires_on', p_expires_on
    )
  );
  return v_id;
end $$;

-- 5.3 record_input_application
--
-- Project, crop cycle, field, assignment and activity type are all
-- derived from the referenced FieldActivity. The operator selects an
-- activity, an item, and a lot; the six scope identifiers the activity
-- already knows are never re-asserted by the browser.
--
-- p_unit and p_applied_area_unit are confirmations of what the client
-- displayed, not authoritative values: the server rejects them when
-- they disagree with the canonical Input Item unit or the canonical
-- assignment area unit.
create or replace function public.record_input_application(
  p_organization_id uuid,
  p_field_activity_id uuid,
  p_input_item_id uuid,
  p_input_lot_id uuid,
  p_application_date date,
  p_quantity numeric,
  p_unit text,
  p_applied_area_quantity numeric,
  p_applied_area_unit text,
  p_notes text,
  p_safety_note text,
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
  v_activity record;
  v_assignment record;
  v_item record;
  v_lot record;
  v_expected_activity text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  -- Scope is derived from the field activity, never from the browser.
  select * into v_activity
    from public.field_activities fa
   where fa.id = p_field_activity_id
     and fa.organization_id = p_organization_id;
  if not found then raise exception 'field activity not found'; end if;

  if not exists (
    select 1 from public.investment_projects p
     where p.id = v_activity.project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  if v_activity.activity_type not in ('PLANT','FERTILIZE','SPRAY') then
    raise exception 'field activity type % does not accept an input application',
      v_activity.activity_type;
  end if;

  select * into v_item
    from public.input_items i
   where i.id = p_input_item_id
     and i.organization_id = p_organization_id
     and i.project_id = v_activity.project_id;
  if not found then raise exception 'input item not found'; end if;

  v_expected_activity := case v_item.category
    when 'SEED' then 'PLANT'
    when 'FERTILIZER' then 'FERTILIZE'
    when 'CHEMICAL' then 'SPRAY'
  end;
  if v_expected_activity is distinct from v_activity.activity_type then
    raise exception 'input category % requires a % activity, not %',
      v_item.category, v_expected_activity, v_activity.activity_type;
  end if;

  select * into v_lot
    from public.input_lots l
   where l.id = p_input_lot_id
     and l.organization_id = p_organization_id
     and l.input_item_id = p_input_item_id;
  if not found then raise exception 'input lot not found'; end if;

  if p_application_date is null then
    raise exception 'invalid application date';
  end if;
  if v_lot.expires_on is not null and p_application_date > v_lot.expires_on then
    raise exception 'input lot expired on % and cannot be applied on %',
      v_lot.expires_on, p_application_date;
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'application quantity must be positive';
  end if;
  if p_unit is null or trim(p_unit) <> v_item.application_unit then
    raise exception 'application unit must be the input item unit (%)', v_item.application_unit;
  end if;

  select * into v_assignment
    from public.crop_cycle_field_assignments a
   where a.id = v_activity.assignment_id
     and a.organization_id = p_organization_id
   for share;
  if not found then raise exception 'crop cycle field assignment not found'; end if;

  if p_applied_area_quantity is null or p_applied_area_quantity <= 0 then
    raise exception 'applied area must be positive';
  end if;
  if p_applied_area_unit is null or trim(p_applied_area_unit) <> v_assignment.assigned_area_unit then
    raise exception 'applied area unit must be the assignment area unit (%)',
      v_assignment.assigned_area_unit;
  end if;
  if p_applied_area_quantity > v_assignment.assigned_area_quantity then
    raise exception 'applied area exceeds the assigned area: applied=%, assigned=%, unit=%',
      p_applied_area_quantity, v_assignment.assigned_area_quantity, v_assignment.assigned_area_unit;
  end if;

  if p_notes is not null and char_length(trim(p_notes)) not between 1 and 2000 then
    raise exception 'invalid notes';
  end if;
  if p_safety_note is not null and char_length(trim(p_safety_note)) not between 1 and 2000 then
    raise exception 'invalid safety note';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  -- Canonical payload hash. Numerics are normalized to the stored
  -- numeric(20,6) precision first so presentation formatting cannot
  -- create a false payload mismatch on an identical stored payload.
  select encode(digest(
    p_field_activity_id::text || '|' || p_input_item_id::text || '|' || p_input_lot_id::text || '|'
    || p_application_date::text || '|' || (p_quantity::numeric(20,6))::text || '|'
    || v_item.application_unit || '|' || (p_applied_area_quantity::numeric(20,6))::text || '|'
    || v_assignment.assigned_area_unit || '|' || coalesce(trim(p_notes), '') || '|'
    || coalesce(trim(p_safety_note), '') || '|' || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf015-input-application:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.input_applications
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.input_applications(
    organization_id, project_id, crop_cycle_id, field_id, assignment_id,
    field_activity_id, input_item_id, input_lot_id, input_category, activity_type,
    application_date, quantity, unit, applied_area_quantity, applied_area_unit,
    notes, safety_note, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_activity.project_id, v_activity.crop_cycle_id, v_activity.field_id,
    v_activity.assignment_id, p_field_activity_id, p_input_item_id, p_input_lot_id,
    v_item.category, v_activity.activity_type,
    p_application_date, p_quantity::numeric(20,6), v_item.application_unit,
    p_applied_area_quantity::numeric(20,6), v_assignment.assigned_area_unit,
    nullif(trim(p_notes), ''), nullif(trim(p_safety_note), ''),
    nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'INPUT_APPLICATION_RECORDED', 'input_application', v_id,
    jsonb_build_object(
      'project_id', v_activity.project_id,
      'field_activity_id', p_field_activity_id,
      'assignment_id', v_activity.assignment_id,
      'input_item_id', p_input_item_id,
      'input_lot_id', p_input_lot_id,
      'application_date', p_application_date
    )
  );
  return v_id;
end $$;

-- ===========================================================================
-- 6. Default-deny RLS, forced RLS, and read models
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array['input_items','input_lots','input_applications'] loop
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

create or replace view public.input_items_read with (security_invoker=on) as
select id, organization_id, project_id, category, name, internal_reference,
       application_unit, manufacturer, notes, created_by, created_at
from public.input_items;

create or replace view public.input_lots_read with (security_invoker=on) as
select l.id, l.organization_id, l.project_id, l.input_item_id,
       i.name as input_item_name, i.category as input_category,
       l.lot_reference, l.supplier_reference,
       l.manufactured_on, l.expires_on, l.unit, l.evidence_reference,
       case
         when l.expires_on is null then 'NO_EXPIRY'
         when l.expires_on < current_date then 'EXPIRED'
         else 'VALID'
       end as expiry_status,
       l.created_by, l.created_at
from public.input_lots l
join public.input_items i on i.id = l.input_item_id;

-- Operational read model for the workspace. The application rate is a
-- derived display value (quantity / applied area); it is deliberately
-- not stored a second time.
create or replace view public.input_applications_read with (security_invoker=on) as
select a.id, a.organization_id, a.project_id, a.crop_cycle_id, a.field_id,
       a.assignment_id, a.field_activity_id, a.input_item_id, a.input_lot_id,
       a.input_category, a.activity_type, a.application_date,
       a.quantity::text as quantity, a.unit,
       a.applied_area_quantity::text as applied_area_quantity, a.applied_area_unit,
       (a.quantity / a.applied_area_quantity)::numeric(20,6)::text as application_rate,
       i.name as input_item_name,
       l.lot_reference,
       l.expires_on,
       case
         when l.expires_on is null then 'NO_EXPIRY'
         when l.expires_on < a.application_date then 'EXPIRED'
         else 'VALID'
       end as lot_expiry_status,
       f.identifier as field_identifier,
       c.crop, c.season_reference,
       a.notes, a.safety_note, a.evidence_reference,
       a.recorded_by, a.created_at
from public.input_applications a
join public.input_items i on i.id = a.input_item_id
join public.input_lots l on l.id = a.input_lot_id
join public.fields f on f.id = a.field_id
join public.crop_cycles c on c.id = a.crop_cycle_id;

grant select on
  public.input_items_read, public.input_lots_read, public.input_applications_read
to authenticated;

-- ===========================================================================
-- 7. Command grants — authenticated only; anon and public are denied.
-- ===========================================================================
revoke all on function public.create_input_item(
  uuid,uuid,text,text,text,text,text,text,text
) from public, anon;
revoke all on function public.create_input_lot(
  uuid,uuid,text,text,date,date,text,text
) from public, anon;
revoke all on function public.record_input_application(
  uuid,uuid,uuid,uuid,date,numeric,text,numeric,text,text,text,text,text
) from public, anon;
grant execute on function
  public.create_input_item(uuid,uuid,text,text,text,text,text,text,text),
  public.create_input_lot(uuid,uuid,text,text,date,date,text,text),
  public.record_input_application(uuid,uuid,uuid,uuid,date,numeric,text,numeric,text,text,text,text,text)
to authenticated;

-- ===========================================================================
-- 8. pgcrypto schema compatibility
--
-- Same portable rule proven by 20260813000500 and reapplied by GF-013 /
-- GF-014: qualify digest() with the actual pgcrypto schema so the new
-- security-definer functions never depend on search_path for it.
-- ===========================================================================
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
    raise exception 'GF-015 requires the pgcrypto extension';
  end if;

  for v_record in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname in ('create_input_item','create_input_lot','record_input_application')
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
        raise exception 'failed to qualify pgcrypto digest in GF-015 commands';
      end if;
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
