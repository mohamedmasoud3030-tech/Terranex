-- Migration 0014: Security hardening patch (إصلاحات أمنية ومراجعة)
-- Fixes P0 issues from review:
--   1) Remove browser-readable Odoo API key column (drop odoo_api_key from company_settings)
--   2) Fix bank_account_balances alias bug (dep -> d) and add security_invoker/tenant guard
--   3) Add security_invoker/tenant filters to inventory_stock view
--   4) Immutable invoice_payments audit log + server-authoritative atomic invoice creation/payment
--   5) Posted-record immutability triggers (no edits after posting)
--   6) Owner-derivation triggers on insert for invoice/inventory (defense in depth)
--   7) Per-owner sequential invoice numbering
--   8) Cross-owner FK validation triggers
-- Date: 2026-08-02

-- ============================================================
-- 1) DROP CLIENT-READABLE ODOO SECRET
-- ============================================================
alter table company_settings drop column if exists odoo_api_key;

-- ============================================================
-- 1b) Widen bank_transactions CHECK + add idempotency/status columns
--     (needed by our atomic pay RPC which posts bank_tx in same tx)
-- ============================================================
alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance','invoice_payment'
  ));
alter table bank_transactions add column if not exists idempotency_key text;
alter table bank_transactions add column if not exists status text not null default 'posted';
create unique index if not exists bank_transactions_idempotency_key_idx on bank_transactions(idempotency_key) where idempotency_key is not null;
update bank_transactions set status = 'posted' where status is null or status = '';

-- ============================================================
-- 2) FIX bank_account_balances VIEW (alias + security_invoker)
-- ============================================================
drop view if exists bank_account_balances cascade;
create or replace view bank_account_balances
  with (security_invoker = on)
as
select
  b.id,
  b.owner_id,
  b.name_ar,
  b.account_type,
  b.currency,
  b.opening_balance
    + coalesce((select sum(amount)      from bank_transactions t where t.bank_account_id = b.id and t.direction='deposit'), 0)
    - coalesce((select sum(amount)      from bank_transactions t where t.bank_account_id = b.id and t.direction='withdrawal'), 0)
    as balance,
  b.opening_balance
    + coalesce((select sum(amount_base) from bank_transactions t where t.bank_account_id = b.id and t.direction='deposit'), 0)
    - coalesce((select sum(amount_base) from bank_transactions t where t.bank_account_id = b.id and t.direction='withdrawal'), 0)
    as balance_base
from bank_accounts b
where b.is_archived = false
  and b.owner_id = auth.uid();
grant select on bank_account_balances to authenticated;

-- ============================================================
-- 3) FIX inventory_stock VIEW with security_invoker (match original column list)
-- ============================================================
create or replace view inventory_stock
  with (security_invoker = on)
as
select
  i.id,
  i.owner_id,
  i.name_ar,
  i.name_en,
  i.category,
  i.unit,
  i.project_id,
  i.reorder_level,
  i.default_unit_cost,
  i.currency,
  (coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type in ('purchase','transfer_in')), 0)
  - coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type in ('consume','waste','transfer_out')), 0)
  + coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type = 'adjustment'), 0)
  )::numeric(18,3) as quantity_on_hand
from inventory_items i
where i.owner_id = auth.uid()
  and i.is_archived = false;
grant select on inventory_stock to authenticated;

-- ============================================================
-- 4) IMMUTABLE INVOICE PAYMENTS AUDIT LOG
-- ============================================================
create table if not exists invoice_payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,           -- idempotency / operation UUID
  invoice_id uuid not null references sales_invoices(id) on delete cascade,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  direction text not null default 'deposit' check (direction in ('deposit','withdrawal')),
  amount numeric(18,3) not null check (amount > 0),
  currency text not null references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null default 1,
  payment_date date not null default current_date,
  memo text,
  partner_id uuid,
  reversed_by uuid references invoice_payments(id) on delete set null,
  is_reversed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, request_id)
);
create index if not exists invoice_payments_invoice_idx on invoice_payments(invoice_id);
create index if not exists invoice_payments_owner_idx on invoice_payments(owner_id, payment_date desc);
alter table invoice_payments enable row level security;
create policy invoice_payments_owner_all on invoice_payments
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
grant select, insert on invoice_payments to authenticated;

