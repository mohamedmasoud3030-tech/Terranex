-- GF-024 / Livestock Commercial, Profitability & Closeout.
--
-- Functional, tenant, finance-isolation, quantity, profitability and closeout
-- proof. Two-session sale/collection/purchase races run in
-- 72_gf024_commercial_concurrency.sh; forward upgrade in
-- 73_gf024_forward_upgrade.sh.

create or replace function gf24_run(p_user uuid,p_sql text) returns uuid language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
create or replace function gf24_catch(p_user uuid,p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  begin execute p_sql; exception when others then v:=sqlerrm; reset role; return v; end;
  reset role; return 'NO_EXCEPTION';
end $$;
create or replace function gf24_count(p_user uuid,p_sql text) returns bigint language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v; reset role; return v;
end $$;
-- Runs as the database owner (no role change) to exercise immutable triggers
-- that the authenticated role can never reach (it has no DML privilege).
create or replace function gf24_owner_catch(p_sql text) returns text language plpgsql as $$
begin
  begin execute p_sql; exception when others then return sqlerrm; end;
  return 'NO_EXCEPTION';
end $$;

select id as gf24_project from public.investment_projects where internal_reference='GF020-LS-A' \gset
select id as gf24_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset
select id as gf24_herd_a from public.livestock_herds
 where internal_reference='HERD-A' and project_id=:'gf24_project' \gset
select id as gf24_site_a from public.livestock_sites
 where internal_reference='SITE-A' and project_id=:'gf24_project' \gset

-- ---------------------------------------------------------------------------
-- 1. Quantity classes registered forward-only, with correct signs.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) = 2 from livestock_quantity_event_types
  where code in ('PURCHASE_IN','SALE_OUT')
) then 1 else 0 end as gf24_commercial_classes_registered;
select 1/case when (
  select bool_and(
    case code when 'PURCHASE_IN' then direction=1 when 'SALE_OUT' then direction=-1 end)
  from livestock_quantity_event_types where code in ('PURCHASE_IN','SALE_OUT')
) then 1 else 0 end as gf24_commercial_class_directions;
select 1/case when (
  select bool_and(requires_operation=false and requires_cause=false and requires_disposal=false)
  from livestock_quantity_event_types where code in ('PURCHASE_IN','SALE_OUT')
) then 1 else 0 end as gf24_commercial_classes_are_not_operation_legs;
select 1/case when (
  select count(*) = 8 from livestock_quantity_event_types
) then 1 else 0 end as gf24_registry_is_additive;

-- ---------------------------------------------------------------------------
-- 2. Fixture: parties, cash account, an ACTIVE Cohort of 100 head.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مشتري مواشي GF024','ORGANIZATION')$$) as gf24_buyer \gset
select gf24_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مورد مواشي GF024','ORGANIZATION')$$) as gf24_supplier \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'حساب تحصيل مواشي GF024','EGP')$$,
  :'gf24_project')) as gf24_cash \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة تجارية GF024', 'PURCHASED', date '2026-08-01', 100, 'MIXED', null,
    null, null, null, null, null, 'gf24-cohort-main'
  )$q$, :'gf24_project', :'gf24_herd_a', :'gf24_site_a')) gf24_cohort \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل الدفعة التجارية', null, 'gf24-activate-main'
  )$q$, :'gf24_project', :'gf24_cohort')) gf24_cohort_active \gset

select (select count(*) from journal_batches) gf24_jb_before,
       (select count(*) from journal_lines) gf24_jl_before \gset

-- ---------------------------------------------------------------------------
-- 3. Purchase intake (SCOPE A): PURCHASE_IN addition + provenance + no Finance.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_purchase(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'شراء دفعة أغسطس GF024', 'عقد شراء 24', timestamptz '2026-08-05 08:00+00',
    'محضر استلام', null,
    array[%L::uuid], array[20]::integer[], array[50000]::bigint[],
    'gf24-purchase-1'
  )$q$, :'gf24_project', :'gf24_supplier', :'gf24_cohort')) gf24_purchase \gset
