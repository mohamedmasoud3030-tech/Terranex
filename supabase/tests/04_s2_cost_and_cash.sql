-- GF-004 / S2 — Cost & Cash behavioral gate.
-- Runs after the S1 suite on the same database: builds on org A's funded
-- project (مشروع النخيل) and proves attribution, balanced immutable posting,
-- authorization boundary, payments, bank import, reconciliation, reversal,
-- tenant/project isolation, and exact derived balances.
-- Real concurrent-session checks run separately in 05_s2_concurrency.sh.

-- ---------------------------------------------------------------------------
-- Helpers (authenticated-role wrappers + owner-context assertion helpers)
-- ---------------------------------------------------------------------------
create or replace function s2_expect_raise(p_user uuid, p_sql text, p_sqlstate text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate = p_sqlstate;
end $$;

create or replace function s2_expect_ok(p_user uuid, p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return true;
exception when others then
  reset role;
  raise notice 's2_expect_ok failed: %', sqlerrm;
  return false;
end $$;

create or replace function s2_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
end $$;

create or replace function s2_owner_expect_raise(p_sql text, p_sqlstate text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate = p_sqlstate;
end $$;

-- Test helper exercises the real two-step Finance workflow while preserving
-- the original S2 assertions around payment posting and retry keys.
create or replace function s2_payment_workflow(
  p_organization_id uuid, p_obligation_id uuid, p_cash_account_id uuid,
  p_amount_minor_units bigint, p_payment_date date, p_idempotency_key text
) returns uuid language plpgsql as $$
declare
  v_approver uuid := auth.uid();
  v_proposal uuid;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
  v_proposal := public.prepare_cost_payment(
    p_organization_id, p_obligation_id, p_cash_account_id,
    p_amount_minor_units, p_payment_date, 'proposal-' || p_idempotency_key);
  perform set_config('request.jwt.claim.sub', v_approver::text, true);
  return public.approve_cost_payment(p_organization_id, v_proposal, p_idempotency_key);
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures: a MEMBER in org A, a supplier party, cash accounts
-- ---------------------------------------------------------------------------
insert into auth.users values ('00000000-0000-4000-8000-000000000003');
insert into public.memberships(organization_id,user_id,role) values
  ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','MEMBER');

select s2_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مورد أول','ORGANIZATION')$$);
select id as s2_supplier_1 from public.parties where legal_name='مورد أول' \gset
select s2_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مورد ثانٍ','ORGANIZATION')$$);
select id as s2_supplier_2 from public.parties where legal_name='مورد ثانٍ' \gset
select s2_run('00000000-0000-4000-8000-000000000002',
  $$select public.create_party('20000000-0000-4000-8000-000000000002','مورد منظمة باء','ORGANIZATION')$$);
select id as s2_supplier_b from public.parties where legal_name='مورد منظمة باء' \gset

select id as s2_project from public.investment_projects where name='مشروع النخيل' \gset
select id as s2_project2 from public.investment_projects where name='مشروع ثانٍ' \gset
select id as s2_contrib_a1 from public.contributions where idempotency_key='contrib-main-a1' \gset
select id as s2_contrib_a2_1 from public.contributions where idempotency_key='contrib-main-a2-1' \gset

-- Any active member (even MEMBER) may create a cash account.
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب بنك المشروع','EGP')$$, :'s2_project'));
select id as s2_account_a from public.project_cash_accounts where name='حساب بنك المشروع' \gset
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب مشروع ثانٍ','EGP')$$, :'s2_project2'));
select id as s2_account_b from public.project_cash_accounts where name='حساب مشروع ثانٍ' \gset
-- A second account on the main project for wrong-account reconciliation tests.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب بنك آخر','EGP')$$, :'s2_project'));
select id as s2_account_c from public.project_cash_accounts where name='حساب بنك آخر' \gset

select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب بعملة أخرى','USD')$$,
  :'s2_project'), 'P0001') then 1 else 0 end as s2_account_currency_must_match_project;

-- ---------------------------------------------------------------------------
-- A. Contribution -> cash attribution: exact balanced posting
-- ---------------------------------------------------------------------------
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-a1-0001')$$,
  :'s2_project', :'s2_contrib_a1', :'s2_account_a'));
select id as s2_attach_batch from public.journal_batches
where source_type='CONTRIBUTION_CASH_ATTRIBUTION' and source_id=:'s2_contrib_a1' \gset

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s2_attach_batch'
    and ((sa.role='BANK_CASH' and jl.debit_minor_units=600000 and jl.credit_minor_units=0 and jl.cash_account_id=:'s2_account_a')
      or (sa.role='CONTRIBUTED_CAPITAL' and jl.credit_minor_units=600000 and jl.debit_minor_units=0))
)=2 then 1 else 0 end as s2_attribution_posts_exact_cash_capital;

select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-a1-0001')$$,
  :'s2_project', :'s2_contrib_a1', :'s2_account_a')) then 1 else 0 end as s2_attribution_retry_same_payload_ok;
