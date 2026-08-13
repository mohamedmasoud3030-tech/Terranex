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
-- Fix (forward-only; no applied migration is edited, and no function body is
-- restated):
--   1. The batch and line period-lock triggers now take FOR SHARE on the
--      covering OPEN period row. A concurrent close approval holds that row
--      FOR UPDATE, so an overlapping posting blocks until the close commits
--      and is then rejected by the same existing OPEN-period rule.
--   2. The existing s6_approve_close_run is renamed to an internal function
--      (its body is untouched) and execute is revoked from API roles. A new,
--      thin s6_approve_close_run keeps the identical public contract and
--      first locks the period row FOR UPDATE (after owner authorization),
--      then delegates. Because the lock precedes the delegated totals and
--      snapshot computation, every in-period posting either commits before
--      the lock (and is visible to the snapshot) or blocks until after the
--      close (and is rejected). No posting can silently cross the boundary.
--      Directly calling the internal function cannot reintroduce the race:
--      it is not executable by anon/authenticated/public.
--
-- Behavior outside the race is unchanged: same public signature, same rules,
-- same messages, same authorization; no control is weakened.

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
  -- FOR SHARE serializes with close approval / reopen, which hold the period
  -- row FOR UPDATE. A posting overlapping a close approval blocks until the
  -- close commits and is then re-checked against the new CLOSED state; it can
  -- never commit unseen across the boundary. At most one OPEN period can
  -- cover the date for a project/currency.
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

-- Rename the proven approval body; it is unchanged. The wrapper below owns
-- the public contract and adds the serialization boundary.
alter function public.s6_approve_close_run(uuid, uuid, text)
  rename to s6_approve_close_run_impl;
revoke all on function public.s6_approve_close_run_impl(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.s6_approve_close_run(
  p_organization_id uuid, p_close_run_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_period_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  -- Serialization boundary: lock the period row BEFORE any delegated state
  -- read. In-period postings take FOR SHARE on this row in the posting
  -- triggers, so from this point every concurrent posting either has already
  -- committed (and is visible to the delegated totals/snapshot) or blocks
  -- until this approval commits and is then rejected by the period lock.
  select period_id into v_period_id
  from public.close_runs
  where id = p_close_run_id and organization_id = p_organization_id;
  if found then
    perform 1 from public.accounting_periods
    where id = v_period_id for update;
  end if;

  return public.s6_approve_close_run_impl(p_organization_id, p_close_run_id, p_idempotency_key);
end $$;
revoke all on function public.s6_approve_close_run(uuid, uuid, text) from public, anon;
grant execute on function public.s6_approve_close_run(uuid, uuid, text) to authenticated;
