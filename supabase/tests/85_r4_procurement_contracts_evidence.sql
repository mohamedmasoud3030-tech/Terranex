-- R4 Contracts & Evidence Closure targeted verification.
-- Proves actual-file approval gates, versioning, append-only evidence,
-- Project/tenant coherence and two-tenant read isolation.

select id as s85_project from public.investment_projects
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='GF025-PROJ' \gset
select id as s85_other_project from public.investment_projects
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='GF025-PROJ2' \gset
select id as s85_supplier from public.procurement_suppliers
 where organization_id='10000000-0000-4000-8000-000000000001'
   and party_id is not null order by created_at limit 1 \gset

select s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'PO-R4-EVIDENCE',%L,null,null,
    current_date+30,'EGP','CONTRACT-R4-EVIDENCE',
    '[{"item_description":"مواد إثبات","quantity":2,"unit":"قطعة","unit_price_minor_units":500}]',
    's85-po-create')$$, :'s85_project', :'s85_supplier')) as s85_po \gset
select s25a_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.submit_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'s85-po-submit')$$, :'s85_po')) as s85_submitted;

select 1/case when s25a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'s85-po-approve-missing')$$, :'s85_po'))
  like '%requires an immutable contract or purchase order file%'
  then 1 else 0 end as s85_po_cannot_approve_without_file;

-- Direct RPC callers cannot manufacture evidence metadata for an object which
-- was never uploaded into the private Storage bucket.
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.register_procurement_evidence(
    '10000000-0000-4000-8000-000000000001',%L,null,'CONTRACT','fake missing object',
    '10000000-0000-4000-8000-000000000001/%s/85000000-0000-4000-8000-000000000099',
    'fake.pdf','application/pdf',100,repeat('f',64),%L,null,null,'s85-fake-object')$$,
  :'s85_project', :'s85_project', :'s85_po')) like '%storage object not found%'
  then 1 else 0 end as s85_missing_storage_object_rejected;
select 1/case when not exists (
  select 1 from public.procurement_evidence_links where organization_id='10000000-0000-4000-8000-000000000001'
    and idempotency_key='s85-fake-object'
) then 1 else 0 end as s85_missing_object_created_no_evidence;

set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence',
  '10000000-0000-4000-8000-000000000001/'||:'s85_project'||'/85000000-0000-4000-8000-000000000097',
  jsonb_build_object('size',101,'mimetype','application/pdf'));
reset role;
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.register_procurement_evidence(
    '10000000-0000-4000-8000-000000000001',%L,null,'CONTRACT','mismatched storage metadata',
    '10000000-0000-4000-8000-000000000001/%s/85000000-0000-4000-8000-000000000097',
    'mismatch.pdf','application/pdf',100,repeat('f',64),%L,null,null,'s85-size-mismatch')$$,
  :'s85_project', :'s85_project', :'s85_po')) like '%size does not match storage object%'
  then 1 else 0 end as s85_storage_size_mismatch_rejected;

select s25a_attach_evidence('00000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001', :'s85_project', 'CONTRACT', :'s85_po', null, null,
  's85-contract-file') as s85_link \gset
select document_id as s85_document, title as s85_title, storage_object_name as s85_object
from public.procurement_evidence_read where evidence_link_id=:'s85_link' \gset

-- The registered-object DELETE policy is fail-closed for authenticated users.
set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
delete from storage.objects where bucket_id='procurement-evidence' and name=:'s85_object';
reset role;
select 1/case when exists (select 1 from storage.objects
  where bucket_id='procurement-evidence' and name=:'s85_object')
  then 1 else 0 end as s85_registered_object_cannot_be_deleted;

-- Even if an administrative/out-of-band operation creates an orphan, the
-- approval predicate rechecks Storage and refuses to authorize from metadata.
delete from storage.objects where bucket_id='procurement-evidence' and name=:'s85_object';
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'s85-po-approve-orphan')$$, :'s85_po'))
  like '%requires an immutable contract or purchase order file%'
  then 1 else 0 end as s85_orphan_evidence_cannot_approve;

-- Restore the test object exactly, then the same evidence metadata is valid.
set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence',:'s85_object',
  jsonb_build_object('size',100,'mimetype','application/pdf'));
reset role;
select s25a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'s85-po-approve')$$, :'s85_po')) as s85_approved;
set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence',
  '10000000-0000-4000-8000-000000000001/'||:'s85_project'||'/85000000-0000-4000-8000-000000000002',
  jsonb_build_object('size',120,'mimetype','application/pdf'));
