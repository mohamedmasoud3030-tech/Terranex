-- P2/P3 final additive hardening.
--
-- P2 and P3 now contain the authoritative commands and schema fixes directly.
-- This migration is intentionally small: it enforces non-goods acceptance-type
-- coherence and publishes final settlement-aware read models. It does not
-- duplicate columns/functions already owned by P2/P3.

-- ---------------------------------------------------------------------------
-- 1. Non-goods invoice lines must match the authoritative acceptance type.
-- ---------------------------------------------------------------------------
create or replace function public.p2_guard_acceptance_type_coherence()
returns trigger
language plpgsql
set search_path=pg_catalog,public
as $$
declare
  v_acceptance_type text;
begin
  if new.procurement_type in ('SERVICE','CONSTRUCTION','MILESTONE') then
    select a.acceptance_type
      into v_acceptance_type
      from public.procurement_acceptance_lines al
      join public.procurement_acceptances a
        on a.id = al.acceptance_id
       and a.organization_id = al.organization_id
       and a.project_id = al.project_id
     where al.id = new.procurement_acceptance_line_id
       and al.organization_id = new.organization_id
       and al.project_id = new.project_id
       and al.purchase_order_id = new.purchase_order_id
       and al.purchase_order_line_id = new.purchase_order_line_id;

    if v_acceptance_type is null then
      raise exception 'referenced procurement acceptance line is not coherent with invoice line';
    end if;
    if v_acceptance_type <> new.procurement_type then
      raise exception 'invoice procurement type % does not match acceptance type %',
        new.procurement_type, v_acceptance_type;
    end if;
  end if;
  return new;
end $$;

create trigger supplier_invoice_lines_acceptance_type_coherence
before insert or update of procurement_type, procurement_acceptance_line_id,
                         purchase_order_line_id, purchase_order_id, project_id, organization_id
on public.supplier_invoice_lines
for each row execute function public.p2_guard_acceptance_type_coherence();

-- ---------------------------------------------------------------------------
-- 2. Final settlement-aware supplier invoice read model.
--
-- Drop/recreate is deliberate: P3 expanded settlement semantics and PostgreSQL
-- cannot safely reorder an existing CREATE OR REPLACE VIEW column list.
-- These views are derived management surfaces, never persisted financial truth.
-- ---------------------------------------------------------------------------
drop view if exists public.procure_to_pay_order_read;
drop view if exists public.supplier_invoices_read;

create view public.supplier_invoices_read with (security_invoker=on) as
select i.id, i.organization_id, i.project_id, i.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       i.supplier_id, s.name as supplier_name, i.party_id,
       i.invoice_reference, i.invoice_date, i.currency, i.cost_treatment,
       i.evidence_reference, i.notes, i.status, i.recorded_by, i.recorded_at,
       i.approved_by, i.approved_at, i.cost_obligation_id, i.authorization_batch_id,
       totals.invoice_total_minor_units::text as invoice_total_minor_units,
       coalesce(pay.paid_minor_units, 0)::text as paid_minor_units,
       case when coalesce(op.is_reversed, false) then '0'
            else greatest(
              totals.invoice_total_minor_units
              - coalesce(pay.paid_minor_units, 0)
              - coalesce(credits.credited_minor_units, 0)
              - coalesce(advapp.applied_minor_units, 0)
              - coalesce(alloc.allocated_minor_units, 0), 0)::text
       end as outstanding_minor_units,
       coalesce(pay.reconciled_minor_units, 0)::text as reconciled_minor_units,
       coalesce(op.is_reversed, false) as payable_is_reversed,
       case
         when coalesce(op.is_reversed, false) then 'PAYABLE_REVERSED'
         when coalesce(pay.paid_minor_units, 0) = 0 then 'UNPAID'
         when coalesce(pay.paid_minor_units, 0) < totals.invoice_total_minor_units then 'PARTIALLY_PAID'
         else 'FULLY_PAID'
       end as payment_state,
       case
         when coalesce(pay.paid_minor_units, 0) = 0 then 'NOT_PAID'
         when coalesce(pay.reconciled_minor_units, 0) = 0 then 'PAID_UNRECONCILED'
         when pay.reconciled_minor_units < pay.paid_minor_units then 'PARTIALLY_RECONCILED'
         else 'RECONCILED'
       end as reconciliation_state,
       coalesce(pay.payment_count, 0)::integer as payment_count,
       i.supplier_stated_total_minor_units::text as supplier_stated_total_minor_units,
       (select count(*) from public.procurement_invoice_exceptions e
         where e.supplier_invoice_id = i.id and e.status = 'OPEN') as open_exception_count,
       coalesce(credits.credited_minor_units, 0)::text as credited_minor_units,
       coalesce(advapp.applied_minor_units, 0)::text as advance_applied_minor_units,
       coalesce(alloc.allocated_minor_units, 0)::text as allocated_prepayment_minor_units,
       case when coalesce(op.is_reversed, false) then '0'
            else greatest(
              totals.invoice_total_minor_units
              - coalesce(pay.paid_minor_units, 0)
              - coalesce(credits.credited_minor_units, 0)
              - coalesce(advapp.applied_minor_units, 0)
              - coalesce(alloc.allocated_minor_units, 0), 0)::text
       end as net_outstanding_minor_units,
       case
         when coalesce(op.is_reversed, false) then 'PAYABLE_REVERSED'
         when coalesce(pay.paid_minor_units, 0)
            + coalesce(credits.credited_minor_units, 0)
            + coalesce(advapp.applied_minor_units, 0)
            + coalesce(alloc.allocated_minor_units, 0) = 0 then 'UNSETTLED'
         when coalesce(pay.paid_minor_units, 0)
            + coalesce(credits.credited_minor_units, 0)
            + coalesce(advapp.applied_minor_units, 0)
            + coalesce(alloc.allocated_minor_units, 0) < totals.invoice_total_minor_units
           then 'PARTIALLY_SETTLED'
         else 'FULLY_SETTLED'
       end as settlement_state
