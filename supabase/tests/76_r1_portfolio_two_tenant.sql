-- R1 — Portfolio Foundation two-tenant isolation.
--
-- Proves that an outside organization cannot read or mutate another
-- organization's portfolios, lifecycle, or project memberships through
-- any path: RLS on tables and read views, command authorization,
-- organization-coherent foreign keys, or membership-reference guards.
--
-- Tenants:
--   * Suite-75 R1 organization 30000000-…-0071 (owner user …-0071)
--   * Tenant B: 20000000-0000-4000-8000-000000000002 (owner user …-0002,
--     established by the S0 isolation suite).

create or replace function s76_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s76_catch(p_user uuid, p_sql text)
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

create or replace function s76_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s76_owner_catch(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    return v_msg;
  end;
  return 'NO_EXCEPTION';
end $$;

select id as r1_tenant_a_org from public.organizations
 where id = '30000000-0000-4000-8000-000000000071' \gset
select id as r1_tenant_a_portfolio from public.investment_portfolios
 where organization_id = :'r1_tenant_a_org'
 order by created_at limit 1 \gset
select id as r1_tenant_a_project from public.investment_projects
 where organization_id = :'r1_tenant_a_org' and internal_reference = 'R1-PROJ-A' \gset

-- ---------------------------------------------------------------------------
-- 1. Tenant B operates its own portfolio without issue.
-- ---------------------------------------------------------------------------
select s76_run('00000000-0000-4000-8000-000000000002',
  $$select public.create_investment_portfolio('20000000-0000-4000-8000-000000000002','محفظة باء ر1','غرض إداري للمنظمة باء',null,'r1-76-b-create-001')$$
) as r1_b_portfolio \gset
select 1/case when :'r1_b_portfolio' is not null then 1 else 0 end
  as r1_tenant_b_creates_own_portfolio;

-- Activate it so later assignment probes reach the organization-coherence
-- checks instead of the lifecycle gate.
select s76_run('00000000-0000-4000-8000-000000000002', format(
  $$select public.transition_investment_portfolio('20000000-0000-4000-8000-000000000002',%L,'DRAFT','ACTIVE','تنشيط للاختبار','r1-76-b-activate-own')$$
  , :'r1_b_portfolio')) as r1_b_activation \gset
select 1/case when :'r1_b_activation' is not null then 1 else 0 end
  as r1_tenant_b_activates_own_portfolio;

-- ---------------------------------------------------------------------------
-- 2. Tenant B cannot read Tenant A portfolios through table or view.
-- ---------------------------------------------------------------------------
select 1/case when s76_count('00000000-0000-4000-8000-000000000002', format(
  $$select count(*) from public.investment_portfolios where organization_id=%L$$
  , :'r1_tenant_a_org')) = 0 then 1 else 0 end
  as r1_tenant_b_cannot_read_tenant_a_table;

select 1/case when s76_count('00000000-0000-4000-8000-000000000002', format(
  $$select count(*) from public.investment_portfolios_read where organization_id=%L$$
  , :'r1_tenant_a_org')) = 0 then 1 else 0 end
  as r1_tenant_b_cannot_read_tenant_a_view;

select 1/case when s76_count('00000000-0000-4000-8000-000000000002', format(
  $$select count(*) from public.portfolio_project_assignments_read where portfolio_id=%L$$
  , :'r1_tenant_a_portfolio')) = 0 then 1 else 0 end
  as r1_membership_view_is_not_a_bypass;

select 1/case when s76_count('00000000-0000-4000-8000-000000000002', format(
  $$select count(*) from public.investment_portfolio_state_history_read where portfolio_id=%L$$
  , :'r1_tenant_a_portfolio')) = 0 then 1 else 0 end
  as r1_history_view_is_not_a_bypass;

-- ---------------------------------------------------------------------------
-- 3. Tenant B cannot run R1 commands against Tenant A scope.
-- ---------------------------------------------------------------------------
select 1/case when s76_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_investment_portfolio(%L,'استيلاء',null,null,'r1-76-b-hijack-001')$$
  , :'r1_tenant_a_org')) like '%forbidden%' then 1 else 0 end
  as r1_tenant_b_cannot_create_in_tenant_a;

