-- Migration 001300: Manual journal entries (قيود يومية عامة)
-- Allows the user (or their accountant) to post multi-line balanced journal vouchers
-- (debit/credit) in double-entry style. If a line references a bank_account the
-- corresponding bank_transaction is auto-created via the link RPC (called from client).
-- Date: 2026-08-02

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default current_date,
  description_ar text,
  description_en text,
  currency text not null default 'OMR' references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null default 1,
  total_debit numeric(18,3) not null default 0,
  total_credit numeric(18,3) not null default 0,
  status text not null default 'draft'
    check (status in ('draft','posted','void')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  posted_at timestamptz,
  unique (id, owner_id),
  unique (owner_id, entry_number)
);

create table if not exists journal_entry_lines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null references journal_entries(id) on delete cascade,
  line_no integer not null default 1,
  account_code text,  -- free-text chart-of-accounts code (populated later when CoA exists)
  description_ar text,
  description_en text,
  debit numeric(18,3) not null default 0,
  credit numeric(18,3) not null default 0,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  partner_id uuid,
  project_id uuid references projects(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, owner_id),
  check ((debit >= 0) and (credit >= 0) and (debit = 0 or credit = 0))
);

create index if not exists journal_entries_owner_idx on journal_entries(owner_id, entry_date desc);
create index if not exists journal_entry_lines_entry_idx on journal_entry_lines(entry_id);

drop trigger if exists trg_journal_entries_updated on journal_entries;
create trigger trg_journal_entries_updated before update on journal_entries
  for each row execute function set_timestamp();

alter table journal_entries enable row level security;
alter table journal_entry_lines enable row level security;

drop policy if exists journal_entries_owner_all on journal_entries;
drop policy if exists journal_entry_lines_owner_all on journal_entry_lines;
create policy journal_entries_owner_all on journal_entries
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy journal_entry_lines_owner_all on journal_entry_lines
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

grant select, insert, update, delete on journal_entries to authenticated;
grant select, insert, update, delete on journal_entry_lines to authenticated;

-- RPC: post a drafted journal entry (sets totals & status, enforces balance)
create or replace function post_journal_entry(
  p_request_id text,
  p_entry_id uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_status text; v_total_d numeric; v_total_c numeric;
begin
  select owner_id, status into v_owner, v_status from journal_entries where id = p_entry_id for update;
  if not found then raise exception 'القيد غير موجود'; end if;
  perform public.terranex_assert_owner(v_owner);
  if v_status <> 'draft' then raise exception 'لا يمكن اعتماد القيد إلا من حالة مسودة'; end if;

  select coalesce(sum(debit),0), coalesce(sum(credit),0)
    into v_total_d, v_total_c
    from journal_entry_lines where entry_id = p_entry_id;

  if abs(v_total_d - v_total_c) > 0.001 then
    raise exception 'القيد غير متوازن: المدين % والدائن %', v_total_d, v_total_c;
  end if;
  if v_total_d <= 0 then raise exception 'يجب أن يحتوي القيد على مبالغ'; end if;

  update journal_entries set
    total_debit = round(v_total_d, 3),
    total_credit = round(v_total_c, 3),
    status = 'posted',
    posted_at = now(),
    updated_at = now()
  where id = p_entry_id and owner_id = v_owner;
  return p_entry_id;
end; $$;
grant execute on function post_journal_entry(text, uuid) to authenticated;

-- Void a posted entry (reverse is manual, this is a simple hard-void)
create or replace function void_journal_entry(
  p_request_id text,
  p_entry_id uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_status text;
begin
  select owner_id, status into v_owner, v_status from journal_entries where id = p_entry_id for update;
  if not found then raise exception 'القيد غير موجود'; end if;
  perform public.terranex_assert_owner(v_owner);
  if v_status = 'void' then return p_entry_id; end if;
  update journal_entries set status = 'void', updated_at = now() where id = p_entry_id and owner_id = v_owner;
  return p_entry_id;
end; $$;
grant execute on function void_journal_entry(text, uuid) to authenticated;