from public.supplier_invoices i
join public.purchase_orders o
  on o.id = i.purchase_order_id and o.organization_id = i.organization_id
join public.procurement_suppliers s
  on s.id = i.supplier_id and s.organization_id = i.organization_id
join (
  select supplier_invoice_id, sum(line_amount_minor_units) as invoice_total_minor_units
  from public.supplier_invoice_lines
  group by supplier_invoice_id
) totals on totals.supplier_invoice_id = i.id
left join public.cost_obligation_position_read op
  on op.obligation_id = i.cost_obligation_id
left join (
  select co.source_supplier_invoice_id,
         sum(case when ps.is_reversed then 0 else ps.amount_minor_units::bigint end) as paid_minor_units,
         sum(case when not ps.is_reversed and ps.is_reconciled
                  then ps.amount_minor_units::bigint else 0 end) as reconciled_minor_units,
         count(*) filter (where not ps.is_reversed) as payment_count
  from public.cost_obligations co
  join public.payment_status_read ps on ps.obligation_id = co.id
  where co.source_supplier_invoice_id is not null
  group by co.source_supplier_invoice_id
) pay on pay.source_supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(amount_minor_units) as credited_minor_units
  from public.supplier_credit_notes
  where status = 'APPROVED'
  group by supplier_invoice_id
) credits on credits.supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications
  group by supplier_invoice_id
) advapp on advapp.supplier_invoice_id = i.id
left join (
  select pa.obligation_id, sum(pa.allocated_minor_units) as allocated_minor_units
  from public.payment_allocations pa
  group by pa.obligation_id
) alloc on alloc.obligation_id = i.cost_obligation_id;

create view public.procure_to_pay_order_read with (security_invoker=on) as
select c.purchase_order_id, c.organization_id, c.project_id, c.supplier_id, c.party_id,
       c.internal_reference, c.currency, c.committed_minor_units,
       coalesce(received.receipt_line_count, 0)::integer as receipt_line_count,
       c.invoiced_minor_units, c.remaining_commitment_minor_units,
       coalesce(fin.paid_minor_units, 0)::text as paid_minor_units,
       coalesce(fin.outstanding_minor_units, 0)::text as outstanding_payable_minor_units,
       coalesce(fin.unreconciled_minor_units, 0)::text as paid_unreconciled_minor_units,
       case when coalesce(fin.unreconciled_minor_units, 0) = 0
                  and coalesce(fin.paid_minor_units, 0) > 0 then 'RECONCILED'
            when coalesce(fin.paid_minor_units, 0) > 0 then 'PAID_UNRECONCILED'
            else 'NOT_PAID' end as reconciliation_state,
       coalesce(acceptance.acceptance_line_count, 0)::integer as acceptance_line_count
from public.project_procurement_commitments_read c
left join (
  select purchase_order_id, count(*) as receipt_line_count
  from public.purchase_receipt_lines
  group by purchase_order_id
) received on received.purchase_order_id = c.purchase_order_id
left join (
  select purchase_order_id, count(*) as acceptance_line_count
  from public.procurement_acceptance_lines
  group by purchase_order_id
) acceptance on acceptance.purchase_order_id = c.purchase_order_id
left join (
  select purchase_order_id,
         sum(paid_minor_units::bigint) as paid_minor_units,
         sum(net_outstanding_minor_units::bigint) as outstanding_minor_units,
         sum((paid_minor_units::bigint - reconciled_minor_units::bigint)) as unreconciled_minor_units
  from public.supplier_invoices_read
  where status = 'APPROVED'
  group by purchase_order_id
) fin on fin.purchase_order_id = c.purchase_order_id;

grant select on public.supplier_invoices_read, public.procure_to_pay_order_read to authenticated;
revoke all on function public.p2_guard_acceptance_type_coherence() from public, anon, authenticated;
