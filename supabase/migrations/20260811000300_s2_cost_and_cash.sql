-- GF-004 / S2 — Cost & Cash vertical slice.
-- Delivers: balanced double-entry project subledger, project cash accounts,
-- supplier obligations, payments, bank statement import, and reconciliation.
-- No allocation, distribution, period close, or external GL in this slice.

-- 1. Project lifecycle gains OPERATING (entered when first cost/cash event posts).
alter table public.investment_projects
  drop constraint if exists investment_projects_lifecycle_state_check;
alter table public.investment_projects
  add constraint investment_projects_lifecycle_state_check
  check (lifecycle_state in ('DRAFT','FUNDING','OPERATING','EXITING','CLOSED'));

-- 2. Financial accounts: semantic roles, not arbitrary chart. Each account belongs
--    to one organization and one semantic role; project-specific dimensions come
--    from journal lines, not from account proliferation.
create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  semantic_role text not null check (semantic_role in (
    'cash','bank_clearing','receivable','contribution_receivable',
    'inventory','property_inventory','development_wip','investment_property',
    'supplier_payable','accrued_cost','customer_advance',
    'contributed_capital','retained_result',
    'property_sale_revenue','other_project_income',
    'cost_of_sale','selling_cost','project_overhead','project_expense',
    'opening_balance_clearing','suspense','inter_project_clearing'
  )),
  display_name text not null check (char_length(trim(display_name)) between 2 and 120),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, semantic_role, currency)
);
create index if not exists financial_accounts_org_idx on public.financial_accounts(organization_id);

-- 3. Journal batches: atomic, balanced, immutable once posted.
create table if not exists public.journal_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  status text not null default 'POSTED' check (status in ('POSTED','REVERSED')),
  source_type text not null,
  source_id uuid not null,
  source_version integer not null default 1,
  posting_date date not null,
  description text,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  posted_at timestamptz not null default now(),
  posted_by uuid references auth.users(id) on delete restrict,
  reversed_by_batch_id uuid references public.journal_batches(id) on delete restrict,
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists journal_batches_project_idx on public.journal_batches(project_id);
create index if not exists journal_batches_source_idx on public.journal_batches(source_type, source_id);

-- 4. Journal lines: balanced debits/credits per batch. Amounts are bigint minor units.
create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  batch_id uuid not null references public.journal_batches(id) on delete restrict,
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  debit_minor_units bigint not null check (debit_minor_units >= 0),
  credit_minor_units bigint not null check (credit_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  counterparty_party_id uuid references public.parties(id) on delete restrict,
  sector_object_type text,
  sector_object_id uuid,
  cost_category text,
  description text,
  constraint journal_lines_one_sided check (
    (debit_minor_units > 0 and credit_minor_units = 0) or
    (credit_minor_units > 0 and debit_minor_units = 0) or
    (debit_minor_units = 0 and credit_minor_units = 0)
  ),
  constraint journal_lines_nonzero check (debit_minor_units > 0 or credit_minor_units > 0),
  foreign key (organization_id, batch_id)
    references public.journal_batches(organization_id, id) on delete restrict,
  foreign key (organization_id, account_id)
    references public.financial_accounts(organization_id, id) on delete restrict,
  foreign key (organization_id, counterparty_party_id)
    references public.parties(organization_id, id) on delete restrict
);
create index if not exists journal_lines_batch_idx on public.journal_lines(batch_id);
create index if not exists journal_lines_account_idx on public.journal_lines(account_id);

-- 5. Balance guard: every posted batch must balance in each currency.
create or replace function public.s2_guard_journal_batch_balanced() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_batch_id uuid; v_currency text; v_debits bigint; v_credits bigint;
begin
  v_batch_id := coalesce(new.batch_id, old.batch_id);
  select currency into v_currency from public.journal_lines where batch_id = v_batch_id limit 1;
  select sum(debit_minor_units), sum(credit_minor_units)
  into v_debits, v_credits
  from public.journal_lines
  where batch_id = v_batch_id and currency = v_currency;
  if v_debits is distinct from v_credits then
    raise exception 'journal batch must balance: debits=% credits=%', v_debits, v_credits;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists journal_batch_balanced_guard on public.journal_lines;
create constraint trigger journal_batch_balanced_guard
after insert or update or delete on public.journal_lines
deferrable initially deferred
for each row execute function public.s2_guard_journal_batch_balanced();