select 1/case when (
  select purchase_in = 20 and current_quantity = 120
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf24_cohort'
) then 1 else 0 end as gf24_purchase_increases_derived_quantity;
select 1/case when (
  select opening_headcount = 100 from livestock_cohorts where id = :'gf24_cohort'
) then 1 else 0 end as gf24_purchase_never_rewrites_opening;
select 1/case when (
  select count(*) = 1 from livestock_quantity_events
  where cohort_id = :'gf24_cohort' and event_type = 'PURCHASE_IN' and quantity = 20
) then 1 else 0 end as gf24_purchase_writes_one_event;
select 1/case when (
  select agreed_amount_minor_units = 1000000
  from livestock_purchase_lines where purchase_id = :'gf24_purchase'
) then 1 else 0 end as gf24_purchase_agreed_amount_snapshot;
-- No Finance side effect: a purchase never posts a journal.
select 1/case when (
  (select count(*) from journal_batches) = :'gf24_jb_before'
  and (select count(*) from journal_lines) = :'gf24_jl_before'
) then 1 else 0 end as gf24_purchase_has_no_finance_effect;
-- Idempotency and payload protection.
select 1/case when gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_purchase(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'شراء دفعة أغسطس GF024', 'عقد شراء 24', timestamptz '2026-08-05 08:00+00',
    'محضر استلام', null,
    array[%L::uuid], array[20]::integer[], array[50000]::bigint[],
    'gf24-purchase-1'
  )$q$, :'gf24_project', :'gf24_supplier', :'gf24_cohort')) = :'gf24_purchase'
then 1 else 0 end as gf24_purchase_replay_idempotent;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_purchase(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'شراء دفعة أغسطس GF024', 'عقد شراء 24', timestamptz '2026-08-05 08:00+00',
    'محضر استلام', null,
    array[%L::uuid], array[99]::integer[], array[50000]::bigint[],
    'gf24-purchase-1'
  )$q$, :'gf24_project', :'gf24_supplier', :'gf24_cohort')) like '%idempotency key payload mismatch%'
then 1 else 0 end as gf24_purchase_payload_mismatch_rejected;
select 1/case when (
  select count(*) = 1 from livestock_quantity_events
  where cohort_id = :'gf24_cohort' and event_type = 'PURCHASE_IN'
) then 1 else 0 end as gf24_purchase_replay_no_duplicate_event;
-- Cross-tenant, wrong-sector and cross-project rejection.
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.record_livestock_purchase(
    '20000000-0000-4000-8000-000000000002', %L, %L,
    'شراء متسلل', null, now(), null, null,
    array[%L::uuid], array[1]::integer[], null,
    'gf24-purchase-tenant-b'
  )$q$, :'gf24_project', :'gf24_supplier', :'gf24_cohort')) <> 'NO_EXCEPTION'
then 1 else 0 end as gf24_cross_tenant_purchase_rejected;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_purchase(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'شراء قطاع خاطئ', null, now(), null, null,
    array[%L::uuid], array[1]::integer[], null,
    'gf24-purchase-wrong-sector'
  )$q$, :'gf24_re_project', :'gf24_supplier', :'gf24_cohort')) like '%livestock project not found%'
then 1 else 0 end as gf24_wrong_sector_purchase_rejected;
-- A future purchase is scheduled truth, never current quantity.
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_purchase(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'شراء مستقبلي GF024', null, timestamptz '2027-01-01 08:00+00',
    null, null, array[%L::uuid], array[30]::integer[], null,
    'gf24-purchase-future'
  )$q$, :'gf24_project', :'gf24_supplier', :'gf24_cohort')) gf24_purchase_future \gset
select 1/case when (
  select purchase_in = 20 and current_quantity = 120
  from livestock_cohort_quantity_rollforward where cohort_id = :'gf24_cohort'
) then 1 else 0 end as gf24_future_purchase_is_not_current_quantity;

-- ---------------------------------------------------------------------------
-- 4. Sale lifecycle (SCOPE B): draft -> approval -> control transfer.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'بيع مواشي GF024-أ',
    'عقد بيع 24', current_date, 'EGP', 'تسليم حي', 'دليل عقد بيع',
    array[%L::uuid], array[60]::integer[], array[8000]::bigint[],
    'gf24-sale-a'
  )$q$, :'gf24_project', :'gf24_buyer', :'gf24_cohort')) gf24_sale_a \gset
