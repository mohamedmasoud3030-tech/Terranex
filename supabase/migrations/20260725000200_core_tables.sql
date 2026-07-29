-- =============================================================================
-- Terranex — Phase 1A — 0002 — The 11 operational tables
-- =============================================================================
-- Table count is 11, proven from every `createSupabaseStore<T>(TABLE, ...)` call
-- site in src/features/*/storage.ts. Sector, ExchangeRate and the profitability
-- view models are deliberately NOT tables (see docs/supabase/INVENTORY.md).
--
-- OWNERSHIP MODEL (owner decision, 2026-07-25):
--   - every table carries `owner_id uuid not null default auth.uid()`
--   - parent tables expose `unique (id, owner_id)` to enable composite FKs
--   - settlements           -> (obligation_id, owner_id) => obligations(id, owner_id)
--   - settlement_allocations-> (settlement_id, owner_id) => settlements(id, owner_id)
--                           -> (obligation_id, owner_id) => obligations(id, owner_id)
-- Cross-tenant references are therefore impossible at the schema level: the FK
-- itself carries the tenant. No trigger, and no join inside an RLS policy.
--
-- `owner_id` is added here as NOT NULL because these tables are being created
-- empty. Migration 0005 handles the case where a pre-existing deployment
-- already has rows.
--
-- Money is `numeric`, never float. Dates that the client sends as 'YYYY-MM-DD'
-- are `date`; timestamps it sends as ISO-8601 are `timestamptz`.
-- Non-destructive: creates tables only. Uses `if not exists` so a partially
-- applied run can be resumed.
-- =============================================================================

-- ─── projects ────────────────────────────────────────────────────── domain.ts:45
create table if not exists public.projects (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid() references auth.users (id) on delete restrict,
  sector_id       public.terranex_sector_id      not null,
  name_ar         text                            not null check (length(btrim(name_ar)) > 0),
  name_en         text                            not null,
  description_ar  text,
  description_en  text,
  status          public.terranex_project_status  not null,
  start_date      date                            not null,
  end_date        date,
  base_currency   public.terranex_currency        not null,
  created_at      timestamptz                     not null default now(),
  updated_at      timestamptz                     not null default now(),
  constraint projects_id_owner_key unique (id, owner_id),
  constraint projects_dates_ordered check (end_date is null or end_date >= start_date)
);

-- ─── partners ────────────────────────────────────────────────────── domain.ts:106
create table if not exists public.partners (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null default auth.uid() references auth.users (id) on delete restrict,
  name_ar            text                                          not null check (length(btrim(name_ar)) > 0),
  name_en            text,
  category           public.terranex_partner_category              not null,
  counterparty_role  public.terranex_partner_counterparty_role,
  phone              text,
  email              text,
  address            text,
  notes              text,
  created_at         timestamptz                                   not null default now(),
  constraint partners_id_owner_key unique (id, owner_id),
  -- domain.ts:101 "required when category = 'counterparty'"
  constraint partners_counterparty_role_required check (
    category <> 'counterparty' or counterparty_role is not null
  )
);

-- ─── assets ──────────────────────────────────────────────────────── domain.ts:74
create table if not exists public.assets (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id            uuid                            not null,
  sector_id             public.terranex_sector_id       not null,
  type                  public.terranex_asset_type      not null,
  name_ar               text                            not null check (length(btrim(name_ar)) > 0),
  name_en               text                            not null,
  acquisition_date      date                            not null,
  acquisition_cost      numeric(18, 4)                  not null check (acquisition_cost >= 0),
  acquisition_currency  public.terranex_currency        not null,
  acquisition_cost_egp  numeric(18, 4)                  not null check (acquisition_cost_egp >= 0),
  current_value_egp     numeric(18, 4)                  check (current_value_egp >= 0),
  status                public.terranex_asset_status    not null,
  quantity              numeric(18, 4),
  unit                  text,
  notes                 text,
  created_at            timestamptz                     not null default now(),
  constraint assets_id_owner_key unique (id, owner_id),
  constraint assets_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict
);

-- ─── documents ───────────────────────────────────────────────────── domain.ts:233
-- `transaction_id` is the reverse side of the transaction<->document link kept
-- by features/documents/transactionDocumentIntegrity.ts. Its FK is added in
-- migration 0003, after `transactions` exists (circular reference).
create table if not exists public.documents (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id       uuid,
  asset_id         uuid,
  partner_id       uuid,
  transaction_id   uuid,
  type             public.terranex_document_type not null,
  title_ar         text                          not null check (length(btrim(title_ar)) > 0),
  title_en         text,
  file_url         text,
  file_name        text,
  file_mime_type   text,
  file_size_bytes  bigint check (file_size_bytes is null or file_size_bytes > 0),
  file_sha256      text,
  issue_date       date,
  expiry_date      date,
  notes            text,
  created_at       timestamptz                   not null default now(),
  constraint documents_id_owner_key unique (id, owner_id),
  constraint documents_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint documents_asset_fk foreign key (asset_id, owner_id)
    references public.assets (id, owner_id) on delete restrict,
  constraint documents_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  -- features/documents/storage.ts normalizeInput(): partial file metadata is invalid
  constraint documents_file_metadata_complete check (
    (file_url is null and file_name is null and file_mime_type is null
      and file_size_bytes is null and file_sha256 is null)
    or (file_url is not null and file_name is not null and file_mime_type is not null
      and file_size_bytes is not null and file_size_bytes > 0)
  )
);

-- ─── project_partners ────────────────────────────────────────────── domain.ts:120
-- Join table: equity partners per project.
create table if not exists public.project_partners (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id      uuid           not null,
  partner_id      uuid           not null,
  equity_pct      numeric(7, 4)  not null check (equity_pct >= 0 and equity_pct <= 100),
  effective_from  date           not null,
  effective_to    date,
  notes           text,
  constraint project_partners_id_owner_key unique (id, owner_id),
  constraint project_partners_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint project_partners_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint project_partners_dates_ordered check (
    effective_to is null or effective_to >= effective_from
  )
);
-- NOTE (documented, deliberately NOT fixed in this phase):
-- features/partners/storage.ts:21 hydrates project_partners with
-- `.order('id')` — a UUID sort, which is arbitrary rather than chronological.
-- Changing the client's order column is out of scope for 1A; recorded in
-- docs/supabase/INVENTORY.md so it is not lost.
--
-- domain.ts:126 also states equity_pct must sum to <=100 per project. That is a
-- cross-row invariant; a CHECK cannot express it and the app does not enforce
-- it today. Deferred to P1B with the other financial invariants.

-- ─── transactions ────────────────────────────────────────────────── domain.ts:176
-- `operational_event_id` FK is added in 0003 (operational_events comes later).
create table if not exists public.transactions (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id            uuid                                    not null,
  asset_id              uuid,
  partner_id            uuid,
  operational_event_id  uuid,
  direction             public.terranex_transaction_direction   not null,
  category              text                                    not null check (length(btrim(category)) > 0),
  amount                numeric(18, 4)                          not null check (amount > 0),
  currency              public.terranex_currency                not null,
  fx_rate               numeric(18, 8)                          not null check (fx_rate > 0),
  amount_egp            numeric(18, 4)                          not null check (amount_egp > 0),
  transaction_date      date                                    not null,
  document_id           uuid,
  description           text,
  notes                 text,
  created_at            timestamptz                             not null default now(),
  updated_at            timestamptz                             not null default now(),
  constraint transactions_id_owner_key unique (id, owner_id),
  constraint transactions_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint transactions_asset_fk foreign key (asset_id, owner_id)
    references public.assets (id, owner_id) on delete restrict,
  constraint transactions_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint transactions_document_fk foreign key (document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  -- storage.ts normalizeInput(): EGP transactions are forced to rate 1
  constraint transactions_egp_rate_is_one check (currency <> 'EGP' or fx_rate = 1)
);

-- core/lib/referenceValidation.ts rejects a document already used by another
-- transaction ("الوثيقة الداعمة مستخدمة في معاملة أخرى بالفعل"). Enforce it.
create unique index if not exists transactions_document_id_unique
  on public.transactions (document_id)
  where document_id is not null;

-- ─── obligations ─────────────────────────────────────────────────── domain.ts:202
create table if not exists public.obligations (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id             uuid,
  partner_id             uuid                                   not null,
  direction              public.terranex_obligation_direction   not null,
  amount                 numeric(18, 4)                         not null check (amount > 0),
  currency               public.terranex_currency               not null,
  amount_egp             numeric(18, 4)                         not null check (amount_egp > 0),
  due_date               date,
  status                 public.terranex_obligation_status      not null,
  amount_settled_egp     numeric(18, 4)                         not null default 0 check (amount_settled_egp >= 0),
  source_transaction_id  uuid,
  document_id            uuid,
  notes                  text,
  created_at             timestamptz                            not null default now(),
  updated_at             timestamptz                            not null default now(),
  constraint obligations_id_owner_key unique (id, owner_id),
  constraint obligations_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint obligations_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint obligations_source_transaction_fk foreign key (source_transaction_id, owner_id)
    references public.transactions (id, owner_id) on delete restrict,
  constraint obligations_document_fk foreign key (document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  -- features/obligations/storage.ts: "إجمالي التسويات أكبر من قيمة الالتزام"
  constraint obligations_settled_within_amount check (amount_settled_egp <= amount_egp)
);

-- ─── settlements ────────────────────── features/settlements/types.ts:10
-- Composite FK carries the tenant: an obligation belonging to another user can
-- never be referenced, because (obligation_id, owner_id) must exist together.
create table if not exists public.settlements (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null default auth.uid() references auth.users (id) on delete restrict,
  obligation_id        uuid                                          not null,
  amount               numeric(18, 4)                                not null check (amount > 0),
  currency             public.terranex_currency                      not null,
  fx_rate              numeric(18, 8)                                not null check (fx_rate > 0),
  amount_egp           numeric(18, 4)                                not null check (amount_egp > 0),
  settlement_date      date                                          not null,
  payment_method       public.terranex_settlement_payment_method     not null,
  reference_number     text,
  receipt_document_id  uuid,
  notes                text,
  status               public.terranex_settlement_status             not null default 'active',
  origin               public.terranex_settlement_origin             not null default 'user',
  reversed_at          timestamptz,
  reversal_reason      text,
  created_at           timestamptz                                   not null default now(),
  updated_at           timestamptz                                   not null default now(),
  constraint settlements_id_owner_key unique (id, owner_id),
  constraint settlements_obligation_fk foreign key (obligation_id, owner_id)
    references public.obligations (id, owner_id) on delete restrict,
  constraint settlements_receipt_document_fk foreign key (receipt_document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  -- storage.ts reverse(): a reversal must carry timestamp + reason
  constraint settlements_reversal_fields_consistent check (
    (status = 'reversed' and reversed_at is not null and length(btrim(coalesce(reversal_reason, ''))) > 0)
    or (status = 'active' and reversed_at is null and reversal_reason is null)
  )
);

-- ─── settlement_allocations ────── features/settlement-allocations/types.ts:2
create table if not exists public.settlement_allocations (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null default auth.uid() references auth.users (id) on delete restrict,
  settlement_id         uuid            not null,
  obligation_id         uuid            not null,
  allocated_amount_egp  numeric(18, 4)  not null check (allocated_amount_egp > 0),
  created_at            timestamptz     not null default now(),
  constraint settlement_allocations_id_owner_key unique (id, owner_id),
  constraint settlement_allocations_settlement_fk foreign key (settlement_id, owner_id)
    references public.settlements (id, owner_id) on delete restrict,
  constraint settlement_allocations_obligation_fk foreign key (obligation_id, owner_id)
    references public.obligations (id, owner_id) on delete restrict,
  -- storage.ts createMany(): "يوجد توزيع مسجل بالفعل لنفس التسوية والالتزام"
  constraint settlement_allocations_unique_pair unique (settlement_id, obligation_id)
);

-- ─── operational_events ──────────────────────────────────────────── domain.ts:275
create table if not exists public.operational_events (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null default auth.uid() references auth.users (id) on delete restrict,
  asset_id               uuid                                        not null,
  project_id             uuid                                        not null,
  type                   public.terranex_operational_event_type      not null,
  event_date             date                                        not null,
  quantity_delta         numeric(18, 4),
  weight_kg              numeric(18, 4) check (weight_kg is null or weight_kg >= 0),
  unit_cost_egp          numeric(18, 4) check (unit_cost_egp is null or unit_cost_egp >= 0),
  total_cost_egp         numeric(18, 4) check (total_cost_egp is null or total_cost_egp >= 0),
  description            text,
  document_id            uuid,
  linked_transaction_id  uuid,
  created_at             timestamptz                                 not null default now(),
  constraint operational_events_id_owner_key unique (id, owner_id),
  constraint operational_events_asset_fk foreign key (asset_id, owner_id)
    references public.assets (id, owner_id) on delete restrict,
  constraint operational_events_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint operational_events_document_fk foreign key (document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  constraint operational_events_transaction_fk foreign key (linked_transaction_id, owner_id)
    references public.transactions (id, owner_id) on delete restrict
);

-- ─── stock_adjustments ───────────────────────────────────────────── domain.ts:301
create table if not exists public.stock_adjustments (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null default auth.uid() references auth.users (id) on delete restrict,
  asset_id           uuid                                   not null,
  project_id         uuid                                   not null,
  adjustment_date    date                                   not null,
  quantity_before    numeric(18, 4)                         not null,
  quantity_after     numeric(18, 4)                         not null,
  value_egp_before   numeric(18, 4)                         not null,
  value_egp_after    numeric(18, 4)                         not null,
  reason             public.terranex_adjustment_reason      not null,
  notes              text,
  created_at         timestamptz                            not null default now(),
  constraint stock_adjustments_id_owner_key unique (id, owner_id),
  constraint stock_adjustments_asset_fk foreign key (asset_id, owner_id)
    references public.assets (id, owner_id) on delete restrict,
  constraint stock_adjustments_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict
);