select 1/case when s76_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.transition_investment_portfolio(%L,%L,'DRAFT','ACTIVE','محاولة خارجية','r1-76-b-activate-001')$$
  , :'r1_tenant_a_org', :'r1_tenant_a_portfolio')) like '%forbidden%' then 1 else 0 end
  as r1_tenant_b_cannot_transition_tenant_a;

select 1/case when s76_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.update_investment_portfolio_metadata(%L,%L,'اسم مزور',null,null,'r1-76-b-update-001')$$
  , :'r1_tenant_a_org', :'r1_tenant_a_portfolio')) like '%forbidden%' then 1 else 0 end
  as r1_tenant_b_cannot_update_tenant_a;

select 1/case when s76_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.assign_project_to_portfolio(%L,%L,%L,'r1-76-b-assign-001')$$
  , :'r1_tenant_a_org', :'r1_tenant_a_portfolio', :'r1_tenant_a_project')) like '%forbidden%'
  then 1 else 0 end as r1_tenant_b_cannot_assign_in_tenant_a;

-- ---------------------------------------------------------------------------
-- 4. Cross-organization project assignment is refused even with a valid
--    command scope on the caller's own organization.
-- ---------------------------------------------------------------------------
select 1/case when s76_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.assign_project_to_portfolio('20000000-0000-4000-8000-000000000002',%L,%L,'r1-76-b-crossassign-001')$$
  , :'r1_b_portfolio', :'r1_tenant_a_project')) like '%project not found in portfolio organization%'
  then 1 else 0 end as r1_cross_org_project_assignment_rejected;

-- And the database-level integrity agrees: a forged row mixing the two
-- organizations violates the organization-coherent foreign keys.
select 1/case when s76_owner_catch(format(
  $$insert into public.portfolio_project_assignments
      (organization_id, portfolio_id, investment_project_id, assigned_by,
       idempotency_key, request_hash)
    values ('20000000-0000-4000-8000-000000000002', %L, %L,
      '00000000-0000-4000-8000-000000000002', 'r1-76-forge-001',
      repeat('b', 64))$$
  , :'r1_b_portfolio', :'r1_tenant_a_project')) <> 'NO_EXCEPTION' then 1 else 0 end
  as r1_org_coherent_fk_blocks_forged_membership;

-- Manager reference across organizations is refused.
select 1/case when s76_catch('00000000-0000-4000-8000-000000000002',
  $$select public.create_investment_portfolio('20000000-0000-4000-8000-000000000002','محفظة بمدير خارجي',null,'00000000-0000-4000-8000-000000000071','r1-76-b-crossmgr-001')$$
) like '%responsible manager must be an active member%' then 1 else 0 end
  as r1_cross_org_manager_rejected;

-- ---------------------------------------------------------------------------
-- 5. An INACTIVE member of Tenant A's R1 org loses command authority.
-- ---------------------------------------------------------------------------
select 1/case when s76_catch('00000000-0000-4000-8000-000000000073', format(
  $$select public.transition_investment_portfolio(%L,%L,'DRAFT','ARCHIVED','عضو موقوف','r1-76-inactive-001')$$
  , :'r1_tenant_a_org', :'r1_tenant_a_portfolio')) like '%forbidden%' then 1 else 0 end
  as r1_inactive_member_cannot_mutate;

select 1/case when s76_count('00000000-0000-4000-8000-000000000073', format(
  $$select count(*) from public.investment_portfolios where organization_id=%L$$
  , :'r1_tenant_a_org')) = 0 then 1 else 0 end
  as r1_inactive_member_cannot_read;

-- Tenant A state unchanged after every outside attempt.
select 1/case when (
  select count(*) from public.investment_portfolios
   where organization_id = :'r1_tenant_a_org'
) >= 2 then 1 else 0 end as r1_tenant_a_state_preserved;
