-- Security/atomicity hardening for purchase invoices, manual accounting
-- vouchers and the bank manual-review marker introduced by PR #66.

-- --------------------------------------------------------------------------
-- Tenant-safe schema and immutable operation/audit records
-- --------------------------------------------------------------------------
alter table purchase_invoices alter column owner_id set default auth.uid();
alter table purchase_invoice_lines alter column owner_id set default auth.uid();
alter table journal_entries alter column owner_id set default auth.uid();
alter table journal_entry_lines alter column owner_id set default auth.uid();

alter table journal_entries drop constraint if exists journal_entries_status_check;
alter table journal_entries add constraint journal_entries_status_check
  check (status in ('draft','posted','reversed','void'));
alter table journal_entries add column if not exists reversal_of_entry_id uuid;
alter table journal_entries add column if not exists reversed_by_entry_id uuid;
alter table journal_entries add column if not exists reversal_reason text;

alter table bank_transactions add column if not exists reviewed_by uuid;
alter table bank_transactions add column if not exists reviewed_at timestamptz;
alter table bank_transactions add column if not exists review_note text;
alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance',
    'invoice_payment','bill_payment','journal_posting','journal_reversal'
  ));

-- Replace single-column references with owner-aware composite references.
alter table purchase_invoices drop constraint if exists purchase_invoices_project_id_fkey;
alter table purchase_invoices drop constraint if exists purchase_invoices_bank_account_id_fkey;
alter table purchase_invoice_lines drop constraint if exists purchase_invoice_lines_invoice_id_fkey;
alter table purchase_invoice_lines drop constraint if exists purchase_invoice_lines_inventory_item_id_fkey;
alter table journal_entry_lines drop constraint if exists journal_entry_lines_entry_id_fkey;
alter table journal_entry_lines drop constraint if exists journal_entry_lines_bank_account_id_fkey;
alter table journal_entry_lines drop constraint if exists journal_entry_lines_project_id_fkey;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'purchase_invoices_project_owner_fk') then
    alter table purchase_invoices add constraint purchase_invoices_project_owner_fk
      foreign key (project_id, owner_id) references projects(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'purchase_invoices_partner_owner_fk') then
    alter table purchase_invoices add constraint purchase_invoices_partner_owner_fk
      foreign key (partner_id, owner_id) references partners(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'purchase_invoices_bank_owner_fk') then
    alter table purchase_invoices add constraint purchase_invoices_bank_owner_fk
      foreign key (bank_account_id, owner_id) references bank_accounts(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'purchase_lines_invoice_owner_fk') then
    alter table purchase_invoice_lines add constraint purchase_lines_invoice_owner_fk
      foreign key (invoice_id, owner_id) references purchase_invoices(id, owner_id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'purchase_lines_item_owner_fk') then
    alter table purchase_invoice_lines add constraint purchase_lines_item_owner_fk
      foreign key (inventory_item_id, owner_id) references inventory_items(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'journal_lines_entry_owner_fk') then
    alter table journal_entry_lines add constraint journal_lines_entry_owner_fk
      foreign key (entry_id, owner_id) references journal_entries(id, owner_id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'journal_lines_bank_owner_fk') then
    alter table journal_entry_lines add constraint journal_lines_bank_owner_fk
      foreign key (bank_account_id, owner_id) references bank_accounts(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'journal_lines_partner_owner_fk') then
    alter table journal_entry_lines add constraint journal_lines_partner_owner_fk
      foreign key (partner_id, owner_id) references partners(id, owner_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'journal_lines_project_owner_fk') then
    alter table journal_entry_lines add constraint journal_lines_project_owner_fk
      foreign key (project_id, owner_id) references projects(id, owner_id) on delete restrict;
  end if;
end $$;

create table if not exists purchase_invoice_operations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  request_id uuid not null,
  operation_type text not null check (operation_type in ('create','receive')),
  payload jsonb not null,
  result_id uuid not null,
  created_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, request_id)
);

create table if not exists purchase_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  request_id uuid not null,
  invoice_id uuid not null,
  bank_account_id uuid not null,
  amount numeric(18,3) not null check (amount > 0),
  currency text not null references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null,
  payment_date date not null,
  memo text,
  partner_id uuid,
  bank_transaction_id uuid not null,
  created_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, request_id),
  foreign key (invoice_id, owner_id) references purchase_invoices(id, owner_id) on delete restrict,
  foreign key (bank_account_id, owner_id) references bank_accounts(id, owner_id) on delete restrict,
  foreign key (bank_transaction_id, owner_id) references bank_transactions(id, owner_id) on delete restrict
);

