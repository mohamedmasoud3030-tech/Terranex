-- =============================================================================
-- Terranex — Phase 1A — 0001 — Enum types
-- =============================================================================
-- Every enum mirrors a union type in `src/core/types/domain.ts`, which AGENTS.md
-- designates the absolute source of truth. Values are copied verbatim; adding or
-- renaming a value here without changing `domain.ts` is a defect.
--
-- Non-destructive & Idempotent: creates types only if they do not already exist.
-- See the paired -down migration.
-- =============================================================================

-- domain.ts:9  Currency
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_currency') then
    create type public.terranex_currency as enum ('EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP');
  end if;
end $$;

-- domain.ts:24  SectorId
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_sector_id') then
    create type public.terranex_sector_id as enum ('real-estate', 'agriculture', 'livestock');
  end if;
end $$;

-- domain.ts:38  ProjectStatus
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_project_status') then
    create type public.terranex_project_status as enum ('planning', 'active', 'on_hold', 'completed', 'cancelled');
  end if;
end $$;

-- domain.ts:62  AssetType
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_asset_type') then
    create type public.terranex_asset_type as enum ('land', 'building', 'farm', 'equipment', 'herd', 'animal_group', 'crop', 'other');
  end if;
end $$;

-- domain.ts:72  AssetStatus
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_asset_status') then
    create type public.terranex_asset_status as enum ('owned', 'leased', 'sold', 'disposed');
  end if;
end $$;

-- domain.ts:96  PartnerCategory
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_partner_category') then
    create type public.terranex_partner_category as enum ('equity_partner', 'counterparty');
  end if;
end $$;

-- domain.ts:98  PartnerCounterpartyRole
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_partner_counterparty_role') then
    create type public.terranex_partner_counterparty_role as enum ('supplier', 'client', 'service_provider', 'lender', 'government', 'other');
  end if;
end $$;

-- domain.ts:145 TransactionDirection
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_transaction_direction') then
    create type public.terranex_transaction_direction as enum ('income', 'expense');
  end if;
end $$;

-- domain.ts:198 ObligationDirection
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_obligation_direction') then
    create type public.terranex_obligation_direction as enum ('receivable', 'payable');
  end if;
end $$;

-- domain.ts:200 ObligationStatus
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_obligation_status') then
    create type public.terranex_obligation_status as enum ('open', 'partial', 'settled', 'disputed', 'written_off');
  end if;
end $$;

-- domain.ts:222 DocumentType
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_document_type') then
    create type public.terranex_document_type as enum (
      'contract', 'invoice', 'receipt', 'ownership_deed', 'veterinary_record',
      'sales_agreement', 'permit', 'court_document', 'other'
    );
  end if;
end $$;

-- domain.ts:256 OperationalEventType
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_operational_event_type') then
    create type public.terranex_operational_event_type as enum (
      'birth', 'death', 'purchase', 'sale', 'vaccination', 'treatment',
      'feed_consumption', 'weighing', 'transfer',
      'planting', 'irrigation', 'fertilization', 'pest_control', 'harvest', 'crop_loss'
    );
  end if;
end $$;

-- domain.ts:294 AdjustmentReason
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_adjustment_reason') then
    create type public.terranex_adjustment_reason as enum (
      'opening_balance', 'data_correction', 'external_audit', 'reconciliation', 'other'
    );
  end if;
end $$;

-- features/settlements/types.ts:3 SettlementPaymentMethod
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_settlement_payment_method') then
    create type public.terranex_settlement_payment_method as enum ('cash', 'bank_transfer', 'cheque', 'card', 'other', 'unknown');
  end if;
end $$;

-- features/settlements/types.ts:5 SettlementStatus
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_settlement_status') then
    create type public.terranex_settlement_status as enum ('active', 'reversed');
  end if;
end $$;

-- features/settlements/types.ts:7 SettlementOrigin
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_settlement_origin') then
    create type public.terranex_settlement_origin as enum ('user', 'legacy_balance_migration');
  end if;
end $$;

-- `transaction_category` is intentionally NOT an enum.
-- domain.ts:147 TransactionCategory is a long, sector-specific and still-evolving
-- union. Pinning it in the database would force a migration for every new
-- category. It is stored as text and validated by Zod on the client. Revisit
-- once the list stabilises.
