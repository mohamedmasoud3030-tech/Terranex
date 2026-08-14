-- GF-020 foundation, isolation, replay and Finance/ownership side-effect proof.
create or replace function gf20_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare r uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into r;
  reset role;
  return r;
end $$;

create or replace function gf20_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare m text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin execute p_sql;
  exception when others then m := sqlerrm; reset role; return m;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

create or replace function gf20_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare r bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into r;
  reset role;
  return r;
end $$;

select gf20_run('00000000-0000-4000-8000-000000000001', $q$
  select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001', 'مشروع الثروة الحيوانية الاصطناعي',
    'GF020-LS-A', 'synthetic GF-020', 'LIVESTOCK'
  )$q$) project_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', $q$
  select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001', 'قطاع خاطئ', null, null, 'DAIRY'
  )$q$) like '%invalid sector%' then 1 else 0 end;
select 1/case when (
  select count(*) from investment_projects where sector in ('REAL_ESTATE','AGRICULTURE')
) > 0 then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_profile(
    '10000000-0000-4000-8000-000000000001', %L,
    'ملف تشغيل اصطناعي', 'gf20-profile-001'
  )$q$, :'project_id')) profile_id \gset
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_profile(
    '10000000-0000-4000-8000-000000000001', %L,
    'ملف تشغيل اصطناعي', 'gf20-profile-001'
  )$q$, :'project_id')) = :'profile_id' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_profile(
    '10000000-0000-4000-8000-000000000001', %L, 'مختلف', 'gf20-profile-001'
  )$q$, :'project_id')) like '%idempotency key payload mismatch%' then 1 else 0 end;

select id re_project from investment_projects where sector = 'REAL_ESTATE' limit 1 \gset
select id ag_project from investment_projects where sector = 'AGRICULTURE' limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_profile(
    '10000000-0000-4000-8000-000000000001', %L, null, 'gf20-profile-re'
  )$q$, :'re_project')) like '%livestock project not found%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_profile(
    '10000000-0000-4000-8000-000000000001', %L, null, 'gf20-profile-ag'
  )$q$, :'ag_project')) like '%livestock project not found%' then 1 else 0 end;

select (select count(*) from journal_batches) jb_before,
       (select count(*) from project_payments) pay_before,
       (select count(*) from property_assets) prop_before,
       (select count(*) from agricultural_land_assets) land_before \gset

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_site(
    '10000000-0000-4000-8000-000000000001', %L, 'مزرعة التسمين',
    'SITE-A', 'FARM', 'الجيزة', null, 'gf20-site-001'
  )$q$, :'project_id')) site_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_site(
    '10000000-0000-4000-8000-000000000001', %L, 'خطأ',
    'SITE-X', 'DAIRY', null, null, 'gf20-site-bad'
  )$q$, :'project_id')) like '%invalid livestock site type%' then 1 else 0 end;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_site(
    '10000000-0000-4000-8000-000000000001', %L, 'مزرعة التسمين',
    'SITE-A', 'FARM', 'الجيزة', null, 'gf20-site-001'
  )$q$, :'project_id')) = :'site_id' then 1 else 0 end;

-- Herd is project/species/purpose identity and has no Site argument.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع أبقار التسمين',
    'HERD-A', 'CATTLE', 'MEAT', 'بلدي', 'gf20-herd-001'
  )$q$, :'project_id')) herd_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'خطأ',
    'HERD-X', 'CAMEL', 'MEAT', null, 'gf20-herd-species'
  )$q$, :'project_id')) like '%invalid livestock species%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_herd(
    '10000000-0000-4000-8000-000000000001', %L, 'خطأ',
    'HERD-X', 'CATTLE', 'DAIRY', null, 'gf20-herd-purpose'
  )$q$, :'project_id')) like '%invalid livestock purpose%' then 1 else 0 end;

-- Cohort requires an immutable opening placement at a same-project Site.
select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة أغسطس 2026', 'PURCHASED', date '2026-08-01', 60, 'MALE', 'بلدي',
    '180', 'KG', 'ESTIMATED', 'محضر استلام اصطناعي', null, 'gf20-cohort-001'
  )$q$, :'project_id', :'herd_id', :'site_id')) cohort_id \gset
