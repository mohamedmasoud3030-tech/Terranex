-- GF-025 / R4 — Procurement Foundation: Suppliers, Purchase Requests & Orders.
--
-- Shared Procurement & Shared Operations foundation (roadmap R4, first gate).
-- Suppliers are ORGANIZATION-scoped and shared across all projects in the
-- organization. Purchase Requests and Purchase Orders are PROJECT-scoped and
-- carry the sector-independent requisition-to-approval workflow that every
-- sector (Real Estate, Agriculture, Livestock) reuses, so sector slices never
-- reinvent procurement and supplier management.
--
-- Financial boundary (deliberate): this slice carries NO money, price, tax,
-- currency, invoice, payment, commitment, obligation, valuation, or inventory
-- quantity. Quantity is numeric(20,6) compatible-unit operational truth only.
-- Pricing/commitment, supplier invoicing/payment, and receiving/inventory
-- consumption are deferred to later bounded procurement slices (GF-026+) that
-- will link to the shared Finance Core (cost obligations / bank cash) exactly
-- as the existing sector slices do. This slice never creates a journal batch,
-- journal line, obligation, or payment, and never invents a financial amount.
--
-- Approval model: DRAFT -> SUBMITTED -> APPROVED (or REJECTED). Submission
-- requires an active member; approval requires the organization OWNER and a
-- maker/checker split (approver <> requester). Guarded status transitions and
-- maker/checker are enforced on the persisted row so no write path bypasses it.
--
-- Workflow-transition idempotency: submit/approve commands are
-- replay-idempotent — each transition persists its command idempotency key
-- and request fingerprint exactly once on the header, a replay of the same
-- logical command with the same key returns the same result without a
-- duplicate audit event, and the same key with a different entity payload
-- fails closed with 'idempotency key payload mismatch'.
--
-- Structural coherence: request/order lines and the order's source request
-- are bound to their header's (id, project, organization) by composite
-- foreign keys, so no persisted line or source reference can ever point
-- across projects even if a future command contains a bug. The source
-- request's APPROVED state is enforced by a guard trigger.

-- ===========================================================================
-- 1. Suppliers (organization-scoped, shared across projects)
-- ===========================================================================
create table public.procurement_suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 160),
  tax_number text check (tax_number is null or char_length(trim(tax_number)) between 1 and 40),
  payment_terms text check (payment_terms is null or char_length(trim(payment_terms)) between 1 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key)
);

-- ===========================================================================
-- 2. Purchase Requests (project-scoped)
-- ===========================================================================
create table public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  internal_reference text not null check (char_length(trim(internal_reference)) between 1 and 80),
  description text check (description is null or char_length(trim(description)) between 1 and 2000),
  status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','APPROVED','REJECTED')),
  requested_by uuid not null references auth.users(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  rejection_reason text check (rejection_reason is null or char_length(trim(rejection_reason)) between 1 and 500),
  -- Workflow-transition idempotency evidence: each guarded transition records
  -- its command idempotency key and request fingerprint exactly once, so a
  -- response-loss retry of the same logical command replays the completed
  -- transition (same result, no duplicate audit event) instead of failing
  -- on state. Columns are filled only by the transition RPCs.
  submit_idempotency_key text
    check (submit_idempotency_key is null or char_length(submit_idempotency_key) between 8 and 120),
  submit_request_hash text
    check (submit_request_hash is null or char_length(submit_request_hash) = 64),
  approve_idempotency_key text
    check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text
    check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (status = 'DRAFT' or submitted_by is not null),
  check (status not in ('APPROVED','REJECTED') or approved_by is not null),
  check (status <> 'REJECTED' or rejection_reason is not null),
  -- maker/checker: the approver must differ from the requester.
  check (approved_by is null or approved_by <> requested_by),
  -- transition evidence must exist exactly when the transition happened
  check ((status = 'DRAFT') = (submit_idempotency_key is null and submit_request_hash is null)),
  check ((status in ('APPROVED','REJECTED')) = (approve_idempotency_key is not null and approve_request_hash is not null)),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  unique (id, organization_id),
  unique (id, project_id, organization_id),
  unique (organization_id, idempotency_key)
);

create unique index purchase_requests_org_submit_key_key
  on public.purchase_requests(organization_id, submit_idempotency_key)
  where submit_idempotency_key is not null;