select 1/case when (select count(*) from public.journal_batches
  where source_type='CONTRIBUTION_CASH_ATTRIBUTION' and source_id=:'s2_contrib_a1')=1
  then 1 else 0 end as s2_attribution_retry_single_effect;

-- Same key + different payload -> reject.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-a1-0001')$$,
  :'s2_project', :'s2_contrib_a2_1', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_attribution_payload_mismatch_rejected;

-- Different key + already-posted contribution -> reject.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-a1-0002')$$,
  :'s2_project', :'s2_contrib_a1', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_attribution_twice_rejected;

-- MEMBER cannot post a contribution to cash (OWNER boundary).
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-member-01')$$,
  :'s2_project', :'s2_contrib_a2_1', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_attribution_member_denied;

select 1/case when (select balance_minor_units from public.project_cash_position_read
  where cash_account_id=:'s2_account_a')='600000' then 1 else 0 end as s2_cash_balance_after_attribution;

-- ---------------------------------------------------------------------------
-- B. Obligations: draft (member), authorize (OWNER), exact balanced postings
-- ---------------------------------------------------------------------------
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'أعمال حفر وتجهيز الموقع',400000,'EGP',date '2026-08-15','EXPENSE','s2-obl-exp-0001')$$,
  :'s2_project', :'s2_supplier_1'));
select id as s2_obl_expense from public.cost_obligations where idempotency_key='s2-obl-exp-0001' \gset

select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'مرحلة تطوير الواجهة',600000,'EGP',date '2026-08-20','CAPITALIZABLE_WIP','s2-obl-wip-0001')$$,
  :'s2_project', :'s2_supplier_1'));
select id as s2_obl_wip from public.cost_obligations where idempotency_key='s2-obl-wip-0001' \gset

select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'التزام قابل للحذف',10000,'EGP',date '2026-08-21','EXPENSE','s2-obl-del-0001')$$,
  :'s2_project', :'s2_supplier_1'));
select id as s2_obl_delete_me from public.cost_obligations where idempotency_key='s2-obl-del-0001' \gset

-- Draft retry and payload binding.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'أعمال حفر وتجهيز الموقع',400000,'EGP',date '2026-08-15','EXPENSE','s2-obl-exp-0001')$$,
  :'s2_project', :'s2_supplier_1')) then 1 else 0 end as s2_obligation_retry_same_payload_ok;
select 1/case when (select count(*) from public.cost_obligations where idempotency_key='s2-obl-exp-0001')=1
  then 1 else 0 end as s2_obligation_retry_single_effect;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'مبلغ مختلف',399999,'EGP',date '2026-08-15','EXPENSE','s2-obl-exp-0001')$$,
  :'s2_project', :'s2_supplier_1'), 'P0001') then 1 else 0 end as s2_obligation_payload_mismatch_rejected;

-- Cross-tenant party reference rejected.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'طرف من منظمة أخرى',5000,'EGP',date '2026-08-22','EXPENSE','s2-obl-cross-tenant')$$,
  :'s2_project', :'s2_supplier_b'), 'P0001') then 1 else 0 end as s2_cross_tenant_party_rejected;

-- MEMBER cannot authorize; OWNER can.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-member-0001')$$,
  :'s2_obl_expense'), 'P0001') then 1 else 0 end as s2_authorize_member_denied;

select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-exp-0001')$$, :'s2_obl_expense'));
select id as s2_exp_batch from public.journal_batches
where source_type='COST_OBLIGATION' and source_id=:'s2_obl_expense' \gset

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s2_exp_batch'
    and ((sa.role='PROJECT_EXPENSE' and jl.debit_minor_units=400000 and jl.credit_minor_units=0)
      or (sa.role='SUPPLIER_PAYABLE' and jl.credit_minor_units=400000 and jl.debit_minor_units=0))
)=2 then 1 else 0 end as s2_expense_posts_exact_debit_credit;

select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-wip-0001')$$, :'s2_obl_wip'));
select id as s2_wip_batch from public.journal_batches
where source_type='COST_OBLIGATION' and source_id=:'s2_obl_wip' \gset

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s2_wip_batch'
    and ((sa.role='DEVELOPMENT_WIP' and jl.debit_minor_units=600000 and jl.credit_minor_units=0)
      or (sa.role='SUPPLIER_PAYABLE' and jl.credit_minor_units=600000 and jl.debit_minor_units=0))
)=2 then 1 else 0 end as s2_wip_posts_exact_debit_credit;

-- Replaying the authorize command returns the same batch with one effect.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-exp-0001')$$,
  :'s2_obl_expense')) then 1 else 0 end as s2_authorize_retry_ok;
select 1/case when (select count(*) from public.journal_batches
  where source_type='COST_OBLIGATION' and source_id=:'s2_obl_expense')=1
  then 1 else 0 end as s2_authorize_retry_single_effect;
-- A second authorization with a different key is rejected.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-exp-0002')$$,
  :'s2_obl_expense'), 'P0001') then 1 else 0 end as s2_authorize_twice_rejected;

