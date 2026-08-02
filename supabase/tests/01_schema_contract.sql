-- =============================================================================
-- Terranex DB test — schema contract
-- =============================================================================
-- Proves the applied schema matches the inventory taken from src/. Fails loudly
-- if a table, owner_id column, composite unique key, RLS flag or RPC is missing.
-- Run against a database that has all migrations applied.
-- =============================================================================
\set ON_ERROR_STOP on
\timing off

do $$
declare
  -- Core operational tables carry full owner-scoped RLS + composite UNIQUE(id, owner_id) + 4 policies.
  v_operational constant text[] := array[
    'assets','bank_accounts','bank_transactions',
    'distribution_allocations','distributions','documents','equity_change_events',
    'financial_audit_logs','inventory_items','inventory_movements',
    'journal_entries','journal_entry_lines',
    'obligations','operational_events','partner_ledger_entries','partners',
    'project_partners','projects','purchase_invoice_lines','purchase_invoices',
    'sales_invoice_lines','sales_invoices',
    'settlement_allocations','settlements','stock_adjustments','transactions'
  ];
  -- Lookup / singleton / audit / ledger tables exempted from the strict "4 policies + composite (id,owner)" check.
  --   * currencies        – global lookup (public read, no owner)
  --   * company_settings  – one row per owner (PK = owner_id, no id column)
  --   * owner_sequences   – PK = (owner_id, sequence_key), no id column
  --   * invoice_payments  – immutable audit; inserts via security-definer pay RPC, client gets SELECT only
  v_lookup constant text[] := array[
    'bank_transaction_review_operations','company_settings','currencies','invoice_payments',
    'journal_operations','owner_sequences','purchase_invoice_operations','purchase_invoice_payments'
  ];
  v_expected_all text[];
  v_actual   text[];
  v_table    text;
  v_count    int;
  v_oid      uuid;
