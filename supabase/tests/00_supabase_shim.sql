-- =============================================================================
-- Terranex — test harness: minimal Supabase-compatible shim
-- =============================================================================
-- Recreates ONLY the pieces of a Supabase project that the migrations depend
-- on, so the schema can be applied to a plain Postgres in CI:
--
--   - roles `anon`, `authenticated`, `service_role`
--   - schema `auth` with `auth.users`
--   - `auth.uid()` reading request.jwt.claim.sub, as Supabase does
--
-- This shim is for the DATABASE tests only. It is never applied to a real
-- Supabase project, which already provides all of the above.
--
-- NOTE: this is a harness, not a fake of the kind Phase 1A forbids. The
-- migrations, RLS, and RPCs under test are the real artefacts, running on a
-- real Postgres. Only the surrounding Supabase scaffolding is reproduced.
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

create schema if not exists auth;

create table if not exists auth.users (
  id         uuid primary key default gen_random_uuid(),
  email      text unique,
  created_at timestamptz not null default now()
);

-- Supabase resolves the current user from the JWT claims injected by PostgREST.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;

-- The migrations run as the bootstrap superuser; these roles need to be able to
-- reach objects in `public`.
grant usage on schema public to anon, authenticated, service_role;