-- Draft edits and deletes; authorized records are immutable.
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.update_cost_obligation_draft('10000000-0000-4000-8000-000000000001',%L,%L,'أعمال حفر وتجهيز الموقع (محدث)',400000,'EGP',date '2026-08-15','EXPENSE')$$,
  :'s2_obl_delete_me', :'s2_supplier_1'));
select 1/case when s2_owner_expect_raise(format(
  $$update public.cost_obligations set description='محاولة تعديل' where id=%L::uuid$$, :'s2_obl_expense'), 'P0001')
  then 1 else 0 end as s2_authorized_obligation_immutable;
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.delete_cost_obligation_draft('10000000-0000-4000-8000-000000000001',%L)$$, :'s2_obl_delete_me'));
select 1/case when not exists (select 1 from public.cost_obligations where id=:'s2_obl_delete_me')
  then 1 else 0 end as s2_draft_deleted;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.delete_cost_obligation_draft('10000000-0000-4000-8000-000000000001',%L)$$, :'s2_obl_expense'), 'P0001')
  then 1 else 0 end as s2_authorized_obligation_not_deletable;

-- ---------------------------------------------------------------------------
-- C. Database-enforced balance and immutability of posted batches
-- ---------------------------------------------------------------------------
create or replace function s2_try_unbalanced_batch() returns text language plpgsql as $$
declare
  v_batch uuid;
  v_exp uuid; v_pay uuid; v_project uuid;
begin
  select id into v_exp from public.semantic_accounts where role='PROJECT_EXPENSE';
  select id into v_pay from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_project from public.investment_projects where name='مشروع النخيل';
  begin
    insert into public.journal_batches(organization_id, project_id, source_type, source_id,
      transaction_date, idempotency_key, request_hash, posted_by)
    values ('10000000-0000-4000-8000-000000000001', v_project,
      'COST_OBLIGATION', gen_random_uuid(), date '2026-08-11',
      's2-unbalanced-0001', repeat('a', 64), '00000000-0000-4000-8000-000000000001')
    returning id into v_batch;
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date)
    values
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project, v_exp,
       100, 0, 'EGP', date '2026-08-11'),
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project, v_pay,
       0, 200, 'EGP', date '2026-08-11');
    return 'NOT-REJECTED';
  exception when others then
    if sqlerrm like '%unbalanced%' then
      return 'REJECTED';
    end if;
    return 'WRONG-ERROR: ' || sqlerrm;
  end;
end $$;
select 1/case when s2_try_unbalanced_batch()='REJECTED' then 1 else 0 end as s2_unbalanced_batch_rejected_by_db;

-- No partial batch can exist: a batch whose first line is inserted alone is rejected.
create or replace function s2_try_single_line_batch() returns text language plpgsql as $$
declare
  v_batch uuid; v_exp uuid; v_project uuid;
begin
  select id into v_exp from public.semantic_accounts where role='PROJECT_EXPENSE';
  select id into v_project from public.investment_projects where name='مشروع النخيل';
  begin
    insert into public.journal_batches(organization_id, project_id, source_type, source_id,
      transaction_date, idempotency_key, request_hash, posted_by)
    values ('10000000-0000-4000-8000-000000000001', v_project,
      'COST_OBLIGATION', gen_random_uuid(), date '2026-08-11',
      's2-single-line-0001', repeat('b', 64), '00000000-0000-4000-8000-000000000001')
    returning id into v_batch;
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date)
    values (v_batch, '10000000-0000-4000-8000-000000000001', v_project, v_exp,
      100, 0, 'EGP', date '2026-08-11');
    return 'NOT-REJECTED';
  exception when others then
    if sqlerrm like '%unbalanced%' then
      return 'REJECTED';
    end if;
    return 'WRONG-ERROR: ' || sqlerrm;
  end;
end $$;
select 1/case when s2_try_single_line_batch()='REJECTED' then 1 else 0 end as s2_partial_batch_rejected_by_db;

-- Mixed-currency batch rejected.
create or replace function s2_try_mixed_currency_batch() returns text language plpgsql as $$
declare
  v_batch uuid; v_exp uuid; v_pay uuid; v_project uuid;
begin
  select id into v_exp from public.semantic_accounts where role='PROJECT_EXPENSE';
  select id into v_pay from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_project from public.investment_projects where name='مشروع النخيل';
  begin
    insert into public.journal_batches(organization_id, project_id, source_type, source_id,
      transaction_date, idempotency_key, request_hash, posted_by)
    values ('10000000-0000-4000-8000-000000000001', v_project,
      'COST_OBLIGATION', gen_random_uuid(), date '2026-08-11',
      's2-mixed-cur-0001', repeat('c', 64), '00000000-0000-4000-8000-000000000001')
    returning id into v_batch;
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date)
    values
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project, v_exp,
       100, 0, 'EGP', date '2026-08-11'),
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project, v_pay,
       0, 100, 'USD', date '2026-08-11');
    return 'NOT-REJECTED';
  exception when others then
    if sqlerrm like '%mixes currencies%' then
      return 'REJECTED';
    end if;
    return 'WRONG-ERROR: ' || sqlerrm;
  end;
