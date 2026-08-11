-- GF-004 / S2 — Cost & Cash vertical slice.
--
-- Delivers Terranex's first balanced project subledger:
--   project cash accounts with derived balances,
--   contribution-to-cash attribution for S1 contributions,
--   supplier cost obligations (EXPENSE / CAPITALIZABLE_WIP) with an explicit
--     OWNER authorization boundary,
--   payments from project cash against an obligation,
--   deterministic CSV bank-statement import (no economics),
--   exact one-to-one payment <-> statement-line reconciliation,
--   linked journal reversal with dependency-order rules.
--
-- Everything financially posted lives in immutable journal batches/lines under
-- locked semantic account roles. No editable balance columns exist anywhere;
-- all positions are derived read views. Bigint money is exposed to the client
-- as text through *_read views so PostgREST/JavaScript cannot round it.

-- ===========================================================================
-- 1. Project cash accounts (tenant + project scoped, append-only resources)
-- ===========================================================================
create table if not exists public.project_cash_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 120),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists cash_accounts_project_idx on public.project_cash_accounts(project_id);

-- ===========================================================================
-- 2. Locked semantic account roles. No chart-of-accounts editor: these five
--    roles are fixed by the S2 policy and cannot be changed by any writer.
-- ===========================================================================
create table if not exists public.semantic_accounts (
  id uuid primary key default gen_random_uuid(),
  role text not null unique check (role in (
    'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP'
  )),
  label_ar text not null check (char_length(trim(label_ar)) between 2 and 120),
  created_at timestamptz not null default now()
);
insert into public.semantic_accounts(role, label_ar) values
  ('BANK_CASH','نقدية البنك / المشروع'),
  ('CONTRIBUTED_CAPITAL','رأس المال المساهم'),
  ('SUPPLIER_PAYABLE','مستحق للموردين'),
  ('PROJECT_EXPENSE','مصروفات المشروع'),
  ('DEVELOPMENT_WIP','أعمال تحت التطوير')
on conflict (role) do nothing;

create or replace function public.s2_guard_semantic_accounts_locked() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'semantic account roles are locked by S2 policy';
end $$;
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

