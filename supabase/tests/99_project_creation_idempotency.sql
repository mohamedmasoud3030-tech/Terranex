-- Recovery DEF-002 — project creation must use command identity, not name.

create or replace function s99_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s99_catch(p_user uuid, p_sql text)
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

-- One logical command may be replayed exactly and must return one project.
select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-A','first payload','REAL_ESTATE','project-create-def002-0001')$$,
  'مشروع متكرر DEF-002'
)) as s99_first \gset

select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-A','first payload','REAL_ESTATE','project-create-def002-0001')$$,
  'مشروع متكرر DEF-002'
)) as s99_replay \gset

select 1/case when :'s99_first' = :'s99_replay' then 1 else 0 end
  as s99_exact_replay_returns_same_project;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'PROJECT_CREATED' and entity_id = :'s99_first'
) = 1 then 1 else 0 end as s99_replay_does_not_duplicate_audit_event;

-- Reusing a command key with a changed payload is a hard failure.
select 1/case when s99_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-B','changed payload','REAL_ESTATE','project-create-def002-0001')$$,
  'مشروع متكرر DEF-002'
)) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s99_changed_payload_same_key_rejected;

-- A NEW command key may intentionally create a distinct project with the same
-- descriptive name and sector. It must never be redirected to the older row.
select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-B','second logical project','REAL_ESTATE','project-create-def002-0002')$$,
  'مشروع متكرر DEF-002'
)) as s99_second \gset

select 1/case when :'s99_first' <> :'s99_second' then 1 else 0 end
  as s99_new_key_same_name_creates_distinct_project;

select 1/case when (
  select count(*) from public.investment_projects
  where organization_id = '10000000-0000-4000-8000-000000000001'
    and sector = 'REAL_ESTATE'
    and name = 'مشروع متكرر DEF-002'
) = 2 then 1 else 0 end as s99_same_name_rows_are_not_collapsed;

-- Legacy 5-argument callers remain compatible: exact payload is deterministic,
-- while a changed payload no longer aliases to an old project by name.
select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-LEGACY-A','legacy first','AGRICULTURE')$$,
  'مشروع قديم متكرر DEF-002'
)) as s99_legacy_first \gset

select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-LEGACY-A','legacy first','AGRICULTURE')$$,
  'مشروع قديم متكرر DEF-002'
)) as s99_legacy_replay \gset

select 1/case when :'s99_legacy_first' = :'s99_legacy_replay' then 1 else 0 end
  as s99_legacy_exact_payload_replays;

select s99_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-LEGACY-B','legacy changed','AGRICULTURE')$$,
  'مشروع قديم متكرر DEF-002'
)) as s99_legacy_changed \gset

select 1/case when :'s99_legacy_first' <> :'s99_legacy_changed' then 1 else 0 end
  as s99_legacy_changed_payload_does_not_alias;

-- The new command-aware arity preserves tenant authorization.
select 1/case when s99_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001',%L,'DEF002-X',null,'LIVESTOCK','project-create-def002-cross-tenant')$$,
  'محاولة مستأجر آخر DEF-002'
)) = 'forbidden' then 1 else 0 end as s99_command_arity_cross_tenant_rejected;

reset role;
select 'S99 project creation idempotency PASS' as result;
