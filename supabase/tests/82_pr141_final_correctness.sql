-- PR #141 final correctness regression proof.
--
-- Proves the two residual invariants fixed by
-- 20260815033000_pr141_final_correctness.sql:
--   * a receipt header cannot bind a PO from another project in the same org;
--   * replay fingerprint comparison is NULL-safe / fail-closed.
--
-- Earlier GF-025/GF-026 suites create the canonical org1 procurement project,
-- approved PO/receipt, and transition idempotency evidence used below.

create or replace function s82_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s82_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

create or replace function s82_super_catch(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    return v_msg;
  end;
  return 'NO_EXCEPTION';
end $$;

-- Resolve the receipt created by suite 79 and its authoritative PO/project/line.
select r.id as s82_receipt,
       r.purchase_order_id as s82_po,
       r.project_id as s82_project
  from public.purchase_receipts r
 where r.organization_id = '10000000-0000-4000-8000-000000000001'
   and r.idempotency_key = 's26a-rec-001'
\gset

select l.purchase_order_line_id as s82_po_line
  from public.purchase_receipt_lines l
 where l.purchase_receipt_id = :'s82_receipt'
 order by l.id
 limit 1
\gset

-- Create a second project in the same organization so all independent FKs
-- (org/project and org/PO) are individually valid; only the new composite
-- PO+project+org coherence FK should reject the bad receipt header.
select s82_run(
  '00000000-0000-4000-8000-000000000003',
  $$select public.create_investment_project(
      '10000000-0000-4000-8000-000000000001',
      'مشروع تحقق تماسك الاستلام',
      'PR141-RECEIPT-COHERENCE',
      'cross-project receipt-header structural regression',
      'REAL_ESTATE')$$
) as s82_other_project_created;

select id as s82_other_project
  from public.investment_projects
 where organization_id = '10000000-0000-4000-8000-000000000001'
   and internal_reference = 'PR141-RECEIPT-COHERENCE'
\gset

select 1/case when s82_super_catch(format(
  $$insert into public.purchase_receipts(
      organization_id, project_id, purchase_order_id, evidence_reference,
      received_by, idempotency_key, request_hash)
    values(
      '10000000-0000-4000-8000-000000000001', %L, %L,
      'PR141 cross-project header',
      '00000000-0000-4000-8000-000000000003',
      's82-cross-project-receipt', repeat('f',64))$$,
  :'s82_other_project', :'s82_po'))
  like '%purchase_receipts_po_project_org_fkey%'
  then 1 else 0 end as s82_cross_project_receipt_header_fk_rejected;

-- Same receipt idempotency key + malformed/null replay payload must fail closed.
-- Before the NULL-safe comparison, nonnull_hash <> NULL evaluated to NULL and
-- the replay path could return the prior success instead of rejecting it.
select 1/case when s82_catch(
  '00000000-0000-4000-8000-000000000003',
  format($$select public.create_purchase_receipt(
      '10000000-0000-4000-8000-000000000001', %L, %L,
      null, null, ARRAY[%L]::uuid[], ARRAY[40]::numeric[], 's26a-rec-001')$$,
    :'s82_project', :'s82_po', :'s82_po_line'))
  like '%idempotency key payload mismatch%'
  then 1 else 0 end as s82_receipt_null_replay_payload_rejected;

-- Transition commands are covered by the same NULL-safe predicate: reusing an
-- already-consumed submit key with a NULL entity id must not replay the old
-- entity successfully.
select 1/case when s82_catch(
  '00000000-0000-4000-8000-000000000003',
  $$select public.submit_purchase_request(
      '10000000-0000-4000-8000-000000000001', null::uuid, 's25a-pr-submit')$$)
  like '%idempotency key payload mismatch%'
  then 1 else 0 end as s82_transition_null_entity_replay_rejected;

-- Structural/introspection proof: every targeted Procurement command now uses
-- the NULL-safe request-hash comparator and none retains `<> v_hash`.
select 1/case when not exists (
  select 1
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
     and pg_get_functiondef(p.oid) like '%<> v_hash%'
) then 1 else 0 end as s82_no_nullable_hash_comparisons_remain;

select 1/case when (
  select count(*) = 8
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
     and pg_get_functiondef(p.oid) like '%IS DISTINCT FROM v_hash%'
) then 1 else 0 end as s82_all_target_commands_use_nullsafe_hash_comparison;
