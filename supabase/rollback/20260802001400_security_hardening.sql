-- Rollback 0014: security hardening

drop index if exists bank_transactions_idempotency_key_idx;
alter table bank_transactions drop column if exists status;
alter table bank_transactions drop column if exists idempotency_key;
alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in ('transaction','settlement','distribution_payment','transfer','manual','opening_balance'));

drop trigger if exists trg_bank_transactions_owner on bank_transactions;
drop trigger if exists trg_inventory_movements_owner on inventory_movements;
drop trigger if exists trg_inventory_items_owner on inventory_items;
drop trigger if exists trg_sales_invoice_lines_owner on sales_invoice_lines;
drop function if exists trg_force_owner() cascade;

drop trigger if exists trg_bank_transactions_protect on bank_transactions;
drop function if exists trg_bank_transactions_protect() cascade;

drop trigger if exists trg_inventory_movements_nodelete on inventory_movements;
drop function if exists trg_inventory_movements_nodelete() cascade;

drop trigger if exists trg_sales_invoices_nodelete on sales_invoices;
drop function if exists trg_sales_invoices_nodelete() cascade;

drop trigger if exists trg_sales_invoices_immutable on sales_invoices;
drop function if exists trg_sales_invoices_immutable() cascade;

create or replace function pay_sales_invoice(
  p_request_id text,
  p_invoice_id uuid,
  p_amount numeric,
  p_bank_account uuid,
  p_date date,
  p_memo text
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_total numeric; v_paid numeric; v_new_paid numeric; v_bank_owner uuid;
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

drop function if exists create_sales_invoice_atomic(text,uuid,uuid,uuid,date,date,text,numeric,numeric,text,jsonb);

drop function if exists next_owner_seq(text) cascade;
drop table if exists owner_sequences cascade;

drop trigger if exists trg_invoice_payments_immutable on invoice_payments;
drop function if exists trg_invoice_payments_immutable() cascade;
drop table if exists invoice_payments cascade;

drop view if exists inventory_stock;
-- restore inventory_stock as original (pre-0014): simple security_barrier view without auth.uid filter
create or replace view inventory_stock as
select
  i.*,
  coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type in ('purchase','transfer_in')), 0)
  - coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type in ('consume','waste','transfer_out')), 0)
  + coalesce((select sum(m.quantity) from inventory_movements m
             where m.item_id = i.id and m.movement_type = 'adjustment'), 0)
  as quantity_on_hand
from inventory_items i;
grant select on inventory_stock to authenticated;

drop view if exists bank_account_balances;
create or replace view bank_account_balances as
select
  b.id,
  b.owner_id,
  b.name_ar,
  b.account_type,
  b.currency,
  b.opening_balance + coalesce(d.total_in,0) - coalesce(w.total_out,0) as balance,
  b.opening_balance + coalesce(d.total_in_base,0) - coalesce(w.total_out_base,0) as balance_base
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

alter table company_settings add column if not exists odoo_api_key text;