select 1/case when (
  select control_state='DRAFT' and line_count=1 and agreed_total_minor_units::bigint=480000
  from livestock_sales_read where sale_id=:'gf24_sale_a'
) then 1 else 0 end as gf24_draft_sale_created;
select 1/case when (
  (select count(*) from journal_batches) = :'gf24_jb_before'
  and (select count(*) from livestock_quantity_events where event_type='SALE_OUT') = 0
) then 1 else 0 end as gf24_draft_has_no_effect;
-- Approval is an OWNER control; a plain ACTIVE MEMBER cannot approve.
insert into auth.users values ('00000000-0000-4000-8000-000000000006')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role, status)
values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000006','MEMBER','ACTIVE')
on conflict (organization_id, user_id) do update set role='MEMBER', status='ACTIVE';
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000006', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-sale-a-approve-member')$q$,
  :'gf24_sale_a')) like '%owner required%' then 1 else 0 end as gf24_member_cannot_approve;
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-sale-a-approve')$q$,
  :'gf24_sale_a')) gf24_sale_a_approved \gset
select 1/case when (
  select control_state='APPROVED' and recognized_revenue_minor_units='0'
  from livestock_sales_read where sale_id=:'gf24_sale_a'
) then 1 else 0 end as gf24_approval_is_not_recognition;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-sale-a-reapprove')$q$,
  :'gf24_sale_a')) like '%only a draft livestock sale%' then 1 else 0 end as gf24_double_approval_rejected;

-- ---------------------------------------------------------------------------
-- 5. Control transfer is one atomic SALE_OUT + revenue/receivable recognition.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.recognize_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, current_date, 'إذن تسليم حي', 'gf24-sale-a-recognize'
  )$q$, :'gf24_sale_a')) gf24_recognition_a \gset
select 1/case when (
  select sale_out=60 and current_quantity=60
  from livestock_cohort_quantity_rollforward where cohort_id=:'gf24_cohort'
) then 1 else 0 end as gf24_sale_out_issues_quantity;
select 1/case when (
  select control_state='CONTROL_TRANSFERRED' and recognized_revenue_minor_units='480000'
    and outstanding_receivable_minor_units='480000' and collected_minor_units='0'
  from livestock_sales_read where sale_id=:'gf24_sale_a'
) then 1 else 0 end as gf24_recognition_revenue_and_receivable;
select 1/case when (
  select count(*)=1 from livestock_quantity_events
  where cohort_id=:'gf24_cohort' and event_type='SALE_OUT' and quantity=60
) then 1 else 0 end as gf24_one_sale_out_event;
select 1/case when (
  select bool_and(source_type in ('LIVESTOCK_SALE_RECOGNITION'))
  from journal_batches jb join livestock_sale_recognitions r on r.journal_batch_id=jb.id
  where r.id=:'gf24_recognition_a'
) then 1 else 0 end as gf24_revenue_uses_shared_journal;
select 1/case when (
  select count(*) = 2 from journal_lines jl
  join livestock_sale_recognitions r on r.journal_batch_id = jl.batch_id
  join semantic_accounts sa on sa.id = jl.account_id
  where r.id=:'gf24_recognition_a'
    and ((sa.role='CUSTOMER_RECEIVABLE' and jl.debit_minor_units=480000)
      or (sa.role='LIVESTOCK_SALE_REVENUE' and jl.credit_minor_units=480000))
) then 1 else 0 end as gf24_recognition_canonical_posting;
-- Replay idempotent even after quantity/state changed.
select 1/case when gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.recognize_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, current_date, 'إذن تسليم حي', 'gf24-sale-a-recognize'
  )$q$, :'gf24_sale_a')) = :'gf24_recognition_a' then 1 else 0 end as gf24_recognition_replay_idempotent;
select 1/case when (
  select count(*)=1 from livestock_quantity_events where event_type='SALE_OUT' and cohort_id=:'gf24_cohort'
  and (select count(*) from livestock_sale_recognitions where sale_id=:'gf24_sale_a')=1
) then 1 else 0 end as gf24_recognition_replay_no_duplicate;

-- ---------------------------------------------------------------------------
-- 6. Collection (SCOPE C): partial, multiple, ceiling, idempotency.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.collect_livestock_sale_receivable(
    '10000000-0000-4000-8000-000000000001', %L, %L, 200000, current_date,
    'إيصال تحصيل أول', 'gf24-collection-1'
  )$q$, :'gf24_recognition_a', :'gf24_cash')) gf24_collection_1 \gset
