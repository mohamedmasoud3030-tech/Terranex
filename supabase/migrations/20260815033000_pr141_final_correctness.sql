-- PR #141 final correctness hardening.
--
-- This additive migration closes two residual persistence/replay gaps found
-- during independent review of the reconciled Procurement foundation:
--   1) a receipt header must bind its purchase order to the SAME project and
--      organization at the database level (not only in create_purchase_receipt);
--   2) idempotency replay fingerprint comparisons must fail closed when a
--      malformed retry produces NULL rather than treating NULL as equal under
--      SQL three-valued logic.
--
-- No product scope is added here. Procurement remains quantity-only operational
-- foundation + receiving; no pricing, invoice, payable, payment, inventory
-- valuation, or investor/legal semantics are introduced.

-- ===========================================================================
-- 1. Receipt-header Purchase Order / Project / Organization coherence.
-- ===========================================================================
-- GF-025 already exposes the referenced unique key
-- purchase_orders(id, project_id, organization_id). This FK makes a persisted
-- receipt header that names Project B while pointing at Project A's PO
-- structurally impossible even for privileged/direct writes.
alter table public.purchase_receipts
  add constraint purchase_receipts_po_project_org_fkey
  foreign key (purchase_order_id, project_id, organization_id)
  references public.purchase_orders(id, project_id, organization_id)
  on delete restrict;

-- ===========================================================================
-- 2. NULL-safe request-fingerprint replay comparison.
-- ===========================================================================
-- Existing GF-025/GF-026 commands used `existing_hash <> v_hash`. In
-- PostgreSQL, `nonnull <> NULL` evaluates to NULL, not TRUE. For replay-first
-- commands (notably create_purchase_receipt, and transition commands when a
-- nullable entity id is supplied), that could let a malformed retry with an
-- already-consumed idempotency key return the old success instead of failing
-- with a payload mismatch.
--
-- Rewrite only the known unmerged Procurement commands, preserving their exact
-- signatures, SECURITY DEFINER attributes, search_path, grants, and bodies.
-- `IS DISTINCT FROM` is the intended equality predicate because it is total
-- over NULL and therefore fail-closed for malformed replay payloads.
do $pr141_nullsafe_replay$
declare
  v_record record;
  v_definition text;
  v_rewritten text;
begin
  for v_record in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.proname = any (array[
         'create_supplier',
         'create_purchase_request',
         'submit_purchase_request',
         'approve_purchase_request',
         'create_purchase_order',
         'submit_purchase_order',
         'approve_purchase_order',
         'create_purchase_receipt'
       ]::text[])
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    v_rewritten := replace(v_definition, '<> v_hash', 'IS DISTINCT FROM v_hash');

    if v_rewritten = v_definition then
      raise exception 'expected request-hash replay comparison not found in %', v_record.proname;
    end if;

    execute v_rewritten;
  end loop;
end
$pr141_nullsafe_replay$;