-- 6. Supplier obligations: recorded facts with optional journal posting.
create table if not exists public.obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  supplier_party_id uuid not null references public.parties(id) on delete restrict,
  status text not null default 'RECOGNIZED' check (status in ('RECOGNIZED','PAID','CANCELLED')),
  obligation_minor_units bigint not null check (obligation_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  cost_category text not null check (char_length(trim(cost_category)) between 2 and 80),
  description text,
  occurred_on date not null,
  journal_batch_id uuid references public.journal_batches(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recorded_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, supplier_party_id)
    references public.parties(organization_id, id) on delete restrict,
  foreign key (organization_id, journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict
);
create index if not exists obligations_project_idx on public.obligations(project_id);

-- 7. Payments: append-only cash outflows.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  obligation_id uuid not null references public.obligations(id) on delete restrict,
  payment_minor_units bigint not null check (payment_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  paid_on date not null,
  cash_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  journal_batch_id uuid references public.journal_batches(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recorded_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, obligation_id)
    references public.obligations(organization_id, id) on delete restrict,
  foreign key (organization_id, cash_account_id)
    references public.financial_accounts(organization_id, id) on delete restrict,
  foreign key (organization_id, journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict
);
create index if not exists payments_obligation_idx on public.payments(obligation_id);

-- 8. Bank statements: immutable external facts.
create table if not exists public.bank_statements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  cash_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  statement_date date not null,
  provider_reference text,
  imported_at timestamptz not null default now(),
  imported_by uuid references auth.users(id) on delete restrict,
  unique (id, organization_id),
  foreign key (organization_id, cash_account_id)
    references public.financial_accounts(organization_id, id) on delete restrict
);

create table if not exists public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  bank_statement_id uuid not null references public.bank_statements(id) on delete restrict,
  cash_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  amount_minor_units bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  value_date date not null,
  description text,
  provider_fingerprint text,
  reconciled boolean not null default false,
  unique (id, organization_id),
  foreign key (organization_id, bank_statement_id)
    references public.bank_statements(organization_id, id) on delete restrict,
  foreign key (organization_id, cash_account_id)
    references public.financial_accounts(organization_id, id) on delete restrict
);
create index if not exists bank_statement_lines_account_idx on public.bank_statement_lines(cash_account_id);

-- 9. Reconciliation: explicit matching, not inferred.
create table if not exists public.reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  bank_statement_line_id uuid not null references public.bank_statement_lines(id) on delete restrict,
  journal_line_id uuid not null references public.journal_lines(id) on delete restrict,
  matched_at timestamptz not null default now(),
  matched_by uuid references auth.users(id) on delete restrict,
  unique (bank_statement_line_id, journal_line_id),
  foreign key (organization_id, bank_statement_line_id)
    references public.bank_statement_lines(organization_id, id) on delete restrict,
  foreign key (organization_id, journal_line_id)
    references public.journal_lines(organization_id, id) on delete restrict
);

-- 10. RLS: default deny, member reads, no browser writes.
alter table public.financial_accounts enable row level security;
alter table public.journal_batches enable row level security;
alter table public.journal_lines enable row level security;
alter table public.obligations enable row level security;
alter table public.payments enable row level security;
alter table public.bank_statements enable row level security;
alter table public.bank_statement_lines enable row level security;
alter table public.reconciliation_matches enable row level security;
alter table public.financial_accounts force row level security;
alter table public.journal_batches force row level security;
alter table public.journal_lines force row level security;
alter table public.obligations force row level security;
alter table public.payments force row level security;
alter table public.bank_statements force row level security;
alter table public.bank_statement_lines force row level security;
alter table public.reconciliation_matches force row level security;

create policy financial_accounts_read on public.financial_accounts for select to authenticated
  using (public.is_active_member(organization_id));
create policy journal_batches_read on public.journal_batches for select to authenticated
  using (public.is_active_member(organization_id));
create policy journal_lines_read on public.journal_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy obligations_read on public.obligations for select to authenticated
  using (public.is_active_member(organization_id));
create policy payments_read on public.payments for select to authenticated
  using (public.is_active_member(organization_id));
create policy bank_statements_read on public.bank_statements for select to authenticated
  using (public.is_active_member(organization_id));
create policy bank_statement_lines_read on public.bank_statement_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy reconciliation_matches_read on public.reconciliation_matches for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.financial_accounts, public.journal_batches, public.journal_lines,
  public.obligations, public.payments, public.bank_statements, public.bank_statement_lines,
  public.reconciliation_matches from anon, authenticated;
grant select on public.financial_accounts, public.journal_batches, public.journal_lines,
  public.obligations, public.payments, public.bank_statements, public.bank_statement_lines,
  public.reconciliation_matches to authenticated;

-- 11. Immutability guards.
create or replace function public.s2_guard_journal_immutable() returns trigger
language plpgsql as $$
begin
  if old is not null and old.status = 'POSTED' and new.status <> 'REVERSED' then
    raise exception 'posted journal batch is immutable except via reversal';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists journal_batches_immutable on public.journal_batches;