select 1/case when (
  select collected_minor_units='200000' and outstanding_receivable_minor_units='280000'
  from livestock_sales_read where sale_id=:'gf24_sale_a'
) then 1 else 0 end as gf24_partial_collection;
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.collect_livestock_sale_receivable(
    '10000000-0000-4000-8000-000000000001', %L, %L, 280000, current_date,
    'إيصال تحصيل ثان', 'gf24-collection-2'
  )$q$, :'gf24_recognition_a', :'gf24_cash')) gf24_collection_2 \gset
select 1/case when (
  select state='SETTLED' and collected_minor_units='480000' and outstanding_receivable_minor_units='0'
  from livestock_sales_read where sale_id=:'gf24_sale_a'
) then 1 else 0 end as gf24_settlement_is_derived;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.collect_livestock_sale_receivable(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1, current_date,
    'تحصيل زائد', 'gf24-collection-over'
  )$q$, :'gf24_recognition_a', :'gf24_cash')) like '%collection exceeds outstanding livestock receivable%'
then 1 else 0 end as gf24_over_collection_rejected;
select 1/case when gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.collect_livestock_sale_receivable(
    '10000000-0000-4000-8000-000000000001', %L, %L, 280000, current_date,
    'إيصال تحصيل ثان', 'gf24-collection-2'
  )$q$, :'gf24_recognition_a', :'gf24_cash')) = :'gf24_collection_2' then 1 else 0 end as gf24_collection_replay_idempotent;
select 1/case when (
  select count(*)=2 from livestock_sale_collections where recognition_id=:'gf24_recognition_a'
) then 1 else 0 end as gf24_collection_replay_no_duplicate;
select 1/case when (
  select bool_and(sa.role='BANK_CASH')
  from journal_lines jl
  join livestock_sale_collections c on c.journal_batch_id = jl.batch_id
  join semantic_accounts sa on sa.id = jl.account_id
  where c.recognition_id=:'gf24_recognition_a' and jl.debit_minor_units>0
) then 1 else 0 end as gf24_collection_reuses_bank_cash;

-- ---------------------------------------------------------------------------
-- 7. Quantity, provenance, future/as-of and traceability.
-- ---------------------------------------------------------------------------
-- A sale that cannot be supplied from the as-of balance is rejected atomically.
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'بيع زائد GF024',
    null, current_date, 'EGP', null, 'دليل بيع زائد',
    array[%L::uuid], array[500]::integer[], array[8000]::bigint[],
    'gf24-sale-oversell'
  )$q$, :'gf24_project', :'gf24_buyer', :'gf24_cohort')) gf24_sale_oversell \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-sale-oversell-approve')$q$,
  :'gf24_sale_oversell')) gf24_sale_oversell_approved \gset
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.recognize_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, current_date, 'تسليم زائد', 'gf24-sale-oversell-recognize'
  )$q$, :'gf24_sale_oversell')) like '%insufficient livestock quantity%'
then 1 else 0 end as gf24_oversell_rejected;
select 1/case when (
  not exists (select 1 from livestock_sale_recognitions where sale_id=:'gf24_sale_oversell')
  and not exists (select 1 from livestock_quantity_events
    where cohort_id=:'gf24_cohort' and event_type='SALE_OUT' and quantity=500)
) then 1 else 0 end as gf24_oversell_atomic_rollback;
-- Control transfer cannot precede Cohort inception.
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'بيع قبل الدخول GF024',
    null, date '2026-07-20', 'EGP', null, null,
    array[%L::uuid], array[10]::integer[], array[8000]::bigint[],
    'gf24-sale-pre-inception'
  )$q$, :'gf24_project', :'gf24_buyer', :'gf24_cohort')) gf24_sale_pre \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-sale-pre-approve')$q$,
  :'gf24_sale_pre')) gf24_sale_pre_approved \gset
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.recognize_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, date '2026-07-25', 'تسليم قبل الدخول', 'gf24-sale-pre-recognize'
  )$q$, :'gf24_sale_pre')) like '%insufficient livestock quantity%'
then 1 else 0 end as gf24_pre_inception_transfer_rejected;
-- Traceability: cohort -> sale line -> buyer -> SALE_OUT -> recognition.
select 1/case when (
  select count(*)=1 from livestock_cohort_sale_traceability_read
  where cohort_id=:'gf24_cohort' and sale_id=:'gf24_sale_a'
    and sold_quantity=60 and recognition_id=:'gf24_recognition_a'
    and sale_out_event_id is not null
) then 1 else 0 end as gf24_cohort_sale_traceability;