end $$;
select 1/case when s2_try_mixed_currency_batch()='REJECTED' then 1 else 0 end as s2_mixed_currency_batch_rejected_by_db;

-- Posted batches and lines are immutable even for privileged writers.
select 1/case when s2_owner_expect_raise(format(
  $$update public.journal_batches set transaction_date=date '2026-01-01' where id=%L::uuid$$, :'s2_exp_batch'), 'P0001')
  then 1 else 0 end as s2_batch_immutable;
select 1/case when s2_owner_expect_raise(format(
  $$delete from public.journal_batches where id=%L::uuid$$, :'s2_exp_batch'), 'P0001')
  then 1 else 0 end as s2_batch_not_deletable;
select 1/case when s2_owner_expect_raise(format(
  $$update public.journal_lines set debit_minor_units=1 where batch_id=%L::uuid$$, :'s2_exp_batch'), 'P0001')
  then 1 else 0 end as s2_lines_immutable;

-- Privileged same-tenant cross-project line references are rejected by the
-- database scope guards (obligation of project A into a batch of project A2).
create or replace function s2_try_cross_project_line() returns text language plpgsql as $$
declare
  v_batch uuid; v_exp uuid; v_pay uuid;
  v_obl_a uuid; v_project2 uuid;
begin
  select id into v_exp from public.semantic_accounts where role='PROJECT_EXPENSE';
  select id into v_pay from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_obl_a from public.cost_obligations where idempotency_key='s2-obl-exp-0001';
  select id into v_project2 from public.investment_projects where name='مشروع ثانٍ';
  begin
    insert into public.journal_batches(organization_id, project_id, source_type, source_id,
      transaction_date, idempotency_key, request_hash, posted_by)
    values ('10000000-0000-4000-8000-000000000001', v_project2,
      'COST_OBLIGATION', gen_random_uuid(), date '2026-08-11',
      's2-cross-proj-0001', repeat('d', 64), '00000000-0000-4000-8000-000000000001')
    returning id into v_batch;
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, obligation_id, transaction_date)
    values
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project2, v_exp,
       100, 0, 'EGP', v_obl_a, date '2026-08-11'),
      (v_batch, '10000000-0000-4000-8000-000000000001', v_project2, v_pay,
       0, 100, 'EGP', v_obl_a, date '2026-08-11');
    return 'NOT-REJECTED';
  exception when others then
    if sqlerrm like '%obligation must belong%' then
      return 'REJECTED';
    end if;
    return 'WRONG-ERROR: ' || sqlerrm;
  end;
end $$;
select 1/case when s2_try_cross_project_line()='REJECTED' then 1 else 0 end as s2_cross_project_line_rejected_by_db;

-- ---------------------------------------------------------------------------
-- D. Payments: partial, exact outstanding, overpayment rejection, idempotency
-- ---------------------------------------------------------------------------
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.prepare_cost_payment('10000000-0000-4000-8000-000000000001',%L,%L,1,date '2026-08-25','s2-member-payment-proposal')$$,
  :'s2_obl_expense', :'s2_account_a'));
select id as s2_member_payment_proposal from public.cost_payment_proposals
  where idempotency_key='s2-member-payment-proposal' \gset
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.approve_cost_payment('10000000-0000-4000-8000-000000000001',%L,'s2-member-payment-approval')$$,
  :'s2_member_payment_proposal'), 'P0001') then 1 else 0 end as s2_payment_member_cannot_approve;

select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,150000,date '2026-08-25','s2-pay-1-000001')$$,
  :'s2_obl_expense', :'s2_account_a'));
select id as s2_payment_1 from public.project_payments where idempotency_key='s2-pay-1-000001' \gset

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=(select b.id from public.journal_batches b where b.source_type='PAYMENT' and b.source_id=:'s2_payment_1')
    and ((sa.role='SUPPLIER_PAYABLE' and jl.debit_minor_units=150000)
      or (sa.role='BANK_CASH' and jl.credit_minor_units=150000 and jl.cash_account_id=:'s2_account_a'))
)=2 then 1 else 0 end as s2_payment_posts_exact_payable_cash;

select 1/case when (select outstanding_minor_units from public.cost_obligation_position_read
  where obligation_id=:'s2_obl_expense')='250000' then 1 else 0 end as s2_outstanding_after_partial;

select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,300000,date '2026-08-25','s2-pay-over-00001')$$,
  :'s2_obl_expense', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_overpayment_rejected;

-- Retry: same key + same payload returns the original payment.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,150000,date '2026-08-25','s2-pay-1-000001')$$,
  :'s2_obl_expense', :'s2_account_a')) then 1 else 0 end as s2_payment_retry_ok;
select 1/case when (select count(*) from public.project_payments where idempotency_key='s2-pay-1-000001')=1
  then 1 else 0 end as s2_payment_retry_single_effect;
-- Same key + different payload -> reject.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,149999,date '2026-08-25','s2-pay-1-000001')$$,
  :'s2_obl_expense', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_payment_payload_mismatch_rejected;

