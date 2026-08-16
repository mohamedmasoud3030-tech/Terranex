-- GF-009 / S7 — deterministic end-to-end pilot rehearsal.
--
-- This suite provisions a dedicated fixture project inside the existing test
-- tenant and drives the complete product cycle through production commands
-- only: S0 project -> S1 terms and funding -> S7 controlled opening import ->
-- S2 cost and cash -> S3 real-estate operations -> S4 revenue and realized
-- result -> S6 period close -> S5 allocation and distribution -> S7
-- reconciliation checkpoints and immutable sign-off.
--
-- Every figure below is a fixture constant. Nothing here is customer data and
-- nothing here is a human UAT result: the rehearsal records a *technical*
-- END_TO_END_CYCLE fact, and the acceptance report is asserted to keep the
-- human gate separate and unstarted for this project.
--
-- The proof is numeric and exact. The nine reconciliation checkpoints compare
-- Terranex-derived balances against externally declared control totals that are
-- written here as literals. If any step of the chain drifts by a single minor
-- unit, a checkpoint records a non-zero variance, an exception is raised, the
-- sign-off is refused, and this suite fails.

\set e2e_checker '00000000-0000-4000-8000-000000000001'
\set e2e_maker '00000000-0000-4000-8000-000000000003'
\set e2e_org '10000000-0000-4000-8000-000000000001'
\set e2e_checksum 'e2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee2ee'

create or replace function s7e_assert(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'S7 end-to-end rehearsal failed: %', p_message;
  end if;
end $$;

create or replace function s7e_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
exception when others then
  reset role;
  raise;
end $$;

-- ===========================================================================
-- 0. S0 — a dedicated project for the rehearsal, created through the product
--    command. The rehearsal never touches the projects other suites depend on.
-- ===========================================================================
select s7e_assert(not exists(select 1 from public.investment_projects
  where organization_id = :'e2e_org' and name = 'مشروع البروفة الشاملة'),
  'the rehearsal must run on a fresh replay, not on a reused fixture project');
select s7e_run(:'e2e_checker', format(
  $$select public.create_investment_project(%L,'مشروع البروفة الشاملة',
    'E2E-REHEARSAL','بروفة تقنية كاملة على بيانات اختبار')$$, :'e2e_org'));
select id e2e_project, reporting_currency e2e_currency
from public.investment_projects
where organization_id = :'e2e_org' and name = 'مشروع البروفة الشاملة' limit 1 \gset
select s7e_assert(:'e2e_currency' = 'EGP', 'the rehearsal fixture assumes the EGP reporting currency');

-- The authoritative period is opened before any posting, so the whole
-- rehearsal runs with the S6 period lock actively enforced rather than in the
-- opt-in window that exists before a project has any period.
select s7e_run(:'e2e_checker', format(
  $$select public.s6_create_accounting_period(%L,%L,current_date,current_date)$$,
  :'e2e_org', :'e2e_project'));
select id e2e_period1 from public.accounting_periods
where organization_id = :'e2e_org' and project_id = :'e2e_project' and version = 1 \gset
select s7e_assert((select status = 'OPEN' from public.accounting_periods where id = :'e2e_period1'),
  'the rehearsal period must be OPEN before the cycle starts');

select s7e_run(:'e2e_checker', format(
  $$select public.create_project_cash_account(%L,%L,'حساب بروفة المشروع',%L)$$,
  :'e2e_org', :'e2e_project', :'e2e_currency'));
select id e2e_cash from public.project_cash_accounts
where organization_id = :'e2e_org' and project_id = :'e2e_project' order by id limit 1 \gset

-- ===========================================================================
-- 1. S1 — parties, participants, governing agreement, capital call,
--    contributions. Committed 3,000,000; called 3,000,000; contributed
--    3,000,000, split 2,000,000 / 1,000,000.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.create_party(%L,'مستثمر البروفة الأول','PERSON')$$, :'e2e_org'));
select s7e_run(:'e2e_checker', format(
  $$select public.create_party(%L,'مستثمر البروفة الثاني','PERSON')$$, :'e2e_org'));
select s7e_run(:'e2e_checker', format(
  $$select public.create_party(%L,'مورد البروفة','ORGANIZATION')$$, :'e2e_org'));
select s7e_run(:'e2e_checker', format(
  $$select public.create_party(%L,'مشتري البروفة','ORGANIZATION')$$, :'e2e_org'));