-- ===========================================================================
-- 3. Cost obligations (draft by any active member, posted by OWNER)
-- ===========================================================================
create table if not exists public.cost_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  party_id uuid not null references public.parties(id) on delete restrict,
  description text not null check (char_length(trim(description)) between 3 and 500),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  transaction_date date not null,
  cost_treatment text not null check (cost_treatment in ('EXPENSE','CAPITALIZABLE_WIP')),
  status text not null default 'DRAFT' check (status in ('DRAFT','AUTHORIZED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  authorized_by uuid references auth.users(id) on delete restrict,
  authorized_at timestamptz,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict
);
create index if not exists cost_obligations_project_idx on public.cost_obligations(project_id);
create index if not exists cost_obligations_status_idx on public.cost_obligations(project_id, status);

-- Drafts may be edited/deleted; an authorized obligation is immutable. The
-- reversal command never updates it: reversal state is derived from journal
-- batch reversal links.
create or replace function public.s2_guard_obligation_draft_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status <> 'DRAFT' then
    raise exception 'an authorized obligation is immutable; correct it by reversal';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists cost_obligations_draft_only on public.cost_obligations;
create trigger cost_obligations_draft_only
before update or delete on public.cost_obligations
for each row execute function public.s2_guard_obligation_draft_only();

-- ===========================================================================
-- 4. Journal batches and lines (the immutable balanced subledger)
-- ===========================================================================
create table if not exists public.journal_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  source_type text not null check (source_type in (
    'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL'
  )),
  source_id uuid not null,
  transaction_date date not null,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  reversal_of_batch_id uuid,
  posted_by uuid references auth.users(id) on delete restrict,
  posted_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (reversal_of_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
-- A batch may be reversed at most once.
create unique index if not exists journal_batches_one_reversal
  on public.journal_batches(reversal_of_batch_id)
  where reversal_of_batch_id is not null;
create index if not exists journal_batches_source_idx on public.journal_batches(source_type, source_id);
create index if not exists journal_batches_project_idx on public.journal_batches(project_id);

create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.journal_batches(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  account_id uuid not null references public.semantic_accounts(id) on delete restrict,
  debit_minor_units bigint not null default 0 check (debit_minor_units >= 0),
  credit_minor_units bigint not null default 0 check (credit_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  cash_account_id uuid,
  obligation_id uuid,
  party_id uuid,
  transaction_date date not null,
  posting_date timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- A line is either a debit or a credit, never both and never neither.
  check ((debit_minor_units > 0 and credit_minor_units = 0)
      or (credit_minor_units > 0 and debit_minor_units = 0)),
  unique (id, organization_id),
  foreign key (batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict
);
create index if not exists journal_lines_batch_idx on public.journal_lines(batch_id);
create index if not exists journal_lines_cash_account_idx on public.journal_lines(cash_account_id)
  where cash_account_id is not null;
create index if not exists journal_lines_obligation_idx on public.journal_lines(obligation_id)
  where obligation_id is not null;

-- ---------------------------------------------------------------------------
-- 4a. Immutability: posted batches and lines are append-only. No UPDATE or
--     DELETE ever; corrections go through the linked reversal command.
-- ---------------------------------------------------------------------------
create or replace function public.s2_guard_journal_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'journal batches and lines are immutable once posted';
end $$;
drop trigger if exists journal_batches_immutable on public.journal_batches;
create trigger journal_batches_immutable
before update or delete on public.journal_batches
for each row execute function public.s2_guard_journal_immutable();
drop trigger if exists journal_lines_immutable on public.journal_lines;
create trigger journal_lines_immutable
before update or delete on public.journal_lines
for each row execute function public.s2_guard_journal_immutable();

-- A source posts at most once while its batch is active; after an explicit
-- linked reversal (a reversal batch referencing it) a new active posting is
-- allowed. Database-enforced for every writer, not just the RPCs.
create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT') then
    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'source already has an active posting';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists journal_batches_one_active_source_guard on public.journal_batches;
create trigger journal_batches_one_active_source_guard
before insert on public.journal_batches
for each row execute function public.s2_guard_one_active_source_posting();

-- ---------------------------------------------------------------------------
-- 4b. The database enforces the balanced-posting invariant, not merely the
--     UI. Every INSERT statement that touches journal_lines is checked at
--     statement end: every batch referenced by the statement must have
--     debits == credits, at least one debit and one credit line, one
--     currency, and lines that agree with the batch header's project.
--     Posting commands insert all lines of a batch in a single statement,
--     so a balanced batch passes; any partial/unbalanced batch is rejected
--     even by privileged writers.
-- ---------------------------------------------------------------------------
create or replace function public.s2_guard_batch_balanced() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_batch uuid;
  v_debit bigint; v_credit bigint; v_lines bigint;
  v_currencies bigint; v_batch_project uuid; v_line_project uuid;
begin
  for v_batch in select distinct batch_id from new_lines loop
    select count(*),
           coalesce(sum(debit_minor_units), 0),
           coalesce(sum(credit_minor_units), 0),
           count(distinct currency)
      into v_lines, v_debit, v_credit, v_currencies
      from public.journal_lines
     where batch_id = v_batch;
    select project_id into v_batch_project
      from public.journal_batches
     where id = v_batch;
    if v_batch_project is null then
      raise exception 'journal lines must reference an existing batch';
    end if;
    select project_id into v_line_project
      from public.journal_lines
     where batch_id = v_batch
     limit 1;
    if v_lines < 2 or v_debit <= 0 or v_credit <= 0 or v_debit <> v_credit then
      raise exception 'journal batch is unbalanced';
    end if;
    if v_currencies <> 1 then
      raise exception 'journal batch mixes currencies';
    end if;
    if v_line_project is null or v_line_project <> v_batch_project then
      raise exception 'journal lines must belong to the batch project';
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists journal_lines_balance_guard on public.journal_lines;
create trigger journal_lines_balance_guard
after insert on public.journal_lines
referencing new table as new_lines
for each statement execute function public.s2_guard_batch_balanced();

-- ---------------------------------------------------------------------------
-- 4c. Line scope guards: dimensions must belong to the same tenant and
--     project as the line itself, even for privileged writers.
-- ---------------------------------------------------------------------------
create or replace function public.s2_validate_journal_line_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_project uuid; v_role text;
begin
  if new.cash_account_id is not null then
    select role into v_role from public.semantic_accounts where id = new.account_id;
    if v_role <> 'BANK_CASH' then
      raise exception 'cash account dimension is only valid on BANK_CASH lines';
    end if;
    select project_id into v_project
      from public.project_cash_accounts
     where id = new.cash_account_id and organization_id = new.organization_id;
    if v_project is null or v_project <> new.project_id then
      raise exception 'cash account must belong to the line organization and project';
    end if;
  end if;
  if new.obligation_id is not null then
    select role into v_role from public.semantic_accounts where id = new.account_id;
    if v_role not in ('SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP') then
      raise exception 'obligation dimension is only valid on obligation account lines';
    end if;
    if not exists (
      select 1 from public.cost_obligations co
      where co.id = new.obligation_id
        and co.organization_id = new.organization_id
        and co.project_id = new.project_id
    ) then
      raise exception 'obligation must belong to the line organization and project';
    end if;
  end if;
  if new.party_id is not null then
    if not exists (
      select 1 from public.parties p
      where p.id = new.party_id and p.organization_id = new.organization_id
    ) then
      raise exception 'party must belong to the line organization';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists journal_line_scope_guard on public.journal_lines;
create trigger journal_line_scope_guard
before insert on public.journal_lines
for each row execute function public.s2_validate_journal_line_scope();

-- ===========================================================================
-- 5. Payments (append-only facts; one journal batch per payment)
-- ===========================================================================
create table if not exists public.project_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  obligation_id uuid not null references public.cost_obligations(id) on delete restrict,
  cash_account_id uuid not null references public.project_cash_accounts(id) on delete restrict,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_date date not null,
  paid_by uuid not null references auth.users(id) on delete restrict,
  posted_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists project_payments_obligation_idx on public.project_payments(obligation_id);
create index if not exists project_payments_cash_idx on public.project_payments(cash_account_id);

create or replace function public.s2_guard_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'posted payment records are append-only';
end $$;
drop trigger if exists project_payments_immutable on public.project_payments;
create trigger project_payments_immutable
before update or delete on public.project_payments
for each row execute function public.s2_guard_append_only();

-- Payment scope guard: obligation and cash account must belong to the same
-- tenant and project as the payment row.
create or replace function public.s2_validate_payment_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1
    from public.cost_obligations co
    join public.project_cash_accounts ca
      on ca.id = new.cash_account_id and ca.organization_id = new.organization_id
    where co.id = new.obligation_id
      and co.organization_id = new.organization_id
      and co.project_id = new.project_id
      and ca.project_id = new.project_id
  ) then
    raise exception 'payment obligation and cash account must belong to one project';
  end if;
  return new;
end $$;
drop trigger if exists project_payments_scope_guard on public.project_payments;
create trigger project_payments_scope_guard
before insert on public.project_payments
for each row execute function public.s2_validate_payment_scope();

-- ===========================================================================
-- 6. Bank statement import (immutable external facts; no economics)
-- ===========================================================================
create table if not exists public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  cash_account_id uuid not null references public.project_cash_accounts(id) on delete restrict,
  line_count integer not null check (line_count >= 1),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  imported_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists bank_statement_imports_account_idx on public.bank_statement_imports(cash_account_id);

create table if not exists public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  cash_account_id uuid not null references public.project_cash_accounts(id) on delete restrict,
  import_id uuid not null references public.bank_statement_imports(id) on delete restrict,
  provider_reference text check (provider_reference is null or char_length(trim(provider_reference)) between 1 and 80),
  transaction_date date not null,
  -- Signed integer minor units: negative means money left the account
  -- (matches a book payment); positive means money entered the account.
  amount_minor_units bigint not null check (amount_minor_units <> 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text not null check (char_length(trim(description)) between 1 and 500),
  fingerprint text not null check (char_length(fingerprint) = 64),
  created_at timestamptz not null default now(),
  unique (organization_id, cash_account_id, fingerprint),
  unique (id, organization_id),
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (import_id, organization_id)
    references public.bank_statement_imports(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists bank_statement_lines_account_idx on public.bank_statement_lines(cash_account_id);

create or replace function public.s2_guard_statement_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'bank statement lines are immutable external facts';
end $$;
drop trigger if exists bank_statement_lines_immutable on public.bank_statement_lines;
create trigger bank_statement_lines_immutable
before update or delete on public.bank_statement_lines
for each row execute function public.s2_guard_statement_append_only();

-- ===========================================================================
-- 7. Reconciliation matches (exact one-to-one; void is the only controlled
--    state transition and is not a destructive edit)
-- ===========================================================================
create table if not exists public.reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  payment_id uuid not null references public.project_payments(id) on delete restrict,
  statement_line_id uuid not null references public.bank_statement_lines(id) on delete restrict,
  cash_account_id uuid not null references public.project_cash_accounts(id) on delete restrict,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  matched_by uuid not null references auth.users(id) on delete restrict,
  matched_at timestamptz not null default now(),
  voided_by uuid references auth.users(id) on delete restrict,
  voided_at timestamptz,
  voided_reason text check (voided_reason is null or char_length(trim(voided_reason)) between 3 and 500),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  -- Durable idempotency for the void command itself (the void has its own
  -- retry key, distinct from the match-creation key).
  void_idempotency_key text check (void_idempotency_key is null
    or char_length(void_idempotency_key) between 8 and 120),
  void_request_hash text check (void_request_hash is null or char_length(void_request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (payment_id, organization_id)
    references public.project_payments(id, organization_id) on delete restrict,
  foreign key (statement_line_id, organization_id)
    references public.bank_statement_lines(id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
-- A statement line cannot be actively reconciled twice; a payment cannot be
-- actively reconciled to multiple lines in this S2 one-to-one implementation.
create unique index if not exists reconciliation_active_line
  on public.reconciliation_matches(statement_line_id) where voided_at is null;
create unique index if not exists reconciliation_active_payment
  on public.reconciliation_matches(payment_id) where voided_at is null;
create unique index if not exists reconciliation_void_key_uidx
  on public.reconciliation_matches(organization_id, void_idempotency_key)
  where void_idempotency_key is not null;

-- Only the controlled void transition is allowed (void columns null -> set),
-- and only once.
create or replace function public.s2_guard_reconciliation_void_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.voided_at is not null then
    raise exception 'reconciliation match is already voided';
  end if;
  if new.payment_id <> old.payment_id
     or new.statement_line_id <> old.statement_line_id
     or new.cash_account_id <> old.cash_account_id
     or new.currency <> old.currency
     or new.project_id <> old.project_id
     or new.organization_id <> old.organization_id
     or new.idempotency_key <> old.idempotency_key
     or new.request_hash <> old.request_hash then
    raise exception 'reconciliation match economics are immutable; only voiding is allowed';
  end if;
  if new.voided_at is null or new.voided_by is null
     or new.voided_reason is null or char_length(trim(new.voided_reason)) < 3
     or new.void_idempotency_key is null
     or new.void_request_hash is null then
    raise exception 'void requires a reason, an actor, and a retry key';
  end if;
  return new;
end $$;
drop trigger if exists reconciliation_void_only on public.reconciliation_matches;
create trigger reconciliation_void_only
before update on public.reconciliation_matches
for each row execute function public.s2_guard_reconciliation_void_only();

create or replace function public.s2_guard_reconciliation_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'reconciliation matches cannot be deleted';
end $$;
drop trigger if exists reconciliation_no_delete on public.reconciliation_matches;
create trigger reconciliation_no_delete
before delete on public.reconciliation_matches
for each row execute function public.s2_guard_reconciliation_append_only();

-- ===========================================================================
-- 8. RLS: default deny, active-member reads, no browser writes
-- ===========================================================================
alter table public.project_cash_accounts enable row level security;
alter table public.semantic_accounts enable row level security;
alter table public.journal_batches enable row level security;
alter table public.journal_lines enable row level security;
alter table public.cost_obligations enable row level security;
alter table public.project_payments enable row level security;
alter table public.bank_statement_imports enable row level security;
alter table public.bank_statement_lines enable row level security;
alter table public.reconciliation_matches enable row level security;
alter table public.project_cash_accounts force row level security;
alter table public.semantic_accounts force row level security;
alter table public.journal_batches force row level security;
alter table public.journal_lines force row level security;
alter table public.cost_obligations force row level security;
alter table public.project_payments force row level security;
alter table public.bank_statement_imports force row level security;
alter table public.bank_statement_lines force row level security;
alter table public.reconciliation_matches force row level security;

create policy cash_accounts_read on public.project_cash_accounts for select to authenticated
  using (public.is_active_member(organization_id));
create policy semantic_accounts_read on public.semantic_accounts for select to authenticated
  using (true);
create policy journal_batches_read on public.journal_batches for select to authenticated
  using (public.is_active_member(organization_id));
create policy journal_lines_read on public.journal_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_obligations_read on public.cost_obligations for select to authenticated
  using (public.is_active_member(organization_id));
create policy project_payments_read on public.project_payments for select to authenticated
  using (public.is_active_member(organization_id));
create policy bank_statement_imports_read on public.bank_statement_imports for select to authenticated
  using (public.is_active_member(organization_id));
create policy bank_statement_lines_read on public.bank_statement_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy reconciliation_matches_read on public.reconciliation_matches for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.project_cash_accounts, public.semantic_accounts,
  public.journal_batches, public.journal_lines, public.cost_obligations,
  public.project_payments, public.bank_statement_imports,
  public.bank_statement_lines, public.reconciliation_matches
  from anon, authenticated;
grant select on public.project_cash_accounts, public.semantic_accounts,
  public.journal_batches, public.journal_lines, public.cost_obligations,
  public.project_payments, public.bank_statement_imports,
  public.bank_statement_lines, public.reconciliation_matches
  to authenticated;

-- ===========================================================================
-- 9. Authorization helpers (server-authoritative, locked search_path)
-- ===========================================================================
create or replace function public.s2_is_owner(p_organization_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.role = 'OWNER'
      and m.status = 'ACTIVE'
  )
$$;
revoke all on function public.s2_is_owner(uuid) from public, anon;
grant execute on function public.s2_is_owner(uuid) to authenticated;

create or replace function public.s2_require_owner(p_organization_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if not public.s2_is_owner(p_organization_id) then
    raise exception 'forbidden: organization owner required';
  end if;
end $$;
revoke all on function public.s2_require_owner(uuid) from public, anon;
grant execute on function public.s2_require_owner(uuid) to authenticated;

-- ===========================================================================
-- 10. Idempotent command: create a project cash account
-- ===========================================================================
create or replace function public.create_project_cash_account(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_currency text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 120 then
    raise exception 'invalid account name';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid currency';
  end if;
  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then
    raise exception 'account currency must match project currency';
  end if;
  insert into public.project_cash_accounts(organization_id, project_id, name, currency)
  values (p_organization_id, p_project_id, trim(p_name), p_currency)
  returning id into v_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CASH_ACCOUNT_CREATED', 'project_cash_account', v_id,
          jsonb_build_object('project_id', p_project_id, 'name', trim(p_name), 'currency', p_currency));
  return v_id;
end $$;

-- ===========================================================================
-- 11. Contribution -> project cash attribution. Posts:
--       Debit  Bank / Project Cash
--       Credit Contributed Capital
--     Each contribution posts at most once unless an explicit linked
--     reversal exists (enforced by journal_batches_one_active_source).
-- ===========================================================================
create or replace function public.attach_contribution_cash(
  p_organization_id uuid,
  p_project_id uuid,
  p_contribution_id uuid,
  p_cash_account_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_contribution record;
  v_batch_id uuid; v_hash text; v_existing record;
  v_bank_cash uuid; v_capital uuid; v_party uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select id, project_id, participant_id, contribution_minor_units, currency, occurred_on
    into v_contribution
  from public.contributions
  where id = p_contribution_id and organization_id = p_organization_id;
  if not found then raise exception 'contribution not found'; end if;
  if v_contribution.project_id <> p_project_id then
    raise exception 'contribution does not belong to project';
  end if;

  if not exists (
    select 1 from public.project_cash_accounts ca
    where ca.id = p_cash_account_id
      and ca.organization_id = p_organization_id
      and ca.project_id = p_project_id
  ) then raise exception 'cash account not found for project'; end if;

  select encode(digest(
    p_contribution_id::text || '|' || p_cash_account_id::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':contribution-cash:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.journal_batches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.source_type <> 'CONTRIBUTION_CASH_ATTRIBUTION'
       or v_existing.source_id <> p_contribution_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  -- At most one active posting per contribution; replay above covers the same
  -- key, so reaching here with an existing active posting is a real conflict.
  if exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'CONTRIBUTION_CASH_ATTRIBUTION'
      and jb.source_id = p_contribution_id
      and jb.organization_id = p_organization_id
      and not exists (
        select 1 from public.journal_batches rb
        where rb.reversal_of_batch_id = jb.id
      )
  ) then raise exception 'contribution is already posted to project cash'; end if;

  select id into v_bank_cash from public.semantic_accounts where role = 'BANK_CASH';
  select id into v_capital from public.semantic_accounts where role = 'CONTRIBUTED_CAPITAL';
  select party_id into v_party from public.project_participants
  where id = v_contribution.participant_id and organization_id = p_organization_id;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'CONTRIBUTION_CASH_ATTRIBUTION', p_contribution_id,
    v_contribution.occurred_on, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_bank_cash,
     v_contribution.contribution_minor_units, 0, v_contribution.currency,
     p_cash_account_id, null, v_contribution.occurred_on),
    (v_batch_id, p_organization_id, p_project_id, v_capital,
     0, v_contribution.contribution_minor_units, v_contribution.currency,
     null, v_party, v_contribution.occurred_on);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CONTRIBUTION_CASH_POSTED', 'journal_batch', v_batch_id,
          jsonb_build_object('project_id', p_project_id,
                             'contribution_id', p_contribution_id,
                             'cash_account_id', p_cash_account_id,
                             'contribution_minor_units', v_contribution.contribution_minor_units,
                             'currency', v_contribution.currency));
  return v_batch_id;
end $$;

-- ===========================================================================
-- 12. Cost obligation lifecycle commands
-- ===========================================================================
create or replace function public.create_cost_obligation(
  p_organization_id uuid,
  p_project_id uuid,
  p_party_id uuid,
  p_description text,
  p_amount_minor_units bigint,
  p_currency text,
  p_transaction_date date,
  p_cost_treatment text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_hash text; v_existing record; v_project_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'obligation amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_cost_treatment not in ('EXPENSE','CAPITALIZABLE_WIP') then
    raise exception 'cost treatment must be EXPENSE or CAPITALIZABLE_WIP';
  end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 500 then
    raise exception 'description must be 3-500 characters';
  end if;
  if p_transaction_date is null then raise exception 'transaction date required'; end if;
  if not exists (
    select 1 from public.parties p
    where p.id = p_party_id and p.organization_id = p_organization_id
  ) then raise exception 'supplier party not found'; end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  select encode(digest(
    p_project_id::text || '|' || p_party_id::text || '|' || trim(p_description) || '|'
    || p_amount_minor_units::text || '|' || p_currency || '|' || p_transaction_date::text || '|'
    || p_cost_treatment, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':cost-obligation:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.cost_obligations
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.cost_obligations(
    organization_id, project_id, party_id, description, amount_minor_units,
    currency, transaction_date, cost_treatment, prepared_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_party_id, trim(p_description),
    p_amount_minor_units, p_currency, p_transaction_date, p_cost_treatment,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DRAFTED', 'cost_obligation', v_id,
          jsonb_build_object('project_id', p_project_id, 'party_id', p_party_id,
                             'amount_minor_units', p_amount_minor_units,
                             'currency', p_currency, 'cost_treatment', p_cost_treatment,
                             'transaction_date', p_transaction_date));
  return v_id;
end $$;

create or replace function public.update_cost_obligation_draft(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_party_id uuid,
  p_description text,
  p_amount_minor_units bigint,
  p_currency text,
  p_transaction_date date,
  p_cost_treatment text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid; v_project_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'obligation amount must be positive';
  end if;
  if p_cost_treatment not in ('EXPENSE','CAPITALIZABLE_WIP') then
    raise exception 'cost treatment must be EXPENSE or CAPITALIZABLE_WIP';
  end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 500 then
    raise exception 'description must be 3-500 characters';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;

  select project_id into v_project
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id;
  if v_project is null then raise exception 'obligation not found'; end if;
  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = v_project and organization_id = p_organization_id;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;
  if not exists (
    select 1 from public.parties p
    where p.id = p_party_id and p.organization_id = p_organization_id
  ) then raise exception 'supplier party not found'; end if;

  update public.cost_obligations
     set party_id = p_party_id,
         description = trim(p_description),
         amount_minor_units = p_amount_minor_units,
         currency = p_currency,
         transaction_date = p_transaction_date,
         cost_treatment = p_cost_treatment
   where id = p_obligation_id and organization_id = p_organization_id
     and status = 'DRAFT';
  if not found then raise exception 'only a draft obligation can be updated'; end if;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DRAFT_UPDATED', 'cost_obligation', p_obligation_id,
          jsonb_build_object('project_id', v_project, 'party_id', p_party_id,
                             'amount_minor_units', p_amount_minor_units,
                             'currency', p_currency, 'cost_treatment', p_cost_treatment,
                             'transaction_date', p_transaction_date));
  return p_obligation_id;
end $$;

create or replace function public.delete_cost_obligation_draft(
  p_organization_id uuid,
  p_obligation_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  select project_id into v_project
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id;
  if v_project is null then raise exception 'obligation not found'; end if;
  delete from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
    and status = 'DRAFT';
  if not found then raise exception 'only a draft obligation can be deleted'; end if;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DRAFT_DELETED', 'cost_obligation', p_obligation_id,
          jsonb_build_object('project_id', v_project));
  return p_obligation_id;
end $$;

-- ===========================================================================
-- 13. Authorization / posting of an obligation. OWNER only. Atomic:
--     EXPENSE:           Debit  Project Expense / Credit Supplier Payable
--     CAPITALIZABLE_WIP: Debit  Development WIP / Credit Supplier Payable
-- ===========================================================================
create or replace function public.authorize_cost_obligation(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_batch_id uuid; v_hash text; v_existing record;
  v_obligation record; v_debit_account uuid; v_payable_account uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select encode(digest(p_obligation_id::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':obligation-authorize:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.journal_batches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.source_type <> 'COST_OBLIGATION'
       or v_existing.source_id <> p_obligation_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_obligation
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'DRAFT' then
    raise exception 'only a draft obligation can be authorized';
  end if;

  select id into v_payable_account from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  if v_obligation.cost_treatment = 'EXPENSE' then
    select id into v_debit_account from public.semantic_accounts where role = 'PROJECT_EXPENSE';
  else
    select id into v_debit_account from public.semantic_accounts where role = 'DEVELOPMENT_WIP';
  end if;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_obligation.project_id, 'COST_OBLIGATION', p_obligation_id,
    v_obligation.transaction_date, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_obligation.project_id, v_debit_account,
     v_obligation.amount_minor_units, 0, v_obligation.currency,
     p_obligation_id, v_obligation.party_id, v_obligation.transaction_date),
    (v_batch_id, p_organization_id, v_obligation.project_id, v_payable_account,
     0, v_obligation.amount_minor_units, v_obligation.currency,
     p_obligation_id, v_obligation.party_id, v_obligation.transaction_date);

  update public.cost_obligations
     set status = 'AUTHORIZED', authorized_by = v_actor, authorized_at = now()
   where id = p_obligation_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_AUTHORIZED', 'cost_obligation', p_obligation_id,
          jsonb_build_object('project_id', v_obligation.project_id,
                             'journal_batch_id', v_batch_id,
                             'amount_minor_units', v_obligation.amount_minor_units,
                             'currency', v_obligation.currency,
                             'cost_treatment', v_obligation.cost_treatment));
  return v_batch_id;
end $$;

-- ===========================================================================
-- 14. Payment from project cash against an authorized obligation. OWNER
--     only. Row locking on the obligation serializes concurrent payments;
--     the idempotency key makes retries single-effect.
--       Debit  Supplier Payable / Credit Bank / Project Cash
-- ===========================================================================
create or replace function public.pay_cost_obligation(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_payment_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payment_id uuid; v_batch_id uuid; v_hash text; v_existing record;
  v_obligation record; v_paid bigint; v_bank_cash uuid; v_payable uuid;
  v_cash_project uuid; v_cash_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  if p_payment_date is null then raise exception 'payment date required'; end if;

  select project_id, currency into v_cash_project, v_cash_currency
  from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id;
  if v_cash_project is null then raise exception 'cash account not found'; end if;

  select encode(digest(
    p_obligation_id::text || '|' || p_cash_account_id::text || '|'
    || p_amount_minor_units::text || '|' || p_payment_date::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':payment:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.project_payments
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.obligation_id <> p_obligation_id
       or v_existing.cash_account_id <> p_cash_account_id
       or v_existing.amount_minor_units <> p_amount_minor_units
       or v_existing.payment_date <> p_payment_date then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  -- Serialization boundary: lock the obligation row so concurrent payment
  -- requests compute the paid total against the same committed state.
  select * into v_obligation
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'AUTHORIZED' then
    raise exception 'payment requires an authorized obligation';
  end if;
  if exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'COST_OBLIGATION'
      and jb.source_id = p_obligation_id
      and jb.organization_id = p_organization_id
      and jb.reversal_of_batch_id is not null
  ) then raise exception 'obligation authorization is reversed; no further payments'; end if;
  if v_obligation.project_id <> v_cash_project then
    raise exception 'cash account must belong to the obligation project';
  end if;
  if v_obligation.currency <> v_cash_currency then
    raise exception 'payment currency must match the cash account';
  end if;

  -- Paid total comes only from active (non-reversed) payment batches.
  select coalesce(sum(pp.amount_minor_units), 0) into v_paid
  from public.project_payments pp
  join public.journal_batches jb
    on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
  where pp.obligation_id = p_obligation_id
    and pp.organization_id = p_organization_id
    and not exists (
      select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id = jb.id
    );
  if v_paid + p_amount_minor_units > v_obligation.amount_minor_units then
    raise exception 'payment exceeds remaining payable';
  end if;

  insert into public.project_payments(
    organization_id, project_id, obligation_id, cash_account_id,
    amount_minor_units, currency, payment_date, paid_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_obligation.project_id, p_obligation_id, p_cash_account_id,
    p_amount_minor_units, v_obligation.currency, p_payment_date, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_payment_id;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_bank_cash from public.semantic_accounts where role = 'BANK_CASH';

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_obligation.project_id, 'PAYMENT', v_payment_id,
    p_payment_date, 'payment-batch-' || v_payment_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_obligation.project_id, v_payable,
     p_amount_minor_units, 0, v_obligation.currency,
     null, p_obligation_id, v_obligation.party_id, p_payment_date),
    (v_batch_id, p_organization_id, v_obligation.project_id, v_bank_cash,
     0, p_amount_minor_units, v_obligation.currency,
     p_cash_account_id, null, null, p_payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_POSTED', 'project_payment', v_payment_id,
          jsonb_build_object('project_id', v_obligation.project_id,
                             'obligation_id', p_obligation_id,
                             'cash_account_id', p_cash_account_id,
                             'journal_batch_id', v_batch_id,
                             'amount_minor_units', p_amount_minor_units,
                             'currency', v_obligation.currency,
                             'payment_date', p_payment_date));
  return v_payment_id;
end $$;

-- ===========================================================================
-- 15. Deterministic CSV bank-statement import. Member-level capture fact:
--     importing creates statement lines only — never project economics.
-- ===========================================================================
create or replace function public.import_bank_statement_lines(
  p_organization_id uuid,
  p_cash_account_id uuid,
  p_dates date[],
  p_amounts text[],
  p_currencies text[],
  p_descriptions text[],
  p_references text[],
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_import_id uuid; v_hash text; v_existing record;
  v_project uuid; v_account_currency text;
  v_n int; v_i int; v_amount bigint; v_fp text;
  v_ref text; v_desc text; v_amount_norm text;
  v_pairs text[];
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_dates is null or array_length(p_dates, 1) is null or array_length(p_dates, 1) < 1 then
    raise exception 'at least one statement line is required';
  end if;
  if array_length(p_dates, 1) <> array_length(p_amounts, 1)
     or array_length(p_dates, 1) <> array_length(p_currencies, 1)
     or array_length(p_dates, 1) <> array_length(p_descriptions, 1) then
    raise exception 'statement columns length mismatch';
  end if;
  -- Null references array is accepted (optional column); a non-null array must
  -- match the row count.
  if p_references is not null and array_length(p_dates, 1) <> array_length(p_references, 1) then
    raise exception 'statement columns length mismatch';
  end if;

  select project_id, currency into v_project, v_account_currency
  from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id;
  if v_project is null then raise exception 'cash account not found'; end if;

  v_n := array_length(p_dates, 1);

  -- Validate every row first so a bad row can never leave a partial import.
  for v_i in 1..v_n loop
    if p_dates[v_i] is null then raise exception 'statement date required at row %', v_i; end if;
    v_amount_norm := translate(trim(coalesce(p_amounts[v_i], '')), '٠١٢٣٤٥٦٧٨٩', '0123456789');
    if v_amount_norm !~ '^-?\d{1,19}$' then
      raise exception 'invalid statement amount at row %', v_i;
    end if;
    begin
      v_amount := v_amount_norm::bigint;
    exception when others then
      raise exception 'statement amount out of range at row %', v_i;
    end;
    if v_amount = 0 then raise exception 'statement amount must be non-zero at row %', v_i; end if;
    if p_currencies[v_i] is null or upper(trim(p_currencies[v_i])) <> v_account_currency then
      raise exception 'statement currency must match account currency at row %', v_i;
    end if;
    v_desc := trim(p_descriptions[v_i]);
    if v_desc is null or char_length(v_desc) not between 1 and 500 then
      raise exception 'statement description must be 1-500 characters at row %', v_i;
    end if;
    v_ref := nullif(trim(coalesce(p_references[v_i], '')), '');
    if v_ref is not null and char_length(v_ref) > 80 then
      raise exception 'provider reference too long at row %', v_i;
    end if;
    v_pairs[v_i] := p_dates[v_i]::text || ':' || v_amount_norm || ':' || v_account_currency
                    || ':' || lower(v_desc) || ':' || coalesce(v_ref, '');
  end loop;

  -- Canonical payload hash over the normalized rows (deterministic order).
  select encode(digest(
    p_cash_account_id::text || '|' || array_to_string(v_pairs, ','), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':bank-import:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.bank_statement_imports
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.cash_account_id <> p_cash_account_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.bank_statement_imports(
    organization_id, project_id, cash_account_id, line_count,
    idempotency_key, request_hash, imported_by
  ) values (
    p_organization_id, v_project, p_cash_account_id, v_n,
    trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_import_id;

  for v_i in 1..v_n loop
    v_amount_norm := translate(trim(p_amounts[v_i]), '٠١٢٣٤٥٦٧٨٩', '0123456789');
    v_amount := v_amount_norm::bigint;
    v_desc := trim(p_descriptions[v_i]);
    v_ref := nullif(trim(coalesce(p_references[v_i], '')), '');

    -- Deterministic fingerprint: the same external fact always hashes the same.
    select encode(digest(
      p_organization_id::text || '|' || p_cash_account_id::text || '|'
      || p_dates[v_i]::text || '|' || v_amount_norm || '|' || v_account_currency || '|'
      || lower(v_desc) || '|' || coalesce(v_ref, ''), 'sha256'), 'hex') into v_fp;

    begin
      insert into public.bank_statement_lines(
        organization_id, project_id, cash_account_id, import_id, provider_reference,
        transaction_date, amount_minor_units, currency, description, fingerprint
      ) values (
        p_organization_id, v_project, p_cash_account_id, v_import_id, v_ref,
        p_dates[v_i], v_amount, v_account_currency, v_desc, v_fp
      );
    exception when unique_violation then
      raise exception 'bank statement line already imported (duplicate fingerprint) at row %', v_i;
    end;
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BANK_STATEMENT_IMPORTED', 'bank_statement_import', v_import_id,
          jsonb_build_object('project_id', v_project, 'cash_account_id', p_cash_account_id,
                             'line_count', v_n));
  return v_import_id;
end $$;

-- ===========================================================================
-- 16. Exact one-to-one reconciliation. OWNER only. No journal effect.
--     Requires: same project cash account, same currency, and
--     statement amount = -payment amount (sign semantics).
-- ===========================================================================
create or replace function public.reconcile_payment(
  p_organization_id uuid,
  p_payment_id uuid,
  p_statement_line_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_match_id uuid; v_hash text; v_existing record;
  v_payment record; v_line record; v_project uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select encode(digest(
    p_payment_id::text || '|' || p_statement_line_id::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':reconcile:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.reconciliation_matches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.payment_id <> p_payment_id
       or v_existing.statement_line_id <> p_statement_line_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  -- Row locks serialize concurrent reconciliation attempts against the same
  -- payment or the same statement line.
  select * into v_payment
  from public.project_payments
  where id = p_payment_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'payment not found'; end if;
  if exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'PAYMENT' and jb.source_id = p_payment_id
      and exists (
        select 1 from public.journal_batches rb
        where rb.reversal_of_batch_id = jb.id
      )
  ) then raise exception 'reversed payments cannot be reconciled'; end if;

  select * into v_line
  from public.bank_statement_lines
  where id = p_statement_line_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'bank statement line not found'; end if;

  if v_payment.cash_account_id <> v_line.cash_account_id then
    raise exception 'payment and statement line must use the same cash account';
  end if;
  if v_payment.currency <> v_line.currency then
    raise exception 'payment and statement line must use the same currency';
  end if;
  if v_line.amount_minor_units <> -v_payment.amount_minor_units then
    raise exception 'statement amount does not match the payment amount';
  end if;

  v_project := v_payment.project_id;
  if v_project <> v_line.project_id then
    raise exception 'payment and statement line must belong to the same project';
  end if;

  if exists (
    select 1 from public.reconciliation_matches m
    where m.statement_line_id = p_statement_line_id and m.voided_at is null
  ) then raise exception 'bank statement line is already reconciled'; end if;
  if exists (
    select 1 from public.reconciliation_matches m
    where m.payment_id = p_payment_id and m.voided_at is null
  ) then raise exception 'payment is already reconciled'; end if;

  insert into public.reconciliation_matches(
    organization_id, project_id, payment_id, statement_line_id, cash_account_id,
    currency, matched_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_project, p_payment_id, p_statement_line_id,
    v_payment.cash_account_id, v_payment.currency, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_match_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'RECONCILIATION_MATCHED', 'reconciliation_match', v_match_id,
          jsonb_build_object('project_id', v_project,
                             'payment_id', p_payment_id,
                             'statement_line_id', p_statement_line_id,
                             'cash_account_id', v_payment.cash_account_id));
  return v_match_id;
end $$;

-- ===========================================================================
-- 17. Void a reconciliation (controlled correction; not a financial posting).
--     OWNER only. Required before the linked payment can be reversed.
-- ===========================================================================
create or replace function public.void_reconciliation(
  p_organization_id uuid,
  p_match_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_existing record; v_reason text; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  v_reason := trim(coalesce(p_reason, ''));
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'void reason must be 3-500 characters';
  end if;

  select encode(digest(p_match_id::text || '|' || v_reason, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':void-reconcile:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.reconciliation_matches
  where organization_id = p_organization_id
    and void_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_match_id or v_existing.void_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  update public.reconciliation_matches
     set voided_at = now(), voided_by = v_actor, voided_reason = v_reason,
         void_idempotency_key = trim(p_idempotency_key), void_request_hash = v_hash
   where id = p_match_id and organization_id = p_organization_id
     and voided_at is null;
  if not found then
    if exists (select 1 from public.reconciliation_matches
               where id = p_match_id and organization_id = p_organization_id
                 and voided_at is not null) then
      raise exception 'reconciliation match is already voided';
    end if;
    raise exception 'reconciliation match not found';
  end if;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'RECONCILIATION_VOIDED', 'reconciliation_match', p_match_id,
          jsonb_build_object('reason', v_reason));
  return p_match_id;
end $$;

-- ===========================================================================
-- 18. Linked reversal of a posted journal batch. OWNER only.
--     Creates the exact inverse batch, preserves the original, and rejects
--     invalid reversal order when downstream dependencies still exist:
--       COST_OBLIGATION: rejected while any active payment exists;
--       PAYMENT: rejected while an active reconciliation exists;
--       REVERSAL: a reversal cannot itself be reversed.
-- ===========================================================================
create or replace function public.reverse_journal_batch(
  p_organization_id uuid,
  p_batch_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_batch record; v_reversal_id uuid; v_hash text; v_existing record;
  v_reason text; v_reversal_date date := current_date;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  v_reason := trim(coalesce(p_reason, ''));
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'reversal reason must be 3-500 characters';
  end if;

  select encode(digest(
    p_batch_id::text || '|' || v_reason, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':reversal:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.journal_batches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.source_type <> 'REVERSAL'
       or v_existing.source_id <> p_batch_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_batch
  from public.journal_batches
  where id = p_batch_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'journal batch not found'; end if;
  if v_batch.source_type = 'REVERSAL' then
    raise exception 'a reversal batch cannot be reversed';
  end if;
  if exists (
    select 1 from public.journal_batches jb
    where jb.reversal_of_batch_id = p_batch_id
  ) then raise exception 'journal batch is already reversed'; end if;

  -- Downstream dependency rules (reversal order).
  if v_batch.source_type = 'COST_OBLIGATION' then
    if exists (
      select 1 from public.project_payments pp
      join public.journal_batches jb
        on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
      where pp.obligation_id = v_batch.source_id
        and pp.organization_id = p_organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then raise exception 'obligation has active payments; reverse payments first'; end if;
  end if;
  if v_batch.source_type = 'PAYMENT' then
    if exists (
      select 1 from public.reconciliation_matches m
      where m.payment_id = v_batch.source_id
        and m.organization_id = p_organization_id
        and m.voided_at is null
    ) then raise exception 'payment has an active reconciliation; void it first'; end if;
  end if;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, reversal_of_batch_id, posted_by
  ) values (
    p_organization_id, v_batch.project_id, 'REVERSAL', p_batch_id,
    v_reversal_date, trim(p_idempotency_key), v_hash, p_batch_id, v_actor
  ) returning id into v_reversal_id;

  -- Exact inverse of every original line, with the same dimensions.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, obligation_id, party_id, transaction_date
  )
  select v_reversal_id, organization_id, project_id, account_id,
         credit_minor_units, debit_minor_units, currency,
         cash_account_id, obligation_id, party_id, v_reversal_date
  from public.journal_lines
  where batch_id = p_batch_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'JOURNAL_BATCH_REVERSED', 'journal_batch', v_batch.id,
          jsonb_build_object('project_id', v_batch.project_id,
                             'reversal_batch_id', v_reversal_id,
                             'source_type', v_batch.source_type,
                             'reason', v_reason));
  return v_reversal_id;
end $$;

-- ===========================================================================
-- 19. Derived read models. Money is bigint in storage and text on the wire.
-- ===========================================================================
create or replace view public.project_cash_position_read with (security_invoker=on) as
select
  ca.id as cash_account_id,
  ca.organization_id,
  ca.project_id,
  ca.name,
  ca.currency,
  coalesce(pos.balance_minor_units, 0)::text as balance_minor_units,
  pos.last_posting_date
from public.project_cash_accounts ca
left join (
  select jl.cash_account_id,
         sum(jl.debit_minor_units) - sum(jl.credit_minor_units) as balance_minor_units,
         max(jl.posting_date) as last_posting_date
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
  group by jl.cash_account_id
) pos on pos.cash_account_id = ca.id;

create or replace view public.cost_obligation_position_read with (security_invoker=on) as
select
  o.id as obligation_id,
  o.organization_id,
  o.project_id,
  o.party_id,
  o.description,
  o.amount_minor_units::text as amount_minor_units,
  o.currency,
  o.transaction_date,
  o.cost_treatment,
  o.status,
  o.prepared_by,
  o.authorized_by,
  o.authorized_at,
  o.created_at,
  coalesce(paid.paid_minor_units, 0)::text as paid_minor_units,
  (o.amount_minor_units - coalesce(paid.paid_minor_units, 0))::text as outstanding_minor_units,
  (auth_batch.id is not null) as is_posted,
  (auth_batch.id is not null and rev.id is not null) as is_reversed,
  auth_batch.id as authorization_batch_id,
  rev.id as reversal_batch_id
from public.cost_obligations o
left join (
  select pp.obligation_id, sum(jl.debit_minor_units) as paid_minor_units
  from public.journal_batches jb
  join public.project_payments pp on pp.id = jb.source_id
  join public.journal_lines jl on jl.batch_id = jb.id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'SUPPLIER_PAYABLE'
  where jb.source_type = 'PAYMENT'
    and jl.debit_minor_units > 0
    and not exists (
      select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id = jb.id
    )
  group by pp.obligation_id
) paid on paid.obligation_id = o.id
left join public.journal_batches auth_batch
  on auth_batch.source_type = 'COST_OBLIGATION'
 and auth_batch.source_id = o.id
 and auth_batch.reversal_of_batch_id is null
left join public.journal_batches rev
  on rev.reversal_of_batch_id = auth_batch.id;

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
  m.id as match_id
from public.project_payments p
join public.journal_batches b
  on b.source_type = 'PAYMENT' and b.source_id = p.id
left join public.journal_batches rev on rev.reversal_of_batch_id = b.id
left join public.reconciliation_matches m
  on m.payment_id = p.id and m.voided_at is null;

create or replace view public.bank_statement_line_status_read with (security_invoker=on) as
select
  l.id as line_id,
  l.organization_id,
  l.project_id,
  l.cash_account_id,
  l.import_id,
  l.provider_reference,
  l.transaction_date,
  l.amount_minor_units::text as amount_minor_units,
  l.currency,
  l.description,
  l.fingerprint,
  l.created_at,
  (m.id is not null) as is_reconciled,
  m.id as match_id,
  m.payment_id as matched_payment_id,
  m.matched_at
from public.bank_statement_lines l
left join public.reconciliation_matches m
  on m.statement_line_id = l.id and m.voided_at is null;

create or replace view public.journal_ledger_read with (security_invoker=on) as
select
  jb.id as batch_id,
  jb.organization_id,
  jb.project_id,
  jb.source_type,
  jb.source_id,
  jb.transaction_date as batch_transaction_date,
  jb.posted_at,
  jb.posted_by,
  jb.reversal_of_batch_id,
  jl.id as line_id,
  jl.account_id,
  sa.role as account_role,
  sa.label_ar as account_label,
  jl.debit_minor_units::text as debit_minor_units,
  jl.credit_minor_units::text as credit_minor_units,
  jl.currency,
  jl.cash_account_id,
  jl.obligation_id,
  jl.party_id,
  jl.transaction_date as line_transaction_date
from public.journal_batches jb
join public.journal_lines jl on jl.batch_id = jb.id
join public.semantic_accounts sa on sa.id = jl.account_id;

grant select on public.project_cash_position_read,
  public.cost_obligation_position_read,
  public.payment_status_read,
  public.bank_statement_line_status_read,
  public.journal_ledger_read to authenticated;

-- ===========================================================================
-- 20. Command grants. Browser clients hold no table DML; they may only call
--     these server-authoritative RPCs.
-- ===========================================================================
revoke all on function public.create_project_cash_account(uuid,uuid,text,text) from public, anon;
revoke all on function public.attach_contribution_cash(uuid,uuid,uuid,uuid,text) from public, anon;
revoke all on function public.create_cost_obligation(uuid,uuid,uuid,text,bigint,text,date,text,text) from public, anon;
revoke all on function public.update_cost_obligation_draft(uuid,uuid,uuid,text,bigint,text,date,text) from public, anon;
revoke all on function public.delete_cost_obligation_draft(uuid,uuid) from public, anon;
revoke all on function public.authorize_cost_obligation(uuid,uuid,text) from public, anon;
revoke all on function public.pay_cost_obligation(uuid,uuid,uuid,bigint,date,text) from public, anon;
revoke all on function public.import_bank_statement_lines(uuid,uuid,date[],text[],text[],text[],text[],text) from public, anon;
revoke all on function public.reconcile_payment(uuid,uuid,uuid,text) from public, anon;
revoke all on function public.void_reconciliation(uuid,uuid,text,text) from public, anon;
revoke all on function public.reverse_journal_batch(uuid,uuid,text,text) from public, anon;

grant execute on function public.create_project_cash_account(uuid,uuid,text,text),
  public.attach_contribution_cash(uuid,uuid,uuid,uuid,text),
  public.create_cost_obligation(uuid,uuid,uuid,text,bigint,text,date,text,text),
  public.update_cost_obligation_draft(uuid,uuid,uuid,text,bigint,text,date,text),
  public.delete_cost_obligation_draft(uuid,uuid),
  public.authorize_cost_obligation(uuid,uuid,text),
  public.pay_cost_obligation(uuid,uuid,uuid,bigint,date,text),
  public.import_bank_statement_lines(uuid,uuid,date[],text[],text[],text[],text[],text),
  public.reconcile_payment(uuid,uuid,uuid,text),
  public.void_reconciliation(uuid,uuid,text,text),
  public.reverse_journal_batch(uuid,uuid,text,text)
to authenticated;
