-- P2 RPC authority hardening.
-- The pre-P2 supplier-invoice command did not carry the supplier-stated total.
-- Keep the old overload only as historical database code, but make it
-- unreachable to application roles so new invoices cannot bypass independent
-- document-total verification.

revoke all on function
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,jsonb,text)
  from public,anon,authenticated;

revoke all on function
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,bigint,jsonb,text)
  from public,anon;
grant execute on function
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,bigint,jsonb,text)
  to authenticated;
