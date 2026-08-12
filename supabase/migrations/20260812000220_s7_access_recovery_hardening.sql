-- GF-009 / S7 — Access revocation and recovery hardening.
--
-- Scope is deliberately minimal: no RBAC framework, no permission matrix, no
-- role editor. S7 adds only the two controls a controlled pilot cannot run
-- without:
--
--   1. an audited, owner-only membership activation/revocation command whose
--      effect is immediate for every existing session, because every read
--      policy and every privileged command re-evaluates `is_active_member` /
--      `s2_is_owner` inside PostgreSQL on each statement; and
--   2. a database-level recovery guard that makes it impossible to strand an
--      organization without an active owner.
--
-- Maker/checker rules established by S5/S7 are untouched. Nothing here can
-- grant a member the ability to approve their own allocation, distribution,
-- opening import, or reconciliation sign-off.

-- ===========================================================================
-- 1. Recovery guard: an organization always keeps at least one active OWNER.
-- ===========================================================================
-- The guard covers the revocation/demotion path (UPDATE). Physical deletion of
-- a membership row is not a product command: memberships are only removed by
-- cascading an entire organization away, where "the organization keeps an
-- owner" is meaningless.
create or replace function public.s7_guard_last_active_owner() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_remaining integer;
begin
  if not (old.role = 'OWNER' and old.status = 'ACTIVE') then return new; end if;
  if new.role = 'OWNER' and new.status = 'ACTIVE' then return new; end if;
  select count(*) into v_remaining
  from public.memberships m
  where m.organization_id = old.organization_id
    and m.role = 'OWNER' and m.status = 'ACTIVE'
    and m.id <> old.id;
  if v_remaining = 0 then
    raise exception 'an organization must keep at least one active owner';
  end if;
  return new;
end $$;
create trigger memberships_last_active_owner_guard
before update on public.memberships
for each row execute function public.s7_guard_last_active_owner();

-- ===========================================================================
-- 2. Owner-only membership status command.
--    Authorization is re-checked inside the database on every call; a browser
--    session that was an owner a moment ago cannot replay this command after
--    its own membership was revoked.
-- ===========================================================================
create or replace function public.s7_set_membership_status(
  p_organization_id uuid, p_user_id uuid, p_status text, p_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_membership record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_status not in ('ACTIVE','INACTIVE') then raise exception 'invalid membership status'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500
     or public.s7_has_unsafe_control_characters(p_reason) then
    raise exception 'a membership change reason is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-membership:' || p_user_id::text, 0));
  select * into v_membership from public.memberships
  where organization_id = p_organization_id and user_id = p_user_id for update;
  if not found then raise exception 'membership not found'; end if;
  if v_membership.status = p_status then return v_membership.id; end if;

  update public.memberships set status = p_status where id = v_membership.id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor,
    case when p_status = 'ACTIVE' then 'S7_MEMBERSHIP_REACTIVATED' else 'S7_MEMBERSHIP_REVOKED' end,
    'membership', v_membership.id,
    jsonb_build_object('user_id', p_user_id, 'role', v_membership.role,
      'previous_status', v_membership.status, 'new_status', p_status,
      'reason', trim(p_reason)));
  return v_membership.id;
end $$;

revoke all on function public.s7_set_membership_status(uuid,uuid,text,text,text) from public, anon;
grant execute on function public.s7_set_membership_status(uuid,uuid,text,text,text) to authenticated;

-- ===========================================================================
-- 3. Membership read model. It exposes no secret and no PII beyond the user id
--    the caller already holds through their own organization membership.
-- ===========================================================================
create or replace view public.s7_membership_access_read with (security_invoker=on) as
select
  m.id as membership_id,
  m.organization_id,
  m.user_id,
  m.role,
  m.status,
  (m.status = 'ACTIVE') as has_access,
  m.created_at
from public.memberships m;
grant select on public.s7_membership_access_read to authenticated;
