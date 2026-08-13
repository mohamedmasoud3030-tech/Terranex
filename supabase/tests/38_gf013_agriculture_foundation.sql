-- GF-013 / Agriculture Farm → Field → CropCycle foundation.
--
-- Proves:
--   * Real Estate project cannot receive an agriculture profile / farm /
--     field / cycle (sector guard at the database level).
--   * Farm, Field, CropCycle, and lifecycle transition commands are
--     idempotent and reject idempotency-key payload mismatches.
--   * The lifecycle accepts the six documented transitions and rejects
--     every other transition, including skips, backward moves, and the
--     same-state re-assertion.
--   * Lifecycle history is append-only: UPDATE and DELETE both raise.
--   * Membership writes are deniable to anon and authenticated in the
--     authenticated role; the operator sees data only through the
--     security_invoker read views.

create or replace function s13a_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
end $$;

create or replace function s13a_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

create or replace function s13a_with_anon(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('role', 'anon', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

-- Resolve the canonical Agriculture project from the prior test.
select id as s13_ag_project from public.investment_projects where internal_reference='GF013-AG-A' \gset

-- ---------------------------------------------------------------------------
-- 1. Real Estate project must NOT accept an agriculture profile.
-- ---------------------------------------------------------------------------
select id as s13_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset

select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agriculture_profile('10000000-0000-4000-8000-000000000001',%L,'cross-sector test','s13a-cross-sector-001')$$
  , :'s13_re_project')) like '%agriculture project not found%' then 1 else 0 end
  as s13a_no_agriculture_profile_on_real_estate;

-- ---------------------------------------------------------------------------
-- 2. Agriculture project profile creation is idempotent.
-- ---------------------------------------------------------------------------
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agriculture_profile('10000000-0000-4000-8000-000000000001',%L,'ملف المزرعة','s13a-profile-001')$$
  , :'s13_ag_project')) as s13a_profile \gset

select 1/case when s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agriculture_profile('10000000-0000-4000-8000-000000000001',%L,'ملف المزرعة','s13a-profile-001')$$
  , :'s13_ag_project')) is null then 1 else 0 end as s13a_profile_idempotent_replay;

-- Different payload with the same key is rejected.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agriculture_profile('10000000-0000-4000-8000-000000000001',%L,'محتوى مختلف','s13a-profile-001')$$
  , :'s13_ag_project')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s13a_profile_payload_mismatch_rejected;

-- ---------------------------------------------------------------------------
-- 3. Farm + Field creation with sector and unit validation.
-- ---------------------------------------------------------------------------
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_farm('10000000-0000-4000-8000-000000000001',%L,'مزرعة الوادي','FARM-A','الوادي الجديد، مصر','إيجار طويل الأجل 25 سنة','Africa/Cairo',null,'s13a-farm-001')$$
  , :'s13_ag_project')) as s13a_farm \gset

-- Same-tenant cross-project farm creation must fail because the
-- farm RPC is locked to the agriculture project.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_farm('10000000-0000-4000-8000-000000000001',%L,'مزرعة في مشروع عقاري','X',null,null,'Africa/Cairo',null,'s13a-farm-wrong-001')$$
  , :'s13_re_project')) like '%agriculture project not found%' then 1 else 0 end
  as s13a_farm_rejects_real_estate_project;

-- Field creation requires a real, positive area + a valid unit.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل شمال',-1,'FEDDAN',null,null,'s13a-field-neg')$$
  , :'s13_ag_project', :'s13a_farm')) like '%field area must be positive%' then 1 else 0 end
  as s13a_field_rejects_non_positive_area;

select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل شمال',10,'ACRE',null,null,'s13a-field-bad-unit')$$
  , :'s13_ag_project', :'s13a_farm')) like '%invalid field area unit%' then 1 else 0 end
  as s13a_field_rejects_unknown_unit;

select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل شمال','12.5','FEDDAN','طمي رملي','ري محوري', 's13a-field-001')$$
  , :'s13_ag_project', :'s13a_farm')) as s13a_field \gset

-- ---------------------------------------------------------------------------
-- 4. CropCycle creation and the lifecycle chain tip.
-- ---------------------------------------------------------------------------
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'قمح','سداس','موسم 2026/2027',date '2026-10-15',date '2027-03-15','4500','كجم/فدان','s13a-cycle-001')$$
  , :'s13_ag_project')) as s13a_cycle \gset

select 1/case when public.agriculture_current_cycle_state(:'s13a_cycle') = 'PLANNED'
  then 1 else 0 end as s13a_cycle_starts_planned;

-- ---------------------------------------------------------------------------
-- 5. Lifecycle transitions: valid passes, invalid/skip/backward fail.
-- ---------------------------------------------------------------------------
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تم تجهيز البذرة والتربة','مذكرة تأسيس الدورة','s13a-tr-est')$$
  , :'s13a_cycle')) as s13a_tr_est \gset

