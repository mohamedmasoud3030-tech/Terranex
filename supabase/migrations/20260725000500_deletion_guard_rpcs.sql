-- =============================================================================
-- Terranex — Phase 1A — 0005 — guard_*_deletion RPCs
-- =============================================================================
-- Five functions, proven from the single `.rpc(` call site in the codebase:
-- src/core/lib/deletionGuards.ts:14 -> requireClient().rpc(fn, { [param]: id })
--
-- CLIENT CONTRACT (deletionGuards.ts callGuard):
--   const { data, error } = await client.rpc(fn, { p_x_id: id });
--   if (error || !data || !Array.isArray(data) || data.length === 0) -> FAILSAFE
--   const row = data[0] as { can_delete: boolean; message_ar: string };
-- So each function MUST return a SET OF one row with exactly the columns
-- `can_delete boolean` and `message_ar text`. `returns table(...)` gives the
-- array shape PostgREST serialises; a scalar or composite would fail the
-- Array.isArray check and silently fail closed.
--
-- Behavioural spec: tests/helpers/fakeSupabase.cjs RPC_HANDLERS, which carries
-- the blocker labels and message format forward from the pre-migration
-- localStorage guards. Message strings are byte-identical.
--
-- SECURITY INVOKER (the default) is deliberate: the counts must be taken with
-- the caller's RLS in force. A SECURITY DEFINER function would count other
-- tenants' rows and leak their existence through the blocker numbers.
-- Combined with RLS, a guard for an id the caller does not own simply sees
-- zero children and reports "can delete" — no cross-tenant information.
--
-- search_path is pinned to '' on every function, so every reference must be
-- schema-qualified. This is the standard defence against search_path
-- hijacking; without it a caller could shadow `documents` with a temp table.
-- Non-destructive: creates functions only.
-- =============================================================================

-- ─── shared message builders ─────────────────────────────────────────────────
-- Mirrors blockIf() / guardResult() in tests/helpers/fakeSupabase.cjs.

