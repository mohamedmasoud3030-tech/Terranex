-- GF-023 — Livestock operational completion: health, reproduction, optional
-- Animal identity and feed. Reuses the GF-020 harness and fixture hierarchy.

select id gf23_project from investment_projects where internal_reference='GF020-LS-A' \gset
select id gf23_site from livestock_sites where project_id=:'gf23_project' and internal_reference='SITE-A' \gset
select id gf23_herd from livestock_herds where project_id=:'gf23_project' and internal_reference='HERD-A' \gset
select id gf23_b_project from investment_projects where internal_reference='GF020-LS-B' \gset
select id gf23_b_cohort from livestock_cohorts where project_id=:'gf23_b_project' and cohort_reference='دفعة باء' \gset

-- Isolated ACTIVE fixtures: reproduction/health and FCR must not contaminate
-- one another's quantity timeline.
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'دفعة عمليات GF023',
  'BORN',current_date-10,20,'MIXED',null,null,null,null,'دليل افتتاحي',null,'gf23-cohort-ops')
$q$,:'gf23_project',:'gf23_herd',:'gf23_site')) gf23_ops \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.transition_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
  'تفعيل العمليات',null,'gf23-cohort-ops-active')
$q$,:'gf23_project',:'gf23_ops')) gf23_ops_active \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'دفعة FCR GF023',
  'PURCHASED',current_date-10,10,'MALE',null,null,null,null,'دليل افتتاحي',null,'gf23-cohort-fcr')
$q$,:'gf23_project',:'gf23_herd',:'gf23_site')) gf23_fcr \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.transition_livestock_cohort(
  '10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE',
  'تفعيل قياس التحويل',null,'gf23-cohort-fcr-active')
$q$,:'gf23_project',:'gf23_fcr')) gf23_fcr_active \gset

select (select count(*) from journal_batches) gf23_jb_before,
       (select count(*) from journal_lines) gf23_jl_before,
       (select count(*) from project_payments) gf23_pay_before \gset

-- ---------------------------------------------------------------------------
-- Medicine/product references and health/withdrawal truth.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_medicine_product(
  '10000000-0000-4000-8000-000000000001',%L,'MED-01','علاج تنفسي','MEDICINE',
  'مادة علاجية',5,null,'gf23-med-01')
$q$,:'gf23_project')) gf23_medicine \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_medicine_product(
  '10000000-0000-4000-8000-000000000001',%L,'VAC-01','لقاح دوري','VACCINE',
  null,2,null,'gf23-vac-01')
$q$,:'gf23_project')) gf23_vaccine \gset

select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_medicine_product(
  '10000000-0000-4000-8000-000000000001',%L,'MED-01','علاج تنفسي','MEDICINE',
  'مادة علاجية',5,null,'gf23-med-01')
$q$,:'gf23_project'))=:'gf23_medicine' then 1 else 0 end as product_replay_idempotent;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_medicine_product(
  '10000000-0000-4000-8000-000000000001',%L,'MED-01','بيانات مختلفة','MEDICINE',
  null,0,null,'gf23-med-01')
$q$,:'gf23_project')) like '%idempotency key payload mismatch%' then 1 else 0 end as product_payload_mismatch_rejected;
select id gf23_ag_project from investment_projects where sector='AGRICULTURE' limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_medicine_product(
  '10000000-0000-4000-8000-000000000001',%L,'WRONG','منتج خاطئ','MEDICINE',null,0,null,'gf23-wrong-sector')
$q$,:'gf23_ag_project')) like '%livestock project not found%' then 1 else 0 end as wrong_sector_product_rejected;
select gf20_run('00000000-0000-4000-8000-000000000001',$q$
 select public.create_investment_project(
  '10000000-0000-4000-8000-000000000001','مشروع ماشية ثان لاختبار العزل','GF023-LS-A2',null,'LIVESTOCK')
$q$) gf23_other_project \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'OBSERVATION','OTHER',
  'خلط مشروع',null,null,null,null,current_date::timestamptz,'مشرف','دليل',null,'gf23-cross-project')
$q$,:'gf23_other_project',:'gf23_ops')) <> 'NO_EXCEPTION'
 then 1 else 0 end as cross_project_health_rejected;

-- Cohort-level treatment and vaccination. Withdrawal values are frozen from
-- the product reference and remain queryable without commercial semantics.
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'TREATMENT',null,null,%L,
  10,'ML','ORAL',current_date::timestamptz,'طبيب بيطري','سجل علاج',null,'gf23-health-treatment')
