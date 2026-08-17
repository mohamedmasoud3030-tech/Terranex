-- S6 corrective gate — material creation/change commands must converge after
-- response loss, reject key/payload reuse, authorize before replay, and keep
-- implementation functions private. Uses a fresh project so historical close
-- fixtures cannot influence the result.

create or replace function s6r_uuid(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
exception when others then
  reset role;
  raise;
end $$;

create or replace function s6r_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_message text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql;
  exception when others then
    v_message := sqlerrm;
    reset role;
    return v_message;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

select s6r_uuid(
  '00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001',
    'S6 replay-safety project','S6-REPLAY-001','S6 replay-safety fixture','REAL_ESTATE'
  )$$
) as s6r_project \gset

-- Canonical create-period command: same key + same payload returns the same id.
select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period(
    '10000000-0000-4000-8000-000000000001',%L,
    '2026-10-01','2026-10-31','s6-period-idem-0001'
  )$$, :'s6r_project'
)) as s6r_period_first \gset

select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period(
    '10000000-0000-4000-8000-000000000001',%L,
    '2026-10-01','2026-10-31','s6-period-idem-0001'
  )$$, :'s6r_project'
)) as s6r_period_replay \gset

select 1/case when :'s6r_period_first' = :'s6r_period_replay' then 1 else 0 end
  as s6_period_replay_same_result;

select 1/case when (
  select count(*) from public.accounting_periods
  where organization_id='10000000-0000-4000-8000-000000000001'
    and project_id=:'s6r_project'
    and start_date='2026-10-01' and end_date='2026-10-31'
) = 1 then 1 else 0 end as s6_period_replay_single_effect;

select 1/case when (
  select count(*) from public.s6_command_receipts
  where organization_id='10000000-0000-4000-8000-000000000001'
    and command_type='CREATE_ACCOUNTING_PERIOD'
    and idempotency_key='s6-period-idem-0001'
) = 1 then 1 else 0 end as s6_period_replay_single_receipt;

select 1/case when (
  select count(*) from public.audit_events
  where organization_id='10000000-0000-4000-8000-000000000001'
    and event_type='ACCOUNTING_PERIOD_OPENED'
    and entity_id=:'s6r_period_first'
) = 1 then 1 else 0 end as s6_period_replay_single_audit;

-- Same key with a different payload must fail before any second effect.
select 1/case when s6r_catch(
  '00000000-0000-4000-8000-000000000001', format(
    $$select public.s6_create_accounting_period(
      '10000000-0000-4000-8000-000000000001',%L,
      '2026-10-01','2026-11-30','s6-period-idem-0001'
    )$$, :'s6r_project'
  )
) = 'idempotency key payload mismatch' then 1 else 0 end
  as s6_period_payload_mismatch_rejected;

-- Replay re-checks authorization before consulting the receipt.
select 1/case when s6r_catch(
  '00000000-0000-4000-8000-000000000002', format(
    $$select public.s6_create_accounting_period(
      '10000000-0000-4000-8000-000000000001',%L,
      '2026-10-01','2026-10-31','s6-period-idem-0001'
    )$$, :'s6r_project'
  )
) = 'forbidden' then 1 else 0 end as s6_period_replay_reauthorizes;

-- Prepare-close has the same canonical replay contract and keeps one run.
select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_prepare_close_run(
    '10000000-0000-4000-8000-000000000001',%L,%L,
    'S6 replay prepare','s6-prepare-idem-0001'
  )$$, :'s6r_project', :'s6r_period_first'
)) as s6r_prepare_first \gset

select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_prepare_close_run(
    '10000000-0000-4000-8000-000000000001',%L,%L,
    'S6 replay prepare','s6-prepare-idem-0001'
  )$$, :'s6r_project', :'s6r_period_first'
)) as s6r_prepare_replay \gset

select 1/case when :'s6r_prepare_first' = :'s6r_prepare_replay' then 1 else 0 end
  as s6_prepare_replay_same_result;

select 1/case when (
  select count(*) from public.close_runs where id=:'s6r_prepare_first'
) = 1 then 1 else 0 end as s6_prepare_replay_single_effect;

