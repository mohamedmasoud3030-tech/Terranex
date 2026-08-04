-- Restore the pre-00700 owner derivation behavior.
-- Migration 20260802001400's rollback subsequently removes the trigger/function.

create or replace function trg_force_owner()
returns trigger
language plpgsql
security invoker
set search_path = public, auth, pg_temp
as $$
begin
  new.owner_id := auth.uid();
  return new;
end;
$$;
