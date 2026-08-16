-- P2 view compatibility gate.
--
-- PR #145 extends the terminal procure-to-pay management view with acceptance
-- visibility. PostgreSQL CREATE OR REPLACE VIEW cannot insert/reorder columns
-- in an existing view. This view is a derived read model (not financial truth)
-- and has no persisted data, so drop it immediately before P2 recreates it.
--
-- Do not use CASCADE: if a future dependency is introduced, replay must fail
-- loudly instead of silently removing dependent objects.

drop view if exists public.procure_to_pay_order_read;