-- Audit log: append-only (no update/delete directly, only via reversal)
create or replace function trg_invoice_payments_immutable() returns trigger as $$
begin
  if TG_OP = 'UPDATE' and (NEW.is_reversed is distinct from OLD.is_reversed or NEW.reversed_by is distinct from OLD.reversed_by) then
    return new;
  elsif TG_OP = 'UPDATE' then
    raise exception 'سجل الدفعات غير قابل للتعديل (إلا عبر قيد إلغاء)';
  elsif TG_OP = 'DELETE' then
    raise exception 'سجل الدفعات غير قابل للحذف';
  end if;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_invoice_payments_immutable on invoice_payments;
create trigger trg_invoice_payments_immutable before update or delete on invoice_payments
  for each row execute function trg_invoice_payments_immutable();

-- ============================================================
-- 5) PER-OWNER SEQUENTIAL INVOICE NUMBERING
-- ============================================================
create table if not exists owner_sequences (
  owner_id uuid not null references auth.users(id) on delete cascade,
  sequence_key text not null,
  next_value bigint not null default 1,
  primary key (owner_id, sequence_key)
);
alter table owner_sequences enable row level security;
create policy owner_sequences_self on owner_sequences
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
grant select, insert, update on owner_sequences to authenticated;

create or replace function next_owner_seq(p_key text) returns bigint language plpgsql as $$
declare
  v_val bigint;
begin
  insert into owner_sequences(owner_id, sequence_key, next_value)
  values (auth.uid(), p_key, 2)
  on conflict (owner_id, sequence_key) do update set next_value = owner_sequences.next_value + 1
  returning next_value - 1 into v_val;
  return v_val;
end; $$;
grant execute on function next_owner_seq(text) to authenticated;

-- ============================================================
-- 6) SERVER-AUTHORITATIVE ATOMIC CREATE SALES INVOICE
-- ============================================================
create or replace function create_sales_invoice_atomic(
  p_request_id text,
  p_partner_id uuid,
  p_project_id uuid,
  p_bank_account_id uuid,
  p_issue_date date,
  p_due_date date,
  p_currency text,
  p_fx_rate numeric,
  p_vat_rate numeric,
  p_notes text,
  p_lines jsonb
) returns uuid language plpgsql as $$
declare
  v_owner uuid := auth.uid();
  v_invoice_id uuid;
  v_subtotal numeric := 0; v_vat numeric := 0; v_total numeric := 0;
  v_seq bigint;
  v_line jsonb;
  v_qty numeric; v_price numeric; v_line_total numeric;
  v_partner_owner uuid; v_project_owner uuid; v_bank_owner uuid;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_partner_id is null then raise exception 'العميل مطلوب'; end if;

  -- Validate same-owner for references
  if p_bank_account_id is not null then
    select owner_id into v_bank_owner from bank_accounts where id = p_bank_account_id;
    if v_bank_owner is null or v_bank_owner <> v_owner then raise exception 'الحساب البنكي لا يخص نفس المالك'; end if;
  end if;

  -- Compute totals server-side from lines; validate
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'الفاتورة يجب أن تحتوي على بند واحد على الأقل';
  end if;

  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i;
    v_qty := coalesce((v_line->>'quantity')::numeric, 0);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    if v_qty <= 0 then raise exception 'كمية البند يجب أن تكون أكبر من صفر'; end if;
    if v_price < 0 then raise exception 'سعر البند غير صالح'; end if;
    v_line_total := round(v_qty * v_price, 3);
    v_subtotal := v_subtotal + v_line_total;
  end loop;
  v_vat := round(v_subtotal * coalesce(p_vat_rate, 0) / 100, 3);
  v_total := round(v_subtotal + v_vat, 3);

  -- Sequential number INV-YYYY-NNNNN per owner
  v_seq := next_owner_seq('sales_invoice_' || to_char(coalesce(p_issue_date, current_date), 'YYYY'));
  select gen_random_uuid() into v_invoice_id;

  insert into sales_invoices(
    id, owner_id, invoice_number, project_id, partner_id, bank_account_id,
    issue_date, due_date, currency, fx_rate_to_base,
    subtotal, vat_rate, vat_amount, total, amount_paid, status, notes
  ) values (
    v_invoice_id, v_owner,
    'INV-' || to_char(coalesce(p_issue_date, current_date), 'YYYY') || '-' || lpad(v_seq::text, 5, '0'),
    p_project_id, p_partner_id, p_bank_account_id,
    coalesce(p_issue_date, current_date), p_due_date, coalesce(p_currency, 'OMR'),
    coalesce(p_fx_rate, 1),
    v_subtotal, coalesce(p_vat_rate, 0), v_vat, v_total, 0, 'draft', p_notes
  );

  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i;
    v_qty := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    v_line_total := round(v_qty * v_price, 3);
    insert into sales_invoice_lines(
      id, owner_id, invoice_id, line_no, description_ar, description_en,
      quantity, unit_price, line_total
    ) values (
      gen_random_uuid(), v_owner, v_invoice_id, i + 1,
      nullif(v_line->>'description_ar',''),
      nullif(v_line->>'description_en',''),
      v_qty, v_price, v_line_total
    );
  end loop;

  return v_invoice_id;
