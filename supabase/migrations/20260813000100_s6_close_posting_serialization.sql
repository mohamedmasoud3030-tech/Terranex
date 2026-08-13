-- Phase 2C — Period-close / posting serialization hardening.
--
-- Proven defect (reproduced by supabase/tests/29_phase2c_concurrency.sh,
-- Race 3, before this migration): a payment whose batch insert passed the
-- OPEN-period trigger could COMMIT after s6_approve_close_run captured the
-- snapshot and closed the period, leaving a posting dated inside a CLOSED
-- period that the approved snapshot does not contain (silent close-boundary
-- crossing; snapshot cash stayed 0 while a -90000 bank posting landed inside
-- the closed period).
--
-- Fix (forward-only; no applied migration is edited):
--   1. The batch and line period-lock triggers now take FOR SHARE on the
--      covering OPEN period row. A concurrent close approval holds that row
--      FOR UPDATE, so an overlapping posting blocks until the close commits
--      and is then rejected by the same existing OPEN-period rule.
--   2. s6_approve_close_run now locks the period row FOR UPDATE at the start
--      of approval, before totals and snapshot computation. Every in-period
--      posting therefore either commits before the lock (and is visible to
--      the snapshot) or blocks until after the close (and is rejected).
--
-- Together these make posting-versus-close deterministic: the database ends
-- in exactly one valid state and no posting can silently cross the close
-- boundary. Behavior is unchanged outside that race: same rules, same
-- messages, same authorization, no control is weakened.

create or replace function public.s6_validate_posting_in_open_period() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_currency text;
  v_open_period_id uuid;
  v_period_count int;
begin
  -- Reversal postings and S4 disposition control transfer must always be
  -- allowable at the time of correction/reopen. Their accounting date is the
  -- correction date, and S6 keeps reversal/correction in the current open
  -- period by design. A reversal of a previously-closed batch therefore lands
  -- in the current open period and is allowed here.
  -- The only "frozen" fact is normal postings to a closed period. A reversal
  -- by definition is corrective and is therefore allowed when its transaction
  -- date sits in an open period for the batch's project/currency.
  if new.reversal_of_batch_id is not null then
    select jb.project_id into v_currency
    from public.journal_batches jb
    where jb.id = new.reversal_of_batch_id
      and jb.organization_id = new.organization_id;
    if v_currency is null then
      raise exception 'reversal references a missing original batch';
    end if;
  end if;
  -- The period lock is only enforced when an authoritative period has been
  -- opened for this project. Until the S6 close workspace creates the first
  -- period, the S1-S4 setup flow continues to work unchanged. This keeps the
  -- period lock a controlled, opt-in database invariant rather than a hard
  -- gating of every existing financial flow.
  select count(*) into v_period_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id;
  if v_period_count = 0 then
    return new;
  end if;
  -- FOR SHARE serializes with s6_approve_close_run / s6_reopen_period, which
  -- hold the period row FOR UPDATE. A posting overlapping a close approval
  -- blocks until the close commits and is then re-checked against the new
  -- CLOSED state below; it can never commit unseen across the boundary.
  -- At most one OPEN period can cover the date for a project/currency.
  select p.id into v_open_period_id
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id
    and p.status = 'OPEN'
    and new.transaction_date between p.start_date and p.end_date
  for share of p;
  if not found then
    raise exception 'no open accounting period covers transaction_date % for this project', new.transaction_date;
  end if;
  return new;
end $$;

create or replace function public.s6_validate_line_in_open_period() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_open_period_id uuid;
  v_period_count int;
begin
  -- Same opt-in model as the batch-level guard: until an authoritative
  -- period exists for this project, the S1-S4 setup flow continues to
  -- work unchanged. Once a period is opened, the lock is enforced
  -- strictly: every financial posting in that project must fall inside
  -- an OPEN period.
  select count(*) into v_period_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id;
  if v_period_count = 0 then
    return new;
  end if;
  -- Defence in depth: the same FOR SHARE serialization as the batch guard.
  select p.id into v_open_period_id
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id
    and p.status = 'OPEN'
    and new.transaction_date between p.start_date and p.end_date
  for share of p;
  if not found then
    raise exception 'no open accounting period covers line transaction_date % for this project', new.transaction_date;
  end if;
  return new;
end $$;

