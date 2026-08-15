-- R4 Procurement Financial Integration targeted verification.
-- Runs after GF-025/GF-026 fixtures and proves the single Procurement -> Finance
-- chain without creating a parallel payable/payment/reconciliation subsystem.

create or replace function s83_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s83_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin execute p_sql;
  exception when others then v_msg := sqlerrm; reset role; return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

select id as s83_project from public.investment_projects
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='GF025-PROJ' \gset
select id as s83_other_project from public.investment_projects
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='GF025-PROJ2' \gset
select id as s83_po from public.purchase_orders
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='PO-GF026-001' \gset
select id as s83_receipt_line, purchase_receipt_id as s83_receipt from public.purchase_receipt_lines
 where purchase_order_id=:'s83_po' order by created_at limit 1 \gset
select s25a_attach_evidence('00000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001', :'s83_project', 'RECEIPT', null, :'s83_receipt', null,
  's83-receipt-file') as s83_receipt_evidence;

-- Approved commercial PO establishes an unposted, server-derived commitment.
select 1/case when exists (
  select 1 from public.project_procurement_commitments_read
  where purchase_order_id=:'s83_po'
    and committed_minor_units=(
      select sum(line_amount_minor_units)::text from public.purchase_order_lines where purchase_order_id=:'s83_po')
    and accounting_effect='UNPOSTED_PURCHASE_COMMITMENT'
) then 1 else 0 end as s83_po_total_server_derived_commitment;

-- Record one received-basis supplier invoice: 10 units x 100 minor units.
select s83_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-001',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":10,"unit_price_minor_units":100}]',
    's83-invoice-create-001')$$,
  :'s83_project', :'s83_po', :'s83_receipt_line')) as s83_invoice \gset

select 1/case when (select invoice_total_minor_units='1000' and status='SUBMITTED'
  from public.supplier_invoices_read where id=:'s83_invoice') then 1 else 0 end
  as s83_invoice_total_server_derived;

-- Response-loss replay returns one invoice; changed payload with same key fails.
select 1/case when s83_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-001',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":10,"unit_price_minor_units":100}]',
    's83-invoice-create-001')$$,
  :'s83_project', :'s83_po', :'s83_receipt_line'))=:'s83_invoice'
  then 1 else 0 end as s83_invoice_idempotent_replay;

select 1/case when s83_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-CHANGED',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":10,"unit_price_minor_units":100}]',
    's83-invoice-create-001')$$,
  :'s83_project', :'s83_po', :'s83_receipt_line')) like '%idempotency key payload mismatch%'
  then 1 else 0 end as s83_invoice_changed_replay_rejected;

-- Cross-project and cross-tenant linkage fail at the command/database boundary.
select 1/case when s83_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-XPROJECT',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":1,"unit_price_minor_units":100}]',
    's83-invoice-xproject')$$,
  :'s83_other_project', :'s83_po', :'s83_receipt_line')) like '%purchase order not found%'
  then 1 else 0 end as s83_cross_project_invoice_rejected;

select 1/case when s83_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-XTENANT',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":1,"unit_price_minor_units":100}]',
    's83-invoice-xtenant')$$,
  :'s83_project', :'s83_po', :'s83_receipt_line')) like '%forbidden%'
  then 1 else 0 end as s83_cross_tenant_invoice_rejected;

-- Owner/checker approval creates the existing authoritative cost_obligation and
-- its normal Finance Core posting; no Procurement payable table exists.
select s25a_attach_evidence('00000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001', :'s83_project', 'SUPPLIER_INVOICE', null, null, :'s83_invoice',
  's83-invoice-file') as s83_invoice_evidence;
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,'s83-invoice-approve-001')$$,
  :'s83_invoice')) as s83_obligation \gset

