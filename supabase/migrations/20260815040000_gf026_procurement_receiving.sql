-- GF-026 / R4 — Procurement Receiving: Receipt of goods against an approved
-- Purchase Order.
--
-- Builds on GF-025. Receiving is the physical receipt of quantities against
-- an APPROVED Purchase Order, recorded as append-only operational facts.
--
-- Financial boundary (deliberate): receiving is quantity-only. It carries NO
-- price, amount, currency, tax, invoice, payment, commitment, obligation, or
-- valuation, and creates NO journal batch, journal line, obligation, or
-- payment. It also creates no inventory balance or availability validation —
-- physical receipt records exist, but inventory valuation, stock balances, and
-- availability checks are deferred to a later bounded slice (and for the
-- Agriculture input path they were explicitly deferred to farm-ERP scope).
--
-- Control boundary: only an APPROVED purchase order may receive. Per order
-- line, the cumulative received quantity may never exceed the ordered
-- quantity. The unit is derived server-side from the order line (never
-- asserted by the browser). Receipts and their lines are append-only.

-- ===========================================================================
-- 0. Composite-FK support: purchase_order_lines needs (id, organization_id).
--    (id is already a PK, so this constraint only adds a supporting index.)
-- ===========================================================================
alter table public.purchase_order_lines
  add constraint purchase_order_lines_id_org_key unique (id, organization_id);

-- ===========================================================================
-- 1. Purchase Receipts (project-scoped, tied to an APPROVED purchase order)
-- ===========================================================================
create table public.purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  received_at timestamptz not null default now(),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  received_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (purchase_order_id, organization_id)
    references public.purchase_orders(id, organization_id) on delete restrict,
  unique (id, organization_id),
  unique (organization_id, idempotency_key)
);

create table public.purchase_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_receipt_id uuid not null references public.purchase_receipts(id) on delete restrict,
  purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete restrict,
  quantity_received numeric(20,6) not null check (quantity_received > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 20),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 1000),
  created_at timestamptz not null default now(),
  unique (id, purchase_receipt_id),
  foreign key (purchase_receipt_id, organization_id)
    references public.purchase_receipts(id, organization_id) on delete restrict,
  foreign key (purchase_order_line_id, organization_id)
    references public.purchase_order_lines(id, organization_id) on delete restrict
);

create index purchase_receipts_org_project_idx on public.purchase_receipts(organization_id, project_id);
create index purchase_receipts_po_idx on public.purchase_receipts(purchase_order_id);
create index purchase_receipt_lines_receipt_idx on public.purchase_receipt_lines(purchase_receipt_id);
create index purchase_receipt_lines_oline_idx on public.purchase_receipt_lines(purchase_order_line_id);

-- ===========================================================================
-- 2. Invariant guards (second layer; the RPC enforces the same rules).
-- ===========================================================================

-- Only an APPROVED purchase order can receive.
create or replace function public.gf026_guard_receipt_po_approved() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
declare
  v_status text;
begin
  select o.status into v_status from public.purchase_orders o
   where o.id = new.purchase_order_id and o.organization_id = new.organization_id;
  if v_status is null then raise exception 'purchase order not found'; end if;
  if v_status <> 'APPROVED' then
    raise exception 'purchase order must be approved before receiving';
  end if;
  return new;
end $$;

-- Receipt line unit must equal the order line unit, and the cumulative
-- received quantity per order line must never exceed the ordered quantity.
create or replace function public.gf026_guard_receipt_line() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
declare
  v_ordered numeric;
  v_unit text;
  v_received numeric;
begin
  select l.quantity, l.unit into v_ordered, v_unit
    from public.purchase_order_lines l
   where l.id = new.purchase_order_line_id
     and l.organization_id = new.organization_id;
  if v_ordered is null then raise exception 'purchase order line not found'; end if;
  if new.unit <> v_unit then raise exception 'receipt line unit must match order line unit'; end if;
  select coalesce(sum(rl.quantity_received), 0) into v_received
    from public.purchase_receipt_lines rl
   where rl.purchase_order_line_id = new.purchase_order_line_id
     and rl.organization_id = new.organization_id;
  if v_received + new.quantity_received > v_ordered then
    raise exception 'received quantity exceeds ordered quantity';
  end if;
  return new;
end $$;

-- Append-only: receipts and their lines are immutable operational facts.
create or replace function public.gf026_guard_append_only() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'append-only: this receiving fact cannot be modified or deleted';
end $$;

create trigger gf026_receipt_po_approved_guard
  before insert or update on public.purchase_receipts
  for each row execute function public.gf026_guard_receipt_po_approved();
create trigger gf026_receipt_line_guard
  before insert on public.purchase_receipt_lines
  for each row execute function public.gf026_guard_receipt_line();
create trigger gf026_receipt_append_only
  before update or delete on public.purchase_receipts
  for each row execute function public.gf026_guard_append_only();
create trigger gf026_receipt_line_append_only
  before update or delete on public.purchase_receipt_lines
  for each row execute function public.gf026_guard_append_only();

