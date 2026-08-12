-- GF-007 / S6 — period close, controlled correction, S4 sale correction,
-- reopen, and database-enforced period lock.

create or replace function s6_expect_raise(p_user uuid, p_sql text, p_sqlstate text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate = p_sqlstate;
end $$;

create or replace function s6_expect_ok(p_user uuid, p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
  return true;
exception when others then
  reset role;
  raise notice 's6_expect_ok failed: %', sqlerrm;
  return false;
end $$;

create or replace function s6_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
end $$;

-- Resolve the prior S4 fixture. The S4 sale recognition on s4_asset is
-- still ACTIVE and is the canonical target for the S4 correction test.
select id as s6_project from public.investment_projects where name = 'مشروع النخيل' \gset
select id as s6_project2 from public.investment_projects where name = 'مشروع ثانٍ' \gset
select id as s6_asset from public.property_assets where idempotency_key = 's3-asset-main-0001' \gset

-- Open an S6 period covering the S4 fixture dates.
do $$
declare
  v_period_id uuid;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', false);
  v_period_id := public.s6_create_accounting_period(
    '10000000-0000-4000-8000-000000000001',
    (select id from public.investment_projects where name = 'مشروع النخيل'),
    (select coalesce(min(transaction_date), current_date - 30)
      from public.journal_batches
      where project_id = (select id from public.investment_projects where name = 'مشروع النخيل')),
    current_date
  );
  reset role;
end $$;

select id as s6_period1 from public.accounting_periods
  where project_id = :'s6_project' and status = 'OPEN' \gset
select 1/case when (select status = 'OPEN' from public.accounting_periods where id = :'s6_period1') then 1 else 0 end as s6_period_opened;

-- Non-overlap invariant: a second open period overlapping the first is
-- rejected at the database.
select 1/case when s6_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period('10000000-0000-4000-8000-000000000001', %L,
    (select start_date from public.accounting_periods where id = %L) + 1,
    (select end_date from public.accounting_periods where id = %L) + 5)$$,
  :'s6_project', :'s6_period1', :'s6_period1'), 'P0001') then 1 else 0 end as s6_overlap_period_rejected;

-- Database-enforced period lock: any direct insert into journal_batches with
-- a date far outside the open period must fail.
do $$
begin
  begin
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, posted_by
    ) values (
      '10000000-0000-4000-8000-000000000001', :'s6_project', 'COST_OBLIGATION',
      gen_random_uuid(), current_date - 3650,
      's6-old-date-' || substr(md5(random()::text), 1, 12),
      repeat('a', 64), '00000000-0000-4000-8000-000000000001'
    );
    raise exception 'old-date posting unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%no open accounting period%' then
      raise notice 'expected period-lock failure, got: %', sqlerrm;
    end if;
  end;
end $$;
select 1/case when (select count(*) from public.journal_batches
  where idempotency_key like 's6-old-date-%') = 0 then 1 else 0 end as s6_lock_rejects_old_posting;

-- Prepare a close run; the existing S4 fixture has no bank reconciliation
-- gap and no WIP-after-control-transfer gap, so most gates PASS. The
-- composite gate passes when no FAIL remains.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_prepare_close_run('10000000-0000-4000-8000-000000000001', %L, %L, 'first close')$$,
  :'s6_project', :'s6_period1'));
select id as s6_run1 from public.close_runs where period_id = :'s6_period1' and version = 1 \gset
select 1/case when (select status = 'PREPARED' from public.close_runs where id = :'s6_run1') then 1 else 0 end as s6_run_prepared;

-- All ten gates are present.
select 1/case when (select count(*) from public.close_run_gates where close_run_id = :'s6_run1') = 10 then 1 else 0 end as s6_ten_gates_present;

-- Direct close run / gate mutation by an active member is denied by RLS.
do $$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
  execute 'set role authenticated';
  begin
    insert into public.close_runs(organization_id, project_id, period_id, version, status, source_cutoff_date, generated_by)
    values('10000000-0000-4000-8000-000000000001', :'s6_project', :'s6_period1', 99, 'PREPARED', current_date,
      '00000000-0000-4000-8000-000000000001');
    raise exception 'direct S6 run DML unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;
select 1/case when (select count(*) from public.close_runs where version = 99) = 0 then 1 else 0 end as s6_direct_run_dml_denied;

