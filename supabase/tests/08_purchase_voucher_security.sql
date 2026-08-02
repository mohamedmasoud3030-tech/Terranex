-- Purchase invoices / manual accounting vouchers: atomicity, replay and RLS.
\set ON_ERROR_STOP on

begin;
set local role postgres;

truncate table
  bank_transaction_review_operations, journal_operations, journal_entry_lines, journal_entries,
  purchase_invoice_payments, purchase_invoice_operations, purchase_invoice_lines, purchase_invoices,
  bank_transactions, bank_accounts, inventory_movements, inventory_items, owner_sequences,
  project_partners, partners, projects cascade;
delete from auth.users where id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into auth.users(id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'alice66@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bob66@terranex.test');

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into projects(id, sector_id, name_ar, name_en, status, start_date, base_currency)
values ('11111111-1111-4111-8111-111111111111', 'real-estate', 'مشروع أليس', 'Alice', 'active', '2026-01-01', 'OMR');
insert into partners(id, name_ar, category, counterparty_role)
values ('22222222-2222-4222-8222-222222222222', 'مورد أليس', 'counterparty', 'supplier');
insert into bank_accounts(id, name_ar, account_type, currency, opening_balance)
values ('33333333-3333-4333-8333-333333333333', 'بنك أليس', 'bank', 'OMR', 0);
insert into inventory_items(id, name_ar, category, unit, currency)
values ('44444444-4444-4444-8444-444444444444', 'مخزون أليس', 'supply', 'unit', 'OMR');

do $$
declare
  v_bill uuid; v_bill_again uuid; v_line uuid; v_entry uuid; v_reversal uuid;
  v_count integer; v_tx uuid;
