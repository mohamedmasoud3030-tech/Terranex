-- R5 defense-in-depth: keep tenant scoping explicit at the read-model boundary
-- in addition to FORCE RLS on the underlying append-only rental fact tables.
-- This does not change accounting behavior or grant any new privilege.

create or replace view public.property_rental_income_read
with (security_invoker=on) as
select
  r.id as recognition_id,r.organization_id,r.project_id,r.property_asset_id,r.tenant_party_id,
  r.contract_reference,r.rental_period_start,r.rental_period_end,
  r.recognized_amount_minor_units::text as recognized_amount_minor_units,r.currency,
  r.recognition_date,r.evidence_reference,r.journal_batch_id,r.revision_no,r.replaces_recognition_id,
  r.recognized_by,r.recognized_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=r.journal_batch_id) as is_reversed,
  coalesce((select sum(c.amount_minor_units) from public.property_rental_collections c
    join public.journal_batches cb on cb.id=c.journal_batch_id
    where c.recognition_id=r.id and cb.reversal_of_batch_id is null
      and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0)::text
    as collected_minor_units,
  (case when exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=r.journal_batch_id)
    then 0 else r.recognized_amount_minor_units-coalesce((select sum(c.amount_minor_units)
      from public.property_rental_collections c join public.journal_batches cb on cb.id=c.journal_batch_id
      where c.recognition_id=r.id and cb.reversal_of_batch_id is null
        and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cb.id)),0) end)::text
    as outstanding_receivable_minor_units,
  current_date as as_of_date
from public.property_rental_income_recognitions r
where public.is_active_member(r.organization_id);

create or replace view public.property_rental_collections_read
with (security_invoker=on) as
select
  c.id as collection_id,c.organization_id,c.project_id,c.recognition_id,c.cash_account_id,
  c.amount_minor_units::text as amount_minor_units,c.currency,c.collection_date,c.evidence_reference,
  c.journal_batch_id,c.collected_by,c.collected_at,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=c.journal_batch_id) as is_reversed,
  (rr.id is not null) as is_reconciled,rr.id as reconciliation_id,rr.statement_line_id,rr.matched_at
from public.property_rental_collections c
left join public.property_rental_collection_reconciliations rr on rr.collection_id=c.id
where public.is_active_member(c.organization_id);

revoke all on public.property_rental_income_read,public.property_rental_collections_read from public,anon;
grant select on public.property_rental_income_read,public.property_rental_collections_read to authenticated;