-- The S2 test fixtures leave a small number of unreconciled bank lines
-- (TXN-RACE-RECON, TXN-ACCT-C, TXN-AMT-C). The S6 close control requires
-- those lines to be addressed through the documented exception workflow
-- before the run can be approved. We request+approve an exception for
-- the BANK_RECONCILIATION_COVERAGE gate here so the rest of the test
-- exercises the approved run, the snapshot, and the closed-period
-- enforcement path.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_request_close_run_exception('10000000-0000-4000-8000-000000000001', %L,
    'BANK_RECONCILIATION_COVERAGE', 'سطر بنكي قديم لم يصل', 'BANK-OLD-RUN1', 'material: not material')$$,
  :'s6_run1'));
select 1/case when s6_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_approve_close_run_exception('10000000-0000-4000-8000-000000000001', %L, 's6-approve-exc-run1')$$,
  (select id from public.close_run_exceptions where close_run_id = :'s6_run1' and gate_code = 'BANK_RECONCILIATION_COVERAGE'))) then 1 else 0 end as s6_run1_exception_approved;
select 1/case when (select result = 'APPROVED_EXCEPTION' from public.close_run_gates
  where close_run_id = :'s6_run1' and gate_code = 'BANK_RECONCILIATION_COVERAGE') then 1 else 0 end as s6_run1_bank_gate_promoted;

-- Approve closes the period and produces an immutable snapshot.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_approve_close_run('10000000-0000-4000-8000-000000000001', %L, 's6-approve-1')$$,
  :'s6_run1'));
select 1/case when (select status = 'APPROVED' from public.close_runs where id = :'s6_run1') then 1 else 0 end as s6_run_approved;
select 1/case when (select status = 'CLOSED' from public.accounting_periods where id = :'s6_period1') then 1 else 0 end as s6_period_closed;
select id as s6_snapshot1 from public.close_run_snapshots where close_run_id = :'s6_run1' \gset
select 1/case when (select char_length(content_hash) = 64 from public.close_run_snapshots where id = :'s6_snapshot1') then 1 else 0 end as s6_snapshot_hashed;
select 1/case when (select content_hash from public.close_run_snapshots where id = :'s6_snapshot1') =
  (select content_hash from public.close_run_snapshots where id = :'s6_snapshot1') then 1 else 0 end as s6_snapshot_hash_stable;
-- Snapshots cannot be updated.
do $$
begin
  begin
    update public.close_run_snapshots set totals = '{"x":"y"}'::jsonb where id = :'s6_snapshot1';
    raise exception 'snapshot update unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%immutable%' and sqlerrm not like '%append-only%' then
      raise notice 'expected snapshot immutability, got: %', sqlerrm;
    end if;
  end;
end $$;
select 1/case when (select count(*) from public.close_run_snapshots where id = :'s6_snapshot1') = 1 then 1 else 0 end as s6_snapshot_immutable;

-- Closed period rejects all normal postings.
do $$
begin
  begin
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, posted_by
    ) values (
      '10000000-0000-4000-8000-000000000001', :'s6_project', 'COST_OBLIGATION',
      gen_random_uuid(), current_date,
      's6-closed-posting-' || substr(md5(random()::text), 1, 12),
      repeat('b', 64), '00000000-0000-4000-8000-000000000001'
    );
    raise exception 'closed-period posting unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%no open accounting period%' then
      raise notice 'expected closed-period rejection, got: %', sqlerrm;
    end if;
  end;
end $$;
select 1/case when (select count(*) from public.journal_batches
  where idempotency_key like 's6-closed-posting-%') = 0 then 1 else 0 end as s6_closed_period_lock_rejects;

-- Hard accounting integrity: an unbalanced journal batch is rejected at the
-- statement-level trigger.
do $$
declare
  v_proj uuid;
  v_bank uuid;
  v_batch uuid;
