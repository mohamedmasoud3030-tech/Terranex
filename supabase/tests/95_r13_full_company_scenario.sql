-- R13 — executable integrated synthetic-company proof.
--
-- This is intentionally the final SQL gate. Gates 01–94 prove each production
-- command and race path in isolation; this scenario composes their persistent
-- authorized facts into one company, one management hierarchy and one exact
-- Project -> Portfolio -> Organization reconciliation. It does not invent R14
-- investor ownership/allocation/distribution policy.

create or replace function r13_assert(p_condition boolean,p_message text) returns void
language plpgsql as $$ begin if p_condition is not true then raise exception 'R13 ASSERTION FAILED: %',p_message; end if; end $$;

create or replace function r13_count_as(p_user uuid,p_sql text) returns bigint language plpgsql as $$
declare v bigint; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true); perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
exception when others then reset role; raise;
end $$;

-- The independent R5 gate has already produced an actual held property,
-- balanced rental recognition (120000 EGP), partial collection (70000), open
-- receivable (50000), and unique bank reconciliation. Promote that isolated
-- organization to the named integrated target company rather than fabricating
-- duplicate financial facts through direct table DML.
update public.organizations set name='المجموعة العربية المتحدة',reporting_currency='EGP'
where id='e5000000-0000-4000-8000-000000000001';
update public.organizations set name='المنظمة المعادية — R13'
where id='e5000000-0000-4000-8000-000000000002';

-- Two management portfolios.
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_portfolio('e5000000-0000-4000-8000-000000000001','محفظة التشغيل المتنوعة','إدارة مستقلة لمشروعات القطاعات الثلاثة',null,'r13-portfolio-main-001')$$);
select id as r13_portfolio from public.investment_portfolios where organization_id='e5000000-0000-4000-8000-000000000001' and idempotency_key='r13-portfolio-main-001' \gset
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_investment_portfolio('e5000000-0000-4000-8000-000000000001',%L,'DRAFT','ACTIVE','جاهزة للتشغيل المتكامل','r13-portfolio-main-active')$$,:'r13_portfolio'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_portfolio('e5000000-0000-4000-8000-000000000001','محفظة تاريخية','إثبات النقل التاريخي دون إعادة كتابة الحقائق',null,'r13-portfolio-history')$$);
select id as r13_history_portfolio from public.investment_portfolios where organization_id='e5000000-0000-4000-8000-000000000001' and idempotency_key='r13-portfolio-history' \gset
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_investment_portfolio('e5000000-0000-4000-8000-000000000001',%L,'DRAFT','ACTIVE','جاهزة لإثبات التاريخ','r13-portfolio-history-active')$$,:'r13_history_portfolio'));

-- One Agriculture and two independent Livestock projects in the SAME current
-- Portfolio. The R5 Real Estate project is the fourth sector project.
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('e5000000-0000-4000-8000-000000000001','مزرعة الوادي R13','R13-AG','دورة زراعية متكاملة','AGRICULTURE')$$);
select id as r13_ag from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-AG' \gset
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('e5000000-0000-4000-8000-000000000001','ماشية الشمال R13','R13-LV-A','مشروع ماشية مستقل أ','LIVESTOCK')$$);
select id as r13_lv_a from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-LV-A' \gset
select r5_run('e5000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('e5000000-0000-4000-8000-000000000001','ماشية الجنوب R13','R13-LV-B','مشروع ماشية مستقل ب','LIVESTOCK')$$);
select id as r13_lv_b from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-LV-B' \gset
select id as r13_re from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R5-RENT' \gset

-- Sector-authoritative roots: no universal asset table.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.create_farm('e5000000-0000-4000-8000-000000000001',%L,'مزرعة الوادي','R13-FARM','الوادي','حيازة مباشرة','Africa/Cairo',null,'r13-farm-root-001')$$,:'r13_ag'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.create_livestock_site('e5000000-0000-4000-8000-000000000001',%L,'موقع الشمال','R13-SITE-A','BARN','حظيرة أ',null,'r13-site-a-0001')$$,:'r13_lv_a'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format(
  $$select public.create_livestock_site('e5000000-0000-4000-8000-000000000001',%L,'موقع الجنوب','R13-SITE-B','BARN','حظيرة ب',null,'r13-site-b-0001')$$,:'r13_lv_b'));