create unique index purchase_requests_org_approve_key_key
  on public.purchase_requests(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;

create table public.purchase_request_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_request_id uuid not null references public.purchase_requests(id) on delete restrict,
  item_description text not null check (char_length(trim(item_description)) between 2 and 160),
  quantity numeric(20,6) not null check (quantity > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 20),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 1000),
  created_at timestamptz not null default now(),
  unique (id, purchase_request_id),
  -- Structural coherence: the header id + project + organization must match
  -- the request header, so a line can never declare a different project than
  -- its header even if a future command contains a bug.
  foreign key (purchase_request_id, project_id, organization_id)
    references public.purchase_requests(id, project_id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

-- ===========================================================================
-- 3. Purchase Orders (project-scoped; optional supplier; optional source PR)
-- ===========================================================================
create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  internal_reference text not null check (char_length(trim(internal_reference)) between 1 and 80),
  supplier_id uuid references public.procurement_suppliers(id) on delete restrict,
  source_purchase_request_id uuid,
  description text check (description is null or char_length(trim(description)) between 1 and 2000),
  status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','APPROVED','REJECTED','CANCELLED')),
  -- No wall-clock-relative CHECK lives here: an order created today is a
  -- valid historical order tomorrow. The "not before the command date" rule
  -- is enforced at the command boundary during creation only.
  expected_delivery_date date,
  requested_by uuid not null references auth.users(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  rejection_reason text check (rejection_reason is null or char_length(trim(rejection_reason)) between 1 and 500),
  -- Workflow-transition idempotency evidence (same contract as purchase_requests).
  submit_idempotency_key text
    check (submit_idempotency_key is null or char_length(submit_idempotency_key) between 8 and 120),
  submit_request_hash text
    check (submit_request_hash is null or char_length(submit_request_hash) = 64),
  approve_idempotency_key text
    check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text
    check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (status = 'DRAFT' or submitted_by is not null),
  check (status not in ('APPROVED','REJECTED') or approved_by is not null),
  check (status <> 'REJECTED' or rejection_reason is not null),
  check (status <> 'CANCELLED' or rejection_reason is not null),
  -- maker/checker: the approver must differ from the requester.
  check (approved_by is null or approved_by <> requested_by),
  -- transition evidence must exist exactly when the transition happened
  check ((status = 'DRAFT') = (submit_idempotency_key is null and submit_request_hash is null)),
  check ((status in ('APPROVED','REJECTED')) = (approve_idempotency_key is not null and approve_request_hash is not null)),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_id, organization_id)
    references public.procurement_suppliers(id, organization_id) on delete restrict,
  -- The source Purchase Request must belong to the SAME project and the same
  -- organization (structural coherence); its APPROVED state is enforced by
  -- gf025_guard_purchase_order_source_request (state is not FK-representable).
  foreign key (source_purchase_request_id, project_id, organization_id)
    references public.purchase_requests(id, project_id, organization_id) on delete restrict,
  unique (id, organization_id),
  unique (id, project_id, organization_id),
  unique (organization_id, idempotency_key)
);

create unique index purchase_orders_org_submit_key_key
  on public.purchase_orders(organization_id, submit_idempotency_key)
  where submit_idempotency_key is not null;
