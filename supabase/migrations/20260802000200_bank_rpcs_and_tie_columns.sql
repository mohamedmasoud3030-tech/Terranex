-- Migration: RPCs for fund transfers and manual bank transactions, plus
-- columns linking transactions/settlements to bank_accounts (backfill-compatible).

-- ----------------------------------------------------------------
-- 1) bank_account_id column on transactions + settlements
-- ----------------------------------------------------------------
alter table transactions add column if not exists bank_account_id uuid
  references bank_accounts(id) on delete set null;
alter table settlements  add column if not exists bank_account_id uuid
  references bank_accounts(id) on delete set null;

-- ----------------------------------------------------------------
-- 2) RPC: record a transfer between two bank accounts (atomically)
-- ----------------------------------------------------------------
create or replace function record_bank_transfer(
  p_from_account uuid,
  p_to_account   uuid,
  p_amount       numeric,
  p_currency     text,
  p_fx_rate_from numeric,
  p_fx_rate_to   numeric,
  p_date         date,
  p_memo         text,
  p_request_id   text
) returns table (withdrawal_id uuid, deposit_id uuid)
language plpgsql
as $$
declare
  v_owner uuid;
  v_amount_from numeric(18,3);
  v_amount_to   numeric(18,3);
  v_wid uuid;
  v_did uuid;
begin
  if p_request_id is null or length(p_request_id) < 1 then
    raise exception 'request_id مطلوب';
  end if;
  if p_from_account = p_to_account then
    raise exception 'لا يمكن التحويل من وإلى نفس الحساب';
  end if;
  if p_amount <= 0 then
    raise exception 'المبلغ يجب أن يكون أكبر من صفر';
  end if;

  select owner_id into v_owner from bank_accounts
    where id = p_from_account for update;
  if v_owner is null then raise exception 'حساب المصدر غير موجود'; end if;

  if exists (select 1 from bank_accounts
              where id = p_to_account and owner_id <> v_owner) then
    raise exception 'حساب الوجهة لا يخص نفس المالك';
  end if;

  v_amount_from := p_amount;
  v_amount_to   := p_amount;

  insert into bank_transactions (
    owner_id, bank_account_id, direction, amount, currency,
    fx_rate_to_base, amount_base, transaction_date,
    reference_type, counterparty_account_id, memo
  ) values (
    v_owner, p_from_account, 'withdrawal', v_amount_from, p_currency,
    p_fx_rate_from, round(v_amount_from * p_fx_rate_from, 3), p_date,
    'transfer', p_to_account, coalesce(p_memo, 'تحويل بين الحسابات')
  ) returning id into v_wid;

  insert into bank_transactions (
    owner_id, bank_account_id, direction, amount, currency,
    fx_rate_to_base, amount_base, transaction_date,
    reference_type, counterparty_account_id, memo
  ) values (
    v_owner, p_to_account, 'deposit', v_amount_to, p_currency,
    p_fx_rate_to, round(v_amount_to * p_fx_rate_to, 3), p_date,
    'transfer', p_from_account, coalesce(p_memo, 'تحويل بين الحسابات')
  ) returning id into v_did;

  return query select v_wid, v_did;
end; $$;

-- ----------------------------------------------------------------
-- 3) RPC: record a manual bank transaction (deposit/withdrawal)
-- ----------------------------------------------------------------
create or replace function record_bank_transaction(
  p_bank_account uuid,
  p_direction    text,
  p_amount       numeric,
  p_currency     text,
  p_fx_rate      numeric,
  p_date         date,
  p_memo         text,
  p_partner_id   uuid,
  p_document_id  uuid,
  p_request_id   text
) returns uuid language plpgsql as $$
declare
  v_owner uuid;
  v_id uuid;
begin
  if p_request_id is null or length(p_request_id) < 1 then
    raise exception 'request_id مطلوب';
  end if;
  if p_amount <= 0 then
    raise exception 'المبلغ يجب أن يكون أكبر من صفر';
  end if;
  if p_direction not in ('deposit','withdrawal') then
    raise exception 'الاتجاه غير صالح';
  end if;

  select owner_id into v_owner from bank_accounts where id = p_bank_account for update;
  if v_owner is null then raise exception 'الحساب البنكي غير موجود'; end if;

  insert into bank_transactions (
    owner_id, bank_account_id, direction, amount, currency,
    fx_rate_to_base, amount_base, transaction_date,
    reference_type, partner_id, memo, document_id
  ) values (
    v_owner, p_bank_account, p_direction, p_amount, p_currency,
    p_fx_rate, round(p_amount * p_fx_rate, 3), p_date,
    'manual', p_partner_id, p_memo, p_document_id
  ) returning id into v_id;

  return v_id;
end; $$;

-- ----------------------------------------------------------------
-- 4) Hook: when record_transaction_atomic / record_settlement_atomic
--    write to bank_transactions if bank_account_id is provided.
--    We do NOT modify existing financial RPCs here to keep this change
--    small and backwards compatible — instead we expose a helper
--    RPC that the client calls AFTER the financial RPC returns.
-- ----------------------------------------------------------------
-- intentionally left blank — client-side orchestration for Phase 1.
