-- 80 — R1/R4 coexistence: Portfolio and Procurement truth stay independent.
--
-- Proves on the reconciled lineage that:
--   * a project under a Portfolio can run the full shared Procurement flow
--     (supplier -> purchase request -> purchase order -> receiving);
--   * moving the project to another Portfolio changes ONLY the management
--     parent: the Purchase Request, Purchase Order, Receipt (and all lines)
--     keep the same ids, statuses, quantities, units and project_id; nothing
--     duplicates; no financial/ledger row is created or moved;
--   * archiving a Portfolio does NOT archive/close the member Project and
--     does NOT mutate Purchase Requests, Purchase Orders, Receipts, or the
--     project ledger;
--   * tenant isolation holds through every path: Portfolio commands, project
--     scoping, security_invoker read views, and RPCs — org B cannot reach
--     org A Procurement, and org A's flow never touched org B's data;
--   * the shared Procurement core exists exactly once: no sector-specific
--     duplicate procurement core (agriculture_*/livestock_*/real_estate_*
--     purchase/procurement tables) exists.
--
-- Fixtures: dedicated org 40000000-…-0081 (owner …-0081, member …-0082).
-- Cross-tenant probes reuse org 10000000-…-0001 (owner …-0001) created by
-- suite 78. This suite runs after suites 75–79.

create or replace function s80a_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s80a_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s80a_catch(p_user uuid, p_sql text)
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

-- ---------------------------------------------------------------------------
-- Fixtures.
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000081'),
  ('00000000-0000-4000-8000-000000000082')
on conflict (id) do nothing;

insert into public.organizations(id, name)
  values ('40000000-0000-4000-8000-000000000081', 'منظمة تعايش ر1 ر4')
  on conflict (id) do nothing;

insert into public.memberships(organization_id, user_id, role, status) values
  ('40000000-0000-4000-8000-000000000081', '00000000-0000-4000-8000-000000000081', 'OWNER', 'ACTIVE'),
  ('40000000-0000-4000-8000-000000000081', '00000000-0000-4000-8000-000000000082', 'MEMBER', 'ACTIVE')
on conflict (organization_id, user_id) do nothing;

-- Tenant-B untouched-count baselines (org 10000000-…-0001 from suite 78).
select count(*) as s80_b_suppliers_before from public.procurement_suppliers
 where organization_id = '10000000-0000-4000-8000-000000000001' \gset
select count(*) as s80_b_receipts_before from public.purchase_receipts
 where organization_id = '10000000-0000-4000-8000-000000000001' \gset

-- Project under tenant A (sector-independent procurement applies to any sector).
select s80a_run('00000000-0000-4000-8000-000000000082',
  $$select public.create_investment_project('40000000-0000-4000-8000-000000000081','مشروع تعايش المشتريات','S80-PROJ','coexistence verification project','REAL_ESTATE')$$
) as s80_project \gset

select id as s80_project_id, sector as s80_project_sector, lifecycle_state as s80_project_lifecycle
  from public.investment_projects
 where internal_reference = 'S80-PROJ'
   and organization_id = '40000000-0000-4000-8000-000000000081' \gset

-- ---------------------------------------------------------------------------
-- 1. Portfolio A: create, activate, assign the project.
-- ---------------------------------------------------------------------------
select s80a_run('00000000-0000-4000-8000-000000000081',
  $$select public.create_investment_portfolio('40000000-0000-4000-8000-000000000081','محفظة التعايش الأولى','إطار إداري أول',null,'s80-pf1-create')$$
) as s80_pf1 \gset

select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.transition_investment_portfolio('40000000-0000-4000-8000-000000000081',%L,'DRAFT','ACTIVE','تفعيل محفظة التعايش الأولى','s80-pf1-activate')$$,
  :'s80_pf1')) as s80_pf1_active \gset

select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.assign_project_to_portfolio('40000000-0000-4000-8000-000000000081',%L,%L,'s80-assign-pf1')$$,
  :'s80_pf1', :'s80_project_id')) as s80_assign1 \gset

select 1/case when :'s80_pf1_active' is not null and :'s80_assign1' is not null then 1 else 0 end
  as s80_portfolio_ready;