-- ---------------------------------------------------------------------------
-- 8. Cost attribution and profitability (SCOPE D).
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_cost_obligation(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'علف وأجور مواشي GF024',
    300000, 'EGP', current_date, 'EXPENSE', 'gf24-cost-obligation'
  )$q$, :'gf24_project', :'gf24_supplier')) gf24_cost_obligation \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.authorize_cost_obligation('10000000-0000-4000-8000-000000000001',%L,'gf24-cost-authorize')$q$,
  :'gf24_cost_obligation')) gf24_cost_batch \gset
select id as gf24_cost_line from public.journal_lines
where batch_id=:'gf24_cost_batch' and debit_minor_units=300000 limit 1 \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.attribute_livestock_cohort_cost(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, 300000,
    'FEED', 'سياسة تحميل تكلفة GF024', 'مذكرة تحميل', 'gf24-attribution-1'
  )$q$, :'gf24_project', :'gf24_cohort', :'gf24_cost_line')) gf24_attribution \gset
select 1/case when (
  select attributed_operating_cost_minor_units='300000'
    and recognized_revenue_minor_units='480000'
    and cash_collected_minor_units='480000'
    and receivable_outstanding_minor_units='0'
    and operating_result_to_date_minor_units='180000'
    and unsold_live_quantity=60
  from livestock_cohort_results_read where cohort_id=:'gf24_cohort'
) then 1 else 0 end as gf24_cohort_result_reproducible;
select 1/case when (
  select cogs_status='NOT_GUESSED' and unsold_live_quantity_value_status='UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'
  from livestock_cohort_results_read where cohort_id=:'gf24_cohort'
) then 1 else 0 end as gf24_no_guessed_cogs_or_valuation;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.attribute_livestock_cohort_cost(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L, 1,
    'FEED', 'سياسة تحميل تكلفة GF024', 'مذكرة تحميل', 'gf24-attribution-over'
  )$q$, :'gf24_project', :'gf24_cohort', :'gf24_cost_line')) like '%exceeds authoritative source amount%'
then 1 else 0 end as gf24_cost_ceiling_enforced;
-- Append-only correction: the Finance source cannot reverse before the offset.
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',%L,'تصحيح المصدر','gf24-source-reverse-blocked')$q$,
  :'gf24_cost_batch')) = 'reverse active livestock cohort cost attributions before reversing the Finance source'
then 1 else 0 end as gf24_source_reversal_requires_offset;
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.reverse_livestock_cohort_cost_attribution(
    '10000000-0000-4000-8000-000000000001', %L, 'تصحيح تحميل الدفعة',
    'مذكرة تصحيح', 'gf24-attribution-reverse'
  )$q$, :'gf24_attribution')) gf24_attribution_reversal \gset
select 1/case when (
  select attributed_operating_cost_minor_units='0' from livestock_cohort_results_read where cohort_id=:'gf24_cohort'
  and (select count(*)=1 from livestock_cohort_cost_attributions where reversal_of_attribution_id=:'gf24_attribution')
) then 1 else 0 end as gf24_append_only_cost_correction;

-- ---------------------------------------------------------------------------
-- 9. Closeout (SCOPE E): technical, no lifecycle mutation, WARN visible.
-- ---------------------------------------------------------------------------
-- A fully-settled, clean Cohort can be technically closed; lifecycle stays ACTIVE.
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.close_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'اكتمال النشاط التجاري للدفعة', 'مذكرة إقفال GF024', 'gf24-close-main'
  )$q$, :'gf24_project', :'gf24_cohort')) gf24_closeout \gset
select 1/case when (
  select count(*)=1 from livestock_cohort_closeouts where cohort_id=:'gf24_cohort'
  and (select public.livestock_current_cohort_state(:'gf24_cohort'))='ACTIVE'
) then 1 else 0 end as gf24_close_keeps_lifecycle_active;
select 1/case when gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.close_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'اكتمال النشاط التجاري للدفعة', 'مذكرة إقفال GF024', 'gf24-close-main'
  )$q$, :'gf24_project', :'gf24_cohort')) = :'gf24_closeout' then 1 else 0 end as gf24_close_replay_idempotent;
