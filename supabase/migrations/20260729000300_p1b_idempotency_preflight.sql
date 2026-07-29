-- =============================================================================
-- Terranex — P1B request replay preflight
-- =============================================================================
-- Wraps transaction creation with an early cache lookup. The core function still
-- owns validation, locking, writes and audit; retries can return after the target
-- graph has changed without duplicating the full implementation here.
-- =============================================================================

create or replace function public.terranex_audit_check_idempotent(
  p_request_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
stable
as $fn$
  select result
  from public.financial_audit_logs
  where request_id = p_request_id
    and (auth.uid() is null or owner_id = auth.uid())
  order by owner_id
  limit 1;
$fn$;

do $migration$
begin
  if to_regprocedure('public.record_transaction_atomic_core(uuid,jsonb,jsonb)') is null then
    alter function public.record_transaction_atomic(uuid, jsonb, jsonb)
      rename to record_transaction_atomic_core;
  end if;
end;
$migration$;

create or replace function public.record_transaction_atomic(
  p_request_id uuid,
  p_transaction jsonb,
  p_payable jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cached jsonb;
begin
  v_cached := public.terranex_audit_check_idempotent(p_request_id);
  if v_cached is not null then
    return v_cached;
  end if;

  return public.record_transaction_atomic_core(
    p_request_id,
    p_transaction,
    p_payable
  );
end;
$fn$;

-- Only the public wrapper is callable by the application. The renamed core is
-- private and is reached exclusively through the wrapper.
revoke execute on function public.record_transaction_atomic_core(uuid, jsonb, jsonb)
  from public, anon, authenticated;
revoke execute on function public.terranex_audit_check_idempotent(uuid)
  from public, anon, authenticated;
revoke execute on function public.record_transaction_atomic(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function public.record_transaction_atomic(uuid, jsonb, jsonb)
  to authenticated;

\echo '=== P1B REQUEST REPLAY PREFLIGHT: MIGRATION COMPLETE ==='
