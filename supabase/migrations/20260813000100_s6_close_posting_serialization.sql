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
-- Fix (forward-only; no applied migration is edited and no existing function
-- body is restated):
--   1. Two small additive triggers take FOR SHARE on the covering OPEN period
--      row on every journal batch/line insert. They run before the existing
--      period-lock guards (trigger names sort first) and change no rule and
--      no message: the existing guards keep raising exactly as before.
--   2. The existing s6_approve_close_run is renamed untouched to an internal
--      function (execute revoked from API roles) and a thin public wrapper
--      keeps the identical contract, first locking the period row FOR UPDATE
--      after owner authorization, then delegating. The lock precedes the
--      delegated totals/snapshot computation, so every in-period posting
--      either commits before the lock (visible to the snapshot) or blocks
--      until the close commits and is then rejected by the existing guards.
--      The internal function is not executable by anon/authenticated/public,
--      so the race cannot be reintroduced through a direct call.
--
-- Result: posting-versus-close is deterministic; the database ends in exactly
-- one valid state and no posting can silently cross the close boundary.

create or replace function public.s6_take_open_period_share_lock() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_open_period_id uuid;
begin
  -- Serialize with close approval / reopen, which hold the period row
  -- FOR UPDATE. If no OPEN period covers the posting date, this selects
  -- nothing and the existing authoritative guard raises the exact message.
  select p.id into v_open_period_id
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id
    and p.status = 'OPEN'
    and new.transaction_date between p.start_date and p.end_date
  for share of p;
  return new;
end $$;

drop trigger if exists a_s6_close_serialization_batch_lock on public.journal_batches;
create trigger a_s6_close_serialization_batch_lock
before insert on public.journal_batches
for each row execute function public.s6_take_open_period_share_lock();

drop trigger if exists a_s6_close_serialization_line_lock on public.journal_lines;
create trigger a_s6_close_serialization_line_lock
before insert on public.journal_lines
for each row execute function public.s6_take_open_period_share_lock();

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