-- Cross-project cash account rejected.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,1000,date '2026-08-25','s2-pay-cross-proj-01')$$,
  :'s2_obl_expense', :'s2_account_b'), 'P0001') then 1 else 0 end as s2_payment_cross_project_rejected;

-- Pay the remainder in full.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,250000,date '2026-08-26','s2-pay-2-000001')$$,
  :'s2_obl_expense', :'s2_account_a'));
select id as s2_payment_2 from public.project_payments where idempotency_key='s2-pay-2-000001' \gset

select 1/case when (select outstanding_minor_units from public.cost_obligation_position_read
  where obligation_id=:'s2_obl_expense')='0' then 1 else 0 end as s2_outstanding_zero_after_full;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,1,date '2026-08-27','s2-pay-after-full-01')$$,
  :'s2_obl_expense', :'s2_account_a'), 'P0001') then 1 else 0 end as s2_payment_after_full_rejected;

select 1/case when (select balance_minor_units from public.project_cash_position_read
  where cash_account_id=:'s2_account_a')='200000' then 1 else 0 end as s2_cash_balance_after_payments;

-- A fresh obligation reserved for the real concurrency suite.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'التزام سباق الدفعات',150000,'EGP',date '2026-09-01','EXPENSE','s2-obl-race-0001')$$,
  :'s2_project', :'s2_supplier_1'));
select id as s2_obl_race from public.cost_obligations where idempotency_key='s2-obl-race-0001' \gset
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-race-0001')$$, :'s2_obl_race'));

-- Reconciliation-race fixture: an active payment with a matching statement
-- line that stays unreconciled until 05_s2_concurrency.sh races on it.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s2_payment_workflow('10000000-0000-4000-8000-000000000001',%L,%L,50000,date '2026-09-02','s2-pay-race-01')$$,
  :'s2_obl_race', :'s2_account_a'));
select id as s2_pay_race from public.project_payments where idempotency_key='s2-pay-race-01' \gset
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-09-02'],
    array['-50000'],
    array['EGP'],
    array['دفعة سباق التسوية'],
    array['TXN-RACE-RECON'],
    's2-import-recon-race')$$, :'s2_account_a'));
select id as s2_line_recon_race from public.bank_statement_lines
where provider_reference='TXN-RACE-RECON' \gset

-- ---------------------------------------------------------------------------
-- E. Bank statement import: deterministic fingerprints, no economics
-- ---------------------------------------------------------------------------
-- A bank statement import by itself creates NO journal economics.
select count(*) as s2_batches_before_import from public.journal_batches \gset
select count(*) as s2_lines_before_import from public.journal_lines \gset
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25', date '2026-08-26'],
    array['-150000','-250000'],
    array['EGP','EGP'],
    array['دفعة للمورد الأول','الدفعة الثانية للمورد'],
    array['TXN-1001','TXN-1002'],
    's2-import-000001')$$, :'s2_account_a'));
select id as s2_import_1 from public.bank_statement_imports where idempotency_key='s2-import-000001' \gset
select id as s2_line_1 from public.bank_statement_lines where import_id=:'s2_import_1' and provider_reference='TXN-1001' \gset
select id as s2_line_2 from public.bank_statement_lines where import_id=:'s2_import_1' and provider_reference='TXN-1002' \gset

select 1/case when (select count(*) from public.journal_batches)=:'s2_batches_before_import'
  then 1 else 0 end as s2_import_creates_no_journal_batches;
select 1/case when (select count(*) from public.journal_lines)=:'s2_lines_before_import'
  then 1 else 0 end as s2_import_creates_no_journal_lines;

-- Retry: same key + same payload returns the same import.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25', date '2026-08-26'],
    array['-150000','-250000'],
    array['EGP','EGP'],
    array['دفعة للمورد الأول','الدفعة الثانية للمورد'],
    array['TXN-1001','TXN-1002'],
    's2-import-000001')$$, :'s2_account_a')) then 1 else 0 end as s2_import_retry_same_payload_ok;
select 1/case when (select count(*) from public.bank_statement_lines where import_id=:'s2_import_1')=2
  then 1 else 0 end as s2_import_retry_single_effect;
-- Same key + different payload -> reject.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['-1'],
    array['EGP'],
    array['مختلف'],
    array['TXN-9999'],
    's2-import-000001')$$, :'s2_account_a'), 'P0001') then 1 else 0 end as s2_import_payload_mismatch_rejected;
-- Same fingerprint with a different key -> duplicate protection.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['-150000'],
    array['EGP'],
    array['دفعة للمورد الأول'],
    array['TXN-1001'],
    's2-import-dup-0001')$$, :'s2_account_a'), 'P0001') then 1 else 0 end as s2_duplicate_fingerprint_rejected;
-- Invalid rows rejected before any line is written.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['1.5.3'],
    array['EGP'],
    array['مبلغ خاطئ'],
    array[null],
    's2-import-bad-0001')$$, :'s2_account_a'), 'P0001') then 1 else 0 end as s2_import_invalid_amount_rejected;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['-50000'],
    array['USD'],
    array['عملة خاطئة'],
    array[null],
    's2-import-cur-0001')$$, :'s2_account_a'), 'P0001') then 1 else 0 end as s2_import_wrong_currency_rejected;