select 1/case when exists (
  select 1 from public.cost_obligations o
  join public.supplier_invoices i on i.cost_obligation_id=o.id
  where i.id=:'s83_invoice' and i.status='APPROVED'
    and o.id=:'s83_obligation' and o.project_id=:'s83_project'
    and o.amount_minor_units=1000 and o.status='AUTHORIZED'
    and o.source_supplier_invoice_id=i.id
) and exists (
  select 1 from public.journal_batches
  where source_type='COST_OBLIGATION' and source_id=:'s83_obligation'
) then 1 else 0 end as s83_invoice_reuses_finance_core_payable;

select 1/case when s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,'s83-invoice-approve-001')$$,
  :'s83_invoice'))=:'s83_obligation' then 1 else 0 end as s83_approval_replay_safe;

-- A competing invoice may be submitted, but exact matching is rechecked under
-- the PO lock at approval. It cannot consume more than remaining receipt truth.
select s83_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-OVER',current_date,'EGP','EXPENSE',
    'فاتورة مورد موثقة',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":40,"unit_price_minor_units":100}]',
    's83-invoice-over-create')$$,
  :'s83_project', :'s83_po', :'s83_receipt_line')) as s83_over_invoice \gset
select s25a_attach_evidence('00000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001', :'s83_project', 'SUPPLIER_INVOICE', null, null, :'s83_over_invoice',
  's83-over-invoice-file') as s83_over_invoice_evidence;
select 1/case when s83_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,'s83-invoice-over-approve')$$,
  :'s83_over_invoice')) like '%exceeds remaining received quantity%'
  then 1 else 0 end as s83_invoice_receipt_ceiling_enforced;

-- Shared Finance payment is proposal -> independent approval -> posting.
-- A new zero-balance account must fail before any proposal can be recorded.
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,'حساب R4','EGP')$$,
  :'s83_project')) as s83_cash \gset
select 1/case when s83_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,1,current_date,'s83-zero-cash-proposal')$$,
  :'s83_obligation', :'s83_cash')) like '%payment exceeds available cash%'
  then 1 else 0 end as s83_zero_cash_payment_rejected;
select 1/case when not has_function_privilege(
  'authenticated', 'public.pay_cost_obligation(uuid,uuid,uuid,bigint,date,text)', 'EXECUTE')
  then 1 else 0 end as s83_direct_payment_rpc_revoked;

-- Explicit balanced test funding (not an application shortcut) gives exactly
-- 1,000 minor units of available book cash for the two partial payments.
select id as s83_bank_account from public.semantic_accounts where role='BANK_CASH' \gset
select id as s83_capital_account from public.semantic_accounts where role='CONTRIBUTED_CAPITAL' \gset
insert into public.journal_batches(
  organization_id,project_id,source_type,source_id,transaction_date,
  idempotency_key,request_hash,posted_by
) values (
  '10000000-0000-4000-8000-000000000001',:'s83_project','CONTRIBUTION_CASH_ATTRIBUTION',
  gen_random_uuid(),current_date,'s83-explicit-cash-fixture',repeat('8',64),
  '00000000-0000-4000-8000-000000000001'
) returning id as s83_funding_batch \gset
insert into public.journal_lines(
  batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,
  currency,cash_account_id,transaction_date
) values
  (:'s83_funding_batch','10000000-0000-4000-8000-000000000001',:'s83_project',:'s83_bank_account',1000,0,'EGP',:'s83_cash',current_date),
  (:'s83_funding_batch','10000000-0000-4000-8000-000000000001',:'s83_project',:'s83_capital_account',0,1000,'EGP',null,current_date);

-- Even an OWNER may prepare, but can never approve their own proposal.
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,1,current_date,'s83-self-payment-proposal')$$,
  :'s83_obligation', :'s83_cash')) as s83_self_proposal \gset
select 1/case when s83_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,'s83-self-payment-approval')$$,
  :'s83_self_proposal')) like '%maker/checker%'
  then 1 else 0 end as s83_payment_self_approval_rejected;

