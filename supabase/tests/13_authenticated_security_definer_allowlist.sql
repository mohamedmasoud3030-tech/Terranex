-- =============================================================================
-- Terranex DB test — authenticated SECURITY DEFINER allowlist
-- =============================================================================
-- Supabase Security Advisor flags every authenticated-executable SECURITY
-- DEFINER function. Terranex permits only the reviewed business RPC boundary
-- below. Any new elevated RPC must be explicitly reviewed and added here and to
-- docs/security/AUTHENTICATED_SECURITY_DEFINER_ALLOWLIST.md.
-- =============================================================================
\set ON_ERROR_STOP on
\timing off

do $$
declare
  v_expected constant text[] := array[
    'approve_distribution_atomic',
    'change_ownership_atomic',
    'create_journal_entry_atomic',
    'create_purchase_invoice_atomic',
    'create_sales_invoice_atomic',
    'delete_transaction_atomic',
    'enqueue_odoo_sync',
    'get_ownership_as_of',
    'pay_distribution_allocation_atomic',
    'pay_purchase_invoice',
    'pay_sales_invoice',
    'post_journal_entry',
    'receive_purchase_invoice_with_stock',
    'record_distribution_atomic',
    'record_partner_capital_movement_atomic',
    'record_partner_ledger_entry_atomic',
    'record_settlement_atomic',
    'record_stock_adjustment_atomic',
    'record_transaction_atomic',
    'reverse_partner_ledger_entry_atomic',
    'reverse_settlement_atomic',
    'set_bank_transaction_reviewed',
    'terranex_assert_owner',
    'update_transaction_atomic',
    'void_journal_entry'
  ];
  v_expected_sorted text[];
  v_actual text[];
  v_name text;
  v_count integer;
begin
  select array_agg(x order by x) into v_expected_sorted
  from unnest(v_expected) as x;

  select array_agg(x order by x) into v_actual
  from (
    select distinct p.proname as x
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) allowed;

  if v_actual is distinct from v_expected_sorted then
    raise exception
      'FAIL authenticated SECURITY DEFINER allowlist: expected %, found %',
      v_expected_sorted, v_actual;
  end if;
  raise notice 'PASS allowlist: exactly % reviewed authenticated SECURITY DEFINER RPCs',
    array_length(v_expected, 1);

  foreach v_name in array v_expected loop
    select count(*) into v_count
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = v_name
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('public', p.oid, 'EXECUTE')
      and array_to_string(coalesce(p.proconfig, array[]::text[]), ',') like '%search_path=%';

    if v_count <> 1 then
      raise exception
        'FAIL allowlist contract for %: expected one pinned, authenticated-only SECURITY DEFINER overload, found %',
        v_name, v_count;
    end if;
  end loop;
  raise notice 'PASS allowlist contracts: anonymous denied and search_path pinned';

  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('public', p.oid, 'EXECUTE')
    );
  if v_count <> 0 then
    raise exception 'FAIL anonymous exposure: % SECURITY DEFINER function(s) remain executable', v_count;
  end if;
  raise notice 'PASS anonymous exposure: zero SECURITY DEFINER functions executable';

  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prorettype = 'pg_catalog.trigger'::regtype
    and (
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
      or has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('public', p.oid, 'EXECUTE')
    );
  if v_count <> 0 then
    raise exception 'FAIL trigger exposure: % trigger function(s) remain externally executable', v_count;
  end if;
  raise notice 'PASS trigger exposure: zero trigger functions externally executable';

  foreach v_name in array array[
    'terranex_lock_financial_request',
    'terranex_audit_check_idempotent',
    'terranex_audit_log'
  ] loop
    select count(*) into v_count
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = v_name
      and has_function_privilege('authenticated', p.oid, 'EXECUTE');
    if v_count <> 0 then
      raise exception 'FAIL internal helper exposure: % is authenticated-executable', v_name;
    end if;
  end loop;
  raise notice 'PASS internal helpers: locked away from authenticated callers';

  raise notice '=== AUTHENTICATED SECURITY DEFINER ALLOWLIST: ALL CHECKS PASSED ===';
end;
$$;