-- Assign all four projects to the primary Portfolio through canonical RPCs.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.assign_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'r13-assign-re-001')$q$,:'r13_portfolio',:'r13_re'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.assign_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'r13-assign-ag-001')$q$,:'r13_portfolio',:'r13_ag'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.assign_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'r13-assign-lva-001')$q$,:'r13_portfolio',:'r13_lv_a'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.assign_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'r13-assign-lvb-001')$q$,:'r13_portfolio',:'r13_lv_b'));

-- Historical reassignment and return: old rows remain, exactly one current row.
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.move_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'اختبار حفظ الإسناد التاريخي','r13-move-ag-out')$q$,:'r13_ag',:'r13_history_portfolio'));
select r5_run('e5000000-0000-4000-8000-0000000000a1',format($q$select public.move_project_to_portfolio('e5000000-0000-4000-8000-000000000001',%L,%L,'إعادة المشروع للمحفظة التشغيلية','r13-move-ag-back')$q$,:'r13_ag',:'r13_portfolio'));

-- Governance on one Livestock project is an actual canonical command and must
-- not contaminate the sibling project.
select r5_run('e5000000-0000-4000-8000-0000000000a2',format($q$select public.record_project_risk('e5000000-0000-4000-8000-000000000001',%L,'خطر علف مستقل','تأخر توريد علف مشروع الشمال','HIGH','e5000000-0000-4000-8000-0000000000a2',current_date+7,'R13-FEED-EVIDENCE','r13-risk-lva-001')$q$,:'r13_lv_a'));

