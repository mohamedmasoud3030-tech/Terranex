-- GF-016 / Agriculture Harvest & Inventory Flow Foundation.
--
-- Bounded operational slice that extends the Agriculture chain from
--
--   Farm → Field → CropCycle → Assignment → Field Activity / Input Application
--
-- to
--
--   Farm → Field → CropCycle → Assignment
--        → Field Activity / Input Application
--        → Harvest Event → Harvest Lot → Storage Location → Inventory Movement
--
-- This slice combines Harvest Event, Harvest Lot, basic harvest-output
-- storage, append-only inventory movements, and current harvest-lot
-- quantity by storage location into one bounded vertical slice.
--
-- Intentional boundary (architecture, not missing work):
--
--   GF-016 tracks physical harvest-output quantity only. It is NOT
--   procurement, purchase ordering, supplier accounting, input
--   receiving, input-stock management, warehouse ERP, valuation,
--   costing, IAS 41 posting, sales, receivables, or general accounting.
--   Sale/dispatch and Agriculture profitability are the final slice.
--
-- GF-015 input lots remain identity/traceability records, not stock
-- records. GF-016 does NOT retrofit an inventory balance onto input
-- lots and does NOT claim InputApplication now validates input-stock
-- availability. There is still no input purchase/receipt/opening-stock
-- workflow, so an input balance would be fabricated.
--
-- Recording a harvest never advances CropCycle lifecycle state. A
-- Harvest Event may only be recorded while its CropCycle is HARVESTING;
-- the operator uses the existing explicit lifecycle-transition command
-- to reach that state. No second lifecycle engine is introduced.
--
-- Deferred (explicitly out of scope): SALE_ISSUE movement, sale /
-- dispatch, buyers, invoicing, receivables, collection, revenue,
-- COGS, inventory valuation, IAS 41 posting, cycle profitability and
-- closeout, input-stock receiving/balance, purchase orders, supplier
-- liabilities, storage capacity planning, warehouse zones/bins, lot
-- splitting/merging, processing/manufacturing, generic unit-conversion,
-- offline sync, GIS, IoT, livestock, and production deployment.

-- ===========================================================================
-- 0. Additive composite key on the already-merged GF-013 assignment table.
--
--    This is the referential target the Harvest Event needs so that
--    organization / project / crop cycle / field / assignment coherence
--    is guaranteed by the database, not only by application checks. It
--    is an additive constraint in a new forward migration; no applied
--    migration is edited.
-- ===========================================================================
alter table public.crop_cycle_field_assignments
  add constraint crop_cycle_field_assignments_harvest_scope_key
  unique (id, organization_id, project_id, crop_cycle_id, field_id);

-- ===========================================================================
-- 1. Storage Location — the minimum object required to hold harvested output.
--
--    Organization + project + name + optional reference + optional notes.
--    Deliberately no capacity planning, warehouse zones, bins/racks,
--    temperature automation, staffing, procurement, or WMS workflow.
-- ===========================================================================
create table public.storage_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 160),
  internal_reference text
    check (internal_reference is null or char_length(trim(internal_reference)) between 1 and 80),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create unique index storage_locations_project_name_key
  on public.storage_locations(organization_id, project_id, lower(trim(name)));
create index storage_locations_project_idx on public.storage_locations(project_id);

-- ===========================================================================
-- 2. Harvest Event — the immutable operational fact of a real harvest.
--
--    Belongs coherently to organization, Agriculture project, CropCycle,
--    Field, and CropCycle-Field assignment. Carries harvest date, gross
--    and net accepted quantity, unit, optional grade, notes, evidence,
--    recorder and idempotency metadata.
--
--    gross_quantity > 0, net_quantity > 0, net_quantity <= gross_quantity.
--    Loss is derived (gross - net) in the read model; it is not stored a
--    second time so two separately-editable values can never contradict
--    the same physical fact.
-- ===========================================================================
create table public.harvest_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid not null,
  assignment_id uuid not null,
  harvest_date date not null,
  gross_quantity numeric(20,6) not null check (gross_quantity > 0),
  net_quantity numeric(20,6) not null check (net_quantity > 0),
  quantity_unit text not null check (char_length(trim(quantity_unit)) between 1 and 40),
  grade text check (grade is null or char_length(trim(grade)) between 1 and 80),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (net_quantity <= gross_quantity),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  -- Composite referential target used by harvest_lots so that scope,
  -- quantity-unit, net-quantity and harvest-date coherence are all
  -- enforced by the database in one key: a lot's initial quantity must
  -- equal its event's net quantity and its date must equal the event's.
  unique (id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, quantity_unit, net_quantity, harvest_date),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (crop_cycle_id, organization_id, project_id)
    references public.crop_cycles(id, organization_id, project_id) on delete restrict,
  foreign key (field_id, organization_id, project_id)
    references public.fields(id, organization_id, project_id) on delete restrict,
  -- Assignment coherence in one key: organization, project, crop cycle,
  -- field and assignment must all agree with the referenced assignment.
  foreign key (assignment_id, organization_id, project_id, crop_cycle_id, field_id)
    references public.crop_cycle_field_assignments(
      id, organization_id, project_id, crop_cycle_id, field_id
    ) on delete restrict
);
create index harvest_events_project_idx on public.harvest_events(project_id, harvest_date desc);
create index harvest_events_assignment_idx on public.harvest_events(assignment_id);