$q$,:'gf23_project',:'gf23_ops',:'gf23_medicine')) gf23_treatment \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'VACCINATION',null,null,%L,
  1,'DOSE','INJECTION',current_date::timestamptz,'طبيب بيطري','سجل تطعيم',null,'gf23-health-vaccine')
$q$,:'gf23_project',:'gf23_ops',:'gf23_vaccine')) gf23_vaccination \gset
select 1/case when (
 select withdrawal_period_days=5
   and withdrawal_ends_at=effective_at+interval '5 days'
   and withdrawal_status='ACTIVE'
 from livestock_health_events_read where id=:'gf23_treatment'
) and (
 select withdrawal_period_days=2
 from livestock_health_events where id=:'gf23_vaccination'
) then 1 else 0 end as withdrawal_window_explicit_and_queryable;
select 1/case when (select count(*)=2 from livestock_active_withdrawals where project_id=:'gf23_project')
 then 1 else 0 end as active_withdrawal_read_model_truthful;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'TREATMENT',null,null,%L,
  1,'DOSE','INJECTION',current_date::timestamptz,'طبيب','دليل',null,'gf23-health-kind-bad')
$q$,:'gf23_project',:'gf23_ops',:'gf23_vaccine')) like '%product kind does not match%'
 then 1 else 0 end as treatment_vaccine_kind_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'DIAGNOSIS',null,'التهاب',null,
  null,null,null,current_date::timestamptz,'طبيب','دليل',null,'gf23-health-diagnosis-bad')
$q$,:'gf23_project',:'gf23_ops')) like '%requires a condition classification%'
 then 1 else 0 end as diagnosis_classification_required;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'TREATMENT',null,null,%L,
  10,'ML','ORAL',current_date::timestamptz,'طبيب بيطري','سجل علاج',null,'gf23-health-treatment')
$q$,:'gf23_project',:'gf23_ops',:'gf23_medicine'))=:'gf23_treatment'
 then 1 else 0 end as health_replay_idempotent;

-- ---------------------------------------------------------------------------
-- Optional Animal identity and Cohort membership provenance.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG',' EG-023-001 ','FEMALE',
  current_date-100,null,current_date::timestamptz,'سجل تعريف',null,'gf23-animal-dam')
$q$,:'gf23_project',:'gf23_ops')) gf23_dam \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'RFID','RF-023-002','MALE',
  current_date-100,null,current_date::timestamptz,'سجل تعريف',null,'gf23-animal-sire')
$q$,:'gf23_project',:'gf23_ops')) gf23_sire \gset
select 1/case when (select count(*)=2 from livestock_animals where identification_cohort_id=:'gf23_ops')
 and (select count(*)=2 from livestock_animal_memberships where cohort_id=:'gf23_ops')
 and (select current_quantity=20 from livestock_cohort_quantity_rollforward where cohort_id=:'gf23_ops')
 then 1 else 0 end as optional_identity_preserves_membership_and_quantity;
select 1/case when (select identification_quantity_effect=0 from livestock_animals_read where id=:'gf23_dam')
 then 1 else 0 end as identification_effect_explicitly_zero;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.identify_livestock_animal(
  '10000000-0000-4000-8000-000000000001',%L,%L,'EAR_TAG','eg 023 001','UNKNOWN',
  null,null,current_date::timestamptz,null,null,'gf23-animal-duplicate')
$q$,:'gf23_project',:'gf23_ops')) like '%Animal identifier already exists%'
 then 1 else 0 end as normalized_identifier_unique_in_project;

-- Animal-level health must use membership valid at the effective time.
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_health_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'OBSERVATION','REPRODUCTIVE',
  'متابعة فردية',null,null,null,null,current_date::timestamptz,'مشرف القطيع','ملاحظة فردية',null,'gf23-health-animal')
$q$,:'gf23_project',:'gf23_ops',:'gf23_dam')) gf23_animal_health \gset
select 1/case when (select animal_id=:'gf23_dam' from livestock_health_events where id=:'gf23_animal_health')
 then 1 else 0 end as animal_level_health_supported;

-- ---------------------------------------------------------------------------
-- Reproduction: observation-only outcome vs exactly one GF-022 BIRTH event.
-- ---------------------------------------------------------------------------
select (select current_quantity from livestock_cohort_quantity_rollforward where cohort_id=:'gf23_ops') gf23_qty_before_birth \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_reproduction_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'BIRTH_OUTCOME',2,
  null,null,null,2,1,'OBSERVATION_ONLY',null,%L,%L,current_date::timestamptz,
  'مشرف الولادة','محضر ملاحظة',null,'gf23-repro-observed')
