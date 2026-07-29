-- =============================================================================
-- ROLLBACK 0003 — circular FKs + indexes
-- =============================================================================
-- FULLY REVERSIBLE. Dropping indexes loses no data; they are rebuilt on
-- re-apply. Dropping the two circular FKs removes referential enforcement but
-- leaves the columns and their values intact.
-- =============================================================================

alter table public.transactions drop constraint if exists transactions_operational_event_fk;
alter table public.documents    drop constraint if exists documents_transaction_fk;

drop index if exists public.stock_adjustments_project_idx;
drop index if exists public.stock_adjustments_asset_idx;
drop index if exists public.operational_events_transaction_idx;
drop index if exists public.operational_events_document_idx;
drop index if exists public.operational_events_project_idx;
drop index if exists public.operational_events_asset_idx;
drop index if exists public.settlement_allocations_obligation_idx;
drop index if exists public.settlement_allocations_settlement_idx;
drop index if exists public.settlements_receipt_document_idx;
drop index if exists public.settlements_obligation_idx;
drop index if exists public.obligations_source_transaction_idx;
drop index if exists public.obligations_document_idx;
drop index if exists public.obligations_partner_idx;
drop index if exists public.obligations_project_idx;
drop index if exists public.transactions_operational_event_idx;
drop index if exists public.transactions_partner_idx;
drop index if exists public.transactions_asset_idx;
drop index if exists public.transactions_project_idx;
drop index if exists public.project_partners_partner_idx;
drop index if exists public.project_partners_project_idx;
drop index if exists public.documents_transaction_idx;
drop index if exists public.documents_partner_idx;
drop index if exists public.documents_asset_idx;
drop index if exists public.documents_project_idx;
drop index if exists public.assets_project_idx;

drop index if exists public.project_partners_owner_id_idx;
drop index if exists public.stock_adjustments_owner_date_idx;
drop index if exists public.operational_events_owner_date_idx;
drop index if exists public.settlements_owner_date_idx;
drop index if exists public.transactions_owner_date_idx;
drop index if exists public.settlement_allocations_owner_created_idx;
drop index if exists public.obligations_owner_created_idx;
drop index if exists public.documents_owner_created_idx;
drop index if exists public.assets_owner_created_idx;
drop index if exists public.partners_owner_created_idx;
drop index if exists public.projects_owner_created_idx;

drop index if exists public.stock_adjustments_owner_idx;
drop index if exists public.operational_events_owner_idx;
drop index if exists public.settlement_allocations_owner_idx;
drop index if exists public.settlements_owner_idx;
drop index if exists public.obligations_owner_idx;
drop index if exists public.transactions_owner_idx;
drop index if exists public.project_partners_owner_idx;
drop index if exists public.documents_owner_idx;
drop index if exists public.assets_owner_idx;
drop index if exists public.partners_owner_idx;
drop index if exists public.projects_owner_idx;