-- ---------------------------------------------------------------------------
-- 2. Full shared Procurement flow on the Portfolio-managed project.
-- ---------------------------------------------------------------------------
select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.create_supplier('40000000-0000-4000-8000-000000000081',%L,null,null,null,'s80-supplier-1')$$,
  'مورد التعايش')) as s80_supplier \gset

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.create_purchase_request('40000000-0000-4000-8000-000000000081',%L,'S80-PR-001','طلب تعايش',
    '[{"item_description":"سماد تعايش","quantity":100,"unit":"كجم"}]','s80-pr-1')$$,
  :'s80_project_id')) as s80_pr \gset

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.submit_purchase_request('40000000-0000-4000-8000-000000000081',%L,'s80-pr-submit')$$,
  :'s80_pr')) as s80_pr_submitted;

select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.approve_purchase_request('40000000-0000-4000-8000-000000000081',%L,'s80-pr-approve')$$,
  :'s80_pr')) as s80_pr_approved;

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.create_purchase_order('40000000-0000-4000-8000-000000000081',%L,'S80-PO-001',%L,null,null,(current_date + 30),
    '[{"item_description":"سماد تعايش","quantity":100,"unit":"كجم"}]','s80-po-1')$$,
  :'s80_project_id', :'s80_supplier')) as s80_po \gset

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.submit_purchase_order('40000000-0000-4000-8000-000000000081',%L,'s80-po-submit')$$,
  :'s80_po')) as s80_po_submitted;

select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.approve_purchase_order('40000000-0000-4000-8000-000000000081',%L,'s80-po-approve')$$,
  :'s80_po')) as s80_po_approved;

select id as s80_po_line_id from public.purchase_order_lines
 where purchase_order_id = :'s80_po' and organization_id = '40000000-0000-4000-8000-000000000081' \gset

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.create_purchase_receipt('40000000-0000-4000-8000-000000000081',%L,%L,'سند استلام تعايش 001',null,array[%L]::uuid[],array[40]::numeric[],'s80-receipt-1')$$,
  :'s80_project_id', :'s80_po', :'s80_po_line_id')) as s80_receipt \gset

