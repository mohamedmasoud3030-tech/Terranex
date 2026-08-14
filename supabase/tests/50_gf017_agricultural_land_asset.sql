-- GF-017 / Agricultural Land Asset, Acquisition & Control.
-- End-to-end domain, finance-isolation, RLS, idempotency and linkage proof.

create or replace function s17_run(p_user uuid,p_sql text) returns uuid
language plpgsql as $$ declare v uuid; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v;
  reset role;
  return v;
end $$;

create or replace function s17_catch(p_user uuid,p_sql text) returns text
language plpgsql as $$ declare v text; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  begin execute p_sql; exception when others then v:=sqlerrm; reset role; return v; end;
  reset role; return 'NO_EXCEPTION';
end $$;

create or replace function s17_count(p_user uuid,p_sql text) returns bigint
language plpgsql as $$ declare v bigint; begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v;
  reset role;
  return v;
end $$;

create or replace function s17_owner_catch(p_sql text) returns text
language plpgsql as $$ declare v text; begin
  begin execute p_sql; exception when others then return sqlerrm; end;
  return 'NO_EXCEPTION';
end $$;

select id as s17_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s17_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset
select id as s17_farm from public.farms where internal_reference='FARM-A' \gset
select id as s17_party from public.parties where organization_id='10000000-0000-4000-8000-000000000001' order by created_at limit 1 \gset

-- Historical Farms survive without fabricated land assets or links.
select 1/case when (select count(*) from public.farms where project_id=:'s17_project')>0
  and (select count(*) from public.agricultural_land_assets where project_id=:'s17_project')=0
  and (select count(*) from public.farm_land_asset_links where project_id=:'s17_project')=0
then 1 else 0 end as s17_existing_farms_not_fabricated;

select count(*) as s17_journals_before from public.journal_batches \gset
select count(*) as s17_payments_before from public.project_payments \gset
select count(*) as s17_contributions_before from public.contributions \gset
select count(*) as s17_obligations_before from public.cost_obligations \gset

-- PURCHASED with contractual consideration (EGP 500,000.00), but no inferred
-- payment, journal, carrying amount or CropCycle cost.
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض النيل','LAND-001','حيازة 123',
    25,'FEDDAN','المنيا، مصر','PURCHASED',date '2026-08-01',null,%L,
    'عقد شراء LAND-001','مستند مسجل LAND-001',50000000,'EGP',null,'s17-land-purchased')$$,
  :'s17_project',:'s17_party')) as s17_purchased \gset

select 1/case when (
  select control_basis='PURCHASED' and legal_area_quantity=25 and area_unit='FEDDAN'
    and agreed_consideration_minor_units=50000000 and consideration_currency='EGP'
    and recorded_by='00000000-0000-4000-8000-000000000001'
  from public.agricultural_land_assets where id=:'s17_purchased'
) then 1 else 0 end as s17_purchased_created;

-- The remaining bounded control bases preserve their truthful non-ownership
-- meaning and cannot carry purchase consideration.
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض الإيجار','LAND-002',null,
    10,'FEDDAN','بني سويف','LEASED',date '2026-09-01',date '2031-08-31',%L,
    'عقد إيجار LAND-002','نسخة عقد الإيجار',null,null,null,'s17-land-leased')$$,
  :'s17_project',:'s17_party')) as s17_leased \gset
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض عينية','LAND-003',null,
    8,'FEDDAN','الفيوم','CONTRIBUTED_IN_KIND',date '2026-08-15',null,%L,
    'محضر مساهمة عينية','قرار ودليل عيني',null,null,null,'s17-land-inkind')$$,
  :'s17_project',:'s17_party')) as s17_inkind \gset
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض إدارة للغير','LAND-004',null,
    6,'FEDDAN','الوادي الجديد','MANAGED_FOR_OWNER',date '2026-07-01',date '2027-06-30',%L,
    'اتفاق إدارة LAND-004','تفويض إدارة موثق',null,null,null,'s17-land-managed')$$,
  :'s17_project',:'s17_party')) as s17_managed \gset

select 1/case when (
  select array_agg(control_basis order by control_basis)=array[
    'CONTRIBUTED_IN_KIND','LEASED','MANAGED_FOR_OWNER','PURCHASED'
  ]::text[] from public.agricultural_land_assets where project_id=:'s17_project'
) then 1 else 0 end as s17_all_control_bases;

-- True replay happens before mutable/natural-key rejection and emits one audit.
select 1/case when s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض النيل','LAND-001','حيازة 123',
    25,'FEDDAN','المنيا، مصر','PURCHASED',date '2026-08-01',null,%L,
    'عقد شراء LAND-001','مستند مسجل LAND-001',50000000,'EGP',null,'s17-land-purchased')$$,
  :'s17_project',:'s17_party'))=:'s17_purchased' then 1 else 0 end as s17_land_replay;
select 1/case when (select count(*) from public.audit_events
  where event_type='AGRICULTURAL_LAND_ASSET_RECORDED' and entity_id=:'s17_purchased')=1
then 1 else 0 end as s17_land_audit_once;

select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'مرجع مكرر','land-001',null,
    3,'FEDDAN',null,'LEASED',date '2026-09-01',null,%L,
    'عقد مكرر','دليل مكرر كاف',null,null,null,'s17-land-duplicate')$$,
  :'s17_project',:'s17_party'))='agricultural land asset reference already exists'
