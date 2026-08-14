-- GF-020 foundation, lifecycle, isolation and Finance/ownership side-effect proof.
create or replace function gf20_run(p_user uuid,p_sql text) returns uuid language plpgsql as $$declare r uuid;begin perform set_config('request.jwt.claim.sub',p_user::text,true);perform set_config('role','authenticated',false);execute p_sql into r;reset role;return r;end$$;
create or replace function gf20_catch(p_user uuid,p_sql text) returns text language plpgsql as $$declare m text;begin perform set_config('request.jwt.claim.sub',p_user::text,true);perform set_config('role','authenticated',false);begin execute p_sql;exception when others then m:=sqlerrm;reset role;return m;end;reset role;return 'NO_EXCEPTION';end$$;
create or replace function gf20_count(p_user uuid,p_sql text) returns bigint language plpgsql as $$declare r bigint;begin perform set_config('request.jwt.claim.sub',p_user::text,true);perform set_config('role','authenticated',false);execute p_sql into r;reset role;return r;end$$;

select gf20_run('00000000-0000-4000-8000-000000000001',$q$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع الثروة الحيوانية الاصطناعي','GF020-LS-A','synthetic GF-020','LIVESTOCK')$q$) project_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',$q$select public.create_investment_project('10000000-0000-4000-8000-000000000001','قطاع خاطئ',null,null,'DAIRY')$q$) like '%invalid sector%' then 1 else 0 end;
select 1/case when (select count(*) from investment_projects where sector in('REAL_ESTATE','AGRICULTURE'))>0 then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,'ملف تشغيل اصطناعي','gf20-profile-001')$q$,:'project_id')) profile_id \gset
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,'ملف تشغيل اصطناعي','gf20-profile-001')$q$,:'project_id'))=:'profile_id' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,'مختلف','gf20-profile-001')$q$,:'project_id')) like '%idempotency key payload mismatch%' then 1 else 0 end;
select id re_project from investment_projects where sector='REAL_ESTATE' limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,null,'gf20-profile-re')$q$,:'re_project')) like '%livestock project not found%' then 1 else 0 end;
select id ag_project from investment_projects where sector='AGRICULTURE' limit 1 \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_profile('10000000-0000-4000-8000-000000000001',%L,null,'gf20-profile-ag')$q$,:'ag_project')) like '%livestock project not found%' then 1 else 0 end;

