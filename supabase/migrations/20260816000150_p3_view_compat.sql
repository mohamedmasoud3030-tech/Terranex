-- P3 view compatibility gate.
--
-- P3 changes the supplier invoice management read model to include settlement
-- facts. PostgreSQL CREATE OR REPLACE VIEW cannot reorder existing columns.
-- These are derived read models, not persisted financial truth, so remove the
-- dependent terminal view first and then the invoice read view immediately
-- before P3 recreates them.
--
-- Do not use CASCADE. Any future unexpected dependency must fail replay loudly.

drop view if exists public.procure_to_pay_order_read;
drop view if exists public.supplier_invoices_read;