$q$,:'gf23_project',:'gf23_ops',:'gf23_dam',:'gf23_sire')) gf23_observed_birth \gset
select 1/case when (select current_quantity=:'gf23_qty_before_birth'::integer from livestock_cohort_quantity_rollforward where cohort_id=:'gf23_ops')
 and (select not affects_authoritative_quantity and birth_quantity_event_id is null from livestock_reproduction_events_read where id=:'gf23_observed_birth')
 then 1 else 0 end as observation_birth_does_not_change_quantity;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_reproduction_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'BIRTH_OUTCOME',2,
  null,null,null,3,0,'GF022_BIRTH',null,%L,%L,current_date::timestamptz,
  'مشرف الولادة','محضر ولادة',null,'gf23-repro-authoritative')
$q$,:'gf23_project',:'gf23_ops',:'gf23_dam',:'gf23_sire')) gf23_authoritative_birth \gset
select 1/case when (
 select affects_authoritative_quantity and birth_quantity_event_id is not null
 from livestock_reproduction_events_read where id=:'gf23_authoritative_birth'
) and (
 select count(*)=1 from livestock_quantity_events q
 join livestock_reproduction_events r on r.birth_quantity_event_id=q.id
 where r.id=:'gf23_authoritative_birth' and q.event_type='BIRTH' and q.quantity=3
) and (
 select current_quantity=:'gf23_qty_before_birth'::integer+3
 from livestock_cohort_quantity_rollforward where cohort_id=:'gf23_ops'
) then 1 else 0 end as authoritative_birth_reuses_gf022_once;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_reproduction_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,null,'BIRTH_OUTCOME',2,
  null,null,null,3,0,'GF022_BIRTH',null,%L,%L,current_date::timestamptz,
  'مشرف الولادة','محضر ولادة',null,'gf23-repro-authoritative')
$q$,:'gf23_project',:'gf23_ops',:'gf23_dam',:'gf23_sire'))=:'gf23_authoritative_birth'
 and (select count(*)=1 from livestock_reproduction_events where idempotency_key='gf23-repro-authoritative')
 then 1 else 0 end as authoritative_birth_replay_no_double_count;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_reproduction_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,'PREGNANCY_CHECK',1,
  null,'POSITIVE',current_date+100,null,null,null,null,null,null,current_date::timestamptz,
  'طبيب التكاثر','كشف حمل',null,'gf23-pregnancy')
$q$,:'gf23_project',:'gf23_ops',:'gf23_dam')) gf23_pregnancy \gset
select 1/case when (select pregnancy_status='POSITIVE' and expected_birth_date=current_date+100 from livestock_reproduction_events where id=:'gf23_pregnancy')
 then 1 else 0 end as pregnancy_lifecycle_recorded;

-- ---------------------------------------------------------------------------
-- Feed issue validation and evidence-aware FCR.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.create_livestock_feed_item(
  '10000000-0000-4000-8000-000000000001',%L,'FEED-01','علف مركز','CONCENTRATE','KG',null,'gf23-feed-item')
$q$,:'gf23_project')) gf23_feed \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_weight_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,current_date::timestamptz-interval '2 days',
  'COHORT_TOTAL',1000,'KG',null,null,'ميزان بداية',null,'gf23-fcr-weight-start')
$q$,:'gf23_project',:'gf23_fcr')) gf23_weight_start \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_feed_issue(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,100,'KG',
  current_date::timestamptz-interval '1 day',current_date-1,current_date-1,
  'عامل التغذية','إذن صرف',null,'gf23-feed-issue')
$q$,:'gf23_project',:'gf23_fcr',:'gf23_feed')) gf23_feed_issue \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_weight_event(
  '10000000-0000-4000-8000-000000000001',%L,%L,current_date::timestamptz,
  'COHORT_TOTAL',1050,'KG',null,null,'ميزان نهاية',null,'gf23-fcr-weight-end')
$q$,:'gf23_project',:'gf23_fcr')) gf23_weight_end \gset
select 1/case when (
 select metric_status='AVAILABLE' and feed_quantity_kg::numeric=100
   and weight_gain_kg::numeric=50 and fcr::numeric=2
 from livestock_feed_conversion_metrics where cohort_id=:'gf23_fcr'
) then 1 else 0 end as fcr_available_only_from_supported_inputs;
select 1/case when (
 select metric_status<>'AVAILABLE' and fcr is null
 from livestock_feed_conversion_metrics where cohort_id=:'gf23_ops'
) then 1 else 0 end as fcr_unavailable_is_truthful_null;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_feed_issue(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,1,'LITER',current_date::timestamptz,
  null,null,'عامل التغذية',null,null,'gf23-feed-wrong-unit')