create table if not exists journal_operations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  request_id uuid not null,
  operation_type text not null check (operation_type in ('create','post','void')),
  payload jsonb not null,
  result_id uuid not null,
  created_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, request_id)
);

create table if not exists bank_transaction_review_operations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  request_id uuid not null,
  transaction_id uuid not null,
  reviewed boolean not null,
  note text,
  created_at timestamptz not null default now(),
  unique (owner_id, request_id),
  foreign key (transaction_id, owner_id) references bank_transactions(id, owner_id) on delete restrict
);

create unique index if not exists inventory_purchase_receipt_line_idx
  on inventory_movements(owner_id, reference_type, reference_id)
  where reference_type = 'purchase_receipt_line';

-- RLS is forced even for table owners; SECURITY DEFINER RPCs are the write path.
alter table purchase_invoices enable row level security;
alter table purchase_invoices force row level security;
alter table purchase_invoice_lines enable row level security;
alter table purchase_invoice_lines force row level security;
alter table purchase_invoice_operations enable row level security;
alter table purchase_invoice_operations force row level security;
alter table purchase_invoice_payments enable row level security;
alter table purchase_invoice_payments force row level security;
alter table journal_entries enable row level security;
alter table journal_entries force row level security;
alter table journal_entry_lines enable row level security;
alter table journal_entry_lines force row level security;
alter table journal_operations enable row level security;
alter table journal_operations force row level security;
alter table bank_transaction_review_operations enable row level security;
alter table bank_transaction_review_operations force row level security;

drop policy if exists purchase_invoices_owner_all on purchase_invoices;
drop policy if exists purchase_invoice_lines_owner_all on purchase_invoice_lines;
drop policy if exists purchase_invoices_owner_select on purchase_invoices;
drop policy if exists purchase_invoices_owner_insert on purchase_invoices;
drop policy if exists purchase_invoices_owner_update on purchase_invoices;
drop policy if exists purchase_invoices_owner_delete on purchase_invoices;
drop policy if exists purchase_invoice_lines_owner_select on purchase_invoice_lines;
drop policy if exists purchase_invoice_lines_owner_insert on purchase_invoice_lines;
drop policy if exists purchase_invoice_lines_owner_update on purchase_invoice_lines;
drop policy if exists purchase_invoice_lines_owner_delete on purchase_invoice_lines;
drop policy if exists purchase_operations_owner_select on purchase_invoice_operations;
drop policy if exists purchase_payments_owner_select on purchase_invoice_payments;
drop policy if exists journal_entries_owner_all on journal_entries;
drop policy if exists journal_entry_lines_owner_all on journal_entry_lines;
drop policy if exists journal_entries_owner_select on journal_entries;
drop policy if exists journal_entries_owner_insert on journal_entries;
drop policy if exists journal_entries_owner_update on journal_entries;
drop policy if exists journal_entries_owner_delete on journal_entries;
drop policy if exists journal_lines_owner_select on journal_entry_lines;
drop policy if exists journal_lines_owner_insert on journal_entry_lines;
drop policy if exists journal_lines_owner_update on journal_entry_lines;
drop policy if exists journal_lines_owner_delete on journal_entry_lines;
drop policy if exists journal_operations_owner_select on journal_operations;
drop policy if exists bank_review_operations_owner_select on bank_transaction_review_operations;

create policy purchase_invoices_owner_select on purchase_invoices
  for select to authenticated using (owner_id = auth.uid());
create policy purchase_invoices_owner_insert on purchase_invoices
  for insert to authenticated with check (owner_id = auth.uid());
create policy purchase_invoices_owner_update on purchase_invoices
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy purchase_invoices_owner_delete on purchase_invoices
  for delete to authenticated using (owner_id = auth.uid());
create policy purchase_invoice_lines_owner_select on purchase_invoice_lines
  for select to authenticated using (owner_id = auth.uid());
create policy purchase_invoice_lines_owner_insert on purchase_invoice_lines
  for insert to authenticated with check (owner_id = auth.uid());
create policy purchase_invoice_lines_owner_update on purchase_invoice_lines
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy purchase_invoice_lines_owner_delete on purchase_invoice_lines
  for delete to authenticated using (owner_id = auth.uid());
create policy purchase_operations_owner_select on purchase_invoice_operations
  for select to authenticated using (owner_id = auth.uid());
