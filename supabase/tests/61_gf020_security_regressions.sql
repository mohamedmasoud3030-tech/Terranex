-- GF-020 explicit active-member, tenant/project, DML, RLS, and sector-guard proof.
select id gf20_a_project from investment_projects where internal_reference = 'GF020-LS-A' \gset
select id gf20_a_site from livestock_sites where internal_reference = 'SITE-A' \gset
select id gf20_a_herd from livestock_herds where internal_reference = 'HERD-A' \gset
select id gf20_a_cohort from livestock_cohorts where cohort_reference = 'دفعة أغسطس 2026' \gset

-- All six material tables remain forced-RLS.
select 1/case when (
  select count(*) = 6 and bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class
  where relnamespace = 'public'::regnamespace
    and relname in (
      'livestock_project_profiles', 'livestock_sites', 'livestock_herds',
      'livestock_cohorts', 'livestock_cohort_initial_placements',
      'livestock_cohort_state_history'
    )
) then 1 else 0 end as livestock_force_rls_preserved;

-- Authenticated browser DML is denied; commands remain the only write path.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  update public.livestock_sites set name = 'تعديل' where id = %L
$q$, :'gf20_a_site')) like '%permission denied%' then 1 else 0 end as site_update_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  delete from public.livestock_herds where id = %L
$q$, :'gf20_a_herd')) like '%permission denied%' then 1 else 0 end as herd_delete_denied;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000001', format($q$
  delete from public.livestock_cohort_initial_placements where cohort_id = %L
$q$, :'gf20_a_cohort')) like '%permission denied%' then 1 else 0 end as placement_delete_denied;

-- Even privileged/import paths cannot attach Livestock rows to another sector.
select id gf20_re_project from investment_projects where sector = 'REAL_ESTATE' limit 1 \gset
select 1/case when gf20_owner_catch(format($q$
  insert into public.livestock_herds(
    organization_id, project_id, name, internal_reference, species, purpose,
    created_by, idempotency_key, request_hash
  ) values (
    '10000000-0000-4000-8000-000000000001', %L, 'قطيع غير صالح',
    'CROSS-SECTOR', 'CATTLE', 'MEAT',
    '00000000-0000-4000-8000-000000000001', 'gf20-cross-sector-herd', repeat('f',64)
  )
$q$, :'gf20_re_project')) like '%livestock project not found%'
then 1 else 0 end as privileged_sector_bypass_rejected;

-- Tenant B can operate its own hierarchy.
select gf20_run('00000000-0000-4000-8000-000000000002', $q$
  select public.create_investment_project(
    '20000000-0000-4000-8000-000000000002', 'مشروع ماشية باء',
    'GF020-LS-B', null, 'LIVESTOCK'
  )$q$) gf20_b_project \gset
select gf20_run('00000000-0000-4000-8000-000000000002', format($q$
  select public.create_livestock_site(
    '20000000-0000-4000-8000-000000000002', %L, 'موقع باء',
    'SITE-B', 'BARN', null, null, 'gf20-b-site'
  )$q$, :'gf20_b_project')) gf20_b_site \gset
select gf20_run('00000000-0000-4000-8000-000000000002', format($q$
  select public.create_livestock_herd(
    '20000000-0000-4000-8000-000000000002', %L, 'قطيع باء',
    'HERD-B', 'SHEEP', 'MEAT', null, 'gf20-b-herd'
  )$q$, :'gf20_b_project')) gf20_b_herd \gset
select gf20_run('00000000-0000-4000-8000-000000000002', format($q$
  select public.create_livestock_cohort(
    '20000000-0000-4000-8000-000000000002', %L, %L, %L,
    'دفعة باء', 'OPENING_BALANCE', current_date, 8,
    null, null, null, null, null, null, null, 'gf20-b-cohort'
  )$q$, :'gf20_b_project', :'gf20_b_herd', :'gf20_b_site')) gf20_b_cohort \gset
select 1/case when gf20_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.livestock_cohorts_read') = 1
then 1 else 0 end as tenant_b_reads_only_own_cohort;

-- Tenant/project-aware hierarchy links reject A/B combinations.
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.create_livestock_cohort(
    '20000000-0000-4000-8000-000000000002', %L, %L, %L,
    'خلط قطيع أ', 'OPENING_BALANCE', current_date, 1,
    null, null, null, null, null, null, null, 'gf20-b-cross-herd'
  )
$q$, :'gf20_b_project', :'gf20_a_herd', :'gf20_b_site')) like '%livestock herd not found%'
then 1 else 0 end as cross_tenant_herd_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.create_livestock_cohort(
    '20000000-0000-4000-8000-000000000002', %L, %L, %L,
    'خلط موقع أ', 'OPENING_BALANCE', current_date, 1,
    null, null, null, null, null, null, null, 'gf20-b-cross-site'
  )
$q$, :'gf20_b_project', :'gf20_b_herd', :'gf20_a_site')) like '%livestock site not found%'
then 1 else 0 end as cross_tenant_site_rejected;
select 1/case when gf20_catch('00000000-0000-4000-8000-000000000002', format($q$
  select public.transition_livestock_cohort(
    '20000000-0000-4000-8000-000000000002', %L, %L,
    'ACTIVE', 'PLANNED', 'محاولة عابرة', null, 'gf20-b-cross-transition'
  )
$q$, :'gf20_a_project', :'gf20_a_cohort')) <> 'NO_EXCEPTION'
then 1 else 0 end as cross_tenant_transition_rejected;

select 'GF-020 security regressions PASS' result;