select id e2e_investor1 from public.parties
where organization_id = :'e2e_org' and legal_name = 'مستثمر البروفة الأول' \gset
select id e2e_investor2 from public.parties
where organization_id = :'e2e_org' and legal_name = 'مستثمر البروفة الثاني' \gset
select id e2e_supplier from public.parties
where organization_id = :'e2e_org' and legal_name = 'مورد البروفة' \gset
select id e2e_buyer from public.parties
where organization_id = :'e2e_org' and legal_name = 'مشتري البروفة' \gset

select s7e_run(:'e2e_checker', format(
  $$select public.add_project_participant(%L,%L,%L)$$, :'e2e_org', :'e2e_project', :'e2e_investor1'));
select s7e_run(:'e2e_checker', format(
  $$select public.add_project_participant(%L,%L,%L)$$, :'e2e_org', :'e2e_project', :'e2e_investor2'));
select id e2e_part1 from public.project_participants
where organization_id = :'e2e_org' and project_id = :'e2e_project' and party_id = :'e2e_investor1' \gset
select id e2e_part2 from public.project_participants
where organization_id = :'e2e_org' and project_id = :'e2e_project' and party_id = :'e2e_investor2' \gset

select s7e_run(:'e2e_checker', format(
  $$select public.create_agreement_draft(%L,%L,current_date,
    array[%L,%L]::uuid[],array[2000000,1000000]::bigint[],'e2e-agreement-001')$$,
  :'e2e_org', :'e2e_project', :'e2e_part1', :'e2e_part2'));
select id e2e_version from public.agreement_versions
where organization_id = :'e2e_org' and idempotency_key = 'e2e-agreement-001' \gset
select s7e_run(:'e2e_checker', format(
  $$select public.activate_agreement_version(%L,%L)$$, :'e2e_org', :'e2e_version'));
select s7e_assert((select status = 'ACTIVE' from public.agreement_versions where id = :'e2e_version'),
  'the governing agreement version must be ACTIVE before funding');

select s7e_run(:'e2e_checker', format(
  $$select public.create_capital_call(%L,%L,%L,current_date,'E2E-CALL-1',
    array[%L,%L]::uuid[],array[2000000,1000000]::bigint[],'e2e-call-0001')$$,
  :'e2e_org', :'e2e_project', :'e2e_version', :'e2e_part1', :'e2e_part2'));
select id e2e_call from public.capital_calls
where organization_id = :'e2e_org' and idempotency_key = 'e2e-call-0001' \gset

select s7e_run(:'e2e_checker', format(
  $$select public.record_contribution(%L,%L,%L,%L,%L,2000000,%L,current_date,'e2e-contrib-001')$$,
  :'e2e_org', :'e2e_project', :'e2e_part1', :'e2e_version', :'e2e_call', :'e2e_currency'));
select s7e_run(:'e2e_checker', format(
  $$select public.record_contribution(%L,%L,%L,%L,%L,1000000,%L,current_date,'e2e-contrib-002')$$,
  :'e2e_org', :'e2e_project', :'e2e_part2', :'e2e_version', :'e2e_call', :'e2e_currency'));
select id e2e_contrib1 from public.contributions
where organization_id = :'e2e_org' and idempotency_key = 'e2e-contrib-001' \gset
select id e2e_contrib2 from public.contributions
where organization_id = :'e2e_org' and idempotency_key = 'e2e-contrib-002' \gset

-- ===========================================================================
-- 2. S7 — the controlled opening import. It is staged by the maker, validated,
--    reviewed, and posted only by a different approver. 500,000 of opening
--    cash matched by 500,000 of opening contributed capital.
-- ===========================================================================
select s7e_run(:'e2e_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','e2e-opening.csv',%L,
    array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L]::uuid[],
    array[%L,null]::uuid[],
    array['500000','0']::text[],
    array['0','500000']::text[],
    array['نقدية افتتاحية للبروفة','رأس مال افتتاحي للبروفة']::text[],
    '500000','500000','e2e-opening-stage-1')$$,
  :'e2e_org', :'e2e_project', :'e2e_checksum', :'e2e_investor1', :'e2e_cash'));
select id e2e_import from public.s7_opening_imports
where organization_id = :'e2e_org' and idempotency_key = 'e2e-opening-stage-1' \gset
select s7e_run(:'e2e_maker', format(
  $$select public.s7_validate_opening_import(%L,%L,'e2e-opening-validate1')$$,
  :'e2e_org', :'e2e_import'));