-- MEMBER 0009 (kept non-owner by suite 78) prepares; a different OWNER
-- revalidates cash/payable and posts. Earlier suites intentionally promote
-- 0003 to OWNER, so it cannot prove this authorization boundary here.
select s83_run('00000000-0000-4000-8000-000000000009', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,400,current_date,'s83-payment-proposal-001')$$,
  :'s83_obligation', :'s83_cash')) as s83_proposal1 \gset
select 1/case when s83_catch('00000000-0000-4000-8000-000000000009', format(
  $$select public.approve_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,'s83-member-payment-approval')$$,
  :'s83_proposal1')) like '%organization owner required%'
  then 1 else 0 end as s83_payment_member_cannot_approve;
select 1/case when s83_run('00000000-0000-4000-8000-000000000009', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,400,current_date,'s83-payment-proposal-001')$$,
  :'s83_obligation', :'s83_cash'))=:'s83_proposal1' then 1 else 0 end as s83_payment_proposal_replay_safe;
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,'s83-payment-001')$$,
  :'s83_proposal1')) as s83_payment1 \gset
select 1/case when s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,'s83-payment-001')$$,
  :'s83_proposal1'))=:'s83_payment1' then 1 else 0 end as s83_payment_approval_replay_safe;
select 1/case when exists (
  select 1 from public.cost_payment_proposals p join public.project_payments pay
    on pay.payment_proposal_id=p.id
  where p.id=:'s83_proposal1' and p.status='POSTED'
    and p.prepared_by='00000000-0000-4000-8000-000000000009'
    and p.approved_by='00000000-0000-4000-8000-000000000001'
    and p.prepared_by<>p.approved_by and pay.id=:'s83_payment1'
) then 1 else 0 end as s83_payment_maker_checker_persisted;

select 1/case when (select payment_state='PARTIALLY_PAID' and paid_minor_units='400' and outstanding_minor_units='600'
  from public.supplier_invoices_read where id=:'s83_invoice') then 1 else 0 end as s83_partial_payment_derived;

select 1/case when s83_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,601,current_date,'s83-payment-over')$$,
  :'s83_obligation', :'s83_cash')) like '%exceeds remaining payable%'
  then 1 else 0 end as s83_overpayment_rejected;

select s83_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.prepare_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,%L,600,current_date,'s83-payment-proposal-002')$$,
  :'s83_obligation', :'s83_cash')) as s83_proposal2 \gset
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_cost_payment(
    '10000000-0000-4000-8000-000000000001',%L,'s83-payment-002')$$,
  :'s83_proposal2')) as s83_payment2 \gset
select 1/case when (select payment_state='FULLY_PAID' and paid_minor_units='1000' and outstanding_minor_units='0'
  from public.supplier_invoices_read where id=:'s83_invoice') then 1 else 0 end as s83_fully_paid_derived;
select 1/case when (select balance_minor_units='0' from public.project_cash_position_read
  where cash_account_id=:'s83_cash') then 1 else 0 end as s83_cash_never_negative;

-- Existing bank import and exact reconciliation link the same shared payments.
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.import_bank_statement_lines(
    '10000000-0000-4000-8000-000000000001',%L,
    ARRAY[current_date,current_date]::date[],ARRAY['-400','-600']::text[],
    ARRAY['EGP','EGP']::text[],ARRAY['دفعة فاتورة R4-1','دفعة فاتورة R4-2']::text[],
    ARRAY['R4-BANK-1','R4-BANK-2']::text[],'s83-bank-import')$$,
  :'s83_cash')) as s83_import \gset
select id as s83_line1 from public.bank_statement_lines where import_id=:'s83_import' and amount_minor_units=-400 \gset
select id as s83_line2 from public.bank_statement_lines where import_id=:'s83_import' and amount_minor_units=-600 \gset
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s83-reconcile-1')$$,
  :'s83_payment1', :'s83_line1')) as s83_match1;
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s83-reconcile-2')$$,
  :'s83_payment2', :'s83_line2')) as s83_match2;