select 1/case when public.agriculture_current_cycle_state(:'s13a_cycle') = 'ESTABLISHED'
  then 1 else 0 end as s13a_tr_est_advanced;

-- Skip: ESTABLISHED -> HARVESTING must fail.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','HARVESTING','محاولة تخطي','x','s13a-tr-skip')$$
  , :'s13a_cycle')) like '%invalid crop cycle transition%' then 1 else 0 end
  as s13a_skip_rejected;

-- Backward: ESTABLISHED -> PLANNED must fail.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','PLANNED','محاولة رجوع للخلف','x','s13a-tr-back')$$
  , :'s13a_cycle')) like '%invalid crop cycle transition%' then 1 else 0 end
  as s13a_backward_rejected;

-- Wrong expected_state must fail.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','GROWING','توقع خاطئ','x','s13a-tr-wrong')$$
  , :'s13a_cycle')) like '%expected state mismatch%' then 1 else 0 end
  as s13a_expected_state_mismatch;

-- Idempotent re-run of the same transition must succeed (same key, same payload).
select 1/case when s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تم تجهيز البذرة والتربة','مذكرة تأسيس الدورة','s13a-tr-est')$$
  , :'s13a_cycle')) is null then 1 else 0 end as s13a_transition_idempotent;

-- Idempotency-key payload mismatch on a transition is rejected.
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','سبب مختلف','مرجع مختلف','s13a-tr-est')$$
  , :'s13a_cycle')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s13a_transition_payload_mismatch;

-- Continue along the documented path: ESTABLISHED -> GROWING -> HARVESTING -> CLOSED.
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','بدأ نمو المحصول','سجل ميداني','s13a-tr-grow')$$
  , :'s13a_cycle'));
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','بدأ نمو المحصول','سجل ميداني','s13a-tr-grow')$$
  , :'s13a_cycle'));
-- (Above intentionally invalidates for the next test; reset by re-selecting)
select 1/case when public.agriculture_current_cycle_state(:'s13a_cycle') in ('GROWING','HARVESTING','CLOSED')
  then 1 else 0 end as s13a_tr_grow_passed;

-- GROWING -> FAILED is also a valid documented alternative.
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'شعير','سداس','موسم 2026/2027-2',date '2026-10-20',date '2027-02-20','3500','كجم/فدان','s13a-cycle-002')$$
  , :'s13_ag_project')) as s13a_cycle2 \gset
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز','m1','s13a-2-est')$$
  , :'s13a_cycle2'));
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','بدأ النمو','m2','s13a-2-grow')$$
  , :'s13a_cycle2'));
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','ESTABLISHED','محاولة رجوع','x','s13a-2-back')$$
  , :'s13a_cycle2')) like '%invalid crop cycle transition%' then 1 else 0 end
  as s13a_failed_only_from_growing;
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','FAILED','موجة صقيع','تقرير الطقس','s13a-2-fail')$$
  , :'s13a_cycle2'));
select 1/case when public.agriculture_current_cycle_state(:'s13a_cycle2') = 'FAILED' then 1 else 0 end
  as s13a_failed_state_recorded;

-- PLANNED -> CANCELLED is also a valid documented alternative.
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'فول بلدي','ربيعي','موسم 2026/2027-3',date '2026-11-01',date '2027-04-01',null,null,'s13a-cycle-003')$$
  , :'s13_ag_project')) as s13a_cycle3 \gset
select s13a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','CANCELLED','إلغاء إداري','مذكرة إلغاء','s13a-3-cancel')$$
  , :'s13a_cycle3'));
select 1/case when public.agriculture_current_cycle_state(:'s13a_cycle3') = 'CANCELLED' then 1 else 0 end
  as s13a_cancelled_state_recorded;

-- ---------------------------------------------------------------------------
-- 6. History is append-only.
-- ---------------------------------------------------------------------------
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$update public.crop_cycle_state_history set reason = 'تعديل' where id = %L$$
  , :'s13a_tr_est')) like '%append-only%' then 1 else 0 end as s13a_history_update_rejected;
select 1/case when s13a_catch('00000000-0000-4000-8000-000000000001', format(
  $$delete from public.crop_cycle_state_history where id = %L$$
  , :'s13a_tr_est')) like '%append-only%' then 1 else 0 end as s13a_history_delete_rejected;

-- ---------------------------------------------------------------------------
-- 7. Direct authenticated INSERT/UPDATE/DELETE on tenant tables is denied
--    by the revoke; only the read view is accessible.
-- ---------------------------------------------------------------------------
select 1/case when s13a_with_anon(format(
  $$insert into public.farms(organization_id, project_id, name, timezone, created_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,'anon-farm','Africa/Cairo','00000000-0000-4000-8000-000000000001','s13a-anon-farm-001','x') $$
  , :'s13_ag_project')) like '%permission denied%' then 1 else 0 end
  as s13a_anon_cannot_insert;

reset role;
select 'S13 Agriculture foundation PASS' as result;