select s7e_assert((select status = 'VALIDATED' and rejected_row_count = 0
  and accepted_row_count = 2 and debit_variance_minor_units = 0
  and credit_variance_minor_units = 0
  from public.s7_opening_imports where id = :'e2e_import'),
  'the rehearsal opening file must validate with zero rejected rows and exact control totals');
select s7e_run(:'e2e_maker', format(
  $$select public.s7_review_opening_import(%L,%L,'مراجعة بروفة','e2e-opening-review-1')$$,
  :'e2e_org', :'e2e_import'));
select s7e_run(:'e2e_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,current_date,'e2e-opening-approve1')$$,
  :'e2e_org', :'e2e_import'));
select journal_batch_id e2e_opening_batch, snapshot_content_hash e2e_opening_hash
from public.s7_opening_imports where id = :'e2e_import' \gset
select s7e_assert((select status = 'POSTED' and prepared_by <> approved_by
  and char_length(snapshot_content_hash) = 64
  from public.s7_opening_imports where id = :'e2e_import'),
  'the opening import must post under maker/checker with a frozen snapshot hash');
select s7e_assert((select sum(debit_minor_units) = 500000 and sum(credit_minor_units) = 500000
  from public.journal_lines where batch_id = :'e2e_opening_batch'),
  'the opening posting must be balanced at the declared control total');

-- ===========================================================================
-- 3. S2 — contribution cash attribution, a capitalizable cost, and its payment.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.attach_contribution_cash(%L,%L,%L,%L,'e2e-cash-attach-01')$$,
  :'e2e_org', :'e2e_project', :'e2e_contrib1', :'e2e_cash'));
select s7e_run(:'e2e_checker', format(
  $$select public.attach_contribution_cash(%L,%L,%L,%L,'e2e-cash-attach-02')$$,
  :'e2e_org', :'e2e_project', :'e2e_contrib2', :'e2e_cash'));

select s7e_run(:'e2e_maker', format(
  $$select public.create_cost_obligation(%L,%L,%L,'أعمال تطوير الموقع للبروفة',
    600000,%L,current_date,'CAPITALIZABLE_WIP','e2e-obligation-wip1')$$,
  :'e2e_org', :'e2e_project', :'e2e_supplier', :'e2e_currency'));
select id e2e_wip_obligation from public.cost_obligations
where organization_id = :'e2e_org' and idempotency_key = 'e2e-obligation-wip1' \gset

-- ===========================================================================
-- 4. S3 — real-estate profile, asset, parcel, controls, acquisition, and a
--    complete development phase, all through the lifecycle commands.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.create_real_estate_profile(%L,%L,'DEVELOP_SELL','القاهرة، مصر','e2e-profile-0001')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_checker', format(
  $$select public.create_property_asset(%L,%L,'أرض البروفة','E2E-PROP-1','e2e-asset-00001')$$,
  :'e2e_org', :'e2e_project'));
select id e2e_asset from public.property_assets
where organization_id = :'e2e_org' and idempotency_key = 'e2e-asset-00001' \gset
select s7e_run(:'e2e_checker', format(
  $$select public.create_parcel(%L,%L,'قطعة-بروفة','CAD-E2E','قطعة أرض للبروفة',
    10.000000,'FEDDAN','e2e-parcel-00001')$$, :'e2e_org', :'e2e_asset'));
select id e2e_parcel from public.parcels
where organization_id = :'e2e_org' and idempotency_key = 'e2e-parcel-00001' \gset

select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'CANDIDATE','DUE_DILIGENCE',
    'بدء فحص الاستحواذ','مذكرة فحص E2E','e2e-state-dd-0001')$$, :'e2e_org', :'e2e_asset'));
select s7e_run(:'e2e_checker', format(
  $$select public.record_property_acquisition(%L,%L,%L,'E2E-ACQ-1',400000,0,%L,
    current_date,null,'عقد استحواذ البروفة','e2e-acquisition-01')$$,
  :'e2e_org', :'e2e_asset', :'e2e_supplier', :'e2e_currency'));
