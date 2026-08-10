insert into auth.users values ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000001','ألف'),('20000000-0000-4000-8000-000000000002','باء');
insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','OWNER'),('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','OWNER');
create function public.s0_rejects_cross_tenant() returns boolean language plpgsql as $$ begin perform public.create_investment_project('20000000-0000-4000-8000-000000000002','محاولة تسريب',null,null); return false; exception when others then return sqlerrm='forbidden'; end $$;
grant execute on function public.s0_rejects_cross_tenant() to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع ألف',null,null) as project_a \gset
select 1 / case when (select count(*) from public.investment_projects)=1 then 1 else 0 end as own_project_visible;
select 1 / case when public.s0_rejects_cross_tenant() then 1 else 0 end as cross_tenant_write_denied;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
select 1 / case when (select count(*) from public.investment_projects where id=:'project_a')=0 then 1 else 0 end as cross_tenant_read_denied;
reset role; select 'S0 tenant isolation PASS' as result;
