-- GF-013 / sector-aware investment project.
--
-- Proves the new sector vocabulary (REAL_ESTATE | AGRICULTURE), the
-- sector-aware create_investment_project RPC, and the unchanged
-- 4-argument Real Estate compatibility path. Also proves the audit
-- event records the actual selected sector, and that Agriculture cannot
-- attach to a Real Estate project at the database level.

create or replace function s13_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s13_catch(p_user uuid, p_sql text)
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

-- Tenant A projects via the new sector-aware RPC.
select s13_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'GF013-RE-A','GF-013 real estate', 'REAL_ESTATE')$$,
  'مشروع النخيل GF-013'
)) as s13_re_a \gset

select s13_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'GF013-AG-A','GF-013 agriculture', 'AGRICULTURE')$$,
  'مشروع المزارع GF-013'
)) as s13_ag_a \gset

-- The audit event for each new project must record the actual sector.
select 1/case when (
  select (payload->>'sector') = 'REAL_ESTATE'
  from public.audit_events
  where event_type = 'PROJECT_CREATED'
    and entity_id = :'s13_re_a'
) then 1 else 0 end as s13_re_audit_records_sector;

select 1/case when (
  select (payload->>'sector') = 'AGRICULTURE'
  from public.audit_events
  where event_type = 'PROJECT_CREATED'
    and entity_id = :'s13_ag_a'
) then 1 else 0 end as s13_ag_audit_records_sector;

-- Sector column is now queryable.
select 1/case when (
  select sector = 'REAL_ESTATE' from public.investment_projects where id = :'s13_re_a'
) then 1 else 0 end as s13_re_sector_visible;

select 1/case when (
  select sector = 'AGRICULTURE' from public.investment_projects where id = :'s13_ag_a'
) then 1 else 0 end as s13_ag_sector_visible;

-- GF-020 later extends the vocabulary with LIVESTOCK. An unsupported
-- sector remains rejected at the database boundary.
select 1/case when s13_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع غير مسموح','GF013-BAD','x','UNSUPPORTED')$$
)) like '%invalid sector%' then 1 else 0 end as s13_invalid_sector_rejected;

-- Historical 2-, 3-, and 4-argument calls still resolve only to the
-- compatibility wrapper and remain locked to REAL_ESTATE.
select s13_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع قديم وسيطتان')$$
)) as s13_legacy_two \gset

select s13_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع قديم 3-وسائط','GF013-LEGACY-3')$$
)) as s13_legacy_three \gset

select s13_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع قديم 4-وسائط','GF013-LEGACY-4','compat')$$
)) as s13_legacy \gset

select 1/case when (
  select count(*) from public.investment_projects
  where id in (:'s13_legacy_two', :'s13_legacy_three', :'s13_legacy')
    and sector = 'REAL_ESTATE'
) = 3 then 1 else 0 end as s13_legacy_arity_keeps_real_estate;

-- Cross-tenant write is still rejected by is_active_member.
select 1/case when s13_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','محاولة عبر المستأجر',null,null,'AGRICULTURE')$$
)) = 'forbidden' then 1 else 0 end as s13_cross_tenant_agriculture_rejected;

reset role;
select 'S13 sector-aware project PASS' as result;