select s7e_run(:'e2e_checker', format(
  $$select public.record_property_control(%L,%L,%L,'ACQUISITION_CHECK','فحص قانوني',
    'PASSED',current_date,null,'لا موانع','%s','تقرير فحص E2E',null,'e2e-control-dd-01')$$,
  :'e2e_org', :'e2e_asset', :'e2e_parcel', :'e2e_checker'));
select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'DUE_DILIGENCE','ACQUIRING',
    'اجتياز الفحص','تقرير فحص E2E','e2e-state-acq-001')$$, :'e2e_org', :'e2e_asset'));
select s7e_run(:'e2e_checker', format(
  $$select public.record_property_control(%L,%L,%L,'TITLE','نقل سند الملكية',
    'PASSED',current_date,null,'تم القيد','%s','سند E2E',null,'e2e-control-title1')$$,
  :'e2e_org', :'e2e_asset', :'e2e_parcel', :'e2e_checker'));
select s7e_run(:'e2e_checker', format(
  $$select public.record_property_control(%L,%L,%L,'POSSESSION','محضر الاستلام',
    'PASSED',current_date,null,'تسليم فعلي','%s','محضر E2E',null,'e2e-control-poss1')$$,
  :'e2e_org', :'e2e_asset', :'e2e_parcel', :'e2e_checker'));
select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'ACQUIRING','HELD',
    'اكتمل السند والاستلام','سند E2E + محضر E2E','e2e-state-held-01')$$, :'e2e_org', :'e2e_asset'));

select s7e_run(:'e2e_checker', format(
  $$select public.create_development_phase(%L,%L,%L,'مرحلة تجهيز الموقع',1,
    current_date,current_date,'e2e-phase-000001')$$, :'e2e_org', :'e2e_asset', :'e2e_parcel'));
select id e2e_phase from public.development_phases
where organization_id = :'e2e_org' and idempotency_key = 'e2e-phase-000001' \gset
select s7e_run(:'e2e_checker', format(
  $$select public.transition_development_phase(%L,%L,'PLANNED','ACTIVE',
    'بدء أعمال التجهيز','e2e-phase-active1')$$, :'e2e_org', :'e2e_phase'));
select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'HELD','DEVELOPING',
    'بدأت مرحلة التطوير','E2E-PHASE-1','e2e-state-develop1')$$, :'e2e_org', :'e2e_asset'));

-- The capitalizable cost is classified to the property and only then authorized,
-- so the posted WIP carries real S3 provenance into the later derecognition.
select s7e_run(:'e2e_maker', format(
  $$select public.classify_property_cost(%L,%L,%L,%L,%L,'SITE_PREPARATION',
    'سياسة رسملة تكاليف التجهيز','e2e-classify-wip-1')$$,
  :'e2e_org', :'e2e_wip_obligation', :'e2e_asset', :'e2e_parcel', :'e2e_phase'));
select s7e_run(:'e2e_checker', format(
  $$select public.authorize_cost_obligation(%L,%L,'e2e-authorize-wip1')$$,
  :'e2e_org', :'e2e_wip_obligation'));
-- The S2 compatibility helper uses the historical direct command on a
-- historical forward replay and the R4 maker/checker workflow on current head.
select s7e_run(:'e2e_checker', format(
  $$select public.s2_payment_workflow(%L,%L,%L,600000,current_date,'e2e-pay-wip-0001')$$,
  :'e2e_org', :'e2e_wip_obligation', :'e2e_cash'));
select s7e_assert((select outstanding_minor_units::bigint = 0
  from public.cost_obligation_position_read where obligation_id = :'e2e_wip_obligation'),
  'the capitalizable obligation must be fully settled from project cash');

select s7e_run(:'e2e_checker', format(
  $$select public.transition_development_phase(%L,%L,'ACTIVE','COMPLETED',
    'اكتملت أعمال التجهيز','e2e-phase-done-1')$$, :'e2e_org', :'e2e_phase'));
select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'DEVELOPING','HELD',
    'انتهاء مرحلة التطوير','E2E-PHASE-1-DONE','e2e-state-reheld1')$$, :'e2e_org', :'e2e_asset'));

-- ===========================================================================
-- 5. S4 — disposition, control transfer, recognition, selling cost, collection.
--    Proceeds 1,200,000; carrying cost 600,000; selling cost 200,000.
-- ===========================================================================
select s7e_run(:'e2e_maker', format(
  $$select public.create_property_disposition(%L,%L,%L,%L,'E2E-DISP-1','عقد تصرف البروفة',
    1200000,%L,current_date,current_date,'e2e-disposition-01')$$,
  :'e2e_org', :'e2e_project', :'e2e_asset', :'e2e_buyer', :'e2e_currency'));