-- ===========================================================================
-- 3. Harvest Lot — the traceable output lot created at harvest.
--
--    One Harvest Event produces exactly one canonical Harvest Lot. The
--    lot's initial quantity equals the event's net quantity, and the lot
--    unit equals the event's quantity unit — both enforced by a composite
--    foreign key. A free-floating Harvest Lot unrelated to a Harvest
--    Event cannot exist.
-- ===========================================================================
create table public.harvest_lots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  crop_cycle_id uuid not null,
  field_id uuid not null,
  assignment_id uuid not null,
  harvest_event_id uuid not null,
  lot_reference text not null check (char_length(trim(lot_reference)) between 1 and 120),
  harvest_date date not null,
  initial_quantity numeric(20,6) not null check (initial_quantity > 0),
  quantity_unit text not null check (char_length(trim(quantity_unit)) between 1 and 40),
  grade text check (grade is null or char_length(trim(grade)) between 1 and 80),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  -- One event -> one canonical lot (grade/multi-lot splitting is a
  -- deliberately deferred future workflow).
  unique (harvest_event_id),
  unique (organization_id, project_id, lot_reference),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, quantity_unit),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  -- Event coherence AND scope AND unit AND quantity AND date coherence in
  -- one key: the lot cannot exist with a unit, scope, initial quantity,
  -- or date that differs from its event. `initial_quantity` is therefore
  -- database-enforced to equal the event's `net_quantity`, and the lot's
  -- `harvest_date` to equal the event's `harvest_date`.
  foreign key (
    harvest_event_id, organization_id, project_id,
    crop_cycle_id, field_id, assignment_id, quantity_unit,
    initial_quantity, harvest_date
  ) references public.harvest_events(
    id, organization_id, project_id,
    crop_cycle_id, field_id, assignment_id, quantity_unit,
    net_quantity, harvest_date
  ) on delete restrict
);
create index harvest_lots_project_idx on public.harvest_lots(project_id, harvest_date desc);
create index harvest_lots_event_idx on public.harvest_lots(harvest_event_id);

-- ===========================================================================
-- 4. Harvest-output Inventory Movement — the append-only truth for a lot.
--
--    There is deliberately NO mutable on_hand / available_quantity /
--    current_balance / remaining_quantity column. Current stock is
--    derived from the append-only movement history.
--
--    Movement semantics:
--      HARVEST_RECEIPT  from = null       to = storage
--      TRANSFER         from = storage A  to = storage B (A != B)
--      ADJUSTMENT_IN    from = null       to = storage
--      ADJUSTMENT_OUT   from = storage    to = null
--      SPOILAGE         from = storage    to = null
--
--    SALE_ISSUE is deliberately NOT implemented in GF-016.
-- ===========================================================================
create table public.harvest_inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  harvest_lot_id uuid not null,
  movement_type text not null check (movement_type in (
    'HARVEST_RECEIPT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','SPOILAGE'
  )),
  movement_date date not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 40),
  from_storage_id uuid,
  to_storage_id uuid,
  reason text check (reason is null or char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  -- Structural from/to semantics per movement type.
  check (
    (movement_type = 'HARVEST_RECEIPT' and from_storage_id is null and to_storage_id is not null)
    or (movement_type = 'TRANSFER'
        and from_storage_id is not null and to_storage_id is not null
        and from_storage_id <> to_storage_id)
    or (movement_type = 'ADJUSTMENT_IN' and from_storage_id is null and to_storage_id is not null)
    or (movement_type in ('ADJUSTMENT_OUT','SPOILAGE')
        and from_storage_id is not null and to_storage_id is null)
  ),
  -- Adjustments and spoilage require a meaningful reason; a transfer or
  -- receipt may carry an optional reason.
  check (movement_type in ('HARVEST_RECEIPT','TRANSFER')
         or (reason is not null and char_length(trim(reason)) between 3 and 500)),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  -- Lot coherence AND unit coherence in one key: the movement quantity
  -- must use the Harvest Lot's own unit.
  foreign key (harvest_lot_id, organization_id, project_id, unit)
    references public.harvest_lots(id, organization_id, project_id, quantity_unit)
    on delete restrict,
  -- Storage locations must belong to the same organization and the same
  -- Agriculture project as the lot (whose org/project are coerced by the
  -- lot key above). Cross-project / cross-tenant movement is impossible.
  foreign key (from_storage_id, organization_id, project_id)
    references public.storage_locations(id, organization_id, project_id) on delete restrict,
  foreign key (to_storage_id, organization_id, project_id)
    references public.storage_locations(id, organization_id, project_id) on delete restrict
);
create index harvest_inventory_movements_lot_idx
  on public.harvest_inventory_movements(harvest_lot_id, movement_date);
