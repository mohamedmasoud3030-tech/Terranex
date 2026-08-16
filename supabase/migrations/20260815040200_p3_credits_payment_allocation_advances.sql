-- P3 — Credits, payment allocations, and supplier advances: schema.
--
-- Exact bigint minor-unit facts. Posted journals remain the authoritative
-- Project Financial Subledger. Supplier advances are prepaid assets, never
-- fake invoices. All settlement commands are added in the following migration.

-- Extend locked semantic account registry.
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE',
  'AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE','PREPAID_ASSET'
));
insert into public.semantic_accounts(role,label_ar)
values ('PREPAID_ASSET','أصل مدفوع مقدم / سلف موردين')
on conflict (role) do nothing;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

-- Extend journal source registry.
alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT','AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION',
  'LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION',
  'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION','SUPPLIER_ADVANCE_APPLICATION'
));

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
  request_hash text not null check (char_length(request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
);
create index unapplied_payments_project_idx on public.unapplied_payments(project_id,payment_date desc);

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
  request_hash text not null check (char_length(request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  unique (id,organization_id),
  foreign key (unapplied_payment_id,organization_id)
    references public.unapplied_payments(id,organization_id) on delete restrict,
  foreign key (obligation_id,organization_id)
    references public.cost_obligations(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
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
  request_hash text not null check (char_length(request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (unapplied_payment_id),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (supplier_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict,
  foreign key (unapplied_payment_id,organization_id)
    references public.unapplied_payments(id,organization_id) on delete restrict
);
create unique index supplier_advances_project_ref_key
  on public.supplier_advances(organization_id,project_id,lower(trim(advance_reference)));
create index supplier_advances_project_idx on public.supplier_advances(project_id,advance_date desc);

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
  request_hash text not null check (char_length(request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  unique (id,organization_id),
  foreign key (advance_id,organization_id)
    references public.supplier_advances(id,organization_id) on delete restrict,
  foreign key (supplier_invoice_id,organization_id)
    references public.supplier_invoices(id,organization_id) on delete restrict,
  foreign key (obligation_id,organization_id)
    references public.cost_obligations(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
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
  approve_request_hash text check (approve_request_hash is null or char_length(approve_request_hash)=64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  check (approved_by is null or approved_by <> recorded_by),
  check (
    (status='RECORDED' and approved_by is null and approved_at is null and authorization_batch_id is null
      and approve_idempotency_key is null and approve_request_hash is null)
    or
    (status='APPROVED' and approved_by is not null and approved_at is not null and authorization_batch_id is not null
      and approve_idempotency_key is not null and approve_request_hash is not null)
  ),
  unique (organization_id,idempotency_key),
  unique (authorization_batch_id),
  unique (id,organization_id),
  foreign key (supplier_invoice_id,organization_id)
    references public.supplier_invoices(id,organization_id) on delete restrict,
  foreign key (obligation_id,organization_id)
    references public.cost_obligations(id,organization_id) on delete restrict,
  foreign key (authorization_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
);
create unique index supplier_credit_notes_reference_key
  on public.supplier_credit_notes(organization_id,supplier_invoice_id,lower(trim(credit_reference)));
create unique index supplier_credit_notes_approve_key
  on public.supplier_credit_notes(organization_id,approve_idempotency_key)
  where approve_idempotency_key is not null;
create index supplier_credit_notes_invoice_idx on public.supplier_credit_notes(supplier_invoice_id);

-- Append-only settlement facts. Credit notes have exactly one governed transition.
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
  if tg_op='DELETE' then raise exception 'supplier credit notes cannot be deleted'; end if;
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
     or new.recorded_at is distinct from old.recorded_at
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash then
    raise exception 'supplier credit note economics are immutable';
  end if;
  if not (old.status='RECORDED' and new.status='APPROVED'
      and new.approved_by is not null and new.approved_by<>old.recorded_by
      and new.approved_at is not null and new.authorization_batch_id is not null
      and new.approve_idempotency_key is not null and new.approve_request_hash is not null) then
    raise exception 'invalid supplier credit note transition';
  end if;
  return new;
end $$;
create trigger supplier_credit_notes_transition_guard
before update or delete on public.supplier_credit_notes
for each row execute function public.p3_guard_credit_note_transition();