then 1 else 0 end as s17_duplicate_reference_domain_error;

select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'مساحة صفر','LAND-ZERO',null,
    0,'FEDDAN',null,'LEASED',date '2026-09-01',null,%L,
    'عقد صفر','دليل مساحة صفر',null,null,null,'s17-land-zero')$$,
  :'s17_project',:'s17_party'))='agricultural land area must be positive'
then 1 else 0 end as s17_area_positive;

select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أساس خاطئ','LAND-BAD',null,
    1,'FEDDAN',null,'OWNED',date '2026-09-01',null,%L,
    'عقد أساس','دليل أساس خاطئ',null,null,null,'s17-land-basis')$$,
  :'s17_project',:'s17_party'))='invalid agricultural land control basis'
then 1 else 0 end as s17_invalid_basis;

select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'أرض عقارية','LAND-RE',null,
    1,'FEDDAN',null,'PURCHASED',date '2026-09-01',null,%L,
    'عقد عقاري','دليل عقاري كاف',null,null,null,'s17-land-re')$$,
  :'s17_re_project',:'s17_party'))='agriculture project not found'
then 1 else 0 end as s17_real_estate_project_rejected;

select 1/case when s17_catch('00000000-0000-4000-8000-000000000002',format(
  $$select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,'محاولة مستأجر','LAND-TENANT',null,
    1,'FEDDAN',null,'LEASED',date '2026-09-01',null,%L,
    'عقد محاولة','دليل محاولة كاف',null,null,null,'s17-land-tenant')$$,
  :'s17_project',:'s17_party'))='forbidden'
then 1 else 0 end as s17_tenant_b_write_rejected;

-- Same-project Farm link succeeds once and is replay-safe.
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.link_farm_to_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,'s17-farm-link-001')$$,
  :'s17_project',:'s17_purchased',:'s17_farm')) as s17_link \gset
select 1/case when s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.link_farm_to_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,'s17-farm-link-001')$$,
  :'s17_project',:'s17_purchased',:'s17_farm'))=:'s17_link'
then 1 else 0 end as s17_link_replay;
select 1/case when (select count(*) from public.audit_events
  where event_type='FARM_LINKED_TO_AGRICULTURAL_LAND_ASSET' and entity_id=:'s17_link')=1
then 1 else 0 end as s17_link_audit_once;

-- Create a second Agriculture project in the same tenant to prove project
-- coherence (not merely tenant coherence) on the Farm link.
select s17_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001','مشروع أرض آخر','GF017-AG-OTHER',null,'AGRICULTURE')$$
) as s17_other_project \gset
select s17_run('00000000-0000-4000-8000-000000000001',format(
  $$select public.create_farm('10000000-0000-4000-8000-000000000001',%L,
    'مزرعة مشروع آخر','GF017-FARM-OTHER',null,null,'Africa/Cairo',null,'s17-other-farm')$$,
  :'s17_other_project')) as s17_other_farm \gset
select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$select public.link_farm_to_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',%L,%L,%L,'s17-cross-project-link')$$,
  :'s17_project',:'s17_purchased',:'s17_other_farm'))='farm not found in project'
then 1 else 0 end as s17_cross_project_farm_rejected;

-- RLS/default-deny and immutable material facts.
select 1/case when s17_count('00000000-0000-4000-8000-000000000002',format(
  $$select count(*) from public.agricultural_land_assets_read where project_id=%L$$,:'s17_project'))=0
then 1 else 0 end as s17_tenant_b_rls;
select 1/case when s17_catch('00000000-0000-4000-8000-000000000001',format(
  $$update public.agricultural_land_assets set name='اختراق' where id=%L$$,:'s17_purchased'))
  like '%permission denied%' then 1 else 0 end as s17_direct_dml_denied;
select 1/case when s17_owner_catch(format(
  $$delete from public.farm_land_asset_links where id=%L$$,:'s17_link'))
  ='agricultural land asset and farm linkage facts are immutable'
then 1 else 0 end as s17_link_append_only;

-- Finance isolation, including no fake cash Contribution for in-kind land.
select 1/case when (select count(*) from public.journal_batches)=:'s17_journals_before'::bigint
  and (select count(*) from public.project_payments)=:'s17_payments_before'::bigint
  and (select count(*) from public.contributions)=:'s17_contributions_before'::bigint
  and (select count(*) from public.cost_obligations)=:'s17_obligations_before'::bigint
  and not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='agricultural_land_assets'
      and column_name in ('paid_minor_units','carrying_amount_minor_units','valuation_minor_units','crop_cycle_cost_minor_units'))
then 1 else 0 end as s17_no_automatic_finance_or_cycle_cost;

-- Real Estate remains structurally unchanged and separate.
select 1/case when to_regclass('public.property_assets') is not null
  and to_regclass('public.property_acquisitions') is not null
  and to_regclass('public.property_control_records') is not null
  and not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='property_assets' and column_name='agricultural_land_asset_id')
  and to_regclass('public.assets') is null and to_regclass('public.universal_assets') is null
then 1 else 0 end as s17_real_estate_alignment_unchanged;

reset role;
select 'GF-017 agricultural land asset PASS' as result;