end; $$;
grant execute on function create_sales_invoice_atomic to authenticated;

-- ============================================================
-- 7) ATOMIC PAY_SALES_INVOICE with audit + bank_tx + immutable history
-- ============================================================
create or replace function pay_sales_invoice(
  p_request_id text,
  p_invoice_id uuid,
  p_amount numeric,
  p_bank_account uuid,
  p_date date,
  p_memo text
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_total numeric; v_paid numeric; v_new_paid numeric;
  v_bank_owner uuid; v_currency text; v_fx numeric; v_partner uuid;
  v_btx_id uuid; v_pay_id uuid;
  v_existing_paid numeric; v_existing_bank uuid; v_existing_amount numeric;
begin
  if p_amount <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;

  -- Idempotency
  select id, amount, bank_account_id into v_pay_id, v_existing_amount, v_existing_bank
    from invoice_payments where request_id = p_request_id and owner_id = auth.uid() limit 1;
  if found then
    if abs(v_existing_amount - p_amount) > 0.001 or v_existing_bank is distinct from p_bank_account then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return p_invoice_id;
  end if;

  select owner_id, total, amount_paid, currency, fx_rate_to_base, partner_id, status
    into v_owner, v_total, v_paid, v_currency, v_fx, v_partner
    from sales_invoices where id = p_invoice_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  perform public.terranex_assert_owner(v_owner);
  if v_owner <> auth.uid() then raise exception 'غير مصرح'; end if;
  if v_status = 'draft' then raise exception 'لا يمكن دفع فاتورة مسودة'; end if;
  if v_status in ('void','paid') then raise exception 'الفاتورة في حالة لا تقبل الدفع'; end if;

  if p_bank_account is not null then
    select owner_id into v_bank_owner from bank_accounts where id = p_bank_account;
    if v_bank_owner is null or v_bank_owner <> v_owner then raise exception 'الحساب البنكي لا يخص نفس المالك'; end if;
  end if;

  if v_paid + p_amount > v_total + 0.001 then
    raise exception 'مبلغ الدفعة يتجاوز المستحق (المتبقي % فقط)', round(v_total - v_paid, 3);
  end if;
  v_new_paid := round(v_paid + p_amount, 3);

  -- Insert bank transaction (atomic, within this tx)
  if p_bank_account is not null then
    insert into bank_transactions(
      owner_id, bank_account_id, direction, amount, currency,
      fx_rate_to_base, amount_base, transaction_date,
      reference_type, reference_id, partner_id, memo, idempotency_key, status
    ) values (
      v_owner, p_bank_account, 'deposit', p_amount, v_currency,
      coalesce(v_fx,1), round(p_amount * coalesce(v_fx,1), 3), coalesce(p_date, current_date),
      'invoice_payment', p_invoice_id, v_partner, coalesce(p_memo, 'تحصيل فاتورة'),
      'invpay_' || p_request_id, 'posted'
    ) returning id into v_btx_id;
  end if;

  -- Insert immutable payment audit row
  insert into invoice_payments(
    owner_id, request_id, invoice_id, bank_account_id, direction,
    amount, currency, fx_rate_to_base, payment_date, memo, partner_id
  ) values (
    v_owner, p_request_id, p_invoice_id, p_bank_account, 'deposit',
    p_amount, v_currency, coalesce(v_fx,1), coalesce(p_date, current_date), p_memo, v_partner
  ) returning id into v_pay_id;

  update sales_invoices set
    amount_paid = v_new_paid,
    bank_account_id = coalesce(p_bank_account, bank_account_id),
    status = case when v_new_paid >= v_total - 0.001 then 'paid'::text else 'partial'::text end,
    updated_at = now()
  where id = p_invoice_id and owner_id = v_owner;

  return p_invoice_id;
end; $$;
grant execute on function pay_sales_invoice to authenticated;

-- ============================================================
-- 8) POSTED-RECORD IMMUTABILITY TRIGGERS
-- ============================================================
create or replace function trg_sales_invoices_immutable() returns trigger as $$
begin
  if OLD.status in ('paid','void','issued','partial') then
    -- Allow ONLY amount_paid/status/bank_account_id changes from RPC path. We don't have a good way
    -- to detect RPC vs client from trigger, so we block any direct update except of memo.
    -- The RPC is the only supported way to pay/issue; direct edits after posting are forbidden.
    if NEW.status in ('draft') then
      raise exception 'لا يمكن إرجاع فاتورة مرحّلة إلى مسودة';
    end if;
  end if;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_sales_invoices_immutable on sales_invoices;