select 1/case when (select reconciliation_state='RECONCILED' and reconciled_minor_units='1000'
  from public.supplier_invoices_read where id=:'s83_invoice') then 1 else 0 end as s83_shared_bank_reconciliation_visible;

-- Portfolio reassignment is management-only and cannot rewrite Project-owned
-- Procurement/Finance facts.
create temporary table s83_financial_snapshot as
select (select to_jsonb(i)::text from public.supplier_invoices i where i.id=:'s83_invoice') as invoice_row,
       (select to_jsonb(o)::text from public.cost_obligations o where o.id=:'s83_obligation') as obligation_row,
       (select jsonb_agg(to_jsonb(p) order by p.id)::text from public.project_payments p where p.obligation_id=:'s83_obligation') as payment_rows;
select s83_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_portfolio(
    '10000000-0000-4000-8000-000000000001','محفظة اختبار R4','اختبار عدم إعادة كتابة الحقائق',null,'s83-portfolio-create')$$
) as s83_portfolio \gset
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_investment_portfolio(
    '10000000-0000-4000-8000-000000000001',%L,'DRAFT','ACTIVE','تفعيل للاختبار','s83-portfolio-activate')$$,
  :'s83_portfolio')) as s83_portfolio_active;
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_project_to_portfolio(
    '10000000-0000-4000-8000-000000000001',%L,%L,'s83-portfolio-assign')$$,
  :'s83_portfolio', :'s83_project')) as s83_assignment;
select s83_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_portfolio(
    '10000000-0000-4000-8000-000000000001','محفظة اختبار R4 الثانية','هدف إداري ثان',null,'s83-portfolio2-create')$$
) as s83_portfolio2 \gset
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_investment_portfolio(
    '10000000-0000-4000-8000-000000000001',%L,'DRAFT','ACTIVE','تفعيل المحفظة الثانية','s83-portfolio2-activate')$$,
  :'s83_portfolio2')) as s83_portfolio2_active;
select s83_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.move_project_to_portfolio(
    '10000000-0000-4000-8000-000000000001',%L,%L,'إعادة تجميع إداري','s83-portfolio-move')$$,
  :'s83_project', :'s83_portfolio2')) as s83_moved;
select 1/case when exists (
  select 1 from s83_financial_snapshot s
  where s.invoice_row=(select to_jsonb(i)::text from public.supplier_invoices i where i.id=:'s83_invoice')
    and s.obligation_row=(select to_jsonb(o)::text from public.cost_obligations o where o.id=:'s83_obligation')
    and s.payment_rows=(select jsonb_agg(to_jsonb(p) order by p.id)::text from public.project_payments p where p.obligation_id=:'s83_obligation')
) then 1 else 0 end as s83_portfolio_assignment_does_not_mutate_financial_truth;

-- Structural and RLS proof: no browser writes and all financial provenance is
-- project/tenant composite-keyed.
select 1/case when s83_catch('00000000-0000-4000-8000-000000000003',
  $$insert into public.supplier_invoices(organization_id,project_id,purchase_order_id,supplier_id,party_id,invoice_reference,invoice_date,currency,cost_treatment,evidence_reference,recorded_by,idempotency_key,request_hash)
    select organization_id,project_id,purchase_order_id,supplier_id,party_id,'DIRECT',current_date,currency,'EXPENSE','direct denied','00000000-0000-4000-8000-000000000003','s83-direct-denied',repeat('a',64)
    from public.supplier_invoices limit 1$$) <> 'NO_EXCEPTION'
  then 1 else 0 end as s83_direct_invoice_write_denied;

select 1/case when not exists (
  select 1 from information_schema.tables
  where table_schema='public' and table_name in ('procurement_payables_v2','procurement_payments','procurement_ledger','supplier_finance_ledger')
) then 1 else 0 end as s83_no_parallel_finance_tables;