select 1/case when (select count(*) from public.bank_statement_lines where import_id=:'s2_import_1')=2
  then 1 else 0 end as s2_import_bad_rows_wrote_nothing;

-- Lines on the second account for wrong-account reconciliation tests.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['-150000'],
    array['EGP'],
    array['دفعة على حساب آخر'],
    array['TXN-ACCT-C'],
    's2-import-acctc-01')$$, :'s2_account_c'));
select id as s2_line_acct_c from public.bank_statement_lines
where import_id=(select id from public.bank_statement_imports where idempotency_key='s2-import-acctc-01') \gset
-- A wrong-amount line on the main account.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.import_bank_statement_lines('10000000-0000-4000-8000-000000000001',%L,
    array[date '2026-08-25'],
    array['-149999'],
    array['EGP'],
    array['مبلغ غير مطابق'],
    array['TXN-AMT-C'],
    's2-import-amtc-01')$$, :'s2_account_a'));
select id as s2_line_amt_c from public.bank_statement_lines
where import_id=(select id from public.bank_statement_imports where idempotency_key='s2-import-amtc-01') \gset

-- ---------------------------------------------------------------------------
-- F. Reconciliation: exact one-to-one, no economics, hard failures
-- ---------------------------------------------------------------------------
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-member-01')$$,
  :'s2_payment_1', :'s2_line_1'), 'P0001') then 1 else 0 end as s2_reconcile_member_denied;

select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-1-000001')$$,
  :'s2_payment_1', :'s2_line_1'));
select id as s2_match_1 from public.reconciliation_matches where idempotency_key='s2-recon-1-000001' \gset

select 1/case when (select count(*) from public.journal_batches)=:'s2_batches_before_import'
  then 1 else 0 end as s2_reconcile_creates_no_journal;
select 1/case when (select is_reconciled from public.bank_statement_line_status_read where line_id=:'s2_line_1')
  then 1 else 0 end as s2_line_reconciled_status;

-- Wrong account / wrong amount / double reconciliation all fail.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-acct-0001')$$,
  :'s2_payment_1', :'s2_line_acct_c'), 'P0001') then 1 else 0 end as s2_reconcile_wrong_account_fails;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-amt-00001')$$,
  :'s2_payment_1', :'s2_line_amt_c'), 'P0001') then 1 else 0 end as s2_reconcile_wrong_amount_fails;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-line-dup-01')$$,
  :'s2_payment_2', :'s2_line_1'), 'P0001') then 1 else 0 end as s2_reconcile_line_twice_fails;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-pay-dup-01')$$,
  :'s2_payment_1', :'s2_line_2'), 'P0001') then 1 else 0 end as s2_reconcile_payment_twice_fails;

-- Retry: same key + same payload returns the same match.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-1-000001')$$,
  :'s2_payment_1', :'s2_line_1')) then 1 else 0 end as s2_reconcile_retry_ok;
select 1/case when (select count(*) from public.reconciliation_matches where idempotency_key='s2-recon-1-000001')=1
  then 1 else 0 end as s2_reconcile_retry_single_effect;

-- Reconcile the second payment too (needed for the reversal-order tests).
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reconcile_payment('10000000-0000-4000-8000-000000000001',%L,%L,'s2-recon-2-000001')$$,
  :'s2_payment_2', :'s2_line_2'));

-- ---------------------------------------------------------------------------
-- G. Correction: linked reversal with dependency-order rules
-- ---------------------------------------------------------------------------
-- Payment with an active reconciliation cannot be reversed yet.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select id from public.journal_batches where source_type='PAYMENT' and source_id=%L::uuid),
    'خطأ في الدفعة','s2-rev-pay-000001')$$, :'s2_payment_1'), 'P0001')
  then 1 else 0 end as s2_reverse_payment_blocked_by_reconciliation;

-- Void the reconciliation (controlled correction), then reversal works.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.void_reconciliation('10000000-0000-4000-8000-000000000001',%L,'إلغاء من قبل عضو','s2-void-member-01')$$,
  :'s2_match_1'), 'P0001') then 1 else 0 end as s2_void_member_denied;
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.void_reconciliation('10000000-0000-4000-8000-000000000001',%L,'مطابقة خاطئة يجب تصحيحها','s2-void-1-000001')$$,
  :'s2_match_1'));
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.void_reconciliation('10000000-0000-4000-8000-000000000001',%L,'مطابقة خاطئة يجب تصحيحها','s2-void-1-000001')$$,
  :'s2_match_1')) then 1 else 0 end as s2_void_retry_ok;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.void_reconciliation('10000000-0000-4000-8000-000000000001',%L,'محاولة إلغاء ثانية','s2-void-1-000002')$$,
  :'s2_match_1'), 'P0001') then 1 else 0 end as s2_void_twice_rejected;
select 1/case when (select is_reconciled from public.bank_statement_line_status_read where line_id=:'s2_line_1') = false
  then 1 else 0 end as s2_line_unreconciled_after_void;