create index harvest_inventory_movements_from_idx
  on public.harvest_inventory_movements(from_storage_id);
create index harvest_inventory_movements_to_idx
  on public.harvest_inventory_movements(to_storage_id);
-- Exactly one initial HARVEST_RECEIPT per Harvest Lot, enforced
-- declaratively so even privileged SQL cannot append a second receipt.
create unique index harvest_inventory_movements_one_receipt
  on public.harvest_inventory_movements(harvest_lot_id)
  where movement_type = 'HARVEST_RECEIPT';

-- ===========================================================================
-- 5. Derived balances (never stored).
--
--    balance(location) = incoming quantity - outgoing quantity at that
--    location. Total lot balance = incoming - outgoing across all
--    locations. These are the only inventory truths; nothing mutable.
-- ===========================================================================
create or replace function public.harvest_lot_storage_balance(
  p_harvest_lot_id uuid,
  p_storage_id uuid
) returns numeric(20,6)
language sql
stable
set search_path = pg_catalog, public
as $$
  select coalesce(sum(m.quantity) filter (where m.to_storage_id = p_storage_id), 0)
       - coalesce(sum(m.quantity) filter (where m.from_storage_id = p_storage_id), 0)
  from public.harvest_inventory_movements m
  where m.harvest_lot_id = p_harvest_lot_id
$$;

create or replace function public.harvest_lot_total_balance(
  p_harvest_lot_id uuid
) returns numeric(20,6)
language sql
stable
set search_path = pg_catalog, public
as $$
  select coalesce(sum(m.quantity) filter (where m.to_storage_id is not null), 0)
       - coalesce(sum(m.quantity) filter (where m.from_storage_id is not null), 0)
  from public.harvest_inventory_movements m
  where m.harvest_lot_id = p_harvest_lot_id
$$;

-- The security_invoker read models below call these derived-balance
-- helpers, so authenticated (the operator role) needs EXECUTE on them.
-- They are read-only and read through the RLS-protected movement table, so
-- they expose exactly what the read views expose. anon and public are denied.
grant execute on function public.harvest_lot_storage_balance(uuid, uuid),
  public.harvest_lot_total_balance(uuid)
  to authenticated;
revoke all on function public.harvest_lot_storage_balance(uuid, uuid),
  public.harvest_lot_total_balance(uuid)
  from public, anon;

-- ===========================================================================
-- 6. Table-boundary invariants that a foreign key or CHECK cannot express.
--
--    Defence in depth: the commands below already enforce these, but the
--    BEFORE INSERT triggers keep them true for any direct INSERT.
-- ===========================================================================

-- 6.1 Harvest Event lifecycle rule: the CropCycle must be HARVESTING.
create or replace function public.gf016_guard_harvest_event_invariants()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_state text;
begin
  select public.agriculture_current_cycle_state(new.crop_cycle_id) into v_state;
  if v_state is distinct from 'HARVESTING' then
    raise exception 'crop cycle is not harvest-ready: current state %',
      coalesce(v_state, 'none');
  end if;
  return new;
end $$;

drop trigger if exists harvest_events_invariants on public.harvest_events;
create trigger harvest_events_invariants
  before insert on public.harvest_events
  for each row execute function public.gf016_guard_harvest_event_invariants();

-- 6.2 Inventory movement invariants: date cannot precede the harvest, and
--     no location may ever go negative. The lot row is locked FOR UPDATE
--     so concurrent movements against the same lot serialize and can
--     never overdraw the same location.
create or replace function public.gf016_guard_harvest_inventory_movement_invariants()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_lot record;
  v_available numeric(20,6);
