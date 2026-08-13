-- Hosted Supabase installs pgcrypto in the `extensions` schema, while a plain
-- PostgreSQL replay may install it in `public`. Terranex SECURITY DEFINER
-- functions deliberately pin search_path to pg_catalog,public, so an
-- unqualified digest(...) call is not portable between those two legitimate
-- pgcrypto layouts.
--
-- Keep the locked search_path. Qualify only the pgcrypto dependency in every
-- existing public function that still contains an unqualified digest call.
-- CREATE OR REPLACE preserves function identity, ownership and grants.

do $pgcrypto_compat$
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
$pgcrypto_compat$;