begin
  v_expected_all := v_operational || v_lookup;

  -- tables exactly equal the union ───────────────────────────────────────────
  select array_agg(tablename order by tablename) into v_actual
  from pg_tables where schemaname = 'public';

  if v_actual is distinct from (select array_agg(t order by t) from unnest(v_expected_all) t) then
    raise exception 'FAIL schema: expected tables % but found %', v_expected_all, v_actual;
  end if;
  raise notice 'PASS schema: all % operational tables + % support tables present',
    array_length(v_operational,1), array_length(v_lookup,1);

  -- ── owner_id NOT NULL + DEFAULT auth.uid() on every operational table ─────
  foreach v_table in array v_operational loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table and column_name='owner_id'
        and is_nullable='NO' and data_type='uuid'
        and column_default like '%auth.uid()%'
    ) then
      raise exception 'FAIL owner_id: %.owner_id is not "uuid NOT NULL DEFAULT auth.uid()"', v_table;
    end if;
  end loop;
  raise notice 'PASS owner_id: uuid NOT NULL DEFAULT auth.uid() on all operational tables';

  -- ── UNIQUE(id, owner_id) on every operational table (composite FKs) ───────
  foreach v_table in array v_operational loop
    if not exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname='public' and t.relname=v_table and c.contype='u'
        and (
          select array_agg(a.attname::text order by a.attname::text)
          from unnest(c.conkey) k join pg_attribute a
            on a.attrelid=c.conrelid and a.attnum=k
        ) = array['id','owner_id']
    ) then
      raise exception 'FAIL composite key: %.UNIQUE(id, owner_id) missing', v_table;
    end if;
  end loop;
  raise notice 'PASS composite keys: UNIQUE(id, owner_id) on all operational tables';

  -- ── RLS enabled AND forced on every operational table ─────────────────────
  foreach v_table in array v_operational loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relrowsecurity and c.relforcerowsecurity
    ) then
      raise exception 'FAIL rls: %  does not have RLS enabled AND forced', v_table;
    end if;
    select count(*) into v_count from pg_policies where schemaname='public' and tablename=v_table;
    if v_count <> 4 then
      raise exception 'FAIL rls: % has % policies, expected 4 (select/insert/update/delete)', v_table, v_count;
    end if;
  end loop;
  raise notice 'PASS rls: enabled + forced with 4 policies on all operational tables';

  -- ── the 5 guard RPCs exist with the exact signature the client calls ───────
  -- Parameter NAMES matter: the client calls rpc(fn, { p_project_id: id }),
  -- and PostgREST resolves named arguments. A renamed parameter breaks the call
  -- even though the type signature is unchanged.
  foreach v_table in array array[
    'guard_project_deletion:p_project_id',
    'guard_partner_deletion:p_partner_id',
    'guard_asset_deletion:p_asset_id',
    'guard_document_deletion:p_document_id',
    'guard_transaction_deletion:p_transaction_id'
  ] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname = split_part(v_table, ':', 1)
        and pg_get_function_identity_arguments(p.oid) = split_part(v_table, ':', 2) || ' uuid'
        and p.proretset  -- set-returning: client does Array.isArray(data)
    ) then
      raise exception 'FAIL rpc: public.%(% uuid) missing, misnamed, or not set-returning',
        split_part(v_table, ':', 1), split_part(v_table, ':', 2);
    end if;
  end loop;
  raise notice 'PASS rpc: all 5 guard_*_deletion(uuid) present and set-returning';

  -- ── the 6 P1B atomic RPCs exist ───────────────────────────────────────────
  foreach v_table in array array[
    'record_transaction_atomic',
    'update_transaction_atomic',
    'delete_transaction_atomic',
    'record_settlement_atomic',
    'reverse_settlement_atomic',
    'record_stock_adjustment_atomic'
  ] loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname = v_table
    ) then
      raise exception 'FAIL rpc: public.% missing', v_table;
    end if;
  end loop;
  raise notice 'PASS rpc: all 6 P1B atomic RPCs present';

  -- ── search_path pinned on every function we ship ───────────────────────────
  for v_table in
    select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (p.proname like 'guard\_%\_deletion'
        or p.proname like 'terranex\_%'
        or p.proname like '%\_atomic'
        or p.proname in (
          'pay_sales_invoice','create_sales_invoice_atomic','next_owner_seq',
          'pay_purchase_invoice','receive_purchase_invoice_with_stock',
          'post_journal_entry','void_journal_entry','set_bank_transaction_reviewed'
        ))
  loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_table
        and array_to_string(coalesce(p.proconfig, array[]::text[]), ',') like '%search_path=%'
    ) then
      raise exception 'FAIL search_path: public.% does not pin search_path', v_table;
    end if;
  end loop;
  raise notice 'PASS search_path: pinned on every shipped function';

  -- ── anon has no privileges anywhere ────────────────────────────────────────
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema='public' and grantee='anon';
  if v_count > 0 then
    raise exception 'FAIL grants: anon holds % table privilege(s) in public', v_count;
  end if;
  raise notice 'PASS grants: anon has zero table privileges';

  -- ── authenticated has exactly SELECT/INSERT/UPDATE/DELETE, nothing more ────
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema='public' and grantee='authenticated'
    and privilege_type not in ('SELECT','INSERT','UPDATE','DELETE');
  if v_count > 0 then
    raise exception 'FAIL grants: authenticated holds % privilege(s) beyond DML', v_count;
  end if;
  raise notice 'PASS grants: authenticated limited to SELECT/INSERT/UPDATE/DELETE';

  -- ── transactions.document_id uniqueness (referenceValidation.ts) ───────────
  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and tablename='transactions'
      and indexdef like '%UNIQUE%' and indexdef like '%document_id%'
  ) then
    raise exception 'FAIL constraint: transactions.document_id is not unique';
  end if;
  raise notice 'PASS constraint: transactions.document_id unique (one doc per transaction)';

  -- ── settlement_allocations unique pair ─────────────────────────────────────
  if not exists (
    select 1 from pg_constraint
    where conname='settlement_allocations_unique_pair' and contype='u'
  ) then
    raise exception 'FAIL constraint: settlement_allocations (settlement_id, obligation_id) not unique';
  end if;
  raise notice 'PASS constraint: settlement_allocations unique (settlement_id, obligation_id)';

  raise notice '=== SCHEMA CONTRACT: ALL CHECKS PASSED ===';
end;
$$;