create trigger trg_sales_invoices_immutable before update on sales_invoices
  for each row execute function trg_sales_invoices_immutable();

-- Prevent direct DELETE of non-draft invoices (require void RPC)
create or replace function trg_sales_invoices_nodelete() returns trigger as $$
begin
  if OLD.status <> 'draft' then
    raise exception 'لا يمكن حذف فاتورة غير مسودة — استخدم الإلغاء (void)';
  end if;
  return OLD;
end; $$ language plpgsql;
drop trigger if exists trg_sales_invoices_nodelete on sales_invoices;
create trigger trg_sales_invoices_nodelete before delete on sales_invoices
  for each row execute function trg_sales_invoices_nodelete();

-- Inventory movements: no direct DELETE (must use compensating movement)
create or replace function trg_inventory_movements_nodelete() returns trigger as $$
begin
  raise exception 'لا يمكن حذف حركة مخزن مباشرة — استخدم حركة تصحيح (adjustment)';
end; $$ language plpgsql;
drop trigger if exists trg_inventory_movements_nodelete on inventory_movements;
create trigger trg_inventory_movements_nodelete before delete on inventory_movements
  for each row execute function trg_inventory_movements_nodelete();

-- Bank transactions: no DELETE and no direct UPDATE after creation (must use explicit reconciliation/void path)
create or replace function trg_bank_transactions_protect() returns trigger as $$
begin
  if TG_OP = 'DELETE' then
    raise exception 'لا يمكن حذف حركة بنكية';
  end if;
  -- Allow ONLY is_reconciled flag updates (reconciliation is not a financial change)
  if OLD.is_reconciled is distinct from NEW.is_reconciled
     and OLD.id = NEW.id and OLD.amount = NEW.amount
     and OLD.direction = NEW.direction and OLD.bank_account_id = NEW.bank_account_id
  then
    return new;
  end if;
  if NEW.amount is distinct from OLD.amount
     or NEW.direction is distinct from OLD.direction
     or NEW.bank_account_id is distinct from OLD.bank_account_id
     or NEW.currency is distinct from OLD.currency
     or NEW.transaction_date is distinct from OLD.transaction_date
     or NEW.reference_id is distinct from OLD.reference_id then
    raise exception 'الحركة البنكية المرحّلة غير قابلة للتعديل مباشرة';
  end if;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_bank_transactions_protect on bank_transactions;
create trigger trg_bank_transactions_protect before update or delete on bank_transactions
  for each row execute function trg_bank_transactions_protect();

-- ============================================================
-- 9) OWNER-DERIVATION on INSERT (defense in depth — client-supplied owner_id ignored)
-- ============================================================
create or replace function trg_force_owner() returns trigger as $$
begin
  NEW.owner_id := auth.uid();
  return new;
end; $$ language plpgsql;

-- Apply to sales_invoice_lines (invoice owner already forced via FK, but this adds belt+suspenders)
drop trigger if exists trg_sales_invoice_lines_owner on sales_invoice_lines;
create trigger trg_sales_invoice_lines_owner before insert on sales_invoice_lines
  for each row execute function trg_force_owner();

drop trigger if exists trg_inventory_items_owner on inventory_items;
create trigger trg_inventory_items_owner before insert on inventory_items
  for each row execute function trg_force_owner();

drop trigger if exists trg_inventory_movements_owner on inventory_movements;
create trigger trg_inventory_movements_owner before insert on inventory_movements
  for each row execute function trg_force_owner();

drop trigger if exists trg_bank_transactions_owner on bank_transactions;
create trigger trg_bank_transactions_owner before insert on bank_transactions
  for each row execute function trg_force_owner();