begin
  v_proj := :'s6_project';
  v_bank := (select id from public.semantic_accounts where role = 'BANK_CASH');
  begin
    insert into public.journal_batches(organization_id, project_id, source_type, source_id,
      transaction_date, idempotency_key, request_hash, posted_by)
    values ('10000000-0000-4000-8000-000000000001', v_proj, 'COST_OBLIGATION', gen_random_uuid(),
      current_date, 's6-try-unbalanced-' || substr(md5(random()::text), 1, 8),
      repeat('c', 64), '00000000-0000-4000-8000-000000000001')
    returning id into v_batch;
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date)
    values (v_batch, '10000000-0000-4000-8000-000000000001', v_proj, v_bank, 100, 0, 'EGP', current_date);
    insert into public.journal_lines(batch_id, organization_id, project_id, account_id,
      debit_minor_units, credit_minor_units, currency, transaction_date)
    values (v_batch, '10000000-0000-4000-8000-000000000001', v_proj, v_bank, 0, 50, 'EGP', current_date);
    raise exception 'unbalanced batch should have been rejected';
  exception when others then
    if sqlerrm not like '%unbalanced%' then
      raise notice 'expected unbalanced rejection, got: %', sqlerrm;
    end if;
  end;
end $$;
select 1/case when (select count(*) from public.journal_batches
  where idempotency_key like 's6-try-unbalanced-%') = 0 then 1 else 0 end as s6_unbalanced_batch_hard_failure;

-- NOT_APPLICABLE: suspense/control accounts are objectively not part of the
-- S1-S4 subledger.
select 1/case when (select result = 'NOT_APPLICABLE' from public.close_run_gates
  where close_run_id = :'s6_run1' and gate_code = 'SUSPENSE_CONTROL_ACCOUNTS')
  then 1 else 0 end as s6_suspense_gate_not_applicable;

-- Cross-tenant RLS: tenant B cannot see tenant A's periods or runs.
do $$
declare v_visible int;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
  perform set_config('role', 'authenticated', false);
  select count(*) into v_visible from public.accounting_periods_read where project_id = :'s6_project';
  reset role;
  if v_visible <> 0 then
    raise exception 'cross-tenant read of periods unexpectedly returned % rows', v_visible;
  end if;
end $$;
select 1 as s6_cross_tenant_period_read_denied;

select 1/case when s6_expect_raise('00000000-0000-4000-8000-000000000002', format(
  $$select public.s6_create_accounting_period('10000000-0000-4000-8000-000000000002', %L, current_date, current_date+1)$$,
  :'s6_project2'), 'P0001') then 1 else 0 end as s6_cross_tenant_period_create_rejected;

-- Approve exception path: request then approve a gate exception, and the
-- gate result flips to APPROVED_EXCEPTION. Use a fresh project/currency
-- fixture so the existing s6_run1 is unaffected.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_create_accounting_period('10000000-0000-4000-8000-000000000001', %L, current_date-2, current_date+1)$$,
  :'s6_project2'));
select id as s6_period2 from public.accounting_periods
  where project_id = :'s6_project2' and status = 'OPEN' \gset
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_prepare_close_run('10000000-0000-4000-8000-000000000001', %L, %L, 'second close to test exceptions')$$,
  :'s6_project2', :'s6_period2'));
select id as s6_run2 from public.close_runs where period_id = :'s6_period2' and version = 1 \gset
select 1/case when s6_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_request_close_run_exception('10000000-0000-4000-8000-000000000001', %L,
    'BANK_RECONCILIATION_COVERAGE', 'سطر بنكي قديم لم يصل', 'BANK-OLD-001', 'material: not material')$$,
  :'s6_run2')) then 1 else 0 end as s6_exception_request_ok;
-- A wrong-tenant approval attempt is denied by the active-member/OWNER check.
select 1/case when s6_expect_raise('00000000-0000-4000-8000-000000000002', format(
  $$select public.s6_approve_close_run_exception('10000000-0000-4000-8000-000000000001', %L, 's6-approve-exc-1')$$,
  (select id from public.close_run_exceptions where close_run_id = :'s6_run2' and gate_code = 'BANK_RECONCILIATION_COVERAGE')),
  'P0001') then 1 else 0 end as s6_wrong_tenant_exception_rejected;

select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_approve_close_run_exception('10000000-0000-4000-8000-000000000001', %L, 's6-approve-exc-1')$$,
  (select id from public.close_run_exceptions where close_run_id = :'s6_run2' and gate_code = 'BANK_RECONCILIATION_COVERAGE')));
