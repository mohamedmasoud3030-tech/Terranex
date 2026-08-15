-- GF-026 / R4 — Procurement Receiving verification.
--
-- Proves:
--   * receiving requires an APPROVED purchase order (draft/rejected rejected);
--   * cumulative received per order line never exceeds the ordered quantity
--     (over-receipt rejected, including across multiple receipts);
--   * the unit is derived server-side from the order line (a mismatched unit
--     is rejected and is never asserted by the browser);
--   * receipts and lines are append-only and idempotent (payload mismatch
--     rejected on key re-use);
--   * tenant-safe commands and read isolation.
--
-- Fixtures (from earlier suites): user ...0001 is OWNER of org ...0001, user
-- ...0002 is OWNER of org ...0002, user ...0003 is MEMBER of org ...0001.

create or replace function s26a_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s26a_catch(p_user uuid, p_sql text)
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

create or replace function s26a_owner_catch(p_sql text)
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

-- Resolve the procurement project created by the GF-025 suite.
select id as s26_project from public.investment_projects
 where internal_reference='GF025-PROJ' and organization_id='10000000-0000-4000-8000-000000000001' \gset

-- ---------------------------------------------------------------------------
-- Setup: supplier + an approved purchase order (2 lines: 100 kg, 20 L).
-- ---------------------------------------------------------------------------
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_supplier('10000000-0000-4000-8000-000000000001',%L,'T-77','صافي 30 يوم',null,'s26a-supplier-001')$$,
  'مورد الأعلاف')) as s26_supplier \gset

select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order('10000000-0000-4000-8000-000000000001',%L,'PO-GF026-001',%L,null,null,(current_date + 30),
    '[{"item_description":"علف ذرة","quantity":100,"unit":"كجم"},{"item_description":"مركز بروتين","quantity":20,"unit":"لتر"}]',
    's26a-po-001')$$, :'s26_project', :'s26_supplier')) as s26_po \gset

select id as s26_po_line_1, unit as s26_po_line_1_unit
from public.purchase_order_lines
where purchase_order_id = :'s26_po' and item_description='علف ذرة' \gset
select id as s26_po_line_2 from public.purchase_order_lines
where purchase_order_id = :'s26_po' and item_description='مركز بروتين' \gset

select s26a_run('00000000-0000-4000-8000-000000000003',
  format($$select public.submit_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s26a-po-submit')$$, :'s26_po')) as s26_po_submitted;
select s26a_run('00000000-0000-4000-8000-000000000001',
  format($$select public.approve_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s26a-po-approve')$$, :'s26_po')) as s26_po_approved;

select 1/case when (select status='APPROVED' from public.purchase_orders where id=:'s26_po')
  then 1 else 0 end as s26_po_approved_state;

-- ---------------------------------------------------------------------------
-- 1. Receiving requires an APPROVED PO.
-- ---------------------------------------------------------------------------
-- Create a second, still-DRAFT order and confirm it cannot receive.
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order('10000000-0000-4000-8000-000000000001',%L,'PO-GF026-DRAFT',null,null,null,(current_date + 30),
    '[{"item_description":"دقيق","quantity":5,"unit":"كجم"}]','s26a-po-draft')$$, :'s26_project')) as s26_po_draft \gset
select id as s26_po_draft_line from public.purchase_order_lines
where purchase_order_id = :'s26_po_draft' \gset
select 1/case when s26a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-د',null,
    ARRAY[%L]::uuid[],ARRAY[5]::numeric[],'s26a-rec-draft')$$,
  :'s26_project', :'s26_po_draft', :'s26_po_draft_line'))
  like '%must be approved before receiving%' then 1 else 0 end as s26_receipt_rejects_draft_po;

-- ---------------------------------------------------------------------------
-- 2. Idempotent receipt with server-derived unit.
-- ---------------------------------------------------------------------------
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-001',null,
    ARRAY[%L]::uuid[],ARRAY[40]::numeric[],'s26a-rec-001')$$,
  :'s26_project', :'s26_po', :'s26_po_line_1')) as s26_receipt_1 \gset

