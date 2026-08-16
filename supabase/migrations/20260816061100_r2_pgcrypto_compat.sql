-- R2 pgcrypto hosted/local schema compatibility.
-- Qualify only pgcrypto.digest in public ordinary functions created after the
-- repository-wide compatibility passes. Keep SECURITY DEFINER search_path
-- locked to pg_catalog,public.

do $r2_pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  proc_row record;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;

  for proc_row in
    select proc.oid,proc.oid::regprocedure::text as signature
    from pg_proc proc
    join pg_namespace n on n.oid=proc.pronamespace
    where n.nspname='public'
      and proc.prokind='f'
      and pg_get_functiondef(proc.oid) ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
    order by proc.oid::regprocedure::text
  loop
    v_definition:=pg_get_functiondef(proc_row.oid);
    v_rewritten:=regexp_replace(
      v_definition,
      '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
      E'\\1'||quote_ident(v_pgcrypto_schema)||'.digest(',
      'g'
    );
    if v_rewritten=v_definition then
      raise exception 'failed to qualify pgcrypto digest in %',proc_row.signature;
    end if;
    execute v_rewritten;
  end loop;
end
$r2_pgcrypto_compat$;