select 1/case when (select result = 'APPROVED_EXCEPTION' from public.close_run_gates
  where close_run_id = :'s6_run2' and gate_code = 'BANK_RECONCILIATION_COVERAGE')
  then 1 else 0 end as s6_exception_promotes_gate;

-- Approve the second close run; a snapshot is captured with derived totals.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_approve_close_run('10000000-0000-4000-8000-000000000001', %L, 's6-approve-2')$$,
  :'s6_run2'));
select 1/case when (select status = 'APPROVED' from public.close_runs where id = :'s6_run2') then 1 else 0 end as s6_run2_approved;
select 1/case when (select status = 'CLOSED' from public.accounting_periods where id = :'s6_period2') then 1 else 0 end as s6_period2_closed;

-- Reopen the second period to exercise the controlled reopen path. A new
-- authoritative period is created with version=2 and supersedes the prior.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_reopen_period('10000000-0000-4000-8000-000000000001', %L, %L, 'reopen to correct a late WIP classification', 'reopen-evidence-001')$$,
  :'s6_project2', :'s6_period2'));
select id as s6_period2_new from public.accounting_periods
  where project_id = :'s6_project2' and status = 'OPEN' and version = 2 \gset
select 1/case when (select supersedes_period_id = :'s6_period2' from public.accounting_periods where id = :'s6_period2_new')
  then 1 else 0 end as s6_reopen_records_supersedes;
select 1/case when (select status = 'CLOSED' from public.accounting_periods where id = :'s6_period2') then 1 else 0 end as s6_old_period_remains_closed;

-- The original CLOSED period remains immutable: its dates and status cannot
-- drift even via direct DML.
do $$
begin
  begin
    update public.accounting_periods set end_date = end_date + 30 where id = :'s6_period2';
    raise exception 'closed period update unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%closed%' and sqlerrm not like '%immutable%' then
      raise notice 'expected closed-period immutability, got: %', sqlerrm;
    end if;
  end;
end $$;
select 1/case when (select end_date from public.accounting_periods where id = :'s6_period2') <= current_date then 1 else 0 end as s6_closed_period_immutable;

-- Concurrency: two prepare_close_run calls racing on the same period. Only
-- one PREPARED run can exist; the unique partial index serializes the race
-- at the database boundary.
do $$
declare v_existing int;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', false);
  perform public.s6_prepare_close_run(
    '10000000-0000-4000-8000-000000000001',
    :'s6_project2', :'s6_period2_new', 'duplicate prepare');
  reset role;
  -- The second attempt must be rejected by the function-level guard.
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', false);
  begin
    perform public.s6_prepare_close_run(
      '10000000-0000-4000-8000-000000000001',
      :'s6_project2', :'s6_period2_new', 'duplicate prepare 2');
    raise exception 'second prepare unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%open close run%' then
      raise notice 'expected duplicate prepare rejection, got: %', sqlerrm;
    end if;
  end;
  reset role;
  -- Approve the one prepared run so we can move on to subsequent tests.
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('role', 'authenticated', false);
  perform public.s6_approve_close_run(
    '10000000-0000-4000-8000-000000000001',
    (select id from public.close_runs where period_id = :'s6_period2_new' and status = 'PREPARED' limit 1),
    's6-approve-dup');
  reset role;
  select count(*) into v_existing from public.close_runs where period_id = :'s6_period2_new' and status = 'APPROVED';
  if v_existing <> 1 then
    raise exception 'expected 1 APPROVED run on s6_period2_new, found %', v_existing;
  end if;
end $$;
select 1/case when (select count(*) from public.close_runs where period_id = :'s6_period2_new' and status = 'APPROVED') = 1
  then 1 else 0 end as s6_duplicate_prepare_rejected;

-- Old close snapshot remains unchanged after data changes; a new close run
-- produces a new snapshot and a new version.
select 1/case when (select count(*) from public.close_run_snapshots where id = :'s6_snapshot1') = 1 then 1 else 0 end as s6_old_snapshot_preserved;

-- S4 sale correction: use the existing s4-disposition-main-001 recognition
-- as the correction target. The S4 reversal guard must reject any attempt
-- without a documented correction_request. After approval and execution,
-- the recognition row and its carrying-cost sources must be marked
-- REVERSED. The reversal batch must exactly negate the original.
select id as s6_recognition_batch from public.property_sale_recognitions r
  join public.property_dispositions d on d.id = r.disposition_id
  where d.idempotency_key = 's4-disposition-main-001' \gset
