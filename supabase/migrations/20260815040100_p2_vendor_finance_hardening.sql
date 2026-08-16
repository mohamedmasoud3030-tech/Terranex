-- P2 — Vendor Finance Hardening: Supplier-Stated Total, Matching Extension, Tolerances.
--
-- Builds on R4 (PR #144) which delivered the core procure-to-pay flow. This
-- migration adds three policy-independent controls:
--
-- 1. Supplier-Stated Total: capture the actual total printed by the supplier,
--    compare with Terranex calculated total, require match or formal exception.
--
-- 2. Matching Policies Extension: support SERVICE acceptance, CONSTRUCTION
--    certified progress, and MILESTONE approval in addition to existing GOODS
--    receipt. A new generic procurement_acceptances table provides the
--    quantity/amount fact for non-goods procurement types.
--
-- 3. Tolerance & Exception Framework: a tolerance breach becomes a formal
--    exception record with reason, evidence, required authority, and
--    approve/reject. No dismissible UI warnings.
--
-- No COGS, inventory valuation, tax, or business-policy numbers are invented.

-- ===========================================================================
-- 1. Supplier-Stated Total
-- ===========================================================================
alter table public.supplier_invoices
  add column supplier_stated_total_minor_units bigint not null
    check (supplier_stated_total_minor_units > 0),
  add column supplier_stated_total_currency text not null
    check (supplier_stated_total_currency ~ '^[A-Z]{3}$');

comment on column public.supplier_invoices.supplier_stated_total_minor_units is
  'The actual total printed on the supplier invoice document, in minor units. NULL before document entry.';

-- ===========================================================================
-- 2. Generic Procurement Acceptance (service/construction/milestone)
-- ===========================================================================
create table public.procurement_acceptances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  purchase_order_id uuid not null,
  acceptance_type text not null check (acceptance_type in ('SERVICE','CONSTRUCTION','MILESTONE')),
  acceptance_reference text not null check (char_length(trim(acceptance_reference)) between 1 and 120),
  acceptance_date date not null,
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  description text
    check (description is null or char_length(trim(description)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (purchase_order_id, project_id, organization_id)
    references public.purchase_orders(id, project_id, organization_id) on delete restrict
);
create unique index procurement_acceptances_project_ref_key
  on public.procurement_acceptances(organization_id, project_id, lower(trim(acceptance_reference)));
create index procurement_acceptances_po_idx
  on public.procurement_acceptances(purchase_order_id);
create index procurement_acceptances_project_idx
  on public.procurement_acceptances(project_id, acceptance_date desc);

-- Add a composite unique key on purchase_order_lines so acceptance-line and
-- invoice-line FKs can reference the same PO line, PO, project and org in
-- one composite without requiring unit_price_minor_units (which is not known
-- at acceptance time).
alter table public.purchase_order_lines
  add constraint purchase_order_lines_id_po_project_org_key
    unique (id, purchase_order_id, project_id, organization_id);

-- The acceptance line carries a denormalized purchase_order_id so a composite
-- FK can prove that the referenced PO line belongs to the same PO/project/org.
-- It is kept coherent with the PO line by the composite FK below.
create table public.procurement_acceptance_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  acceptance_id uuid not null,
  purchase_order_id uuid not null,
  purchase_order_line_id uuid not null,
  accepted_quantity numeric(20,6) not null check (accepted_quantity > 0),
  unit text not null check (char_length(trim(unit)) between 1 and 20),
  notes text check (notes is null or char_length(trim(notes)) between 1 and 2000),
  created_at timestamptz not null default now(),
  unique (id, organization_id, project_id),
  unique (id, purchase_order_line_id, purchase_order_id, project_id, organization_id),
  unique (acceptance_id, purchase_order_line_id),
  foreign key (acceptance_id, organization_id, project_id)
    references public.procurement_acceptances(id, organization_id, project_id) on delete restrict,
  foreign key (purchase_order_line_id, purchase_order_id, project_id, organization_id)
    references public.purchase_order_lines(id, purchase_order_id, project_id, organization_id)
    on delete restrict
);
create index procurement_acceptance_lines_acceptance_idx
  on public.procurement_acceptance_lines(acceptance_id);
create index procurement_acceptance_lines_po_line_idx
  on public.procurement_acceptance_lines(purchase_order_line_id);

-- ===========================================================================
-- 3. Extend supplier_invoice_lines to reference acceptance as an alternative
--    to purchase_receipt_line. One of the two must be set.
-- ===========================================================================
alter table public.supplier_invoice_lines
  alter column purchase_receipt_line_id drop not null,
  add column procurement_acceptance_line_id uuid,
  add column procurement_type text not null default 'GOODS'
    check (procurement_type in ('GOODS','SERVICE','CONSTRUCTION','MILESTONE')),
  -- Re-establish the R4 goods-receipt coherence FK (the same composite the
  -- original table declared) after the column became nullable.
  add constraint supplier_invoice_lines_purchase_receipt_line_fkey
    foreign key (purchase_receipt_line_id, purchase_order_line_id, purchase_order_id, project_id, organization_id)
    references public.purchase_receipt_lines(id, purchase_order_line_id, purchase_order_id, project_id, organization_id)
    on delete restrict,
  add constraint supplier_invoice_lines_receipt_or_acceptance check (
    (procurement_type = 'GOODS' and purchase_receipt_line_id is not null and procurement_acceptance_line_id is null)
    or (procurement_type in ('SERVICE','CONSTRUCTION','MILESTONE')
        and procurement_acceptance_line_id is not null and purchase_receipt_line_id is null)
  ),
  -- Acceptance coherence in one key: the referenced acceptance line must
  -- belong to the same PO line, project and organization as the invoice line.
  add constraint supplier_invoice_lines_acceptance_line_fkey
    foreign key (procurement_acceptance_line_id, purchase_order_line_id, purchase_order_id, project_id, organization_id)
    references public.procurement_acceptance_lines(id, purchase_order_line_id, purchase_order_id, project_id, organization_id)
    on delete restrict;

create index supplier_invoice_lines_acceptance_idx
  on public.supplier_invoice_lines(procurement_acceptance_line_id) where procurement_acceptance_line_id is not null;

-- ===========================================================================
-- 4. Tolerance & Exception Framework
-- ===========================================================================
create table public.procurement_exception_reasons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  reason_code text not null check (char_length(trim(reason_code)) between 2 and 40),
  label_ar text not null check (char_length(trim(label_ar)) between 2 and 200),
  label_en text not null check (char_length(trim(label_en)) between 2 and 200),
  unique (organization_id, reason_code)
);