select 1/case when (
  select count(*) from public.purchase_requests
  where id = :'s80_pr'::uuid and status = 'APPROVED'
    and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 and (
  select count(*) from public.purchase_orders
  where id = :'s80_po'::uuid and status = 'APPROVED'
    and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 and (
  select count(*) from public.purchase_receipts
  where id = :'s80_receipt'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 then 1 else 0 end as s80_procurement_flow_complete;

-- No financial artifact may exist for the project (procurement is quantity-only).
select 1/case when (
  select count(*) from public.journal_batches
  where organization_id = '40000000-0000-4000-8000-000000000081'
) = 0 and (
  select count(*) from public.journal_lines
  where organization_id = '40000000-0000-4000-8000-000000000081'
) = 0 then 1 else 0 end as s80_no_financial_posting_from_procurement;

-- ---------------------------------------------------------------------------
-- 3. Move the project to Portfolio B; verify ONLY the parent changed.
-- ---------------------------------------------------------------------------
select s80a_run('00000000-0000-4000-8000-000000000081',
  $$select public.create_investment_portfolio('40000000-0000-4000-8000-000000000081','محفظة التعايش الثانية','إطار إداري ثان',null,'s80-pf2-create')$$
) as s80_pf2 \gset

select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.transition_investment_portfolio('40000000-0000-4000-8000-000000000081',%L,'DRAFT','ACTIVE','تفعيل محفظة التعايش الثانية','s80-pf2-activate')$$,
  :'s80_pf2')) as s80_pf2_active;

select s80a_run('00000000-0000-4000-8000-000000000082', format(
  $$select public.move_project_to_portfolio('40000000-0000-4000-8000-000000000081',%L,%L,'نقل إداري للتحقق من التعايش','s80-move-pf2')$$,
  :'s80_project_id', :'s80_pf2')) as s80_move \gset

select 1/case when :'s80_move' is not null then 1 else 0 end as s80_move_executed;

-- One current parent only, and it is Portfolio B.
select 1/case when (
  select count(*) from public.portfolio_project_assignments
  where investment_project_id = :'s80_project_id'
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and removed_at is null
) = 1 and (
  select portfolio_id from public.portfolio_project_assignments
  where investment_project_id = :'s80_project_id'
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and removed_at is null
) = :'s80_pf2'::uuid then 1 else 0 end as s80_single_current_parent_is_pf2;

-- Old membership is soft-closed (append-only history, never deleted).
select 1/case when (
  select count(*) from public.portfolio_project_assignments
  where investment_project_id = :'s80_project_id'
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and portfolio_id = :'s80_pf1'::uuid
    and removed_at is not null and removal_reason is not null
) = 1 then 1 else 0 end as s80_old_membership_soft_closed;

-- Purchase Request unchanged: same id, status, project.
select 1/case when (
  select count(*) from public.purchase_requests
  where id = :'s80_pr'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and project_id = :'s80_project_id'::uuid
    and status = 'APPROVED'
    and internal_reference = 'S80-PR-001'
) = 1 then 1 else 0 end as s80_pr_unchanged_after_move;

-- Purchase Order unchanged: same id, status, supplier, project.
select 1/case when (
  select count(*) from public.purchase_orders
  where id = :'s80_po'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and project_id = :'s80_project_id'::uuid
    and status = 'APPROVED'
    and supplier_id = :'s80_supplier'::uuid
    and internal_reference = 'S80-PO-001'
) = 1 then 1 else 0 end as s80_po_unchanged_after_move;

-- Receipt unchanged: same id, order, quantity.
select 1/case when (
  select count(*) from public.purchase_receipts
  where id = :'s80_receipt'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and purchase_order_id = :'s80_po'::uuid
    and project_id = :'s80_project_id'::uuid
) = 1 and (
  select quantity_received from public.purchase_receipt_lines
  where purchase_receipt_id = :'s80_receipt'::uuid
    and purchase_order_line_id = :'s80_po_line_id'::uuid
) = 40 then 1 else 0 end as s80_receipt_unchanged_after_move;

-- No duplication: exactly one PR/PO/receipt for this flow.
select 1/case when (
  select count(*) from public.purchase_requests
  where project_id = :'s80_project_id'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 and (
  select count(*) from public.purchase_orders
  where project_id = :'s80_project_id'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 and (
  select count(*) from public.purchase_receipts
  where project_id = :'s80_project_id'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 then 1 else 0 end as s80_no_duplicate_procurement_facts;

-- Project truth untouched: same identity, sector, lifecycle.
select 1/case when (
  select count(*) from public.investment_projects
  where id = :'s80_project_id'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and sector = :'s80_project_sector'
    and lifecycle_state = :'s80_project_lifecycle'
) = 1 then 1 else 0 end as s80_project_truth_untouched_after_move;

-- ---------------------------------------------------------------------------
-- 4. Archive Portfolio B; verify nothing operational changes.
-- ---------------------------------------------------------------------------
select s80a_run('00000000-0000-4000-8000-000000000081', format(
  $$select public.transition_investment_portfolio('40000000-0000-4000-8000-000000000081',%L,'ACTIVE','ARCHIVED','أرشفة محفظة التعايش الثانية للتحقق','s80-pf2-archive')$$,
  :'s80_pf2')) as s80_pf2_archived;

select 1/case when (
  select status from public.investment_portfolios
  where id = :'s80_pf2'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 'ARCHIVED' then 1 else 0 end as s80_pf2_archived_state;

-- Archiving the Portfolio must not archive/close the Project.
select 1/case when (
  select lifecycle_state from public.investment_projects
  where id = :'s80_project_id'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = :'s80_project_lifecycle' then 1 else 0 end as s80_project_not_archived_by_portfolio;

-- ... and must not mutate Procurement truth.
select 1/case when (
  select status from public.purchase_requests
  where id = :'s80_pr'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 'APPROVED' and (
  select status from public.purchase_orders
  where id = :'s80_po'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 'APPROVED' and (
  select count(*) from public.purchase_receipts
  where id = :'s80_receipt'::uuid and organization_id = '40000000-0000-4000-8000-000000000081'
) = 1 then 1 else 0 end as s80_procurement_untouched_by_archive;

-- Membership survives portfolio archiving (membership is a project fact).
select 1/case when (
  select count(*) from public.portfolio_project_assignments
  where investment_project_id = :'s80_project_id'::uuid
    and organization_id = '40000000-0000-4000-8000-000000000081'
    and removed_at is null
) = 1 then 1 else 0 end as s80_membership_survives_archive;

-- Audit trail: assign + move + archive all recorded.
select 1/case when (
  select count(*) from public.audit_events
  where organization_id = '40000000-0000-4000-8000-000000000081'
    and event_type in ('PROJECT_ASSIGNED_TO_PORTFOLIO','PROJECT_MOVED_BETWEEN_PORTFOLIOS','PORTFOLIO_TRANSITIONED')
) >= 4 then 1 else 0 end as s80_audit_trail_complete;

-- ---------------------------------------------------------------------------
-- 5. Tenant isolation: org B (…-0001) cannot reach tenant A Procurement
--    through Portfolio commands, project scoping, views, or RPCs.
-- ---------------------------------------------------------------------------
select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_supplier('40000000-0000-4000-8000-000000000081','مورد مخترق',null,null,null,'s80-cross-supplier')$$))
  like '%forbidden%' then 1 else 0 end as s80_cross_supplier_forbidden;

select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_purchase_request('40000000-0000-4000-8000-000000000081',%L,'S80-X','اختراق',
    '[{"item_description":"اختراق","quantity":1,"unit":"كجم"}]','s80-cross-pr')$$, :'s80_project_id'))
  like '%forbidden%' then 1 else 0 end as s80_cross_pr_forbidden;

select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_purchase_receipt('40000000-0000-4000-8000-000000000081',%L,%L,'اختراق استلام',null,array[%L]::uuid[],array[1]::numeric[],'s80-cross-receipt')$$,
  :'s80_project_id', :'s80_po', :'s80_po_line_id'))
  like '%forbidden%' then 1 else 0 end as s80_cross_receipt_forbidden;

select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_investment_portfolio('40000000-0000-4000-8000-000000000081',%L,'ACTIVE','ARCHIVED','اختراق','s80-cross-transition')$$,
  :'s80_pf2')) like '%forbidden%' then 1 else 0 end as s80_cross_portfolio_transition_forbidden;