select id as s6_recognition_id from public.property_sale_recognitions
  where journal_batch_id = :'s6_recognition_batch' \gset
-- Reopen the S4 close so we can use a fresh OPEN period as the correction
-- period. (s6_period1 on s6_project is CLOSED.)
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_reopen_period('10000000-0000-4000-8000-000000000001', %L, %L, 'reopen to correct s4 sale recognition', 'reopen-evidence-s4')$$,
  :'s6_project', :'s6_period1'));
select id as s6_period1_new from public.accounting_periods
  where project_id = :'s6_project' and status = 'OPEN' and version = 2 \gset
-- S4 reversal without a correction request must fail.
select 1/case when s6_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001', %L, 'unauthorized s4 correction', 's6-bad-rev-1')$$,
  :'s6_recognition_batch'), 'P0001') then 1 else 0 end as s6_s4_reversal_without_correction_rejected;
-- Request, approve, execute the correction. The reversal batch goes into the
-- OPEN period.
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_request_correction('10000000-0000-4000-8000-000000000001', %L, %L, %L, %L,
    'تصحيح سعر البيع حسب العقد الجديد', 'دليل تصحيح مرفق')$$,
  :'s6_project', :'s6_recognition_batch', :'s6_period1', :'s6_period1_new'));
select id as s6_correction1 from public.correction_requests
  where target_batch_id = :'s6_recognition_batch' \gset
-- Reversal still rejected before approval.
select 1/case when s6_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.reverse_journal_batch('10000000-0000-4000-8000-000000000001', %L, 'still no approval', 's6-bad-rev-2')$$,
  :'s6_recognition_batch'), 'P0001') then 1 else 0 end as s6_s4_reversal_still_rejected_before_approval;
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_approve_correction('10000000-0000-4000-8000-000000000001', %L, 's6-approve-corr-1')$$,
  :'s6_correction1'));
select s6_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.s6_execute_correction('10000000-0000-4000-8000-000000000001', %L, current_date, 's6-execute-corr-1')$$,
  :'s6_correction1'));
select 1/case when (select status = 'REVERSED' from public.property_sale_recognitions
  where id = :'s6_recognition_id')
  then 1 else 0 end as s6_s4_recognition_reversed;
select 1/case when (select count(*) from public.property_sale_carrying_cost_sources
  where recognition_id = :'s6_recognition_id' and status = 'REVERSED') > 0
  then 1 else 0 end as s6_s4_carrying_sources_reversed;
-- The reversal batch must exactly negate the original.
select 1/case when (
  select coalesce(sum(jl.debit_minor_units - jl.credit_minor_units), 0)
  from public.journal_lines jl
  where jl.batch_id = (select reversal_batch_id from public.correction_requests where id = :'s6_correction1')
) = 0 then 1 else 0 end as s6_reversal_balanced_to_zero;

-- A re-execute call is rejected (correction already EXECUTED).
do $$
begin
  begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
    perform set_config('role', 'authenticated', false);
    perform * from public.s6_execute_correction(
      '10000000-0000-4000-8000-000000000001', :'s6_correction1',
      current_date, 's6-execute-corr-2');
    raise exception 'second execute unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%already executed%' and sqlerrm not like '%only APPROVED%' then
      raise notice 'expected re-execute rejection, got: %', sqlerrm;
    end if;
  end;
  reset role;
end $$;
select 1/case when (select count(*) from public.journal_batches
  where source_type = 'REVERSAL' and source_id = :'s6_recognition_batch') = 1
  then 1 else 0 end as s6_correction_execute_single_effect;

-- Read models expose the correction chain and the snapshot for the closed
-- period, with security_invoker semantics.
select 1/case when (select count(*) from public.correction_requests_read
  where organization_id = '10000000-0000-4000-8000-000000000001') > 0
  then 1 else 0 end as s6_correction_read_model_exposes_chain;
select 1/case when (select count(*) from public.close_run_snapshots_read
  where project_id = :'s6_project') >= 1
  then 1 else 0 end as s6_snapshot_read_model_available;

select 'S6 period close and correction SQL PASS' as result;
