-- Migration 0012: Invoice-payment bank reference types.
-- Extends bank_transactions.reference_type so sales/purchase invoice payments
-- can post to the bank ledger via link_financial_movement, and a helper RPC
-- posts purchase-invoice driven inventory inbound movements.
-- Date: 2026-08-02

-- 1) Widen the CHECK to allow invoice payments
alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance',
    'invoice_payment','bill_payment'
  ));

-- 1b) Add idempotency_key + status columns to bank_transactions (defensive for future dedupe)
alter table bank_transactions add column if not exists idempotency_key text;
alter table bank_transactions add column if not exists status text not null default 'posted';
-- Backfill status for existing rows
update bank_transactions set status = 'posted' where status is null or length(coalesce(status, '')) = 0;
create unique index if not exists bank_transactions_idempotency_key_idx on bank_transactions(idempotency_key) where idempotency_key is not null;

-- 2) Widen the RPC guard to accept invoice_payment / bill_payment / manual
create or replace function link_financial_movement(
  p_request_id text,
  p_reference_type text,
  p_reference_id uuid,
  p_bank_account uuid,
  p_direction text,
  p_amount numeric,
  p_currency text,
  p_fx_rate numeric,
  p_date date,
  p_memo text,
  p_partner_id uuid,
  p_document_id uuid
) returns uuid language plpgsql as $$
declare
  v_id uuid;
  v_existing uuid;
  v_owner uuid;
begin
  if p_request_id is null or length(p_request_id) < 1 then
    raise exception 'request_id مطلوب';
  end if;
  if p_reference_type not in ('transaction','settlement','distribution_payment','invoice_payment','bill_payment','manual') then
    raise exception 'نوع المرجع غير مدعوم: %', p_reference_type;
  end if;
  if p_direction not in ('deposit','withdrawal') then
    raise exception 'اتجاه الحركة غير صالح';
  end if;
  if p_amount <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if p_bank_account is null then return null; end if;

  -- idempotency: dedupe by idempotency_key first, then by (reference_type, reference_id)
  select id into v_existing from bank_transactions where idempotency_key = p_request_id limit 1;
  if v_existing is not null then return v_existing; end if;

  select bt.id into v_existing
  from bank_transactions bt
  where bt.reference_type = p_reference_type
    and bt.reference_id = p_reference_id
    and bt.bank_account_id = p_bank_account
    and abs(bt.amount - p_amount) < 0.001
  limit 1;
  if v_existing is not null then return v_existing; end if;

  select owner_id into v_owner from bank_accounts where id = p_bank_account for update;
  if v_owner is null then raise exception 'الحساب البنكي غير موجود'; end if;
  perform public.terranex_assert_owner(v_owner);

  insert into bank_transactions(
    owner_id, bank_account_id, transaction_date, direction, amount,
    currency, fx_rate_to_base, amount_base, memo, reference_type, reference_id,
    partner_id, document_id, idempotency_key, status
  ) values (
    v_owner, p_bank_account, p_date, p_direction, p_amount,
    p_currency, coalesce(p_fx_rate,1), round(p_amount * coalesce(p_fx_rate,1), 3), p_memo, p_reference_type, p_reference_id,
    p_partner_id, p_document_id, p_request_id, 'posted'
  ) returning id into v_id;

  return v_id;
end; $$;
grant execute on function link_financial_movement(text, text, uuid, uuid, text, numeric, text, numeric, date, text, uuid, uuid) to authenticated;

-- 3) Helper RPC: receive a purchase invoice and create inbound inventory
--    movements for any lines linked to an inventory_item.
--    Safe to retry: checks for existing movement by idempotency tag.
create or replace function receive_purchase_invoice_with_stock(
  p_request_id text,
  p_invoice_id uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_status text; v_pid uuid;
  v_line record;
begin
  select owner_id, status, id into v_owner, v_status, v_pid
    from purchase_invoices where id = p_invoice_id for update;
  if not found then raise exception 'فاتورة المشتريات غير موجودة'; end if;
  perform public.terranex_assert_owner(v_owner);
  if v_status <> 'draft' then
    raise exception 'لا يمكن اعتماد الفاتورة إلا من حالة مسودة';
  end if;

  update purchase_invoices set status = 'received', updated_at = now()
    where id = p_invoice_id and owner_id = v_owner;

  for v_line in
    select pl.* from purchase_invoice_lines pl
    where pl.invoice_id = p_invoice_id
      and pl.inventory_item_id is not null
  loop
    -- Idempotency: skip if this line already produced an inbound movement
    if not exists (
      select 1 from inventory_movements im
      where im.owner_id = v_owner
        and im.item_id = v_line.inventory_item_id
        and im.reference_type = 'bill_payment'
        and im.reference_id = p_invoice_id
        and abs(im.quantity - v_line.quantity) < 0.0001
    ) then
      insert into inventory_movements(
        owner_id, item_id, movement_type, quantity, unit_cost,
        currency, fx_rate_to_base, total_cost_base, movement_date,
        reference_type, reference_id, notes
      )
      select
        v_owner,
        v_line.inventory_item_id,
        'purchase'::text,
        v_line.quantity,
        v_line.unit_price,
        pi.currency,
        pi.fx_rate_to_base,
        round((v_line.line_total * pi.fx_rate_to_base)::numeric, 3),
        pi.issue_date,
        'bill_payment'::text,
        p_invoice_id,
        coalesce(v_line.description_ar, 'استلام بضاعة من فاتورة مشتريات')
      from purchase_invoices pi
      where pi.id = p_invoice_id;
    end if;
  end loop;

  return p_invoice_id;
end; $$;
grant execute on function receive_purchase_invoice_with_stock(text, uuid) to authenticated;
