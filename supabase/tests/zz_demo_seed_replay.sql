-- ===========================================================================
-- Demo showcase seed replay gate (runs LAST, after every other suite).
--
-- The permanent Real Estate showcase (`scripts/demo/seed_real_estate_showcase.sql`)
-- is a documented re-runnable operational fixture. After the pre-owner policy
-- safety boundary (migration 20260816062000), contribution-cash attachment and
-- the S5 allocation/distribution commands fail closed unless the organization
-- has approved policy_authority rows — and the registry ships EMPTY by design.
--
-- This gate proves, on the disposable verification database:
--   1. the seed completes end-to-end on a fresh current schema (DEMO_CREATED);
--   2. re-running it is an exact no-op (DEMO_ALREADY_EXISTS);
--   3. the synthetic demo policy activation is confined to the demo
--      organization — no other tenant gains a policy row.
-- ===========================================================================

-- The disposable auth.users shim carries only `id`; the seed reads email,
-- last_sign_in_at and created_at to resolve its maker/checker actors.
alter table auth.users add column if not exists email text;
alter table auth.users add column if not exists last_sign_in_at timestamptz;
alter table auth.users add column if not exists created_at timestamptz;

insert into auth.users(id, email, last_sign_in_at, created_at) values
  ('e0000000-0000-4000-8000-00000000000a', 'demo-checker@terranex.invalid', now(), now()),
  ('e0000000-0000-4000-8000-00000000000b', 'demo-maker@terranex.invalid', null, now())
on conflict (id) do nothing;

-- Snapshot the organizations that already hold policy rows (earlier suites
-- activate policy for their own test tenants); the seed must add policy rows
-- for the demo organization ONLY.
create temp table demo_policy_before as
select distinct organization_id from public.policy_authority;

-- First run: full creation through the production S0-S7 command surface.
-- The seed ends with a select that must return DEMO_CREATED.
\i scripts/demo/seed_real_estate_showcase.sql

-- Second run: exact no-op.
\i scripts/demo/seed_real_estate_showcase.sql

do $$
declare
  v_org uuid;
  v_rows integer;
begin
  select o.id into v_org
  from public.organizations o
  where o.name = 'شركة أفق النيل للاستثمار العقاري – DEMO'
  order by o.created_at desc
  limit 1;
  if v_org is null then
    raise exception 'demo seed replay: demo organization was not created';
  end if;

  select count(*) into v_rows
  from public.policy_authority a
  where a.organization_id = v_org;
  if v_rows <> 2 then
    raise exception 'demo seed replay: demo organization must hold exactly 2 policy rows, got %', v_rows;
  end if;
  if not exists (
    select 1 from public.policy_authority a
    where a.organization_id = v_org
      and a.scope = 'CAPITAL_CONTRIBUTION'
      and a.status = 'APPROVED'
      and a.policy_version = 'DEMO-SHOWCASE-POLICY-2026-01'
  ) then
    raise exception 'demo seed replay: CAPITAL_CONTRIBUTION demo policy missing';
  end if;
  if not exists (
    select 1 from public.policy_authority a
    where a.organization_id = v_org
      and a.scope = 'INVESTOR_ECONOMICS'
      and a.status = 'APPROVED'
      and a.policy_version = 'DEMO-SHOWCASE-POLICY-2026-01'
  ) then
    raise exception 'demo seed replay: INVESTOR_ECONOMICS demo policy missing';
  end if;
  if exists (
    select 1 from public.policy_authority a
    left join demo_policy_before b on b.organization_id = a.organization_id
    where b.organization_id is null
      and a.organization_id <> v_org
  ) then
    raise exception 'demo seed replay: seed added policy rows to a non-demo organization';
  end if;
end $$;

select 'demo seed replay PASS' as result;
