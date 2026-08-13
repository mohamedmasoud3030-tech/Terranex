-- GF-013 / Agriculture two-tenant isolation.
--
-- Proves that Tenant B cannot read or mutate Tenant A's agriculture
-- records through any server-authoritative command, and that the
-- application cannot bypass it via the read views either.

create or replace function s13c_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s13c_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s13c_catch(p_user uuid, p_sql text)
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

-- Ensure tenant B exists and has an OWNER membership.
insert into public.organizations(id, name)
  values ('20000000-0000-4000-8000-000000000099', 'منظمة باء-ب')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role)
  values ('20000000-0000-4000-8000-000000000099', '00000000-0000-4000-8000-000000000002', 'OWNER')
  on conflict (organization_id, user_id) do nothing;

-- Tenant A's agriculture project and a farm id from earlier suites.
select id as s13c_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s13c_farm    from public.farms where internal_reference='FARM-A' \gset

-- 1. Tenant B can create its own Agriculture project, but not inside Tenant A.
select 1/case when s13c_run('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_investment_project('20000000-0000-4000-8000-000000000099','مشروع باء','GF013-AG-B','x','AGRICULTURE')$$
)) is not null then 1 else 0 end
  as s13c_tenant_b_creates_own_agriculture;

-- 2. Tenant B cannot read Tenant A's project through the public table.
select 1/case when s13c_count('00000000-0000-4000-8000-000000000002', format(
  $$select count(*) from public.investment_projects where id = %L$$
  , :'s13c_project')) = 0 then 1 else 0 end as s13c_tenant_b_cannot_read_tenant_a_project;

-- 3. Tenant B cannot run agriculture commands on Tenant A's project.
select 1/case when s13c_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_agriculture_profile('20000000-0000-4000-8000-000000000099',%L,'x','s13c-cross-001')$$
  , :'s13c_project')) is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s13c_tenant_b_agriculture_profile_rejected;

select 1/case when s13c_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_farm('20000000-0000-4000-8000-000000000099',%L,'cross-tenant','x',null,null,'Africa/Cairo',null,'s13c-cross-farm')$$
  , :'s13c_project')) is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s13c_tenant_b_farm_rejected;

select 1/case when s13c_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_field('20000000-0000-4000-8000-000000000099',%L,%L,'cross','1','FEDDAN',null,null,'s13c-cross-field')$$
  , :'s13c_project', :'s13c_farm')) is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s13c_tenant_b_field_rejected;

-- 4. Tenant B's read views see no Tenant A rows.
select 1/case when s13c_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.farms_read') = 0 then 1 else 0 end as s13c_tenant_b_cannot_read_farms;
select 1/case when s13c_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.fields_read') = 0 then 1 else 0 end as s13c_tenant_b_cannot_read_fields;
select 1/case when s13c_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.crop_cycles_read') = 0 then 1 else 0 end as s13c_tenant_b_cannot_read_cycles;
select 1/case when s13c_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.crop_cycle_timeline_read') = 0 then 1 else 0 end as s13c_tenant_b_cannot_read_timeline;

reset role;
select 'S13 two-tenant Agriculture isolation PASS' as result;