create or replace function public.terranex_block_if(p_count bigint, p_label text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_count = 0 then null else p_label || ': ' || p_count::text end;
$$;

comment on function public.terranex_block_if(bigint, text) is
  'Formats one deletion blocker as "label: n", or NULL when the count is zero. Mirrors blockIf() in tests/helpers/fakeSupabase.cjs.';

create or replace function public.terranex_guard_result(p_blockers text[], p_entity text)
returns table (can_delete boolean, message_ar text)
language sql
immutable
set search_path = ''
as $$
  select
    active.blockers is null or cardinality(active.blockers) = 0,
    case
      when active.blockers is null or cardinality(active.blockers) = 0
        then 'يمكن حذف ' || p_entity || ' بعد التأكيد. لا توجد روابط تشغيلية تمنع الحذف.'
      else 'لا يمكن حذف ' || p_entity
        || ' لأنه مرتبط بسجلات مالية أو تشغيلية. افصل أو عالج الروابط أولاً: '
        || array_to_string(active.blockers, '، ') || '.'
    end
  from (
    select array_remove(p_blockers, null) as blockers
  ) as active;
$$;

comment on function public.terranex_guard_result(text[], text) is
  'Builds the {can_delete, message_ar} guard row from a blocker list. Message text is byte-identical to guardResult() in tests/helpers/fakeSupabase.cjs.';

-- ─── guard_project_deletion ──────────────────────────────────────────────────
create or replace function public.guard_project_deletion(p_project_id uuid)
returns table (can_delete boolean, message_ar text)
language sql
stable
set search_path = ''
as $$
  select * from public.terranex_guard_result(
    array[
      public.terranex_block_if((select count(*) from public.transactions       t where t.project_id = p_project_id), 'معاملات'),
      public.terranex_block_if((select count(*) from public.obligations        o where o.project_id = p_project_id), 'التزامات'),
      public.terranex_block_if((select count(*) from public.assets             a where a.project_id = p_project_id), 'أصول'),
      public.terranex_block_if((select count(*) from public.documents          d where d.project_id = p_project_id), 'مستندات'),
      public.terranex_block_if((select count(*) from public.project_partners  pp where pp.project_id = p_project_id), 'شركاء'),
      public.terranex_block_if((select count(*) from public.operational_events e where e.project_id = p_project_id), 'أحداث تشغيلية'),
      public.terranex_block_if((select count(*) from public.stock_adjustments  s where s.project_id = p_project_id), 'تسويات مخزون')
    ],
    'المشروع'
  );
$$;

-- ─── guard_partner_deletion ──────────────────────────────────────────────────
create or replace function public.guard_partner_deletion(p_partner_id uuid)
returns table (can_delete boolean, message_ar text)
language sql
stable
set search_path = ''
as $$
  select * from public.terranex_guard_result(
    array[
      public.terranex_block_if((select count(*) from public.transactions      t where t.partner_id = p_partner_id), 'معاملات'),
      public.terranex_block_if((select count(*) from public.obligations       o where o.partner_id = p_partner_id), 'التزامات'),
      public.terranex_block_if((select count(*) from public.documents         d where d.partner_id = p_partner_id), 'مستندات'),
      public.terranex_block_if((select count(*) from public.project_partners pp where pp.partner_id = p_partner_id), 'مشاريع ملكية')
    ],
    'الشريك'
  );
$$;

-- ─── guard_asset_deletion ────────────────────────────────────────────────────
create or replace function public.guard_asset_deletion(p_asset_id uuid)
returns table (can_delete boolean, message_ar text)
language sql
stable
set search_path = ''
as $$
  select * from public.terranex_guard_result(
    array[
      public.terranex_block_if((select count(*) from public.transactions       t where t.asset_id = p_asset_id), 'معاملات'),
      public.terranex_block_if((select count(*) from public.documents          d where d.asset_id = p_asset_id), 'مستندات'),
      public.terranex_block_if((select count(*) from public.operational_events e where e.asset_id = p_asset_id), 'أحداث تشغيلية'),
      public.terranex_block_if((select count(*) from public.stock_adjustments  s where s.asset_id = p_asset_id), 'تسويات مخزون')
    ],
    'الأصل'
  );
$$;

-- ─── guard_document_deletion ─────────────────────────────────────────────────
create or replace function public.guard_document_deletion(p_document_id uuid)
returns table (can_delete boolean, message_ar text)
language sql
stable
set search_path = ''
as $$
  select * from public.terranex_guard_result(
    array[
      public.terranex_block_if((select count(*) from public.transactions       t where t.document_id = p_document_id), 'معاملات'),
      public.terranex_block_if((select count(*) from public.obligations        o where o.document_id = p_document_id), 'التزامات'),
      public.terranex_block_if((select count(*) from public.settlements        s where s.receipt_document_id = p_document_id), 'تسويات'),
      public.terranex_block_if((select count(*) from public.operational_events e where e.document_id = p_document_id), 'أحداث تشغيلية')
    ],
    'المستند'
  );
$$;

-- ─── guard_transaction_deletion ──────────────────────────────────────────────
create or replace function public.guard_transaction_deletion(p_transaction_id uuid)
returns table (can_delete boolean, message_ar text)
language sql
stable
set search_path = ''
as $$
  select * from public.terranex_guard_result(
    array[
      public.terranex_block_if((select count(*) from public.obligations        o where o.source_transaction_id = p_transaction_id), 'التزامات'),
      public.terranex_block_if((select count(*) from public.operational_events e where e.linked_transaction_id = p_transaction_id), 'أحداث تشغيلية')
    ],
    'المعاملة'
  );
$$;

comment on function public.guard_project_deletion(uuid)     is 'Deletion guard for projects. Returns one {can_delete, message_ar} row. SECURITY INVOKER so counts respect the caller RLS.';
comment on function public.guard_partner_deletion(uuid)     is 'Deletion guard for partners.';
comment on function public.guard_asset_deletion(uuid)       is 'Deletion guard for assets.';
comment on function public.guard_document_deletion(uuid)    is 'Deletion guard for documents.';
comment on function public.guard_transaction_deletion(uuid) is 'Deletion guard for transactions.';
