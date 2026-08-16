-- P3 — Credits, Payment Allocation and Advances.
--
-- Extends the shared Finance Core with three policy-independent capabilities:
--
-- 1. Supplier Credit Notes: reduction against previously approved supplier
--    invoices. Creates a reversal obligation chain. Never a fake invoice.
--
-- 2. Unapplied Payments & Many-to-Many Allocation: payments may be recorded
--    without an obligation (unapplied) and later allocated across multiple
--    obligations. No data loss on partial or unallocated amounts.
--
-- 3. Supplier Advances/Prepayments: advance payment recorded as an asset
--    (prepaid asset), later applied against supplier invoices. Never a fake
--    invoice. Advance application reduces the payable.
--
-- No COGS, inventory valuation, tax, or business-policy numbers are invented.
-- Revenue-side credit notes are deferred until P5 (customer-side invoice model).

-- ===========================================================================
-- 1. Supplier Credit Notes
-- ===========================================================================
create table public.supplier_credit_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_invoice_id uuid not null,
  credit_reference text not null check (char_length(trim(credit_reference)) between 1 and 120),
  credit_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  reversal_obligation_id uuid,
  authorization_batch_id uuid,
  status text not null default 'RECORDED' check (status in ('RECORDED','APPROVED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approve_idempotency_key text
    check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text
    check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (approved_by is null or approved_by <> recorded_by),
  check (
    (status = 'RECORDED' and reversal_obligation_id is null and authorization_batch_id is null)
    or (status = 'APPROVED' and reversal_obligation_id is not null and authorization_batch_id is not null)
  ),
  unique (organization_id, supplier_invoice_id, lower(trim(credit_reference))),
  unique (organization_id, idempotency_key),
  unique (reversal_obligation_id),
  unique (authorization_batch_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict,
  foreign key (reversal_obligation_id, project_id, organization_id)
    references public.cost_obligations(id, project_id, organization_id) on delete restrict,
  foreign key (authorization_batch_id, project_id, organization_id)
    references public.journal_batches(id, project_id, organization_id) on delete restrict
);

create unique index supplier_credit_notes_approve_key
  on public.supplier_credit_notes(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;
create index supplier_credit_notes_invoice_idx
  on public.supplier_credit_notes(supplier_invoice_id);
create index supplier_credit_notes_project_idx
  on public.supplier_credit_notes(project_id, credit_date desc);

-- ===========================================================================
-- 2. Unapplied Payments & Payment Allocation
-- ===========================================================================
alter table public.project_payments
  add column allocation_status text not null default 'ALLOCATED'
    check (allocation_status in ('UNAPPLIED','PARTIALLY_ALLOCATED','ALLOCATED')),
  alter column obligation_id drop not null;

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  payment_id uuid not null,
  obligation_id uuid not null,
  allocated_minor_units bigint not null check (allocated_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  allocated_by uuid not null references auth.users(id) on delete restrict,
  allocated_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  foreign key (payment_id, organization_id)
    references public.project_payments(id, organization_id) on delete restrict,
  foreign key (obligation_id, project_id, organization_id)
    references public.cost_obligations(id, project_id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index payment_allocations_payment_idx on public.payment_allocations(payment_id);
create index payment_allocations_obligation_idx on public.payment_allocations(obligation_id);

-- ===========================================================================
-- 3. Supplier Advances / Prepayments
-- ===========================================================================
create table public.supplier_advances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_party_id uuid not null references public.parties(id, organization_id) on delete restrict,
  advance_reference text not null check (char_length(trim(advance_reference)) between 1 and 120),
  advance_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  description text check (description is null or char_length(trim(description)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  payment_id uuid,
  status text not null default 'UNAPPLIED'
    check (status in ('UNAPPLIED','PARTIALLY_APPLIED','FULLY_APPLIED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, project_id, lower(trim(advance_reference))),
  unique (organization_id, idempotency_key),
  unique (payment_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (payment_id, organization_id)
    references public.project_payments(id, organization_id) on delete restrict
);
create index supplier_advances_project_idx on public.supplier_advances(project_id, advance_date desc);

create table public.supplier_advance_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  advance_id uuid not null,
  supplier_invoice_id uuid not null,
  applied_amount_minor_units bigint not null check (applied_amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  foreign key (advance_id, organization_id)
    references public.supplier_advances(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index supplier_advance_applications_advance_idx on public.supplier_advance_applications(advance_id);
create index supplier_advance_applications_invoice_idx on public.supplier_advance_applications(supplier_invoice_id);

-- ===========================================================================
-- 4. Immutability and state transition guards
-- ===========================================================================
create or replace function public.p3_guard_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin raise exception 'credit note, allocation and advance records are append-only'; end $$;

create or replace function public.p3_guard_credit_note_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status <> 'RECORDED' then raise exception 'credit note is not in RECORDED state'; end if;
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.supplier_invoice_id is distinct from old.supplier_invoice_id
     or new.credit_reference is distinct from old.credit_reference
     or new.credit_date is distinct from old.credit_date
     or new.currency is distinct from old.currency
     or new.amount_minor_units is distinct from old.amount_minor_units
     or new.reason is distinct from old.reason then
    raise exception 'credit note economics are immutable';
  end if;
  return new;
end $$;

drop trigger if exists supplier_credit_notes_no_change on public.supplier_credit_notes;
create trigger supplier_credit_notes_no_change
  before delete on public.supplier_credit_notes
  for each row execute function public.p3_guard_immutable();
create trigger supplier_credit_notes_transition_guard
  before update on public.supplier_credit_notes
  for each row execute function public.p3_guard_credit_note_transition();

drop trigger if exists payment_allocations_no_change on public.payment_allocations;
create trigger payment_allocations_no_change
  before update or delete on public.payment_allocations
  for each row execute function public.p3_guard_immutable();

drop trigger if exists supplier_advances_no_change on public.supplier_advances;
create trigger supplier_advances_no_change
  before update or delete on public.supplier_advances
  for each row execute function public.p3_guard_immutable();

drop trigger if exists supplier_advance_applications_no_change on public.supplier_advance_applications;
create trigger supplier_advance_applications_no_change
  before update or delete on public.supplier_advance_applications
  for each row execute function public.p3_guard_immutable();

-- ===========================================================================
-- 5. Commands
-- ===========================================================================

-- 5a. Record a supplier credit note (RECORDED status, no financial effect yet)
create or replace function public.record_supplier_credit_note(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_invoice_id uuid,
  p_credit_reference text,
  p_credit_date date,
  p_currency text,
  p_amount_minor_units bigint,
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
  if not exists (select 1 from public.supplier_invoices i
    where i.id = p_supplier_invoice_id and i.project_id = p_project_id
      and i.organization_id = p_organization_id) then
    raise exception 'supplier invoice not found';
  end if;
  if p_credit_reference is null or char_length(trim(p_credit_reference)) not between 1 and 120 then
    raise exception 'invalid credit note reference';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'credit amount must be positive';
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'supplier_invoice_id', p_supplier_invoice_id, 'credit_reference', trim(p_credit_reference),
    'credit_date', p_credit_date, 'currency', p_currency,
    'amount_minor_units', p_amount_minor_units, 'reason', trim(p_reason),
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-credit-note:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_credit_notes
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.supplier_credit_notes(
    organization_id, project_id, supplier_invoice_id, credit_reference, credit_date,
    currency, amount_minor_units, reason, evidence_reference, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_supplier_invoice_id, trim(p_credit_reference),
    p_credit_date, p_currency, p_amount_minor_units, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREDIT_NOTE_RECORDED', 'supplier_credit_note', v_id,
    jsonb_build_object('supplier_invoice_id', p_supplier_invoice_id, 'amount_minor_units', p_amount_minor_units));
  return v_id;
end $$;

-- 5b. Approve credit note: creates reversal obligation + balanced journal batch
create or replace function public.approve_supplier_credit_note(
  p_organization_id uuid,
  p_credit_note_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_credit public.supplier_credit_notes%rowtype;
  v_invoice public.supplier_invoices%rowtype;
  v_obligation_id uuid;
  v_batch_id uuid;
  v_payable uuid;
  v_expense uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := encode(digest(p_credit_note_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-credit-approve:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_credit_notes
  where organization_id = p_organization_id and approve_idempotency_key = trim(p_idempotency_key);
  if found then return v_existing.reversal_obligation_id; end if;

  select * into v_credit from public.supplier_credit_notes
  where id = p_credit_note_id and organization_id = p_organization_id for update;
  if not found then raise exception 'credit note not found'; end if;
  if v_credit.status <> 'RECORDED' then raise exception 'credit note is not in RECORDED state'; end if;

  -- Find the original invoice and its obligation
  select * into v_invoice from public.supplier_invoices
  where id = v_credit.supplier_invoice_id and organization_id = p_organization_id;
  if v_invoice.cost_obligation_id is null then raise exception 'original invoice has no obligation'; end if;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_expense from public.semantic_accounts where role = 'PROJECT_EXPENSE';

  -- Create a negative obligation (credit/reversal)
  insert into public.cost_obligations(
    organization_id, project_id, party_id, description, amount_minor_units,
    currency, transaction_date, cost_treatment, prepared_by,
    idempotency_key, request_hash, source_supplier_invoice_id
  ) values (
    p_organization_id, v_credit.project_id, v_invoice.party_id,
    'Supplier credit note ' || v_credit.credit_reference,
    v_credit.amount_minor_units, v_credit.currency, v_credit.credit_date,
    v_invoice.cost_treatment, v_credit.recorded_by,
    'p3-credit-obligation:' || v_credit.id::text, v_hash, v_credit.supplier_invoice_id
  ) returning id into v_obligation_id;

  -- Immediately authorize the reversal obligation
  v_batch_id := public.authorize_cost_obligation(
    p_organization_id, v_obligation_id, 'p3-credit-authorize:' || v_credit.id::text);

  -- The journal: credit payable (reduce liability), debit expense (reduce cost)
  -- Swap debit/credit from the original obligation posting to effect a reversal
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_credit.project_id, v_payable,
     0, v_credit.amount_minor_units, v_credit.currency,
     v_obligation_id, v_invoice.party_id, v_credit.credit_date),
    (v_batch_id, p_organization_id, v_credit.project_id, v_expense,
     v_credit.amount_minor_units, 0, v_credit.currency,
     v_obligation_id, v_invoice.party_id, v_credit.credit_date);

  update public.supplier_credit_notes
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key), approve_request_hash = v_hash,
         reversal_obligation_id = v_obligation_id, authorization_batch_id = v_batch_id
   where id = p_credit_note_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREDIT_NOTE_APPROVED', 'supplier_credit_note', p_credit_note_id,
    jsonb_build_object('reversal_obligation_id', v_obligation_id, 'authorization_batch_id', v_batch_id,
      'amount_minor_units', v_credit.amount_minor_units, 'currency', v_credit.currency));
  return v_obligation_id;
end $$;

-- 5c. Record an unapplied payment (no obligation yet)
create or replace function public.record_unapplied_payment(
  p_organization_id uuid,
  p_project_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_payment_date date,
  p_description text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payment_id uuid := gen_random_uuid();
  v_hash text;
  v_existing record;
  v_account record;
  v_batch_id uuid;
  v_payable uuid;
  v_cash uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'payment amount must be positive';
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'cash_account_id', p_cash_account_id,
    'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
    'payment_date', p_payment_date
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-unapplied:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.project_payments
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then return v_existing.id; end if;

  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;

  insert into public.project_payments(
    id, organization_id, project_id, cash_account_id,
    amount_minor_units, currency, payment_date, paid_by,
    idempotency_key, request_hash, allocation_status
  ) values (
    v_payment_id, p_organization_id, p_project_id, p_cash_account_id,
    p_amount_minor_units, p_currency, p_payment_date, v_actor,
    trim(p_idempotency_key), v_hash, 'UNAPPLIED'
  );

  select id into v_cash from public.semantic_accounts where role = 'BANK_CASH';
  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'PAYMENT', v_payment_id, p_payment_date,
    'p3-unapplied-batch-' || v_payment_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency, cash_account_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_payable,
     p_amount_minor_units, 0, p_currency, null, p_payment_date),
    (v_batch_id, p_organization_id, p_project_id, v_cash,
     0, p_amount_minor_units, p_currency, p_cash_account_id, p_payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'UNAPPLIED_PAYMENT_RECORDED', 'project_payment', v_payment_id,
    jsonb_build_object('project_id', p_project_id, 'amount_minor_units', p_amount_minor_units,
      'currency', p_currency, 'cash_account_id', p_cash_account_id));
  return v_payment_id;
end $$;

-- 5d. Allocate an unapplied payment to an obligation
create or replace function public.allocate_payment(
  p_organization_id uuid,
  p_payment_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_payment record;
  v_obligation record;
  v_allocated_numeric numeric;
  v_paid_numeric numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'allocation amount must be positive';
  end if;

  v_hash := encode(digest(p_payment_id::text || '|' || p_obligation_id::text || '|' || p_amount_minor_units::text,
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-allocate:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.payment_allocations
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then return v_existing.id; end if;

  select * into v_payment from public.project_payments
  where id = p_payment_id and organization_id = p_organization_id for update;
  if not found then raise exception 'payment not found'; end if;

  select * into v_obligation from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.project_id <> v_payment.project_id then
    raise exception 'obligation does not belong to the same project';
  end if;
  if v_obligation.currency <> v_payment.currency then
    raise exception 'obligation and payment currency must match';
  end if;

  -- Check ceiling: allocated <= payment amount
  select coalesce(sum(allocated_minor_units::numeric), 0) into v_allocated_numeric
  from public.payment_allocations where payment_id = p_payment_id;
  if v_allocated_numeric + p_amount_minor_units > v_payment.amount_minor_units then
    raise exception 'allocation exceeds payment amount';
  end if;

  -- Check ceiling: total payments allocated to obligation <= obligation amount
  select coalesce(sum(pa.allocated_minor_units::numeric), 0) into v_paid_numeric
  from public.payment_allocations pa
  join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pa.payment_id
  where pa.obligation_id = p_obligation_id
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id);
  if v_paid_numeric + p_amount_minor_units > v_obligation.amount_minor_units then
    raise exception 'allocation exceeds obligation amount';
  end if;

  insert into public.payment_allocations(
    organization_id, project_id, payment_id, obligation_id,
    allocated_minor_units, currency, allocated_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_payment.project_id, p_payment_id, p_obligation_id,
    p_amount_minor_units, v_payment.currency, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  -- Update payment allocation status
  update public.project_payments
     set allocation_status = case
       when v_allocated_numeric + p_amount_minor_units >= v_payment.amount_minor_units then 'ALLOCATED'
       else 'PARTIALLY_ALLOCATED'
     end
   where id = p_payment_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_ALLOCATED', 'payment_allocation', v_id,
    jsonb_build_object('payment_id', p_payment_id, 'obligation_id', p_obligation_id,
      'allocated_minor_units', p_amount_minor_units));
  return v_id;
end $$;

-- 5e. Record supplier advance (prepayment)
create or replace function public.record_supplier_advance(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_advance_reference text,
  p_advance_date date,
  p_currency text,
  p_amount_minor_units bigint,
  p_description text,
  p_evidence_reference text,
  p_payment_id uuid,
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
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'advance amount must be positive';
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
    'advance_reference', trim(p_advance_reference), 'advance_date', p_advance_date,
    'currency', p_currency, 'amount_minor_units', p_amount_minor_units,
    'description', p_description, 'evidence_reference', p_evidence_reference,
    'payment_id', p_payment_id
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-advance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_advances
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then return v_existing.id; end if;

  insert into public.supplier_advances(
    organization_id, project_id, supplier_party_id, advance_reference, advance_date,
    currency, amount_minor_units, description, evidence_reference, payment_id,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_supplier_party_id, trim(p_advance_reference),
    p_advance_date, p_currency, p_amount_minor_units, nullif(trim(p_description), ''),
    nullif(trim(p_evidence_reference), ''), p_payment_id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_RECORDED', 'supplier_advance', v_id,
    jsonb_build_object('project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
      'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
      'payment_id', p_payment_id, 'advance_date', p_advance_date));
  return v_id;
end $$;

-- 5f. Apply advance against a supplier invoice
create or replace function public.apply_supplier_advance(
  p_organization_id uuid,
  p_advance_id uuid,
  p_supplier_invoice_id uuid,
  p_applied_amount_minor_units bigint,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_advance record;
  v_applied_numeric numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_applied_amount_minor_units is null or p_applied_amount_minor_units <= 0 then
    raise exception 'application amount must be positive';
  end if;

  v_hash := encode(digest(p_advance_id::text || '|' || p_supplier_invoice_id::text || '|' || p_applied_amount_minor_units::text,
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-apply-advance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_advance_applications
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then return v_existing.id; end if;

  select * into v_advance from public.supplier_advances
  where id = p_advance_id and organization_id = p_organization_id for update;
  if not found then raise exception 'advance not found'; end if;

  select coalesce(sum(applied_amount_minor_units::numeric), 0) into v_applied_numeric
  from public.supplier_advance_applications where advance_id = p_advance_id;
  if v_applied_numeric + p_applied_amount_minor_units > v_advance.amount_minor_units then
    raise exception 'application exceeds advance amount';
  end if;

  insert into public.supplier_advance_applications(
    organization_id, project_id, advance_id, supplier_invoice_id,
    applied_amount_minor_units, currency, applied_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_advance.project_id, p_advance_id, p_supplier_invoice_id,
    p_applied_amount_minor_units, v_advance.currency, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  update public.supplier_advances
     set status = case
       when v_applied_numeric + p_applied_amount_minor_units >= v_advance.amount_minor_units then 'FULLY_APPLIED'
       else 'PARTIALLY_APPLIED'
     end
   where id = p_advance_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_APPLIED', 'supplier_advance_application', v_id,
    jsonb_build_object('advance_id', p_advance_id, 'supplier_invoice_id', p_supplier_invoice_id,
      'applied_amount_minor_units', p_applied_amount_minor_units));
  return v_id;
end $$;

-- ===========================================================================
-- 6. RLS, grants, read models
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array[
    'supplier_credit_notes','payment_allocations',
    'supplier_advances','supplier_advance_applications'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t||'_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

revoke all on function
  public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.approve_supplier_credit_note(uuid,uuid,text),
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,uuid,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text)
  from public, anon;
grant execute on function
  public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.approve_supplier_credit_note(uuid,uuid,text),
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,uuid,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text)
  to authenticated;

do $pgcrypto_compat_p3$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
  v_commands text[] := array[
    'approve_supplier_credit_note','record_unapplied_payment',
    'allocate_payment','record_supplier_advance','apply_supplier_advance',
    'record_supplier_credit_note'
  ];
begin
  select n.nspname into v_pgcrypto_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;
  for v_record in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
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
$pgcrypto_compat_p3$;