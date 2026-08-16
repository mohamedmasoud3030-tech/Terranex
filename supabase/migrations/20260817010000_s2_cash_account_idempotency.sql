-- S2 corrective hardening — make project cash-account creation genuinely
-- idempotent. The original S2 migration labels create_project_cash_account as
-- an idempotent command, but its four-argument implementation performs a plain
-- INSERT and has no retry key/replay contract. A response-loss retry can
-- therefore create a second cash account.

alter table public.project_cash_accounts
  add column if not exists idempotency_key text,
  add column if not exists request_hash text;

alter table public.project_cash_accounts
  drop constraint if exists project_cash_accounts_idempotency_metadata_check;

alter table public.project_cash_accounts
  add constraint project_cash_accounts_idempotency_metadata_check check (
    (idempotency_key is null and request_hash is null)
    or (
      idempotency_key is not null
      and char_length(idempotency_key) between 8 and 120
      and request_hash is not null
      and char_length(request_hash) = 64
    )
  );

create unique index if not exists project_cash_accounts_idempotency_uidx
  on public.project_cash_accounts(organization_id, idempotency_key)
  where idempotency_key is not null;

-- Replace the legacy non-idempotent implementation. A compatibility overload
-- is recreated below after the authoritative five-argument command exists.
revoke execute on function public.create_project_cash_account(uuid, uuid, text, text)
  from authenticated;
drop function public.create_project_cash_account(uuid, uuid, text, text);

create function public.create_project_cash_account(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_currency text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_project_currency text;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;
  if not public.is_active_member(p_organization_id) then
    raise exception 'forbidden';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 120 then
    raise exception 'invalid account name';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid currency';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency
    into v_project_currency
  from public.investment_projects
  where id = p_project_id
    and organization_id = p_organization_id;

  if v_project_currency is null then
    raise exception 'project not found';
  end if;
  if p_currency <> v_project_currency then
    raise exception 'account currency must match project currency';
  end if;

  select encode(
    digest(
      jsonb_build_object(
        'project_id', p_project_id,
        'name', trim(p_name),
        'currency', p_currency
      )::text,
      'sha256'
    ),
    'hex'
  ) into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':cash-account:' || trim(p_idempotency_key),
    0
  ));

  select id, request_hash
    into v_existing
  from public.project_cash_accounts
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);

  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.project_cash_accounts(
    organization_id,
    project_id,
    name,
    currency,
    idempotency_key,
    request_hash
  ) values (
    p_organization_id,
    p_project_id,
    trim(p_name),
    p_currency,
    trim(p_idempotency_key),
    v_hash
  )
  returning id into v_id;

  insert into public.audit_events(
    organization_id,
    actor_id,
    event_type,
    entity_type,
    entity_id,
    payload
  ) values (
    p_organization_id,
    v_actor,
    'CASH_ACCOUNT_CREATED',
    'project_cash_account',
    v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'name', trim(p_name),
      'currency', p_currency
    )
  );

  return v_id;
end
$$;

revoke all on function public.create_project_cash_account(uuid, uuid, text, text, text)
  from public, anon;
grant execute on function public.create_project_cash_account(uuid, uuid, text, text, text)
  to authenticated;

-- Hosted Supabase may keep pgcrypto in extensions while local replay may keep
-- it in public. Keep SECURITY DEFINER search_path locked and qualify digest in
-- the function definition using the extension's actual schema, matching the
-- repository's established pgcrypto compatibility strategy.
do $cash_account_pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  v_oid oid;
begin
  select n.nspname
    into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;

  select p.oid
    into v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_project_cash_account'
    and pg_get_function_identity_arguments(p.oid)
      = 'p_organization_id uuid, p_project_id uuid, p_name text, p_currency text, p_idempotency_key text';

  if v_oid is null then
    raise exception 'create_project_cash_account identity not found for pgcrypto qualification';
  end if;

  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := regexp_replace(
    v_definition,
    '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
    E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
    'g'
  );

  if v_rewritten = v_definition then
    raise exception 'failed to qualify pgcrypto digest in create_project_cash_account';
  end if;

  execute v_rewritten;
end
$cash_account_pgcrypto_compat$;

-- Backward-compatible overload for cached/older clients. It is no longer a
-- plain INSERT: the payload deterministically maps to a bounded legacy key and
-- delegates to the authoritative five-argument command. A hash collision can
-- only produce an explicit payload-mismatch failure, never the wrong replay.
create function public.create_project_cash_account(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_currency text
) returns uuid
language sql
security invoker
set search_path=pg_catalog,public
as $$
  select public.create_project_cash_account(
    p_organization_id,
    p_project_id,
    p_name,
    p_currency,
    'legacy-' || pg_catalog.md5(
      p_project_id::text || chr(31) || trim(p_name) || chr(31) || p_currency
    )
  )
$$;

revoke all on function public.create_project_cash_account(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.create_project_cash_account(uuid, uuid, text, text)
  to authenticated;