create table public.procurement_invoice_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_invoice_id uuid not null,
  exception_type text not null check (exception_type in (
    'SUPPLIER_TOTAL_MISMATCH',
    'LINE_PRICE_MISMATCH',
    'QUANTITY_EXCEEDS_ACCEPTED',
    'UNAUTHORIZED_LINE',
    'MISSING_EVIDENCE',
    'OTHER'
  )),
  -- The computed vs stated values for the breach
  expected_minor_units bigint,
  actual_minor_units bigint,
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'OPEN' check (status in ('OPEN','APPROVED','REJECTED')),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_notes text check (approval_notes is null or char_length(trim(approval_notes)) between 3 and 500),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  resolve_idempotency_key text
    check (resolve_idempotency_key is null or char_length(resolve_idempotency_key) between 8 and 120),
  resolve_request_hash text
    check (resolve_request_hash is null or char_length(resolve_request_hash) = 64),
  check (approved_by is null or approved_by <> created_by),
  check (
    (status = 'OPEN' and approved_by is null and approved_at is null and approval_notes is null)
    or (status in ('APPROVED','REJECTED') and approved_by is not null and approved_at is not null)
  ),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict
);
create index procurement_invoice_exceptions_invoice_idx
  on public.procurement_invoice_exceptions(supplier_invoice_id);
create index procurement_invoice_exceptions_status_idx
  on public.procurement_invoice_exceptions(status, created_at);
create unique index procurement_invoice_exceptions_resolve_key
  on public.procurement_invoice_exceptions(organization_id, resolve_idempotency_key)
  where resolve_idempotency_key is not null;

-- ===========================================================================
-- 5. Append-only / immutable guards
--
-- Acceptances and acceptance lines are fully append-only. Invoice exceptions
-- are append-only for DELETE and for economics, but the controlled
-- OPEN -> APPROVED / OPEN -> REJECTED transition must remain possible, so
-- the exception table gets a dedicated state-transition guard instead of the
-- blanket immutable trigger.
-- ===========================================================================
create or replace function public.p2_guard_acceptance_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'procurement acceptance and acceptance-line records are append-only';
end $$;

create trigger procurement_acceptances_immutable
  before update or delete on public.procurement_acceptances
  for each row execute function public.p2_guard_acceptance_immutable();
