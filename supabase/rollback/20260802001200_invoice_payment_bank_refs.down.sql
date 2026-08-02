drop function if exists receive_purchase_invoice_with_stock(text, uuid);

create or replace function link_financial_movement(
  p_request_id text, p_reference_type text, p_reference_id uuid,
  p_bank_account uuid, p_direction text, p_amount numeric, p_currency text,
  p_fx_rate numeric, p_date date, p_memo text, p_partner_id uuid, p_document_id uuid
) returns uuid language plpgsql as $$
declare
  v_owner uuid; v_existing uuid; v_id uuid;
begin
  if p_request_id is null or length(p_request_id) < 1 then raise exception 'request_id مطلوب'; end if;
  if p_reference_type not in ('transaction','settlement','distribution_payment') then raise exception 'نوع المرجع غير صالح'; end if;
  if p_direction not in ('deposit','withdrawal') then raise exception 'الاتجاه غير صالح'; end if;
  if p_amount <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if p_bank_account is null then return null; end if;
  select bt.id into v_existing from bank_transactions bt
    where bt.reference_type = p_reference_type and bt.reference_id = p_reference_id limit 1;
  if v_existing is not null then return v_existing; end if;
  select owner_id into v_owner from bank_accounts where id = p_bank_account for update;
  if v_owner is null then raise exception 'الحساب البنكي غير موجود'; end if;
  insert into bank_transactions (
    owner_id, bank_account_id, direction, amount, currency, fx_rate_to_base,
    amount_base, transaction_date, reference_type, reference_id, partner_id, memo, document_id
  ) values (
    v_owner, p_bank_account, p_direction, p_amount, p_currency, coalesce(p_fx_rate, 1),
    round(p_amount * coalesce(p_fx_rate, 1), 3), p_date, p_reference_type,
    p_reference_id, p_partner_id, p_memo, p_document_id
  ) returning id into v_id;
  return v_id;
end; $$;
grant execute on function link_financial_movement(text, text, uuid, uuid, text, numeric, text, numeric, date, text, uuid, uuid) to authenticated;

alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in ('transaction','settlement','distribution_payment','transfer','manual','opening_balance'));
drop index if exists bank_transactions_idempotency_key_idx;
alter table bank_transactions drop column if exists status;
alter table bank_transactions drop column if exists idempotency_key;
