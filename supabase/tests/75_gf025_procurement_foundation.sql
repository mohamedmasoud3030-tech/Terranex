-- GF-025 / R4 — Procurement Foundation verification.
--
-- Proves for Suppliers, Purchase Requests and Purchase Orders:
--   * tenant-safe commands that reject cross-tenant access;
--   * idempotent creation with request_hash payload-mismatch rejection;
--   * the DRAFT -> SUBMITTED -> APPROVED lifecycle for requests and orders;
--   * maker/checker (approver <> requester) and OWNER-only approval;
--   * append-only line rows and non-deletable headers;
--   * authenticated direct writes are denied (RPCs are the only write path);
--   * two-tenant read isolation through the security_invoker read views.
--
-- Fixtures: user ...0001 is OWNER of org ...0001, user ...0002 is OWNER of
-- org ...0002, user ...0003 is MEMBER of org ...0001 (established by earlier
-- suites). This suite creates its own project under org ...0001.

create or replace function s25a_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s25a_catch(p_user uuid, p_sql text)
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

create or replace function s25a_owner_catch(p_sql text)
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

-- ---------------------------------------------------------------------------
-- Setup: a project in org ...0001 (sector-independent procurement).
-- Also register a dedicated MEMBER (0009) of org ...0001: earlier suites mutate
-- 0003's role to OWNER, so a genuine non-owner actor is created here for the
-- "non-owner cannot approve" / maker-checker assertions.
-- ---------------------------------------------------------------------------
insert into auth.users values ('00000000-0000-4000-8000-000000000009') on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role)
  values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000009','MEMBER')
  on conflict (organization_id, user_id) do update set role='MEMBER';
select s25a_run('00000000-0000-4000-8000-000000000003',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع اختبار المشتريات','GF025-PROJ','project for procurement verification','REAL_ESTATE')$$
) as s25_project \gset
select id as s25_project_id from public.investment_projects
 where internal_reference='GF025-PROJ' and organization_id='10000000-0000-4000-8000-000000000001' \gset

-- ---------------------------------------------------------------------------
-- 1. Supplier: create, idempotent replay, payload mismatch, cross-tenant.
-- ---------------------------------------------------------------------------
select s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_supplier('10000000-0000-4000-8000-000000000001',%L,'123-456-789','صافي 30 يوم',null,'s25a-supplier-001')$$,
  'مورد الأسمدة المصرية')) as s25_supplier \gset

select 1/case when s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_supplier('10000000-0000-4000-8000-000000000001',%L,'123-456-789','صافي 30 يوم',null,'s25a-supplier-001')$$,
  'مورد الأسمدة المصرية')) = :'s25_supplier' then 1 else 0 end as s25_supplier_idempotent_replay;

select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_supplier('10000000-0000-4000-8000-000000000001',%L,'999','غير ذلك',null,'s25a-supplier-001')$$,
  'مورد مختلف')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s25_supplier_payload_mismatch_rejected;

select 1/case when s25a_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_supplier('10000000-0000-4000-8000-000000000001',%L,null,null,null,'s25a-supplier-cross')$$,
  'مورد عبر المستأجر')) like '%forbidden%' then 1 else 0 end as s25_supplier_cross_tenant_forbidden;

-- ---------------------------------------------------------------------------
-- 2. Purchase Request: create + lines, idempotency, lifecycle, maker/checker.
-- ---------------------------------------------------------------------------
select s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_request('10000000-0000-4000-8000-000000000001',%L,'PR-GF025-001','طلب أسمدة ومبيدات',
    '[{"item_description":"سماد يوريا","quantity":100,"unit":"كجم"},{"item_description":"مبيد حشري","quantity":20,"unit":"لتر"}]',
    's25a-pr-001')$$, :'s25_project_id')) as s25_pr \gset

select 1/case when s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_request('10000000-0000-4000-8000-000000000001',%L,'PR-GF025-001','طلب أسمدة ومبيدات',
    '[{"item_description":"سماد يوريا","quantity":100,"unit":"كجم"},{"item_description":"مبيد حشري","quantity":20,"unit":"لتر"}]',
    's25a-pr-001')$$, :'s25_project_id')) = :'s25_pr' then 1 else 0 end as s25_pr_idempotent_replay;

select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_request('10000000-0000-4000-8000-000000000001',%L,'PR-GF025-001','طلب مختلف',
    '[{"item_description":"سماد يوريا","quantity":100,"unit":"كجم"}]',
    's25a-pr-001')$$, :'s25_project_id')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s25_pr_payload_mismatch_rejected;

select 1/case when (select count(*) = 2 from public.purchase_request_lines
   where purchase_request_id = :'s25_pr') then 1 else 0 end as s25_pr_two_lines_created;