select public.register_procurement_evidence(
  '10000000-0000-4000-8000-000000000001', :'s85_project', :'s85_document', 'CONTRACT', :'s85_title',
  '10000000-0000-4000-8000-000000000001/'||:'s85_project'||'/85000000-0000-4000-8000-000000000002',
  'contract-v2.pdf','application/pdf',120,repeat('c',64), :'s85_po',null,null,'s85-contract-v2'
) as s85_v2_link;
reset role;
select 1/case when (select max(version_number)=2 and count(*)=2
  from public.procurement_evidence_versions where document_id=:'s85_document')
  then 1 else 0 end as s85_replacement_creates_version;

set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence',
  '10000000-0000-4000-8000-000000000001/'||:'s85_other_project'||'/11111111-1111-4111-8111-111111111111',
  jsonb_build_object('size',100,'mimetype','application/pdf'));
reset role;
select 1/case when s25a_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.register_procurement_evidence(
    '10000000-0000-4000-8000-000000000001',%L,null,'CONTRACT','cross project evidence',
    '10000000-0000-4000-8000-000000000001/%s/11111111-1111-4111-8111-111111111111',
    'cross.pdf','application/pdf',100,repeat('d',64),%L,null,null,'s85-cross-project')$$,
  :'s85_other_project', :'s85_other_project', :'s85_po')) like '%purchase order not found%'
  then 1 else 0 end as s85_cross_project_link_rejected;

create or replace function s85_catch_admin(p_sql text) returns text language plpgsql as $$
declare v_message text;
begin
  begin execute p_sql; exception when others then return sqlerrm; end;
  return 'NO_EXCEPTION';
end $$;
select 1/case when s85_catch_admin(format(
  $$update public.procurement_evidence_versions set original_filename='changed.pdf' where document_id=%L$$,
  :'s85_document')) like '%append-only%'
  then 1 else 0 end as s85_version_is_immutable;

set request.jwt.claim.sub='00000000-0000-4000-8000-000000000002';
set role authenticated;
select 1/case when (select count(*)=0 from public.procurement_evidence_read
  where project_id=:'s85_project') then 1 else 0 end as s85_other_tenant_cannot_read;
reset role;

select 1/case when exists (
  select 1 from public.audit_events where event_type='PROCUREMENT_EVIDENCE_LINKED'
    and entity_id in (select id from public.procurement_evidence_versions where document_id=:'s85_document')
) then 1 else 0 end as s85_evidence_audited;

-- The same direct-RPC bypass is closed for Supplier Invoice approval.
select id as s85_invoice_po from public.purchase_orders
 where organization_id='10000000-0000-4000-8000-000000000001'
   and internal_reference='PO-GF026-001' \gset
select id as s85_invoice_receipt_line from public.purchase_receipt_lines
 where purchase_order_id=:'s85_invoice_po' order by created_at limit 1 \gset
select s83_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.record_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,%L,'INV-R4-EVIDENCE-BYPASS',current_date,'EGP','EXPENSE',
    'مرجع فاتورة دون ملف',null,
    '[{"purchase_receipt_line_id":"%s","quantity_invoiced":1,"unit_price_minor_units":100}]',
    's85-invoice-create')$$, :'s85_project', :'s85_invoice_po', :'s85_invoice_receipt_line')) as s85_invoice \gset
select 1/case when s83_catch('00000000-0000-4000-8000-000000000003', format(
  $$select public.register_procurement_evidence(
    '10000000-0000-4000-8000-000000000001',%L,null,'SUPPLIER_INVOICE','fake invoice file',
    '10000000-0000-4000-8000-000000000001/%s/85000000-0000-4000-8000-000000000098',
    'fake-invoice.pdf','application/pdf',100,repeat('f',64),null,null,%L,'s85-fake-invoice-object')$$,
  :'s85_project', :'s85_project', :'s85_invoice')) like '%storage object not found%'
  then 1 else 0 end as s85_missing_invoice_object_rejected;
select 1/case when s83_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_supplier_invoice(
    '10000000-0000-4000-8000-000000000001',%L,'s85-invoice-approve-missing')$$, :'s85_invoice'))
  like '%requires an immutable invoice file%'
  then 1 else 0 end as s85_fake_metadata_cannot_unblock_invoice;
