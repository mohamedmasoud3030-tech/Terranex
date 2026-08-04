-- Preserve caller-derived tenant isolation without erasing trusted server/RPC ownership.
--
-- The original trigger always assigned auth.uid(). That is correct for browser writes,
-- but it replaced an explicit, already validated owner_id with NULL in trusted server
-- contexts (PostgreSQL tests, service-role jobs, and SECURITY DEFINER lifecycles without
-- a JWT claim). Cash lifecycle RPCs then failed after creating no partial state.

create or replace function trg_force_owner()
returns trigger
language plpgsql
security invoker
set search_path = public, auth, pg_temp
as $$
declare
  v_authenticated_owner uuid := auth.uid();
begin
  if v_authenticated_owner is not null then
    if new.owner_id is not null and new.owner_id <> v_authenticated_owner then
      raise exception using
        errcode = '42501',
        message = 'owner_id cannot differ from the authenticated owner';
    end if;
    new.owner_id := v_authenticated_owner;
  elsif new.owner_id is null then
    raise exception using
      errcode = '23502',
      message = 'owner_id requires authenticated context or trusted server derivation';
  end if;

  return new;
end;
$$;

comment on function trg_force_owner() is
  'Derives owner_id from auth.uid() for authenticated writes and preserves an explicit owner_id only for trusted server contexts without a JWT owner.';
