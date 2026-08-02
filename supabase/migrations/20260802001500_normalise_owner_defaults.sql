-- 0015 — Normalise owner defaults + RLS for P0 tables introduced after 0002
--
-- Several tables added in 20260802000100..20260802001400 did not set the
-- `owner_id uuid NOT NULL DEFAULT auth.uid()` baseline expected by 01_schema_contract.
-- Apply additively:
--   - set DEFAULT auth.uid() on owner_id where missing
--   - ensure UNIQUE(id, owner_id) composite key on id-based operational tables
--   - ensure RLS enabled+forced with 4 policies (select/insert/update/delete)
--   - owner_sequences / invoice_payments get proper RLS (select-only for payments)
--   - tighten bank_transactions delete back to manual-only (enforced by trigger)

-- 1) defaults ----------------------------------------------------------------
do $$
declare
  tbl text;
  all_tables constant text[] := array[
    'bank_accounts','bank_transactions','company_settings',
    'inventory_items','inventory_movements','invoice_payments',
    'sales_invoices','sales_invoice_lines','owner_sequences'
  ];
begin
  foreach tbl in array all_tables loop
    execute format('alter table %I alter column owner_id set default auth.uid()', tbl);
    execute format('alter table %I alter column owner_id set not null', tbl);
  end loop;
end $$;

-- 2) composite UNIQUE(id, owner_id) for id-based tables ----------------------
-- company_settings PK is owner_id (no id column); owner_sequences uses seq_key+owner;
-- currencies has no owner_id.
do $$
declare
  tbl text;
  need boolean;
  op_tables constant text[] := array[
    'bank_accounts','bank_transactions',
    'inventory_items','inventory_movements','invoice_payments',
    'sales_invoices','sales_invoice_lines'
  ];
begin
  foreach tbl in array op_tables loop
    select not exists (
      select 1 from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
      where n.nspname='public' and t.relname=tbl and c.contype='u'
        and (select array_agg(a.attname::text order by a.attname::text)
               from unnest(c.conkey) k join pg_attribute a
                 on a.attrelid=c.conrelid and a.attnum=k)
            = array['id','owner_id']
    ) into need;
    if need then
      execute format('alter table %I add constraint %I_id_owner_key unique (id, owner_id)',
                     tbl, tbl);
    end if;
  end loop;
  -- owner_sequences already has PRIMARY KEY (owner_id, sequence_key); no extra key needed.
end $$;

-- 3) RLS policies ------------------------------------------------------------
do $$
declare
  tbl text;
  pol text;
  v text;
  verbs constant text[] := array['select','insert','update','delete'];
  id_tables constant text[] := array[
    'bank_accounts','bank_transactions','company_settings',
    'inventory_items','inventory_movements','sales_invoices','sales_invoice_lines'
  ];
begin
  foreach tbl in array id_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('alter table %I force row level security', tbl);
    -- Drop legacy wildcard/ALL policies AND every known owner_* policy name
    -- used across the migration history (000100 used "_owner_select" naming;
    -- 000400 used bare "_select"/"_insert"/"_update"/"_delete" naming; 000700 used
    -- "_owner_all" naming). This ensures that re-running this migration
    -- (idempotency gate) does not error on "policy already exists".
    foreach v in array verbs loop
      execute format('drop policy if exists %I_owner_%s on %I', tbl, v, tbl);
      execute format('drop policy if exists %I_%s on %I', tbl, v, tbl);
    end loop;
    execute format('drop policy if exists inv_items_owner_all on %I', tbl);
    execute format('drop policy if exists inv_mvmts_owner_all on %I', tbl);
    execute format('drop policy if exists %I_owner_all on %I', tbl, tbl);
    foreach v in array verbs loop
      pol := tbl || '_owner_' || v;
      if v = 'insert' then
        execute format(
          'create policy %I on %I for %s to authenticated with check (auth.uid() = owner_id)',
          pol, tbl, v);
      else
        execute format(
          'create policy %I on %I for %s to authenticated using (auth.uid() = owner_id)',
          pol, tbl, v);
      end if;
    end loop;
  end loop;

  -- invoice_payments: SELECT owner-only; writes disabled (audit-only via security definer)
  alter table invoice_payments enable row level security;
  alter table invoice_payments force row level security;
  foreach v in array verbs loop
    pol := 'invoice_payments_owner_' || v;
    execute format('drop policy if exists %I on invoice_payments', pol);
  end loop;
  create policy invoice_payments_owner_select on invoice_payments
    for select to authenticated using (auth.uid() = owner_id);
  create policy invoice_payments_owner_insert on invoice_payments
    for insert to authenticated with check (false);
  create policy invoice_payments_owner_update on invoice_payments
    for update to authenticated using (false);
  create policy invoice_payments_owner_delete on invoice_payments
    for delete to authenticated using (false);

  -- owner_sequences: select/insert/update for owner; no delete
  alter table owner_sequences enable row level security;
  alter table owner_sequences force row level security;
  foreach v in array verbs loop
    pol := 'owner_sequences_owner_' || v;
    execute format('drop policy if exists %I on owner_sequences', pol);
    if v = 'delete' then continue; end if;
    if v = 'insert' then
      execute format('create policy %I on owner_sequences for %s to authenticated with check (auth.uid() = owner_id)', pol, v);
    else
      execute format('create policy %I on owner_sequences for %s to authenticated using (auth.uid() = owner_id)', pol, v);
    end if;
  end loop;
end $$;

-- 4) tighten bank_transactions delete to manual rows only --------------------
-- (non-manual deletions refused by trg_bank_transactions_protect regardless.)
drop policy if exists bank_transactions_owner_delete on bank_transactions;
create policy bank_transactions_owner_delete on bank_transactions
  for delete to authenticated using (
    auth.uid() = owner_id and reference_type = 'manual'
  );

-- 5) grants ------------------------------------------------------------------
grant select, insert, update, delete on bank_accounts, bank_transactions,
  company_settings, inventory_items, inventory_movements,
  sales_invoices, sales_invoice_lines, owner_sequences to authenticated;
grant select on invoice_payments to authenticated;
-- currencies is a global lookup (public read); anonymous needs SELECT so the
-- sign-up/bootstrap flow can render currency pickers. This is a table with no
-- user data, so read access to anon is safe.
grant select on currencies to authenticated;
-- revoke any previously-granted anon table privileges (anon must only have
-- usage on the schema, never table privileges)
do $$
declare r record;
begin
  for r in
    select table_schema, table_name, string_agg(privilege_type, ',' order by privilege_type) as privs
    from information_schema.role_table_grants
    where table_schema='public' and grantee='anon'
    group by table_schema, table_name
  loop
    execute format('revoke all privileges on table %I.%I from anon', r.table_schema, r.table_name);
  end loop;
end $$;

-- 6) pin search_path on trigger / helper functions added in earlier migrations
--    that did not set it (01_schema_contract requires every shipped function to
--    harden search_path against search_path hijack).
-- Pin search_path on every public function that doesn't already pin it (covers
-- RPCs + triggers + helpers; matches 01_schema_contract's invariant).
do $$
declare r record;
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and array_to_string(coalesce(p.proconfig, array[]::text[]), ',') not like '%search_path=%'
  loop
    execute format('alter function public.%I(%s) set search_path = public', r.proname, r.args);
  end loop;
end $$;