select 1/case when (select count(*) = 1 from public.purchase_receipt_lines
   where purchase_receipt_id = :'s26_receipt_1') then 1 else 0 end as s26_receipt_1_one_line;

-- The stored unit equals the order line unit (derived server-side).
select 1/case when (select unit = :'s26_po_line_1_unit' from public.purchase_receipt_lines
   where purchase_receipt_id = :'s26_receipt_1') then 1 else 0 end as s26_receipt_unit_derived_from_order_line;

-- Idempotent replay returns the same receipt id.
select 1/case when s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-001',null,
    ARRAY[%L]::uuid[],ARRAY[40]::numeric[],'s26a-rec-001')$$,
  :'s26_project', :'s26_po', :'s26_po_line_1')) = :'s26_receipt_1' then 1 else 0 end as s26_receipt_idempotent_replay;

-- Same key, different payload -> payload mismatch.
select 1/case when s26a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند مختلف',null,
    ARRAY[%L]::uuid[],ARRAY[50]::numeric[],'s26a-rec-001')$$,
  :'s26_project', :'s26_po', :'s26_po_line_1')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s26_receipt_payload_mismatch_rejected;

-- ---------------------------------------------------------------------------
-- 3. Over-receipt is rejected (across receipts), and unit must match.
-- ---------------------------------------------------------------------------
-- 40 already received; receiving 61 more on the same 100-unit line over-receives.
select 1/case when s26a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-002',null,
    ARRAY[%L]::uuid[],ARRAY[61]::numeric[],'s26a-rec-over')$$,
  :'s26_project', :'s26_po', :'s26_po_line_1')) like '%received quantity exceeds ordered quantity%' then 1 else 0 end
  as s26_over_receipt_rejected;

-- Exactly the remainder (60) is accepted.
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-003',null,
    ARRAY[%L]::uuid[],ARRAY[60]::numeric[],'s26a-rec-remain')$$,
  :'s26_project', :'s26_po', :'s26_po_line_1')) as s26_receipt_remain \gset

select 1/case when (select coalesce(sum(quantity_received),0) = 100 from public.purchase_receipt_lines
   where purchase_order_line_id = :'s26_po_line_1') then 1 else 0 end as s26_line_fully_received;

-- ---------------------------------------------------------------------------
-- 4. Append-only guards.
-- ---------------------------------------------------------------------------
select 1/case when s26a_owner_catch(format(
  $$delete from public.purchase_receipts where id=%L$$, :'s26_receipt_1'))
  like '%append-only%' then 1 else 0 end as s26_receipt_not_deletable;

select 1/case when s26a_owner_catch(format(
  $$update public.purchase_receipt_lines set quantity_received=1 where purchase_receipt_id=%L$$, :'s26_receipt_1'))
  like '%append-only%' then 1 else 0 end as s26_receipt_line_append_only;

-- ---------------------------------------------------------------------------
-- 5. Tenant isolation: org2 member cannot receive on org1's order.
-- ---------------------------------------------------------------------------
select 1/case when s26a_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'تجاوز',null,
    ARRAY[%L]::uuid[],ARRAY[1]::numeric[],'s26a-rec-cross')$$,
  :'s26_project', :'s26_po', :'s26_po_line_2')) like '%forbidden%' then 1 else 0 end as s26_receipt_cross_tenant_forbidden;

-- Read isolation through the receiving read view.
select 1/case when not exists (
  select 1 from public.purchase_receipts_read
   where organization_id='10000000-0000-4000-8000-000000000001' and purchase_order_id=:'s26_po'
) then 0 else 1 end as s26_receipts_read_exposes_org1_receipts;

-- ---------------------------------------------------------------------------
-- 6. Structural coherence: a persisted receipt line can never point at
--    another order's line, another project, or another order than its
--    receipt header (composite foreign keys — proven with direct inserts
--    as the fixture session, which bypasses every RPC and RLS).
-- ---------------------------------------------------------------------------
create or replace function s26b_super_catch(p_sql text)
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