begin
  select * into v_lot
    from public.harvest_lots l
   where l.id = new.harvest_lot_id
     and l.organization_id = new.organization_id
   for update;
  if not found then
    raise exception 'harvest lot not found for inventory movement';
  end if;
  if new.movement_date < v_lot.harvest_date then
    raise exception 'movement date % cannot precede the harvest date %',
      new.movement_date, v_lot.harvest_date;
  end if;
  if new.movement_type = 'HARVEST_RECEIPT' then
    if new.quantity <> v_lot.initial_quantity then
      raise exception 'harvest receipt quantity % must equal the lot initial quantity %',
        new.quantity, v_lot.initial_quantity;
    end if;
    if new.movement_date <> v_lot.harvest_date then
      raise exception 'harvest receipt date % must equal the harvest date %',
        new.movement_date, v_lot.harvest_date;
    end if;
  end if;
  if new.from_storage_id is not null then
    v_available := public.harvest_lot_storage_balance(new.harvest_lot_id, new.from_storage_id);
    if v_available < new.quantity then
      raise exception 'insufficient inventory: available %, requested %',
        v_available, new.quantity;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists harvest_inventory_movements_invariants on public.harvest_inventory_movements;
create trigger harvest_inventory_movements_invariants
  before insert on public.harvest_inventory_movements
  for each row execute function public.gf016_guard_harvest_inventory_movement_invariants();

-- Append-only / immutable operational facts.
create or replace function public.gf016_guard_harvest_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'harvest and inventory facts are append-only';
end $$;
drop trigger if exists harvest_events_no_change on public.harvest_events;
create trigger harvest_events_no_change
  before update or delete on public.harvest_events
  for each row execute function public.gf016_guard_harvest_append_only();
drop trigger if exists harvest_lots_no_change on public.harvest_lots;
create trigger harvest_lots_no_change
  before update or delete on public.harvest_lots
  for each row execute function public.gf016_guard_harvest_append_only();
drop trigger if exists harvest_inventory_movements_no_change on public.harvest_inventory_movements;
create trigger harvest_inventory_movements_no_change
  before update or delete on public.harvest_inventory_movements
  for each row execute function public.gf016_guard_harvest_append_only();

-- ===========================================================================
-- 7. Server-authoritative commands.
--
--    Numeric values are normalized to the stored numeric(20,6) precision
--    before hashing so presentation formatting is never a false payload
--    mismatch. Actor always comes from auth.uid(), never the browser.
-- ===========================================================================