-- Zero quantity is never forced CLOSED.
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة مستنفدة GF024', 'PURCHASED', date '2026-08-01', 10, 'MIXED', null,
    null, null, null, null, null, 'gf24-cohort-zero'
  )$q$, :'gf24_project', :'gf24_herd_a', :'gf24_site_a')) gf24_cohort_zero \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل مستنفدة', null, 'gf24-activate-zero'
  )$q$, :'gf24_project', :'gf24_cohort_zero')) gf24_cohort_zero_active \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.record_livestock_mortality(
    '10000000-0000-4000-8000-000000000001', %L, %L, 10, now(), 'DISEASE', null,
    'تقرير بيطري', null, null, 'gf24-zero-mortality'
  )$q$, :'gf24_project', :'gf24_cohort_zero')) gf24_zero_mortality \gset
select 1/case when (
  select current_quantity=0 from livestock_cohort_quantity_rollforward where cohort_id=:'gf24_cohort_zero'
  and (select public.livestock_current_cohort_state(:'gf24_cohort_zero'))='ACTIVE'
) then 1 else 0 end as gf24_zero_quantity_stays_active;
select 1/case when exists (
  select 1 from livestock_cohort_integrity_issues_read
  where cohort_id=:'gf24_cohort_zero' and code='ZERO_QUANTITY_ACTIVE' and severity='WARN'
) then 1 else 0 end as gf24_zero_quantity_is_warn_not_blocker;
select 1/case when gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.close_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L,
    'إقفال دفعة مستنفدة', 'مذكرة إقفال مستنفدة', 'gf24-close-zero'
  )$q$, :'gf24_project', :'gf24_cohort_zero')) is not null then 1 else 0 end
  as gf24_zero_quantity_close_not_blocked_by_zero;

-- ---------------------------------------------------------------------------
-- 10. Security: RLS, direct-DML denial, inactive member, immutable facts.
-- ---------------------------------------------------------------------------
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', $q$
  insert into public.livestock_sales(
    organization_id, project_id, buyer_party_id, sale_reference, sale_date,
    currency, prepared_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', :'gf24_project', :'gf24_buyer',
    'بيع مخترق', current_date, 'EGP', '00000000-0000-4000-8000-000000000001',
    'gf24-direct-dml', repeat('a', 64)
  )$q$) like '%permission denied%' then 1 else 0 end as gf24_direct_dml_denied;
-- Append-only and immutable facts are database triggers, not just RPC rules.
select 1/case when gf24_owner_catch(format($q$
  update public.livestock_sales set sale_reference='مغشوش' where id=%L$q$, :'gf24_sale_a'))
  like '%economics are immutable%' then 1 else 0 end as gf24_sale_header_immutable_outside_transition;
select 1/case when gf24_owner_catch(format($q$
  delete from public.livestock_sale_collections where id=%L$q$, :'gf24_collection_1'))
  like '%append-only%' then 1 else 0 end as gf24_collection_facts_immutable;
select 1/case when gf24_owner_catch(format($q$
  update public.livestock_sale_recognitions set recognized_revenue_minor_units=1 where id=%L$q$, :'gf24_recognition_a'))
  like '%append-only%' then 1 else 0 end as gf24_recognition_facts_immutable;
-- A generic journal-only reversal of a recognition/collection is blocked.
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001',
    (select journal_batch_id from livestock_sale_recognitions where id=%L),
    'تصحيح غير آمن', 'gf24-sale-reverse-blocked')$q$, :'gf24_recognition_a'))
  like '%controlled S6 correction policy%' then 1 else 0 end as gf24_generic_sale_reversal_blocked;
select 1/case when (
  select count(*) from pg_trigger where not tgisinternal and tgname in (
    'livestock_sale_lines_insert_guard','livestock_sale_recognitions_insert_guard',
    'livestock_sale_collections_insert_guard','journal_batches_gf024_sale_reversal_guard',
    'livestock_cost_attributions_insert_guard','journal_batches_gf024_attributed_cost_reversal_guard'
  )
) = 6 then 1 else 0 end as gf24_cross_fact_guards_attached;
-- Inactive member is refused.
insert into auth.users values ('00000000-0000-4000-8000-000000000004')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role, status)
values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','MEMBER','INACTIVE')
on conflict (organization_id, user_id) do update set status='INACTIVE';
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000004', format($q$
  select public.create_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'بيع عضو غير نشط',
    null, current_date, 'EGP', null, null,
    array[%L::uuid], array[1]::integer[], array[8000]::bigint[],
    'gf24-inactive-member'
  )$q$, :'gf24_project', :'gf24_buyer', :'gf24_cohort')) like '%forbidden%'