create or replace function public.s6_approve_close_run(
  p_organization_id uuid, p_close_run_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_run record;
  v_period record;
  v_hash text;
  v_existing record;
  v_fail_count int;
  v_fail_count_text text;
  v_snapshot_id uuid;
  v_totals jsonb;
  v_currency text;
  v_period_id_text text;
  v_project_id_text text;
  v_committed text;
  v_called text;
  v_contributed text;
  v_receivable text;
  v_project_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  select encode(digest(p_close_run_id::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-approve:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.close_runs
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_close_run_id or v_existing.approval_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;
  select * into v_run from public.close_runs
  where id = p_close_run_id and organization_id = p_organization_id for update;
  if not found then raise exception 'close run not found'; end if;
  v_project_id := v_run.project_id;
  if v_run.status <> 'PREPARED' then
    raise exception 'only a PREPARED run can be approved';
  end if;
  -- Serialization boundary: lock the period row BEFORE reading any state.
  -- In-period postings take FOR SHARE on this row in the posting triggers,
  -- so from this point every concurrent posting either has already committed
  -- (and is visible to the totals/snapshot below) or blocks until this
  -- approval commits and is then rejected by the period lock. No posting can
  -- silently cross the close boundary.
  select * into v_period from public.accounting_periods
  where id = v_run.period_id for update;
  select count(*) into v_fail_count
  from public.close_run_gates
  where close_run_id = p_close_run_id and result = 'FAIL';
  if v_fail_count > 0 then
    raise exception 'cannot approve a run with failing gates; request exceptions first';
  end if;
  -- Compute totals and content hash, persist the snapshot. We assign each
  -- intermediate to a local variable to keep the SELECT context small
  -- and avoid the function parameter being treated as a column inside a
  -- jsonb_build_object(... p_project_id ...) expression.
  select reporting_currency into v_currency
  from public.investment_projects
  where id = v_project_id;

  select coalesce((select sum(
        case when sa.role = 'BANK_CASH' then jl.debit_minor_units - jl.credit_minor_units else 0 end
      )
    ), 0)
  into v_fail_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jl.organization_id = p_organization_id
    and jl.project_id = v_project_id
    and jl.transaction_date <= v_run.source_cutoff_date
    and jl.currency = v_currency;
  v_fail_count_text := v_fail_count::text;

  -- Pre-compute totals into local variables to keep the function arguments
  -- out of the jsonb_build_object context.
  select coalesce(pcp.committed_minor_units, '0'),
         coalesce(pcp.called_minor_units, '0'),
         coalesce(pcp.contributed_minor_units, '0'),
         coalesce(pcp.receivable_minor_units, '0')
  into v_committed, v_called, v_contributed, v_receivable
  from public.project_capital_position_read pcp
  where pcp.project_id = v_project_id
    and pcp.organization_id = p_organization_id;
  -- Recognize revenue totals separately. v_fail_count is reused as
  -- recognized_revenue_minor_units at this stage.
  select coalesce(sum(r.recognized_proceeds_minor_units), 0)
    into v_fail_count
  from public.property_sale_recognitions r
  where r.organization_id = p_organization_id
    and r.project_id = v_project_id
    and r.status = 'ACTIVE'
    and r.recognition_date <= v_run.source_cutoff_date;
  v_period_id_text := v_run.period_id::text;
  v_project_id_text := v_project_id::text;
  v_totals := jsonb_build_object(
    'project_id', v_project_id_text,
    'period_id', v_period_id_text,
    'currency', v_currency,
    'cash_minor_units', v_fail_count_text::text,
    'committed_capital_minor_units', v_committed,
    'called_minor_units', v_called,
    'contributed_minor_units', v_contributed,
    'receivable_minor_units', v_receivable,
    'recognized_revenue_minor_units', v_fail_count::text,
    'carrying_cost_derecognized_minor_units', '0',
    'realized_result_minor_units', '0',
    'collected_cash_minor_units', '0',
    'outstanding_receivable_minor_units', '0'
  );
  insert into public.close_run_snapshots(
    organization_id, close_run_id, project_id, period_id, content_hash, totals
  ) values (
    p_organization_id, p_close_run_id, v_project_id, v_run.period_id,
    encode(digest(v_totals::text, 'sha256'), 'hex'),
    v_totals
  ) returning id into v_snapshot_id;
  -- Mark the run approved.
  update public.close_runs
  set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
    approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
  where id = p_close_run_id;
  -- Close the period (the row is already locked by this transaction).
  update public.accounting_periods
  set status = 'CLOSED', closed_at = now(), closed_by = v_actor,
    source_close_run_id = p_close_run_id
  where id = v_period.id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CLOSE_RUN_APPROVED', 'close_run', p_close_run_id,
    jsonb_build_object('project_id', v_project_id, 'period_id', v_run.period_id,
      'version', v_run.version, 'snapshot_id', v_snapshot_id));
  return p_close_run_id;
end $$;
revoke all on function public.s6_approve_close_run(uuid,uuid,text) from public, anon;
grant execute on function public.s6_approve_close_run(uuid,uuid,text) to authenticated;
