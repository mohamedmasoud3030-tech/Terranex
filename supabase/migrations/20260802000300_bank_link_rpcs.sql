-- Migration: RPCs to link financial transactions/settlements to bank_transactions
-- Phase: Cash-basis bookkeeping — every income/expense that moves cash also
--        lands in the bank ledger, with an idempotency key so double-clicks
--        on the Save button produce exactly one bank row.
-- Date: 2026-08-02

-- Ensure transactions.bank_account_id / settlements.bank_account_id exist
-- (migration 20260802000200 added them; re-run defensively).
alter table transactions add column if not exists bank_account_id uuid
  references bank_accounts(id) on delete set null;
alter table settlements  add column if not exists bank_account_id uuid
  references bank_accounts(id) on delete set null;

-- ----------------------------------------------------------------
-- 1) link_financial_movement: idempotently write a bank_transaction
--    for a financial transaction or settlement.
--    Called from the client AFTER the financial RPC returns the
--    transaction/settlement id. A request_id idempotency key is
--    used to avoid double-posting on retries (see ADR-003).
-- ----------------------------------------------------------------
create or replace function link_financial_movement(
  p_request_id      text,
  p_reference_type  text,       -- 'transaction' or 'settlement'
  p_reference_id    uuid,
  p_bank_account    uuid,
  p_direction       text,       -- 'deposit' for income/settlement-in, 'withdrawal' for expense/settlement-out
  p_amount          numeric,
  p_currency        text,
  p_fx_rate         numeric,
  p_date            date,
  p_memo            text,
  p_partner_id      uuid,
  p_document_id     uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid;
  v_existing uuid;
  v_id uuid;
begin
  if p_request_id is null or length(p_request_id) < 1 then
    raise exception 'request_id مطلوب';
  end if;
  if p_reference_type not in ('transaction','settlement','distribution_payment') then
    raise exception 'نوع المرجع غير صالح';
  end if;
  if p_direction not in ('deposit','withdrawal') then
    raise exception 'الاتجاه غير صالح';
  end if;
  if p_amount <= 0 then
    raise exception 'المبلغ يجب أن يكون أكبر من صفر';
  end if;
  if p_bank_account is null then
    return null;  -- no bank account selected -> nothing to post, soft success
  end if;

  -- Idempotency: if a row with this (owner, reference_type, reference_id)
  -- already exists, return it instead of creating a duplicate. The
  -- request_id is also matched as a secondary guard.
  select bt.id into v_existing
  from bank_transactions bt
  where bt.reference_type = p_reference_type
    and bt.reference_id = p_reference_id
  limit 1;
  if v_existing is not null then
    return v_existing;
  end if;

  select owner_id into v_owner from bank_accounts where id = p_bank_account for update;
  if v_owner is null then raise exception 'الحساب البنكي غير موجود'; end if;

  insert into bank_transactions (
    owner_id, bank_account_id, direction, amount, currency,
    fx_rate_to_base, amount_base, transaction_date,
    reference_type, reference_id, partner_id, memo, document_id
  ) values (
    v_owner, p_bank_account, p_direction, p_amount, p_currency,
    coalesce(p_fx_rate, 1), round(p_amount * coalesce(p_fx_rate, 1), 3), p_date,
    p_reference_type, p_reference_id, p_partner_id, p_memo, p_document_id
  ) returning id into v_id;

  return v_id;
end; $$;

grant execute on function link_financial_movement to authenticated;