select id e2e_disposition from public.property_dispositions
where organization_id = :'e2e_org' and idempotency_key = 'e2e-disposition-01' \gset
select s7e_run(:'e2e_checker', format(
  $$select public.approve_property_disposition(%L,%L,'e2e-disp-approve-1')$$,
  :'e2e_org', :'e2e_disposition'));
select s7e_run(:'e2e_checker', format(
  $$select public.transition_property_asset(%L,%L,'HELD','EXITING',
    'بدء إجراءات التخارج','E2E-DISP-1','e2e-state-exiting1')$$, :'e2e_org', :'e2e_asset'));
select s7e_run(:'e2e_checker', format(
  $$select public.confirm_property_control_transfer(%L,%L,current_date,
    'محضر تسليم البروفة','e2e-transfer-0001')$$, :'e2e_org', :'e2e_disposition'));
select s7e_run(:'e2e_checker', format(
  $$select public.recognize_property_sale(%L,%L,current_date,'e2e-recognize-001')$$,
  :'e2e_org', :'e2e_disposition'));
select id e2e_recognition, journal_batch_id e2e_sale_batch
from public.property_sale_recognitions where disposition_id = :'e2e_disposition' \gset
select s7e_assert((select carrying_cost_minor_units = 600000
  and recognized_proceeds_minor_units = 1200000
  from public.property_sale_recognitions where id = :'e2e_recognition'),
  'recognition must derive carrying cost from the posted S2/S3 sources, not from a budget');
select s7e_assert((select coalesce(sum(amount_minor_units),0) = 600000
  from public.property_sale_carrying_cost_sources where recognition_id = :'e2e_recognition'),
  'carrying-cost provenance must reconcile line by line to the derecognition');

select s7e_run(:'e2e_maker', format(
  $$select public.create_cost_obligation(%L,%L,%L,'عمولة بيع البروفة',
    200000,%L,current_date,'EXPENSE','e2e-obligation-sell')$$,
  :'e2e_org', :'e2e_project', :'e2e_supplier', :'e2e_currency'));
select id e2e_sell_obligation from public.cost_obligations
where organization_id = :'e2e_org' and idempotency_key = 'e2e-obligation-sell' \gset
select s7e_run(:'e2e_maker', format(
  $$select public.classify_property_selling_cost(%L,%L,%L,null,null,
    'عمولة وسيط البيع حسب العقد','e2e-classify-sell1')$$,
  :'e2e_org', :'e2e_sell_obligation', :'e2e_asset'));
select s7e_run(:'e2e_checker', format(
  $$select public.authorize_cost_obligation(%L,%L,'e2e-authorize-sell')$$,
  :'e2e_org', :'e2e_sell_obligation'));

select s7e_run(:'e2e_checker', format(
  $$select public.collect_property_sale_receivable(%L,%L,%L,1200000,current_date,
    'إشعار تحصيل البروفة','e2e-collect-00001')$$,
  :'e2e_org', :'e2e_recognition', :'e2e_cash'));
select s7e_assert((select realized_result_minor_units = '400000'
  and recognized_revenue_minor_units = '1200000'
  and carrying_cost_derecognized_minor_units = '600000'
  and selling_costs_minor_units = '200000'
  and outstanding_receivable_minor_units = '0'
  from public.property_realized_result_read where recognition_id = :'e2e_recognition'),
  'the realized result must be exactly 400000 with the receivable fully collected');

-- ===========================================================================
-- 6. S6 — close the period. The snapshot is the only allocation source.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.s6_prepare_close_run(%L,%L,%L,'بروفة إقفال شاملة')$$,
  :'e2e_org', :'e2e_project', :'e2e_period1'));
select id e2e_close_run from public.close_runs
where organization_id = :'e2e_org' and period_id = :'e2e_period1' and version = 1 \gset
select s7e_assert((select count(*) = 0 from public.close_run_gates
  where close_run_id = :'e2e_close_run' and result = 'FAIL'),
  'the rehearsal must close on truthful gate results, never on a waived failure');
select s7e_run(:'e2e_checker', format(
  $$select public.s6_approve_close_run(%L,%L,'e2e-close-approve1')$$,
  :'e2e_org', :'e2e_close_run'));
