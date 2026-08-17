-- Recovery DEF-002 — project creation command identity.
--
-- Project names are descriptive metadata, not command identities. The previous
-- RPC treated (organization, sector, normalized name) as an idempotency key and
-- could therefore return an older project even when the operator supplied a
-- different internal reference or description. Introduce explicit command
-- identity while preserving historical RPC arities for compatibility.

alter table public.investment_projects
  add column if not exists creation_idempotency_key text,
  add column if not exists creation_request_hash text;

alter table public.investment_projects
  add constraint investment_projects_creation_idempotency_key_check
    check (
      creation_idempotency_key is null
      or char_length(creation_idempotency_key) between 8 and 120
    ),
  add constraint investment_projects_creation_request_hash_check
    check (
      creation_request_hash is null
      or char_length(creation_request_hash) = 64
    ),
  add constraint investment_projects_creation_command_pair_check
    check (
      (creation_idempotency_key is null and creation_request_hash is null)
      or (creation_idempotency_key is not null and creation_request_hash is not null)
    );

create unique index if not exists investment_projects_creation_command_key
  on public.investment_projects(organization_id, creation_idempotency_key)
  where creation_idempotency_key is not null;

-- Uses PostgreSQL's built-in SHA-256 binary-string function so the definition
-- is portable across hosted Supabase (pgcrypto in extensions) and plain
-- PostgreSQL replay environments.
create or replace function public.project_creation_request_hash(
  p_name text,
  p_internal_reference text,
  p_description text,
  p_sector text
) returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(
    sha256(
      convert_to(
        jsonb_build_array(
          trim(p_name),
          nullif(trim(p_internal_reference), ''),
          nullif(trim(p_description), ''),
          upper(trim(coalesce(p_sector, '')))
        )::text,
        'UTF8'
      )
    ),
    'hex'
  )
$$;
revoke all on function public.project_creation_request_hash(text,text,text,text)
  from public, anon, authenticated;

-- Canonical command-aware RPC. A logical command owns one explicit key.
create or replace function public.create_investment_project(
  p_organization_id uuid,
  p_name text,
  p_internal_reference text,
  p_description text,
  p_sector text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid;
  v_sector text;
  v_hash text;
  v_existing record;
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
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_sector := upper(trim(coalesce(p_sector, '')));
  if v_sector not in ('REAL_ESTATE','AGRICULTURE','LIVESTOCK') then
    raise exception 'invalid sector';
  end if;
  v_hash := public.project_creation_request_hash(
    p_name, p_internal_reference, p_description, v_sector
  );

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':project-create:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.investment_projects
   where organization_id = p_organization_id
     and creation_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.creation_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.investment_projects(
    organization_id,
    name,
    internal_reference,
    description,
    sector,
    creation_idempotency_key,
    creation_request_hash
  ) values (
    p_organization_id,
    trim(p_name),
    nullif(trim(p_internal_reference), ''),
    nullif(trim(p_description), ''),
    v_sector,
    trim(p_idempotency_key),
    v_hash
  ) returning id into v_project;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id,
    v_actor,
    'PROJECT_CREATED',
    'investment_project',
    v_project,
    jsonb_build_object('name', trim(p_name), 'sector', v_sector)
  );

  return v_project;
end $$;

revoke all on function public.create_investment_project(uuid,text,text,text,text,text)
  from public, anon;
grant execute on function public.create_investment_project(uuid,text,text,text,text,text)
  to authenticated;

-- Preserve the existing 5-argument contract for historical callers, but stop
-- using project name as command identity. Exact legacy payloads deterministically
-- replay; a changed payload derives a different key and creates a different
-- project instead of silently returning the wrong one. The 2/3/4-argument
-- Real-Estate compatibility wrapper already delegates to this signature.
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
  v_hash text;
begin
  v_hash := public.project_creation_request_hash(
    p_name, p_internal_reference, p_description, p_sector
  );
  return public.create_investment_project(
    p_organization_id,
    p_name,
    p_internal_reference,
    p_description,
    p_sector,
    'legacy-' || v_hash
  );
end $$;

revoke all on function public.create_investment_project(uuid,text,text,text,text)
  from public, anon;
grant execute on function public.create_investment_project(uuid,text,text,text,text)
  to authenticated;
