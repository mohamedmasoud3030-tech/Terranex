-- Odoo payments/banking bridge: transactional enqueue, tenant isolation,
-- immutable payment audit, bank-journal mapping and completion lifecycle.
\set ON_ERROR_STOP on

begin;
set local role postgres;

truncate table
  odoo_entity_mappings, odoo_sync_outbox,
  purchase_invoice_payments, purchase_invoice_operations,
  purchase_invoice_lines, purchase_invoices,
  invoice_payments, sales_invoice_lines, sales_invoices,
  bank_transactions, bank_accounts, owner_sequences,
  project_partners, partners, projects cascade;

delete from auth.users where id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb92'
);
insert into auth.users(id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92', 'alice-payments@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb92', 'bob-payments@terranex.test');

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92';

insert into projects(id, sector_id, name_ar, name_en, status, start_date, base_currency)
values (
  '11111111-1111-4111-8111-111111111192', 'real-estate',
  'مشروع مدفوعات أليس', 'Alice Payments', 'active', '2026-01-01', 'EGP'
);
insert into partners(id, name_ar, category, counterparty_role) values
  ('22222222-2222-4222-8222-222222222192', 'عميل أليس', 'counterparty', 'client'),
  ('22222222-2222-4222-8222-222222222193', 'مورد أليس', 'counterparty', 'supplier');
insert into bank_accounts(
  id, name_ar, account_type, currency, opening_balance, bank_name
) values (
  '33333333-3333-4333-8333-333333333392',
  'بنك مصر التشغيلي', 'bank', 'EGP', 0, 'بنك مصر'
);

do $$
declare
  v_sales_invoice uuid;
  v_purchase_invoice uuid;
  v_sales_payment uuid;
  v_purchase_payment uuid;
  v_count integer;
begin
  v_sales_invoice := create_sales_invoice_atomic(
    'sales-create-eg-92',
    '22222222-2222-4222-8222-222222222192',
    '11111111-1111-4111-8111-111111111192',
    '33333333-3333-4333-8333-333333333392',
    '2026-08-04', '2026-08-20', 'EGP', 1, 14, 'فاتورة مصرية',
    jsonb_build_array(
      jsonb_build_object('description_ar','خدمة إدارة','quantity',1,'unit_price',1000)
    )
  );
  perform issue_sales_invoice('sales-issue-eg-92', v_sales_invoice);
  perform pay_sales_invoice(
    'sales-pay-eg-92', v_sales_invoice, 570,
    '33333333-3333-4333-8333-333333333392',
    '2026-08-04', 'دفعة عميل نصفية'
  );
  select id into v_sales_payment
    from invoice_payments
   where owner_id = auth.uid() and request_id = 'sales-pay-eg-92';
  if v_sales_payment is null then raise exception 'FAIL missing immutable sales payment'; end if;

  v_purchase_invoice := create_purchase_invoice_atomic(
    '10000000-0000-4000-8000-000000000092', 'SUP-EG-92',
    '22222222-2222-4222-8222-222222222193',
    '11111111-1111-4111-8111-111111111192',
    '33333333-3333-4333-8333-333333333392',
    '2026-08-04', '2026-08-20', 'EGP', 1, 14, 'فاتورة مورد مصرية',
    jsonb_build_array(
      jsonb_build_object('description_ar','توريد مواد','quantity',2,'unit_price',250)
    )
  );
  perform receive_purchase_invoice_with_stock(
    '10000000-0000-4000-8000-000000000093',
    v_purchase_invoice,
    '2026-08-04'
  );
  perform pay_purchase_invoice(
    '10000000-0000-4000-8000-000000000094',
    v_purchase_invoice, 285,
    '33333333-3333-4333-8333-333333333392',
    '2026-08-04', 'دفعة مورد نصفية'
  );
  select id into v_purchase_payment
    from purchase_invoice_payments
   where owner_id = auth.uid()
     and request_id = '10000000-0000-4000-8000-000000000094';
  if v_purchase_payment is null then raise exception 'FAIL missing immutable purchase payment'; end if;

  select count(*) into v_count from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'bank_account'
     and entity_id = '33333333-3333-4333-8333-333333333392'
     and status = 'pending';
  if v_count <> 1 then raise exception 'FAIL bank account event count=%', v_count; end if;

  select count(*) into v_count from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'sales_payment'
     and entity_id = v_sales_payment and status = 'pending';
  if v_count <> 1 then raise exception 'FAIL sales payment event count=%', v_count; end if;

  select count(*) into v_count from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'purchase_payment'
     and entity_id = v_purchase_payment and status = 'pending';
  if v_count <> 1 then raise exception 'FAIL purchase payment event count=%', v_count; end if;

  -- Replaying the authoritative RPC does not create another payment or event.
  perform pay_sales_invoice(
    'sales-pay-eg-92', v_sales_invoice, 570,
    '33333333-3333-4333-8333-333333333392',
    '2026-08-04', 'دفعة عميل نصفية'
  );
  select count(*) into v_count from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'sales_payment'
     and entity_id = v_sales_payment and status = 'pending';
  if v_count <> 1 then raise exception 'FAIL payment replay duplicated Odoo event'; end if;
end $$;

-- Bob sees no payment/bank integration rows and cannot enqueue Alice's payment.
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb92';
do $$
declare v_count integer; v_payment uuid;
begin
  select count(*) into v_count from odoo_sync_outbox
   where entity_type in ('bank_account','sales_payment','purchase_payment');
  if v_count <> 0 then raise exception 'FAIL Bob sees Alice Odoo payment rows'; end if;

  select id into v_payment from invoice_payments
   where request_id = 'sales-pay-eg-92';
  if v_payment is not null then raise exception 'FAIL Bob sees Alice immutable payment'; end if;

  begin
    perform enqueue_odoo_sync(
      'bank_account', '33333333-3333-4333-8333-333333333392', 'upsert'
    );
    raise exception 'FAIL Bob enqueued Alice bank account';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
  end;
end $$;

-- Simulate successful Odoo worker completion. Payment rows must not be updated.
set local role postgres;
do $$
declare
  v_bank_event uuid;
  v_sales_event uuid;
  v_purchase_event uuid;
  v_sales_payment uuid;
  v_purchase_payment uuid;
  v_sales_amount numeric;
  v_purchase_amount numeric;
  v_count integer;
begin
  select id into v_bank_event from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and entity_type = 'bank_account'
     and entity_id = '33333333-3333-4333-8333-333333333392'
     and status = 'pending';

  select p.id, p.amount into v_sales_payment, v_sales_amount
    from invoice_payments p
   where p.owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and p.request_id = 'sales-pay-eg-92';
  select id into v_sales_event from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and entity_type = 'sales_payment' and entity_id = v_sales_payment;

  select p.id, p.amount into v_purchase_payment, v_purchase_amount
    from purchase_invoice_payments p
   where p.owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and p.request_id = '10000000-0000-4000-8000-000000000094';
  select id into v_purchase_event from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and entity_type = 'purchase_payment' and entity_id = v_purchase_payment;

  perform complete_odoo_sync(v_bank_event, 'account.journal', 9201, '{"test":true}'::jsonb);
  perform complete_odoo_sync(v_sales_event, 'account.payment', 9202, '{"test":true}'::jsonb);
  perform complete_odoo_sync(v_purchase_event, 'account.payment', 9203, '{"test":true}'::jsonb);

  if (select odoo_res_id from bank_accounts
       where id = '33333333-3333-4333-8333-333333333392') <> 9201 then
    raise exception 'FAIL bank journal source mapping';
  end if;
  if (select amount from invoice_payments where id = v_sales_payment) <> v_sales_amount then
    raise exception 'FAIL sales payment audit row mutated';
  end if;
  if (select amount from purchase_invoice_payments where id = v_purchase_payment) <> v_purchase_amount then
    raise exception 'FAIL purchase payment audit row mutated';
  end if;

  select count(*) into v_count from odoo_entity_mappings
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa92'
     and (
       (entity_type='bank_account' and entity_id='33333333-3333-4333-8333-333333333392' and odoo_record_id=9201)
       or (entity_type='sales_payment' and entity_id=v_sales_payment and odoo_record_id=9202)
       or (entity_type='purchase_payment' and entity_id=v_purchase_payment and odoo_record_id=9203)
     );
  if v_count <> 3 then raise exception 'FAIL stable payment/bank mappings count=%', v_count; end if;

  if exists (
    select 1 from odoo_sync_outbox
     where entity_type='bank_account'
       and entity_id='33333333-3333-4333-8333-333333333392'
       and status='pending'
  ) then
    raise exception 'FAIL mapping-only bank update requeued event';
  end if;
end $$;

rollback;
\echo '=== ODOO PAYMENTS / BANKING SUITE: ALL CHECKS PASSED ==='
