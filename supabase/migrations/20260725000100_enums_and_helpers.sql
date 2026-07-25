-- =============================================================================
-- Terranex — Phase 1A — 0001 — Enum types
-- =============================================================================
-- Every enum mirrors a union type in `src/core/types/domain.ts`, which AGENTS.md
-- designates the absolute source of truth. Values are copied verbatim; adding or
-- renaming a value here without changing `domain.ts` is a defect.
--
-- Non-destructive: creates types only. See the paired -down migration.
-- =============================================================================

-- domain.ts:9  Currency
create type public.terranex_currency as enum ('EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP');

-- domain.ts:24  SectorId
create type public.terranex_sector_id as enum ('real-estate', 'agriculture', 'livestock');

-- domain.ts:38  ProjectStatus
create type public.terranex_project_status as enum ('planning', 'active', 'on_hold', 'completed', 'cancelled');

-- domain.ts:62  AssetType
create type public.terranex_asset_type as enum ('land', 'building', 'farm', 'equipment', 'herd', 'animal_group', 'crop', 'other');

-- domain.ts:72  AssetStatus
create type public.terranex_asset_status as enum ('owned', 'leased', 'sold', 'disposed');

-- domain.ts:96  PartnerCategory
create type public.terranex_partner_category as enum ('equity_partner', 'counterparty');

-- domain.ts:98  PartnerCounterpartyRole
create type public.terranex_partner_counterparty_role as enum ('supplier', 'client', 'service_provider', 'lender', 'government', 'other');

-- domain.ts:145 TransactionDirection
create type public.terranex_transaction_direction as enum ('income', 'expense');

-- domain.ts:198 ObligationDirection
create type public.terranex_obligation_direction as enum ('receivable', 'payable');

-- domain.ts:200 ObligationStatus
create type public.terranex_obligation_status as enum ('open', 'partial', 'settled', 'disputed', 'written_off');

-- domain.ts:222 DocumentType
create type public.terranex_document_type as enum (
  'contract', 'invoice', 'receipt', 'ownership_deed', 'veterinary_record',
  'sales_agreement', 'permit', 'court_document', 'other'
);

-- domain.ts:256 OperationalEventType
create type public.terranex_operational_event_type as enum (
  'birth', 'death', 'purchase', 'sale', 'vaccination', 'treatment',
  'feed_consumption', 'weighing', 'transfer',
  'planting', 'irrigation', 'fertilization', 'pest_control', 'harvest', 'crop_loss'
);

-- domain.ts:294 AdjustmentReason
create type public.terranex_adjustment_reason as enum (
  'opening_balance', 'data_correction', 'external_audit', 'reconciliation', 'other'
);

-- features/settlements/types.ts:3 SettlementPaymentMethod
create type public.terranex_settlement_payment_method as enum ('cash', 'bank_transfer', 'cheque', 'card', 'other', 'unknown');

-- features/settlements/types.ts:5 SettlementStatus
create type public.terranex_settlement_status as enum ('active', 'reversed');

-- features/settlements/types.ts:7 SettlementOrigin
create type public.terranex_settlement_origin as enum ('user', 'legacy_balance_migration');

-- `transaction_category` is intentionally NOT an enum.
-- domain.ts:147 TransactionCategory is a long, sector-specific and still-evolving
-- union. Pinning it in the database would force a migration for every new
-- category. It is stored as text and validated by Zod on the client. Revisit
-- once the list stabilises.
