-- Investor capital/distribution lifecycle: draft vs approval, bank-backed cash,
-- tenant isolation, idempotency, reversal, Odoo dependency ordering.
\set ON_ERROR_STOP on
begin;
set local role postgres;

truncate table
  odoo_entity_mappings,odoo_sync_outbox,financial_audit_logs,
  distribution_allocations,distributions,partner_ledger_entries,equity_change_events,
  project_partners,bank_transactions,bank_accounts,partners,projects,owner_sequences cascade;

delete from auth.users where id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb94'
);
insert into auth.users(id,email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94','alice-investor@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb94','bob-investor@terranex.test');

set local role authenticated;
set local request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94';

insert into projects(id,sector_id,name_ar,name_en,status,start_date,base_currency)
values('11111111-1111-4111-8111-111111111194','real-estate','مشروع المستثمرين','Investor Project','active','2026-01-01','EGP');
insert into partners(id,name_ar,category,counterparty_role) values
 ('22222222-2222-4222-8222-222222222194','شريك أول','equity_partner','client'),
 ('22222222-2222-4222-8222-222222222195','شريك ثان','equity_partner','client');
insert into bank_accounts(id,name_ar,account_type,currency,opening_balance)
values('33333333-3333-4333-8333-333333333394','الخزينة الرئيسية','cash','EGP',0);

select change_ownership_atomic(
 '40000000-0000-4000-8000-000000000094','11111111-1111-4111-8111-111111111194',
 '22222222-2222-4222-8222-222222222194','2026-01-01',60,'entry',null,null,null,'تأسيس',null
);
select change_ownership_atomic(
 '40000000-0000-4000-8000-000000000095','11111111-1111-4111-8111-111111111194',
 '22222222-2222-4222-8222-222222222195','2026-01-01',40,'entry',null,null,null,'تأسيس',null
);

do $$
declare
  v_distribution uuid;
  v_first_allocation uuid;
  v_second_allocation uuid;
  v_first_payment uuid;
  v_second_payment uuid;
  v_capital uuid;
  v_capital_reversal uuid;
  v_result jsonb;
  v_count integer;
begin
  begin
    perform record_partner_ledger_entry_atomic(
      '40000000-0000-4000-8000-000000000096',
      '11111111-1111-4111-8111-111111111194','22222222-2222-4222-8222-222222222194',
      'capital_contribution',1000,'EGP',1,'2026-08-04',null,null,null,'غير مسموح',null
    );
    raise exception 'FAIL legacy RPC created a cash capital row';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
    if SQLERRM not like '%atomic lifecycle RPC%' then raise; end if;
  end;

  v_result:=record_partner_capital_movement_atomic(
    '40000000-0000-4000-8000-000000000097',
    '11111111-1111-4111-8111-111111111194','22222222-2222-4222-8222-222222222194',
    'capital_contribution',1000,'EGP',1,'2026-08-04',
    '33333333-3333-4333-8333-333333333394',null,null,'مساهمة تأسيسية'
  );
  v_capital:=(v_result->>'ledger_entry_id')::uuid;
  if not exists(select 1 from partner_ledger_entries where id=v_capital and bank_transaction_id is not null) then
    raise exception 'FAIL capital ledger is not linked to bank transaction';
  end if;
  if not exists(select 1 from bank_transactions where reference_id=v_capital and direction='deposit' and reference_type='partner_capital') then
    raise exception 'FAIL capital bank deposit missing';
  end if;

  perform record_partner_capital_movement_atomic(
    '40000000-0000-4000-8000-000000000097',
    '11111111-1111-4111-8111-111111111194','22222222-2222-4222-8222-222222222194',
    'capital_contribution',1000,'EGP',1,'2026-08-04',
    '33333333-3333-4333-8333-333333333394',null,null,'مساهمة تأسيسية'
  );
  select count(*) into v_count from partner_ledger_entries where id=v_capital;
  if v_count<>1 then raise exception 'FAIL capital retry duplicated ledger'; end if;

  v_result:=record_distribution_atomic(
    '40000000-0000-4000-8000-000000000098',
    '11111111-1111-4111-8111-111111111194','2026-08-04','2026-08-04',
    1000,'EGP',1,'توزيع أغسطس',null
  );
  v_distribution:=(v_result->>'distribution_id')::uuid;
  if (select status from distributions where id=v_distribution)<>'draft' then
    raise exception 'FAIL new distribution is not draft';
  end if;
  if exists(select 1 from partner_ledger_entries where related_distribution_id=v_distribution) then
    raise exception 'FAIL draft distribution created entitlements';
  end if;
  if (select count(*) from distribution_allocations where distribution_id=v_distribution)<>2 then
    raise exception 'FAIL frozen allocation snapshot missing';
  end if;

  v_result:=approve_distribution_atomic(
    '40000000-0000-4000-8000-000000000099',v_distribution,'اعتماد مجلس الإدارة'
  );
  if (select status from distributions where id=v_distribution)<>'approved' then
    raise exception 'FAIL distribution approval status';
  end if;
  if (select count(*) from partner_ledger_entries where related_distribution_id=v_distribution and entry_type='distribution_entitlement')<>2 then
    raise exception 'FAIL approval did not create two entitlements';
  end if;
  if (select coalesce(sum(amount),0) from partner_ledger_entries where related_distribution_id=v_distribution and entry_type='distribution_entitlement')<>1000 then
    raise exception 'FAIL entitlement total does not reconcile';
  end if;
  if (select count(*) from odoo_sync_outbox where entity_type='distribution' and entity_id=v_distribution and status='pending')<>1 then
    raise exception 'FAIL approved distribution Odoo event';
  end if;

  select id into v_first_allocation from distribution_allocations
   where distribution_id=v_distribution and partner_id='22222222-2222-4222-8222-222222222194';
  select id into v_second_allocation from distribution_allocations
   where distribution_id=v_distribution and partner_id='22222222-2222-4222-8222-222222222195';

  v_result:=pay_distribution_allocation_atomic(
    '40000000-0000-4000-8000-000000000100',v_first_allocation,
    '33333333-3333-4333-8333-333333333394','2026-08-05',null,'دفع الشريك الأول'
  );
  v_first_payment:=(v_result->>'ledger_entry_id')::uuid;
  if (select status from distributions where id=v_distribution)<>'approved' then
    raise exception 'FAIL partial distribution payment closed header';
  end if;
  if (select status from distribution_allocations where id=v_first_allocation)<>'paid' then
    raise exception 'FAIL first allocation not paid';
  end if;
  if not exists(select 1 from bank_transactions where reference_id=v_first_payment and direction='withdrawal') then
    raise exception 'FAIL first distribution bank withdrawal missing';
  end if;
  if (select available_at from odoo_sync_outbox where entity_type='partner_ledger_entry' and entity_id=v_first_payment)<>'infinity'::timestamptz then
    raise exception 'FAIL distribution payment not held for declaration mapping';
  end if;

  v_result:=pay_distribution_allocation_atomic(
    '40000000-0000-4000-8000-000000000101',v_second_allocation,
    '33333333-3333-4333-8333-333333333394','2026-08-05',null,'دفع الشريك الثاني'
  );
  v_second_payment:=(v_result->>'ledger_entry_id')::uuid;
  if (select status from distributions where id=v_distribution)<>'paid' then
    raise exception 'FAIL final payment did not close distribution';
  end if;

  v_result:=reverse_partner_ledger_entry_atomic(
    '40000000-0000-4000-8000-000000000102',v_capital,'2026-08-06','تصحيح مساهمة'
  );
  v_capital_reversal:=(v_result->>'reversal_entry_id')::uuid;
  if not exists(select 1 from bank_transactions where reference_id=v_capital_reversal and direction='withdrawal' and reference_type='partner_ledger_reversal') then
    raise exception 'FAIL capital reversal cash movement missing';
  end if;
  if (select available_at from odoo_sync_outbox where entity_type='partner_ledger_entry' and entity_id=v_capital_reversal)<>'infinity'::timestamptz then
    raise exception 'FAIL capital reversal not held for original mapping';
  end if;
end $$;

set local role postgres;
do $$
declare
  v_distribution uuid;
  v_capital uuid;
  v_capital_reversal uuid;
  v_first_payment uuid;
  v_second_payment uuid;
  v_event uuid;
  v_count integer;
begin
  select id into v_distribution from distributions
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94' and notes='اعتماد مجلس الإدارة';
  select id into v_capital from partner_ledger_entries
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94' and entry_type='capital_contribution' and notes='مساهمة تأسيسية';
  select id into v_capital_reversal from partner_ledger_entries
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94' and entry_type='reversal' and reversal_of_id=v_capital;
  select id into v_first_payment from partner_ledger_entries
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94' and entry_type='distribution_payment' and notes='دفع الشريك الأول';
  select id into v_second_payment from partner_ledger_entries
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94' and entry_type='distribution_payment' and notes='دفع الشريك الثاني';

  select count(*) into v_count from claim_odoo_sync_batch(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94',100,'general-test'
  ) where entity_type in ('distribution','partner_ledger_entry');
  if v_count<>0 then raise exception 'FAIL general worker claimed investor events'; end if;

  select id into v_event from odoo_sync_outbox where entity_type='distribution' and entity_id=v_distribution;
  perform complete_odoo_sync(v_event,'account.move',9401,'{"test":true}'::jsonb);
  if exists(select 1 from odoo_sync_outbox where entity_type='partner_ledger_entry'
      and entity_id in(v_first_payment,v_second_payment) and available_at='infinity'::timestamptz) then
    raise exception 'FAIL declaration mapping did not release distribution payments';
  end if;

  select id into v_event from odoo_sync_outbox where entity_type='partner_ledger_entry' and entity_id=v_capital;
  perform complete_odoo_sync(v_event,'account.move',9402,'{"test":true}'::jsonb);
  if (select available_at from odoo_sync_outbox where entity_type='partner_ledger_entry' and entity_id=v_capital_reversal)='infinity'::timestamptz then
    raise exception 'FAIL original capital mapping did not release reversal';
  end if;

  select id into v_event from odoo_sync_outbox where entity_type='partner_ledger_entry' and entity_id=v_first_payment;
  perform complete_odoo_sync(v_event,'account.move',9403,'{"test":true}'::jsonb);
end $$;

set local role authenticated;
set local request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa94';
do $$
declare
  v_distribution uuid;
  v_first_allocation uuid;
  v_first_payment uuid;
begin
  select id into v_distribution from distributions where notes='اعتماد مجلس الإدارة';
  select id into v_first_allocation from distribution_allocations
   where distribution_id=v_distribution and partner_id='22222222-2222-4222-8222-222222222194';
  select id into v_first_payment from partner_ledger_entries
   where related_distribution_id=v_distribution and entry_type='distribution_payment' and notes='دفع الشريك الأول';

  perform reverse_partner_ledger_entry_atomic(
    '40000000-0000-4000-8000-000000000103',v_first_payment,'2026-08-06','إلغاء دفعة التوزيع'
  );
  if (select status from distribution_allocations where id=v_first_allocation)<>'due' then
    raise exception 'FAIL reversed payment did not reopen allocation';
  end if;
  if (select status from distributions where id=v_distribution)<>'approved' then
    raise exception 'FAIL reversed payment did not reopen distribution';
  end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb94';
do $$
declare v_count integer;
begin
  select count(*) into v_count from distributions;
  if v_count<>0 then raise exception 'FAIL Bob sees Alice distributions'; end if;
  select count(*) into v_count from partner_ledger_entries;
  if v_count<>0 then raise exception 'FAIL Bob sees Alice partner ledger'; end if;
  begin
    perform approve_distribution_atomic(
      '40000000-0000-4000-8000-000000000104',
      '00000000-0000-4000-8000-000000000001',null
    );
    raise exception 'FAIL Bob approved a foreign distribution';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
  end;
end $$;

rollback;
\echo '=== INVESTOR CAPITAL / DISTRIBUTION LIFECYCLE: ALL CHECKS PASSED ==='
