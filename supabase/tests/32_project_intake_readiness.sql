-- Guided intake declarations: tenant isolation, set-once freeze, balanced
-- control totals, no journal side-effects, no anonymous/browser writes.
insert into auth.users values ('00000000-0000-4000-8000-000000000099')
  on conflict (id) do nothing;

create or replace function public.intake_caught(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'NO_EXCEPTION';
exception when others then
  return sqlerrm;
end $$;
grant execute on function public.intake_caught(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);

select public.create_organization('منظمة إدخال المشروع') as intake_org \gset
select public.create_investment_project(:'intake_org'::uuid, 'مشروع إدخال عقاري', 'INTAKE-1', null) as intake_project \gset

select public.intake_record_freeze_date(
  :'intake_org'::uuid, :'intake_project'::uuid, date '2026-03-31', 'FREEZE-PACK-01'
) as intake_decl \gset

select 1 / case when (
  select freeze_date = date '2026-03-31'
  from public.project_intake_declarations_read
  where project_id = :'intake_project'::uuid
) then 1 else 0 end as intake_freeze_recorded;

-- Identical replay is idempotent.
select 1 / case when public.intake_record_freeze_date(
  :'intake_org'::uuid, :'intake_project'::uuid, date '2026-03-31', 'FREEZE-PACK-01'
) = :'intake_decl'::uuid then 1 else 0 end as intake_freeze_replay_ok;

select 1 / case when public.intake_caught(format(
  $$select public.intake_record_freeze_date(%L::uuid,%L::uuid, date '2026-04-30', 'FREEZE-PACK-02')$$,
  :'intake_org', :'intake_project'
)) like 'freeze date is set-once%' then 1 else 0 end as intake_freeze_set_once;

select 1 / case when public.intake_caught(format(
  $$select public.intake_declare_control_totals(%L::uuid,%L::uuid,'1000','900','TB-UNBAL')$$,
  :'intake_org', :'intake_project'
)) like '%does not accept a plug%' then 1 else 0 end as intake_unbalanced_totals_refused;

select public.intake_declare_control_totals(
  :'intake_org'::uuid, :'intake_project'::uuid, '125000', '125000', 'TB-SIGNED-01'
);

select 1 / case when (
  select declared_debit_total_minor_units = '125000'
     and declared_credit_total_minor_units = '125000'
  from public.project_intake_declarations_read
  where project_id = :'intake_project'::uuid
) then 1 else 0 end as intake_balanced_totals_stored;

select public.intake_record_setup_references(
  :'intake_org'::uuid, :'intake_project'::uuid,
  'اتفاقية الشركاء', 'CR-9988', 'PILOT-SCOPE-01'
);

select public.intake_declare_section_applicability(
  :'intake_org'::uuid, :'intake_project'::uuid,
  'HISTORICAL_CALLS', false, 'لم تصدر طلبات قبل التجميد', 'CALL-REG-EMPTY'
);

select count(*) as intake_journals_before
from public.journal_batches
where project_id = :'intake_project'::uuid \gset

select public.intake_report_modelling_gap(
  :'intake_org'::uuid, :'intake_project'::uuid,
  'TB-LINE-240', 'قرض شريك', '500000',
  'لا يوجد ترميز افتتاحي لالتزامات القروض في الإصدار الحالي'
) as intake_gap \gset

select 1 / case when (
  select count(*) from public.journal_batches where project_id = :'intake_project'::uuid
) = :'intake_journals_before'::int then 1 else 0 end as intake_gap_does_not_post;

select public.intake_record_evidence_item(
  :'intake_org'::uuid, :'intake_project'::uuid,
  'EVID-AGREEMENT-01', 'اتفاقية الشركاء', 'خزانة العقود لدى العميل'
);

reset role;

insert into public.memberships(organization_id, user_id, role, status)
values (:'intake_org'::uuid, '00000000-0000-4000-8000-000000000099', 'MEMBER', 'ACTIVE');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000099', false);

select 1 / case when public.intake_caught(format(
  $$select public.intake_record_freeze_date(%L::uuid,%L::uuid, date '2026-03-31', 'FREEZE-X')$$,
  :'intake_org', :'intake_project'
)) like '%owner%' or public.intake_caught(format(
  $$select public.intake_record_freeze_date(%L::uuid,%L::uuid, date '2026-03-31', 'FREEZE-X')$$,
  :'intake_org', :'intake_project'
)) like 'forbidden%' then 1 else 0 end as intake_member_cannot_declare_freeze;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', false);

select 1 / case when (
  select count(*) from public.project_intake_declarations_read
  where project_id = :'intake_project'::uuid
) = 0 then 1 else 0 end as intake_cross_tenant_read_denied;

select 1 / case when public.intake_caught(format(
  $$select public.intake_record_evidence_item(%L::uuid,%L::uuid,'EVID-X','حقيقة','موقع')$$,
  :'intake_org', :'intake_project'
)) in ('forbidden', 'project not found')
  or public.intake_caught(format(
  $$select public.intake_record_evidence_item(%L::uuid,%L::uuid,'EVID-X','حقيقة','موقع')$$,
  :'intake_org', :'intake_project'
)) like 'forbidden%' then 1 else 0 end as intake_cross_tenant_write_denied;

reset role;

do $$
declare
  v_rel record;
  v_anon_exec boolean;
  v_auth_exec boolean;
  t text;
begin
  foreach t in array array[
    'project_intake_declarations',
    'project_intake_section_applicability',
    'project_intake_modelling_gaps',
    'project_intake_evidence_items'
  ] loop
    select c.relrowsecurity, c.relforcerowsecurity
      into v_rel
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = t and c.relkind in ('r', 'p');
    if not found or not v_rel.relrowsecurity or not v_rel.relforcerowsecurity then
      raise exception '% must have ENABLE + FORCE RLS', t;
    end if;
    if has_table_privilege('authenticated', format('public.%I', t), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', t), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', t), 'DELETE')
       or has_table_privilege('anon', format('public.%I', t), 'SELECT') then
      raise exception '% must not allow browser writes or anonymous reads', t;
    end if;
  end loop;

  select has_function_privilege(
      'anon',
      'public.intake_record_freeze_date(uuid,uuid,date,text)',
      'EXECUTE'
    ),
    has_function_privilege(
      'authenticated',
      'public.intake_record_freeze_date(uuid,uuid,date,text)',
      'EXECUTE'
    )
    into v_anon_exec, v_auth_exec;
  if v_anon_exec then
    raise exception 'intake freeze command must not be executable by anon';
  end if;
  if not v_auth_exec then
    raise exception 'intake freeze command must remain executable by authenticated';
  end if;
end $$;

select 'INTAKE readiness PASS' as result;