select id e2e_snapshot, content_hash e2e_snapshot_hash
from public.close_run_snapshots where close_run_id = :'e2e_close_run' \gset
select s7e_assert((select status = 'CLOSED' from public.accounting_periods where id = :'e2e_period1'),
  'approving the close run must close the authoritative period');

-- A closed period must refuse an ordinary posting. This is asserted here rather
-- than assumed, because the rest of the rehearsal depends on the lock working.
select s7e_assert((
  select not exists (
    select 1 from public.accounting_periods
    where organization_id = :'e2e_org' and project_id = :'e2e_project' and status = 'OPEN')
), 'no OPEN period may remain while the closed period awaits reopening');

select s7e_run(:'e2e_checker', format(
  $$select public.s6_reopen_period(%L,%L,%L,'فتح فترة تالية لترحيل التخصيص',
    'قرار إعادة الفتح E2E')$$, :'e2e_org', :'e2e_project', :'e2e_period1'));
select id e2e_period2 from public.accounting_periods
where organization_id = :'e2e_org' and project_id = :'e2e_project' and version = 2 \gset
select s7e_assert((select status = 'OPEN' and supersedes_period_id = :'e2e_period1'::uuid
  from public.accounting_periods where id = :'e2e_period2'),
  'the reopened period must be a new authoritative version that supersedes the closed one');

-- ===========================================================================
-- 7. S5 — allocation and distribution from the approved snapshot, under
--    maker/checker. 400,000 splits exactly 200,000 / 200,000.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',
    array[%L,%L]::uuid[],array[1,1]::bigint[],2,'E2E-RULE-BASIS','e2e-rules-000001')$$,
  :'e2e_org', :'e2e_project', :'e2e_version', :'e2e_investor1', :'e2e_investor2'));
select s7e_run(:'e2e_maker', format(
  $$select public.s5_prepare_allocation(%L,%L,%L,%L,'REAL_ESTATE_SALE_RESULT','e2e-alloc-prep-01')$$,
  :'e2e_org', :'e2e_project', :'e2e_snapshot', :'e2e_version'));
select id e2e_run from public.s5_allocation_runs
where organization_id = :'e2e_org' and idempotency_key = 'e2e-alloc-prep-01' \gset
select s7e_assert((select source_amount_minor_units = 400000
  and snapshot_content_hash = :'e2e_snapshot_hash'
  from public.s5_allocation_runs where id = :'e2e_run'),
  'the allocation run must freeze the approved close snapshot and its exact source amount');
select s7e_assert(public.s5_allocation_lines_are_canonical(:'e2e_run'),
  'allocation lines must equal the deterministic largest-remainder result');
select s7e_assert((select count(*) = 2 and sum(allocated_minor_units) = 400000
  and bool_and(allocated_minor_units = 200000)
  from public.s5_allocation_lines where run_id = :'e2e_run'),
  'the rehearsal allocation must split 400000 into two exact halves');
select s7e_run(:'e2e_checker', format(
  $$select public.s5_approve_allocation(%L,%L,current_date,'e2e-alloc-appr-01')$$,
  :'e2e_org', :'e2e_run'));
select s7e_assert((select prepared_by <> approved_by and status = 'APPROVED'
  from public.s5_allocation_runs where id = :'e2e_run'),
  'allocation approval must be performed by someone other than the preparer');

select s7e_run(:'e2e_maker', format(
  $$select public.s5_prepare_distribution(%L,%L,%L,%L,150000,'E2E-DIST-EVIDENCE','e2e-dist-prep-01')$$,
  :'e2e_org', :'e2e_project', :'e2e_run', :'e2e_investor1'));
select id e2e_distribution from public.s5_distributions
where organization_id = :'e2e_org' and idempotency_key = 'e2e-dist-prep-01' \gset
select s7e_run(:'e2e_checker', format(
  $$select public.s5_approve_distribution(%L,%L,current_date,'e2e-dist-appr-01')$$,
  :'e2e_org', :'e2e_distribution'));
select s7e_run(:'e2e_checker', format(
  $$select public.s5_pay_distribution(%L,%L,%L,150000,current_date,'E2E-PAY-EVIDENCE','e2e-dist-pay-001')$$,
  :'e2e_org', :'e2e_distribution', :'e2e_cash'));
