-- P3 — Credits, Payment Allocation and Advances.
--
-- Extends the shared Finance Core with policy-independent supplier-side
-- capabilities. The accounting follows the canonical Project Financial
-- Subledger contract: every posting is a balanced journal batch with exact
-- money; no fake invoice is ever created to justify an advance.
--
-- Flow (per mission P3):
--   Supplier Advance → Payment (cash out) → Prepaid Asset (unapplied balance)
--   → Future Vendor Bill → Advance Application → Remaining Payable
--
-- 1. Supplier Credit Notes: a supplier's credit reduces the payable and the
--    original cost account (Dr Supplier Payable / Cr Expense-or-WIP). It is
--    the exact opposite of the original invoice posting, never an addition.
--
-- 2. Unapplied Payments: cash paid with no obligation yet is booked as a
--    Prepaid Asset (Dr Prepaid Asset / Cr Bank Cash), NOT as a payable.
--    Later allocation to an obligation settles it (Dr Supplier Payable /
--    Cr Prepaid Asset).
--
-- 3. Payment Allocation (many-to-many): one unapplied payment may be
--    allocated across several obligations with exact ceiling protection.
--
-- 4. Supplier Advances / Prepayments: an advance is an unapplied payment
--    designated against a supplier. Advance application reduces the payable.
--
-- No COGS, inventory valuation, tax, or business-policy numbers are invented.
-- Customer-side credit notes are deferred until a customer invoice model
-- exists.

-- ===========================================================================
-- 1. Extend the locked shared-core registries (forward-only, GF-024 pattern).
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE',
  'PREPAID_ASSET'
));
insert into public.semantic_accounts(role, label_ar)
values 

-- ===========================================================================
-- Authoritative obligation settlement function.
-- Every command that reduces the payable must lock the obligation row with
-- FOR UPDATE and use this function to verify the ceiling.
-- ===========================================================================
create or replace function public.obligation_active_outstanding_minor_units(
  p_organization_id uuid,
  p_obligation_id uuid
) returns bigint
language sql stable set search_path=pg_catalog,public as $$
  select coalesce(o.amount_minor_units, 0)
    - coalesce((
        select sum(pp.amount_minor_units) from public.project_payments pp
        join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
        where pp.obligation_id = p_obligation_id and pp.organization_id = p_organization_id
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
    ), 0)
    - coalesce((
        select sum(cn.amount_minor_units) from public.supplier_credit_notes cn
        join public.supplier_invoices si on si.id = cn.supplier_invoice_id
        where si.cost_obligation_id = p_obligation_id
          and cn.organization_id = p_organization_id and cn.status = 'APPROVED'
    ), 0)
    - coalesce((
        select sum(aa.applied_amount_minor_units) from public.supplier_advance_applications aa
        join public.supplier_invoices si on si.id = aa.supplier_invoice_id
        where si.cost_obligation_id = p_obligation_id
          and aa.organization_id = p_organization_id
    ), 0)
    - coalesce((
        select sum(pa.allocated_minor_units) from public.payment_allocations pa
        where pa.obligation_id = p_obligation_id and pa.organization_id = p_organization_id
    ), 0)
  from public.cost_obligations o
  where o.id = p_obligation_id and o.organization_id = p_organization_id
$$;
comment on function public.obligation_active_outstanding_minor_units is
  'Authoritative settlement calculation: original obligation minus all active payments, credit notes, advance applications, and allocations.';

('PREPAID_ASSET','أصل مدفوع مقدم / سلف موردين')
on conflict (role) do nothing;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT','AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION',
  'LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION',
  'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION',
  'SUPPLIER_ADVANCE_APPLICATION'
));