then 1 else 0 end as gf24_inactive_member_rejected;

-- ---------------------------------------------------------------------------
-- 11. Shared S6 OPEN/CLOSED period lock on monetary postings.
-- ---------------------------------------------------------------------------
select gf24_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',
    'مشروع فترة مواشي GF024','GF024-PERIOD-LS',null,'LIVESTOCK')$$) as gf24_period_project \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.s6_create_accounting_period('10000000-0000-4000-8000-000000000001',%L,current_date-1,current_date+1)$$,
  :'gf24_period_project')) as gf24_period \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,null,'gf24-period-profile')$$,
  :'gf24_period_project')) as gf24_period_profile \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_livestock_site('10000000-0000-4000-8000-000000000001',%L,'موقع فترة GF024','SITE-P24','FARM',null,null,'gf24-period-site')$$,
  :'gf24_period_project')) as gf24_period_site \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_livestock_herd('10000000-0000-4000-8000-000000000001',%L,'قطيع فترة GF024','HERD-P24','CATTLE','MEAT',null,'gf24-period-herd')$$,
  :'gf24_period_project')) as gf24_period_herd \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة فترة GF024', 'PURCHASED', current_date-2, 20, 'MIXED', null,
    null, null, null, null, null, 'gf24-period-cohort'
  )$q$, :'gf24_period_project', :'gf24_period_herd', :'gf24_period_site')) gf24_period_cohort \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'تفعيل دفعة الفترة', null, 'gf24-period-activate'
  )$q$, :'gf24_period_project', :'gf24_period_cohort')) gf24_period_cohort_active \gset
select gf24_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_project_cash_account('10000000-0000-4000-8000-000000000001',%L,'نقدية فترة GF024','EGP')$$,
  :'gf24_period_project')) as gf24_period_cash \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'بيع فترة GF024',
    null, current_date, 'EGP', null, 'دليل بيع فترة',
    array[%L::uuid], array[5]::integer[], array[8000]::bigint[],
    'gf24-period-sale'
  )$q$, :'gf24_period_project', :'gf24_buyer', :'gf24_period_cohort')) gf24_period_sale \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.approve_livestock_sale('10000000-0000-4000-8000-000000000001',%L,'gf24-period-sale-approve')$q$,
  :'gf24_period_sale')) gf24_period_sale_approved \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.recognize_livestock_sale(
    '10000000-0000-4000-8000-000000000001', %L, current_date, 'تسليم فترة', 'gf24-period-recognize'
  )$q$, :'gf24_period_sale')) gf24_period_recognition \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.s6_prepare_close_run('10000000-0000-4000-8000-000000000001',%L,%L,'إغلاق فترة مواشي GF024')$q$,
  :'gf24_period_project', :'gf24_period')) gf24_period_close_run \gset
select gf24_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.s6_approve_close_run('10000000-0000-4000-8000-000000000001',%L,'gf24-period-close-approve')$q$,
  :'gf24_period_close_run')) gf24_period_approved_close \gset
select 1/case when (
  select status='CLOSED' from accounting_periods where id=:'gf24_period'
) then 1 else 0 end as gf24_shared_s6_period_closed;
select 1/case when gf24_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.collect_livestock_sale_receivable(
    '10000000-0000-4000-8000-000000000001', %L, %L, 1000, current_date,
    'تحصيل بعد الإغلاق', 'gf24-period-collection-blocked'
  )$q$, :'gf24_period_recognition', :'gf24_period_cash')) like 'no open accounting period covers%'
then 1 else 0 end as gf24_collection_obeys_closed_period;
select 1/case when not exists (
  select 1 from livestock_sale_collections where recognition_id=:'gf24_period_recognition'
) then 1 else 0 end as gf24_closed_period_collection_atomic_rollback;

select 'GF-024 Livestock commercial, profitability and closeout PASS (synthetic)' as result;
