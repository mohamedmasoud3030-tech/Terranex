begin;

select 1 / case when to_regclass('public.accounting_periods_scope_start_version_unique') is not null
  and to_regclass('public.accounting_periods_authoritative_unique') is null
then 1 else 0 end as sequential_period_index_replaced;

insert into auth.users(id,email)
values ('00000000-0000-0000-0000-000000006001','s6-sequential-periods@test.invalid')
on conflict (id) do nothing;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000006001',true);
set local role authenticated;

select public.create_organization('S6 sequential periods test') as org_id \gset
select public.create_investment_project(:'org_id'::uuid,'Sequential accounting periods test',null,null) as project_id \gset

select public.s6_create_accounting_period(
  :'org_id'::uuid, :'project_id'::uuid, date '2026-07-01', date '2026-07-31'
) as july_id \gset

reset role;
update public.accounting_periods
set status='CLOSED', closed_at=now(), closed_by='00000000-0000-0000-0000-000000006001'::uuid
where id=:'july_id'::uuid;
set local role authenticated;

select public.s6_create_accounting_period(
  :'org_id'::uuid, :'project_id'::uuid, date '2026-08-01', date '2026-08-31'
) as august_id \gset

reset role;

select 1 / case when (
  select count(*) from public.accounting_periods
  where project_id=:'project_id'::uuid and version=1
) = 2 then 1 else 0 end as two_independent_v1_periods_allowed;

select 1 / case when (
  select count(*) from public.accounting_periods
  where project_id=:'project_id'::uuid and status='OPEN'
) = 1 then 1 else 0 end as one_open_period_invariant_preserved;

select 1 / case when not exists (
  select 1
  from public.accounting_periods a
  join public.accounting_periods b
    on b.project_id=a.project_id and b.id<>a.id
   and daterange(a.start_date,a.end_date,'[]') && daterange(b.start_date,b.end_date,'[]')
  where a.project_id=:'project_id'::uuid
) then 1 else 0 end as sequential_periods_do_not_overlap;

rollback;

select 'S6 sequential accounting periods SQL PASS' as result;
