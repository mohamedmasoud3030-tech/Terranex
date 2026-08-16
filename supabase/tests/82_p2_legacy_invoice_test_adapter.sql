-- Test-only compatibility adapter for pre-P2 R4 regression suites.
-- Production application roles cannot execute the legacy supplier-invoice RPC.
-- Older R4 tests predate the supplier-stated-total argument, so in this
-- disposable test database only we derive the fixture document total from the
-- fixture lines and forward to the authoritative P2 command.

create or replace function public.record_supplier_invoice(
  p_organization_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_currency text,
  p_cost_treatment text,
  p_evidence_reference text,
  p_notes text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_total numeric;
begin
  select sum((line->>'quantity_invoiced')::numeric * (line->>'unit_price_minor_units')::bigint)
    into v_total
    from jsonb_array_elements(p_lines) line;
  if v_total is null or v_total<=0 or v_total<>trunc(v_total) then
    raise exception 'legacy test invoice total must be exact positive minor units';
  end if;
  return public.record_supplier_invoice(
    p_organization_id,p_project_id,p_purchase_order_id,p_invoice_reference,p_invoice_date,
    p_currency,p_cost_treatment,p_evidence_reference,p_notes,v_total::bigint,p_lines,p_idempotency_key
  );
end $$;

revoke all on function
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,jsonb,text)
  from public,anon;
grant execute on function
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,jsonb,text)
  to authenticated;