select (select count(*) from journal_batches) jb_before,(select count(*) from project_payments) pay_before,(select count(*) from property_assets) prop_before,(select count(*) from agricultural_land_assets) land_before \gset
select gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_site('10000000-0000-4000-8000-000000000001',%L,'مزرعة التسمين','SITE-A','FARM','الجيزة',null,'gf20-site-001')$q$,:'project_id')) site_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_site('10000000-0000-4000-8000-000000000001',%L,'خطأ','SITE-X','DAIRY',null,null,'gf20-site-bad')$q$,:'project_id')) like '%invalid livestock site type%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_site('10000000-0000-4000-8000-000000000001',%L,'مكرر','SITE-A','BARN',null,null,'gf20-site-dup')$q$,:'project_id')) like '%reference already exists%' then 1 else 0 end;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_site('10000000-0000-4000-8000-000000000001',%L,'مزرعة التسمين','SITE-A','FARM','الجيزة',null,'gf20-site-001')$q$,:'project_id'))=:'site_id' then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_herd('10000000-0000-4000-8000-000000000001',%L,%L,'قطيع أبقار التسمين','HERD-A','CATTLE','MEAT','بلدي','gf20-herd-001')$q$,:'project_id',:'site_id')) herd_id \gset
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_herd('10000000-0000-4000-8000-000000000001',%L,%L,'خطأ','HERD-X','CAMEL','MEAT',null,'gf20-herd-species')$q$,:'project_id',:'site_id')) like '%invalid livestock species%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_herd('10000000-0000-4000-8000-000000000001',%L,%L,'خطأ','HERD-X','CATTLE','DAIRY',null,'gf20-herd-purpose')$q$,:'project_id',:'site_id')) like '%invalid livestock purpose%' then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'دفعة أغسطس 2026','PURCHASED',date '2026-08-01',60,'MALE','بلدي','180','KG','SAMPLED_AVERAGE','محضر استلام اصطناعي',null,'gf20-cohort-001')$q$,:'project_id',:'herd_id')) cohort_id \gset
select 1/case when (select opening_headcount=60 and lifecycle_state='PLANNED' and species='CATTLE' and site_name='مزرعة التسمين' from livestock_cohorts_read where id=:'cohort_id') then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'ZERO','BORN',current_date,0,null,null,null,null,null,null,null,'gf20-cohort-zero')$q$,:'project_id',:'herd_id')) like '%invalid livestock opening headcount%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'BAD','WRONG',current_date,1,null,null,null,null,null,null,null,'gf20-cohort-origin')$q$,:'project_id',:'herd_id')) like '%invalid livestock cohort origin%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'WEIGHT','BORN',current_date,1,null,null,-1,'KG','ESTIMATED',null,null,'gf20-cohort-weight')$q$,:'project_id',:'herd_id')) like '%invalid livestock opening weight%' then 1 else 0 end;
-- Fractional count cannot resolve an integer RPC signature.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.create_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'FRACTION','BORN',current_date,1.5,null,null,null,null,null,null,null,'gf20-fraction')$q$,:'project_id',:'herd_id')) <> 'NO_EXCEPTION' then 1 else 0 end;

select gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.transition_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE','بدء التشغيل','محضر تفعيل','gf20-active-001')$q$,:'project_id',:'cohort_id')) transition_id \gset
select 1/case when (select lifecycle_state='ACTIVE' from livestock_cohorts_read where id=:'cohort_id') then 1 else 0 end;
select 1/case when gf20_run('00000000-0000-4000-8000-000000000001',format($q$select public.transition_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'PLANNED','ACTIVE','بدء التشغيل','محضر تفعيل','gf20-active-001')$q$,:'project_id',:'cohort_id'))=:'transition_id' then 1 else 0 end;
select 1/case when (select count(*) from livestock_cohort_state_history where cohort_id=:'cohort_id')=2 then 1 else 0 end;
select 1/case when (select count(*) from audit_events where entity_id=:'cohort_id' and event_type='LIVESTOCK_COHORT_STATE_CHANGED')=1 then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$select public.transition_livestock_cohort('10000000-0000-4000-8000-000000000001',%L,%L,'ACTIVE','PLANNED','رجوع غير مسموح',null,'gf20-backward')$q$,:'project_id',:'cohort_id')) like '%invalid livestock cohort transition%' then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001',format($q$update public.livestock_cohorts set opening_headcount=61 where id=%L$q$,:'cohort_id')) like '%permission denied%' then 1 else 0 end;

-- Tenant B sees no A rows and cannot create/transition through A hierarchy.
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002','select count(*) from public.livestock_sites_read')=0 then 1 else 0 end;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002','select count(*) from public.livestock_herds_read')=0 then 1 else 0 end;
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002','select count(*) from public.livestock_cohorts_read')=0 then 1 else 0 end;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002',format($q$select public.transition_livestock_cohort('20000000-0000-4000-8000-000000000001',%L,%L,'ACTIVE','PLANNED','x',null,'gf20-tenant-b')$q$,:'project_id',:'cohort_id')) <> 'NO_EXCEPTION' then 1 else 0 end;

select 1/case when (select count(*) from journal_batches)=:'jb_before' and (select count(*) from project_payments)=:'pay_before' and (select count(*) from property_assets)=:'prop_before' and (select count(*) from agricultural_land_assets)=:'land_before' then 1 else 0 end;
select 'GF-020 Livestock foundation PASS' result;