create trigger journal_batches_immutable before update on public.journal_batches
  for each row execute function public.s2_guard_journal_immutable();

create or replace function public.s2_guard_append_only() returns trigger
language plpgsql as $$
begin
  raise exception using
    message = case tg_table_name
      when 'journal_lines' then 'journal lines are immutable once posted'
      when 'payments' then 'payments are append-only posted facts'
      when 'bank_statement_lines' then 'bank statement lines are immutable external facts'
      when 'reconciliation_matches' then 'reconciliation matches are immutable'
      else 'record is append-only' end,
    errcode = 'P0001';
end $$;

drop trigger if exists journal_lines_immutable on public.journal_lines;
create trigger journal_lines_immutable before update or delete on public.journal_lines
  for each row execute function public.s2_guard_append_only();
drop trigger if exists payments_immutable on public.payments;
create trigger payments_immutable before update or delete on public.payments
  for each row execute function public.s2_guard_append_only();
drop trigger if exists bank_statement_lines_immutable on public.bank_statement_lines;
create trigger bank_statement_lines_immutable before update or delete on public.bank_statement_lines
  for each row execute function public.s2_guard_append_only();
drop trigger if exists reconciliation_matches_immutable on public.reconciliation_matches;
create trigger reconciliation_matches_immutable before update or delete on public.reconciliation_matches
  for each row execute function public.s2_guard_append_only();

-- 12. Read views: cast int8 to text for exact JavaScript transport.
create or replace view public.obligations_read with (security_invoker=on) as
select id, organization_id, project_id, supplier_party_id, status,
       obligation_minor_units::text as obligation_minor_units, currency,
       cost_category, description, occurred_on, created_at
from public.obligations;

create or replace view public.payments_read with (security_invoker=on) as
select id, organization_id, project_id, obligation_id,
       payment_minor_units::text as payment_minor_units, currency, paid_on, created_at
from public.payments;

create or replace view public.project_cost_position with (security_invoker=on) as
select
  p.organization_id,
  p.id as project_id,
  p.reporting_currency as currency,
  coalesce(sum(o.obligation_minor_units) filter (where o.status = 'RECOGNIZED'), 0) as recognized_cost_minor_units,
  coalesce(sum(o.obligation_minor_units) filter (where o.status = 'PAID'), 0) as paid_cost_minor_units,
  coalesce(sum(o.obligation_minor_units) filter (where o.status in ('RECOGNIZED','PAID')), 0) as total_cost_minor_units
from public.investment_projects p
left join public.obligations o on o.project_id = p.id and o.organization_id = p.organization_id and o.status <> 'CANCELLED'
group by p.organization_id, p.id, p.reporting_currency;

grant select on public.obligations_read, public.payments_read, public.project_cost_position to authenticated;

