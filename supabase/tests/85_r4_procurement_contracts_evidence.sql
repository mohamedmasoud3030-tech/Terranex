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

select s25a_attach_evidence('00000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001', :'s85_project', 'CONTRACT', :'s85_po', null, null,
  's85-contract-file') as s85_link \gset
select s25a_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.approve_purchase_order(
    '10000000-0000-4000-8000-000000000001',%L,'s85-po-approve')$$, :'s85_po')) as s85_approved;

select document_id as s85_document, title as s85_title
from public.procurement_evidence_read where evidence_link_id=:'s85_link' \gset
set request.jwt.claim.sub='00000000-0000-4000-8000-000000000003';
set role authenticated;
select public.register_procurement_evidence(
  '10000000-0000-4000-8000-000000000001', :'s85_project', :'s85_document', 'CONTRACT', :'s85_title',
  '10000000-0000-4000-8000-000000000001/'||:'s85_project'||'/'||gen_random_uuid()::text,
  'contract-v2.pdf','application/pdf',120,repeat('c',64), :'s85_po',null,null,'s85-contract-v2'
) as s85_v2_link;
reset role;
select 1/case when (select max(version_number)=2 and count(*)=2
  from public.procurement_evidence_versions where document_id=:'s85_document')
  then 1 else 0 end as s85_replacement_creates_version;

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