create policy purchase_payments_owner_select on purchase_invoice_payments
  for select to authenticated using (owner_id = auth.uid());
create policy journal_entries_owner_select on journal_entries
  for select to authenticated using (owner_id = auth.uid());
create policy journal_entries_owner_insert on journal_entries
  for insert to authenticated with check (owner_id = auth.uid());
create policy journal_entries_owner_update on journal_entries
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy journal_entries_owner_delete on journal_entries
  for delete to authenticated using (owner_id = auth.uid());
create policy journal_lines_owner_select on journal_entry_lines
  for select to authenticated using (owner_id = auth.uid());
create policy journal_lines_owner_insert on journal_entry_lines
  for insert to authenticated with check (owner_id = auth.uid());
create policy journal_lines_owner_update on journal_entry_lines
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy journal_lines_owner_delete on journal_entry_lines
  for delete to authenticated using (owner_id = auth.uid());
create policy journal_operations_owner_select on journal_operations
  for select to authenticated using (owner_id = auth.uid());
create policy bank_review_operations_owner_select on bank_transaction_review_operations
  for select to authenticated using (owner_id = auth.uid());

revoke all on purchase_invoices, purchase_invoice_lines, purchase_invoice_operations,
  purchase_invoice_payments, journal_entries, journal_entry_lines, journal_operations,
  bank_transaction_review_operations from anon, authenticated;
grant select on purchase_invoices, purchase_invoice_lines, purchase_invoice_operations,
  purchase_invoice_payments, journal_entries, journal_entry_lines, journal_operations,
  bank_transaction_review_operations to authenticated;
revoke update on bank_transactions from authenticated;

create or replace function trg_financial_audit_immutable() returns trigger
language plpgsql set search_path = public as $$
begin
  raise exception 'سجل التدقيق المالي غير قابل للتعديل أو الحذف';
end; $$;

drop trigger if exists trg_purchase_payments_immutable on purchase_invoice_payments;
create trigger trg_purchase_payments_immutable before update or delete on purchase_invoice_payments
  for each row execute function trg_financial_audit_immutable();
drop trigger if exists trg_purchase_operations_immutable on purchase_invoice_operations;
create trigger trg_purchase_operations_immutable before update or delete on purchase_invoice_operations
  for each row execute function trg_financial_audit_immutable();
drop trigger if exists trg_journal_operations_immutable on journal_operations;
create trigger trg_journal_operations_immutable before update or delete on journal_operations
  for each row execute function trg_financial_audit_immutable();
drop trigger if exists trg_journal_lines_immutable on journal_entry_lines;
create trigger trg_journal_lines_immutable before update or delete on journal_entry_lines
  for each row execute function trg_financial_audit_immutable();

-- Remove the legacy non-atomic overloads before exposing the authoritative RPCs.
drop function if exists receive_purchase_invoice(text, uuid);
drop function if exists receive_purchase_invoice_with_stock(text, uuid);
drop function if exists pay_purchase_invoice(text, uuid, numeric, uuid, date, text);
drop function if exists post_journal_entry(text, uuid);
drop function if exists void_journal_entry(text, uuid);

