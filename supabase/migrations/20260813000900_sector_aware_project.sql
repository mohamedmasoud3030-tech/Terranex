-- GF-013 / Sector-aware investment project.
--
-- Adds Agriculture as a second sector without weakening the existing
-- Real Estate path. The canonical sector vocabulary is now:
--
--     REAL_ESTATE | AGRICULTURE
--
-- (Livestock remains deferred; ADR 0012 keeps the construction order
-- Real Estate → Agriculture → Livestock.)
--
-- The project RPC is upgraded without introducing an ambiguous
-- PostgREST overload. We keep the original 4-argument signature as a
-- thin compatibility wrapper used by S0 tests and the historical test
-- suite, and add a new 5-argument signature that takes the explicit
-- sector. Browser/server code must call the new RPC; the old wrapper
-- is Real-Estate-only and routes through it for backward compatibility.
--
-- No existing Real Estate row, function, view, or test is weakened.

-- ===========================================================================
-- 1. Expand the authoritative sector vocabulary
-- ===========================================================================
alter table public.investment_projects
  drop constraint investment_projects_sector_check;
alter table public.investment_projects
  add constraint investment_projects_sector_check
    check (sector in ('REAL_ESTATE','AGRICULTURE'));

-- ===========================================================================
-- 2. Server-authoritative sector-aware project creation
-- ===========================================================================
create or replace function public.create_investment_project(
  p_organization_id uuid,
  p_name text,
  p_internal_reference text,
  p_description text,
  p_sector text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid;
  v_hash text;
  v_existing record;
  v_sector text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid project name';
  end if;
  if p_internal_reference is not null and char_length(trim(p_internal_reference)) > 80 then
    raise exception 'invalid internal reference';
  end if;
  if p_description is not null and char_length(trim(p_description)) > 2000 then
    raise exception 'invalid description';
  end if;
  v_sector := upper(trim(coalesce(p_sector, '')));
  if v_sector not in ('REAL_ESTATE','AGRICULTURE') then
    raise exception 'invalid sector';
  end if;

  select encode(digest(p_organization_id::text || '|' || trim(p_name) || '|'
         || coalesce(trim(p_internal_reference),'') || '|' || v_sector,
         'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s0-project:' || trim(p_name) || ':' || v_sector, 0));

  -- Idempotent on identical payload: a project with the same canonical
  -- name and sector in the same organization may only be created once.
  select * into v_existing
    from public.investment_projects
   where organization_id = p_organization_id
     and sector = v_sector
     and lower(trim(name)) = lower(trim(p_name))
   limit 1;
  if found then
    return v_existing.id;
  end if;

  insert into public.investment_projects(
    organization_id, name, internal_reference, description, sector
  ) values (
    p_organization_id, trim(p_name),
    nullif(trim(p_internal_reference), ''),
    nullif(trim(p_description), ''),
    v_sector
  )
  returning id into v_project;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_CREATED', 'investment_project', v_project,
    jsonb_build_object('name', trim(p_name), 'sector', v_sector)
  );

  return v_project;
end $$;

-- Real Estate compatibility path: the original 4-arg signature is
-- preserved as a strict wrapper that locks sector to REAL_ESTATE so
-- every existing call site and test continues to create a Real Estate
-- project without change.
create or replace function public.create_investment_project(
  p_organization_id uuid,
  p_name text,
  p_internal_reference text,
  p_description text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return public.create_investment_project(
    p_organization_id, p_name, p_internal_reference, p_description, 'REAL_ESTATE'
  );
end $$;

-- ===========================================================================
-- 3. Surface sector on the read path used by the application
-- ===========================================================================
-- The application already selects the row directly from
-- investment_projects; sector is now a column on the same row, so the
-- existing queries naturally include it. No view change required.

-- ===========================================================================
-- 4. Privileges — unchanged; the new RPC is granted to the same role as
--    the original.
-- ===========================================================================
revoke all on function public.create_investment_project(uuid,text,text,text,text) from public, anon;
grant execute on function public.create_investment_project(uuid,text,text,text,text) to authenticated;