-- Integrated hierarchy, sector roots, sibling isolation and historical truth.
do $$
declare
  v_port uuid := (select id from public.investment_portfolios where organization_id='e5000000-0000-4000-8000-000000000001' and idempotency_key='r13-portfolio-main-001');
  v_ag uuid := (select id from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-AG');
  v_a uuid := (select id from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-LV-A');
  v_b uuid := (select id from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001' and internal_reference='R13-LV-B');
begin
  perform public.r13_assert((select count(*) from public.portfolio_project_assignments where investment_project_id=v_ag)=3,'historical Agriculture assignments must remain append-only');
  perform public.r13_assert((select count(*) from public.portfolio_project_assignments where investment_project_id=v_ag and removed_at is null)=1,'Agriculture must have exactly one current Portfolio');
  perform public.r13_assert((select count(*) from public.portfolio_project_assignments where portfolio_id=v_port and removed_at is null)=4,'primary Portfolio must contain RE, Agriculture and two Livestock projects');
  perform public.r13_assert((select count(*) from public.livestock_sites where project_id=v_a)=1 and (select count(*) from public.livestock_sites where project_id=v_b)=1,'each Livestock project must retain its own operational root');
  perform public.r13_assert(not exists(select 1 from public.livestock_sites where project_id=v_a and internal_reference='R13-SITE-B'),'Livestock sibling operational facts must not contaminate project A');
  perform public.r13_assert((select count(*) from public.project_risk_items where project_id=v_a)=1 and (select count(*) from public.project_risk_items where project_id=v_b)=0,'Livestock sibling governance must remain isolated');
end $$;

-- Exact Project = Portfolio = Organization BY_CURRENCY reconciliation for every
-- independent financial measure exposed by F9/F10. These are actual posted R5
-- rental facts, not fabricated zero totals; the zero-valued measures are also
-- compared from their authoritative project rows rather than hardcoded.
do $$
declare p record; o record; s record; v_port uuid := (select id from public.investment_portfolios where organization_id='e5000000-0000-4000-8000-000000000001' and idempotency_key='r13-portfolio-main-001'); begin
  select * into p from public.portfolio_financial_rollup_read where portfolio_id=v_port and currency='EGP';
  select * into o from public.organization_financial_consolidation_read where organization_id='e5000000-0000-4000-8000-000000000001' and level='BY_CURRENCY' and currency='EGP';
  select
    sum(cash_balance_minor_units::bigint) cash,
    sum(receivable_open_minor_units::bigint) receivable,
    sum(revenue_recognized_minor_units::bigint) revenue,
    sum(cost_of_sale_minor_units::bigint) cos,
    sum(expense_posted_minor_units::bigint) expense,
    sum(wip_posted_minor_units::bigint) wip,
    sum(contributions_received_minor_units::bigint) contributions,
    sum(payable_open_minor_units::bigint) payable,
    sum(paid_minor_units::bigint) paid,
    sum(retention_held_minor_units::bigint) retention
  into s from public.project_financial_position_read where organization_id='e5000000-0000-4000-8000-000000000001' and currency='EGP';
  perform public.r13_assert(s.revenue=120000 and s.cash=70000 and s.receivable=50000,'posted rental chain must supply non-zero revenue/cash/receivable evidence');
  perform public.r13_assert(s.cash=p.cash_balance_minor_units::bigint and s.cash=o.cash_balance_minor_units::bigint,'cash difference must equal zero');
  perform public.r13_assert(s.receivable=p.receivable_open_minor_units::bigint and s.receivable=o.receivable_open_minor_units::bigint,'receivable difference must equal zero');
  perform public.r13_assert(s.revenue=p.revenue_recognized_minor_units::bigint and s.revenue=o.revenue_recognized_minor_units::bigint,'revenue difference must equal zero');
  perform public.r13_assert(s.cos=p.cost_of_sale_minor_units::bigint and s.cos=o.cost_of_sale_minor_units::bigint,'cost of sale difference must equal zero');
  perform public.r13_assert(s.expense=p.expense_posted_minor_units::bigint and s.expense=o.expense_posted_minor_units::bigint,'expense difference must equal zero');
  perform public.r13_assert(s.wip=p.wip_posted_minor_units::bigint and s.wip=o.wip_posted_minor_units::bigint,'WIP difference must equal zero');
  perform public.r13_assert(s.contributions=p.contributions_received_minor_units::bigint and s.contributions=o.contributions_received_minor_units::bigint,'contribution difference must equal zero');
  perform public.r13_assert(s.payable=p.payable_open_minor_units::bigint and s.payable=o.payable_open_minor_units::bigint,'payable difference must equal zero');
  perform public.r13_assert(s.paid=p.paid_minor_units::bigint and s.paid=o.paid_minor_units::bigint,'paid difference must equal zero');
  perform public.r13_assert(s.retention=p.retention_held_minor_units::bigint and s.retention=o.retention_held_minor_units::bigint,'retention difference must equal zero');
end $$;

-- Real authenticated hostile caller: no project, sector asset, governance,
-- rental, journal or management report visibility.
do $$
declare h uuid='e5000000-0000-4000-8000-0000000000a3'; begin
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.investment_projects where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read projects');
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.cross_sector_asset_register_read where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read assets');
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.project_risk_items_read where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read governance');
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.property_rental_income_read where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read revenue');
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.journal_ledger_read where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read finance');
  perform public.r13_assert(public.r13_count_as(h,$q$select count(*) from public.organization_financial_consolidation_read where organization_id='e5000000-0000-4000-8000-000000000001'$q$)=0,'hostile tenant read reports');
end $$;

-- Repository-wide gates 01–94 immediately preceding this test independently
-- prove procurement partial receipt/invoice/payment, budget/FAC/maker-checker,
-- RE sale/valuation, Agriculture lifecycle/close, Livestock quantity
-- conservation, reversal/correction/period locks, OMR exactness, FX signed and
-- missing-rate behavior, concurrency and SECDEF ACLs. Their failure prevents
-- this integrated final gate from running or passing.
select 'R13 FULL SYNTHETIC COMPANY PASS — Project/Portfolio/Organization differences = 0; hostile tenant rows = 0' as result;