select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_project_to_portfolio('40000000-0000-4000-8000-000000000081',%L,%L,'s80-cross-assign')$$,
  :'s80_pf2', :'s80_project_id')) like '%forbidden%' then 1 else 0 end as s80_cross_assign_forbidden;

-- Org B cannot move tenant A's project, even naming an org A portfolio.
select 1/case when s80a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.move_project_to_portfolio('40000000-0000-4000-8000-000000000081',%L,%L,'اختراق نقل','s80-cross-move')$$,
  :'s80_project_id', :'s80_pf2')) like '%forbidden%' then 1 else 0 end as s80_cross_move_forbidden;

-- Read views: org B sees zero tenant-A procurement rows (checked as the
-- org B user so RLS applies; the suite itself runs as superuser).
select 1/case when s80a_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.purchase_orders_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) = 0
 and s80a_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.purchase_receipts_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) = 0
 and s80a_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.investment_portfolios_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) = 0
 then 1 else 0 end as s80_cross_tenant_reads_denied;

-- Org A's own member CAN read its own Procurement rows through the
-- security_invoker views (proves the authenticated view grants exist and
-- the canonical application read path works).
select 1/case when s80a_count('00000000-0000-4000-8000-000000000082', format(
  $$select count(*) from public.purchase_orders_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) >= 1
 and s80a_count('00000000-0000-4000-8000-000000000082', format(
  $$select count(*) from public.purchase_order_lines_receiving_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) >= 1
 and s80a_count('00000000-0000-4000-8000-000000000082', format(
  $$select count(*) from public.purchase_receipts_read where organization_id=%L$$,
  '40000000-0000-4000-8000-000000000081')) = 1
 then 1 else 0 end as s80_own_tenant_reads_through_views;

-- Org B's own Procurement data was never touched by tenant A's flow.
select 1/case when (
  select count(*) from public.procurement_suppliers
  where organization_id = '10000000-0000-4000-8000-000000000001'
) = :'s80_b_suppliers_before' and (
  select count(*) from public.purchase_receipts
  where organization_id = '10000000-0000-4000-8000-000000000001'
) = :'s80_b_receipts_before' then 1 else 0 end as s80_tenant_b_data_untouched;

-- ---------------------------------------------------------------------------
-- 6. One shared Procurement core: no sector-specific duplicate requisition
--    engine. (Sector commercial fact tables such as GF-024
--    `livestock_purchases` are sector-scoped purchase FACTS, not a
--    supplier/requisition/order/receiving core, and are allowed.)
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) from information_schema.tables
  where table_schema = 'public'
    and table_name in ('procurement_suppliers','purchase_requests','purchase_request_lines',
                       'purchase_orders','purchase_order_lines','purchase_receipts','purchase_receipt_lines')
) = 7 and (
  select count(*) from information_schema.tables
  where table_schema = 'public'
    and (table_name like 'agriculture%supplier%' or table_name like 'livestock%supplier%'
      or table_name like 'real_estate%supplier%'
      or table_name like 'agriculture%purchase_request%' or table_name like 'livestock%purchase_request%'
      or table_name like 'agriculture%purchase_order%' or table_name like 'livestock%purchase_order%'
      or table_name like 'agriculture%purchase_receipt%' or table_name like 'livestock%purchase_receipt%')
) = 0 then 1 else 0 end as s80_single_shared_procurement_core;
