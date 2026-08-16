-- P3 — Credits, payment allocations, and supplier advances.
--
-- Authoritative supplier-side settlement extensions for the shared Project
-- Financial Subledger. All money is exact bigint minor units. Posted journal
-- truth is append-only. Supplier advances are prepaid assets, never fake bills.

-- ===========================================================================
-- 1. Extend shared semantic registries.
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','PREPAID_ASSET'
));
insert into public.semantic_accounts(role, label_ar)
values ('PREPAID_ASSET','أصل مدفوع مقدم / سلف موردين')
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
  'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION','SUPPLIER_ADVANCE_APPLICATION'
));

-- ===========================================================================
-- 2. Settlement tables.
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
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (journal_batch_id),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index unapplied_payments_project_idx on public.unapplied_payments(project_id, payment_date desc);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  unapplied_payment_id uuid not null,
  obligation_id uuid not null,
  allocated_minor_units bigint not null check (allocated_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  allocation_date date not null,
  journal_batch_id uuid not null,
  allocated_by uuid not null references auth.users(id) on delete restrict,
  allocated_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (journal_batch_id),
  unique (id, organization_id),
  foreign key (unapplied_payment_id, organization_id)
    references public.unapplied_payments(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index payment_allocations_payment_idx on public.payment_allocations(unapplied_payment_id);
create index payment_allocations_obligation_idx on public.payment_allocations(obligation_id);

create table public.supplier_advances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_party_id uuid not null,
  unapplied_payment_id uuid not null,
  advance_reference text not null check (char_length(trim(advance_reference)) between 1 and 120),
  advance_date date not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text check (description is null or char_length(trim(description)) between 3 and 500),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
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
  obligation_id uuid not null,
  applied_amount_minor_units bigint not null check (applied_amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  application_date date not null,
  journal_batch_id uuid not null,
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (journal_batch_id),
  unique (id, organization_id),
  foreign key (advance_id, organization_id)
    references public.supplier_advances(id, organization_id) on delete restrict,
  foreign key (supplier_invoice_id, organization_id)
    references public.supplier_invoices(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index supplier_advance_applications_advance_idx on public.supplier_advance_applications(advance_id);
create index supplier_advance_applications_invoice_idx on public.supplier_advance_applications(supplier_invoice_id);

create table public.supplier_credit_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_invoice_id uuid not null,
  obligation_id uuid not null,
  credit_reference text not null check (char_length(trim(credit_reference)) between 1 and 120),
  credit_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'RECORDED' check (status in ('RECORDED','APPROVED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  authorization_batch_id uuid,
  approve_idempotency_key text check (approve_idempotency_key is null or char_length(approve_idempotency_key) between 8 and 120),
  approve_request_hash text check (approve_request_hash is null or char_length(approve_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (approved_by is null or approved_by <> recorded_by),
  check (
    (status = 'RECORDED' and approved_by is null and approved_at is null and authorization_batch_id is null
      and approve_idempotency_key is null and approve_request_hash is null)
    or
    (status = 'APPROVED' and approved_by is not null and approved_at is not null and authorization_batch_id is not null
      and approve_idempotency_key is not null and approve_request_hash is not null)
  ),
  unique (organization_id, supplier_invoice_id, lower(trim(credit_reference))),
  unique (organization_id, idempotency_key),
  unique (authorization_batch_id),
  unique (id, organization_id),
  foreign key (supplier_invoice_id, organization_id)
    references public.supplier_invoices(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (authorization_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create unique index supplier_credit_notes_approve_key
  on public.supplier_credit_notes(organization_id, approve_idempotency_key)
  where approve_idempotency_key is not null;
create index supplier_credit_notes_invoice_idx on public.supplier_credit_notes(supplier_invoice_id);

-- ===========================================================================
-- 3. Immutability and transition guards.
-- ===========================================================================
create or replace function public.p3_guard_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'P3 financial settlement facts are append-only';
end $$;

create trigger unapplied_payments_no_change before update or delete on public.unapplied_payments
for each row execute function public.p3_guard_append_only();
create trigger payment_allocations_no_change before update or delete on public.payment_allocations
for each row execute function public.p3_guard_append_only();
create trigger supplier_advances_no_change before update or delete on public.supplier_advances
for each row execute function public.p3_guard_append_only();
create trigger supplier_advance_applications_no_change before update or delete on public.supplier_advance_applications
for each row execute function public.p3_guard_append_only();

create or replace function public.p3_guard_credit_note_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'supplier credit notes cannot be deleted';
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.supplier_invoice_id is distinct from old.supplier_invoice_id
     or new.obligation_id is distinct from old.obligation_id
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
  if not (old.status = 'RECORDED' and new.status = 'APPROVED'
          and new.approved_by is not null and new.approved_by <> old.recorded_by
          and new.approved_at is not null and new.authorization_batch_id is not null
          and new.approve_idempotency_key is not null and new.approve_request_hash is not null) then
    raise exception 'invalid supplier credit note transition';
  end if;
  return new;
end $$;
create trigger supplier_credit_notes_transition_guard
before update or delete on public.supplier_credit_notes
for each row execute function public.p3_guard_credit_note_transition();

-- ===========================================================================
-- 4. Authoritative outstanding payable calculation.
-- ===========================================================================
create or replace function public.obligation_active_outstanding_minor_units(
  p_organization_id uuid,
  p_obligation_id uuid
) returns bigint
language sql stable set search_path=pg_catalog,public as $$
  select o.amount_minor_units
    - coalesce((
        select sum(pp.amount_minor_units)
        from public.project_payments pp
        join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
        where pp.organization_id = p_organization_id and pp.obligation_id = p_obligation_id
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
      ), 0)
    - coalesce((
        select sum(pa.allocated_minor_units)
        from public.payment_allocations pa
        where pa.organization_id = p_organization_id and pa.obligation_id = p_obligation_id
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = pa.journal_batch_id)
      ), 0)
    - coalesce((
        select sum(sa.applied_amount_minor_units)
        from public.supplier_advance_applications sa
        where sa.organization_id = p_organization_id and sa.obligation_id = p_obligation_id
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = sa.journal_batch_id)
      ), 0)
    - coalesce((
        select sum(cn.amount_minor_units)
        from public.supplier_credit_notes cn
        where cn.organization_id = p_organization_id and cn.obligation_id = p_obligation_id
          and cn.status = 'APPROVED'
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = cn.authorization_batch_id)
      ), 0)
  from public.cost_obligations o
  where o.organization_id = p_organization_id and o.id = p_obligation_id
$$;

-- Existing ordinary payments must serialize on the same obligation row and
-- respect all P3 settlement facts, not only prior cash payments.
create or replace function public.p3_guard_project_payment_settlement() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_outstanding bigint;
begin
  perform 1 from public.cost_obligations
   where id = new.obligation_id and organization_id = new.organization_id
   for update;
  if not found then raise exception 'obligation not found'; end if;
  v_outstanding := public.obligation_active_outstanding_minor_units(new.organization_id, new.obligation_id);
  if v_outstanding is null or new.amount_minor_units > v_outstanding then
    raise exception 'payment exceeds current outstanding payable';
  end if;
  return new;
end $$;
create trigger p3_project_payment_settlement_guard
before insert on public.project_payments
for each row execute function public.p3_guard_project_payment_settlement();

-- ===========================================================================
-- 5. Commands.
-- ===========================================================================
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
  v_id uuid := gen_random_uuid();
  v_batch_id uuid := gen_random_uuid();
  v_hash text;
  v_existing public.unapplied_payments%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_prepaid uuid; v_cash uuid; v_available bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then raise exception 'payment amount must be positive'; end if;
  if p_payment_date is null then raise exception 'payment date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id',p_project_id,'cash_account_id',p_cash_account_id,'amount_minor_units',p_amount_minor_units,
    'currency',p_currency,'payment_date',p_payment_date,'description',p_description,
    'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':p3-unapplied:' || trim(p_idempotency_key),0));
  select * into v_existing from public.unapplied_payments
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_account from public.project_cash_accounts
   where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency <> p_currency then raise exception 'cash account currency mismatch'; end if;
  v_available := public.s5_cash_account_balance_internal(p_organization_id,p_project_id,p_cash_account_id,p_currency);
  if p_amount_minor_units > v_available then raise exception 'unapplied payment exceeds available cash'; end if;

  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  select id into v_cash from public.semantic_accounts where role='BANK_CASH';

  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,p_project_id,'UNAPPLIED_PAYMENT',v_id,p_payment_date,
         'p3-unapplied-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,cash_account_id,transaction_date)
  values
    (v_batch_id,p_organization_id,p_project_id,v_prepaid,p_amount_minor_units,0,p_currency,null,p_payment_date),
    (v_batch_id,p_organization_id,p_project_id,v_cash,0,p_amount_minor_units,p_currency,p_cash_account_id,p_payment_date);

  insert into public.unapplied_payments(id,organization_id,project_id,cash_account_id,amount_minor_units,currency,payment_date,
    description,evidence_reference,journal_batch_id,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_cash_account_id,p_amount_minor_units,p_currency,p_payment_date,
    nullif(trim(p_description),''),nullif(trim(p_evidence_reference),''),v_batch_id,v_actor,trim(p_idempotency_key),v_hash);

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'UNAPPLIED_PAYMENT_RECORDED','unapplied_payment',v_id,
    jsonb_build_object('project_id',p_project_id,'amount_minor_units',p_amount_minor_units,'currency',p_currency,'journal_batch_id',v_batch_id));
  return v_id;
end $$;

create or replace function public.allocate_payment(
  p_organization_id uuid,
  p_unapplied_payment_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_allocation_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid := gen_random_uuid(); v_batch_id uuid := gen_random_uuid(); v_hash text;
  v_existing public.payment_allocations%rowtype; v_payment public.unapplied_payments%rowtype;
  v_obligation public.cost_obligations%rowtype; v_used bigint; v_outstanding bigint;
  v_payable uuid; v_prepaid uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then raise exception 'allocation amount must be positive'; end if;
  if p_allocation_date is null then raise exception 'allocation date required'; end if;

  v_hash := encode(digest(p_unapplied_payment_id::text||'|'||p_obligation_id::text||'|'||p_amount_minor_units::text||'|'||p_allocation_date::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-allocate:'||trim(p_idempotency_key),0));
  select * into v_existing from public.payment_allocations
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_payment from public.unapplied_payments
   where id=p_unapplied_payment_id and organization_id=p_organization_id for update;
  if not found then raise exception 'unapplied payment not found'; end if;
  if exists(select 1 from public.supplier_advances a where a.unapplied_payment_id=v_payment.id) then
    raise exception 'supplier advance payments must be settled through apply_supplier_advance';
  end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_payment.journal_batch_id) then
    raise exception 'unapplied payment posting is reversed';
  end if;

  select * into v_obligation from public.cost_obligations
   where id=p_obligation_id and organization_id=p_organization_id for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'AUTHORIZED' then raise exception 'allocation requires authorized obligation'; end if;
  if v_obligation.project_id <> v_payment.project_id then raise exception 'project mismatch'; end if;
  if v_obligation.currency <> v_payment.currency then raise exception 'currency mismatch'; end if;

  select coalesce(sum(pa.allocated_minor_units),0) into v_used
   from public.payment_allocations pa
   where pa.unapplied_payment_id=v_payment.id
     and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=pa.journal_batch_id);
  if v_used + p_amount_minor_units > v_payment.amount_minor_units then raise exception 'allocation exceeds unapplied payment amount'; end if;
  v_outstanding := public.obligation_active_outstanding_minor_units(p_organization_id,p_obligation_id);
  if v_outstanding is null or p_amount_minor_units > v_outstanding then raise exception 'allocation exceeds current outstanding payable'; end if;

  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_obligation.project_id,'PAYMENT_ALLOCATION',v_id,p_allocation_date,
         'p3-allocation-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_obligation.project_id,v_payable,p_amount_minor_units,0,v_obligation.currency,v_obligation.id,v_obligation.party_id,p_allocation_date),
    (v_batch_id,p_organization_id,v_obligation.project_id,v_prepaid,0,p_amount_minor_units,v_obligation.currency,null,null,p_allocation_date);
  insert into public.payment_allocations(id,organization_id,project_id,unapplied_payment_id,obligation_id,allocated_minor_units,currency,
    allocation_date,journal_batch_id,allocated_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,v_obligation.project_id,v_payment.id,v_obligation.id,p_amount_minor_units,v_obligation.currency,
    p_allocation_date,v_batch_id,v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.record_supplier_advance(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_cash_account_id uuid,
  p_advance_reference text,
  p_advance_date date,
  p_currency text,
  p_amount_minor_units bigint,
  p_description text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_advances%rowtype; v_payment_id uuid; v_child_key text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_advance_reference is null or char_length(trim(p_advance_reference)) not between 1 and 120 then raise exception 'invalid advance reference'; end if;
  if not exists(select 1 from public.parties where id=p_supplier_party_id and organization_id=p_organization_id) then raise exception 'supplier party not found'; end if;

  v_hash:=encode(digest(jsonb_build_object('project_id',p_project_id,'supplier_party_id',p_supplier_party_id,
    'cash_account_id',p_cash_account_id,'advance_reference',trim(p_advance_reference),'advance_date',p_advance_date,
    'currency',p_currency,'amount_minor_units',p_amount_minor_units,'description',p_description,'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-advance:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_advances
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  v_child_key := 'p3advpay:' || substr(v_hash,1,32);
  v_payment_id := public.record_unapplied_payment(p_organization_id,p_project_id,p_cash_account_id,p_amount_minor_units,
    p_currency,p_advance_date,p_description,p_evidence_reference,v_child_key);
  insert into public.supplier_advances(id,organization_id,project_id,supplier_party_id,unapplied_payment_id,advance_reference,advance_date,
    amount_minor_units,currency,description,evidence_reference,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_supplier_party_id,v_payment_id,trim(p_advance_reference),p_advance_date,
    p_amount_minor_units,p_currency,nullif(trim(p_description),''),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.apply_supplier_advance(
  p_organization_id uuid,
  p_advance_id uuid,
  p_supplier_invoice_id uuid,
  p_applied_amount_minor_units bigint,
  p_application_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_advance_applications%rowtype; v_advance public.supplier_advances%rowtype;
  v_invoice public.supplier_invoices%rowtype; v_obligation public.cost_obligations%rowtype;
  v_used bigint; v_outstanding bigint; v_payable uuid; v_prepaid uuid; v_payment_batch uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_applied_amount_minor_units is null or p_applied_amount_minor_units<=0 then raise exception 'application amount must be positive'; end if;
  if p_application_date is null then raise exception 'application date required'; end if;

  v_hash:=encode(digest(p_advance_id::text||'|'||p_supplier_invoice_id::text||'|'||p_applied_amount_minor_units::text||'|'||p_application_date::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-apply:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_advance_applications
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_advance from public.supplier_advances where id=p_advance_id and organization_id=p_organization_id for update;
  if not found then raise exception 'advance not found'; end if;
  select up.journal_batch_id into v_payment_batch from public.unapplied_payments up where up.id=v_advance.unapplied_payment_id;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_payment_batch) then raise exception 'advance payment is reversed'; end if;

  select * into v_invoice from public.supplier_invoices where id=p_supplier_invoice_id and organization_id=p_organization_id;
  if not found or v_invoice.status<>'APPROVED' or v_invoice.cost_obligation_id is null then raise exception 'approved supplier invoice with payable required'; end if;
  if v_invoice.project_id<>v_advance.project_id then raise exception 'project mismatch'; end if;
  if v_invoice.party_id<>v_advance.supplier_party_id then raise exception 'supplier mismatch'; end if;
  if v_invoice.currency<>v_advance.currency then raise exception 'currency mismatch'; end if;

  select * into v_obligation from public.cost_obligations where id=v_invoice.cost_obligation_id and organization_id=p_organization_id for update;
  if not found or v_obligation.status<>'AUTHORIZED' then raise exception 'authorized obligation required'; end if;
  select coalesce(sum(a.applied_amount_minor_units),0) into v_used from public.supplier_advance_applications a
   where a.advance_id=v_advance.id and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=a.journal_batch_id);
  if v_used+p_applied_amount_minor_units>v_advance.amount_minor_units then raise exception 'application exceeds advance balance'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(p_organization_id,v_obligation.id);
  if v_outstanding is null or p_applied_amount_minor_units>v_outstanding then raise exception 'application exceeds current outstanding payable'; end if;

  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_obligation.project_id,'SUPPLIER_ADVANCE_APPLICATION',v_id,p_application_date,
    'p3-advance-app-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_obligation.project_id,v_payable,p_applied_amount_minor_units,0,v_obligation.currency,v_obligation.id,v_obligation.party_id,p_application_date),
    (v_batch_id,p_organization_id,v_obligation.project_id,v_prepaid,0,p_applied_amount_minor_units,v_obligation.currency,null,null,p_application_date);
  insert into public.supplier_advance_applications(id,organization_id,project_id,advance_id,supplier_invoice_id,obligation_id,
    applied_amount_minor_units,currency,application_date,journal_batch_id,applied_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,v_obligation.project_id,v_advance.id,v_invoice.id,v_obligation.id,
    p_applied_amount_minor_units,v_obligation.currency,p_application_date,v_batch_id,v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

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
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_credit_notes%rowtype; v_invoice public.supplier_invoices%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'credit amount must be positive'; end if;
  if p_credit_reference is null or char_length(trim(p_credit_reference)) not between 1 and 120 then raise exception 'invalid credit reference'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'credit reason required'; end if;

  v_hash:=encode(digest(jsonb_build_object('project_id',p_project_id,'supplier_invoice_id',p_supplier_invoice_id,
    'credit_reference',trim(p_credit_reference),'credit_date',p_credit_date,'currency',p_currency,
    'amount_minor_units',p_amount_minor_units,'reason',trim(p_reason),'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-credit:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_credit_notes where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_invoice from public.supplier_invoices where id=p_supplier_invoice_id and organization_id=p_organization_id;
  if not found or v_invoice.project_id<>p_project_id or v_invoice.status<>'APPROVED' or v_invoice.cost_obligation_id is null then
    raise exception 'approved supplier invoice with payable required';
  end if;
  if v_invoice.currency<>p_currency then raise exception 'credit currency must match invoice'; end if;
  insert into public.supplier_credit_notes(id,organization_id,project_id,supplier_invoice_id,obligation_id,credit_reference,
    credit_date,currency,amount_minor_units,reason,evidence_reference,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_supplier_invoice_id,v_invoice.cost_obligation_id,trim(p_credit_reference),
    p_credit_date,p_currency,p_amount_minor_units,trim(p_reason),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.approve_supplier_credit_note(
  p_organization_id uuid,
  p_credit_note_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_hash text; v_credit public.supplier_credit_notes%rowtype;
  v_existing public.supplier_credit_notes%rowtype; v_invoice public.supplier_invoices%rowtype;
  v_obligation public.cost_obligations%rowtype; v_batch_id uuid:=gen_random_uuid();
  v_outstanding bigint; v_payable uuid; v_cost uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=encode(digest(p_credit_note_id::text||'|approve','sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-credit-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_credit_notes
   where organization_id=p_organization_id and approve_idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.id<>p_credit_note_id or v_existing.approve_request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.authorization_batch_id;
  end if;

  select * into v_credit from public.supplier_credit_notes where id=p_credit_note_id and organization_id=p_organization_id for update;
  if not found or v_credit.status<>'RECORDED' then raise exception 'credit note is not recordable for approval'; end if;
  if v_credit.recorded_by=v_actor then raise exception 'maker/checker: credit recorder cannot approve'; end if;
  select * into v_obligation from public.cost_obligations where id=v_credit.obligation_id and organization_id=p_organization_id for update;
  if not found or v_obligation.status<>'AUTHORIZED' then raise exception 'authorized obligation required'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(p_organization_id,v_obligation.id);
  if v_outstanding is null or v_credit.amount_minor_units>v_outstanding then raise exception 'credit exceeds current outstanding payable'; end if;
  select * into v_invoice from public.supplier_invoices where id=v_credit.supplier_invoice_id and organization_id=p_organization_id;
  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  if v_invoice.cost_treatment='EXPENSE' then
    select id into v_cost from public.semantic_accounts where role='PROJECT_EXPENSE';
  else
    select id into v_cost from public.semantic_accounts where role='DEVELOPMENT_WIP';
  end if;

  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_credit.project_id,'SUPPLIER_CREDIT_NOTE',v_credit.id,v_credit.credit_date,
    'p3-credit-batch:'||v_credit.id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_credit.project_id,v_payable,v_credit.amount_minor_units,0,v_credit.currency,v_obligation.id,v_obligation.party_id,v_credit.credit_date),
    (v_batch_id,p_organization_id,v_credit.project_id,v_cost,0,v_credit.amount_minor_units,v_credit.currency,v_obligation.id,v_obligation.party_id,v_credit.credit_date);
  update public.supplier_credit_notes
     set status='APPROVED',approved_by=v_actor,approved_at=now(),authorization_batch_id=v_batch_id,
         approve_idempotency_key=trim(p_idempotency_key),approve_request_hash=v_hash
   where id=v_credit.id;
  return v_batch_id;
end $$;

-- ===========================================================================
-- 6. Read models.
-- ===========================================================================
create view public.unapplied_payments_read with (security_invoker=on) as
select p.id as unapplied_payment_id,p.organization_id,p.project_id,p.cash_account_id,ca.name as cash_account_name,
       p.amount_minor_units::text as amount_minor_units,p.currency,p.payment_date,p.description,p.evidence_reference,
       p.journal_batch_id,p.recorded_by,p.recorded_at,
       coalesce(a.allocated_minor_units,0)::text as allocated_minor_units,
       coalesce(sa.applied_minor_units,0)::text as advance_applied_minor_units,
       greatest(p.amount_minor_units-coalesce(a.allocated_minor_units,0)-coalesce(sa.applied_minor_units,0),0)::text as remaining_minor_units
from public.unapplied_payments p
join public.project_cash_accounts ca on ca.id=p.cash_account_id and ca.organization_id=p.organization_id
left join (
  select unapplied_payment_id,sum(allocated_minor_units) as allocated_minor_units
  from public.payment_allocations pa
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=pa.journal_batch_id)
  group by unapplied_payment_id
) a on a.unapplied_payment_id=p.id
left join (
  select adv.unapplied_payment_id,sum(app.applied_amount_minor_units) as applied_minor_units
  from public.supplier_advances adv join public.supplier_advance_applications app on app.advance_id=adv.id
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=app.journal_batch_id)
  group by adv.unapplied_payment_id
) sa on sa.unapplied_payment_id=p.id;

create view public.payment_allocations_read with (security_invoker=on) as
select pa.id as allocation_id,pa.organization_id,pa.project_id,pa.unapplied_payment_id,pa.obligation_id,
       pa.allocated_minor_units::text as allocated_minor_units,pa.currency,pa.allocation_date,pa.journal_batch_id,pa.allocated_by,pa.allocated_at
from public.payment_allocations pa;

create view public.supplier_advances_read with (security_invoker=on) as
select a.id as advance_id,a.organization_id,a.project_id,a.supplier_party_id,p.legal_name as supplier_name,
       a.advance_reference,a.advance_date,a.currency,a.amount_minor_units::text as amount_minor_units,
       coalesce(x.applied_minor_units,0)::text as applied_minor_units,
       greatest(a.amount_minor_units-coalesce(x.applied_minor_units,0),0)::text as remaining_minor_units,
       case when coalesce(x.applied_minor_units,0)=0 then 'UNAPPLIED'
            when coalesce(x.applied_minor_units,0)<a.amount_minor_units then 'PARTIALLY_APPLIED'
            else 'FULLY_APPLIED' end as status,
       a.unapplied_payment_id,a.recorded_by,a.recorded_at
from public.supplier_advances a
join public.parties p on p.id=a.supplier_party_id and p.organization_id=a.organization_id
left join (
  select advance_id,sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications app
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=app.journal_batch_id)
  group by advance_id
) x on x.advance_id=a.id;

create view public.supplier_advance_applications_read with (security_invoker=on) as
select app.id as application_id,app.organization_id,app.project_id,app.advance_id,app.supplier_invoice_id,
       app.obligation_id,app.applied_amount_minor_units::text as applied_amount_minor_units,app.currency,
       app.application_date,app.journal_batch_id,app.applied_by,app.applied_at
from public.supplier_advance_applications app;

create view public.supplier_credit_notes_read with (security_invoker=on) as
select c.id as credit_note_id,c.organization_id,c.project_id,c.supplier_invoice_id,c.obligation_id,c.credit_reference,
       c.credit_date,c.currency,c.amount_minor_units::text as amount_minor_units,c.reason,c.evidence_reference,c.status,
       c.authorization_batch_id,c.recorded_by,c.recorded_at,c.approved_by,c.approved_at
from public.supplier_credit_notes c;

-- ===========================================================================
-- 7. RLS and grants.
-- ===========================================================================
do $$ declare t text; begin
  foreach t in array array['unapplied_payments','payment_allocations','supplier_advances','supplier_advance_applications','supplier_credit_notes'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

grant select on public.unapplied_payments_read,public.payment_allocations_read,public.supplier_advances_read,
  public.supplier_advance_applications_read,public.supplier_credit_notes_read to authenticated;

revoke all on function public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text) from public,anon;
revoke all on function public.allocate_payment(uuid,uuid,uuid,bigint,date,text) from public,anon;
revoke all on function public.record_supplier_advance(uuid,uuid,uuid,uuid,text,date,text,bigint,text,text,text) from public,anon;
revoke all on function public.apply_supplier_advance(uuid,uuid,uuid,bigint,date,text) from public,anon;
revoke all on function public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text) from public,anon;
revoke all on function public.approve_supplier_credit_note(uuid,uuid,text) from public,anon;

grant execute on function public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text) to authenticated;
grant execute on function public.allocate_payment(uuid,uuid,uuid,bigint,date,text) to authenticated;
grant execute on function public.record_supplier_advance(uuid,uuid,uuid,uuid,text,date,text,bigint,text,text,text) to authenticated;
grant execute on function public.apply_supplier_advance(uuid,uuid,uuid,bigint,date,text) to authenticated;
grant execute on function public.record_supplier_credit_note(uuid,uuid,uuid,text,date,text,bigint,text,text,text) to authenticated;
grant execute on function public.approve_supplier_credit_note(uuid,uuid,text) to authenticated;

revoke all on function public.p3_guard_append_only(),public.p3_guard_credit_note_transition(),
  public.obligation_active_outstanding_minor_units(uuid,uuid),public.p3_guard_project_payment_settlement()
  from public,anon,authenticated;

-- pgcrypto hosted-schema compatibility for unqualified digest() calls.
do $pgcrypto_compat_p3$
declare
  v_pgcrypto_schema text; v_record record; v_definition text; v_rewritten text;
  v_commands text[]:=array['record_unapplied_payment','allocate_payment','record_supplier_advance',
    'apply_supplier_advance','record_supplier_credit_note','approve_supplier_credit_note'];
begin
  select n.nspname into v_pgcrypto_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;
  for v_record in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname=any(v_commands::text[])
  loop
    v_definition:=pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten:=regexp_replace(v_definition,'(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1'||quote_ident(v_pgcrypto_schema)||'.digest(','g');
      if v_rewritten=v_definition then raise exception 'failed to qualify pgcrypto digest in %',v_record.proname; end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat_p3$;