-- ===========================================================================
-- 2. Unapplied payments (prepaid asset leg)
-- ===========================================================================
create table public.unapplied_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  cash_account_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_date date not null,
  description text check (description is null or char_length(trim(description)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (cash_account_id, project_id, organization_id)
    references public.project_cash_accounts(id, project_id, organization_id) on delete restrict
);
create index unapplied_payments_project_idx
  on public.unapplied_payments(project_id, payment_date desc);

-- ===========================================================================
-- 3. Payment allocations (many-to-many: unapplied payment -> obligation)
-- ===========================================================================
create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  unapplied_payment_id uuid not null,
  obligation_id uuid not null,
  allocated_minor_units bigint not null check (allocated_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  allocated_by uuid not null references auth.users(id) on delete restrict,
  allocated_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (unapplied_payment_id, organization_id)
    references public.unapplied_payments(id, organization_id) on delete restrict,
  foreign key (obligation_id, project_id, organization_id)
    references public.cost_obligations(id, project_id, organization_id) on delete restrict
);
create index payment_allocations_payment_idx on public.payment_allocations(unapplied_payment_id);
create index payment_allocations_obligation_idx on public.payment_allocations(obligation_id);

-- ===========================================================================
-- 4. Supplier advances / prepayments
-- ===========================================================================
create table public.supplier_advances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_party_id uuid not null,
  advance_reference text not null check (char_length(trim(advance_reference)) between 1 and 120),
  advance_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  description text check (description is null or char_length(trim(description)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  unapplied_payment_id uuid not null,
  status text not null default 'UNAPPLIED'
    check (status in ('UNAPPLIED','PARTIALLY_APPLIED','FULLY_APPLIED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, project_id, lower(trim(advance_reference))),
  unique (organization_id, idempotency_key),
  unique (unapplied_payment_id),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  foreign key (unapplied_payment_id, organization_id)
    references public.unapplied_payments(id, organization_id) on delete restrict
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
  journal_batch_id uuid not null,
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (journal_batch_id),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (advance_id, organization_id)
    references public.supplier_advances(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index supplier_advance_applications_advance_idx on public.supplier_advance_applications(advance_id);
create index supplier_advance_applications_invoice_idx on public.supplier_advance_applications(supplier_invoice_id);

-- ===========================================================================
-- 5. Supplier credit notes (reduction of payable and cost)
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
  status text not null default 'RECORDED' check (status in ('RECORDED','APPROVED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approve_idempotency_key text
    check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text
    check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  authorization_batch_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (approved_by is null or approved_by <> recorded_by),
  check (
    (status = 'RECORDED' and approved_by is null and approved_at is null
      and approve_idempotency_key is null and approve_request_hash is null
      and authorization_batch_id is null)
    or
    (status = 'APPROVED' and approved_by is not null and approved_at is not null
      and approve_idempotency_key is not null and approve_request_hash is not null
      and authorization_batch_id is not null)
  ),
  unique (organization_id, supplier_invoice_id, lower(trim(credit_reference))),
  unique (organization_id, idempotency_key),
  unique (authorization_batch_id),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, project_id, organization_id)
    references public.supplier_invoices(id, project_id, organization_id) on delete restrict,
  foreign key (authorization_batch_id, project_id, organization_id)
    references public.journal_batches(id, project_id, organization_id) on delete restrict
);
create unique index supplier_credit_notes_approve_key
  on public.supplier_credit_notes(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;
create index supplier_credit_notes_invoice_idx on public.supplier_credit_notes(supplier_invoice_id);
create index supplier_credit_notes_project_idx on public.supplier_credit_notes(project_id, credit_date desc);

-- ===========================================================================
-- 6. Immutability and controlled state transitions
-- ===========================================================================
create or replace function public.p3_guard_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'credit note, allocation, advance-application and unapplied-payment records are append-only';
end $$;

-- Unapplied payments: fully append-only (status is derived in read models).
create trigger unapplied_payments_no_change
  before update or delete on public.unapplied_payments
  for each row execute function public.p3_guard_append_only();
create trigger payment_allocations_no_change
  before update or delete on public.payment_allocations
  for each row execute function public.p3_guard_append_only();
create trigger supplier_advance_applications_no_change
  before update or delete on public.supplier_advance_applications
  for each row execute function public.p3_guard_append_only();

-- Supplier advances: DELETE forbidden; economics immutable; only the status
-- may change through the controlled application transitions.
create or replace function public.p3_guard_advance_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.supplier_party_id is distinct from old.supplier_party_id
     or new.advance_reference is distinct from old.advance_reference
     or new.advance_date is distinct from old.advance_date
     or new.currency is distinct from old.currency
     or new.amount_minor_units is distinct from old.amount_minor_units
     or new.description is distinct from old.description
     or new.evidence_reference is distinct from old.evidence_reference
     or new.unapplied_payment_id is distinct from old.unapplied_payment_id
     or new.recorded_by is distinct from old.recorded_by
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash then
    raise exception 'supplier advance economics are immutable';
  end if;
  -- Controlled status transitions only: UNAPPLIED -> PARTIALLY_APPLIED/FULLY_APPLIED
  -- and PARTIALLY_APPLIED -> FULLY_APPLIED.
  if not (
    (old.status = 'UNAPPLIED' and new.status in ('PARTIALLY_APPLIED','FULLY_APPLIED'))
    or (old.status = 'PARTIALLY_APPLIED' and new.status = 'FULLY_APPLIED')
  ) then
    raise exception 'invalid supplier advance status transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;
create trigger supplier_advances_no_delete
  before delete on public.supplier_advances
  for each row execute function public.p3_guard_append_only();
create trigger supplier_advances_transition_guard
  before update on public.supplier_advances
  for each row execute function public.p3_guard_advance_transition();

-- Supplier credit notes: DELETE forbidden; RECORDED -> APPROVED is the only
-- update transition; economics are immutable.
create or replace function public.p3_guard_credit_note_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.supplier_invoice_id is distinct from old.supplier_invoice_id
     or new.credit_reference is distinct from old.credit_reference
     or new.credit_date is distinct from old.credit_date
     or new.currency is distinct from old.currency
     or new.amount_minor_units is distinct from old.amount_minor_units
     or new.reason is distinct from old.reason
     or new.evidence_reference is distinct from old.evidence_reference
     or new.recorded_by is distinct from old.recorded_by
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash then
    raise exception 'supplier credit note economics are immutable';
  end if;
  if not (
    old.status = 'RECORDED' and new.status = 'APPROVED'
    and new.approved_by is not null and new.approved_by <> new.recorded_by
    and new.approved_at is not null
    and new.approve_idempotency_key is not null
    and new.approve_request_hash is not null
    and new.authorization_batch_id is not null
  ) then
    raise exception 'only a RECORDED credit note can be approved by a different authority';
  end if;
  return new;
end $$;
create trigger supplier_credit_notes_no_delete
  before delete on public.supplier_credit_notes
  for each row execute function public.p3_guard_append_only();
create trigger supplier_credit_notes_transition_guard
  before update on public.supplier_credit_notes
  for each row execute function public.p3_guard_credit_note_transition();

-- ===========================================================================
-- 7. Commands
-- ===========================================================================

-- 7a. Record an unapplied payment:
--     Dr PREPAID_ASSET / Cr BANK_CASH (never a payable before an obligation).
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
  v_prepaid uuid;
  v_cash uuid;
  v_available bigint;
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
  if p_payment_date is null then raise exception 'payment date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_description is not null and char_length(trim(p_description)) not between 3 and 500 then
    raise exception 'invalid payment description';
  end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'invalid evidence reference';
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'cash_account_id', p_cash_account_id,
    'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
    'payment_date', p_payment_date, 'description', p_description,
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-unapplied:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.unapplied_payments
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency <> p_currency then raise exception 'cash account currency mismatch'; end if;

  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if p_amount_minor_units > v_available then
    raise exception 'unapplied payment exceeds available cash';
  end if;

  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';
  select id into v_cash from public.semantic_accounts where role = 'BANK_CASH';

  insert into public.unapplied_payments(
    id, organization_id, project_id, cash_account_id, amount_minor_units,
    currency, payment_date, description, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    v_payment_id, p_organization_id, p_project_id, p_cash_account_id,
    p_amount_minor_units, p_currency, p_payment_date,
    nullif(trim(p_description), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  );

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'UNAPPLIED_PAYMENT', v_payment_id, p_payment_date,
    'p3-unapplied-batch-' || v_payment_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    cash_account_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_prepaid,
     p_amount_minor_units, 0, p_currency,
     null, p_payment_date),
    (v_batch_id, p_organization_id, p_project_id, v_cash,
     0, p_amount_minor_units, p_currency,
     p_cash_account_id, p_payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'UNAPPLIED_PAYMENT_RECORDED', 'unapplied_payment', v_payment_id,
    jsonb_build_object('project_id', p_project_id, 'amount_minor_units', p_amount_minor_units,
      'currency', p_currency, 'cash_account_id', p_cash_account_id, 'journal_batch_id', v_batch_id));
  return v_payment_id;
end $$;

-- 7b. Allocate an unapplied payment to an obligation:
--     Dr SUPPLIER_PAYABLE / Cr PREPAID_ASSET.
create or replace function public.allocate_payment(
  p_organization_id uuid,
  p_unapplied_payment_id uuid,
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
  v_outstanding bigint;
  v_paid_numeric numeric;
  v_batch_id uuid;
  v_payable uuid;
  v_prepaid uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'allocation amount must be positive';
  end if;

  v_hash := encode(digest(p_unapplied_payment_id::text || '|' || p_obligation_id::text || '|' || p_amount_minor_units::text,
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-allocate:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.payment_allocations
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_payment from public.unapplied_payments
  where id = p_unapplied_payment_id and organization_id = p_organization_id for update;
  if not found then raise exception 'unapplied payment not found'; end if;

  select * into v_obligation from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.project_id <> v_payment.project_id then
    raise exception 'obligation does not belong to the same project';
  end if;
  if v_obligation.currency <> v_payment.currency then
    raise exception 'obligation and unapplied payment currency must match';
  end if;

  -- Ceiling 1: allocations cannot exceed the unapplied payment.
  select coalesce(sum(allocated_minor_units::numeric), 0) into v_allocated_numeric
  from public.payment_allocations where unapplied_payment_id = p_unapplied_payment_id;
  if v_allocated_numeric + p_amount_minor_units > v_payment.amount_minor_units then
    raise exception 'allocation exceeds unapplied payment amount';
  end if;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';

  insert into public.payment_allocations(
    organization_id, project_id, unapplied_payment_id, obligation_id,
    allocated_minor_units, currency, allocated_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_payment.project_id, p_unapplied_payment_id, p_obligation_id,
    p_amount_minor_units, v_payment.currency, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_payment.project_id, 'PAYMENT_ALLOCATION', v_id, v_payment.payment_date,
    'p3-allocation-batch-' || v_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_payment.project_id, v_payable,
     p_amount_minor_units, 0, v_payment.currency,
     p_obligation_id, v_obligation.party_id, v_payment.payment_date),
    (v_batch_id, p_organization_id, v_payment.project_id, v_prepaid,
     0, p_amount_minor_units, v_payment.currency,
     null, null, v_payment.payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_ALLOCATED', 'payment_allocation', v_id,
    jsonb_build_object('unapplied_payment_id', p_unapplied_payment_id, 'obligation_id', p_obligation_id,
      'allocated_minor_units', p_amount_minor_units, 'journal_batch_id', v_batch_id));
  return v_id;
end $$;

-- 7c. Record a supplier advance (creates the prepaid-asset payment leg and
--     the advance header atomically). NEVER a fake invoice.
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
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_payment_id uuid := gen_random_uuid();
  v_batch_id uuid;
  v_account record;
  v_prepaid uuid;
  v_cash uuid;
  v_available bigint;
  v_payment_hash text;
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
  if p_advance_date is null then raise exception 'advance date required'; end if;
  if p_advance_reference is null or char_length(trim(p_advance_reference)) not between 1 and 120 then
    raise exception 'invalid advance reference';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
    'advance_reference', trim(p_advance_reference), 'advance_date', p_advance_date,
    'currency', p_currency, 'amount_minor_units', p_amount_minor_units,
    'cash_account_id', p_cash_account_id, 'description', p_description,
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-advance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_advances
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if not exists (select 1 from public.parties
    where id = p_supplier_party_id and organization_id = p_organization_id) then
    raise exception 'supplier party not found';
  end if;

  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency <> p_currency then raise exception 'cash account currency mismatch'; end if;

  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if p_amount_minor_units > v_available then
    raise exception 'advance exceeds available cash';
  end if;

  v_payment_hash := encode(digest(v_payment_id::text || '|advance-payment', 'sha256'), 'hex');
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';
  select id into v_cash from public.semantic_accounts where role = 'BANK_CASH';

  insert into public.unapplied_payments(
    id, organization_id, project_id, cash_account_id, amount_minor_units,
    currency, payment_date, description, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    v_payment_id, p_organization_id, p_project_id, p_cash_account_id,
    p_amount_minor_units, p_currency, p_advance_date,
    nullif(trim(p_description), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, 'p3-advance-payment:' || v_payment_id::text, v_payment_hash
  );

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'UNAPPLIED_PAYMENT', v_payment_id, p_advance_date,
    'p3-advance-batch-' || v_payment_id::text, v_payment_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    cash_account_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_prepaid,
     p_amount_minor_units, 0, p_currency,
     null, p_advance_date),
    (v_batch_id, p_organization_id, p_project_id, v_cash,
     0, p_amount_minor_units, p_currency,
     p_cash_account_id, p_advance_date);

  insert into public.supplier_advances(
    organization_id, project_id, supplier_party_id, advance_reference, advance_date,
    currency, amount_minor_units, description, evidence_reference, unapplied_payment_id,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_supplier_party_id, trim(p_advance_reference),
    p_advance_date, p_currency, p_amount_minor_units, nullif(trim(p_description), ''),
    nullif(trim(p_evidence_reference), ''), v_payment_id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_RECORDED', 'supplier_advance', v_id,
    jsonb_build_object('project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
      'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
      'cash_account_id', p_cash_account_id, 'unapplied_payment_id', v_payment_id,
      'journal_batch_id', v_batch_id, 'advance_date', p_advance_date));
  return v_id;
end $$;

-- 7d. Apply an advance against a supplier invoice:
--     Dr SUPPLIER_PAYABLE / Cr PREPAID_ASSET, reducing remaining payable.
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
  v_invoice record;
  v_obligation record;
  v_outstanding bigint;
  v_applied_numeric numeric;
  v_remaining_advance numeric;
  v_batch_id uuid;
  v_payable uuid;
  v_prepaid uuid;
  v_new_status text;
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
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_advance from public.supplier_advances
  where id = p_advance_id and organization_id = p_organization_id for update;
  if not found then raise exception 'advance not found'; end if;

  select * into v_invoice from public.supplier_invoices
  where id = p_supplier_invoice_id and project_id = v_advance.project_id
    and organization_id = p_organization_id;
  if not found then raise exception 'supplier invoice not found'; end if;
  if v_invoice.status <> 'APPROVED' then raise exception 'advance application requires an approved supplier invoice'; end if;
  if v_invoice.cost_obligation_id is null then raise exception 'invoice has no payable obligation'; end if;
  if v_invoice.currency <> v_advance.currency then raise exception 'advance and invoice currency must match'; end if;

  -- Supplier coherence: the advance supplier must match the invoice party.
  if v_advance.supplier_party_id <> v_invoice.party_id then
    raise exception 'advance supplier % does not match invoice supplier %; cannot apply one supplier advance to another supplier invoice',
      v_advance.supplier_party_id, v_invoice.party_id;
  end if;

  -- Lock the obligation and check the authoritative settlement ceiling.
  select * into v_obligation from public.cost_obligations
  where id = v_invoice.cost_obligation_id and organization_id = p_organization_id
  for update;
  v_outstanding := public.obligation_active_outstanding_minor_units(
    p_organization_id, v_invoice.cost_obligation_id);
  if p_applied_amount_minor_units > v_outstanding then
    raise exception 'advance application of % exceeds current outstanding payable % on obligation',
      p_applied_amount_minor_units, v_outstanding;
  end if;

  -- Ceiling: applications cannot exceed the advance.
  select coalesce(sum(applied_amount_minor_units::numeric), 0) into v_applied_numeric
  from public.supplier_advance_applications where advance_id = p_advance_id;
  if v_applied_numeric + p_applied_amount_minor_units > v_advance.amount_minor_units then
    raise exception 'application exceeds advance amount';
  end if;
  v_new_status := case when v_advance.amount_minor_units - v_applied_numeric - p_applied_amount_minor_units <= 0
    then 'FULLY_APPLIED' else 'PARTIALLY_APPLIED' end;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_advance.project_id, 'SUPPLIER_ADVANCE_APPLICATION',
    v_application_id, v_invoice.invoice_date,
    'p3-apply-advance-batch:' || v_application_id::text,
    v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_advance.project_id, v_payable,
     p_applied_amount_minor_units, 0, v_advance.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_invoice.invoice_date),
    (v_batch_id, p_organization_id, v_advance.project_id, v_prepaid,
     0, p_applied_amount_minor_units, v_advance.currency,
     null, null, v_invoice.invoice_date);

  insert into public.supplier_advance_applications(
    organization_id, project_id, advance_id, supplier_invoice_id,
    applied_amount_minor_units, currency, journal_batch_id,
    applied_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_advance.project_id, p_advance_id, p_supplier_invoice_id,
    p_applied_amount_minor_units, v_advance.currency, v_batch_id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  update public.supplier_advances
     set status = v_new_status
   where id = p_advance_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_APPLIED', 'supplier_advance_application', v_id,
    jsonb_build_object('advance_id', p_advance_id, 'supplier_invoice_id', p_supplier_invoice_id,
      'applied_amount_minor_units', p_applied_amount_minor_units, 'journal_batch_id', v_batch_id,
      'advance_status', v_new_status));
  return v_id;
end $$;

-- 7e. Record a supplier credit note (no financial effect until approved)
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
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'credit note reason is required';
  end if;
  if p_credit_date is null then raise exception 'credit date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;

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

-- 7f. Approve a credit note: REVERSES the original invoice's payable and cost
--     accounts. The journal is the exact opposite of the invoice posting:
--       Dr SUPPLIER_PAYABLE / Cr PROJECT_EXPENSE (or DEVELOPMENT_WIP).
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
  v_batch_id uuid;
  v_payable uuid;
  v_credit_account uuid;
  v_credited_numeric numeric;
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
  if found then
    if v_existing.id is distinct from p_credit_note_id
       or v_existing.approve_request_hash IS DISTINCT FROM v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.authorization_batch_id;
  end if;

  select * into v_credit from public.supplier_credit_notes
  where id = p_credit_note_id and organization_id = p_organization_id for update;
  if not found then raise exception 'credit note not found'; end if;
  if v_credit.status <> 'RECORDED' then raise exception 'credit note is not in RECORDED state'; end if;
  if v_credit.recorded_by = v_actor then raise exception 'maker/checker: credit recorder cannot approve'; end if;

  select * into v_invoice from public.supplier_invoices
  where id = v_credit.supplier_invoice_id and organization_id = p_organization_id;
  if v_invoice.status <> 'APPROVED' or v_invoice.cost_obligation_id is null then
    raise exception 'credit note requires an approved supplier invoice with a payable obligation';
  end if;
  if v_invoice.currency <> v_credit.currency then raise exception 'credit note currency must match invoice'; end if;

  -- Ceiling: total approved credits for this invoice cannot exceed its total.
  select coalesce(sum(c.amount_minor_units::numeric), 0) into v_credited_numeric
  from public.supplier_credit_notes c
  where c.supplier_invoice_id = v_credit.supplier_invoice_id
    and c.organization_id = p_organization_id
    and c.status = 'APPROVED';
  select coalesce(sum(sil.line_amount_minor_units::numeric), 0) into v_credited_numeric
  from public.supplier_invoice_lines sil
  where sil.supplier_invoice_id = v_credit.supplier_invoice_id
    and sil.organization_id = p_organization_id
  limit 1;
  if (select coalesce(sum(c.amount_minor_units::numeric), 0)
      from public.supplier_credit_notes c
      where c.supplier_invoice_id = v_credit.supplier_invoice_id
        and c.organization_id = p_organization_id
        and c.status = 'APPROVED')
     + v_credit.amount_minor_units > v_credited_numeric then
    raise exception 'credit notes exceed the supplier invoice total';
  end if;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  if v_invoice.cost_treatment = 'EXPENSE' then
    select id into v_credit_account from public.semantic_accounts where role = 'PROJECT_EXPENSE';
  else
    select id into v_credit_account from public.semantic_accounts where role = 'DEVELOPMENT_WIP';
  end if;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_credit.project_id, 'SUPPLIER_CREDIT_NOTE', p_credit_note_id,
    v_credit.credit_date, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  -- Reversal of the original invoice posting: Dr Payable / Cr Cost account.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_credit.project_id, v_payable,
     v_credit.amount_minor_units, 0, v_credit.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_credit.credit_date),
    (v_batch_id, p_organization_id, v_credit.project_id, v_credit_account,
     0, v_credit.amount_minor_units, v_credit.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_credit.credit_date);

  update public.supplier_credit_notes
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key), approve_request_hash = v_hash,
         authorization_batch_id = v_batch_id
   where id = p_credit_note_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREDIT_NOTE_APPROVED', 'supplier_credit_note', p_credit_note_id,
    jsonb_build_object('authorization_batch_id', v_batch_id,
      'amount_minor_units', v_credit.amount_minor_units, 'currency', v_credit.currency,
      'accounting_direction', 'REVERSAL_OF_INVOICE'));
  return v_batch_id;
end $$;

-- ===========================================================================
-- 8. Read models
-- ===========================================================================
create or replace view public.unapplied_payments_read with (security_invoker=on) as
select p.id as unapplied_payment_id, p.organization_id, p.project_id,
       p.cash_account_id, ca.name as cash_account_name,
       p.amount_minor_units::text as amount_minor_units, p.currency,
       p.payment_date, p.description, p.evidence_reference,
       p.recorded_by, p.recorded_at,
       coalesce(alloc.allocated_minor_units, 0)::text as allocated_minor_units,
       coalesce(advapp.applied_minor_units, 0)::text as advance_applied_minor_units,
       greatest(
         p.amount_minor_units
         - coalesce(alloc.allocated_minor_units, 0)
         - coalesce(advapp.applied_minor_units, 0), 0)::text as remaining_minor_units
from public.unapplied_payments p
join public.project_cash_accounts ca
  on ca.id = p.cash_account_id and ca.organization_id = p.organization_id
left join (
  select unapplied_payment_id, sum(allocated_minor_units) as allocated_minor_units
  from public.payment_allocations group by unapplied_payment_id
) alloc on alloc.unapplied_payment_id = p.id
left join (
  select a.unapplied_payment_id, sum(saa.applied_amount_minor_units) as applied_minor_units
  from public.supplier_advances a
  join public.supplier_advance_applications saa on saa.advance_id = a.id
  group by a.unapplied_payment_id
) advapp on advapp.unapplied_payment_id = p.id;

create or replace view public.payment_allocations_read with (security_invoker=on) as
select pa.id as allocation_id, pa.organization_id, pa.project_id,
       pa.unapplied_payment_id, pa.obligation_id,
       o.description as obligation_description,
       pa.allocated_minor_units::text as allocated_minor_units,
       pa.currency, pa.allocated_by, pa.allocated_at
from public.payment_allocations pa
join public.cost_obligations o
  on o.id = pa.obligation_id and o.organization_id = pa.organization_id;

create or replace view public.supplier_advances_read with (security_invoker=on) as
select a.id as advance_id, a.organization_id, a.project_id,
       a.supplier_party_id, p.legal_name as supplier_name,
       a.advance_reference, a.advance_date, a.currency,
       a.amount_minor_units::text as amount_minor_units,
       coalesce(applied.applied_minor_units, 0)::text as applied_minor_units,
       greatest(a.amount_minor_units - coalesce(applied.applied_minor_units, 0), 0)::text
         as remaining_minor_units,
       a.status, a.unapplied_payment_id, a.recorded_by, a.recorded_at
from public.supplier_advances a
join public.parties p on p.id = a.supplier_party_id and p.organization_id = a.organization_id
left join (
  select advance_id, sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications group by advance_id
) applied on applied.advance_id = a.id;

create or replace view public.supplier_advance_applications_read with (security_invoker=on) as
select saa.id as application_id, saa.organization_id, saa.project_id,
       saa.advance_id, a.advance_reference, saa.supplier_invoice_id,
       i.invoice_reference, saa.applied_amount_minor_units::text as applied_amount_minor_units,
       saa.currency, saa.journal_batch_id, saa.applied_by, saa.applied_at
from public.supplier_advance_applications saa
join public.supplier_advances a on a.id = saa.advance_id
join public.supplier_invoices i on i.id = saa.supplier_invoice_id;

create or replace view public.supplier_credit_notes_read with (security_invoker=on) as
select c.id as credit_note_id, c.organization_id, c.project_id,
       c.supplier_invoice_id, i.invoice_reference,
       c.credit_reference, c.credit_date, c.currency,
       c.amount_minor_units::text as amount_minor_units,
       c.reason, c.evidence_reference, c.status,
       c.authorization_batch_id, c.recorded_by, c.recorded_at,
       c.approved_by, c.approved_at
from public.supplier_credit_notes c
join public.supplier_invoices i on i.id = c.supplier_invoice_id;

-- Supplier invoices: outstanding payable is reduced by approved credit notes
-- and advance applications (in addition to payments).
create or replace view public.supplier_invoices_read with (security_invoker=on) as
select i.id, i.organization_id, i.project_id, i.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       i.supplier_id, s.name as supplier_name, i.party_id,
       i.invoice_reference, i.invoice_date, i.currency, i.cost_treatment,
       i.evidence_reference, i.notes, i.status, i.recorded_by, i.recorded_at,
       i.approved_by, i.approved_at, i.cost_obligation_id, i.authorization_batch_id,
       i.supplier_stated_total_minor_units::text as supplier_stated_total_minor_units,
       totals.invoice_total_minor_units::text as invoice_total_minor_units,
       coalesce(pay.paid_minor_units, 0)::text as paid_minor_units,
       coalesce(credits.credited_minor_units, 0)::text as credited_minor_units,
       coalesce(advapp.applied_minor_units, 0)::text as advance_applied_minor_units,
       case when coalesce(op.is_reversed, false) then '0'
            else greatest(
              totals.invoice_total_minor_units
              - coalesce(pay.paid_minor_units, 0)
              - coalesce(credits.credited_minor_units, 0)
              - coalesce(advapp.applied_minor_units, 0), 0)::text
       end as outstanding_minor_units,
       coalesce(pay.reconciled_minor_units, 0)::text as reconciled_minor_units,
       coalesce(op.is_reversed, false) as payable_is_reversed,
       case
         when coalesce(op.is_reversed, false) then 'PAYABLE_REVERSED'
         when coalesce(pay.paid_minor_units, 0) = 0
              and coalesce(credits.credited_minor_units, 0) = 0
              and coalesce(advapp.applied_minor_units, 0) = 0 then 'UNPAID'
         when coalesce(pay.paid_minor_units, 0)
            + coalesce(credits.credited_minor_units, 0)
            + coalesce(advapp.applied_minor_units, 0) < totals.invoice_total_minor_units then 'PARTIALLY_PAID'
         else 'FULLY_PAID'
       end as payment_state,
       case
         when coalesce(pay.paid_minor_units, 0) = 0 then 'NOT_PAID'
         when coalesce(pay.reconciled_minor_units, 0) = 0 then 'PAID_UNRECONCILED'
         when pay.reconciled_minor_units < pay.paid_minor_units then 'PARTIALLY_RECONCILED'
         else 'RECONCILED'
       end as reconciliation_state,
       coalesce(pay.payment_count, 0)::integer as payment_count,
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
) pay on pay.source_supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(amount_minor_units) as credited_minor_units
  from public.supplier_credit_notes where status = 'APPROVED' group by supplier_invoice_id
) credits on credits.supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications group by supplier_invoice_id
) advapp on advapp.supplier_invoice_id = i.id;

-- ===========================================================================
-- 9. RLS, grants, immutability enforcement
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array[
    'unapplied_payments','payment_allocations',
    'supplier_advances','supplier_advance_applications','supplier_credit_notes'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t||'_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

grant select on
  public.unapplied_payments_read,
  public.payment_allocations_read,
  public.supplier_advances_read,
  public.supplier_advance_applications_read,
  public.supplier_credit_notes_read
  to authenticated;

revoke all on function
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text),
  public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.approve_supplier_credit_note(uuid,uuid,text)
  from public, anon;
grant execute on function
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text),
  public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text),
  public.approve_supplier_credit_note(uuid,uuid,text)
  to authenticated;

-- Trigger/helper functions are internal only.
revoke all on function
  public.p3_guard_append_only(),
  public.p3_guard_advance_transition(),
  public.p3_guard_credit_note_transition()
  from public, anon, authenticated;

-- pgcrypto schema compatibility for the new digest references
do $pgcrypto_compat_p3$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
  v_commands text[] := array[
    'record_unapplied_payment','allocate_payment',
    'record_supplier_advance','apply_supplier_advance',
    'record_supplier_credit_note','approve_supplier_credit_note'
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