create unique index purchase_orders_org_approve_key_key
  on public.purchase_orders(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  item_description text not null check (char_length(trim(item_description)) between 2 and 160),
  quantity numeric(20,6) not null check (quantity > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 20),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 1000),
  created_at timestamptz not null default now(),
  unique (id, purchase_order_id),
  -- Structural coherence: the header id + project + organization must match
  -- the order header, so a line can never declare a different project than
  -- its header even if a future command contains a bug.
  foreign key (purchase_order_id, project_id, organization_id)
    references public.purchase_orders(id, project_id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

create index procurement_suppliers_org_idx on public.procurement_suppliers(organization_id);
create unique index procurement_suppliers_org_name_key on public.procurement_suppliers(organization_id, lower(trim(name)));
create index purchase_requests_org_project_idx on public.purchase_requests(organization_id, project_id);
create unique index purchase_requests_org_project_ref_key on public.purchase_requests(organization_id, project_id, lower(internal_reference));
create index purchase_request_lines_req_idx on public.purchase_request_lines(purchase_request_id);
create index purchase_orders_org_project_idx on public.purchase_orders(organization_id, project_id);
create unique index purchase_orders_org_project_ref_key on public.purchase_orders(organization_id, project_id, lower(internal_reference));
create index purchase_order_lines_order_idx on public.purchase_order_lines(purchase_order_id);

-- ===========================================================================
-- 4. Guard: only a submitted draft may be approved/rejected by an OWNER;
--    already-final documents cannot be edited (append-only operational facts).
-- ===========================================================================
create or replace function public.gf025_guard_purchase_request_state() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  if tg_op = 'UPDATE' and (old.status = 'APPROVED' or old.status = 'REJECTED') then
    raise exception 'purchase request is final and cannot be modified';
  end if;
  if new.status = old.status then
    raise exception 'no-op status transition';
  end if;
  if old.status = 'DRAFT' and new.status not in ('SUBMITTED') then
    raise exception 'draft may only be submitted';
  end if;
  if old.status = 'SUBMITTED' and new.status not in ('APPROVED','REJECTED') then
    raise exception 'submitted request may only be approved or rejected';
  end if;
  return new;
end $$;

create or replace function public.gf025_guard_purchase_order_state() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  if tg_op = 'UPDATE' and old.status in ('APPROVED','REJECTED','CANCELLED') then
    raise exception 'purchase order is final and cannot be modified';
  end if;
  if new.status = old.status then
    raise exception 'no-op status transition';
  end if;
  if old.status = 'DRAFT' and new.status not in ('SUBMITTED') then
    raise exception 'draft may only be submitted';
  end if;
  if old.status = 'SUBMITTED' and new.status not in ('APPROVED','REJECTED') then
    raise exception 'submitted order may only be approved or rejected';
  end if;
  return new;
end $$;

-- Immutability guards:
--  * line rows are fully append-only (no update, no delete);
--  * request/order headers may change status through the audited RPCs
--    (guarded by the state triggers above) but can never be deleted;
--  * suppliers (a shared master) can be edited but never deleted.
-- Source coherence guard: a Purchase Order may only source a Purchase
-- Request in the APPROVED state. Same-project/same-organization membership
-- is already enforced structurally by the composite foreign key on
-- (source_purchase_request_id, project_id, organization_id); this trigger
-- adds the state condition, which a foreign key cannot express. The source
-- request's state cannot change afterwards (final states are frozen by the
-- request state guard), so an insert/update-time check is sufficient.
create or replace function public.gf025_guard_purchase_order_source_request() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
declare
  v_status text;
begin
  if new.source_purchase_request_id is not null then
    select r.status into v_status
      from public.purchase_requests r
     where r.id = new.source_purchase_request_id
       and r.organization_id = new.organization_id;
    if v_status is null then
      raise exception 'source purchase request not found';
    end if;
    if v_status <> 'APPROVED' then
      raise exception 'source purchase request must be approved';
    end if;
  end if;
  return new;
end $$;

create trigger gf025_purchase_order_source_request_guard
  before insert or update of source_purchase_request_id on public.purchase_orders
  for each row execute function public.gf025_guard_purchase_order_source_request();

create or replace function public.gf025_guard_append_only() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'append-only: this procurement fact cannot be modified or deleted';
end $$;

create or replace function public.gf025_guard_no_delete() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'append-only: this procurement header cannot be deleted';
end $$;

create trigger gf025_purchase_request_state_guard
  before update on public.purchase_requests
  for each row execute function public.gf025_guard_purchase_request_state();
create trigger gf025_purchase_request_no_delete
  before delete on public.purchase_requests
  for each row execute function public.gf025_guard_no_delete();
create trigger gf025_purchase_request_line_append_only
  before update or delete on public.purchase_request_lines
  for each row execute function public.gf025_guard_append_only();

create trigger gf025_purchase_order_state_guard
  before update on public.purchase_orders
  for each row execute function public.gf025_guard_purchase_order_state();
create trigger gf025_purchase_order_no_delete
  before delete on public.purchase_orders
  for each row execute function public.gf025_guard_no_delete();
create trigger gf025_purchase_order_line_append_only
  before update or delete on public.purchase_order_lines
  for each row execute function public.gf025_guard_append_only();