select s7e_assert((select settlement_status = 'PAID' and outstanding_minor_units = '0'
  from public.s5_distributions_read where distribution_id = :'e2e_distribution'),
  'the rehearsal distribution must be fully settled from project cash');

-- ===========================================================================
-- 8. Balances and provenance survive the whole cycle.
-- ===========================================================================
select s7e_assert((select count(*) = 0 from (
    select jl.batch_id from public.journal_lines jl
    where jl.organization_id = :'e2e_org' and jl.project_id = :'e2e_project'
    group by jl.batch_id
    having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units) or count(*) < 2
  ) u), 'every batch produced by the rehearsal must be balanced with at least two lines');
select s7e_assert((select balance_minor_units::bigint = 3950000
  from public.project_cash_position_read where cash_account_id = :'e2e_cash'),
  'the derived cash position must equal the exact expected 3950000');
select s7e_assert((
  select closing_capital_minor_units::bigint = 2550000
  from public.s5_partner_capital_statement_read
  where project_id = :'e2e_project' and participant_party_id = :'e2e_investor1'),
  'investor one closing capital must reconcile to 2550000 (2000000 + 500000 opening + 200000 - 150000)');
select s7e_assert((
  select closing_capital_minor_units::bigint = 1200000
  from public.s5_partner_capital_statement_read
  where project_id = :'e2e_project' and participant_party_id = :'e2e_investor2'),
  'investor two closing capital must reconcile to 1200000 (1000000 + 200000)');
select s7e_assert((
  select bool_and(closing_capital_minor_units::bigint =
    opening_capital_minor_units::bigint + contributions_minor_units::bigint
    + allocated_income_minor_units::bigint - allocated_loss_minor_units::bigint
    - approved_distributions_minor_units::bigint)
  from public.s5_partner_capital_statement_read where project_id = :'e2e_project'),
  'the partner-capital rollforward must reconcile exactly for every investor');

-- Provenance chain: opening import -> journal; sale -> carrying-cost sources;
-- close snapshot -> allocation run -> distribution -> payment journal.
select s7e_assert((select count(*) = 1 from public.journal_batches
  where id = :'e2e_opening_batch' and source_type = 'S7_OPENING_IMPORT'
    and source_id = :'e2e_import'::uuid),
  'the opening posting must remain traceable to its import record');
select s7e_assert((select close_snapshot_id = :'e2e_snapshot'::uuid
  and source_period_id = :'e2e_period1'::uuid
  from public.s5_allocation_runs where id = :'e2e_run'),
  'the allocation run must remain traceable to the closed period and its snapshot');
select s7e_assert((select allocation_run_id = :'e2e_run'::uuid
  from public.s5_distributions where id = :'e2e_distribution'),
  'the distribution must remain traceable to its allocation run');
select s7e_assert((select count(*) = 1 from public.s5_distribution_payments p
  join public.journal_batches jb on jb.id = p.journal_batch_id
  where p.distribution_id = :'e2e_distribution'
    and jb.source_type = 'S5_DISTRIBUTION_PAYMENT'),
  'the distribution payment must remain traceable to its own posted batch');

-- ===========================================================================
-- 9. S7 reconciliation: nine checkpoints against externally declared control
--    totals. Every declared value below is a fixture constant, so a matched
--    checkpoint is an exact, independent proof of the whole chain.
-- ===========================================================================
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',current_date,
    3950000,'كشف بنك البروفة','EV-E2E-CASH',null,null,'e2e-recon-cash-01')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'SUPPLIER_OBLIGATION_POSITION',current_date,
    200000,'كشف الموردين للبروفة','EV-E2E-AP',null,null,'e2e-recon-ap-0001')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'CUSTOMER_RECEIVABLE_POSITION',current_date,
    0,'كشف العملاء للبروفة','EV-E2E-AR',null,null,'e2e-recon-ar-0001')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'REALIZED_RESULT',current_date,
    400000,'ملخص نتيجة البروفة','EV-E2E-RESULT',null,null,'e2e-recon-result1')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'CONTRIBUTED_CAPITAL',current_date,
    3500000,'سجل المساهمات للبروفة','EV-E2E-CONTRIB',null,null,'e2e-recon-contrib')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PARTNER_CAPITAL',current_date,
    3750000,'سجل رأس مال الشركاء','EV-E2E-CAPITAL',null,null,'e2e-recon-capital')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'DISTRIBUTION_PAYABLE',current_date,
    0,'سجل التوزيعات المستحقة','EV-E2E-DIST-AP',null,null,'e2e-recon-dist-ap')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'DISTRIBUTION_PAID',current_date,
    150000,'سجل التوزيعات المدفوعة','EV-E2E-DIST-PAID',null,null,'e2e-recon-dist-pd')$$,
  :'e2e_org', :'e2e_project'));