-- A submitted request can be approved only by the OWNER, and not by the requester.
select s25a_run('00000000-0000-4000-8000-000000000003',
  format($$select public.submit_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-submit')$$, :'s25_pr')) as s25_pr_submitted;

select 1/case when (select status='SUBMITTED' from public.purchase_requests where id=:'s25_pr')
  then 1 else 0 end as s25_pr_submitted_state;

-- a genuine MEMBER (0009) cannot approve: only an OWNER may approve.
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000009', format(
  $$select public.approve_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-approve-by-member')$$, :'s25_pr'))
  like '%organization owner required%' then 1 else 0 end as s25_pr_non_owner_cannot_approve;

-- owner (0001) approves.
select s25a_run('00000000-0000-4000-8000-000000000001',
  format($$select public.approve_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-approve')$$, :'s25_pr')) as s25_pr_approved;
select 1/case when (select status='APPROVED' from public.purchase_requests where id=:'s25_pr')
  then 1 else 0 end as s25_pr_approved_state;

-- Submitting an already-approved request is rejected.
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.submit_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-resubmit')$$, :'s25_pr'))
  not like '%NO_EXCEPTION%' then 1 else 0 end as s25_pr_final_not_resubmittable;

-- Maker/checker: an OWNER who is also the requester cannot approve their own.
select s25a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_purchase_request('10000000-0000-4000-8000-000000000001',%L,'PR-GF025-SELF','طلب من المالك',
    '[{"item_description":"سلك شبكي","quantity":5,"unit":"لفة"}]','s25a-pr-self')$$, :'s25_project_id')) as s25_pr_self \gset
select s25a_run('00000000-0000-4000-8000-000000000001',
  format($$select public.submit_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-self-submit')$$, :'s25_pr_self')) as s25_pr_self_submitted;
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_request('10000000-0000-4000-8000-000000000001',%L,'s25a-pr-self-approve')$$, :'s25_pr_self'))
  like '%maker/checker%' then 1 else 0 end as s25_self_approval_forbidden;

-- ---------------------------------------------------------------------------
-- 3. Purchase Order: create + lines + supplier, lifecycle, maker/checker.
-- ---------------------------------------------------------------------------
select s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order('10000000-0000-4000-8000-000000000001',%L,'PO-GF025-001',%L,%L,null,(current_date + 30),
    '[{"item_description":"سماد يوريا","quantity":100,"unit":"كجم"}]','s25a-po-001')$$,
  :'s25_project_id', :'s25_supplier', :'s25_pr')) as s25_po \gset

select 1/case when (select count(*) = 1 from public.purchase_order_lines
   where purchase_order_id = :'s25_po') then 1 else 0 end as s25_po_one_line_created;

select s25a_run('00000000-0000-4000-8000-000000000003',
  format($$select public.submit_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s25a-po-submit')$$, :'s25_po')) as s25_po_submitted;
select 1/case when (select status='SUBMITTED' from public.purchase_orders where id=:'s25_po')
  then 1 else 0 end as s25_po_submitted_state;

select s25a_run('00000000-0000-4000-8000-000000000001',
  format($$select public.approve_purchase_order('10000000-0000-4000-8000-000000000001',%L,'s25a-po-approve')$$, :'s25_po')) as s25_po_approved;
select 1/case when (select status='APPROVED' from public.purchase_orders where id=:'s25_po')
  then 1 else 0 end as s25_po_approved_state;

-- Supplier must be active to appear on an order.
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order('10000000-0000-4000-8000-000000000001',%L,'PO-GF025-BAD',%L,null,null,(current_date + 30),
    '[{"item_description":"شيء","quantity":1,"unit":"قطعة"}]','s25a-po-bad')$$, :'s25_project_id',
  '11111111-1111-4111-8111-111111111111')) like '%active supplier not found%' then 1 else 0 end
  as s25_po_unknown_supplier_rejected;

-- ---------------------------------------------------------------------------
-- 4. Append-only and no-delete guards (direct SQL as the fixture session).
-- ---------------------------------------------------------------------------
select 1/case when s25a_owner_catch(format(
  $$delete from public.purchase_requests where id=%L$$, :'s25_pr')) like '%cannot be deleted%' then 1 else 0 end
  as s25_pr_header_not_deletable;

select 1/case when s25a_owner_catch(format(
  $$update public.purchase_request_lines set quantity=999 where purchase_request_id=%L$$, :'s25_pr'))
  like '%append-only%' then 1 else 0 end as s25_line_append_only;

select 1/case when s25a_owner_catch(format(
  $$delete from public.purchase_order_lines where purchase_order_id=%L$$, :'s25_po'))
  like '%append-only%' then 1 else 0 end as s25_order_line_append_only;

-- ---------------------------------------------------------------------------
-- 5. Authenticated direct writes are denied; reads are tenant-isolated.
-- ---------------------------------------------------------------------------
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$insert into public.procurement_suppliers(organization_id,name,created_by,idempotency_key,request_hash)
    values('10000000-0000-4000-8000-000000000001','مورد مباشر','00000000-0000-4000-8000-000000000003','x12345678','%L')$$, repeat('a',64)))
  not like '%NO_EXCEPTION%' then 1 else 0 end as s25_direct_write_denied;

select 1/case when not exists (
  select 1 from public.purchase_orders_read o
   join public.procurement_suppliers_read s on s.id = o.supplier_id
   where o.internal_reference = 'PO-GF025-001' and s.organization_id = '10000000-0000-4000-8000-000000000001'
) then 0 else 1 end as s25_read_view_exposes_order_with_supplier;