create trigger gf025_supplier_no_delete
  before delete on public.procurement_suppliers
  for each row execute function public.gf025_guard_no_delete();

-- ===========================================================================
-- 5. Idempotent commands
-- ===========================================================================

-- 5.1 create_supplier — organization-scoped, shared across projects.
create or replace function public.create_supplier(
  p_organization_id uuid,
  p_name text,
  p_tax_number text,
  p_payment_terms text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
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
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid supplier name';
  end if;
  if p_tax_number is not null and char_length(trim(p_tax_number)) > 40 then
    raise exception 'invalid tax number';
  end if;
  if p_payment_terms is not null and char_length(trim(p_payment_terms)) > 200 then
    raise exception 'invalid payment terms';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then
    raise exception 'invalid notes';
  end if;

  select encode(digest(
    p_organization_id::text || '|' || trim(p_name) || '|'
    || coalesce(trim(p_tax_number), '') || '|' || coalesce(trim(p_payment_terms), '')
    || '|' || coalesce(trim(p_notes), ''),
    'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-supplier:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.procurement_suppliers
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.procurement_suppliers(
    organization_id, name, tax_number, payment_terms, notes, created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, trim(p_name), nullif(trim(p_tax_number), ''), nullif(trim(p_payment_terms), ''),
    nullif(trim(p_notes), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREATED', 'procurement_supplier', v_id,
    jsonb_build_object('name', trim(p_name)));
  return v_id;
end $$;

-- 5.2 create_purchase_request — request + lines atomically, project-scoped.
create or replace function public.create_purchase_request(
  p_organization_id uuid,
  p_project_id uuid,
  p_internal_reference text,
  p_description text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_line jsonb;
  v_n numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id and p.organization_id = p_organization_id
  ) then raise exception 'project not found'; end if;
  if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_description is not null and char_length(trim(p_description)) > 2000 then
    raise exception 'invalid description';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one request line is required';
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (v_line->>'item_description') is null
       or char_length(trim(v_line->>'item_description')) not between 2 and 160 then
      raise exception 'invalid request line item description';
    end if;
    v_n := (v_line->>'quantity')::numeric;
    if v_n is null or v_n <= 0 then raise exception 'invalid request line quantity'; end if;
    if (v_line->>'unit') is null or char_length(trim(v_line->>'unit')) not between 1 and 20 then
      raise exception 'invalid request line unit';
    end if;
  end loop;

  select encode(digest(
    p_project_id::text || '|' || trim(p_internal_reference) || '|'
    || coalesce(trim(p_description), '') || '|' || (p_lines::jsonb)::text,
    'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-pr:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.purchase_requests
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.purchase_requests(
    organization_id, project_id, internal_reference, description, requested_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_internal_reference), nullif(trim(p_description), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    insert into public.purchase_request_lines(
      organization_id, project_id, purchase_request_id, item_description, quantity, unit, notes
    ) values (
      p_organization_id, p_project_id, v_id,
      trim(v_line->>'item_description'), (v_line->>'quantity')::numeric, trim(v_line->>'unit'),
      nullif(trim(coalesce(v_line->>'notes','')), '')
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_REQUEST_CREATED', 'purchase_request', v_id,
    jsonb_build_object('project_id', p_project_id, 'internal_reference', trim(p_internal_reference)));
  return v_id;
end $$;

-- 5.3 submit_purchase_request — DRAFT -> SUBMITTED (replay-idempotent).
--
-- Idempotency contract (matches the repository command pattern): the first
-- execution performs the transition exactly once and persists its command
-- key + request fingerprint on the header; a replay of the same logical
-- command with the same key returns the same entity id without mutating
-- state or writing a second audit event; the same key with a different
-- entity payload fails closed with 'idempotency key payload mismatch'.
create or replace function public.submit_purchase_request(
  p_organization_id uuid,
  p_purchase_request_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := encode(digest(p_organization_id::text || '|'
    || p_purchase_request_id::text || '|submit', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-pr-submit:' || trim(p_idempotency_key), 0));

  -- Replay path: the same logical submission with the same key returns the
  -- already-completed result without a duplicate audit event.
  select * into v_existing from public.purchase_requests
   where organization_id = p_organization_id
     and submit_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.submit_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status into v_status from public.purchase_requests
   where id = p_purchase_request_id and organization_id = p_organization_id
   for update;
  if v_status is null then raise exception 'purchase request not found'; end if;
  if v_status <> 'DRAFT' then raise exception 'purchase request is not in draft'; end if;
  update public.purchase_requests
     set status = 'SUBMITTED', submitted_by = v_actor, submitted_at = now(),
         submit_idempotency_key = trim(p_idempotency_key),
         submit_request_hash = v_hash
   where id = p_purchase_request_id and organization_id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_REQUEST_SUBMITTED', 'purchase_request', p_purchase_request_id, '{}'::jsonb);
  return p_purchase_request_id;
end $$;

-- 5.4 approve_purchase_request — SUBMITTED -> APPROVED, OWNER + maker/checker
--     (replay-idempotent; same key/payload contract as the submit command).
create or replace function public.approve_purchase_request(
  p_organization_id uuid,
  p_purchase_request_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_status text;
  v_requested_by uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  perform public.s2_require_owner(p_organization_id);
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-pr-approve:' || p_purchase_request_id::text, 0));

  v_hash := encode(digest(p_organization_id::text || '|'
    || p_purchase_request_id::text || '|approve', 'sha256'), 'hex');

  -- Replay path: the same logical approval with the same key returns the
  -- already-completed result without a duplicate audit event.
  select * into v_existing from public.purchase_requests
   where organization_id = p_organization_id
     and approve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.approve_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status, requested_by into v_status, v_requested_by from public.purchase_requests
   where id = p_purchase_request_id and organization_id = p_organization_id
   for update;
  if v_status is null then raise exception 'purchase request not found'; end if;
  if v_status <> 'SUBMITTED' then raise exception 'purchase request is not submitted'; end if;
  if v_requested_by = v_actor then raise exception 'maker/checker: requester cannot approve'; end if;
  update public.purchase_requests
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key),
         approve_request_hash = v_hash
   where id = p_purchase_request_id and organization_id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_REQUEST_APPROVED', 'purchase_request', p_purchase_request_id, '{}'::jsonb);
  return p_purchase_request_id;
end $$;

-- 5.5 create_purchase_order — order + lines atomically; optional supplier, optional source PR.
create or replace function public.create_purchase_order(
  p_organization_id uuid,
  p_project_id uuid,
  p_internal_reference text,
  p_supplier_id uuid,
  p_source_purchase_request_id uuid,
  p_description text,
  p_expected_delivery_date date,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_line jsonb;
  v_n numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id and p.organization_id = p_organization_id
  ) then raise exception 'project not found'; end if;
  if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_supplier_id is not null and not exists (
    select 1 from public.procurement_suppliers s
     where s.id = p_supplier_id and s.organization_id = p_organization_id and s.status = 'ACTIVE'
  ) then raise exception 'active supplier not found'; end if;
  -- Source coherence: the referenced Purchase Request must belong to the
  -- same organization AND the same project AND be APPROVED. The database
  -- enforces the same rule structurally (composite foreign key + state
  -- guard trigger); this is the command-boundary validation with a
  -- user-facing error.
  if p_source_purchase_request_id is not null and not exists (
    select 1 from public.purchase_requests r
     where r.id = p_source_purchase_request_id
       and r.organization_id = p_organization_id
       and r.project_id = p_project_id
       and r.status = 'APPROVED'
  ) then raise exception 'source purchase request must belong to the same project and be approved'; end if;
  -- Delivery-date rule lives at the command boundary: a new order cannot
  -- carry a past expected delivery date, but stored historical orders keep
  -- their past dates forever (no volatile wall-clock CHECK on the table).
  if p_expected_delivery_date is not null and p_expected_delivery_date < current_date then
    raise exception 'expected delivery date cannot be in the past';
  end if;
  if p_description is not null and char_length(trim(p_description)) > 2000 then
    raise exception 'invalid description';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one order line is required';
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (v_line->>'item_description') is null
       or char_length(trim(v_line->>'item_description')) not between 2 and 160 then
      raise exception 'invalid order line item description';
    end if;
    v_n := (v_line->>'quantity')::numeric;
    if v_n is null or v_n <= 0 then raise exception 'invalid order line quantity'; end if;
    if (v_line->>'unit') is null or char_length(trim(v_line->>'unit')) not between 1 and 20 then
      raise exception 'invalid order line unit';
    end if;
  end loop;

  select encode(digest(
    p_project_id::text || '|' || trim(p_internal_reference) || '|'
    || coalesce(p_supplier_id::text, '') || '|' || coalesce(p_source_purchase_request_id::text, '')
    || '|' || coalesce(trim(p_description), '') || '|'
    || coalesce(p_expected_delivery_date::text, '') || '|' || (p_lines::jsonb)::text,
    'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-po:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.purchase_orders
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.purchase_orders(
    organization_id, project_id, internal_reference, supplier_id, source_purchase_request_id,
    description, expected_delivery_date, requested_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_internal_reference), p_supplier_id, p_source_purchase_request_id,
    nullif(trim(p_description), ''), p_expected_delivery_date, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    insert into public.purchase_order_lines(
      organization_id, project_id, purchase_order_id, item_description, quantity, unit, notes
    ) values (
      p_organization_id, p_project_id, v_id,
      trim(v_line->>'item_description'), (v_line->>'quantity')::numeric, trim(v_line->>'unit'),
      nullif(trim(coalesce(v_line->>'notes','')), '')
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_ORDER_CREATED', 'purchase_order', v_id,
    jsonb_build_object('project_id', p_project_id, 'internal_reference', trim(p_internal_reference)));
  return v_id;
end $$;

-- 5.6 submit_purchase_order — DRAFT -> SUBMITTED (replay-idempotent;
--     same key/payload contract as the request submit command).
create or replace function public.submit_purchase_order(
  p_organization_id uuid,
  p_purchase_order_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := encode(digest(p_organization_id::text || '|'
    || p_purchase_order_id::text || '|submit', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-po-submit:' || trim(p_idempotency_key), 0));

  -- Replay path: the same logical submission with the same key returns the
  -- already-completed result without a duplicate audit event.
  select * into v_existing from public.purchase_orders
   where organization_id = p_organization_id
     and submit_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.submit_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status into v_status from public.purchase_orders
   where id = p_purchase_order_id and organization_id = p_organization_id
   for update;
  if v_status is null then raise exception 'purchase order not found'; end if;
  if v_status <> 'DRAFT' then raise exception 'purchase order is not in draft'; end if;
  update public.purchase_orders
     set status = 'SUBMITTED', submitted_by = v_actor, submitted_at = now(),
         submit_idempotency_key = trim(p_idempotency_key),
         submit_request_hash = v_hash
   where id = p_purchase_order_id and organization_id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_ORDER_SUBMITTED', 'purchase_order', p_purchase_order_id, '{}'::jsonb);
  return p_purchase_order_id;
end $$;

-- 5.7 approve_purchase_order — SUBMITTED -> APPROVED, OWNER + maker/checker
--     (replay-idempotent; same key/payload contract as the request approve).
create or replace function public.approve_purchase_order(
  p_organization_id uuid,
  p_purchase_order_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_status text;
  v_requested_by uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  perform public.s2_require_owner(p_organization_id);
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-po-approve:' || p_purchase_order_id::text, 0));

  v_hash := encode(digest(p_organization_id::text || '|'
    || p_purchase_order_id::text || '|approve', 'sha256'), 'hex');

  -- Replay path: the same logical approval with the same key returns the
  -- already-completed result without a duplicate audit event.
  select * into v_existing from public.purchase_orders
   where organization_id = p_organization_id
     and approve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.approve_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status, requested_by into v_status, v_requested_by from public.purchase_orders
   where id = p_purchase_order_id and organization_id = p_organization_id
   for update;
  if v_status is null then raise exception 'purchase order not found'; end if;
  if v_status <> 'SUBMITTED' then raise exception 'purchase order is not submitted'; end if;
  if v_requested_by = v_actor then raise exception 'maker/checker: requester cannot approve'; end if;
  update public.purchase_orders
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key),
         approve_request_hash = v_hash
   where id = p_purchase_order_id and organization_id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_ORDER_APPROVED', 'purchase_order', p_purchase_order_id, '{}'::jsonb);
  return p_purchase_order_id;
end $$;

revoke all on function public.create_supplier(uuid,text,text,text,text,text) from public, anon;
revoke all on function public.create_purchase_request(uuid,uuid,text,text,jsonb,text) from public, anon;
revoke all on function public.submit_purchase_request(uuid,uuid,text) from public, anon;
revoke all on function public.approve_purchase_request(uuid,uuid,text) from public, anon;
revoke all on function public.create_purchase_order(uuid,uuid,text,uuid,uuid,text,date,jsonb,text) from public, anon;
revoke all on function public.submit_purchase_order(uuid,uuid,text) from public, anon;
revoke all on function public.approve_purchase_order(uuid,uuid,text) from public, anon;
grant execute on function public.create_supplier(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.create_purchase_request(uuid,uuid,text,text,jsonb,text) to authenticated;
grant execute on function public.submit_purchase_request(uuid,uuid,text) to authenticated;
grant execute on function public.approve_purchase_request(uuid,uuid,text) to authenticated;
grant execute on function public.create_purchase_order(uuid,uuid,text,uuid,uuid,text,date,jsonb,text) to authenticated;
grant execute on function public.submit_purchase_order(uuid,uuid,text) to authenticated;
grant execute on function public.approve_purchase_order(uuid,uuid,text) to authenticated;

-- ===========================================================================
-- 6. RLS: default-deny, tenant-safe. Only security_invoker read views are
--    exposed; direct writes are reserved to the audited RPCs.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'procurement_suppliers', 'purchase_requests', 'purchase_request_lines',
    'purchase_orders', 'purchase_order_lines'
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

-- 7. Read models (projected, supplier-linked, no financial amounts).
create or replace view public.procurement_suppliers_read with (security_invoker=on) as
select id, organization_id, name, tax_number, payment_terms, notes, status, created_by, created_at
from public.procurement_suppliers;

create or replace view public.purchase_requests_read with (security_invoker=on) as
select id, organization_id, project_id, internal_reference, description, status,
       requested_by, submitted_by, submitted_at, approved_by, approved_at, rejection_reason,
       created_at,
       (select count(*) from public.purchase_request_lines l
         where l.purchase_request_id = r.id) as line_count
from public.purchase_requests r;

create or replace view public.purchase_request_lines_read with (security_invoker=on) as
select id, organization_id, project_id, purchase_request_id,
       item_description, quantity::text as quantity, unit, notes, created_at
from public.purchase_request_lines;

create or replace view public.purchase_orders_read with (security_invoker=on) as
select o.id, o.organization_id, o.project_id, o.internal_reference,
       o.supplier_id, s.name as supplier_name,
       o.source_purchase_request_id,
       o.description, o.status, o.expected_delivery_date,
       o.requested_by, o.submitted_by, o.submitted_at, o.approved_by, o.approved_at,
       o.rejection_reason, o.created_at,
       (select count(*) from public.purchase_order_lines l
         where l.purchase_order_id = o.id) as line_count
from public.purchase_orders o
left join public.procurement_suppliers s on s.id = o.supplier_id and s.organization_id = o.organization_id;

create or replace view public.purchase_order_lines_read with (security_invoker=on) as
select id, organization_id, project_id, purchase_order_id,
       item_description, quantity::text as quantity, unit, notes, created_at
from public.purchase_order_lines;

-- Canonical read path: the operator UI reads through the security_invoker
-- views as `authenticated`; the views themselves must be granted to the
-- authenticated role (RLS on the underlying tables still applies per
-- caller). Without this grant the application read path fails at runtime.
grant select on
  public.procurement_suppliers_read,
  public.purchase_requests_read,
  public.purchase_request_lines_read,
  public.purchase_orders_read,
  public.purchase_order_lines_read
to authenticated;

-- ===========================================================================
-- 8. pgcrypto schema qualification (GF-025 commands)
--    Terranex keeps SECURITY DEFINER search_path locked to pg_catalog,public.
--    pgcrypto may live in `public` (local replay) or `extensions` (hosted
--    Supabase); rewrite the unqualified digest() calls in this slice's
--    commands to the owning schema, matching the repo convention.
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
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;

  for v_record in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.proname in (
         'create_supplier','create_purchase_request','submit_purchase_request',
         'approve_purchase_request','create_purchase_order','submit_purchase_order',
         'approve_purchase_order'
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
        raise exception 'failed to qualify pgcrypto digest in GF-025 commands';
      end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat$;
