-- R4 — Procurement Financial Integration.
--
-- Extends the existing Procurement operational core and reuses the S2-S7
-- Finance Core for payable posting, payment, cash and bank reconciliation.
-- There is no Procurement ledger and no Procurement payment table.
--
-- Accounting boundary:
--   * an APPROVED commercial Purchase Order is an unposted commitment;
--   * receiving remains an operational quantity fact only;
--   * an APPROVED supplier invoice creates and authorizes the existing
--     Finance Core cost_obligation (expense/WIP debit, supplier payable credit);
--   * shared Finance payment proposals enforce maker/checker and available
--     cash before project_payments and reconciliation_matches remain
--     authoritative for posted payment and bank reconciliation;
--   * posted corrections continue through reverse_journal_batch.

-- ===========================================================================
-- 1. Authoritative supplier Party and commercial Purchase Order terms.
--    Existing pre-R4 quantity-only rows remain readable but cannot be approved
--    financially until represented by a new complete commercial order.
-- ===========================================================================
alter table public.procurement_suppliers
  add column party_id uuid,
  add column party_link_idempotency_key text
    check (party_link_idempotency_key is null or char_length(party_link_idempotency_key) between 8 and 120),
  add column party_link_request_hash text
    check (party_link_request_hash is null or char_length(party_link_request_hash) = 64),
  add constraint procurement_suppliers_party_org_fkey
    foreign key (party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  add constraint procurement_suppliers_id_party_org_key
    unique (id, party_id, organization_id);

create unique index procurement_suppliers_org_party_key
  on public.procurement_suppliers(organization_id, party_id)
  where party_id is not null;
create unique index procurement_suppliers_org_party_link_key
  on public.procurement_suppliers(organization_id, party_link_idempotency_key)
  where party_link_idempotency_key is not null;

create or replace function public.r4_guard_supplier_party_link()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.party_id is not null and new.party_id is distinct from old.party_id then
    raise exception 'supplier financial party is immutable once linked';
  end if;
  if old.party_id is null and new.party_id is not null
     and (new.party_link_idempotency_key is null or new.party_link_request_hash is null) then
    raise exception 'supplier financial party link requires command evidence';
  end if;
  return new;
end $$;
create trigger r4_supplier_party_link_guard
before update of party_id on public.procurement_suppliers
for each row execute function public.r4_guard_supplier_party_link();

alter table public.purchase_orders
  add column currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  add column commercial_reference text
    check (commercial_reference is null or char_length(trim(commercial_reference)) between 3 and 200),
  add constraint purchase_orders_id_supplier_project_org_key
    unique (id, supplier_id, project_id, organization_id);

alter table public.purchase_order_lines
  add column unit_price_minor_units bigint
    check (unit_price_minor_units is null or unit_price_minor_units > 0),
  add column line_amount_minor_units bigint generated always as (
    case
      when unit_price_minor_units is null then null
      else (quantity * unit_price_minor_units)::bigint
    end
  ) stored,
  add constraint purchase_order_lines_exact_money_check check (
    unit_price_minor_units is null
    or quantity * unit_price_minor_units = trunc(quantity * unit_price_minor_units)
  ),
  add constraint purchase_order_lines_commercial_key
    unique (id, purchase_order_id, project_id, organization_id, unit_price_minor_units);

-- Commercial terms cannot be changed while transitioning a header. Lines were
-- already append-only in GF-025; this closes the corresponding header edge.
create or replace function public.r4_guard_purchase_order_commercial_immutable()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.supplier_id is distinct from old.supplier_id
     or new.project_id is distinct from old.project_id
     or new.organization_id is distinct from old.organization_id
     or new.currency is distinct from old.currency
     or new.commercial_reference is distinct from old.commercial_reference
     or new.expected_delivery_date is distinct from old.expected_delivery_date
     or new.source_purchase_request_id is distinct from old.source_purchase_request_id then
    raise exception 'purchase order commercial terms are immutable';
  end if;
  return new;
end $$;

create trigger r4_purchase_order_commercial_immutable
before update on public.purchase_orders
for each row execute function public.r4_guard_purchase_order_commercial_immutable();

-- The supplier profile is the operational identity; Party is the existing
-- authoritative financial counterparty. This owner-gated command upgrades an
-- earlier operational-only supplier without replacing either identity model.
create or replace function public.link_supplier_party(
  p_organization_id uuid,
  p_supplier_id uuid,
  p_party_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_supplier record;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := encode(digest(p_supplier_id::text || '|' || p_party_id::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r4-supplier-party:' || trim(p_idempotency_key), 0));

  select * into v_supplier
  from public.procurement_suppliers
  where organization_id = p_organization_id
    and party_link_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_supplier.party_link_request_hash IS DISTINCT FROM v_hash
       or v_supplier.id is distinct from p_supplier_id
       or v_supplier.party_id is distinct from p_party_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_supplier.id;
  end if;

  if not exists (
    select 1 from public.parties p
    where p.id = p_party_id and p.organization_id = p_organization_id
  ) then raise exception 'supplier party not found'; end if;

  select * into v_supplier
  from public.procurement_suppliers
  where id = p_supplier_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'supplier not found'; end if;
  if v_supplier.party_id is not null then
    raise exception 'supplier financial party is immutable once linked';
  end if;

  update public.procurement_suppliers
     set party_id = p_party_id,
         party_link_idempotency_key = trim(p_idempotency_key),
         party_link_request_hash = v_hash
   where id = p_supplier_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_PARTY_LINKED', 'procurement_supplier', p_supplier_id,
    jsonb_build_object('party_id', p_party_id));
  return p_supplier_id;
end $$;

-- Replace the quantity-only creation contract: every newly-created supplier
-- now names the existing authoritative Party used by Finance Core.
drop function public.create_supplier(uuid,text,text,text,text,text);
create or replace function public.create_supplier(
  p_organization_id uuid,
  p_party_id uuid,
  p_name text,
  p_tax_number text,
  p_payment_terms text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
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
  if not exists (
    select 1 from public.parties p where p.id = p_party_id and p.organization_id = p_organization_id
  ) then raise exception 'supplier party not found'; end if;
  if p_tax_number is not null and char_length(trim(p_tax_number)) > 40 then raise exception 'invalid tax number'; end if;
  if p_payment_terms is not null and char_length(trim(p_payment_terms)) > 200 then raise exception 'invalid payment terms'; end if;
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then raise exception 'invalid notes'; end if;

  v_hash := encode(digest(
    p_party_id::text || '|' || trim(p_name) || '|' || coalesce(trim(p_tax_number), '') || '|'
    || coalesce(trim(p_payment_terms), '') || '|' || coalesce(trim(p_notes), ''), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-supplier:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.procurement_suppliers
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash
       or v_existing.party_id is distinct from p_party_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.procurement_suppliers(
    organization_id, party_id, name, tax_number, payment_terms, notes,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_party_id, trim(p_name), nullif(trim(p_tax_number), ''),
    nullif(trim(p_payment_terms), ''), nullif(trim(p_notes), ''), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREATED', 'procurement_supplier', v_id,
    jsonb_build_object('name', trim(p_name), 'party_id', p_party_id));
  return v_id;
end $$;

-- Replace Purchase Order creation with exact commercial terms. The browser
-- supplies quantity and unit price only; all line/order totals are database
-- derived. The integrality check avoids inventing a rounding policy.
drop function public.create_purchase_order(uuid,uuid,text,uuid,uuid,text,date,jsonb,text);
create or replace function public.create_purchase_order(
  p_organization_id uuid,
  p_project_id uuid,
  p_internal_reference text,
  p_supplier_id uuid,
  p_source_purchase_request_id uuid,
  p_description text,
  p_expected_delivery_date date,
  p_currency text,
  p_commercial_reference text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_line jsonb;
  v_quantity numeric;
  v_unit_price bigint;
  v_project_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then raise exception 'invalid internal reference'; end if;
  if p_supplier_id is null or not exists (
    select 1 from public.procurement_suppliers s
    where s.id = p_supplier_id and s.organization_id = p_organization_id
      and s.status = 'ACTIVE' and s.party_id is not null
  ) then raise exception 'active financially linked supplier not found'; end if;
  select reporting_currency into v_project_currency
    from public.investment_projects
   where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;
  if p_commercial_reference is null or char_length(trim(p_commercial_reference)) not between 3 and 200 then
    raise exception 'commercial evidence reference is required';
  end if;
  if p_source_purchase_request_id is not null and not exists (
    select 1 from public.purchase_requests r
     where r.id = p_source_purchase_request_id and r.organization_id = p_organization_id
       and r.project_id = p_project_id and r.status = 'APPROVED'
  ) then raise exception 'source purchase request must belong to the same project and be approved'; end if;
  if p_expected_delivery_date is not null and p_expected_delivery_date < current_date then
    raise exception 'expected delivery date cannot be in the past';
  end if;
  if p_description is not null and char_length(trim(p_description)) > 2000 then raise exception 'invalid description'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'at least one order line is required'; end if;
  if jsonb_array_length(p_lines) > 50 then raise exception 'too many order lines'; end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (v_line->>'item_description') is null
       or char_length(trim(v_line->>'item_description')) not between 2 and 160 then raise exception 'invalid order line item description'; end if;
    begin
      v_quantity := (v_line->>'quantity')::numeric;
      v_unit_price := (v_line->>'unit_price_minor_units')::bigint;
    exception when others then
      raise exception 'invalid order line commercial amount';
    end;
    if v_quantity is null or v_quantity <= 0 then raise exception 'invalid order line quantity'; end if;
    if v_unit_price is null or v_unit_price <= 0 then raise exception 'invalid order line unit price'; end if;
    if v_quantity * v_unit_price <> trunc(v_quantity * v_unit_price) then
      raise exception 'order line amount must resolve to exact minor units';
    end if;
    if (v_line->>'unit') is null or char_length(trim(v_line->>'unit')) not between 1 and 20 then raise exception 'invalid order line unit'; end if;
  end loop;

  v_hash := encode(digest(
    p_project_id::text || '|' || trim(p_internal_reference) || '|' || p_supplier_id::text || '|'
    || coalesce(p_source_purchase_request_id::text, '') || '|' || coalesce(trim(p_description), '') || '|'
    || coalesce(p_expected_delivery_date::text, '') || '|' || p_currency || '|'
    || trim(p_commercial_reference) || '|' || p_lines::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-po:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.purchase_orders
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.purchase_orders(
    organization_id, project_id, internal_reference, supplier_id, source_purchase_request_id,
    description, expected_delivery_date, currency, commercial_reference,
    requested_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, trim(p_internal_reference), p_supplier_id, p_source_purchase_request_id,
    nullif(trim(p_description), ''), p_expected_delivery_date, p_currency, trim(p_commercial_reference),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    insert into public.purchase_order_lines(
      organization_id, project_id, purchase_order_id, item_description, quantity, unit,
      unit_price_minor_units, notes
    ) values (
      p_organization_id, p_project_id, v_id, trim(v_line->>'item_description'),
      (v_line->>'quantity')::numeric, trim(v_line->>'unit'),
      (v_line->>'unit_price_minor_units')::bigint,
      nullif(trim(coalesce(v_line->>'notes','')), '')
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_ORDER_CREATED', 'purchase_order', v_id,
    jsonb_build_object('project_id', p_project_id, 'internal_reference', trim(p_internal_reference),
      'supplier_id', p_supplier_id, 'currency', p_currency,
      'commercial_total_minor_units', (select sum(line_amount_minor_units) from public.purchase_order_lines where purchase_order_id = v_id)));
  return v_id;
end $$;

-- Approved PO = unposted commercial commitment. It does not create an expense,
-- payable or cash posting. The shared Finance read model below exposes it.
create or replace function public.approve_purchase_order(
  p_organization_id uuid,
  p_purchase_order_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_order record;
  v_total bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_hash := encode(digest(p_organization_id::text || '|' || p_purchase_order_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf025-po-approve:' || p_purchase_order_id::text, 0));

  select * into v_existing from public.purchase_orders
   where organization_id = p_organization_id and approve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.approve_request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_order from public.purchase_orders
   where id = p_purchase_order_id and organization_id = p_organization_id for update;
  if not found then raise exception 'purchase order not found'; end if;
  if v_order.status <> 'SUBMITTED' then raise exception 'purchase order is not submitted'; end if;
  if v_order.requested_by = v_actor then raise exception 'maker/checker: requester cannot approve'; end if;
  if v_order.supplier_id is null or v_order.currency is null or v_order.commercial_reference is null then
    raise exception 'purchase order commercial terms are incomplete';
  end if;
  if not exists (
    select 1 from public.procurement_suppliers s
    where s.id = v_order.supplier_id and s.organization_id = p_organization_id
      and s.status = 'ACTIVE' and s.party_id is not null
  ) then raise exception 'active financially linked supplier not found'; end if;
  if exists (
    select 1 from public.purchase_order_lines l
    where l.purchase_order_id = p_purchase_order_id
      and (l.unit_price_minor_units is null or l.line_amount_minor_units is null)
  ) then raise exception 'purchase order commercial lines are incomplete'; end if;
  select sum(line_amount_minor_units) into v_total
    from public.purchase_order_lines where purchase_order_id = p_purchase_order_id;
  if v_total is null or v_total <= 0 then raise exception 'purchase order commercial total must be positive'; end if;

  update public.purchase_orders
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key), approve_request_hash = v_hash
   where id = p_purchase_order_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PURCHASE_ORDER_APPROVED', 'purchase_order', p_purchase_order_id,
    jsonb_build_object('project_id', v_order.project_id, 'commitment_effect', 'UNPOSTED',
      'commercial_total_minor_units', v_total, 'currency', v_order.currency));
  return p_purchase_order_id;
end $$;

-- ===========================================================================
-- 2. Supplier invoice: immutable submitted commercial fact, exact match to
--    approved PO price and received quantity, then Finance Core payable.
-- ===========================================================================
create table public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  supplier_id uuid not null references public.procurement_suppliers(id) on delete restrict,
  party_id uuid not null references public.parties(id) on delete restrict,
  invoice_reference text not null check (char_length(trim(invoice_reference)) between 1 and 120),
  invoice_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  cost_treatment text not null check (cost_treatment in ('EXPENSE','CAPITALIZABLE_WIP')),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  status text not null default 'SUBMITTED' check (status in ('SUBMITTED','APPROVED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approve_idempotency_key text
    check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text
    check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  cost_obligation_id uuid,
  authorization_batch_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (approved_by is null or approved_by <> recorded_by),
  check (
    (status = 'SUBMITTED' and approved_by is null and approved_at is null
      and approve_idempotency_key is null and approve_request_hash is null
      and cost_obligation_id is null and authorization_batch_id is null)
    or
    (status = 'APPROVED' and approved_by is not null and approved_at is not null
      and approve_idempotency_key is not null and approve_request_hash is not null
      and cost_obligation_id is not null and authorization_batch_id is not null)
  ),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (purchase_order_id, supplier_id, project_id, organization_id)
    references public.purchase_orders(id, supplier_id, project_id, organization_id) on delete restrict,
  foreign key (supplier_id, party_id, organization_id)
    references public.procurement_suppliers(id, party_id, organization_id) on delete restrict,
  unique (id, organization_id),
  unique (id, project_id, organization_id),
  unique (id, purchase_order_id, project_id, organization_id),
  unique (organization_id, idempotency_key)
);

create unique index supplier_invoices_supplier_reference_key
  on public.supplier_invoices(organization_id, supplier_id, lower(trim(invoice_reference)));
create unique index supplier_invoices_org_approve_key
  on public.supplier_invoices(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;
create index supplier_invoices_project_idx on public.supplier_invoices(organization_id, project_id, invoice_date);
create index supplier_invoices_po_idx on public.supplier_invoices(purchase_order_id);

-- Composite support for a line to prove receipt/order/project/tenant coherence.
alter table public.purchase_receipt_lines
  add constraint purchase_receipt_lines_invoice_basis_key
    unique (id, purchase_order_line_id, purchase_order_id, project_id, organization_id);

create table public.supplier_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_invoice_id uuid not null references public.supplier_invoices(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete restrict,
  purchase_receipt_line_id uuid not null references public.purchase_receipt_lines(id) on delete restrict,
  quantity_invoiced numeric(20,6) not null check (quantity_invoiced > 0),
  unit_price_minor_units bigint not null check (unit_price_minor_units > 0),
  line_amount_minor_units bigint generated always as (
    (quantity_invoiced * unit_price_minor_units)::bigint
  ) stored,
  created_at timestamptz not null default now(),
  check (quantity_invoiced * unit_price_minor_units = trunc(quantity_invoiced * unit_price_minor_units)),
  foreign key (supplier_invoice_id, purchase_order_id, project_id, organization_id)
    references public.supplier_invoices(id, purchase_order_id, project_id, organization_id) on delete restrict,
  foreign key (purchase_order_line_id, purchase_order_id, project_id, organization_id, unit_price_minor_units)
    references public.purchase_order_lines(id, purchase_order_id, project_id, organization_id, unit_price_minor_units) on delete restrict,
  foreign key (purchase_receipt_line_id, purchase_order_line_id, purchase_order_id, project_id, organization_id)
    references public.purchase_receipt_lines(id, purchase_order_line_id, purchase_order_id, project_id, organization_id) on delete restrict,
  unique (supplier_invoice_id, purchase_receipt_line_id)
);
create index supplier_invoice_lines_receipt_idx on public.supplier_invoice_lines(purchase_receipt_line_id);
create index supplier_invoice_lines_order_line_idx on public.supplier_invoice_lines(purchase_order_line_id);

-- Finance Core provenance: the invoice-created obligation is still the one
-- authoritative cost_obligation used by journal/payment/reconciliation.
alter table public.cost_obligations
  add column source_supplier_invoice_id uuid,
  add constraint cost_obligations_id_project_org_key unique (id, project_id, organization_id),
  add constraint cost_obligations_supplier_invoice_fkey
    foreign key (source_supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict;
create unique index cost_obligations_supplier_invoice_key
  on public.cost_obligations(source_supplier_invoice_id)
  where source_supplier_invoice_id is not null;

alter table public.journal_batches
  add constraint journal_batches_id_project_org_key unique (id, project_id, organization_id);

alter table public.supplier_invoices
  add constraint supplier_invoices_obligation_project_org_fkey
    foreign key (cost_obligation_id, project_id, organization_id)
    references public.cost_obligations(id, project_id, organization_id) on delete restrict,
  add constraint supplier_invoices_batch_project_org_fkey
    foreign key (authorization_batch_id, project_id, organization_id)
    references public.journal_batches(id, project_id, organization_id) on delete restrict;

create or replace function public.r4_guard_supplier_invoice_transition()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status <> 'SUBMITTED' or new.status <> 'APPROVED' then
    raise exception 'supplier invoice is immutable after recording';
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.purchase_order_id is distinct from old.purchase_order_id
     or new.supplier_id is distinct from old.supplier_id
     or new.party_id is distinct from old.party_id
     or new.invoice_reference is distinct from old.invoice_reference
     or new.invoice_date is distinct from old.invoice_date
     or new.currency is distinct from old.currency
     or new.cost_treatment is distinct from old.cost_treatment
     or new.evidence_reference is distinct from old.evidence_reference
     or new.notes is distinct from old.notes
     or new.recorded_by is distinct from old.recorded_by
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash then
    raise exception 'supplier invoice commercial facts are immutable';
  end if;
  return new;
end $$;

create or replace function public.r4_guard_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'append-only: this procurement financial fact cannot be modified or deleted';
end $$;

create trigger supplier_invoice_transition_guard
before update on public.supplier_invoices
for each row execute function public.r4_guard_supplier_invoice_transition();
create trigger supplier_invoice_no_delete
before delete on public.supplier_invoices
for each row execute function public.r4_guard_append_only();
create trigger supplier_invoice_lines_append_only
before update or delete on public.supplier_invoice_lines
for each row execute function public.r4_guard_append_only();

create or replace function public.record_supplier_invoice(
  p_organization_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_currency text,
  p_cost_treatment text,
  p_evidence_reference text,
  p_notes text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_order record;
  v_line jsonb;
  v_receipt record;
  v_quantity numeric;
  v_unit_price bigint;
  v_total numeric := 0;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash := encode(digest(
    p_project_id::text || '|' || p_purchase_order_id::text || '|' || coalesce(trim(p_invoice_reference), '') || '|'
    || coalesce(p_invoice_date::text, '') || '|' || coalesce(p_currency, '') || '|'
    || coalesce(p_cost_treatment, '') || '|' || coalesce(trim(p_evidence_reference), '') || '|'
    || coalesce(trim(p_notes), '') || '|' || coalesce(p_lines::text, ''), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r4-supplier-invoice:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_invoices
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if p_invoice_reference is null or char_length(trim(p_invoice_reference)) not between 1 and 120 then raise exception 'invalid supplier invoice reference'; end if;
  if p_invoice_date is null then raise exception 'supplier invoice date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_cost_treatment not in ('EXPENSE','CAPITALIZABLE_WIP') then raise exception 'cost treatment must be EXPENSE or CAPITALIZABLE_WIP'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'supplier invoice evidence is required'; end if;
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then raise exception 'invalid notes'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'at least one supplier invoice line is required'; end if;
  if jsonb_array_length(p_lines) > 50 then raise exception 'too many supplier invoice lines'; end if;

  select o.*, s.party_id into v_order
    from public.purchase_orders o
    join public.procurement_suppliers s
      on s.id = o.supplier_id and s.organization_id = o.organization_id
   where o.id = p_purchase_order_id and o.project_id = p_project_id
     and o.organization_id = p_organization_id
   for update of o;
  if not found then raise exception 'purchase order not found'; end if;
  if v_order.status <> 'APPROVED' then raise exception 'supplier invoice requires an approved purchase order'; end if;
  if v_order.party_id is null then raise exception 'supplier financial party is not linked'; end if;
  if p_currency <> v_order.currency then raise exception 'supplier invoice currency must match purchase order'; end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    begin
      v_quantity := (v_line->>'quantity_invoiced')::numeric;
      v_unit_price := (v_line->>'unit_price_minor_units')::bigint;
    exception when others then
      raise exception 'invalid supplier invoice line amount';
    end;
    if v_quantity is null or v_quantity <= 0 then raise exception 'invalid supplier invoice line quantity'; end if;
    if v_unit_price is null or v_unit_price <= 0 then raise exception 'invalid supplier invoice unit price'; end if;
    if v_quantity * v_unit_price <> trunc(v_quantity * v_unit_price) then
      raise exception 'supplier invoice line amount must resolve to exact minor units';
    end if;

    select rl.id, rl.purchase_order_line_id, rl.quantity_received,
           ol.unit_price_minor_units
      into v_receipt
      from public.purchase_receipt_lines rl
      join public.purchase_order_lines ol
        on ol.id = rl.purchase_order_line_id and ol.organization_id = rl.organization_id
     where rl.id = (v_line->>'purchase_receipt_line_id')::uuid
       and rl.purchase_order_id = p_purchase_order_id
       and rl.project_id = p_project_id
       and rl.organization_id = p_organization_id
     for update of rl;
    if not found then raise exception 'receipt line not found for this purchase order'; end if;
    if v_receipt.unit_price_minor_units is null or v_unit_price <> v_receipt.unit_price_minor_units then
      raise exception 'supplier invoice unit price must exactly match purchase order';
    end if;
    if v_quantity > v_receipt.quantity_received then raise exception 'supplier invoice quantity exceeds received quantity'; end if;
    v_total := v_total + (v_quantity * v_unit_price);
  end loop;
  if v_total <= 0 or v_total <> trunc(v_total) then raise exception 'supplier invoice total must be exact positive minor units'; end if;

  insert into public.supplier_invoices(
    organization_id, project_id, purchase_order_id, supplier_id, party_id,
    invoice_reference, invoice_date, currency, cost_treatment, evidence_reference,
    notes, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_purchase_order_id, v_order.supplier_id, v_order.party_id,
    trim(p_invoice_reference), p_invoice_date, p_currency, p_cost_treatment,
    trim(p_evidence_reference), nullif(trim(p_notes), ''), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    select rl.purchase_order_line_id into v_receipt
      from public.purchase_receipt_lines rl
     where rl.id = (v_line->>'purchase_receipt_line_id')::uuid;
    insert into public.supplier_invoice_lines(
      organization_id, project_id, supplier_invoice_id, purchase_order_id,
      purchase_order_line_id, purchase_receipt_line_id, quantity_invoiced, unit_price_minor_units
    ) values (
      p_organization_id, p_project_id, v_id, p_purchase_order_id,
      v_receipt.purchase_order_line_id, (v_line->>'purchase_receipt_line_id')::uuid,
      (v_line->>'quantity_invoiced')::numeric, (v_line->>'unit_price_minor_units')::bigint
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_INVOICE_RECORDED', 'supplier_invoice', v_id,
    jsonb_build_object('project_id', p_project_id, 'purchase_order_id', p_purchase_order_id,
      'supplier_id', v_order.supplier_id, 'invoice_reference', trim(p_invoice_reference),
      'invoice_total_minor_units', v_total::bigint, 'currency', p_currency));
  return v_id;
end $$;

create or replace function public.approve_supplier_invoice(
  p_organization_id uuid,
  p_supplier_invoice_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_invoice record;
  v_total bigint;
  v_obligation_id uuid;
  v_batch_id uuid;
  v_obligation_hash text;
  v_description text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash := encode(digest(p_supplier_invoice_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r4-invoice-approve:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_invoices
   where organization_id = p_organization_id and approve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.approve_request_hash IS DISTINCT FROM v_hash
       or v_existing.id is distinct from p_supplier_invoice_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.cost_obligation_id;
  end if;

  select * into v_invoice from public.supplier_invoices
   where id = p_supplier_invoice_id and organization_id = p_organization_id for update;
  if not found then raise exception 'supplier invoice not found'; end if;
  if v_invoice.status <> 'SUBMITTED' then raise exception 'supplier invoice is not submitted'; end if;
  if v_invoice.recorded_by = v_actor then raise exception 'maker/checker: invoice recorder cannot approve'; end if;

  -- One PO lock serializes every approval consuming any receipt under it. This
  -- protects the exact receipt ceiling even when two invoices race.
  perform 1 from public.purchase_orders
   where id = v_invoice.purchase_order_id and organization_id = p_organization_id
   for update;

  if exists (
    with current_invoice as (
      select purchase_receipt_line_id, sum(quantity_invoiced) as quantity
      from public.supplier_invoice_lines
      where supplier_invoice_id = p_supplier_invoice_id
      group by purchase_receipt_line_id
    ), already_approved as (
      select il.purchase_receipt_line_id, sum(il.quantity_invoiced) as quantity
      from public.supplier_invoice_lines il
      join public.supplier_invoices i on i.id = il.supplier_invoice_id
      where i.status = 'APPROVED'
        and i.organization_id = p_organization_id
        and i.id <> p_supplier_invoice_id
      group by il.purchase_receipt_line_id
    )
    select 1
    from current_invoice ci
    join public.purchase_receipt_lines rl on rl.id = ci.purchase_receipt_line_id
    left join already_approved aa on aa.purchase_receipt_line_id = ci.purchase_receipt_line_id
    where ci.quantity + coalesce(aa.quantity, 0) > rl.quantity_received
  ) then raise exception 'supplier invoice quantity exceeds remaining received quantity'; end if;

  select sum(line_amount_minor_units) into v_total
    from public.supplier_invoice_lines where supplier_invoice_id = p_supplier_invoice_id;
  if v_total is null or v_total <= 0 then raise exception 'supplier invoice total must be positive'; end if;

  v_description := 'Supplier invoice ' || v_invoice.invoice_reference;
  v_obligation_hash := encode(digest(
    v_invoice.id::text || '|' || v_invoice.project_id::text || '|' || v_invoice.party_id::text || '|'
    || v_total::text || '|' || v_invoice.currency || '|' || v_invoice.invoice_date::text || '|'
    || v_invoice.cost_treatment, 'sha256'), 'hex');

  -- Reuse the authoritative Finance Core obligation and authorization posting.
  -- prepared_by remains the invoice recorder, preserving maker/checker provenance.
  insert into public.cost_obligations(
    organization_id, project_id, party_id, description, amount_minor_units,
    currency, transaction_date, cost_treatment, prepared_by, idempotency_key,
    request_hash, source_supplier_invoice_id
  ) values (
    p_organization_id, v_invoice.project_id, v_invoice.party_id, v_description,
    v_total, v_invoice.currency, v_invoice.invoice_date, v_invoice.cost_treatment,
    v_invoice.recorded_by, 'r4-invoice-obligation:' || v_invoice.id::text,
    v_obligation_hash, v_invoice.id
  ) returning id into v_obligation_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DRAFTED', 'cost_obligation', v_obligation_id,
    jsonb_build_object('project_id', v_invoice.project_id, 'party_id', v_invoice.party_id,
      'prepared_by', v_invoice.recorded_by, 'supplier_invoice_id', v_invoice.id, 'amount_minor_units', v_total,
      'currency', v_invoice.currency, 'cost_treatment', v_invoice.cost_treatment,
      'transaction_date', v_invoice.invoice_date));

  v_batch_id := public.authorize_cost_obligation(
    p_organization_id, v_obligation_id, 'r4-invoice-authorize:' || v_invoice.id::text);

  update public.supplier_invoices
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key), approve_request_hash = v_hash,
         cost_obligation_id = v_obligation_id, authorization_batch_id = v_batch_id
   where id = p_supplier_invoice_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_INVOICE_APPROVED', 'supplier_invoice', p_supplier_invoice_id,
    jsonb_build_object('project_id', v_invoice.project_id, 'purchase_order_id', v_invoice.purchase_order_id,
      'cost_obligation_id', v_obligation_id, 'authorization_batch_id', v_batch_id,
      'payable_minor_units', v_total, 'currency', v_invoice.currency));
  return v_obligation_id;
end $$;

-- ===========================================================================
-- 3. Shared Finance payment proposal, maker/checker and cash capacity.
--    The proposal is a Finance workflow fact; project_payments remains the
--    only immutable posted payment fact. No Procurement payment ledger exists.
-- ===========================================================================
alter table public.project_cash_accounts
  add constraint project_cash_accounts_id_project_org_key
    unique (id, project_id, organization_id);

create table public.cost_payment_proposals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  obligation_id uuid not null references public.cost_obligations(id) on delete restrict,
  cash_account_id uuid not null references public.project_cash_accounts(id) on delete restrict,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_date date not null,
  status text not null default 'PROPOSED' check (status in ('PROPOSED','APPROVED','POSTED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  project_payment_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  approval_idempotency_key text
    check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text
    check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (id, project_id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (obligation_id, project_id, organization_id)
    references public.cost_obligations(id, project_id, organization_id) on delete restrict,
  foreign key (cash_account_id, project_id, organization_id)
    references public.project_cash_accounts(id, project_id, organization_id) on delete restrict,
  constraint cost_payment_proposals_state_check check (
    (status = 'PROPOSED' and approved_by is null and approved_at is null
      and approval_idempotency_key is null and approval_request_hash is null
      and project_payment_id is null)
    or
    (status = 'APPROVED' and approved_by is not null and approved_at is not null
      and approved_by <> prepared_by and approval_idempotency_key is not null
      and approval_request_hash is not null and project_payment_id is null)
    or
    (status = 'POSTED' and approved_by is not null and approved_at is not null
      and approved_by <> prepared_by and approval_idempotency_key is not null
      and approval_request_hash is not null and project_payment_id is not null)
  )
);
create index cost_payment_proposals_project_status_idx
  on public.cost_payment_proposals(project_id, status, prepared_at);
create index cost_payment_proposals_obligation_idx
  on public.cost_payment_proposals(obligation_id, status);
create unique index cost_payment_proposals_org_approval_key
  on public.cost_payment_proposals(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;

alter table public.project_payments
  add column payment_proposal_id uuid,
  add constraint project_payments_proposal_org_fkey
    foreign key (payment_proposal_id, organization_id)
    references public.cost_payment_proposals(id, organization_id) on delete restrict;
create unique index project_payments_one_proposal
  on public.project_payments(payment_proposal_id)
  where payment_proposal_id is not null;
alter table public.cost_payment_proposals
  add constraint cost_payment_proposals_payment_org_fkey
    foreign key (project_payment_id, organization_id)
    references public.project_payments(id, organization_id) on delete restrict;

-- Only the two controlled approval transitions may update a proposal. Its
-- economics, maker and retry evidence are immutable from initial preparation.
create or replace function public.r4_guard_payment_proposal_transition()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'payment proposal is immutable; do not delete it';
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.obligation_id is distinct from old.obligation_id
     or new.cash_account_id is distinct from old.cash_account_id
     or new.amount_minor_units is distinct from old.amount_minor_units
     or new.currency is distinct from old.currency
     or new.payment_date is distinct from old.payment_date
     or new.prepared_by is distinct from old.prepared_by
     or new.prepared_at is distinct from old.prepared_at
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash
     or new.created_at is distinct from old.created_at then
    raise exception 'payment proposal commercial truth is immutable';
  end if;
  if old.status = 'PROPOSED' and new.status = 'APPROVED'
     and old.approved_by is null and new.approved_by is not null
     and old.approved_at is null and new.approved_at is not null
     and old.approval_idempotency_key is null and new.approval_idempotency_key is not null
     and old.approval_request_hash is null and new.approval_request_hash is not null
     and old.project_payment_id is null and new.project_payment_id is null then
    return new;
  end if;
  if old.status = 'APPROVED' and new.status = 'POSTED'
     and new.approved_by is not distinct from old.approved_by
     and new.approved_at is not distinct from old.approved_at
     and new.approval_idempotency_key is not distinct from old.approval_idempotency_key
     and new.approval_request_hash is not distinct from old.approval_request_hash
     and old.project_payment_id is null and new.project_payment_id is not null then
    return new;
  end if;
  raise exception 'invalid payment proposal transition';
end $$;
create trigger cost_payment_proposals_transition_guard
before update or delete on public.cost_payment_proposals
for each row execute function public.r4_guard_payment_proposal_transition();

-- Every newly posted Finance Core supplier payment must trace to an independently
-- approved proposal with exactly the same tenant, Project, account and money.
create or replace function public.r4_guard_project_payment_proposal()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
declare v_proposal public.cost_payment_proposals%rowtype;
begin
  if new.payment_proposal_id is null then
    raise exception 'direct payment posting disabled; approved payment proposal required';
  end if;
  select * into v_proposal from public.cost_payment_proposals
  where id = new.payment_proposal_id and organization_id = new.organization_id;
  if not found or v_proposal.status <> 'APPROVED' then
    raise exception 'payment requires an approved payment proposal';
  end if;
  if v_proposal.project_id is distinct from new.project_id
     or v_proposal.obligation_id is distinct from new.obligation_id
     or v_proposal.cash_account_id is distinct from new.cash_account_id
     or v_proposal.amount_minor_units is distinct from new.amount_minor_units
     or v_proposal.currency is distinct from new.currency
     or v_proposal.payment_date is distinct from new.payment_date
     or v_proposal.approved_by is distinct from new.paid_by
     or v_proposal.prepared_by = new.paid_by then
    raise exception 'payment does not match independently approved proposal';
  end if;
  return new;
end $$;
create trigger r4_project_payment_proposal_guard
before insert on public.project_payments
for each row execute function public.r4_guard_project_payment_proposal();

-- Payment posting itself locks and rechecks the cash account below.
-- Reversal semantics remain owned by the existing correction path.
create or replace function public.prepare_cost_payment(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_payment_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing public.cost_payment_proposals%rowtype;
  v_obligation public.cost_obligations%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_paid numeric;
  v_available bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  if p_payment_date is null then raise exception 'payment date required'; end if;

  v_hash := encode(digest(
    p_obligation_id::text || '|' || p_cash_account_id::text || '|'
    || p_amount_minor_units::text || '|' || p_payment_date::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':payment-proposal:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_payment_proposals
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash
       or v_existing.obligation_id is distinct from p_obligation_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.amount_minor_units is distinct from p_amount_minor_units
       or v_existing.payment_date is distinct from p_payment_date then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  -- Global lock order is cash account, then obligation. Approval uses the same
  -- order; different obligations competing for one account therefore serialize.
  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'cash account not found'; end if;
  select * into v_obligation from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'AUTHORIZED' then
    raise exception 'payment requires an authorized obligation';
  end if;
  if not exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'COST_OBLIGATION' and jb.source_id = v_obligation.id
      and jb.organization_id = p_organization_id
      and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
  ) then raise exception 'obligation authorization is reversed; no further payments'; end if;
  if v_account.project_id <> v_obligation.project_id then
    raise exception 'cash account must belong to the obligation project';
  end if;
  if v_account.currency <> v_obligation.currency then
    raise exception 'payment currency must match the cash account';
  end if;
  if exists (select 1 from public.accounting_periods p
             where p.organization_id = p_organization_id and p.project_id = v_obligation.project_id)
     and not exists (select 1 from public.accounting_periods p
                     where p.organization_id = p_organization_id and p.project_id = v_obligation.project_id
                       and p.status = 'OPEN' and p_payment_date between p.start_date and p.end_date) then
    raise exception 'no open accounting period covers payment date % for this project', p_payment_date;
  end if;

  select coalesce(sum(pp.amount_minor_units::numeric), 0) into v_paid
  from public.project_payments pp
  join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
  where pp.obligation_id = p_obligation_id and pp.organization_id = p_organization_id
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id);
  if v_paid + p_amount_minor_units::numeric > v_obligation.amount_minor_units::numeric then
    raise exception 'payment exceeds remaining payable';
  end if;
  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if p_amount_minor_units > v_available then
    raise exception 'payment exceeds available cash';
  end if;

  insert into public.cost_payment_proposals(
    organization_id, project_id, obligation_id, cash_account_id,
    amount_minor_units, currency, payment_date, prepared_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, v_obligation.project_id, v_obligation.id, v_account.id,
    p_amount_minor_units, v_obligation.currency, p_payment_date, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_PROPOSAL_PREPARED', 'cost_payment_proposal', v_id,
    jsonb_build_object('project_id', v_obligation.project_id, 'obligation_id', v_obligation.id,
      'cash_account_id', v_account.id, 'amount_minor_units', p_amount_minor_units,
      'currency', v_obligation.currency, 'payment_date', p_payment_date,
      'available_cash_minor_units_at_preparation', v_available));
  return v_id;
end $$;

create or replace function public.approve_cost_payment(
  p_organization_id uuid,
  p_payment_proposal_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_proposal public.cost_payment_proposals%rowtype;
  v_existing public.cost_payment_proposals%rowtype;
  v_obligation public.cost_obligations%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_hash text;
  v_paid numeric;
  v_available bigint;
  v_payment_id uuid;
  v_batch_id uuid;
  v_payable uuid;
  v_bank_cash uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  v_hash := encode(digest(p_payment_proposal_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':payment-approval:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_payment_proposals
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id is distinct from p_payment_proposal_id
       or v_existing.approval_request_hash is distinct from v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    if v_existing.status = 'POSTED' then return v_existing.project_payment_id; end if;
  end if;

  select * into v_proposal from public.cost_payment_proposals
  where id = p_payment_proposal_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'payment proposal not found'; end if;
  if v_proposal.status = 'POSTED' then
    if v_proposal.approval_idempotency_key is not distinct from trim(p_idempotency_key)
       and v_proposal.approval_request_hash is not distinct from v_hash then
      return v_proposal.project_payment_id;
    end if;
    raise exception 'payment proposal is already posted';
  end if;
  if v_proposal.status <> 'PROPOSED' then raise exception 'payment proposal is not pending'; end if;
  if v_proposal.prepared_by = v_actor then
    raise exception 'maker/checker: payment preparer cannot approve';
  end if;

  select * into v_account from public.project_cash_accounts
  where id = v_proposal.cash_account_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'cash account not found'; end if;
  select * into v_obligation from public.cost_obligations
  where id = v_proposal.obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'AUTHORIZED' then
    raise exception 'payment requires an authorized obligation';
  end if;
  if not exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'COST_OBLIGATION' and jb.source_id = v_obligation.id
      and jb.organization_id = p_organization_id
      and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
  ) then raise exception 'obligation authorization is reversed; no further payments'; end if;
  if v_account.project_id is distinct from v_proposal.project_id
     or v_account.currency is distinct from v_proposal.currency
     or v_obligation.project_id is distinct from v_proposal.project_id
     or v_obligation.currency is distinct from v_proposal.currency then
    raise exception 'payment proposal scope or currency no longer coherent';
  end if;
  if exists (select 1 from public.accounting_periods p
             where p.organization_id = p_organization_id and p.project_id = v_proposal.project_id)
     and not exists (select 1 from public.accounting_periods p
                     where p.organization_id = p_organization_id and p.project_id = v_proposal.project_id
                       and p.status = 'OPEN' and v_proposal.payment_date between p.start_date and p.end_date) then
    raise exception 'no open accounting period covers payment date % for this project', v_proposal.payment_date;
  end if;

  select coalesce(sum(pp.amount_minor_units::numeric), 0) into v_paid
  from public.project_payments pp
  join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
  where pp.obligation_id = v_proposal.obligation_id and pp.organization_id = p_organization_id
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id);
  if v_paid + v_proposal.amount_minor_units::numeric > v_obligation.amount_minor_units::numeric then
    raise exception 'payment exceeds remaining payable';
  end if;
  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if v_proposal.amount_minor_units > v_available then
    raise exception 'payment exceeds available cash';
  end if;

  update public.cost_payment_proposals
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
   where id = v_proposal.id;

  insert into public.project_payments(
    organization_id, project_id, obligation_id, cash_account_id,
    amount_minor_units, currency, payment_date, paid_by,
    idempotency_key, request_hash, payment_proposal_id
  ) values (
    p_organization_id, v_proposal.project_id, v_proposal.obligation_id, v_proposal.cash_account_id,
    v_proposal.amount_minor_units, v_proposal.currency, v_proposal.payment_date, v_actor,
    trim(p_idempotency_key), v_proposal.request_hash, v_proposal.id
  ) returning id into v_payment_id;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_bank_cash from public.semantic_accounts where role = 'BANK_CASH';
  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_proposal.project_id, 'PAYMENT', v_payment_id,
    v_proposal.payment_date, 'payment-batch-' || v_payment_id::text,
    v_proposal.request_hash, v_actor
  ) returning id into v_batch_id;
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_proposal.project_id, v_payable,
     v_proposal.amount_minor_units, 0, v_proposal.currency,
     null, v_proposal.obligation_id, v_obligation.party_id, v_proposal.payment_date),
    (v_batch_id, p_organization_id, v_proposal.project_id, v_bank_cash,
     0, v_proposal.amount_minor_units, v_proposal.currency,
     v_proposal.cash_account_id, null, null, v_proposal.payment_date);

  update public.cost_payment_proposals
     set status = 'POSTED', project_payment_id = v_payment_id
   where id = v_proposal.id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values
    (p_organization_id, v_actor, 'PAYMENT_PROPOSAL_APPROVED', 'cost_payment_proposal', v_proposal.id,
      jsonb_build_object('project_id', v_proposal.project_id, 'prepared_by', v_proposal.prepared_by,
        'approved_by', v_actor, 'project_payment_id', v_payment_id,
        'available_cash_minor_units_at_approval', v_available)),
    (p_organization_id, v_actor, 'PAYMENT_POSTED', 'project_payment', v_payment_id,
      jsonb_build_object('project_id', v_proposal.project_id, 'obligation_id', v_proposal.obligation_id,
        'cash_account_id', v_proposal.cash_account_id, 'payment_proposal_id', v_proposal.id,
        'journal_batch_id', v_batch_id, 'amount_minor_units', v_proposal.amount_minor_units,
        'currency', v_proposal.currency, 'payment_date', v_proposal.payment_date));
  return v_payment_id;
end $$;

-- Keep the historical signature as a fail-closed internal tombstone so stale
-- clients receive a precise error. API roles have no EXECUTE privilege.
create or replace function public.pay_cost_obligation(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_payment_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'direct payment posting disabled; prepare and approve a payment proposal';
end $$;
revoke all on function public.pay_cost_obligation(uuid,uuid,uuid,bigint,date,text)
  from public, anon, authenticated;

-- ===========================================================================
-- 4. RLS and shared management read models.
-- ===========================================================================
alter table public.supplier_invoices enable row level security;
alter table public.supplier_invoices force row level security;
alter table public.supplier_invoice_lines enable row level security;
alter table public.supplier_invoice_lines force row level security;
alter table public.cost_payment_proposals enable row level security;
alter table public.cost_payment_proposals force row level security;
create policy supplier_invoices_read on public.supplier_invoices for select to authenticated
  using (public.is_active_member(organization_id));
create policy supplier_invoice_lines_read on public.supplier_invoice_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_payment_proposals_read on public.cost_payment_proposals for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.supplier_invoices, public.supplier_invoice_lines,
  public.cost_payment_proposals from public, anon, authenticated;
grant select on public.supplier_invoices, public.supplier_invoice_lines,
  public.cost_payment_proposals to authenticated;

create or replace view public.cost_payment_proposals_read with (security_invoker=on) as
select p.id as payment_proposal_id, p.organization_id, p.project_id,
       p.obligation_id, p.cash_account_id, ca.name as cash_account_name,
       p.amount_minor_units::text as amount_minor_units, p.currency, p.payment_date,
       p.status, p.prepared_by, p.prepared_at, p.approved_by, p.approved_at,
       p.project_payment_id, o.description as obligation_description
from public.cost_payment_proposals p
join public.cost_obligations o
  on o.id = p.obligation_id and o.organization_id = p.organization_id
join public.project_cash_accounts ca
  on ca.id = p.cash_account_id and ca.organization_id = p.organization_id;

-- Preserve the original shared payment view columns and append proposal
-- provenance so Finance and Procurement can show maker/checker truth.
create or replace view public.payment_status_read with (security_invoker=on) as
select
  p.id as payment_id,
  p.organization_id,
  p.project_id,
  p.obligation_id,
  p.cash_account_id,
  p.amount_minor_units::text as amount_minor_units,
  p.currency,
  p.payment_date,
  p.paid_by,
  p.posted_at,
  b.id as batch_id,
  (rev.id is not null) as is_reversed,
  rev.id as reversal_batch_id,
  (m.id is not null) as is_reconciled,
  m.id as match_id,
  p.payment_proposal_id,
  proposal.prepared_by,
  proposal.approved_by
from public.project_payments p
join public.journal_batches b
  on b.source_type = 'PAYMENT' and b.source_id = p.id
left join public.journal_batches rev on rev.reversal_of_batch_id = b.id
left join public.reconciliation_matches m
  on m.payment_id = p.id and m.voided_at is null
left join public.cost_payment_proposals proposal
  on proposal.id = p.payment_proposal_id and proposal.organization_id = p.organization_id;

-- Existing views retain their original columns and append R4 financial fields.
create or replace view public.procurement_suppliers_read with (security_invoker=on) as
select s.id, s.organization_id, s.name, s.tax_number, s.payment_terms, s.notes,
       s.status, s.created_by, s.created_at,
       s.party_id, p.legal_name as party_name
from public.procurement_suppliers s
left join public.parties p on p.id = s.party_id and p.organization_id = s.organization_id;

create or replace view public.purchase_orders_read with (security_invoker=on) as
select o.id, o.organization_id, o.project_id, o.internal_reference,
       o.supplier_id, s.name as supplier_name,
       o.source_purchase_request_id,
       o.description, o.status, o.expected_delivery_date,
       o.requested_by, o.submitted_by, o.submitted_at, o.approved_by, o.approved_at,
       o.rejection_reason, o.created_at,
       (select count(*) from public.purchase_order_lines l where l.purchase_order_id = o.id) as line_count,
       o.currency, o.commercial_reference,
       coalesce((select sum(l.line_amount_minor_units) from public.purchase_order_lines l where l.purchase_order_id = o.id), 0)::text as commercial_total_minor_units
from public.purchase_orders o
left join public.procurement_suppliers s on s.id = o.supplier_id and s.organization_id = o.organization_id;

create or replace view public.purchase_order_lines_read with (security_invoker=on) as
select l.id, l.organization_id, l.project_id, l.purchase_order_id,
       l.item_description, l.quantity::text as quantity, l.unit, l.notes, l.created_at,
       l.unit_price_minor_units::text as unit_price_minor_units,
       l.line_amount_minor_units::text as line_amount_minor_units,
       o.currency
from public.purchase_order_lines l
join public.purchase_orders o on o.id = l.purchase_order_id and o.organization_id = l.organization_id;

create or replace view public.purchase_order_lines_receiving_read with (security_invoker=on) as
select ol.id as purchase_order_line_id, ol.organization_id, ol.project_id, ol.purchase_order_id,
       ol.item_description, ol.unit,
       ol.quantity::text as ordered_quantity,
       coalesce(sum(rl.quantity_received), 0)::text as received_quantity,
       (ol.quantity - coalesce(sum(rl.quantity_received), 0))::text as remaining_quantity,
       ol.unit_price_minor_units::text as unit_price_minor_units,
       ol.line_amount_minor_units::text as ordered_amount_minor_units,
       o.currency
from public.purchase_order_lines ol
join public.purchase_orders o on o.id = ol.purchase_order_id and o.organization_id = ol.organization_id
left join public.purchase_receipt_lines rl
  on rl.purchase_order_line_id = ol.id and rl.organization_id = ol.organization_id
group by ol.id, ol.organization_id, ol.project_id, ol.purchase_order_id, ol.item_description,
         ol.unit, ol.quantity, ol.unit_price_minor_units, ol.line_amount_minor_units, o.currency;

-- Approved PO commercial truth is the commitment. It is deliberately unposted:
-- receiving does not create expense/payable and invoice approval does.
create or replace view public.project_procurement_commitments_read with (security_invoker=on) as
select o.id as purchase_order_id, o.organization_id, o.project_id, o.supplier_id,
       s.party_id, o.internal_reference, o.approved_at as committed_at,
       o.currency,
       sum(ol.line_amount_minor_units)::text as committed_minor_units,
       coalesce(inv.invoiced_minor_units, 0)::text as invoiced_minor_units,
       (sum(ol.line_amount_minor_units) - coalesce(inv.invoiced_minor_units, 0))::text as remaining_commitment_minor_units,
       'UNPOSTED_PURCHASE_COMMITMENT'::text as accounting_effect
from public.purchase_orders o
join public.purchase_order_lines ol on ol.purchase_order_id = o.id
join public.procurement_suppliers s on s.id = o.supplier_id and s.organization_id = o.organization_id
left join (
  select i.purchase_order_id, sum(il.line_amount_minor_units) as invoiced_minor_units
  from public.supplier_invoices i
  join public.supplier_invoice_lines il on il.supplier_invoice_id = i.id
  where i.status = 'APPROVED'
  group by i.purchase_order_id
) inv on inv.purchase_order_id = o.id
where o.status = 'APPROVED' and o.currency is not null
 group by o.id, o.organization_id, o.project_id, o.supplier_id, s.party_id,
          o.internal_reference, o.approved_at, o.currency, inv.invoiced_minor_units;

create or replace view public.purchase_receipt_invoice_basis_read with (security_invoker=on) as
select rl.id as purchase_receipt_line_id, rl.organization_id, rl.project_id,
       rl.purchase_order_id, rl.purchase_order_line_id, rl.purchase_receipt_id,
       ol.item_description, ol.unit, rl.quantity_received::text as received_quantity,
       coalesce(inv.invoiced_quantity, 0)::text as approved_invoiced_quantity,
       (rl.quantity_received - coalesce(inv.invoiced_quantity, 0))::text as available_to_invoice_quantity,
       ol.unit_price_minor_units::text as unit_price_minor_units,
       o.currency, r.evidence_reference as receipt_evidence_reference
from public.purchase_receipt_lines rl
join public.purchase_receipts r on r.id = rl.purchase_receipt_id and r.organization_id = rl.organization_id
join public.purchase_order_lines ol on ol.id = rl.purchase_order_line_id and ol.organization_id = rl.organization_id
join public.purchase_orders o on o.id = rl.purchase_order_id and o.organization_id = rl.organization_id
left join (
  select il.purchase_receipt_line_id, sum(il.quantity_invoiced) as invoiced_quantity
  from public.supplier_invoice_lines il
  join public.supplier_invoices i on i.id = il.supplier_invoice_id and i.status = 'APPROVED'
  group by il.purchase_receipt_line_id
) inv on inv.purchase_receipt_line_id = rl.id
where o.status = 'APPROVED' and ol.unit_price_minor_units is not null;

create or replace view public.supplier_invoice_lines_read with (security_invoker=on) as
select il.id, il.organization_id, il.project_id, il.supplier_invoice_id,
       il.purchase_order_id, il.purchase_order_line_id, il.purchase_receipt_line_id,
       ol.item_description, ol.unit, il.quantity_invoiced::text as quantity_invoiced,
       il.unit_price_minor_units::text as unit_price_minor_units,
       il.line_amount_minor_units::text as line_amount_minor_units,
       i.currency
from public.supplier_invoice_lines il
join public.supplier_invoices i on i.id = il.supplier_invoice_id
join public.purchase_order_lines ol on ol.id = il.purchase_order_line_id;

-- One management row follows Invoice -> shared obligation -> shared payment ->
-- shared bank reconciliation. Payment and reconciliation statuses are derived,
-- never duplicated on the invoice.
create or replace view public.supplier_invoices_read with (security_invoker=on) as
select i.id, i.organization_id, i.project_id, i.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       i.supplier_id, s.name as supplier_name, i.party_id,
       i.invoice_reference, i.invoice_date, i.currency, i.cost_treatment,
       i.evidence_reference, i.notes, i.status, i.recorded_by, i.recorded_at,
       i.approved_by, i.approved_at, i.cost_obligation_id, i.authorization_batch_id,
       totals.invoice_total_minor_units::text as invoice_total_minor_units,
       coalesce(pay.paid_minor_units, 0)::text as paid_minor_units,
       case when coalesce(op.is_reversed, false) then '0'
            else (totals.invoice_total_minor_units - coalesce(pay.paid_minor_units, 0))::text
       end as outstanding_minor_units,
       coalesce(pay.reconciled_minor_units, 0)::text as reconciled_minor_units,
       coalesce(op.is_reversed, false) as payable_is_reversed,
       case
         when coalesce(op.is_reversed, false) then 'PAYABLE_REVERSED'
         when coalesce(pay.paid_minor_units, 0) = 0 then 'UNPAID'
         when coalesce(pay.paid_minor_units, 0) < totals.invoice_total_minor_units then 'PARTIALLY_PAID'
         else 'FULLY_PAID'
       end as payment_state,
       case
         when coalesce(pay.paid_minor_units, 0) = 0 then 'NOT_PAID'
         when coalesce(pay.reconciled_minor_units, 0) = 0 then 'PAID_UNRECONCILED'
         when pay.reconciled_minor_units < pay.paid_minor_units then 'PARTIALLY_RECONCILED'
         else 'RECONCILED'
       end as reconciliation_state,
       coalesce(pay.payment_count, 0)::integer as payment_count
from public.supplier_invoices i
join public.purchase_orders o on o.id = i.purchase_order_id and o.organization_id = i.organization_id
join public.procurement_suppliers s on s.id = i.supplier_id and s.organization_id = i.organization_id
join (
  select supplier_invoice_id, sum(line_amount_minor_units) as invoice_total_minor_units
  from public.supplier_invoice_lines group by supplier_invoice_id
) totals on totals.supplier_invoice_id = i.id
left join public.cost_obligation_position_read op
  on op.obligation_id = i.cost_obligation_id
left join (
  select co.source_supplier_invoice_id,
         sum(case when ps.is_reversed then 0 else ps.amount_minor_units::bigint end) as paid_minor_units,
         sum(case when not ps.is_reversed and ps.is_reconciled then ps.amount_minor_units::bigint else 0 end) as reconciled_minor_units,
         count(*) filter (where not ps.is_reversed) as payment_count
  from public.cost_obligations co
  join public.payment_status_read ps on ps.obligation_id = co.id
  where co.source_supplier_invoice_id is not null
  group by co.source_supplier_invoice_id
) pay on pay.source_supplier_invoice_id = i.id;

create or replace view public.procure_to_pay_order_read with (security_invoker=on) as
select c.purchase_order_id, c.organization_id, c.project_id, c.supplier_id, c.party_id,
       c.internal_reference, c.currency, c.committed_minor_units,
       coalesce(received.receipt_line_count, 0)::integer as receipt_line_count,
       c.invoiced_minor_units, c.remaining_commitment_minor_units,
       coalesce(fin.paid_minor_units, 0)::text as paid_minor_units,
       coalesce(fin.outstanding_minor_units, 0)::text as outstanding_payable_minor_units,
       coalesce(fin.unreconciled_minor_units, 0)::text as paid_unreconciled_minor_units,
       case when coalesce(fin.unreconciled_minor_units, 0) = 0 and coalesce(fin.paid_minor_units, 0) > 0
            then 'RECONCILED' when coalesce(fin.paid_minor_units, 0) > 0 then 'PAID_UNRECONCILED'
            else 'NOT_PAID' end as reconciliation_state
from public.project_procurement_commitments_read c
left join (
  -- Quantities with unlike units are never summed at order level. Per-line
  -- ordered/received/remaining truth lives in purchase_order_lines_receiving_read.
  select purchase_order_id, count(*) as receipt_line_count
  from public.purchase_receipt_lines group by purchase_order_id
) received on received.purchase_order_id = c.purchase_order_id
left join (
  select purchase_order_id,
         sum(paid_minor_units::bigint) as paid_minor_units,
         sum(outstanding_minor_units::bigint) as outstanding_minor_units,
         sum((paid_minor_units::bigint - reconciled_minor_units::bigint)) as unreconciled_minor_units
  from public.supplier_invoices_read where status = 'APPROVED' group by purchase_order_id
) fin on fin.purchase_order_id = c.purchase_order_id;

grant select on public.cost_payment_proposals_read, public.payment_status_read,
  public.procurement_suppliers_read, public.purchase_orders_read,
  public.purchase_order_lines_read, public.purchase_order_lines_receiving_read,
  public.project_procurement_commitments_read, public.purchase_receipt_invoice_basis_read,
  public.supplier_invoice_lines_read, public.supplier_invoices_read,
  public.procure_to_pay_order_read to authenticated;

-- ===========================================================================
-- 5. Command grants and pgcrypto hosted-schema compatibility.
-- ===========================================================================
revoke all on function public.link_supplier_party(uuid,uuid,uuid,text) from public, anon;
revoke all on function public.create_supplier(uuid,uuid,text,text,text,text,text) from public, anon;
revoke all on function public.create_purchase_order(uuid,uuid,text,uuid,uuid,text,date,text,text,jsonb,text) from public, anon;
revoke all on function public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,jsonb,text) from public, anon;
revoke all on function public.approve_supplier_invoice(uuid,uuid,text) from public, anon;
revoke all on function public.prepare_cost_payment(uuid,uuid,uuid,bigint,date,text) from public, anon;
revoke all on function public.approve_cost_payment(uuid,uuid,text) from public, anon;
grant execute on function public.link_supplier_party(uuid,uuid,uuid,text),
  public.create_supplier(uuid,uuid,text,text,text,text,text),
  public.create_purchase_order(uuid,uuid,text,uuid,uuid,text,date,text,text,jsonb,text),
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,jsonb,text),
  public.approve_supplier_invoice(uuid,uuid,text),
  public.prepare_cost_payment(uuid,uuid,uuid,bigint,date,text),
  public.approve_cost_payment(uuid,uuid,text)
to authenticated;

-- The replacement approve function retained its signature and prior grant.
revoke all on function public.approve_purchase_order(uuid,uuid,text) from public, anon;
grant execute on function public.approve_purchase_order(uuid,uuid,text) to authenticated;

do $pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
begin
  select n.nspname into v_pgcrypto_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;

  for v_record in
    select p.oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname = any(array[
         'link_supplier_party','create_supplier','create_purchase_order',
         'approve_purchase_order','record_supplier_invoice','approve_supplier_invoice',
         'prepare_cost_payment','approve_cost_payment'
       ]::text[])
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten := regexp_replace(v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(', 'g');
      if v_rewritten = v_definition then raise exception 'failed to qualify pgcrypto digest in R4 command'; end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat$;