create trigger procurement_acceptance_lines_immutable
  before update or delete on public.procurement_acceptance_lines
  for each row execute function public.p2_guard_acceptance_immutable();

-- Exceptions: DELETE is forbidden, economics are immutable, but the controlled
-- OPEN -> APPROVED/REJECTED resolution transition is allowed.
create or replace function public.p2_guard_exception_delete() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'procurement invoice exceptions cannot be deleted';
end $$;
create trigger procurement_invoice_exceptions_no_delete
  before delete on public.procurement_invoice_exceptions
  for each row execute function public.p2_guard_exception_delete();

create or replace function public.p2_guard_exception_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  -- All economic/identity fields are immutable for the life of the record.
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.supplier_invoice_id is distinct from old.supplier_invoice_id
     or new.exception_type is distinct from old.exception_type
     or new.expected_minor_units is distinct from old.expected_minor_units
     or new.actual_minor_units is distinct from old.actual_minor_units
     or new.currency is distinct from old.currency
     or new.reason is distinct from old.reason
     or new.evidence_reference is distinct from old.evidence_reference
     or new.created_by is distinct from old.created_by
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash then
    raise exception 'procurement exception economics are immutable';
  end if;
  -- Only the controlled resolution transition is permitted.
  if not (
    old.status = 'OPEN'
    and new.status in ('APPROVED','REJECTED')
    and new.approved_by is not null
    and new.approved_at is not null
    and new.approved_by <> new.created_by
  ) then
    raise exception 'only OPEN exceptions can be resolved by a different approving authority';
  end if;
  return new;
end $$;
create trigger procurement_invoice_exceptions_transition_guard
  before update on public.procurement_invoice_exceptions
  for each row execute function public.p2_guard_exception_transition();

-- ===========================================================================
-- 6. Update approve_supplier_invoice to enforce supplier-stated-total match
--    and require an approved exception to proceed on mismatch.
-- ===========================================================================
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
  v_supplier_total bigint;
  v_exception_approved boolean;
  v_line record;
  v_accepted_quantity numeric;
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

  -- One PO lock serializes every approval consuming any receipt under it.
  perform 1 from public.purchase_orders
   where id = v_invoice.purchase_order_id and organization_id = p_organization_id
   for update;

  -- Verify quantity ceilings per line (receipt or acceptance)
  for v_line in
    select sil.id, sil.purchase_receipt_line_id, sil.procurement_acceptance_line_id,
           sil.quantity_invoiced, sil.unit_price_minor_units, sil.procurement_type
    from public.supplier_invoice_lines sil
    where sil.supplier_invoice_id = p_supplier_invoice_id
  loop
    if v_line.procurement_type = 'GOODS' then
      if exists (
        with current_invoice as (
          select purchase_receipt_line_id, sum(quantity_invoiced) as quantity
          from public.supplier_invoice_lines
          where supplier_invoice_id = p_supplier_invoice_id
            and purchase_receipt_line_id = v_line.purchase_receipt_line_id
          group by purchase_receipt_line_id
        ), already_approved as (
          select il.purchase_receipt_line_id, sum(il.quantity_invoiced) as quantity
          from public.supplier_invoice_lines il
          join public.supplier_invoices i on i.id = il.supplier_invoice_id
          where i.status = 'APPROVED'
            and i.organization_id = p_organization_id
            and i.id <> p_supplier_invoice_id
            and il.purchase_receipt_line_id = v_line.purchase_receipt_line_id
          group by il.purchase_receipt_line_id
        )
        select 1
        from current_invoice ci
        join public.purchase_receipt_lines rl on rl.id = ci.purchase_receipt_line_id
        left join already_approved aa on aa.purchase_receipt_line_id = ci.purchase_receipt_line_id
        where ci.quantity + coalesce(aa.quantity, 0) > rl.quantity_received
      ) then raise exception 'supplier invoice quantity exceeds remaining received quantity'; end if;
    else
      select accepted_quantity into v_accepted_quantity
      from public.procurement_acceptance_lines
      where id = v_line.procurement_acceptance_line_id;
      if v_accepted_quantity is null then raise exception 'acceptance line not found'; end if;
      if exists (
        with current_invoice as (
          select procurement_acceptance_line_id, sum(quantity_invoiced) as quantity
          from public.supplier_invoice_lines
          where supplier_invoice_id = p_supplier_invoice_id
            and procurement_acceptance_line_id = v_line.procurement_acceptance_line_id
          group by procurement_acceptance_line_id
        ), already_approved as (
          select il.procurement_acceptance_line_id, sum(il.quantity_invoiced) as quantity
          from public.supplier_invoice_lines il
          join public.supplier_invoices i on i.id = il.supplier_invoice_id
          where i.status = 'APPROVED'
            and i.organization_id = p_organization_id
            and i.id <> p_supplier_invoice_id
            and il.procurement_acceptance_line_id = v_line.procurement_acceptance_line_id
          group by il.procurement_acceptance_line_id
        )
        select 1
        from current_invoice ci
        left join already_approved aa on aa.procurement_acceptance_line_id = ci.procurement_acceptance_line_id
        where ci.quantity + coalesce(aa.quantity, 0) > v_accepted_quantity
      ) then raise exception 'supplier invoice quantity exceeds accepted quantity'; end if;
    end if;
  end loop;

  select sum(line_amount_minor_units) into v_total
    from public.supplier_invoice_lines where supplier_invoice_id = p_supplier_invoice_id;
  if v_total is null or v_total <= 0 then raise exception 'supplier invoice total must be positive'; end if;

  -- Supplier-Stated Total check: the calculated total must equal the total
  -- printed by the supplier, unless an approved exception records the reason.
  v_supplier_total := v_invoice.supplier_stated_total_minor_units;
  if v_supplier_total is not null and v_supplier_total <> v_total then
    select exists (
      select 1 from public.procurement_invoice_exceptions e
      where e.supplier_invoice_id = p_supplier_invoice_id
        and e.exception_type = 'SUPPLIER_TOTAL_MISMATCH'
        and e.status = 'APPROVED'
        and e.expected_minor_units = v_total
        and e.actual_minor_units = v_supplier_total
    ) into v_exception_approved;
    if not v_exception_approved then
      raise exception 'supplier stated total % does not match calculated total %. Record an approved exception to proceed.',
        v_supplier_total, v_total;
    end if;
  end if;

  v_description := 'Supplier invoice ' || v_invoice.invoice_reference;
  v_obligation_hash := encode(digest(
    v_invoice.id::text || '|' || v_invoice.project_id::text || '|' || v_invoice.party_id::text || '|'
    || v_total::text || '|' || v_invoice.currency || '|' || v_invoice.invoice_date::text || '|'
    || v_invoice.cost_treatment, 'sha256'), 'hex');

  -- Reuse the authoritative Finance Core obligation and authorization posting.
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
      'payable_minor_units', v_total, 'currency', v_invoice.currency,
      'supplier_stated_total_minor_units', v_supplier_total));
  return v_obligation_id;