-- Reversing a payment batch creates the exact inverse and preserves the original.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select id from public.journal_batches where source_type='PAYMENT' and source_id=%L::uuid),
    'دفعة مسجلة بالخطأ','s2-rev-pay-000001')$$, :'s2_payment_1'));
select id as s2_rev_pay_batch from public.journal_batches
where source_type='REVERSAL' and source_id=(select id from public.journal_batches
  where source_type='PAYMENT' and source_id=:'s2_payment_1') \gset

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=:'s2_rev_pay_batch'
    and ((sa.role='SUPPLIER_PAYABLE' and jl.credit_minor_units=150000 and jl.debit_minor_units=0)
      or (sa.role='BANK_CASH' and jl.debit_minor_units=150000 and jl.credit_minor_units=0))
)=2 then 1 else 0 end as s2_payment_reversal_exact_inverse;
select 1/case when (select count(*) from public.journal_lines
  where batch_id=(select id from public.journal_batches where source_type='PAYMENT' and source_id=:'s2_payment_1'))=2
  then 1 else 0 end as s2_original_payment_lines_untouched;
select 1/case when (select is_reversed from public.payment_status_read where payment_id=:'s2_payment_1')
  then 1 else 0 end as s2_payment_status_reversed;

-- Double reversal and reversal-of-reversal are rejected.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select id from public.journal_batches where source_type='PAYMENT' and source_id=%L::uuid),
    'محاولة عكس مكررة','s2-rev-pay-000002')$$, :'s2_payment_1'), 'P0001')
  then 1 else 0 end as s2_payment_double_reversal_rejected;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'عكس العكس','s2-rev-of-rev-0001')$$,
  :'s2_rev_pay_batch'), 'P0001') then 1 else 0 end as s2_reversal_of_reversal_rejected;

-- Reversal retry: same key returns the same reversal batch.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select id from public.journal_batches where source_type='PAYMENT' and source_id=%L::uuid),
    'دفعة مسجلة بالخطأ','s2-rev-pay-000001')$$, :'s2_payment_1')) then 1 else 0 end as s2_reversal_retry_ok;

-- The obligation still has an active payment (the second one): reversing the
-- obligation authorization is rejected until that payment is reversed too.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'إلغاء الالتزام','s2-rev-obl-000001')$$,
  :'s2_exp_batch'), 'P0001') then 1 else 0 end as s2_reverse_obligation_blocked_by_active_payment;

-- Void the second match, reverse the second payment, then reverse the obligation.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.void_reconciliation('10000000-0000-4000-8000-000000000001',%L,'تصحيح مسار العكس','s2-void-2-000001')$$,
  (select id from public.reconciliation_matches where payment_id=:'s2_payment_2')));
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select id from public.journal_batches where source_type='PAYMENT' and source_id=%L::uuid),
    'دفعة ثانية بالخطأ','s2-rev-pay2-00001')$$, :'s2_payment_2'));
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'الالتزام مسجل بالخطأ','s2-rev-obl-000001')$$,
  :'s2_exp_batch'));

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=(select id from public.journal_batches
    where source_type='REVERSAL' and source_id=:'s2_exp_batch')
    and ((sa.role='PROJECT_EXPENSE' and jl.credit_minor_units=400000 and jl.debit_minor_units=0)
      or (sa.role='SUPPLIER_PAYABLE' and jl.debit_minor_units=400000 and jl.credit_minor_units=0))
)=2 then 1 else 0 end as s2_obligation_reversal_exact_inverse;
select 1/case when (select is_reversed from public.cost_obligation_position_read
  where obligation_id=:'s2_obl_expense') then 1 else 0 end as s2_obligation_position_reversed;

-- Contribution attribution can be reversed and then reposted (linked reversal).
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'إسناد خاطئ','s2-rev-attach-0001')$$,
  :'s2_attach_batch'));
select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.batch_id=(select id from public.journal_batches
    where source_type='REVERSAL' and source_id=:'s2_attach_batch')
    and ((sa.role='BANK_CASH' and jl.credit_minor_units=600000 and jl.debit_minor_units=0)
      or (sa.role='CONTRIBUTED_CAPITAL' and jl.debit_minor_units=600000 and jl.credit_minor_units=0))
)=2 then 1 else 0 end as s2_attribution_reversal_exact_inverse;
-- Cash is exactly zero from the reversed chain plus the still-active race
-- payment (400000 out) that the concurrency suite owns.
select 1/case when (select balance_minor_units from public.project_cash_position_read
  where cash_account_id=:'s2_account_a')='-400000' then 1 else 0 end as s2_cash_after_full_reversal_chain;

-- After an explicit linked reversal the contribution may be posted again.
select s2_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.attach_contribution_cash('10000000-0000-4000-8000-000000000001',%L,%L,%L,'s2-attach-a1-0003')$$,
  :'s2_project', :'s2_contrib_a1', :'s2_account_a'));
