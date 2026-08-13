-- Persistent Terranex Real Estate showcase data.
--
-- This is DEMO data, never customer evidence and never canonical Phase 2 credit.
-- It intentionally runs through the production S0-S7 command surface instead
-- of inserting financial facts directly. Re-running is a no-op once the
-- project internal_reference exists.

create or replace function pg_temp.terranex_demo_run(p_user uuid, p_sql text)
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

create or replace function pg_temp.terranex_seed_showcase()
returns text language plpgsql as $$
declare
  v_checker uuid;
  v_maker uuid;
  v_org uuid;
  v_project uuid;
  v_period_july uuid;
  v_period_aug uuid;
  v_cash uuid;
  v_investor_a uuid;
  v_investor_b uuid;
  v_supplier uuid;
  v_buyer uuid;
  v_part_a uuid;
  v_part_b uuid;
  v_agreement uuid;
  v_call uuid;
  v_contrib_a uuid;
  v_contrib_b uuid;
  v_opening uuid;
  v_asset_a uuid;
  v_parcel_a uuid;
  v_phase uuid;
  v_milestone uuid;
  v_acq_obligation uuid;
  v_dev_obligation uuid;
  v_budget uuid;
  v_valuation_a uuid;
  v_disposition uuid;
  v_recognition uuid;
  v_sell_obligation uuid;
  v_close_run uuid;
  v_snapshot uuid;
  v_alloc_run uuid;
  v_distribution uuid;
  v_asset_b uuid;
  v_parcel_b uuid;
  v_valuation_b uuid;
  v_checkpoint uuid;
  v_n integer := 0;
