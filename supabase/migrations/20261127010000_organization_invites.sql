-- Organization member invites (first-trial readiness).
--
-- An OWNER creates a single-use, expiring invite link for an organization.
-- The raw token is returned to the creator exactly once; only its SHA-256
-- hash is stored. A signed-in user who holds the link accepts it and becomes
-- a MEMBER of the organization. An existing membership is reactivated but
-- never demoted (an OWNER who accepts a MEMBER invite stays OWNER).
--
-- No invitation e-mail is sent: Supabase Auth e-mail on the free plan is
-- rate-limited, so the product surfaces a copyable link the owner passes to
-- the invitee through any channel they choose.

create table public.organization_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  token_hash text not null unique check (char_length(token_hash) = 64),
  role text not null default 'MEMBER' check (role = 'MEMBER'),
  note text check (note is null or char_length(trim(note)) between 1 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  revoked_at timestamptz,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  unique (organization_id, idempotency_key),
  check (expires_at > created_at),
  check (accepted_at is null or accepted_by is not null)
);

alter table public.organization_invites enable row level security;

-- Members may list their own organization's invites. Writes stay behind the
-- SECURITY DEFINER commands below; no insert/update/delete policy exists.
create policy organization_invites_member_read on public.organization_invites
  for select to authenticated using (public.is_active_member(organization_id));

-- Read projection without the token hash or command key.
create or replace view public.organization_invites_read with (security_invoker=on) as
select
  id,
  organization_id,
  role,
  note,
  created_by,
  created_at,
  expires_at,
  accepted_by,
  accepted_at,
  revoked_at,
  case
    when revoked_at is not null then 'REVOKED'
    when accepted_at is not null then 'ACCEPTED'
    when expires_at <= now() then 'EXPIRED'
    else 'PENDING'
  end as status
from public.organization_invites;

create or replace function public.create_organization_invite(
  p_organization_id uuid,
  p_note text,
  p_idempotency_key text
) returns text language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_existing record;
  v_invite_id uuid := gen_random_uuid();
  v_token text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_note is not null and char_length(trim(p_note)) not between 1 and 200 then
    raise exception 'invalid invite note';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':org-invite:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.organization_invites
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.note is not distinct from nullif(trim(coalesce(p_note, '')), '') then
      -- Exact replay of a confirmed command. The raw token was returned once
      -- and is deliberately not recoverable; an empty return tells the caller
      -- the invite already exists without minting a second one.
      return '';
    end if;
    raise exception 'idempotency key payload mismatch';
  end if;

  -- 244 bits of entropy from two v4 UUIDs, hex without dashes (64 chars).
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  insert into public.organization_invites(
    id, organization_id, token_hash, note, created_by, expires_at, idempotency_key
  ) values (
    v_invite_id, p_organization_id,
    encode(digest(v_token, 'sha256'), 'hex'),
    nullif(trim(coalesce(p_note, '')), ''), v_actor,
    now() + interval '7 days', trim(p_idempotency_key)
  );

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'ORGANIZATION_INVITE_CREATED', 'organization_invite', v_invite_id,
    jsonb_build_object('note', nullif(trim(coalesce(p_note, '')), '')));
  return v_token;
end $$;

create or replace function public.preview_organization_invite(p_token text)
returns table(organization_name text, invite_status text)
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_inv record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_token is null or char_length(trim(p_token)) <> 64 then return; end if;
  select i.id, i.revoked_at, i.accepted_at, i.expires_at, o.name
    into v_inv
  from public.organization_invites i
  join public.organizations o on o.id = i.organization_id
  where i.token_hash = encode(digest(trim(p_token), 'sha256'), 'hex');
  if not found then return; end if;
  return query select v_inv.name,
    case
      when v_inv.revoked_at is not null then 'REVOKED'
      when v_inv.accepted_at is not null then 'ACCEPTED'
      when v_inv.expires_at <= now() then 'EXPIRED'
      else 'PENDING'
    end;
end $$;

create or replace function public.accept_organization_invite(p_token text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_inv record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if p_token is null or char_length(trim(p_token)) <> 64 then
    raise exception 'invalid invite token';
  end if;
  select * into v_inv from public.organization_invites
  where token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
  for update;
  if not found then raise exception 'invite not found'; end if;
  if v_inv.revoked_at is not null then raise exception 'invite revoked'; end if;
  if v_inv.expires_at <= now() then raise exception 'invite expired'; end if;
  if v_inv.accepted_at is not null then
    -- A retry by the same invitee is an idempotent replay, not reuse.
    if v_inv.accepted_by = v_actor then return v_inv.organization_id; end if;
    raise exception 'invite already used';
  end if;

  insert into public.memberships(organization_id, user_id, role, status)
  values (v_inv.organization_id, v_actor, v_inv.role, 'ACTIVE')
  on conflict (organization_id, user_id) do update
    set status = 'ACTIVE'
  where public.memberships.status <> 'ACTIVE';

  update public.organization_invites
    set accepted_by = v_actor, accepted_at = now()
  where id = v_inv.id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (v_inv.organization_id, v_actor, 'ORGANIZATION_INVITE_ACCEPTED', 'organization_invite', v_inv.id,
    jsonb_build_object('member_user_id', v_actor));
  return v_inv.organization_id;
end $$;

create or replace function public.revoke_organization_invite(
  p_organization_id uuid,
  p_invite_id uuid
) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  update public.organization_invites
    set revoked_at = now()
  where id = p_invite_id
    and organization_id = p_organization_id
    and accepted_at is null
    and revoked_at is null;
  if not found then raise exception 'invite not found or already closed'; end if;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'ORGANIZATION_INVITE_REVOKED', 'organization_invite', p_invite_id,
    jsonb_build_object('revoked_by', v_actor));
end $$;

revoke all on public.organization_invites from anon, authenticated;
grant select on public.organization_invites, public.organization_invites_read to authenticated;

revoke all on function public.create_organization_invite(uuid, text, text) from public, anon;
revoke all on function public.preview_organization_invite(text) from public, anon;
revoke all on function public.accept_organization_invite(text) from public, anon;
revoke all on function public.revoke_organization_invite(uuid, uuid) from public, anon;
grant execute on function public.create_organization_invite(uuid, text, text) to authenticated;
grant execute on function public.preview_organization_invite(text) to authenticated;
grant execute on function public.accept_organization_invite(text) to authenticated;
grant execute on function public.revoke_organization_invite(uuid, uuid) to authenticated;

-- Hosted Supabase installs pgcrypto in the `extensions` schema while a plain
-- PostgreSQL replay installs it in `public` (see
-- 20260813000500_pgcrypto_digest_schema_compat.sql). Qualify the digest calls
-- in the functions created above the same way so the locked search_path stays
-- portable across both layouts.
do $invite_pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  r record;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;
  for r in
    select p.oid, p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('create_organization_invite', 'preview_organization_invite', 'accept_organization_invite')
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
    order by p.oid::regprocedure::text
  loop
    v_definition := pg_get_functiondef(r.oid);
    v_rewritten := regexp_replace(
      v_definition,
      '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
      E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
      'g'
    );
    if v_rewritten = v_definition then
      raise exception 'failed to qualify pgcrypto digest in %', r.signature;
    end if;
    execute v_rewritten;
  end loop;
end
$invite_pgcrypto_compat$;