$q$,:'gf23_project',:'gf23_fcr',:'gf23_feed')) like '%unit does not match%'
 then 1 else 0 end as feed_issue_unit_mismatch_rejected;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$
 select public.record_livestock_feed_issue(
  '10000000-0000-4000-8000-000000000001',%L,%L,%L,100,'KG',
  current_date::timestamptz-interval '1 day',current_date-1,current_date-1,
  'عامل التغذية','إذن صرف',null,'gf23-feed-issue')
$q$,:'gf23_project',:'gf23_fcr',:'gf23_feed'))=:'gf23_feed_issue'
 then 1 else 0 end as feed_replay_idempotent;

-- ---------------------------------------------------------------------------
-- Isolation, inactive membership, RLS and privileged/direct-write backstops.
-- ---------------------------------------------------------------------------
select gf20_run('00000000-0000-4000-8000-000000000002',format($q$
 select public.create_livestock_medicine_product(
  '20000000-0000-4000-8000-000000000002',%L,'MED-01','منتج باء','MEDICINE',null,0,null,'gf23-b-product')
$q$,:'gf23_b_project')) gf23_b_product \gset
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
 'select count(*) from public.livestock_medicine_products_read')=1
 and gf20_count('00000000-0000-4000-8000-000000000001',
 'select count(*) from public.livestock_medicine_products_read where project_id='''||:'gf23_b_project'||'''')=0
 then 1 else 0 end as two_tenant_rls_isolation;

insert into auth.users(id) values('00000000-0000-4000-8000-000000000099') on conflict do nothing;
insert into memberships(organization_id,user_id,role,status)
values('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000099','MEMBER','INACTIVE')
on conflict(organization_id,user_id) do update set status='INACTIVE';
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000099',format($q$
 select public.create_livestock_feed_item(
  '10000000-0000-4000-8000-000000000001',%L,'INACTIVE','مرفوض','OTHER','KG',null,'gf23-inactive')
$q$,:'gf23_project')) like '%forbidden%' then 1 else 0 end as inactive_member_rejected;

select 1/case when (
 select count(*)=7 and bool_and(relrowsecurity and relforcerowsecurity)
 from pg_class where relnamespace='public'::regnamespace and relname in (
  'livestock_medicine_products','livestock_animals','livestock_animal_memberships',
  'livestock_health_events','livestock_reproduction_events','livestock_feed_items','livestock_feed_issues')
) then 1 else 0 end as gf023_all_tables_force_rls;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$
 update public.livestock_health_events set notes='تعديل' where id=%L
$q$,:'gf23_treatment')) like '%permission denied%'
 then 1 else 0 end as authenticated_direct_update_denied;
select 1/case when gf20_owner_catch(format($q$
 update public.livestock_health_events set notes='تعديل' where id=%L
$q$,:'gf23_treatment')) like '%append-only%'
 then 1 else 0 end as privileged_fact_mutation_rejected;

begin;
set constraints livestock_animals_membership_shape immediate;
select 1/case when gf20_owner_catch(format($q$
 insert into public.livestock_animals(
  organization_id,project_id,identification_cohort_id,identifier_type,identifier_value,
  identifier_normalized,sex,identified_at,identified_by,idempotency_key,request_hash)
 values('10000000-0000-4000-8000-000000000001',%L,%L,'OTHER','ORPHAN','ORPHAN',
  'UNKNOWN',current_date::timestamptz,'00000000-0000-4000-8000-000000000001','gf23-orphan-animal',repeat('a',64))
$q$,:'gf23_project',:'gf23_ops')) like '%requires exactly one identification membership%'
 then 1 else 0 end as privileged_orphan_animal_rejected;
rollback;

select 1/case when gf20_owner_catch(format($q$
 insert into public.livestock_feed_items(
  organization_id,project_id,item_reference,name,feed_category,issue_unit,created_by,idempotency_key,request_hash)
 values('10000000-0000-4000-8000-000000000001',%L,'CROSS','خاطئ','OTHER','KG',
 '00000000-0000-4000-8000-000000000001','gf23-cross-sector-direct',repeat('b',64))
$q$,:'gf23_ag_project')) like '%livestock project not found%'
 then 1 else 0 end as privileged_wrong_sector_rejected;

-- New operational facts create no hidden Finance/commercial side effects.
select 1/case when (select count(*) from journal_batches)=:'gf23_jb_before'
 and (select count(*) from journal_lines)=:'gf23_jl_before'
 and (select count(*) from project_payments)=:'gf23_pay_before'
 and not exists(select 1 from livestock_quantity_event_types where code in ('SALE_OUT','PURCHASE_IN'))
 then 1 else 0 end as no_finance_or_commercial_side_effect;

select 'GF-023 Livestock Operations Completion PASS' result;
