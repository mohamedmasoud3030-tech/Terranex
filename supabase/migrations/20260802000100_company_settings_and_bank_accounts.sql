-- Migration: Company Settings + Bank Accounts (الإعدادات العامة للشركة + حسابات البنوك والصناديق)
-- Phase: Operational foundation — enables "كم لدينا في البنك الآن؟" على لوحة التحكم
-- Date: 2026-08-02

-- ----------------------------------------------------------------
-- 0) currencies lookup (referenced by FKs in company_settings/bank_accounts/etc.)
-- ----------------------------------------------------------------
create table if not exists currencies (
  code text primary key,
  name_ar text,
  name_en text,
  symbol text,
  is_active boolean not null default true
);
insert into currencies (code, name_ar, name_en, symbol) values
  ('OMR', 'ريال عماني', 'Omani Rial', 'ر.ع'),
  ('EGP', 'جنيه مصري', 'Egyptian Pound', 'ج.م'),
  ('USD', 'دولار أمريكي', 'US Dollar', '$'),
  ('SAR', 'ريال سعودي', 'Saudi Riyal', 'ر.س'),
  ('AED', 'درهم إماراتي', 'UAE Dirham', 'د.إ'),
  ('EUR', 'يورو', 'Euro', '€'),
  ('GBP', 'جنيه إسترليني', 'British Pound', '£')
on conflict (code) do nothing;
alter table currencies enable row level security;
drop policy if exists currencies_all_read on currencies;
create policy currencies_all_read on currencies for select to authenticated using (true);
grant select on currencies to authenticated, anon;

-- ----------------------------------------------------------------
-- 1) company_settings: one row per owner (single-company per tenant)
-- ----------------------------------------------------------------
create table if not exists company_settings (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  company_name_ar text not null default 'شركتي',
  company_name_en text,
  commercial_register text,
  tax_number text,
  phone text,
  email text,
  address text,
  city text,
  country text check (country in ('EG','OM','SA','AE','OTHER')) default 'OM',
  fiscal_year_start date not null default (date_trunc('year', current_date))::date,
  base_currency text not null default 'OMR'
    references currencies(code) on delete restrict,
  vat_enabled boolean not null default false,
  vat_rate numeric(5,2) not null default 0
    check (vat_rate between 0 and 100),
  vat_number text,
  logo_url text,
  odoo_url text,
  odoo_db text,
  odoo_username text,
  odoo_api_key text,            -- encrypted in production; plain for self-host MVP
  odoo_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- trigger to bump updated_at
create or replace function set_timestamp() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

drop trigger if exists trg_company_settings_updated on company_settings;
create trigger trg_company_settings_updated
  before update on company_settings
  for each row execute function set_timestamp();

-- RLS: owner-only
alter table company_settings enable row level security;

drop policy if exists company_settings_owner_select on company_settings;
drop policy if exists company_settings_owner_insert on company_settings;
drop policy if exists company_settings_owner_update on company_settings;
drop policy if exists company_settings_owner_delete on company_settings;
create policy company_settings_owner_select on company_settings
  for select to authenticated using (auth.uid() = owner_id);
create policy company_settings_owner_insert on company_settings
  for insert to authenticated with check (auth.uid() = owner_id);
create policy company_settings_owner_update on company_settings
  for update to authenticated using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);
create policy company_settings_owner_delete on company_settings
  for delete to authenticated using (auth.uid() = owner_id);

grant select, insert, update, delete on company_settings to authenticated;

-- ensure a default row exists for an owner on first sign-in (call via RPC or bootstrap)
create or replace function ensure_company_settings(p_owner_id uuid)
returns company_settings language plpgsql as $$
declare
  row company_settings;
begin
  insert into company_settings (owner_id)
  values (p_owner_id)
  on conflict (owner_id) do nothing;
  select * into row from company_settings where owner_id = p_owner_id;
  return row;
end; $$;

-- ----------------------------------------------------------------
-- 2) bank_accounts: cash / bank / wallet accounts
-- ----------------------------------------------------------------
create table if not exists bank_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name_ar text not null,
  name_en text,
  account_type text not null
    check (account_type in ('bank','cash','wallet')),
  currency text not null references currencies(code) on delete restrict,
  opening_balance numeric(18,3) not null default 0 check (opening_balance >= 0),
  opening_date date not null default current_date,
  bank_name text,
  account_number text,
  iban text,
  is_archived boolean not null default false,
  odoo_res_id integer unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create index if not exists bank_accounts_owner_idx on bank_accounts(owner_id);

drop trigger if exists trg_bank_accounts_updated on bank_accounts;
create trigger trg_bank_accounts_updated before update on bank_accounts
  for each row execute function set_timestamp();

alter table bank_accounts enable row level security;

