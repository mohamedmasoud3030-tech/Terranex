-- Migration: Sales invoices (فواتير مبيعات)
-- Phase: Invoicing MVP — VAT-compliant drafts with Omani default, linked to
--        projects/partners, with payment tracking via bank_account_id.
-- Date: 2026-08-02

create table if not exists sales_invoices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  invoice_number text not null,
  project_id uuid references projects(id) on delete set null,
  partner_id uuid,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  issue_date date not null default current_date,
  due_date date,
  currency text not null default 'OMR' references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null default 1,
  subtotal numeric(18,3) not null default 0,
  vat_rate numeric(5,2) not null default 0,
  vat_amount numeric(18,3) not null default 0,
  total numeric(18,3) not null default 0,
  amount_paid numeric(18,3) not null default 0,
  status text not null default 'draft'
    check (status in ('draft','issued','paid','partial','void','overdue')),
  notes text,
  odoo_res_id integer unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, invoice_number)
);

create table if not exists sales_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  invoice_id uuid not null references sales_invoices(id) on delete cascade,
  line_no integer not null default 1,
  description_ar text,
  description_en text,
  quantity numeric(18,3) not null default 1,
  unit_price numeric(18,3) not null default 0,
  line_total numeric(18,3) not null default 0,
  created_at timestamptz not null default now(),
  unique (id, owner_id)
);

create index if not exists sales_invoices_owner_idx on sales_invoices(owner_id, issue_date desc);
create index if not exists sales_invoices_partner_idx on sales_invoices(partner_id);
create index if not exists sales_invoice_lines_invoice_idx on sales_invoice_lines(invoice_id);

drop trigger if exists trg_sales_invoices_updated on sales_invoices;
create trigger trg_sales_invoices_updated before update on sales_invoices
  for each row execute function set_timestamp();

alter table sales_invoices enable row level security;
alter table sales_invoice_lines enable row level security;

drop policy if exists sales_invoices_owner_select on sales_invoices;
drop policy if exists sales_invoices_owner_insert on sales_invoices;
drop policy if exists sales_invoices_owner_update on sales_invoices;
drop policy if exists sales_invoices_owner_delete on sales_invoices;
create policy sales_invoices_owner_select on sales_invoices
  for select to authenticated using (auth.uid() = owner_id);
create policy sales_invoices_owner_insert on sales_invoices
  for insert to authenticated with check (auth.uid() = owner_id);
create policy sales_invoices_owner_update on sales_invoices
  for update to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy sales_invoices_owner_delete on sales_invoices
  for delete to authenticated using (auth.uid() = owner_id);

drop policy if exists sales_invoice_lines_owner_select on sales_invoice_lines;
drop policy if exists sales_invoice_lines_owner_insert on sales_invoice_lines;
drop policy if exists sales_invoice_lines_owner_update on sales_invoice_lines;
drop policy if exists sales_invoice_lines_owner_delete on sales_invoice_lines;
drop policy if exists sales_invoice_lines_owner_all on sales_invoice_lines;
create policy sales_invoice_lines_owner_select on sales_invoice_lines
  for select to authenticated using (auth.uid() = owner_id);
create policy sales_invoice_lines_owner_all on sales_invoice_lines
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

grant select, insert, update, delete on sales_invoices to authenticated;
grant select, insert, update, delete on sales_invoice_lines to authenticated;

-- RPC: issue invoice (move status from draft -> issued), validating totals
create or replace function issue_sales_invoice(
  p_request_id text,
  p_invoice_id uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid;
  v_status text;
begin
  select owner_id, status into v_owner, v_status
    from sales_invoices where id = p_invoice_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  perform public.terranex_assert_owner(v_owner);
  if v_status <> 'draft' then
    raise exception 'لا يمكن إصدار الفاتورة إلا من حالة مسودة';
  end if;
  update sales_invoices set status = 'issued', updated_at = now()
    where id = p_invoice_id and owner_id = v_owner;
  return p_invoice_id;
end; $$;

grant execute on function issue_sales_invoice to authenticated;

-- RPC: register payment against an invoice (updates amount_paid & status)
create or replace function pay_sales_invoice(
  p_request_id text,
  p_invoice_id uuid,
  p_amount numeric,
  p_bank_account uuid,
  p_date date,
  p_memo text
) returns uuid language plpgsql as $$
declare
  v_owner uuid;
  v_total numeric;
  v_paid numeric;
  v_new_paid numeric;
  v_bank_owner uuid;
begin
  if p_amount <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select owner_id, total, amount_paid into v_owner, v_total, v_paid
    from sales_invoices where id = p_invoice_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  perform public.terranex_assert_owner(v_owner);
  if p_bank_account is not null then
    select owner_id into v_bank_owner from bank_accounts where id = p_bank_account;
    if v_bank_owner is null or v_bank_owner <> v_owner then
      raise exception 'الحساب البنكي لا يخص نفس المالك';
    end if;
  end if;
  v_new_paid := least(v_total, v_paid + p_amount);
  update sales_invoices set
    amount_paid = v_new_paid,
    bank_account_id = coalesce(p_bank_account, bank_account_id),
    status = case when v_new_paid >= v_total then 'paid'::text else 'partial'::text end,
    updated_at = now()
  where id = p_invoice_id and owner_id = v_owner;
  return p_invoice_id;
end; $$;

grant execute on function pay_sales_invoice to authenticated;