-- 13. Server-authoritative commands.
create or replace function public.ensure_financial_account(
  p_organization_id uuid, p_semantic_role text, p_display_name text, p_currency text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_display_name is null or char_length(trim(p_display_name)) not between 2 and 120 then
    raise exception 'invalid account display name';
  end if;

  select id into v_id from public.financial_accounts
  where organization_id = p_organization_id
    and semantic_role = p_semantic_role
    and currency = p_currency;
  if v_id is not null then return v_id; end if;

  insert into public.financial_accounts(organization_id, semantic_role, display_name, currency)
  values (p_organization_id, p_semantic_role, trim(p_display_name), p_currency)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.record_obligation(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_cost_category text,
  p_description text,
  p_occurred_on date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_batch_id uuid; v_expense_account uuid; v_payable_account uuid;
  v_project_currency text; v_existing uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'obligation amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_occurred_on is null then raise exception 'obligation date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_cost_category is null or char_length(trim(p_cost_category)) not between 2 and 80 then
    raise exception 'cost category required';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (select 1 from public.parties
                 where id = p_supplier_party_id and organization_id = p_organization_id) then
    raise exception 'supplier party not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':obligation:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.obligations
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  -- Create balanced journal batch: Dr expense, Cr payable.
  v_expense_account := public.ensure_financial_account(p_organization_id, 'project_expense', 'مصروفات المشروع', p_currency);
  v_payable_account := public.ensure_financial_account(p_organization_id, 'supplier_payable', 'ذمم الموردين', p_currency);

  insert into public.journal_batches(
    organization_id, project_id, status, source_type, source_id, source_version,
    posting_date, description, idempotency_key, posted_by
  ) values (
    p_organization_id, p_project_id, 'POSTED', 'obligation', gen_random_uuid(), 1,
    p_occurred_on, 'اعتراف بالتزام: ' || coalesce(p_description, trim(p_cost_category)),
    trim(p_idempotency_key) || ':obligation', v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, counterparty_party_id, cost_category, description)
  values (p_organization_id, v_batch_id, v_expense_account, p_amount_minor_units, 0, p_currency, p_supplier_party_id, trim(p_cost_category), p_description);

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, counterparty_party_id, cost_category, description)
  values (p_organization_id, v_batch_id, v_payable_account, 0, p_amount_minor_units, p_currency, p_supplier_party_id, trim(p_cost_category), p_description);

  insert into public.obligations(
    organization_id, project_id, supplier_party_id, status, obligation_minor_units,
    currency, cost_category, description, occurred_on, journal_batch_id, idempotency_key, recorded_by
  ) values (
    p_organization_id, p_project_id, p_supplier_party_id, 'RECOGNIZED', p_amount_minor_units,
    p_currency, trim(p_cost_category), p_description, p_occurred_on, v_batch_id, trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  update public.investment_projects set lifecycle_state = 'OPERATING'
  where id = p_project_id and lifecycle_state in ('DRAFT','FUNDING');

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'OBLIGATION_RECOGNIZED','obligation', v_id,
          jsonb_build_object('project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
                             'obligation_minor_units', p_amount_minor_units, 'currency', p_currency,
                             'cost_category', trim(p_cost_category), 'occurred_on', p_occurred_on));
  return v_id;
end $$;

create or replace function public.record_payment(
  p_organization_id uuid,
  p_project_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_paid_on date,
  p_cash_account_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_batch_id uuid; v_payable_account uuid;
  v_project_currency text; v_existing uuid;
  v_obligation_amount bigint; v_already_paid bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_paid_on is null then raise exception 'payment date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':payment:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.payments
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  -- Lock obligation and check payment ceiling.
  select obligation_minor_units into v_obligation_amount
  from public.obligations
  where id = p_obligation_id and organization_id = p_organization_id and project_id = p_project_id
  for update;
  if v_obligation_amount is null then raise exception 'obligation not found'; end if;

  select coalesce(sum(payment_minor_units),0) into v_already_paid
  from public.payments
  where obligation_id = p_obligation_id and organization_id = p_organization_id;
  if v_already_paid + p_amount_minor_units > v_obligation_amount then
    raise exception 'payment exceeds remaining obligation amount';
  end if;

  -- Create balanced journal batch: Dr payable, Cr cash.
  v_payable_account := public.ensure_financial_account(p_organization_id, 'supplier_payable', 'ذمم الموردين', p_currency);

  insert into public.journal_batches(
    organization_id, project_id, status, source_type, source_id, source_version,
    posting_date, description, idempotency_key, posted_by
  ) values (
    p_organization_id, p_project_id, 'POSTED', 'payment', gen_random_uuid(), 1,
    p_paid_on, 'دفعة مقابل التزام',
    trim(p_idempotency_key) || ':payment', v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, description)
  values (p_organization_id, v_batch_id, v_payable_account, p_amount_minor_units, 0, p_currency, 'دفعة');

  insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, description)
  values (p_organization_id, v_batch_id, p_cash_account_id, 0, p_amount_minor_units, p_currency, 'دفعة');

  insert into public.payments(
    organization_id, project_id, obligation_id, payment_minor_units, currency, paid_on,
    cash_account_id, journal_batch_id, idempotency_key, recorded_by
  ) values (
    p_organization_id, p_project_id, p_obligation_id, p_amount_minor_units, p_currency,
    p_paid_on, p_cash_account_id, v_batch_id, trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  -- Mark obligation as fully paid if applicable.
  if v_already_paid + p_amount_minor_units = v_obligation_amount then
    update public.obligations set status = 'PAID' where id = p_obligation_id;
  end if;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'PAYMENT_RECORDED','payment', v_id,
          jsonb_build_object('project_id', p_project_id, 'obligation_id', p_obligation_id,
                             'payment_minor_units', p_amount_minor_units, 'currency', p_currency,
                             'paid_on', p_paid_on));
  return v_id;
end $$;

revoke all on function public.ensure_financial_account(uuid,text,text,text) from public, anon;
revoke all on function public.record_obligation(uuid,uuid,uuid,bigint,text,text,text,date,text) from public, anon;
revoke all on function public.record_payment(uuid,uuid,uuid,bigint,text,date,uuid,text) from public, anon;
grant execute on function public.ensure_financial_account(uuid,text,text,text),
  public.record_obligation(uuid,uuid,uuid,bigint,text,text,text,date,text),
  public.record_payment(uuid,uuid,uuid,bigint,text,date,uuid,text)
to authenticated;