drop policy if exists bank_accounts_owner_select on bank_accounts;
drop policy if exists bank_accounts_owner_insert on bank_accounts;
drop policy if exists bank_accounts_owner_update on bank_accounts;
drop policy if exists bank_accounts_owner_delete on bank_accounts;
create policy bank_accounts_owner_select on bank_accounts
  for select to authenticated using (auth.uid() = owner_id);
create policy bank_accounts_owner_insert on bank_accounts
  for insert to authenticated with check (auth.uid() = owner_id);
create policy bank_accounts_owner_update on bank_accounts
  for update to authenticated using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);
create policy bank_accounts_owner_delete on bank_accounts
  for delete to authenticated using (auth.uid() = owner_id);

grant select, insert, update, delete on bank_accounts to authenticated;

-- guard: refuse to delete a bank account that has transactions
create or replace function guard_bank_account_deletion() returns trigger as $$
declare
  tx_count integer;
begin
  select count(*) into tx_count from bank_transactions
    where bank_account_id = OLD.id and owner_id = OLD.owner_id;
  if tx_count > 0 then
    raise exception 'لا يمكن حذف الحساب — توجد % حركة مرتبطة به.', tx_count;
  end if;
  return OLD;
end; $$ language plpgsql;

drop trigger if exists trg_guard_bank_account_deletion on bank_accounts;
create trigger trg_guard_bank_account_deletion before delete on bank_accounts
  for each row execute function guard_bank_account_deletion();

-- ----------------------------------------------------------------
-- 3) bank_transactions: movements on a bank/cash/wallet account
--    These are AUTOMATICALLY created by RPCs that touch money:
--    - record_transaction_atomic (income/expense)
--    - record_settlement_atomic (payment against an obligation)
--    - transfer between bank accounts (new RPC)
-- Manual entries are allowed for adjustments/opening balances.
-- ----------------------------------------------------------------
create table if not exists bank_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  bank_account_id uuid not null references bank_accounts(id) on delete restrict,
  direction text not null check (direction in ('deposit','withdrawal')),
  amount numeric(18,3) not null check (amount > 0),
  currency text not null references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null default 1,
  amount_base numeric(18,3) not null,
  transaction_date date not null default current_date,
  reference_type text not null
    check (reference_type in ('transaction','settlement','distribution_payment','transfer','manual','opening_balance')),
  reference_id uuid,
  counterparty_account_id uuid references bank_accounts(id) on delete set null,
  partner_id uuid,  -- optional counterparty display (not an FK to avoid cycles)
  memo text,
  document_id uuid,
  is_reconciled boolean not null default false,
  odoo_res_id integer unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create index if not exists bank_transactions_account_date_idx on bank_transactions(bank_account_id, transaction_date desc);
create index if not exists bank_transactions_owner_date_idx on bank_transactions(owner_id, transaction_date desc);
create index if not exists bank_transactions_reference_idx on bank_transactions(reference_type, reference_id);

drop trigger if exists trg_bank_transactions_updated on bank_transactions;
create trigger trg_bank_transactions_updated before update on bank_transactions
  for each row execute function set_timestamp();

alter table bank_transactions enable row level security;

drop policy if exists bank_transactions_owner_select on bank_transactions;
drop policy if exists bank_transactions_owner_insert on bank_transactions;
drop policy if exists bank_transactions_owner_update on bank_transactions;
drop policy if exists bank_transactions_owner_delete on bank_transactions;
create policy bank_transactions_owner_select on bank_transactions
  for select to authenticated using (auth.uid() = owner_id);
create policy bank_transactions_owner_insert on bank_transactions
  for insert to authenticated with check (auth.uid() = owner_id);
create policy bank_transactions_owner_update on bank_transactions
  for update to authenticated using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);
-- no delete through client directly: use a reversal journal entry to preserve audit
create policy bank_transactions_owner_delete on bank_transactions
  for delete to authenticated using (
    auth.uid() = owner_id and reference_type = 'manual'
  );

grant select, insert, update, delete on bank_transactions to authenticated;

-- ----------------------------------------------------------------
-- 4) computed view: current balance per bank account (fast for dashboard)
-- ----------------------------------------------------------------
create or replace view bank_account_balances as
select
  b.id,
  b.owner_id,
  b.name_ar,
  b.account_type,
  b.currency,
  b.opening_balance + coalesce(d.total_in, 0) - coalesce(w.total_out, 0) as balance,
  b.opening_balance + coalesce(d.total_in_base, 0) - coalesce(w.total_out_base, 0) as balance_base
from bank_accounts b
left join (
  select bank_account_id, sum(amount) as total_in, sum(amount_base) as total_in_base
  from bank_transactions where direction='deposit' group by bank_account_id
) d on d.bank_account_id = b.id
left join (
  select bank_account_id, sum(amount) as total_out, sum(amount_base) as total_out_base
  from bank_transactions where direction='withdrawal' group by bank_account_id
) w on w.bank_account_id = b.id
where b.is_archived = false;

grant select on bank_account_balances to authenticated;