-- ===========================================================================
-- 3. Idempotent command: create_purchase_receipt
-- ===========================================================================
create or replace function public.create_purchase_receipt(
  p_organization_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_evidence_reference text,
  p_notes text default null,
  p_lines jsonb default '[]',
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_line jsonb;
  v_n numeric;
  v_unit text;
  v_ordered numeric;
  v_received numeric;
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
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then raise exception 'invalid notes'; end if;

  -- The purchase order must exist, belong to this organization/project, and be APPROVED.
  select o.status into v_unit from public.purchase_orders o
   where o.id = p_purchase_order_id and o.organization_id = p_organization_id and o.project_id = p_project_id;
  if v_unit is null then raise exception 'purchase order not found'; end if;
  if v_unit <> 'APPROVED' then raise exception 'purchase order must be approved before receiving'; end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one receipt line is required';
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_n := (v_line->>'quantity_received')::numeric;
    if v_n is null or v_n <= 0 then raise exception 'invalid receipt line quantity'; end if;
    select l.quantity, l.unit into v_ordered, v_unit
      from public.purchase_order_lines l
     where l.id = (v_line->>'purchase_order_line_id')::uuid
       and l.purchase_order_id = p_purchase_order_id
       and l.organization_id = p_organization_id;
    if v_ordered is null then raise exception 'order line not found for this order'; end if;
    select coalesce(sum(rl.quantity_received), 0) into v_received
      from public.purchase_receipt_lines rl
     where rl.purchase_order_line_id = (v_line->>'purchase_order_line_id')::uuid
       and rl.organization_id = p_organization_id;
    if v_received + v_n > v_ordered then raise exception 'received quantity exceeds ordered quantity'; end if;
  end loop;

  select encode(digest(
    p_purchase_order_id::text || '|' || trim(p_evidence_reference) || '|'
    || coalesce(trim(p_notes), '') || '|' || (p_lines::jsonb)::text,
    'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf026-receipt:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.purchase_receipts
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.purchase_receipts(
    organization_id, project_id, purchase_order_id, evidence_reference, notes,
    received_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_purchase_order_id, trim(p_evidence_reference),
    nullif(trim(p_notes), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    -- Unit is derived from the order line; the browser never asserts it.
    select l.unit into v_unit from public.purchase_order_lines l
     where l.id = (v_line->>'purchase_order_line_id')::uuid
       and l.organization_id = p_organization_id;
    insert into public.purchase_receipt_lines(
      organization_id, project_id, purchase_receipt_id, purchase_order_line_id,
      quantity_received, unit, notes
    ) values (
      p_organization_id, p_project_id, v_id, (v_line->>'purchase_order_line_id')::uuid,
      (v_line->>'quantity_received')::numeric, v_unit,
      nullif(trim(coalesce(v_line->>'notes','')), '')
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_RECEIPT_CREATED', 'purchase_receipt', v_id,
    jsonb_build_object('project_id', p_project_id, 'purchase_order_id', p_purchase_order_id));
  return v_id;
end $$;

revoke all on function public.create_purchase_receipt(uuid,uuid,uuid,text,text,jsonb,text) from public, anon;
grant execute on function public.create_purchase_receipt(uuid,uuid,uuid,text,text,jsonb,text) to authenticated;

-- ===========================================================================
-- 4. RLS: default-deny, tenant-safe, read views only.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['purchase_receipts', 'purchase_receipt_lines'] loop
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

-- ===========================================================================
-- 5. Read models.
-- ===========================================================================
-- Receipts with order reference and supplier name.
create or replace view public.purchase_receipts_read with (security_invoker=on) as
select r.id, r.organization_id, r.project_id, r.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       s.name as supplier_name,
       r.received_at, r.evidence_reference, r.notes, r.received_by, r.created_at,
       (select count(*) from public.purchase_receipt_lines l
         where l.purchase_receipt_id = r.id) as line_count
from public.purchase_receipts r
join public.purchase_orders o on o.id = r.purchase_order_id and o.organization_id = r.organization_id
left join public.procurement_suppliers s on s.id = o.supplier_id and s.organization_id = o.organization_id;

create or replace view public.purchase_receipt_lines_read with (security_invoker=on) as
select l.id, l.organization_id, l.project_id, l.purchase_receipt_id, l.purchase_order_line_id,
       ol.item_description,
       l.quantity_received::text as quantity_received, l.unit, l.notes, l.created_at
from public.purchase_receipt_lines l
join public.purchase_order_lines ol on ol.id = l.purchase_order_line_id and ol.organization_id = l.organization_id;

-- Receiving status per order line: ordered, received, remaining (derived).
create or replace view public.purchase_order_lines_receiving_read with (security_invoker=on) as
select ol.id as purchase_order_line_id, ol.organization_id, ol.project_id, ol.purchase_order_id,
       ol.item_description, ol.unit,
       ol.quantity::text as ordered_quantity,
       coalesce(sum(rl.quantity_received), 0)::text as received_quantity,
       (ol.quantity - coalesce(sum(rl.quantity_received), 0))::text as remaining_quantity
from public.purchase_order_lines ol
left join public.purchase_receipt_lines rl
  on rl.purchase_order_line_id = ol.id and rl.organization_id = ol.organization_id
group by ol.id, ol.organization_id, ol.project_id, ol.purchase_order_id, ol.item_description, ol.unit, ol.quantity;