end $$;

-- ===========================================================================
-- 7. Command: create procurement acceptance (service/construction/milestone)
-- ===========================================================================
create or replace function public.create_procurement_acceptance(
  p_organization_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_acceptance_type text,
  p_acceptance_reference text,
  p_acceptance_date date,
  p_evidence_reference text,
  p_description text,
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
  v_quantity numeric;
  v_po_line_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_acceptance_type not in ('SERVICE','CONSTRUCTION','MILESTONE') then
    raise exception 'acceptance type must be SERVICE, CONSTRUCTION, or MILESTONE';
  end if;
  if p_acceptance_reference is null or char_length(trim(p_acceptance_reference)) not between 1 and 120 then
    raise exception 'invalid acceptance reference';
  end if;
  if p_acceptance_date is null then raise exception 'acceptance date required'; end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;
  if p_description is not null and char_length(trim(p_description)) not between 3 and 2000 then
    raise exception 'invalid description';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one acceptance line is required';
  end if;
  if jsonb_array_length(p_lines) > 50 then raise exception 'too many acceptance lines'; end if;

  select o.* into v_order
  from public.purchase_orders o
  where o.id = p_purchase_order_id and o.project_id = p_project_id
    and o.organization_id = p_organization_id;
  if not found then raise exception 'purchase order not found'; end if;
  if v_order.status <> 'APPROVED' then raise exception 'acceptance requires an approved purchase order'; end if;

  -- Validate every line before any insert, so the aggregate is atomic.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    begin
      v_quantity := (v_line->>'accepted_quantity')::numeric;
      v_po_line_id := (v_line->>'purchase_order_line_id')::uuid;
    exception when others then
      raise exception 'invalid acceptance line payload';
    end;
    if v_quantity is null or v_quantity <= 0 then raise exception 'acceptance quantity must be positive'; end if;
    if (v_line->>'unit') is null or char_length(trim(v_line->>'unit')) not between 1 and 20 then
      raise exception 'invalid acceptance line unit';
    end if;
    if not exists (
      select 1 from public.purchase_order_lines l
      where l.id = v_po_line_id
        and l.purchase_order_id = p_purchase_order_id
        and l.project_id = p_project_id
        and l.organization_id = p_organization_id
    ) then raise exception 'purchase order line not found for acceptance line'; end if;
  end loop;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'purchase_order_id', p_purchase_order_id,
    'acceptance_type', p_acceptance_type, 'acceptance_reference', trim(p_acceptance_reference),
    'acceptance_date', p_acceptance_date, 'evidence_reference', p_evidence_reference,
    'description', p_description, 'lines', p_lines
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p2-acceptance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.procurement_acceptances
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.procurement_acceptances(
    organization_id, project_id, purchase_order_id, acceptance_type,
    acceptance_reference, acceptance_date, evidence_reference, description,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_purchase_order_id, p_acceptance_type,
    trim(p_acceptance_reference), p_acceptance_date, nullif(trim(p_evidence_reference), ''),
    nullif(trim(p_description), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    insert into public.procurement_acceptance_lines(
      organization_id, project_id, acceptance_id, purchase_order_id, purchase_order_line_id,
      accepted_quantity, unit, notes
    ) values (
      p_organization_id, p_project_id, v_id, p_purchase_order_id,
      (v_line->>'purchase_order_line_id')::uuid,
      (v_line->>'accepted_quantity')::numeric, trim(v_line->>'unit'),
      nullif(trim(coalesce(v_line->>'notes', '')), '')
    );
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PROCUREMENT_ACCEPTANCE_CREATED', 'procurement_acceptance', v_id,
    jsonb_build_object('project_id', p_project_id, 'purchase_order_id', p_purchase_order_id,
      'acceptance_type', p_acceptance_type, 'acceptance_reference', trim(p_acceptance_reference)));
  return v_id;
end $$;

-- ===========================================================================
-- 8. Command: create an invoice exception for total mismatch
-- ===========================================================================
create or replace function public.create_supplier_invoice_exception(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_invoice_id uuid,
  p_exception_type text,
  p_expected_minor_units bigint,
  p_actual_minor_units bigint,
  p_currency text,
  p_reason text,
  p_evidence_reference text,
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
  if p_exception_type not in ('SUPPLIER_TOTAL_MISMATCH','LINE_PRICE_MISMATCH','QUANTITY_EXCEEDS_ACCEPTED','UNAUTHORIZED_LINE','MISSING_EVIDENCE','OTHER') then
    raise exception 'invalid exception type';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'exception reason is required';
  end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;
  if not exists (
    select 1 from public.supplier_invoices i
    where i.id = p_supplier_invoice_id and i.project_id = p_project_id
      and i.organization_id = p_organization_id
  ) then raise exception 'supplier invoice not found'; end if;

  v_hash := encode(digest(jsonb_build_object(
    'supplier_invoice_id', p_supplier_invoice_id, 'exception_type', p_exception_type,
    'expected_minor_units', p_expected_minor_units, 'actual_minor_units', p_actual_minor_units,
    'currency', p_currency, 'reason', trim(p_reason),
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p2-exception:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.procurement_invoice_exceptions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.procurement_invoice_exceptions(
    organization_id, project_id, supplier_invoice_id, exception_type,
    expected_minor_units, actual_minor_units, currency, reason, evidence_reference,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_supplier_invoice_id, p_exception_type,
    p_expected_minor_units, p_actual_minor_units, p_currency, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_INVOICE_EXCEPTION_CREATED', 'procurement_invoice_exception', v_id,
    jsonb_build_object('supplier_invoice_id', p_supplier_invoice_id, 'exception_type', p_exception_type,
      'expected_minor_units', p_expected_minor_units, 'actual_minor_units', p_actual_minor_units));
  return v_id;
end $$;

-- ===========================================================================
-- 9. Command: approve/reject an exception (OWNER only)
-- ===========================================================================
create or replace function public.resolve_supplier_invoice_exception(
  p_organization_id uuid,
  p_exception_id uuid,
  p_decision text,
  p_approval_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_exception public.procurement_invoice_exceptions%rowtype;
  v_existing public.procurement_invoice_exceptions%rowtype;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_decision not in ('APPROVED','REJECTED') then raise exception 'decision must be APPROVED or REJECTED'; end if;
  if p_approval_notes is not null and char_length(trim(p_approval_notes)) not between 3 and 500 then
    raise exception 'invalid approval notes';
  end if;

  v_hash := encode(digest(p_exception_id::text || '|' || p_decision || '|' || coalesce(trim(p_approval_notes), ''),
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p2-exception-resolve:' || trim(p_idempotency_key), 0));

  -- Replay using dedicated resolve_idempotency_key (not the creation key)
  select * into v_existing from public.procurement_invoice_exceptions
  where organization_id = p_organization_id
    and resolve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id is distinct from p_exception_id
       or v_existing.status <> p_decision
       or v_existing.resolve_request_hash IS DISTINCT FROM v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_exception from public.procurement_invoice_exceptions
  where id = p_exception_id and organization_id = p_organization_id for update;
  if not found then raise exception 'exception not found'; end if;
  if v_exception.status <> 'OPEN' then raise exception 'exception is already resolved'; end if;
  if v_exception.created_by = v_actor then raise exception 'maker/checker: exception creator cannot resolve'; end if;
  if v_exception.resolve_idempotency_key is not null then
    raise exception 'exception already has a resolution key; cannot re-resolve';
  end if;

  update public.procurement_invoice_exceptions
     set status = p_decision, approved_by = v_actor, approved_at = now(),
         approval_notes = nullif(trim(p_approval_notes), ''),
         resolve_idempotency_key = trim(p_idempotency_key),
         resolve_request_hash = v_hash
   where id = p_exception_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor,
    case when p_decision = 'APPROVED' then 'SUPPLIER_INVOICE_EXCEPTION_APPROVED'
         else 'SUPPLIER_INVOICE_EXCEPTION_REJECTED' end,
    'procurement_invoice_exception', p_exception_id,
    jsonb_build_object('supplier_invoice_id', v_exception.supplier_invoice_id,
      'exception_type', v_exception.exception_type, 'decision', p_decision));
  return p_exception_id;
end $$;

-- ===========================================================================
-- 10. Record command update for supplier-stated total and procurement type
-- ===========================================================================
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
  p_supplier_stated_total_minor_units bigint,
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
  v_procurement_type text;
  v_acceptance_line_id uuid;
  v_po_line_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash := encode(digest(
    p_project_id::text || '|' || p_purchase_order_id::text || '|' || coalesce(trim(p_invoice_reference), '') || '|'
    || coalesce(p_invoice_date::text, '') || '|' || coalesce(p_currency, '') || '|'
    || coalesce(p_cost_treatment, '') || '|' || coalesce(trim(p_evidence_reference), '') || '|'
    || coalesce(trim(p_notes), '') || '|' || coalesce(p_supplier_stated_total_minor_units::text, '') || '|'
    || coalesce(p_lines::text, ''), 'sha256'), 'hex');
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
  if p_supplier_stated_total_minor_units is null then
    raise exception 'supplier stated total is required for every supplier invoice';
  end if;
  if p_supplier_stated_total_minor_units <= 0 then
    raise exception 'supplier stated total must be positive';
  end if;
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

    v_procurement_type := coalesce(v_line->>'procurement_type', 'GOODS');
    if v_procurement_type = 'GOODS' then
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
    elsif v_procurement_type in ('SERVICE','CONSTRUCTION','MILESTONE') then
      v_acceptance_line_id := (v_line->>'procurement_acceptance_line_id')::uuid;
      v_po_line_id := (v_line->>'purchase_order_line_id')::uuid;
      if v_acceptance_line_id is null then raise exception 'acceptance line required for non-goods procurement'; end if;
      select al.id, al.purchase_order_line_id, al.accepted_quantity, ol.unit_price_minor_units
        into v_receipt
        from public.procurement_acceptance_lines al
        join public.purchase_order_lines ol
          on ol.id = al.purchase_order_line_id and ol.organization_id = al.organization_id
       where al.id = v_acceptance_line_id
         and al.purchase_order_id = p_purchase_order_id
         and al.project_id = p_project_id
         and al.organization_id = p_organization_id
       for update of al;
      if not found then raise exception 'acceptance line not found for this purchase order'; end if;
      if v_po_line_id is not null and v_po_line_id <> v_receipt.purchase_order_line_id then
        raise exception 'invoice line purchase order line does not match acceptance line';
      end if;
      if v_receipt.unit_price_minor_units is null or v_unit_price <> v_receipt.unit_price_minor_units then
        raise exception 'supplier invoice unit price must exactly match purchase order';
      end if;
      if v_quantity > v_receipt.accepted_quantity then raise exception 'supplier invoice quantity exceeds accepted quantity'; end if;
    else
      raise exception 'invalid procurement type: %', v_procurement_type;
    end if;
    v_total := v_total + (v_quantity * v_unit_price);
  end loop;
  if v_total <= 0 or v_total <> trunc(v_total) then raise exception 'supplier invoice total must be exact positive minor units'; end if;

  insert into public.supplier_invoices(
    organization_id, project_id, purchase_order_id, supplier_id, party_id,
    invoice_reference, invoice_date, currency, cost_treatment, evidence_reference,
    notes, supplier_stated_total_minor_units, supplier_stated_total_currency,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_purchase_order_id, v_order.supplier_id, v_order.party_id,
    trim(p_invoice_reference), p_invoice_date, p_currency, p_cost_treatment,
    trim(p_evidence_reference), nullif(trim(p_notes), ''), p_supplier_stated_total_minor_units,
    p_currency, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_procurement_type := coalesce(v_line->>'procurement_type', 'GOODS');
    if v_procurement_type = 'GOODS' then
      select rl.purchase_order_line_id into v_receipt
        from public.purchase_receipt_lines rl
       where rl.id = (v_line->>'purchase_receipt_line_id')::uuid;
      insert into public.supplier_invoice_lines(
        organization_id, project_id, supplier_invoice_id, purchase_order_id,
        purchase_order_line_id, purchase_receipt_line_id, quantity_invoiced,
        unit_price_minor_units, procurement_type
      ) values (
        p_organization_id, p_project_id, v_id, p_purchase_order_id,
        v_receipt.purchase_order_line_id, (v_line->>'purchase_receipt_line_id')::uuid,
        (v_line->>'quantity_invoiced')::numeric, (v_line->>'unit_price_minor_units')::bigint,
        'GOODS'
      );
    else
      insert into public.supplier_invoice_lines(
        organization_id, project_id, supplier_invoice_id, purchase_order_id,
        purchase_order_line_id, procurement_acceptance_line_id, quantity_invoiced,
        unit_price_minor_units, procurement_type
      ) values (
        p_organization_id, p_project_id, v_id, p_purchase_order_id,
        (v_line->>'purchase_order_line_id')::uuid, (v_line->>'procurement_acceptance_line_id')::uuid,
        (v_line->>'quantity_invoiced')::numeric, (v_line->>'unit_price_minor_units')::bigint,
        v_procurement_type
      );
    end if;
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_INVOICE_RECORDED', 'supplier_invoice', v_id,
    jsonb_build_object('project_id', p_project_id, 'purchase_order_id', p_purchase_order_id,
      'supplier_id', v_order.supplier_id, 'invoice_reference', trim(p_invoice_reference),
      'invoice_total_minor_units', v_total::bigint, 'currency', p_currency,
      'supplier_stated_total_minor_units', p_supplier_stated_total_minor_units));
  return v_id;
end $$;

-- ===========================================================================
-- 11. Read models
-- ===========================================================================
create or replace view public.procurement_acceptances_read with (security_invoker=on) as
select a.id as acceptance_id, a.organization_id, a.project_id, a.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       a.acceptance_type, a.acceptance_reference, a.acceptance_date,
       a.evidence_reference, a.description, a.recorded_by, a.recorded_at,
       (select count(*) from public.procurement_acceptance_lines l where l.acceptance_id = a.id) as line_count
from public.procurement_acceptances a
join public.purchase_orders o on o.id = a.purchase_order_id and o.organization_id = a.organization_id;

create or replace view public.procurement_acceptance_lines_read with (security_invoker=on) as
select al.id as acceptance_line_id, al.organization_id, al.project_id, al.acceptance_id,
       al.purchase_order_line_id, ol.item_description, al.accepted_quantity::text as accepted_quantity,
       al.unit, al.notes, al.created_at, ol.unit_price_minor_units::text as unit_price_minor_units,
       o.currency
from public.procurement_acceptance_lines al
join public.purchase_order_lines ol on ol.id = al.purchase_order_line_id
join public.purchase_orders o on o.id = ol.purchase_order_id;

create or replace view public.procurement_invoice_exceptions_read with (security_invoker=on) as
select e.id as exception_id, e.organization_id, e.project_id, e.supplier_invoice_id,
       i.invoice_reference, e.exception_type,
       e.expected_minor_units::text as expected_minor_units,
       e.actual_minor_units::text as actual_minor_units,
       e.currency, e.reason, e.evidence_reference, e.status,
       e.approved_by, e.approved_at, e.approval_notes,
       e.created_by, e.created_at
from public.procurement_invoice_exceptions e
join public.supplier_invoices i on i.id = e.supplier_invoice_id;

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
            else greatest(totals.invoice_total_minor_units - coalesce(pay.paid_minor_units, 0), 0)::text
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
       coalesce(pay.payment_count, 0)::integer as payment_count,
       i.supplier_stated_total_minor_units::text as supplier_stated_total_minor_units,
       (select count(*) from public.procurement_invoice_exceptions e
        where e.supplier_invoice_id = i.id and e.status = 'OPEN') as open_exception_count
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

-- ===========================================================================
-- 12. RLS and grants
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array[
    'procurement_acceptances','procurement_acceptance_lines',
    'procurement_exception_reasons','procurement_invoice_exceptions'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t||'_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

grant select on
  public.procurement_acceptances_read,
  public.procurement_acceptance_lines_read,
  public.procurement_invoice_exceptions_read
  to authenticated;

revoke all on function
  public.create_procurement_acceptance(uuid,uuid,uuid,text,text,date,text,text,jsonb,text),
  public.create_supplier_invoice_exception(uuid,uuid,uuid,text,bigint,bigint,text,text,text,text),
  public.resolve_supplier_invoice_exception(uuid,uuid,text,text,text)
  from public, anon;
grant execute on function
  public.create_procurement_acceptance(uuid,uuid,uuid,text,text,date,text,text,jsonb,text),
  public.create_supplier_invoice_exception(uuid,uuid,uuid,text,bigint,bigint,text,text,text,text),
  public.resolve_supplier_invoice_exception(uuid,uuid,text,text,text)
  to authenticated;

-- The updated record_supplier_invoice and approve_supplier_invoice replace
-- the R4 versions; their grants are preserved by the existing grant statements.

-- pgcrypto schema compatibility for the new digest references
do $pgcrypto_compat_p2$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
  v_commands text[] := array[
    'create_procurement_acceptance','create_supplier_invoice_exception',
    'resolve_supplier_invoice_exception','record_supplier_invoice',
    'approve_supplier_invoice'
  ];
begin
  select n.nspname into v_pgcrypto_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;

  for v_record in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.proname = any(v_commands::text[])
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten := regexp_replace(v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(', 'g');
      if v_rewritten = v_definition then raise exception 'failed to qualify pgcrypto digest in %', v_record.proname; end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat_p2$;

-- ===========================================================================
-- 13. Update the procure-to-pay order read model to include acceptance info
-- ===========================================================================
create or replace view public.procure_to_pay_order_read with (security_invoker=on) as
select c.purchase_order_id, c.organization_id, c.project_id, c.supplier_id, c.party_id,
       c.internal_reference, c.currency, c.committed_minor_units,
       coalesce(received.receipt_line_count, 0)::integer as receipt_line_count,
       coalesce(acceptance.acceptance_line_count, 0)::integer as acceptance_line_count,
       c.invoiced_minor_units, c.remaining_commitment_minor_units,
       coalesce(fin.paid_minor_units, 0)::text as paid_minor_units,
       coalesce(fin.outstanding_minor_units, 0)::text as outstanding_payable_minor_units,
       coalesce(fin.unreconciled_minor_units, 0)::text as paid_unreconciled_minor_units,
       case when coalesce(fin.unreconciled_minor_units, 0) = 0 and coalesce(fin.paid_minor_units, 0) > 0
            then 'RECONCILED' when coalesce(fin.paid_minor_units, 0) > 0 then 'PAID_UNRECONCILED'
            else 'NOT_PAID' end as reconciliation_state
from public.project_procurement_commitments_read c
left join (
  select purchase_order_id, count(*) as receipt_line_count
  from public.purchase_receipt_lines group by purchase_order_id
) received on received.purchase_order_id = c.purchase_order_id
left join (
  select purchase_order_id, count(*) as acceptance_line_count
  from public.procurement_acceptance_lines group by purchase_order_id
) acceptance on acceptance.purchase_order_id = c.purchase_order_id
left join (
  select purchase_order_id,
         sum(paid_minor_units::bigint) as paid_minor_units,
         sum(outstanding_minor_units::bigint) as outstanding_minor_units,
         sum((paid_minor_units::bigint - reconciled_minor_units::bigint)) as unreconciled_minor_units
  from public.supplier_invoices_read where status = 'APPROVED' group by purchase_order_id
) fin on fin.purchase_order_id = c.purchase_order_id;