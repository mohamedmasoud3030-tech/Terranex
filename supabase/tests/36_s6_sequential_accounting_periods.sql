begin;

select 1 / case when to_regclass('public.accounting_periods_scope_start_version_unique') is not null
  and to_regclass('public.accounting_periods_authoritative_unique') is null
then 1 else 0 end as sequential_period_index_replaced;

-- This is an index/period-window invariant test, not an authorization test.
-- Use deterministic fixture IDs so it does not depend on psql variable
-- interpolation or command-RPC side effects.
insert into auth.users(id)
values ('00000000-0000-0000-0000-000000006001')
on conflict (id) do nothing;

insert into public.organizations(id,name)
values ('00000000-0000-0000-0000-000000006010','S6 sequential periods test');

insert into public.investment_projects(
  id, organization_id, name, internal_reference, sector, lifecycle_state,
  reporting_currency, description
) values (
  '00000000-0000-0000-0000-000000006020',
  '00000000-0000-0000-0000-000000006010',
  'Sequential accounting periods test',
  'S6-SEQUENTIAL-PERIODS-TEST',
  'REAL_ESTATE', 'DRAFT', 'EGP',
  'Regression fixture for independent monthly period version lineages'
);

insert into public.accounting_periods(
  id, organization_id, project_id, reporting_currency,
  start_date, end_date, status, version,
  opened_by, closed_at, closed_by
) values (
  '00000000-0000-0000-0000-000000006031',
  '00000000-0000-0000-0000-000000006010',
  '00000000-0000-0000-0000-000000006020',
  'EGP', date '2026-07-01', date '2026-07-31', 'CLOSED', 1,
  '00000000-0000-0000-0000-000000006001', now(),
  '00000000-0000-0000-0000-000000006001'
), (
  '00000000-0000-0000-0000-000000006032',
  '00000000-0000-0000-0000-000000006010',
  '00000000-0000-0000-0000-000000006020',
  'EGP', date '2026-08-01', date '2026-08-31', 'OPEN', 1,
  '00000000-0000-0000-0000-000000006001', null, null
);

select 1 / case when (
  select count(*) from public.accounting_periods
  where project_id='00000000-0000-0000-0000-000000006020'::uuid
    and version=1
) = 2 then 1 else 0 end as two_independent_v1_periods_allowed;

select 1 / case when (
  select count(*) from public.accounting_periods
  where project_id='00000000-0000-0000-0000-000000006020'::uuid
    and status='OPEN'
) = 1 then 1 else 0 end as one_open_period_invariant_preserved;

select 1 / case when not exists (
  select 1
  from public.accounting_periods a
  join public.accounting_periods b
    on b.project_id=a.project_id
   and b.id<>a.id
   and daterange(a.start_date,a.end_date,'[]') && daterange(b.start_date,b.end_date,'[]')
  where a.project_id='00000000-0000-0000-0000-000000006020'::uuid
) then 1 else 0 end as sequential_periods_do_not_overlap;

rollback;

select 'S6 sequential accounting periods SQL PASS' as result;
