-- Every public function must resolve pgcrypto.digest explicitly through the
-- schema that actually owns the extension. This reproduces hosted Supabase,
-- where pgcrypto normally lives in `extensions`, without widening any
-- SECURITY DEFINER search_path.

select 1 / case when exists (
  select 1
  from pg_extension e
  where e.extname = 'pgcrypto'
) then 1 else 0 end as pgcrypto_extension_present;

select 1 / case when not exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and pg_get_functiondef(p.oid)
      ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
) then 1 else 0 end as public_functions_have_no_unqualified_digest;

select 'pgcrypto hosted-schema compatibility SQL PASS' as result;