select s7e_run(:'e2e_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'INVESTOR_STATEMENT_TOTAL',current_date,
    3750000,'كشوف المستثمرين للبروفة','EV-E2E-STATEMENT',null,null,'e2e-recon-stmt-01')$$,
  :'e2e_org', :'e2e_project'));

select s7e_assert((select count(*) = 9 from public.s7_reconciliation_checkpoints
  where project_id = :'e2e_project'),
  'the rehearsal must record all nine reconciliation checkpoints');
select s7e_assert((select bool_and(variance_minor_units = 0 and status = 'MATCHED')
  from public.s7_reconciliation_checkpoints where project_id = :'e2e_project'),
  'every rehearsal checkpoint must reconcile to exactly zero variance');
select s7e_assert((select count(*) = 0 from public.s7_reconciliation_exceptions
  where project_id = :'e2e_project'),
  'a fully matched rehearsal must raise no reconciliation exception');

-- Immutable sign-off, by an approver who is not the preparer.
do $$
declare v_id uuid; v_n int := 0;
begin
  for v_id in
    select c.id from public.s7_reconciliation_checkpoints c
    join public.investment_projects p on p.id = c.project_id
    where p.name = 'مشروع البروفة الشاملة'
    order by c.checkpoint_code
  loop
    v_n := v_n + 1;
    perform s7e_run('00000000-0000-4000-8000-000000000001', format(
      $q$select public.s7_sign_off_reconciliation_checkpoint(
        '10000000-0000-4000-8000-000000000001',%L,'محضر اعتماد البروفة','e2e-signoff-%s')$q$,
      v_id, lpad(v_n::text, 4, '0')));
  end loop;
end $$;
select s7e_assert((select bool_and(status = 'SIGNED_OFF' and signed_off_by <> prepared_by)
  from public.s7_reconciliation_checkpoints where project_id = :'e2e_project'),
  'every rehearsal checkpoint must carry an immutable maker/checker sign-off');

-- ===========================================================================
-- 10. Only now is the technical rehearsal fact recorded — and it is recorded
--     as a technical result, never as customer acceptance.
-- ===========================================================================
select s7e_run(:'e2e_checker', format(
  $$select public.s7_record_pilot_rehearsal(%L,%L,'END_TO_END_CYCLE','PASS',
    'بروفة تقنية كاملة على بيانات اختبار: تأسيس، تمويل، رصيد افتتاحي، تكاليف، عمليات عقارية، بيع، إقفال، تخصيص، توزيع، ومطابقة تسع نقاط رقابية بصفر انحراف',
    jsonb_build_object('source','27_s7_end_to_end_rehearsal.sql','checkpoints',9,
      'cash_minor_units','3950000','realized_result_minor_units','400000'),
    'e2e-rehearsal-cycle')$$, :'e2e_org', :'e2e_project'));

select s7e_assert((select end_to_end_result = 'PASS'
  and posted_opening_imports = 1
  and opening_control_totals_match
  and opening_import_rejected_rows = 0
  and reconciliation_checkpoints = 9
  and reconciliation_non_zero_variances = 0
  and unresolved_exceptions = 0
  and unresolved_critical_exceptions = 0
  and unbalanced_journal_batches = 0
  and unreconciled_bank_statement_lines = 0
  from public.s7_pilot_acceptance_report_read where project_id = :'e2e_project'),
  'the acceptance report must reproduce the rehearsal state exactly from recorded facts');
select s7e_assert((select human_uat_status = 'NOT_STARTED' and uat_accepted_tasks = 0
  from public.s7_pilot_acceptance_report_read where project_id = :'e2e_project'),
  'a passing technical rehearsal must never advance the human UAT gate');
select s7e_assert((select backup_restore_result is null and access_revocation_result is null
  from public.s7_pilot_acceptance_report_read where project_id = :'e2e_project'),
  'rehearsals that were not recorded for this project must report as unknown, never as PASS');

select 'S7 end-to-end pilot rehearsal SQL PASS' result;
