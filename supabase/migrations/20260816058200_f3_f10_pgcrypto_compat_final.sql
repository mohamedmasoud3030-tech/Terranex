-- F3–F10 pgcrypto hosted-schema compatibility pass (final).
--
-- Hosted Supabase installs pgcrypto in the `extensions` schema; a plain
-- PostgreSQL replay may install it in `public`. The F3–F10 migrations add
-- new SECURITY DEFINER commands (and redefine three existing ones) that
-- call digest(...) unqualified — they are created AFTER the original
-- qualification pass in 20260813000500_pgcrypto_digest_schema_compat.sql.
--
-- This migration re-runs the same bounded pass: keep the locked
-- search_path, qualify only the pgcrypto dependency in every public
-- ordinary function that still contains an unqualified digest call.
-- CREATE OR REPLACE preserves function identity, ownership and grants.
-- It is a no-op for functions already qualified.

do $f3_f10_pgcrypto_compat_final$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  r record;
begin
  select n.nspname
    into v_pgcrypto_schema
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
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid)
        ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
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
$f3_f10_pgcrypto_compat_final$;