-- --------------------------------------------------------------------------
-- Purchase invoice RPCs
-- --------------------------------------------------------------------------
create or replace function create_purchase_invoice_atomic(
  p_request_id uuid, p_vendor_invoice_number text, p_partner_id uuid,
  p_project_id uuid, p_bank_account_id uuid, p_issue_date date, p_due_date date,
  p_currency text, p_fx_rate numeric, p_vat_rate numeric, p_notes text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_id uuid; v_payload jsonb; v_old_payload jsonb;
  v_old_type text; v_line jsonb; v_qty numeric; v_price numeric; v_line_total numeric;
  v_subtotal numeric := 0; v_vat numeric; v_total numeric; v_seq bigint; i integer;
  v_ref uuid;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_request_id is null then raise exception 'request_id مطلوب'; end if;
  v_payload := jsonb_build_object(
    'vendor_invoice_number', p_vendor_invoice_number, 'partner_id', p_partner_id,
    'project_id', p_project_id, 'bank_account_id', p_bank_account_id,
    'issue_date', coalesce(p_issue_date, current_date), 'due_date', p_due_date,
    'currency', coalesce(p_currency, 'OMR'), 'fx_rate', coalesce(p_fx_rate, 1),
    'vat_rate', coalesce(p_vat_rate, 0), 'notes', p_notes, 'lines', p_lines
  );
  select operation_type, payload, result_id into v_old_type, v_old_payload, v_id
    from purchase_invoice_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old_type <> 'create' or v_old_payload is distinct from v_payload then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return v_id;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'فاتورة المشتريات يجب أن تحتوي على بند واحد على الأقل';
  end if;
  if p_partner_id is not null and not exists (select 1 from partners where id = p_partner_id and owner_id = v_owner) then
    raise exception 'المورد لا يخص نفس المالك';
  end if;
  if p_project_id is not null and not exists (select 1 from projects where id = p_project_id and owner_id = v_owner) then
    raise exception 'المشروع لا يخص نفس المالك';
  end if;
  if p_bank_account_id is not null and not exists (select 1 from bank_accounts where id = p_bank_account_id and owner_id = v_owner) then
    raise exception 'الحساب البنكي لا يخص نفس المالك';
  end if;
  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i;
    v_qty := coalesce((v_line->>'quantity')::numeric, 0);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    if v_qty <= 0 or v_price < 0 then raise exception 'كمية أو سعر بند المشتريات غير صالح'; end if;
    v_ref := nullif(v_line->>'inventory_item_id', '')::uuid;
    if v_ref is not null and not exists (select 1 from inventory_items where id = v_ref and owner_id = v_owner) then
      raise exception 'صنف المخزون لا يخص نفس المالك';
    end if;
    v_subtotal := v_subtotal + round(v_qty * v_price, 3);
  end loop;
  v_vat := round(v_subtotal * coalesce(p_vat_rate, 0) / 100, 3);
  v_total := round(v_subtotal + v_vat, 3);
  v_seq := next_owner_seq('purchase_invoice_' || to_char(coalesce(p_issue_date, current_date), 'YYYY'));
  v_id := gen_random_uuid();
  insert into purchase_invoices(
    id, owner_id, invoice_number, vendor_invoice_number, project_id, partner_id,
    bank_account_id, issue_date, due_date, currency, fx_rate_to_base, subtotal,
    vat_rate, vat_amount, total, amount_paid, status, notes
  ) values (
    v_id, v_owner, 'BILL-' || to_char(coalesce(p_issue_date, current_date), 'YYYY') || '-' || lpad(v_seq::text, 5, '0'),
    p_vendor_invoice_number, p_project_id, p_partner_id, p_bank_account_id,
    coalesce(p_issue_date, current_date), p_due_date, coalesce(p_currency, 'OMR'),
    coalesce(p_fx_rate, 1), v_subtotal, coalesce(p_vat_rate, 0), v_vat, v_total, 0, 'draft', p_notes
  );
  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i; v_qty := (v_line->>'quantity')::numeric; v_price := (v_line->>'unit_price')::numeric;
    insert into purchase_invoice_lines(
      owner_id, invoice_id, line_no, description_ar, description_en, quantity,
      unit_price, line_total, inventory_item_id
    ) values (
      v_owner, v_id, i + 1, nullif(v_line->>'description_ar',''),
      nullif(v_line->>'description_en',''), v_qty, v_price, round(v_qty * v_price, 3),
      nullif(v_line->>'inventory_item_id','')::uuid
    );
  end loop;
  insert into purchase_invoice_operations(owner_id, request_id, operation_type, payload, result_id)
    values (v_owner, p_request_id, 'create', v_payload, v_id);
  return v_id;
end; $$;

create or replace function receive_purchase_invoice_with_stock(
  p_request_id uuid, p_invoice_id uuid, p_receipt_date date
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_status text; v_payload jsonb; v_old_payload jsonb;
  v_old_type text; v_result uuid; v_line record;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  v_payload := jsonb_build_object('invoice_id', p_invoice_id, 'receipt_date', coalesce(p_receipt_date, current_date));
  select operation_type, payload, result_id into v_old_type, v_old_payload, v_result
    from purchase_invoice_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old_type <> 'receive' or v_old_payload is distinct from v_payload then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return v_result;
  end if;
  select status into v_status from purchase_invoices
    where id = p_invoice_id and owner_id = v_owner for update;
  if not found then raise exception 'فاتورة المشتريات غير موجودة'; end if;
  if v_status <> 'draft' then raise exception 'لا يمكن اعتماد الفاتورة إلا من حالة مسودة'; end if;
  for v_line in
    select pl.*, pi.currency, pi.fx_rate_to_base
      from purchase_invoice_lines pl join purchase_invoices pi on (pi.id, pi.owner_id) = (pl.invoice_id, pl.owner_id)
      where pl.invoice_id = p_invoice_id and pl.owner_id = v_owner and pl.inventory_item_id is not null
  loop
    insert into inventory_movements(
      owner_id, item_id, movement_type, quantity, unit_cost, currency, fx_rate_to_base,
      total_cost_base, movement_date, reference_type, reference_id, notes
    ) values (
      v_owner, v_line.inventory_item_id, 'purchase', v_line.quantity, v_line.unit_price,
      v_line.currency, v_line.fx_rate_to_base, round(v_line.line_total * v_line.fx_rate_to_base, 3),
      coalesce(p_receipt_date, current_date), 'purchase_receipt_line', v_line.id,
      coalesce(v_line.description_ar, 'استلام فاتورة مشتريات')
    );
  end loop;
  update purchase_invoices set status = 'received', updated_at = now()
    where id = p_invoice_id and owner_id = v_owner;
  insert into purchase_invoice_operations(owner_id, request_id, operation_type, payload, result_id)
    values (v_owner, p_request_id, 'receive', v_payload, p_invoice_id);
  return p_invoice_id;
end; $$;

create or replace function pay_purchase_invoice(
  p_request_id uuid, p_invoice_id uuid, p_amount numeric, p_bank_account uuid,
  p_date date, p_memo text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_old purchase_invoice_payments%rowtype;
  v_total numeric; v_paid numeric; v_status text; v_currency text; v_fx numeric; v_partner uuid;
  v_new_paid numeric; v_pay_id uuid := gen_random_uuid(); v_bank_tx uuid;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_request_id is null then raise exception 'request_id مطلوب'; end if;
  select * into v_old from purchase_invoice_payments where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old.invoice_id is distinct from p_invoice_id or v_old.bank_account_id is distinct from p_bank_account
       or abs(v_old.amount - p_amount) > 0.001 or v_old.payment_date is distinct from coalesce(p_date, current_date)
       or v_old.memo is distinct from p_memo then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return p_invoice_id;
  end if;
  if p_amount <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select total, amount_paid, status, currency, fx_rate_to_base, partner_id
    into v_total, v_paid, v_status, v_currency, v_fx, v_partner
    from purchase_invoices where id = p_invoice_id and owner_id = v_owner for update;
  if not found then raise exception 'فاتورة المشتريات غير موجودة'; end if;
  if v_status not in ('received','partial') then raise exception 'الفاتورة في حالة لا تقبل الدفع'; end if;
  if not exists (select 1 from bank_accounts where id = p_bank_account and owner_id = v_owner) then
    raise exception 'الحساب البنكي لا يخص نفس المالك';
  end if;
  if v_paid + p_amount > v_total + 0.001 then
    raise exception 'مبلغ الدفعة يتجاوز المستحق (المتبقي % فقط)', round(v_total - v_paid, 3);
  end if;
  v_new_paid := round(v_paid + p_amount, 3);
  insert into bank_transactions(
    owner_id, bank_account_id, direction, amount, currency, fx_rate_to_base,
    amount_base, transaction_date, reference_type, reference_id, partner_id,
    memo, idempotency_key, status
  ) values (
    v_owner, p_bank_account, 'withdrawal', p_amount, v_currency, v_fx,
    round(p_amount * v_fx, 3), coalesce(p_date, current_date), 'bill_payment',
    v_pay_id, v_partner, coalesce(p_memo, 'دفع فاتورة مشتريات'),
    'billpay_' || p_request_id::text, 'posted'
  ) returning id into v_bank_tx;
  insert into purchase_invoice_payments(
    id, owner_id, request_id, invoice_id, bank_account_id, amount, currency,
    fx_rate_to_base, payment_date, memo, partner_id, bank_transaction_id
  ) values (
    v_pay_id, v_owner, p_request_id, p_invoice_id, p_bank_account, p_amount,
    v_currency, v_fx, coalesce(p_date, current_date), p_memo, v_partner, v_bank_tx
  );
  update purchase_invoices set amount_paid = v_new_paid, bank_account_id = p_bank_account,
    status = case when v_new_paid >= v_total - 0.001 then 'paid' else 'partial' end,
    updated_at = now() where id = p_invoice_id and owner_id = v_owner;
  return p_invoice_id;
end; $$;

-- --------------------------------------------------------------------------
-- Manual accounting voucher RPCs (not a chart-of-accounts general ledger)
-- --------------------------------------------------------------------------
create or replace function create_journal_entry_atomic(
  p_request_id uuid, p_entry_date date, p_description_ar text, p_description_en text,
  p_currency text, p_fx_rate numeric, p_notes text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_id uuid; v_payload jsonb; v_old_payload jsonb; v_old_type text;
  v_line jsonb; v_debit numeric; v_credit numeric; v_total_d numeric := 0; v_total_c numeric := 0;
  v_bank uuid; v_partner uuid; v_project uuid; v_seq bigint; i integer;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  v_payload := jsonb_build_object(
    'entry_date', coalesce(p_entry_date, current_date), 'description_ar', p_description_ar,
    'description_en', p_description_en, 'currency', coalesce(p_currency, 'OMR'),
    'fx_rate', coalesce(p_fx_rate, 1), 'notes', p_notes, 'lines', p_lines
  );
  select operation_type, payload, result_id into v_old_type, v_old_payload, v_id
    from journal_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old_type <> 'create' or v_old_payload is distinct from v_payload then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return v_id;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'السند يجب أن يحتوي على بندين على الأقل';
  end if;
  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i; v_debit := coalesce((v_line->>'debit')::numeric, 0); v_credit := coalesce((v_line->>'credit')::numeric, 0);
    if v_debit < 0 or v_credit < 0 or (v_debit > 0 and v_credit > 0) or (v_debit = 0 and v_credit = 0) then
      raise exception 'بند السند يجب أن يكون مديناً أو دائناً فقط';
    end if;
    v_bank := nullif(v_line->>'bank_account_id','')::uuid;
    v_partner := nullif(v_line->>'partner_id','')::uuid;
    v_project := nullif(v_line->>'project_id','')::uuid;
    if v_bank is not null and not exists (select 1 from bank_accounts where id = v_bank and owner_id = v_owner) then raise exception 'الحساب البنكي لا يخص نفس المالك'; end if;
    if v_partner is not null and not exists (select 1 from partners where id = v_partner and owner_id = v_owner) then raise exception 'الطرف لا يخص نفس المالك'; end if;
    if v_project is not null and not exists (select 1 from projects where id = v_project and owner_id = v_owner) then raise exception 'المشروع لا يخص نفس المالك'; end if;
    v_total_d := v_total_d + v_debit; v_total_c := v_total_c + v_credit;
  end loop;
  if v_total_d <= 0 or abs(v_total_d - v_total_c) > 0.001 then
    raise exception 'السند غير متوازن: المدين % والدائن %', v_total_d, v_total_c;
  end if;
  v_seq := next_owner_seq('manual_voucher_' || to_char(coalesce(p_entry_date, current_date), 'YYYY'));
  v_id := gen_random_uuid();
  insert into journal_entries(
    id, owner_id, entry_number, entry_date, description_ar, description_en,
    currency, fx_rate_to_base, total_debit, total_credit, status, notes
  ) values (
    v_id, v_owner, 'MV-' || to_char(coalesce(p_entry_date, current_date), 'YYYY') || '-' || lpad(v_seq::text, 5, '0'),
    coalesce(p_entry_date, current_date), p_description_ar, p_description_en,
    coalesce(p_currency, 'OMR'), coalesce(p_fx_rate, 1), round(v_total_d, 3), round(v_total_c, 3), 'draft', p_notes
  );
  for i in 0..jsonb_array_length(p_lines) - 1 loop
    v_line := p_lines->i;
    insert into journal_entry_lines(
      owner_id, entry_id, line_no, account_code, description_ar, description_en,
      debit, credit, bank_account_id, partner_id, project_id
    ) values (
      v_owner, v_id, i + 1, nullif(v_line->>'account_code',''), nullif(v_line->>'description_ar',''),
      nullif(v_line->>'description_en',''), coalesce((v_line->>'debit')::numeric, 0),
      coalesce((v_line->>'credit')::numeric, 0), nullif(v_line->>'bank_account_id','')::uuid,
      nullif(v_line->>'partner_id','')::uuid, nullif(v_line->>'project_id','')::uuid
    );
  end loop;
  insert into journal_operations(owner_id, request_id, operation_type, payload, result_id)
    values (v_owner, p_request_id, 'create', v_payload, v_id);
  return v_id;
end; $$;

create or replace function post_journal_entry(p_request_id uuid, p_entry_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_status text; v_currency text; v_fx numeric; v_date date;
  v_payload jsonb := jsonb_build_object('entry_id', p_entry_id); v_old_payload jsonb; v_old_type text; v_result uuid;
  v_line record; v_amount numeric;
begin
  select operation_type, payload, result_id into v_old_type, v_old_payload, v_result
    from journal_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old_type <> 'post' or v_old_payload is distinct from v_payload then raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة'; end if;
    return v_result;
  end if;
  select status, currency, fx_rate_to_base, entry_date into v_status, v_currency, v_fx, v_date
    from journal_entries where id = p_entry_id and owner_id = v_owner for update;
  if not found then raise exception 'السند غير موجود'; end if;
  if v_status <> 'draft' then raise exception 'لا يمكن اعتماد السند إلا من حالة مسودة'; end if;
  for v_line in select * from journal_entry_lines where entry_id = p_entry_id and owner_id = v_owner order by line_no loop
    if v_line.bank_account_id is not null then
      v_amount := case when v_line.debit > 0 then v_line.debit else v_line.credit end;
      insert into bank_transactions(
        owner_id, bank_account_id, direction, amount, currency, fx_rate_to_base,
        amount_base, transaction_date, reference_type, reference_id, partner_id,
        memo, document_id, idempotency_key, status
      ) values (
        v_owner, v_line.bank_account_id, case when v_line.debit > 0 then 'deposit' else 'withdrawal' end,
        v_amount, v_currency, v_fx, round(v_amount * v_fx, 3), v_date,
        'journal_posting', v_line.id, v_line.partner_id,
        coalesce(v_line.description_ar, 'سند محاسبي يدوي'), p_entry_id,
        'jpost_' || p_request_id::text || '_' || v_line.id::text, 'posted'
      );
    end if;
  end loop;
  update journal_entries set status = 'posted', posted_at = now(), updated_at = now()
    where id = p_entry_id and owner_id = v_owner;
  insert into journal_operations(owner_id, request_id, operation_type, payload, result_id)
    values (v_owner, p_request_id, 'post', v_payload, p_entry_id);
  return p_entry_id;
end; $$;

create or replace function void_journal_entry(p_request_id uuid, p_entry_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_entry journal_entries%rowtype; v_payload jsonb;
  v_old_payload jsonb; v_old_type text; v_result uuid; v_reversal uuid; v_reversal_line uuid;
  v_seq bigint; v_line record; v_amount numeric;
begin
  v_payload := jsonb_build_object('entry_id', p_entry_id, 'reason', p_reason);
  select operation_type, payload, result_id into v_old_type, v_old_payload, v_result
    from journal_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old_type <> 'void' or v_old_payload is distinct from v_payload then raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة'; end if;
    return v_result;
  end if;
  select * into v_entry from journal_entries where id = p_entry_id and owner_id = v_owner for update;
  if not found then raise exception 'السند غير موجود'; end if;
  if v_entry.status = 'draft' then
    update journal_entries set status = 'void', reversal_reason = p_reason, updated_at = now()
      where id = p_entry_id and owner_id = v_owner;
    v_result := p_entry_id;
  elsif v_entry.status = 'posted' then
    v_seq := next_owner_seq('manual_voucher_' || to_char(current_date, 'YYYY'));
    v_reversal := gen_random_uuid();
    insert into journal_entries(
      id, owner_id, entry_number, entry_date, description_ar, description_en, currency,
      fx_rate_to_base, total_debit, total_credit, status, notes, posted_at,
      reversal_of_entry_id, reversal_reason
    ) values (
      v_reversal, v_owner, 'MV-' || to_char(current_date, 'YYYY') || '-' || lpad(v_seq::text, 5, '0'),
      current_date, 'عكس: ' || coalesce(v_entry.description_ar, v_entry.entry_number),
      'Reversal: ' || coalesce(v_entry.description_en, v_entry.entry_number), v_entry.currency,
      v_entry.fx_rate_to_base, v_entry.total_credit, v_entry.total_debit, 'posted',
      p_reason, now(), p_entry_id, p_reason
    );
    for v_line in select * from journal_entry_lines where entry_id = p_entry_id and owner_id = v_owner order by line_no loop
      insert into journal_entry_lines(
        owner_id, entry_id, line_no, account_code, description_ar, description_en,
        debit, credit, bank_account_id, partner_id, project_id
      ) values (
        v_owner, v_reversal, v_line.line_no, v_line.account_code, v_line.description_ar,
        v_line.description_en, v_line.credit, v_line.debit, v_line.bank_account_id,
        v_line.partner_id, v_line.project_id
      ) returning id into v_reversal_line;
      if v_line.bank_account_id is not null then
        v_amount := case when v_line.debit > 0 then v_line.debit else v_line.credit end;
        insert into bank_transactions(
          owner_id, bank_account_id, direction, amount, currency, fx_rate_to_base,
          amount_base, transaction_date, reference_type, reference_id, partner_id,
          memo, document_id, idempotency_key, status
        ) values (
          v_owner, v_line.bank_account_id, case when v_line.debit > 0 then 'withdrawal' else 'deposit' end,
          v_amount, v_entry.currency, v_entry.fx_rate_to_base,
          round(v_amount * v_entry.fx_rate_to_base, 3), current_date, 'journal_reversal',
          v_reversal_line, v_line.partner_id, coalesce(p_reason, 'عكس سند محاسبي يدوي'),
          v_reversal, 'jrev_' || p_request_id::text || '_' || v_line.id::text, 'posted'
        );
      end if;
    end loop;
    update journal_entries set status = 'reversed', reversed_by_entry_id = v_reversal,
      reversal_reason = p_reason, updated_at = now() where id = p_entry_id and owner_id = v_owner;
    v_result := v_reversal;
  else
    raise exception 'السند في حالة لا تقبل الإلغاء أو العكس';
  end if;
  insert into journal_operations(owner_id, request_id, operation_type, payload, result_id)
    values (v_owner, p_request_id, 'void', v_payload, v_result);
  return v_result;
end; $$;

-- This flag records an internal manual review only. It is deliberately not
-- described as statement matching/reconciliation.
create or replace function set_bank_transaction_reviewed(
  p_request_id uuid, p_transaction_id uuid, p_reviewed boolean, p_note text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := auth.uid(); v_old bank_transaction_review_operations%rowtype;
begin
  select * into v_old from bank_transaction_review_operations where owner_id = v_owner and request_id = p_request_id;
  if found then
    if v_old.transaction_id is distinct from p_transaction_id or v_old.reviewed is distinct from p_reviewed or v_old.note is distinct from p_note then
      raise exception 'تم استخدام معرّف العملية مسبقاً ببيانات مختلفة';
    end if;
    return p_transaction_id;
  end if;
  if not exists (select 1 from bank_transactions where id = p_transaction_id and owner_id = v_owner) then
    raise exception 'الحركة البنكية غير موجودة';
  end if;
  update bank_transactions set is_reconciled = p_reviewed,
    reviewed_by = case when p_reviewed then v_owner else null end,
    reviewed_at = case when p_reviewed then now() else null end,
    review_note = case when p_reviewed then p_note else null end,
    updated_at = now()
    where id = p_transaction_id and owner_id = v_owner;
  insert into bank_transaction_review_operations(owner_id, request_id, transaction_id, reviewed, note)
    values (v_owner, p_request_id, p_transaction_id, p_reviewed, p_note);
  return p_transaction_id;
end; $$;

revoke all on function create_purchase_invoice_atomic(uuid,text,uuid,uuid,uuid,date,date,text,numeric,numeric,text,jsonb) from public, anon;
revoke all on function receive_purchase_invoice_with_stock(uuid,uuid,date) from public, anon;
revoke all on function pay_purchase_invoice(uuid,uuid,numeric,uuid,date,text) from public, anon;
revoke all on function create_journal_entry_atomic(uuid,date,text,text,text,numeric,text,jsonb) from public, anon;
revoke all on function post_journal_entry(uuid,uuid) from public, anon;
revoke all on function void_journal_entry(uuid,uuid,text) from public, anon;
revoke all on function set_bank_transaction_reviewed(uuid,uuid,boolean,text) from public, anon;
grant execute on function create_purchase_invoice_atomic(uuid,text,uuid,uuid,uuid,date,date,text,numeric,numeric,text,jsonb) to authenticated;
grant execute on function receive_purchase_invoice_with_stock(uuid,uuid,date) to authenticated;
grant execute on function pay_purchase_invoice(uuid,uuid,numeric,uuid,date,text) to authenticated;
grant execute on function create_journal_entry_atomic(uuid,date,text,text,text,numeric,text,jsonb) to authenticated;
grant execute on function post_journal_entry(uuid,uuid) to authenticated;
grant execute on function void_journal_entry(uuid,uuid,text) to authenticated;
grant execute on function set_bank_transaction_reviewed(uuid,uuid,boolean,text) to authenticated;