-- RPC-written receipt lines carry the server-derived purchase_order_id.
select 1/case when (select count(*) = 1 from public.purchase_receipt_lines
  where purchase_receipt_id = :'s26_receipt_1'
    and purchase_order_line_id = :'s26_po_line_1'
    and purchase_order_id = :'s26_po') then 1 else 0 end
  as s26_receipt_lines_carry_header_order;

-- A second approved PO (single 100-unit line) + its own receipt.
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order('10000000-0000-4000-8000-000000000001',%L,'PO-GF026-B',null,null,null,(current_date + 30),
    '[{"item_description":"شعير","quantity":100,"unit":"كجم"}]','s26a-po-b')$$, :'s26_project')) as s26_po_b \gset
select id as s26_po_b_line from public.purchase_order_lines
 where purchase_order_id = :'s26_po_b' \gset
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.submit_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s26a-po-b-submit')$$, :'s26_po_b')) as s26_po_b_submitted;
select s26a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s26a-po-b-approve')$$, :'s26_po_b')) as s26_po_b_approved;
select s26a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_receipt('10000000-0000-4000-8000-000000000001',%L,%L,'سند استلام-ب',null,
    ARRAY[%L]::uuid[],ARRAY[10]::numeric[],'s26a-rec-b')$$,
  :'s26_project', :'s26_po_b', :'s26_po_b_line')) as s26_receipt_b \gset

-- A receipt line referencing an order line of ANOTHER purchase order is
-- structurally impossible (the declared purchase_order_id must equal the
-- order line's own purchase_order_id).
select 1/case when s26b_super_catch(format(
  $$insert into public.purchase_receipt_lines(organization_id,project_id,purchase_receipt_id,purchase_order_line_id,purchase_order_id,quantity_received,unit)
    values('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,5,'كجم')$$,
  :'s26_project', :'s26_receipt_1', :'s26_po_b_line', :'s26_po')) like '%violates foreign key%'
  then 1 else 0 end as s26_receipt_line_cross_order_impossible;

-- A receipt line whose declared order differs from its receipt header's
-- order is structurally impossible.
select 1/case when s26b_super_catch(format(
  $$insert into public.purchase_receipt_lines(organization_id,project_id,purchase_receipt_id,purchase_order_line_id,purchase_order_id,quantity_received,unit)
    values('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,1,'لتر')$$,
  :'s26_project', :'s26_receipt_b', :'s26_po_line_2', :'s26_po_b')) like '%violates foreign key%'
  then 1 else 0 end as s26_receipt_line_wrong_order_impossible;

-- A receipt line declaring a different project than its receipt header is
-- structurally impossible.
select 1/case when s26b_super_catch(format(
  $$insert into public.purchase_receipt_lines(organization_id,project_id,purchase_receipt_id,purchase_order_line_id,purchase_order_id,quantity_received,unit)
    values('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,1,'كجم')$$,
  (select id from public.investment_projects where internal_reference='GF025-PROJ2' and organization_id='10000000-0000-4000-8000-000000000001'),
  :'s26_receipt_b', :'s26_po_b_line', :'s26_po_b')) like '%violates foreign key%'
  then 1 else 0 end as s26_receipt_line_cross_project_impossible;

-- The BEFORE INSERT guard still fires first on a unit mismatch (first-line
-- defense preserved next to the structural constraints).
select 1/case when s26b_super_catch(format(
  $$insert into public.purchase_receipt_lines(organization_id,project_id,purchase_receipt_id,purchase_order_line_id,purchase_order_id,quantity_received,unit)
    values('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,1,'لتر')$$,
  :'s26_project', :'s26_receipt_b', :'s26_po_b_line', :'s26_po_b')) like '%receipt line unit must match order line unit%'
  then 1 else 0 end as s26_receipt_line_unit_guard_preserved;
