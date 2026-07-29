-- Restore the unwrapped transaction RPC before the base P1B rollback runs.
drop function if exists public.record_transaction_atomic(uuid, jsonb, jsonb);

do $rollback$
begin
  if to_regprocedure('public.record_transaction_atomic_core(uuid,jsonb,jsonb)') is not null then
    alter function public.record_transaction_atomic_core(uuid, jsonb, jsonb)
      rename to record_transaction_atomic;
  end if;
end;
$rollback$;

drop function if exists public.terranex_audit_check_idempotent(uuid);

\echo '=== ROLLBACK P1B REQUEST REPLAY PREFLIGHT: COMPLETE ==='
