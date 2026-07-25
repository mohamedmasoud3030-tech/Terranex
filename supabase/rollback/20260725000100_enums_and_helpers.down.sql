-- =============================================================================
-- ROLLBACK 0001 — enum types
-- =============================================================================
-- FULLY REVERSIBLE once the tables using them are gone (rollback 0002 first).
-- Types hold no data.
-- =============================================================================

drop type if exists public.terranex_settlement_origin;
drop type if exists public.terranex_settlement_status;
drop type if exists public.terranex_settlement_payment_method;
drop type if exists public.terranex_adjustment_reason;
drop type if exists public.terranex_operational_event_type;
drop type if exists public.terranex_document_type;
drop type if exists public.terranex_obligation_status;
drop type if exists public.terranex_obligation_direction;
drop type if exists public.terranex_transaction_direction;
drop type if exists public.terranex_partner_counterparty_role;
drop type if exists public.terranex_partner_category;
drop type if exists public.terranex_asset_status;
drop type if exists public.terranex_asset_type;
drop type if exists public.terranex_project_status;
drop type if exists public.terranex_sector_id;
drop type if exists public.terranex_currency;