begin
  select id into v_checker
  from auth.users
  where last_sign_in_at is not null
    and coalesce(email, '') <> 'demo-maker@terranex.invalid'
  order by last_sign_in_at desc nulls last, created_at desc
  limit 1;

  select id into v_maker
  from auth.users
  where email = 'demo-maker@terranex.invalid'
  order by created_at desc
  limit 1;

  if v_checker is null then
    raise exception 'demo seed requires an existing signed-in Terranex user';
  end if;
  if v_maker is null then
    raise exception 'demo seed requires demo-maker@terranex.invalid to be provisioned first';
  end if;

  if exists (
    select 1 from public.investment_projects
    where internal_reference = 'DEMO-RE-2026-001'
  ) then
    return 'DEMO_ALREADY_EXISTS';
  end if;

  -- S0: organization and project.
  perform pg_temp.terranex_demo_run(v_checker,
    $$select public.create_organization('شركة أفق النيل للاستثمار العقاري – DEMO')$$);

  select o.id into v_org
  from public.organizations o
  join public.memberships m on m.organization_id = o.id
  where o.name = 'شركة أفق النيل للاستثمار العقاري – DEMO'
    and m.user_id = v_checker
    and m.status = 'ACTIVE'
  order by o.created_at desc
  limit 1;

  if v_org is null then raise exception 'demo organization was not created'; end if;

  insert into public.memberships(organization_id, user_id, role, status)
  values (v_org, v_maker, 'MEMBER', 'ACTIVE')
  on conflict (organization_id, user_id) do update
    set role = excluded.role, status = excluded.status;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    v_org, v_checker, 'DEMO_MEMBER_BOOTSTRAPPED', 'organization', v_org,
    jsonb_build_object('purpose','persistent_showcase','role','MEMBER')
  );

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_investment_project(%L,'مشروع واحة سفنكس – المرحلة الأولى (DEMO)',
      'DEMO-RE-2026-001',
      'مشروع عرض تجريبي شبه واقعي لصفقة تطوير وبيع أرض في مصر؛ جميع الأسماء والمستندات والأرقام تجريبية وليست بيانات عميل')$$,
    v_org));

  select id into v_project
  from public.investment_projects
  where organization_id = v_org and internal_reference = 'DEMO-RE-2026-001';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s6_create_accounting_period(%L,%L,date '2026-07-01',date '2026-07-31')$$,
    v_org, v_project));
  select id into v_period_july from public.accounting_periods
  where project_id = v_project and version = 1 and status = 'OPEN';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_project_cash_account(%L,%L,'الحساب البنكي الرئيسي – EGP (DEMO)','EGP')$$,
    v_org, v_project));
  select id into v_cash from public.project_cash_accounts
  where organization_id = v_org and project_id = v_project
  order by created_at limit 1;

  -- S1: investors, agreement, commitments, call and post-freeze contributions.
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_party(%L,'أحمد محمود سليمان – DEMO','PERSON')$$, v_org));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_party(%L,'شركة أفق كابيتال للاستثمار ش.م.م – DEMO','ORGANIZATION')$$, v_org));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_party(%L,'شركة الرواد للتنمية والتعمير ش.م.م – DEMO','ORGANIZATION')$$, v_org));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_party(%L,'شركة مدار للاستثمار العقاري ش.م.م – DEMO','ORGANIZATION')$$, v_org));

  select id into v_investor_a from public.parties where organization_id=v_org and legal_name='أحمد محمود سليمان – DEMO';
  select id into v_investor_b from public.parties where organization_id=v_org and legal_name='شركة أفق كابيتال للاستثمار ش.م.م – DEMO';
  select id into v_supplier from public.parties where organization_id=v_org and legal_name='شركة الرواد للتنمية والتعمير ش.م.م – DEMO';
  select id into v_buyer from public.parties where organization_id=v_org and legal_name='شركة مدار للاستثمار العقاري ش.م.م – DEMO';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.add_project_participant(%L,%L,%L)$$, v_org, v_project, v_investor_a));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.add_project_participant(%L,%L,%L)$$, v_org, v_project, v_investor_b));
  select id into v_part_a from public.project_participants where project_id=v_project and party_id=v_investor_a;
  select id into v_part_b from public.project_participants where project_id=v_project and party_id=v_investor_b;

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_agreement_draft(%L,%L,date '2026-01-15',
      array[%L,%L]::uuid[],array[2100000000,1400000000]::bigint[],
      'demo-agreement-2026-001')$$,
    v_org, v_project, v_part_a, v_part_b));
  select id into v_agreement from public.agreement_versions
  where organization_id=v_org and idempotency_key='demo-agreement-2026-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.activate_agreement_version(%L,%L)$$, v_org, v_agreement));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_capital_call(%L,%L,%L,date '2026-07-05','CALL-2026-01',
      array[%L,%L]::uuid[],array[1600000000,1400000000]::bigint[],
      'demo-capital-call-2026-001')$$,
    v_org, v_project, v_agreement, v_part_a, v_part_b));
  select id into v_call from public.capital_calls
  where organization_id=v_org and idempotency_key='demo-capital-call-2026-001';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_contribution(%L,%L,%L,%L,%L,1600000000,'EGP',date '2026-07-05','demo-contribution-a-001')$$,
    v_org, v_project, v_part_a, v_agreement, v_call));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_contribution(%L,%L,%L,%L,%L,1400000000,'EGP',date '2026-07-06','demo-contribution-b-001')$$,
    v_org, v_project, v_part_b, v_agreement, v_call));
  select id into v_contrib_a from public.contributions where organization_id=v_org and idempotency_key='demo-contribution-a-001';
  select id into v_contrib_b from public.contributions where organization_id=v_org and idempotency_key='demo-contribution-b-001';

  -- Guided intake declarations and DS-17 evidence references.
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_freeze_date(%L,%L,date '2026-06-30','DEMO-FREEZE-2026-06-30')$$,
    v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_control_totals(%L,%L,'500000000','500000000','DEMO-SIGNED-TB-2026-06-30')$$,
    v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_setup_references(%L,%L,
      'اتفاقية شركاء واحة سفنكس – نسخة DEMO','DEMO-CR-2026-001','DEMO-SCOPE-RE-001')$$,
    v_org, v_project));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'HISTORICAL_CALLS',false,
      'لا توجد طلبات رأس مال قبل تاريخ التجميد','DEMO-CALL-REGISTER-EMPTY')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'HISTORICAL_CONTRIBUTIONS',true,
      'يوجد 5,000,000 جنيه رأس مال قبل التجميد ممثل حصريًا عبر S7 OPENING_CONTRIBUTED_CAPITAL','DEMO-OPENING-CAPITAL-01')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'ACQUISITION_BASIS',true,
      'الأصل الرئيسي تم الاستحواذ عليه بعد التجميد بعقد موثق في سجل العرض','DEMO-ACQ-CONTRACT-01')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'DEVELOPMENT_BASELINE',true,
      'ميزانية الاستحواذ وتجهيز الموقع معتمدة داخل Terranex','DEMO-BUDGET-2026-01')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'UNPAID_SUPPLIERS',false,
      'لا توجد التزامات موردين افتتاحية قبل التجميد؛ أي رصيد لاحق ناتج عن تشغيل يوليو','DEMO-AP-OPENING-NONE')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'SALES_DISPOSITIONS',false,
      'لا توجد تصرفات أو مبيعات مكتملة قبل تاريخ التجميد','DEMO-SALES-OPENING-NONE')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'HISTORICAL_DISTRIBUTIONS',false,
      'لا توجد توزيعات معتمدة قبل تاريخ التجميد','DEMO-DIST-OPENING-NONE')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_declare_section_applicability(%L,%L,'BANK_STATEMENTS',false,
      'نسخة العرض لا تدعي كشف بنك خارجي حقيقي؛ حركة النقد معروضة من القيود النظامية فقط','DEMO-BANK-STATEMENT-NA')$$, v_org, v_project));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_evidence_item(%L,%L,'DEMO-CR-2026-001','السجل التجاري للمنظمة التجريبية','خزانة العرض التجريبي / 01-Organization')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_evidence_item(%L,%L,'DEMO-AGREEMENT-2026-001','اتفاقية المستثمرين ونسب 60/40','خزانة العرض التجريبي / 02-Agreement')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_evidence_item(%L,%L,'DEMO-FREEZE-2026-06-30','حزمة تجميد البيانات الافتتاحية','خزانة العرض التجريبي / 03-Opening')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.intake_record_evidence_item(%L,%L,'DEMO-BANK-ACCOUNT-01','الحساب البنكي الرئيسي للمشروع','خزانة العرض التجريبي / 04-Cash')$$, v_org, v_project));

  -- S7 opening: 5m cash = 5m opening contributed capital, exact zero variance.
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','demo-opening-2026-06-30.csv',%L,
      array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
      array[null,%L]::uuid[],array[%L,null]::uuid[],
      array['500000000','0']::text[],array['0','500000000']::text[],
      array['رصيد البنك عند التجميد – DEMO','رأس مال المستثمر الأول قبل التجميد – DEMO']::text[],
      '500000000','500000000','demo-opening-stage-001')$$,
    v_org, v_project, repeat('d',64), v_investor_a, v_cash));
  select id into v_opening from public.s7_opening_imports
  where organization_id=v_org and idempotency_key='demo-opening-stage-001';
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_validate_opening_import(%L,%L,'demo-opening-validate-001')$$, v_org, v_opening));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_review_opening_import(%L,%L,'مراجعة ملف افتتاحي تجريبي متوازن','demo-opening-review-001')$$, v_org, v_opening));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s7_approve_opening_import(%L,%L,date '2026-07-01','demo-opening-approve-001')$$, v_org, v_opening));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.attach_contribution_cash(%L,%L,%L,%L,'demo-cash-attach-a-001')$$,
    v_org, v_project, v_contrib_a, v_cash));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.attach_contribution_cash(%L,%L,%L,%L,'demo-cash-attach-b-001')$$,
    v_org, v_project, v_contrib_b, v_cash));

  -- S3 primary asset and acquisition basis.
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_real_estate_profile(%L,%L,'DEVELOP_SELL','مدينة سفنكس الجديدة، الجيزة، مصر','demo-profile-001')$$,
    v_org, v_project));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_property_asset(%L,%L,'أرض واحة سفنكس – القطاع A (DEMO)','DEMO-SPHINX-A','demo-asset-a-001')$$,
    v_org, v_project));
  select id into v_asset_a from public.property_assets where organization_id=v_org and idempotency_key='demo-asset-a-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_parcel(%L,%L,'A-17','SPX-A17-2026','قطعة أرض استثمارية داخل نطاق تطوير تجريبي',
      3.250000,'FEDDAN','demo-parcel-a-001')$$, v_org, v_asset_a));
  select id into v_parcel_a from public.parcels where organization_id=v_org and idempotency_key='demo-parcel-a-001';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'CANDIDATE','DUE_DILIGENCE',
      'بدء الفحص القانوني والفني','DEMO-DD-PACK-A17','demo-state-a-dd')$$, v_org, v_asset_a));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.create_cost_obligation(%L,%L,%L,'ثمن الأرض وتكاليف إقفال الاستحواذ – القطاع A',
      1890000000,'EGP',date '2026-07-09','CAPITALIZABLE_WIP','demo-obligation-acq-001')$$,
    v_org, v_project, v_supplier));
  select id into v_acq_obligation from public.cost_obligations where organization_id=v_org and idempotency_key='demo-obligation-acq-001';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_property_acquisition(%L,%L,%L,'DEMO-ACQ-2026-017',1800000000,90000000,'EGP',
      date '2026-07-09',%L,'عقد شراء + محضر تسليم + إثبات رسوم إقفال – DEMO','demo-acquisition-001')$$,
    v_org, v_asset_a, v_supplier, v_acq_obligation));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_property_control(%L,%L,%L,'ACQUISITION_CHECK','فحص قانوني وفني قبل الاستحواذ',
      'PASSED',date '2026-07-08',null,'لا موانع جوهرية مسجلة',%L,'DEMO-DD-PACK-A17',null,'demo-control-acq-001')$$,
    v_org, v_asset_a, v_parcel_a, v_checker));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'DUE_DILIGENCE','ACQUIRING',
      'اجتياز فحص الاستحواذ وتوقيع العقد','DEMO-ACQ-2026-017','demo-state-a-acquiring')$$,
    v_org, v_asset_a));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_property_control(%L,%L,%L,'TITLE','قيد سند الملكية',
      'PASSED',date '2026-07-10',null,'تم إثبات السند في سجل العرض',%L,'DEMO-TITLE-A17',null,'demo-control-title-a')$$,
    v_org, v_asset_a, v_parcel_a, v_checker));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_property_control(%L,%L,%L,'POSSESSION','محضر الاستلام الفعلي',
      'PASSED',date '2026-07-10',null,'تم الاستلام الفعلي للقطعة',%L,'DEMO-POSSESSION-A17',null,'demo-control-possession-a')$$,
    v_org, v_asset_a, v_parcel_a, v_checker));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'ACQUIRING','HELD',
      'اكتمل السند والاستلام','DEMO-TITLE-A17 + DEMO-POSSESSION-A17','demo-state-a-held')$$,
    v_org, v_asset_a));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_development_phase(%L,%L,%L,'تجهيز الموقع والبنية الأولية',1,
      date '2026-07-11',date '2026-07-22','demo-phase-siteprep-001')$$,
    v_org, v_asset_a, v_parcel_a));
  select id into v_phase from public.development_phases where organization_id=v_org and idempotency_key='demo-phase-siteprep-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_development_milestone(%L,%L,'اكتمال تسوية وتمهيد الموقع',1,date '2026-07-22','demo-milestone-site-001')$$,
    v_org, v_phase));
  select id into v_milestone from public.development_milestones where organization_id=v_org and idempotency_key='demo-milestone-site-001';

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.create_cost_obligation(%L,%L,%L,'أعمال تسوية وتمهيد وتجهيز الموقع – القطاع A',
      610000000,'EGP',date '2026-07-18','CAPITALIZABLE_WIP','demo-obligation-site-001')$$,
    v_org, v_project, v_supplier));
  select id into v_dev_obligation from public.cost_obligations where organization_id=v_org and idempotency_key='demo-obligation-site-001';

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.propose_property_budget(%L,%L,'EGP','ميزانية معتمدة للاستحواذ وتجهيز الموقع – نسخة DEMO',
      array[%L,%L]::uuid[],array[null,%L]::uuid[],
      array['ACQUISITION','SITE_PREPARATION']::text[],
      array[1890000000,610000000]::bigint[],'demo-budget-2026-001')$$,
    v_org, v_asset_a, v_parcel_a, v_parcel_a, v_phase));
  select id into v_budget from public.property_budget_versions where organization_id=v_org and idempotency_key='demo-budget-2026-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.approve_property_budget(%L,%L,'demo-budget-approve-001')$$, v_org, v_budget));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.classify_property_cost(%L,%L,%L,%L,null,'ACQUISITION',
      'سياسة رسملة تكلفة الاستحواذ ضمن DEVELOPMENT_WIP','demo-classify-acq-001')$$,
    v_org, v_acq_obligation, v_asset_a, v_parcel_a));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.authorize_cost_obligation(%L,%L,'demo-authorize-acq-001')$$, v_org, v_acq_obligation));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.pay_cost_obligation(%L,%L,%L,1890000000,date '2026-07-10','demo-pay-acq-001')$$,
    v_org, v_acq_obligation, v_cash));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_development_phase(%L,%L,'PLANNED','ACTIVE','بدء أعمال تجهيز الموقع','demo-phase-active-001')$$,
    v_org, v_phase));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_development_milestone(%L,%L,'PLANNED','ACTIVE','بدء بند تسوية الموقع','demo-mile-active-001')$$,
    v_org, v_milestone));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'HELD','DEVELOPING',
      'بدء مرحلة تجهيز الموقع','DEMO-PHASE-SITE-01','demo-state-a-developing')$$,
    v_org, v_asset_a));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.classify_property_cost(%L,%L,%L,%L,%L,'SITE_PREPARATION',
      'سياسة رسملة أعمال تجهيز الموقع ضمن DEVELOPMENT_WIP','demo-classify-site-001')$$,
    v_org, v_dev_obligation, v_asset_a, v_parcel_a, v_phase));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.authorize_cost_obligation(%L,%L,'demo-authorize-site-001')$$, v_org, v_dev_obligation));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.pay_cost_obligation(%L,%L,%L,610000000,date '2026-07-20','demo-pay-site-001')$$,
    v_org, v_dev_obligation, v_cash));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.confirm_real_estate_event(%L,%L,%L,%L,%L,%L,'DEVELOPMENT_PROGRESS',
      timestamp with time zone '2026-07-18 10:00:00+02',55,'PERCENT',%L,
      'مدينة سفنكس الجديدة – القطاع A','تم إنجاز أعمال التسوية الرئيسية بنسبة 55%%','DEMO-SITE-PHOTO-01','demo-event-progress-001')$$,
    v_org, v_project, v_asset_a, v_parcel_a, v_phase, v_milestone, v_maker));

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_development_milestone(%L,%L,'ACTIVE','COMPLETED','اكتمال تسوية وتمهيد الموقع','demo-mile-complete-001')$$,
    v_org, v_milestone));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_development_phase(%L,%L,'ACTIVE','COMPLETED','اكتمال مرحلة تجهيز الموقع','demo-phase-complete-001')$$,
    v_org, v_phase));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'DEVELOPING','HELD',
      'اكتمال الأعمال المخططة وأصبح الأصل جاهزًا للتصرف','DEMO-SITE-COMPLETE-01','demo-state-a-reheld')$$,
    v_org, v_asset_a));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.propose_property_valuation(%L,%L,date '2026-07-23','مقيّم مستقل – DEMO','مقارنة سوقية',
      3350000000,'EGP','مقارنة بقطع مماثلة مع خصم سيولة؛ تقييم إداري غير محاسبي','MEDIUM',
      'DEMO-VALUATION-A-2026-07','demo-valuation-a-001')$$,
    v_org, v_asset_a));
  select id into v_valuation_a from public.property_valuations where organization_id=v_org and idempotency_key='demo-valuation-a-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.approve_property_valuation(%L,%L,'demo-valuation-a-approve')$$, v_org, v_valuation_a));

  -- S4: approved sale of the developed asset for 34m; selling cost 1.5m remains payable.
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.create_property_disposition(%L,%L,%L,%L,'DEMO-SALE-A-2026-01','عقد بيع القطاع A – DEMO',
      3400000000,'EGP',date '2026-07-25',date '2026-07-29','demo-disposition-a-001')$$,
    v_org, v_project, v_asset_a, v_buyer));
  select id into v_disposition from public.property_dispositions where organization_id=v_org and idempotency_key='demo-disposition-a-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.approve_property_disposition(%L,%L,'demo-disposition-approve-001')$$, v_org, v_disposition));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'HELD','EXITING','بدء إجراءات البيع ونقل السيطرة','DEMO-SALE-A-2026-01','demo-state-a-exiting')$$,
    v_org, v_asset_a));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.confirm_property_control_transfer(%L,%L,date '2026-07-29','DEMO-SALE-HANDOVER-A','demo-control-transfer-a')$$,
    v_org, v_disposition));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.recognize_property_sale(%L,%L,date '2026-07-29','demo-sale-recognize-a')$$,
    v_org, v_disposition));
  select id into v_recognition from public.property_sale_recognitions where disposition_id=v_disposition;

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.create_cost_obligation(%L,%L,%L,'عمولة وتسويق وإتمام بيع القطاع A',
      150000000,'EGP',date '2026-07-29','EXPENSE','demo-obligation-selling-001')$$,
    v_org, v_project, v_supplier));
  select id into v_sell_obligation from public.cost_obligations where organization_id=v_org and idempotency_key='demo-obligation-selling-001';
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.classify_property_selling_cost(%L,%L,%L,null,null,
      'تكلفة بيع مباشرة مرتبطة بعقد التصرف','demo-classify-selling-001')$$,
    v_org, v_sell_obligation, v_asset_a));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.authorize_cost_obligation(%L,%L,'demo-authorize-selling-001')$$, v_org, v_sell_obligation));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.collect_property_sale_receivable(%L,%L,%L,3400000000,date '2026-07-30',
      'DEMO-BANK-CREDIT-SALE-A','demo-sale-collect-a')$$,
    v_org, v_recognition, v_cash));

  -- Add a second live pipeline asset so the showcase is not only a closed sale.
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_property_asset(%L,%L,'أرض التوسعات – القطاع B (DEMO)','DEMO-SPHINX-B','demo-asset-b-001')$$,
    v_org, v_project));
  select id into v_asset_b from public.property_assets where organization_id=v_org and idempotency_key='demo-asset-b-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.create_parcel(%L,%L,'B-04','SPX-B04-2026','قطعة توسعات تحت الفحص قبل الاستحواذ',
      5.250000,'FEDDAN','demo-parcel-b-001')$$, v_org, v_asset_b));
  select id into v_parcel_b from public.parcels where organization_id=v_org and idempotency_key='demo-parcel-b-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.transition_property_asset(%L,%L,'CANDIDATE','DUE_DILIGENCE',
      'بدء فحص فرصة توسع جديدة','DEMO-DD-PACK-B04','demo-state-b-dd')$$,
    v_org, v_asset_b));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.record_property_control(%L,%L,%L,'INSPECTION','معاينة موقع أولية',
      'PASSED',date '2026-07-27',null,'الموقع مطابق لوصف العرض الأولي',%L,'DEMO-SITE-VISIT-B04',null,'demo-control-b-inspection')$$,
    v_org, v_asset_b, v_parcel_b, v_checker));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.propose_property_valuation(%L,%L,date '2026-07-28','مقيّم مستقل – DEMO','مقارنة سوقية',
      2800000000,'EGP','تقييم أولي قبل الاستحواذ، بدون أثر محاسبي','MEDIUM','DEMO-VALUATION-B-2026-07','demo-valuation-b-001')$$,
    v_org, v_asset_b));
  select id into v_valuation_b from public.property_valuations where organization_id=v_org and idempotency_key='demo-valuation-b-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.approve_property_valuation(%L,%L,'demo-valuation-b-approve')$$, v_org, v_valuation_b));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.confirm_real_estate_event(%L,%L,%L,%L,null,null,'SITE_VISIT',
      timestamp with time zone '2026-07-27 11:30:00+02',null,null,%L,
      'مدينة سفنكس الجديدة – القطاع B','معاينة أولية لفرصة التوسع؛ ما زالت تحت الفحص','DEMO-SITE-VISIT-B04','demo-event-b-visit')$$,
    v_org, v_project, v_asset_b, v_parcel_b, v_maker));

  -- Close July and allocate the exact realized result in August.
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s6_prepare_close_run(%L,%L,%L,'إقفال يوليو 2026 – مشروع العرض')$$,
    v_org, v_project, v_period_july));
  select id into v_close_run from public.close_runs where organization_id=v_org and period_id=v_period_july and version=1;
  if exists(select 1 from public.close_run_gates where close_run_id=v_close_run and result='FAIL') then
    raise exception 'demo July close has a failed gate';
  end if;
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s6_approve_close_run(%L,%L,'demo-close-july-approve')$$, v_org, v_close_run));
  select id into v_snapshot from public.close_run_snapshots where close_run_id=v_close_run;

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s6_create_accounting_period(%L,%L,date '2026-08-01',date '2026-08-31')$$,
    v_org, v_project));
  select id into v_period_aug from public.accounting_periods
  where project_id=v_project and status='OPEN' and start_date=date '2026-08-01';

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s5_configure_allocation_rules(%L,%L,%L,'FIXED_SHARES',
      array[%L,%L]::uuid[],array[60,40]::bigint[],100,'نسب اتفاقية المستثمرين 60%% / 40%% – DEMO','demo-allocation-rules-001')$$,
    v_org, v_project, v_agreement, v_investor_a, v_investor_b));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s5_prepare_allocation(%L,%L,%L,%L,'REALIZED_RESULT','demo-allocation-run-001')$$,
    v_org, v_project, v_snapshot, v_agreement));
  select id into v_alloc_run from public.s5_allocation_runs where organization_id=v_org and idempotency_key='demo-allocation-run-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s5_approve_allocation(%L,%L,date '2026-08-05','demo-allocation-approve-001')$$,
    v_org, v_alloc_run));

  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s5_prepare_distribution(%L,%L,%L,%L,300000000,'DEMO-DIST-BOARD-2026-01','demo-distribution-001')$$,
    v_org, v_project, v_alloc_run, v_investor_a));
  select id into v_distribution from public.s5_distributions where organization_id=v_org and idempotency_key='demo-distribution-001';
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s5_approve_distribution(%L,%L,date '2026-08-05','demo-distribution-approve-001')$$,
    v_org, v_distribution));
  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s5_pay_distribution(%L,%L,%L,300000000,date '2026-08-06','DEMO-BANK-DEBIT-DIST-01','demo-distribution-pay-001')$$,
    v_org, v_distribution, v_cash));

  -- Nine exact reconciliation checkpoints, then independent sign-off.
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',date '2026-08-06',
      4100000000,'كشف حركة النقد التجريبي','DEMO-CTRL-CASH',null,null,'demo-recon-cash')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'SUPPLIER_OBLIGATION_POSITION',date '2026-08-06',
      150000000,'كشف الموردين التجريبي','DEMO-CTRL-AP',null,null,'demo-recon-ap')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'CUSTOMER_RECEIVABLE_POSITION',date '2026-08-06',
      0,'كشف العملاء التجريبي','DEMO-CTRL-AR',null,null,'demo-recon-ar')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'REALIZED_RESULT',date '2026-08-06',
      750000000,'ملخص النتيجة المحققة','DEMO-CTRL-RESULT',null,null,'demo-recon-result')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'CONTRIBUTED_CAPITAL',date '2026-08-06',
      3500000000,'سجل المساهمات التجريبي','DEMO-CTRL-CONTRIB',null,null,'demo-recon-contrib')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PARTNER_CAPITAL',date '2026-08-06',
      3950000000,'سجل رأس مال الشركاء','DEMO-CTRL-CAPITAL',null,null,'demo-recon-capital')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'DISTRIBUTION_PAYABLE',date '2026-08-06',
      0,'سجل التوزيعات المستحقة','DEMO-CTRL-DIST-AP',null,null,'demo-recon-dist-ap')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'DISTRIBUTION_PAID',date '2026-08-06',
      300000000,'سجل التوزيعات المدفوعة','DEMO-CTRL-DIST-PAID',null,null,'demo-recon-dist-paid')$$, v_org, v_project));
  perform pg_temp.terranex_demo_run(v_maker, format(
    $$select public.s7_record_reconciliation_checkpoint(%L,%L,'INVESTOR_STATEMENT_TOTAL',date '2026-08-06',
      3950000000,'إجمالي كشوف المستثمرين','DEMO-CTRL-STATEMENTS',null,null,'demo-recon-statements')$$, v_org, v_project));

  for v_checkpoint in
    select id from public.s7_reconciliation_checkpoints
    where organization_id=v_org and project_id=v_project
    order by checkpoint_code
  loop
    v_n := v_n + 1;
    perform pg_temp.terranex_demo_run(v_checker, format(
      $$select public.s7_sign_off_reconciliation_checkpoint(%L,%L,'محضر اعتماد المطابقة – DEMO',%L)$$,
      v_org, v_checkpoint, 'demo-signoff-' || lpad(v_n::text,3,'0')));
  end loop;

  perform pg_temp.terranex_demo_run(v_checker, format(
    $$select public.s7_record_pilot_rehearsal(%L,%L,'END_TO_END_CYCLE','PASS',
      'عرض تقني دائم على بيانات تجريبية شبه واقعية: تمويل، افتتاح، استحواذ، تطوير، بيع، إقفال، تخصيص، توزيع ومطابقة بصفر انحراف. لا يمثل قبول عميل أو Phase 2 حقيقية.',
      jsonb_build_object('source','persistent-demo','demo',true,'checkpoints',9,
        'cash_minor_units','4100000000','realized_result_minor_units','750000000'),
      'demo-e2e-rehearsal-001')$$,
    v_org, v_project));

  -- Final hard assertions: if a single number drifts, the surrounding
  -- transaction must roll back rather than leave a misleading showcase.
  if (select balance_minor_units::bigint from public.project_cash_position_read where cash_account_id=v_cash) <> 4100000000 then
    raise exception 'demo cash expected 4100000000 minor units';
  end if;
  if (select realized_result_minor_units::bigint from public.property_realized_result_read where recognition_id=v_recognition) <> 750000000 then
    raise exception 'demo realized result expected 750000000 minor units';
  end if;
  if (select outstanding_minor_units::bigint from public.cost_obligation_position_read where obligation_id=v_sell_obligation) <> 150000000 then
    raise exception 'demo supplier payable expected 150000000 minor units';
  end if;
  if (select coalesce(sum(closing_capital_minor_units::bigint),0) from public.s5_partner_capital_statement_read where project_id=v_project) <> 3950000000 then
    raise exception 'demo partner capital expected 3950000000 minor units';
  end if;
  if (select count(*) from public.s7_reconciliation_checkpoints where project_id=v_project) <> 9 then
    raise exception 'demo requires nine reconciliation checkpoints';
  end if;
  if exists(select 1 from public.s7_reconciliation_checkpoints where project_id=v_project and (variance_minor_units <> 0 or status <> 'SIGNED_OFF')) then
    raise exception 'demo reconciliation must be zero-variance and signed off';
  end if;
  if exists(
    select 1 from public.journal_lines jl
    where jl.project_id=v_project
    group by jl.batch_id
    having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units) or count(*) < 2
  ) then
    raise exception 'demo contains an unbalanced journal batch';
  end if;
  if (select lifecycle_state from public.property_assets where id=v_asset_b) <> 'DUE_DILIGENCE' then
    raise exception 'demo expansion asset must remain in DUE_DILIGENCE';
  end if;

  return 'DEMO_CREATED';
end $$;

select pg_temp.terranex_seed_showcase() as demo_seed_result;