select 1/case when s6r_catch(
  '00000000-0000-4000-8000-000000000001', format(
    $$select public.s6_prepare_close_run(
      '10000000-0000-4000-8000-000000000001',%L,%L,
      'different notes','s6-prepare-idem-0001'
    )$$, :'s6r_project', :'s6r_period_first'
  )
) = 'idempotency key payload mismatch' then 1 else 0 end
  as s6_prepare_payload_mismatch_rejected;

-- Cached/older clients keep the legacy create-period arity, but the wrapper
-- derives a deterministic key and converges on retry.
select s6r_uuid(
  '00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project(
    '10000000-0000-4000-8000-000000000001',
    'S6 legacy replay project','S6-REPLAY-LEGACY','S6 legacy replay fixture','REAL_ESTATE'
  )$$
) as s6r_legacy_project \gset

select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period(
    '10000000-0000-4000-8000-000000000001',%L,'2026-12-01','2026-12-31'
  )$$, :'s6r_legacy_project'
)) as s6r_legacy_period_first \gset

select s6r_uuid('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period(
    '10000000-0000-4000-8000-000000000001',%L,'2026-12-01','2026-12-31'
  )$$, :'s6r_legacy_project'
)) as s6r_legacy_period_replay \gset

select 1/case when :'s6r_legacy_period_first' = :'s6r_legacy_period_replay' then 1 else 0 end
  as s6_legacy_period_replay_same_result;

select 1/case when (
  select count(*) from public.accounting_periods
  where project_id=:'s6r_legacy_project' and start_date='2026-12-01' and end_date='2026-12-31'
) = 1 then 1 else 0 end as s6_legacy_period_single_effect;

-- All five canonical overloads exist; legacy arities remain available.
select 1/case when to_regprocedure(
  'public.s6_create_accounting_period(uuid,uuid,date,date,text)'
) is not null then 1 else 0 end as s6_keyed_create_period_exists;
select 1/case when to_regprocedure(
  'public.s6_prepare_close_run(uuid,uuid,uuid,text,text)'
) is not null then 1 else 0 end as s6_keyed_prepare_exists;
select 1/case when to_regprocedure(
  'public.s6_request_close_run_exception(uuid,uuid,text,text,text,text,text)'
) is not null then 1 else 0 end as s6_keyed_exception_request_exists;
select 1/case when to_regprocedure(
  'public.s6_reopen_period(uuid,uuid,uuid,text,text,text)'
) is not null then 1 else 0 end as s6_keyed_reopen_exists;
select 1/case when to_regprocedure(
  'public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text,text)'
) is not null then 1 else 0 end as s6_keyed_correction_request_exists;

-- Internal implementations and receipt storage are never directly executable /
-- readable by API roles.
select 1/case when not has_function_privilege(
  'authenticated','public.s6_create_accounting_period_impl(uuid,uuid,date,date)','EXECUTE'
) then 1 else 0 end as s6_create_impl_private;
select 1/case when not has_function_privilege(
  'authenticated','public.s6_prepare_close_run_impl(uuid,uuid,uuid,text)','EXECUTE'
) then 1 else 0 end as s6_prepare_impl_private;
select 1/case when not has_function_privilege(
  'authenticated','public.s6_request_close_run_exception_impl(uuid,uuid,text,text,text,text)','EXECUTE'
) then 1 else 0 end as s6_exception_impl_private;
select 1/case when not has_function_privilege(
  'authenticated','public.s6_reopen_period_impl(uuid,uuid,uuid,text,text)','EXECUTE'
) then 1 else 0 end as s6_reopen_impl_private;
select 1/case when not has_function_privilege(
  'authenticated','public.s6_request_correction_impl(uuid,uuid,uuid,uuid,uuid,text,text)','EXECUTE'
) then 1 else 0 end as s6_correction_impl_private;
select 1/case when not has_table_privilege(
  'authenticated','public.s6_command_receipts','SELECT'
) then 1 else 0 end as s6_receipt_table_private;

reset role;
drop function if exists s6r_uuid(uuid,text);
drop function if exists s6r_catch(uuid,text);
select 'S6 command replay-safety SQL PASS' as result;