-- 7.1 create_storage_location
create or replace function public.create_storage_location(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_internal_reference text,
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
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid storage location name';
  end if;
  if p_internal_reference is not null
     and char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 1 and 2000 then
    raise exception 'invalid notes';
  end if;

  select encode(digest(
    p_project_id::text || '|' || trim(p_name) || '|'
    || coalesce(trim(p_internal_reference), '') || '|' || coalesce(trim(p_notes), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf016-storage:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.storage_locations
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if exists (
    select 1 from public.storage_locations
     where organization_id = p_organization_id
       and project_id = p_project_id
       and lower(trim(name)) = lower(trim(p_name))
  ) then
    raise exception 'storage location already exists for this project';
  end if;

  insert into public.storage_locations(
    organization_id, project_id, name, internal_reference, notes,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_name),
    nullif(trim(p_internal_reference), ''), nullif(trim(p_notes), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'STORAGE_LOCATION_CREATED', 'storage_location', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'name', trim(p_name)
    )
  );
  return v_id;
end $$;

-- 7.2 record_harvest_event — one authoritative atomic command.
--
--     Validates membership, Agriculture project, CropCycle state
--     (HARVESTING), assignment coherence, and quantities, then creates
--     the Harvest Event, exactly one Harvest Lot, the lot's initial
--     HARVEST_RECEIPT into the selected storage location, and one audit
--     event, all in a single transaction. Project, crop cycle, field and
--     assignment are derived from the referenced assignment — never
--     asserted by the browser.
create or replace function public.record_harvest_event(
  p_organization_id uuid,
  p_assignment_id uuid,
  p_harvest_date date,
  p_gross_quantity numeric,
  p_net_quantity numeric,
  p_quantity_unit text,
  p_grade text,
  p_lot_reference text,
  p_destination_storage_id uuid,
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
  v_lot_id uuid;
  v_receipt_id uuid;
  v_hash text;
  v_existing record;
  v_assignment record;
  v_cycle record;
  v_destination record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  -- Scope is derived from the assignment, never from the browser.
  select * into v_assignment
    from public.crop_cycle_field_assignments a
   where a.id = p_assignment_id
     and a.organization_id = p_organization_id
   for update;
  if not found then raise exception 'crop cycle field assignment not found'; end if;

  if not exists (
    select 1 from public.investment_projects p
     where p.id = v_assignment.project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  select * into v_cycle
    from public.crop_cycles c
   where c.id = v_assignment.crop_cycle_id
     and c.organization_id = p_organization_id
     and c.project_id = v_assignment.project_id
   for update;
  if not found then raise exception 'crop cycle not found'; end if;

  if p_harvest_date is null then
    raise exception 'invalid harvest date';
  end if;
  if p_gross_quantity is null or p_gross_quantity <= 0 then
    raise exception 'harvest gross quantity must be positive';
  end if;
  if p_net_quantity is null or p_net_quantity <= 0 then
    raise exception 'harvest net quantity must be positive';
  end if;
  if p_net_quantity > p_gross_quantity then
    raise exception 'harvest net quantity must not exceed gross quantity';
  end if;
  if p_quantity_unit is null or char_length(trim(p_quantity_unit)) not between 1 and 40 then
    raise exception 'invalid harvest quantity unit';
  end if;
  if p_grade is not null and char_length(trim(p_grade)) not between 1 and 80 then
    raise exception 'invalid harvest grade';
  end if;
  if p_lot_reference is null
     or char_length(trim(p_lot_reference)) not between 1 and 120 then
    raise exception 'invalid lot reference';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) not between 1 and 2000 then
    raise exception 'invalid notes';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  select * into v_destination
    from public.storage_locations s
   where s.id = p_destination_storage_id
     and s.organization_id = p_organization_id
     and s.project_id = v_assignment.project_id
   for share;
  if not found then raise exception 'storage location not found'; end if;

  select encode(digest(
    p_assignment_id::text || '|' || p_harvest_date::text || '|'
    || (p_gross_quantity::numeric(20,6))::text || '|'
    || (p_net_quantity::numeric(20,6))::text || '|'
    || trim(p_quantity_unit) || '|' || coalesce(trim(p_grade), '') || '|'
    || trim(p_lot_reference) || '|' || p_destination_storage_id::text || '|'
    || coalesce(trim(p_notes), '') || '|' || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf016-harvest:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.harvest_events
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Lifecycle rule: harvest may only be recorded while HARVESTING. This
  -- check runs AFTER the idempotency replay so a true retry returns the
  -- original event even after the cycle has moved out of HARVESTING.
  if public.agriculture_current_cycle_state(v_cycle.id) is distinct from 'HARVESTING' then
    raise exception 'crop cycle is not harvest-ready: current state %',
      coalesce(public.agriculture_current_cycle_state(v_cycle.id), 'none');
  end if;

  -- Explicit natural-key check so a genuine duplicate lot reference is a
  -- domain error instead of leaking a constraint name.
  if exists (
    select 1 from public.harvest_lots
     where organization_id = p_organization_id
       and project_id = v_assignment.project_id
       and lot_reference = trim(p_lot_reference)
  ) then
    raise exception 'harvest lot reference already exists for this project';
  end if;

  insert into public.harvest_events(
    organization_id, project_id, crop_cycle_id, field_id, assignment_id,
    harvest_date, gross_quantity, net_quantity, quantity_unit,
    grade, notes, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_assignment.project_id, v_assignment.crop_cycle_id,
    v_assignment.field_id, p_assignment_id,
    p_harvest_date, p_gross_quantity::numeric(20,6), p_net_quantity::numeric(20,6),
    trim(p_quantity_unit),
    nullif(trim(p_grade), ''), nullif(trim(p_notes), ''),
    nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.harvest_lots(
    organization_id, project_id, crop_cycle_id, field_id, assignment_id,
    harvest_event_id, lot_reference, harvest_date, initial_quantity,
    quantity_unit, grade, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_assignment.project_id, v_assignment.crop_cycle_id,
    v_assignment.field_id, p_assignment_id,
    v_id, trim(p_lot_reference), p_harvest_date,
    p_net_quantity::numeric(20,6), trim(p_quantity_unit),
    nullif(trim(p_grade), ''),
    v_actor, 'lot-' || v_id::text,
    encode(digest(v_id::text || '|HARVEST_LOT', 'sha256'), 'hex')
  ) returning id into v_lot_id;

  -- Initial receipt: the lot's net quantity lands at the selected storage
  -- location on the harvest date.
  insert into public.harvest_inventory_movements(
    organization_id, project_id, harvest_lot_id, movement_type,
    movement_date, quantity, unit, from_storage_id, to_storage_id,
    reason, evidence_reference, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_assignment.project_id, v_lot_id, 'HARVEST_RECEIPT',
    p_harvest_date, p_net_quantity::numeric(20,6), trim(p_quantity_unit),
    null, p_destination_storage_id,
    null, nullif(trim(p_evidence_reference), ''),
    v_actor, 'receipt-' || v_lot_id::text,
    encode(digest(v_lot_id::text || '|HARVEST_RECEIPT', 'sha256'), 'hex')
  ) returning id into v_receipt_id;

  -- One audit event references the event, the lot, and the initial
  -- receipt movement; no three redundant audit rows.
  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'HARVEST_EVENT_RECORDED', 'harvest_event', v_id,
    jsonb_build_object(
      'project_id', v_assignment.project_id,
      'crop_cycle_id', v_assignment.crop_cycle_id,
      'field_id', v_assignment.field_id,
      'assignment_id', p_assignment_id,
      'harvest_lot_id', v_lot_id,
      'lot_reference', trim(p_lot_reference),
      'initial_receipt_movement_id', v_receipt_id,
      'destination_storage_id', p_destination_storage_id,
      'harvest_date', p_harvest_date,
      'net_quantity', p_net_quantity::numeric(20,6)
    )
  );
  return v_id;
end $$;

-- 7.3 transfer_harvest_inventory — move quantity between two locations of
--     the same lot. A transfer merely changes location; it never creates
--     quantity. The source must have sufficient available quantity.
create or replace function public.transfer_harvest_inventory(
  p_organization_id uuid,
  p_harvest_lot_id uuid,
  p_from_storage_id uuid,
  p_to_storage_id uuid,
  p_quantity numeric,
  p_movement_date date,
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
  v_lot record;
  v_from record;
  v_to record;
  v_available numeric(20,6);
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  -- Lock the lot row so concurrent movements against the same lot
  -- serialize and cannot overdraw the same location.
  select * into v_lot
    from public.harvest_lots l
   where l.id = p_harvest_lot_id
     and l.organization_id = p_organization_id
   for update;
  if not found then raise exception 'harvest lot not found'; end if;

  if not exists (
    select 1 from public.investment_projects p
     where p.id = v_lot.project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  if p_from_storage_id is null or p_to_storage_id is null
     or p_from_storage_id = p_to_storage_id then
    raise exception 'transfer source and destination storage must differ';
  end if;

  select * into v_from
    from public.storage_locations s
   where s.id = p_from_storage_id
     and s.organization_id = p_organization_id
     and s.project_id = v_lot.project_id
   for share;
  if not found then raise exception 'storage location not found'; end if;

  select * into v_to
    from public.storage_locations s
   where s.id = p_to_storage_id
     and s.organization_id = p_organization_id
     and s.project_id = v_lot.project_id
   for share;
  if not found then raise exception 'storage location not found'; end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'transfer quantity must be positive';
  end if;
  if p_movement_date is null then
    raise exception 'invalid movement date';
  end if;
  if p_movement_date < v_lot.harvest_date then
    raise exception 'movement date % cannot precede the harvest date %',
      p_movement_date, v_lot.harvest_date;
  end if;
  if p_reason is not null and char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid movement reason';
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  select encode(digest(
    p_harvest_lot_id::text || '|' || p_from_storage_id::text || '|'
    || p_to_storage_id::text || '|' || (p_quantity::numeric(20,6))::text || '|'
    || p_movement_date::text || '|' || coalesce(trim(p_reason), '') || '|'
    || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf016-transfer:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.harvest_inventory_movements
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Balance check runs AFTER the idempotency replay so a true retry
  -- returns the original movement even after the source balance changed.
  v_available := public.harvest_lot_storage_balance(p_harvest_lot_id, p_from_storage_id);
  if v_available < p_quantity then
    raise exception 'insufficient inventory: available %, requested %',
      v_available, p_quantity;
  end if;

  insert into public.harvest_inventory_movements(
    organization_id, project_id, harvest_lot_id, movement_type,
    movement_date, quantity, unit, from_storage_id, to_storage_id,
    reason, evidence_reference, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_lot.project_id, p_harvest_lot_id, 'TRANSFER',
    p_movement_date, p_quantity::numeric(20,6), v_lot.quantity_unit,
    p_from_storage_id, p_to_storage_id,
    nullif(trim(p_reason), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'HARVEST_INVENTORY_TRANSFERRED', 'harvest_inventory_movement', v_id,
    jsonb_build_object(
      'project_id', v_lot.project_id,
      'harvest_lot_id', p_harvest_lot_id,
      'from_storage_id', p_from_storage_id,
      'to_storage_id', p_to_storage_id,
      'quantity', p_quantity::numeric(20,6),
      'movement_date', p_movement_date
    )
  );
  return v_id;
end $$;

-- 7.4 record_harvest_inventory_adjustment — ADJUSTMENT_IN, ADJUSTMENT_OUT
--     or SPOILAGE against a lot at one storage location. A meaningful
--     reason is required; corrections are append-only.
create or replace function public.record_harvest_inventory_adjustment(
  p_organization_id uuid,
  p_harvest_lot_id uuid,
  p_storage_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_movement_date date,
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
  v_lot record;
  v_storage record;
  v_available numeric(20,6);
  v_event_type text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select * into v_lot
    from public.harvest_lots l
   where l.id = p_harvest_lot_id
     and l.organization_id = p_organization_id
   for update;
  if not found then raise exception 'harvest lot not found'; end if;

  if not exists (
    select 1 from public.investment_projects p
     where p.id = v_lot.project_id
       and p.organization_id = p_organization_id
       and p.sector = 'AGRICULTURE'
  ) then
    raise exception 'agriculture project not found';
  end if;

  if p_movement_type not in ('ADJUSTMENT_IN','ADJUSTMENT_OUT','SPOILAGE') then
    raise exception 'invalid harvest inventory movement type';
  end if;

  select * into v_storage
    from public.storage_locations s
   where s.id = p_storage_id
     and s.organization_id = p_organization_id
     and s.project_id = v_lot.project_id
   for share;
  if not found then raise exception 'storage location not found'; end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'adjustment quantity must be positive';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'adjustment reason is required';
  end if;
  if p_movement_date is null then
    raise exception 'invalid movement date';
  end if;
  if p_movement_date < v_lot.harvest_date then
    raise exception 'movement date % cannot precede the harvest date %',
      p_movement_date, v_lot.harvest_date;
  end if;
  if p_evidence_reference is not null
     and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  select encode(digest(
    p_harvest_lot_id::text || '|' || p_storage_id::text || '|'
    || p_movement_type || '|' || (p_quantity::numeric(20,6))::text || '|'
    || p_movement_date::text || '|' || trim(p_reason) || '|'
    || coalesce(trim(p_evidence_reference), ''),
    'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf016-adjustment:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.harvest_inventory_movements
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Balance check runs AFTER the idempotency replay so a true retry
  -- returns the original movement even after the balance changed.
  if p_movement_type in ('ADJUSTMENT_OUT','SPOILAGE') then
    v_available := public.harvest_lot_storage_balance(p_harvest_lot_id, p_storage_id);
    if v_available < p_quantity then
      raise exception 'insufficient inventory: available %, requested %',
        v_available, p_quantity;
    end if;
  end if;

  insert into public.harvest_inventory_movements(
    organization_id, project_id, harvest_lot_id, movement_type,
    movement_date, quantity, unit, from_storage_id, to_storage_id,
    reason, evidence_reference, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_lot.project_id, p_harvest_lot_id, p_movement_type,
    p_movement_date, p_quantity::numeric(20,6), v_lot.quantity_unit,
    case when p_movement_type in ('ADJUSTMENT_OUT','SPOILAGE') then p_storage_id else null end,
    case when p_movement_type = 'ADJUSTMENT_IN' then p_storage_id else null end,
    trim(p_reason), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  v_event_type := case
    when p_movement_type = 'SPOILAGE' then 'HARVEST_SPOILAGE_RECORDED'
    else 'HARVEST_INVENTORY_ADJUSTED'
  end;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, v_event_type, 'harvest_inventory_movement', v_id,
    jsonb_build_object(
      'project_id', v_lot.project_id,
      'harvest_lot_id', p_harvest_lot_id,
      'storage_id', p_storage_id,
      'movement_type', p_movement_type,
      'quantity', p_quantity::numeric(20,6),
      'movement_date', p_movement_date
    )
  );
  return v_id;
end $$;

-- ===========================================================================
-- 8. Default-deny RLS, forced RLS, and read models
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'storage_locations',
    'harvest_events',
    'harvest_lots',
    'harvest_inventory_movements'
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

create or replace view public.storage_locations_read with (security_invoker=on) as
select id, organization_id, project_id, name, internal_reference, notes,
       created_by, created_at
from public.storage_locations;

-- Harvest events: derived loss, lot reference and destination storage.
create or replace view public.harvest_events_read with (security_invoker=on) as
select e.id, e.organization_id, e.project_id, e.crop_cycle_id, e.field_id,
       e.assignment_id, e.harvest_date,
       e.gross_quantity::text as gross_quantity,
       e.net_quantity::text as net_quantity,
       (e.gross_quantity - e.net_quantity)::text as harvest_loss,
       e.quantity_unit, e.grade, e.notes, e.evidence_reference,
       e.recorded_by, e.recorded_at,
       c.crop, c.season_reference,
       f.identifier as field_identifier,
       l.id as harvest_lot_id,
       l.lot_reference,
       r.destination_storage_id,
       r.destination_storage_name
from public.harvest_events e
join public.crop_cycles c on c.id = e.crop_cycle_id
join public.fields f on f.id = e.field_id
join public.harvest_lots l on l.harvest_event_id = e.id
join lateral (
  select m.to_storage_id as destination_storage_id, s.name as destination_storage_name
  from public.harvest_inventory_movements m
  join public.storage_locations s on s.id = m.to_storage_id
  where m.harvest_lot_id = l.id and m.movement_type = 'HARVEST_RECEIPT'
  limit 1
) r on true;

-- Harvest lots: current total balance is derived, never stored.
create or replace view public.harvest_lots_read with (security_invoker=on) as
select l.id, l.organization_id, l.project_id, l.crop_cycle_id, l.field_id,
       l.assignment_id, l.harvest_event_id, l.lot_reference, l.harvest_date,
       l.initial_quantity::text as initial_quantity, l.quantity_unit, l.grade,
       public.harvest_lot_total_balance(l.id)::text as current_total_balance,
       c.crop, c.season_reference,
       f.identifier as field_identifier,
       l.created_by, l.created_at
from public.harvest_lots l
join public.crop_cycles c on c.id = l.crop_cycle_id
join public.fields f on f.id = l.field_id;

-- Inventory by location: derived balance per (lot, storage location).
create or replace view public.harvest_inventory_by_location_read with (security_invoker=on) as
select l.id as harvest_lot_id, l.organization_id, l.project_id,
       l.lot_reference, l.quantity_unit, l.grade,
       s.id as storage_id, s.name as storage_name,
       public.harvest_lot_storage_balance(l.id, s.id)::text as current_balance,
       (select max(m.movement_date)
        from public.harvest_inventory_movements m
        where m.harvest_lot_id = l.id
          and (m.from_storage_id = s.id or m.to_storage_id = s.id)) as last_movement_date
from public.harvest_lots l
join public.storage_locations s
  on s.organization_id = l.organization_id and s.project_id = l.project_id
where exists (
  select 1 from public.harvest_inventory_movements m
  where m.harvest_lot_id = l.id
    and (m.from_storage_id = s.id or m.to_storage_id = s.id)
);

-- Movement history: append-only operational facts with human-readable
-- from/to names.
create or replace view public.harvest_inventory_movements_read with (security_invoker=on) as
select m.id, m.organization_id, m.project_id, m.harvest_lot_id,
       m.movement_type, m.movement_date, m.quantity::text as quantity, m.unit,
       m.from_storage_id, m.to_storage_id,
       fs.name as from_storage_name, ts.name as to_storage_name,
       m.reason, m.evidence_reference, m.recorded_by, m.created_at,
       l.lot_reference
from public.harvest_inventory_movements m
join public.harvest_lots l on l.id = m.harvest_lot_id
left join public.storage_locations fs on fs.id = m.from_storage_id
left join public.storage_locations ts on ts.id = m.to_storage_id;

grant select on
  public.storage_locations_read,
  public.harvest_events_read,
  public.harvest_lots_read,
  public.harvest_inventory_by_location_read,
  public.harvest_inventory_movements_read
to authenticated;

-- ===========================================================================
-- 9. Command grants — authenticated only; anon and public are denied.
-- ===========================================================================
revoke all on function public.create_storage_location(
  uuid,uuid,text,text,text,text
) from public, anon;
revoke all on function public.record_harvest_event(
  uuid,uuid,date,numeric,numeric,text,text,text,uuid,text,text,text
) from public, anon;
revoke all on function public.transfer_harvest_inventory(
  uuid,uuid,uuid,uuid,numeric,date,text,text,text
) from public, anon;
revoke all on function public.record_harvest_inventory_adjustment(
  uuid,uuid,uuid,text,numeric,date,text,text,text
) from public, anon;
grant execute on function
  public.create_storage_location(uuid,uuid,text,text,text,text),
  public.record_harvest_event(uuid,uuid,date,numeric,numeric,text,text,text,uuid,text,text,text),
  public.transfer_harvest_inventory(uuid,uuid,uuid,uuid,numeric,date,text,text,text),
  public.record_harvest_inventory_adjustment(uuid,uuid,uuid,text,numeric,date,text,text,text)
to authenticated;

-- ===========================================================================
-- 10. pgcrypto schema compatibility
--
--     Same portable rule proven by 20260813000500 and reapplied by
--     GF-013 / GF-014 / GF-015: qualify digest() with the actual pgcrypto
--     schema so the new security-definer functions never depend on
--     search_path for it.
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
    raise exception 'GF-016 requires the pgcrypto extension';
  end if;

  for v_record in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname in (
        'create_storage_location','record_harvest_event',
        'transfer_harvest_inventory','record_harvest_inventory_adjustment'
      )
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
        raise exception 'failed to qualify pgcrypto digest in GF-016 commands';
      end if;
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