begin
  v_bill := create_purchase_invoice_atomic(
    '10000000-0000-4000-8000-000000000001', 'V-100',
    '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111',
    '33333333-3333-4333-8333-333333333333', '2026-08-01', '2026-08-15',
    'OMR', 1, 0, 'atomic bill',
    jsonb_build_array(jsonb_build_object(
      'description_ar','مواد','quantity',2,'unit_price',5,
      'inventory_item_id','44444444-4444-4444-8444-444444444444'))
  );
  v_bill_again := create_purchase_invoice_atomic(
    '10000000-0000-4000-8000-000000000001', 'V-100',
    '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111',
    '33333333-3333-4333-8333-333333333333', '2026-08-01', '2026-08-15',
    'OMR', 1, 0, 'atomic bill',
    jsonb_build_array(jsonb_build_object(
      'description_ar','مواد','quantity',2,'unit_price',5,
      'inventory_item_id','44444444-4444-4444-8444-444444444444'))
  );
  if v_bill_again <> v_bill or (select count(*) from purchase_invoices) <> 1
     or (select count(*) from purchase_invoice_lines where invoice_id = v_bill) <> 1 then
    raise exception 'FAIL purchase create atomic replay';
  end if;

  select id into v_line from purchase_invoice_lines where invoice_id = v_bill;
  perform receive_purchase_invoice_with_stock(
    '10000000-0000-4000-8000-000000000002', v_bill, '2026-08-03');
  perform receive_purchase_invoice_with_stock(
    '10000000-0000-4000-8000-000000000002', v_bill, '2026-08-03');
  if (select count(*) from inventory_movements where reference_type = 'purchase_receipt_line' and reference_id = v_line) <> 1
     or (select movement_date from inventory_movements where reference_id = v_line) <> '2026-08-03'::date then
    raise exception 'FAIL purchase receipt replay/date/per-line reference';
  end if;

  perform pay_purchase_invoice('10000000-0000-4000-8000-000000000003', v_bill, 5,
    '33333333-3333-4333-8333-333333333333', '2026-08-04', 'half one');
  perform pay_purchase_invoice('10000000-0000-4000-8000-000000000004', v_bill, 5,
    '33333333-3333-4333-8333-333333333333', '2026-08-04', 'half two');
  if (select count(*) from purchase_invoice_payments where invoice_id = v_bill) <> 2
     or (select count(*) from bank_transactions where reference_type = 'bill_payment') <> 2
     or (select status from purchase_invoices where id = v_bill) <> 'paid' then
    raise exception 'FAIL distinct equal purchase payments';
  end if;
  perform pay_purchase_invoice('10000000-0000-4000-8000-000000000004', v_bill, 5,
    '33333333-3333-4333-8333-333333333333', '2026-08-04', 'half two');
  if (select count(*) from purchase_invoice_payments where invoice_id = v_bill) <> 2 then
    raise exception 'FAIL purchase payment replay duplicated';
  end if;
  begin
    perform pay_purchase_invoice('10000000-0000-4000-8000-000000000004', v_bill, 4,
      '33333333-3333-4333-8333-333333333333', '2026-08-04', 'changed');
    raise exception 'FAIL conflicting payment replay accepted';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
  end;

  v_entry := create_journal_entry_atomic(
    '20000000-0000-4000-8000-000000000001', '2026-08-05', 'سند اختبار', null,
    'OMR', 1, null,
    jsonb_build_array(
      jsonb_build_object('account_code','BANK-REF','description_ar','إيداع','debit',10,'credit',0,'bank_account_id','33333333-3333-4333-8333-333333333333'),
      jsonb_build_object('account_code','OFFSET-REF','description_ar','مقابل','debit',0,'credit',10)
    )
  );
  perform post_journal_entry('20000000-0000-4000-8000-000000000002', v_entry);
  select count(*) into v_count from bank_transactions where reference_type = 'journal_posting' and document_id = v_entry;
  perform post_journal_entry('20000000-0000-4000-8000-000000000002', v_entry);
  if v_count <> 1 or (select count(*) from bank_transactions where reference_type = 'journal_posting' and document_id = v_entry) <> 1 then
    raise exception 'FAIL journal post atomic replay';
  end if;
  v_reversal := void_journal_entry('20000000-0000-4000-8000-000000000003', v_entry, 'تصحيح');
  if (select status from journal_entries where id = v_entry) <> 'reversed'
     or (select reversal_of_entry_id from journal_entries where id = v_reversal) <> v_entry
     or (select count(*) from bank_transactions where reference_type = 'journal_reversal' and document_id = v_reversal) <> 1 then
    raise exception 'FAIL posted voucher reversal';
  end if;

  select id into v_tx from bank_transactions where reference_type = 'journal_posting' limit 1;
  perform set_bank_transaction_reviewed('30000000-0000-4000-8000-000000000001', v_tx, true, 'reviewed only');
  if not (select is_reconciled from bank_transactions where id = v_tx)
     or (select reviewed_by from bank_transactions where id = v_tx) <> auth.uid() then
    raise exception 'FAIL manual review marker';
  end if;
end $$;

set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
do $$
declare v_table text; v_count integer;
begin
  foreach v_table in array array[
    'purchase_invoices','purchase_invoice_lines','purchase_invoice_payments','purchase_invoice_operations',
    'journal_entries','journal_entry_lines','journal_operations','bank_transaction_review_operations'
  ] loop
    execute format('select count(*) from %I', v_table) into v_count;
    if v_count <> 0 then raise exception 'FAIL RLS: Bob sees % in %', v_count, v_table; end if;
  end loop;
  begin
    perform create_purchase_invoice_atomic(
      '40000000-0000-4000-8000-000000000001', null, null, null,
      '33333333-3333-4333-8333-333333333333', current_date, null, 'OMR', 1, 0, null,
      jsonb_build_array(jsonb_build_object('description_ar','attack','quantity',1,'unit_price',1)));
    raise exception 'FAIL cross-owner bank accepted';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
  end;
end $$;

set local role postgres;
rollback;
\echo '=== PURCHASE / MANUAL VOUCHER SECURITY SUITE: ALL CHECKS PASSED ==='