select 1/case when (
  select opening_headcount = 60 and lifecycle_state = 'PLANNED'
    and species = 'CATTLE' and initial_site_name = 'مزرعة التسمين'
  from livestock_cohorts_read where id = :'cohort_id'
) then 1 else 0 end;
select 1/case when (
  select count(*) from livestock_cohort_initial_placements
  where cohort_id = :'cohort_id' and site_id = :'site_id'
) = 1 then 1 else 0 end;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'دفعة أغسطس 2026', 'PURCHASED', date '2026-08-01', 60, 'MALE', 'بلدي',
    '180', 'KG', 'ESTIMATED', 'محضر استلام اصطناعي', null, 'gf20-cohort-001'
  )$q$, :'project_id', :'herd_id', :'site_id')) = :'cohort_id' then 1 else 0 end;
select 1/case when (
  select count(*) from livestock_cohorts where id = :'cohort_id'
) = 1 and (
  select count(*) from livestock_cohort_initial_placements where cohort_id = :'cohort_id'
) = 1 and (
  select count(*) from audit_events
  where entity_id = :'cohort_id' and event_type = 'LIVESTOCK_COHORT_CREATED'
) = 1 then 1 else 0 end;

select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'ZERO', 'BORN', current_date, 0, null, null, null, null, null, null, null,
    'gf20-cohort-zero'
  )$q$, :'project_id', :'herd_id', :'site_id')) like '%invalid livestock opening headcount%'
  then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  select public.create_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, %L,
    'SAMPLE', 'BORN', current_date, 1, null, null, 100, 'KG',
    'SAMPLED_AVERAGE', null, null, 'gf20-cohort-sample'
  )$q$, :'project_id', :'herd_id', :'site_id')) like '%invalid livestock opening weight%'
  then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'بدء التشغيل', 'محضر تفعيل', 'gf20-active-001'
  )$q$, :'project_id', :'cohort_id')) transition_id \gset
select 1/case when (
  select lifecycle_state = 'ACTIVE' from livestock_cohorts_read where id = :'cohort_id'
) then 1 else 0 end;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001', format($q$
  select public.transition_livestock_cohort(
    '10000000-0000-4000-8000-000000000001', %L, %L, 'PLANNED', 'ACTIVE',
    'بدء التشغيل', 'محضر تفعيل', 'gf20-active-001'
  )$q$, :'project_id', :'cohort_id')) = :'transition_id' then 1 else 0 end;
select 1/case when (
  select count(*) from livestock_cohort_state_history where cohort_id = :'cohort_id'
) = 2 and (
  select count(*) from audit_events
  where entity_id = :'cohort_id' and event_type = 'LIVESTOCK_COHORT_STATE_CHANGED'
) = 1 then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_cohorts set opening_headcount = 61 where id = %L
$q$, :'cohort_id')) like '%permission denied%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_cohort_initial_placements set site_id = %L where cohort_id = %L
$q$, :'site_id', :'cohort_id')) like '%permission denied%' then 1 else 0 end;

-- Tenant B cannot see or command Tenant A placement/hierarchy.
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.livestock_sites_read') = 0 then 1 else 0 end;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.livestock_herds_read') = 0 then 1 else 0 end;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.livestock_cohorts_read') = 0 then 1 else 0 end;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.livestock_cohort_initial_placements_read') = 0
  then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.transition_livestock_cohort(
    '20000000-0000-4000-8000-000000000001', %L, %L, 'ACTIVE', 'PLANNED',
    'محاولة غير مسموحة', null, 'gf20-tenant-b'
  )$q$, :'project_id', :'cohort_id')) <> 'NO_EXCEPTION' then 1 else 0 end;

-- No Finance, ownership, valuation, or other-sector side effect.
select 1/case when (select count(*) from journal_batches) = :'jb_before'
  and (select count(*) from project_payments) = :'pay_before'
  and (select count(*) from property_assets) = :'prop_before'
  and (select count(*) from agricultural_land_assets) = :'land_before'
  then 1 else 0 end;
select 1/case when not exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'livestock_cohorts'
    and column_name in ('current_headcount','current_site_id','carrying_value')
) then 1 else 0 end;

select 'GF-020 Livestock foundation PASS' result;