select 1/case when (select balance_minor_units from public.project_cash_position_read
  where cash_account_id=:'s2_account_a')='200000' then 1 else 0 end as s2_contribution_repost_after_reversal;

-- ---------------------------------------------------------------------------
-- H. Tenant isolation and authorization boundary
-- ---------------------------------------------------------------------------
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_cost_obligation('10000000-0000-4000-8000-000000000001',%L,%L,'تسريب عبر منظمة باء',100,'EGP',date '2026-08-30','EXPENSE','s2-obl-orgb-0001')$$,
  :'s2_project', :'s2_supplier_1'), 'P0001') then 1 else 0 end as s2_cross_tenant_command_denied;

create or replace function s2_cross_tenant_obligation_read(p_user uuid, p_obligation uuid)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  return not exists (select 1 from public.cost_obligations where id = p_obligation);
end $$;
select 1/case when s2_cross_tenant_obligation_read('00000000-0000-4000-8000-000000000002',:'s2_obl_expense')
  then 1 else 0 end as s2_cross_tenant_obligation_read_denied;

select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000002', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-orgb-0001')$$,
  :'s2_obl_wip'), 'P0001') then 1 else 0 end as s2_cross_tenant_authorize_denied;

-- MEMBER in the SAME organization cannot authorize, pay, reconcile, void, or reverse.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'s2-auth-member-0002')$$,
  :'s2_obl_wip'), 'P0001') then 1 else 0 end as s2_member_cannot_authorize;
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'من عضو','s2-rev-member-0001')$$,
  :'s2_wip_batch'), 'P0001') then 1 else 0 end as s2_member_cannot_reverse;

-- Direct browser DML on material S2 tables remains denied.
do $$
begin
  execute 'set role authenticated';
  begin
    execute 'insert into public.cost_obligations(organization_id,project_id,party_id,description,amount_minor_units,currency,transaction_date,cost_treatment,prepared_by,idempotency_key,request_hash) values (''10000000-0000-4000-8000-000000000001'',''00000000-0000-4000-8000-000000000002'',''00000000-0000-4000-8000-000000000001'',''should fail'',1,''EGP'',date ''2026-08-30'',''EXPENSE'',''00000000-0000-4000-8000-000000000001'',''s2-direct-dml-0001'',repeat(''e'',64))';
    raise exception 'direct insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

-- ---------------------------------------------------------------------------
-- I. Exact transport and derived balances
-- ---------------------------------------------------------------------------
select 1/case when pg_typeof((select balance_minor_units from public.project_cash_position_read
  where cash_account_id=:'s2_account_a'))='text'::regtype then 1 else 0 end as s2_cash_position_transport_is_text;
select 1/case when pg_typeof((select outstanding_minor_units from public.cost_obligation_position_read
  where obligation_id=:'s2_obl_wip'))='text'::regtype then 1 else 0 end as s2_obligation_transport_is_text;

-- Exact project subledger reproduction from journal lines. Includes the race
-- obligation (authorized 1000000 expense, 400000 paid, not reversed):
-- cash     = debit-credit    = 200000  (600000 reposted attribution + reversals
--                                       - 400000 active race payment);
-- payable  = credit-debit    = 1200000 (wip 600000 + race 1000000 - 400000 paid);
-- expense  = debit-credit    = 1000000 (race obligation; expense chain reversed);
-- WIP      = debit-credit    = 600000  (never reversed).
select 1/case when (
  select coalesce(sum(debit_minor_units),0)-coalesce(sum(credit_minor_units),0)
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.project_id=:'s2_project' and sa.role='BANK_CASH')=200000
  then 1 else 0 end as s2_ledger_cash_exact;
select 1/case when (
  select coalesce(sum(credit_minor_units),0)-coalesce(sum(debit_minor_units),0)
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.project_id=:'s2_project' and sa.role='SUPPLIER_PAYABLE')=1200000
  then 1 else 0 end as s2_ledger_payable_exact;
select 1/case when (
  select coalesce(sum(debit_minor_units),0)-coalesce(sum(credit_minor_units),0)
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.project_id=:'s2_project' and sa.role='PROJECT_EXPENSE')=1000000
  then 1 else 0 end as s2_ledger_expense_exact;
select 1/case when (
  select coalesce(sum(debit_minor_units),0)-coalesce(sum(credit_minor_units),0)
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.project_id=:'s2_project' and sa.role='DEVELOPMENT_WIP')=600000
  then 1 else 0 end as s2_ledger_wip_exact;

-- The S2 workflow leaves a complete audit trail.
select 1/case when (
  select count(distinct event_type) from public.audit_events where event_type in
  ('CASH_ACCOUNT_CREATED','CONTRIBUTION_CASH_POSTED','OBLIGATION_DRAFTED',
   'OBLIGATION_AUTHORIZED','PAYMENT_POSTED','BANK_STATEMENT_IMPORTED',
   'RECONCILIATION_MATCHED','RECONCILIATION_VOIDED','JOURNAL_BATCH_REVERSED')
)=9 then 1 else 0 end as s2_workflow_audited;

select 'S2 costs and cash SQL PASS' as result;
