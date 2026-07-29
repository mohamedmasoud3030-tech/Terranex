-- =============================================================================
-- Terranex — Phase 1A — 0003 — Circular FKs + indexes
-- =============================================================================
-- Two links are circular and cannot be declared inline in 0002:
--   documents.transaction_id      -> transactions   (transactions come later)
--   transactions.operational_event_id -> operational_events (later still)
-- Both are added here, still as tenant-carrying composite FKs.
--
-- Indexes: every column the client filters or orders by. `hydrate()` issues
-- `.select('*').order(<col>, {ascending:false})` on every load, so each store's
-- order column must be indexed or every page load is a full scan + sort.
-- Non-destructive: adds constraints and indexes only.
-- =============================================================================

-- ─── circular FKs ────────────────────────────────────────────────────────────

-- Reverse side of the transaction<->document link maintained by
-- features/documents/transactionDocumentIntegrity.ts.
alter table public.documents
  add constraint documents_transaction_fk
  foreign key (transaction_id, owner_id)
  references public.transactions (id, owner_id) on delete restrict;

-- domain.ts:180 "links to OperationalEvent if auto-generated"
alter table public.transactions
  add constraint transactions_operational_event_fk
  foreign key (operational_event_id, owner_id)
  references public.operational_events (id, owner_id) on delete restrict;

-- ─── owner_id indexes ────────────────────────────────────────────────────────
-- Every RLS policy filters on owner_id, so every table needs it indexed.
create index if not exists projects_owner_idx               on public.projects (owner_id);
create index if not exists partners_owner_idx               on public.partners (owner_id);
create index if not exists assets_owner_idx                 on public.assets (owner_id);
create index if not exists documents_owner_idx              on public.documents (owner_id);
create index if not exists project_partners_owner_idx       on public.project_partners (owner_id);
create index if not exists transactions_owner_idx           on public.transactions (owner_id);
create index if not exists obligations_owner_idx            on public.obligations (owner_id);
create index if not exists settlements_owner_idx            on public.settlements (owner_id);
create index if not exists settlement_allocations_owner_idx on public.settlement_allocations (owner_id);
create index if not exists operational_events_owner_idx     on public.operational_events (owner_id);
create index if not exists stock_adjustments_owner_idx      on public.stock_adjustments (owner_id);

-- ─── hydration order-column indexes ──────────────────────────────────────────
-- Composite (owner_id, <order col> desc) matches the exact access pattern:
-- filter by tenant via RLS, then sort descending.
create index if not exists projects_owner_created_idx
  on public.projects (owner_id, created_at desc);
create index if not exists partners_owner_created_idx
  on public.partners (owner_id, created_at desc);
create index if not exists assets_owner_created_idx
  on public.assets (owner_id, created_at desc);
create index if not exists documents_owner_created_idx
  on public.documents (owner_id, created_at desc);
create index if not exists obligations_owner_created_idx
  on public.obligations (owner_id, created_at desc);
create index if not exists settlement_allocations_owner_created_idx
  on public.settlement_allocations (owner_id, created_at desc);
create index if not exists transactions_owner_date_idx
  on public.transactions (owner_id, transaction_date desc);
create index if not exists settlements_owner_date_idx
  on public.settlements (owner_id, settlement_date desc);
create index if not exists operational_events_owner_date_idx
  on public.operational_events (owner_id, event_date desc);
create index if not exists stock_adjustments_owner_date_idx
  on public.stock_adjustments (owner_id, adjustment_date desc);
-- project_partners is ordered by `id` (see the note in 0002). Indexed as-is so
-- the current client is not slowed down; the ordering choice itself is a
-- documented smell, not fixed here.
create index if not exists project_partners_owner_id_idx
  on public.project_partners (owner_id, id desc);

-- ─── FK / deletion-guard lookup indexes ──────────────────────────────────────
-- Each guard_*_deletion function counts rows referencing the entity. Without
-- these, every guard call is a sequential scan of every child table.
create index if not exists assets_project_idx                    on public.assets (project_id);
create index if not exists documents_project_idx                 on public.documents (project_id);
create index if not exists documents_asset_idx                   on public.documents (asset_id);
create index if not exists documents_partner_idx                 on public.documents (partner_id);
create index if not exists documents_transaction_idx             on public.documents (transaction_id);
create index if not exists project_partners_project_idx          on public.project_partners (project_id);
create index if not exists project_partners_partner_idx          on public.project_partners (partner_id);
create index if not exists transactions_project_idx              on public.transactions (project_id);
create index if not exists transactions_asset_idx                on public.transactions (asset_id);
create index if not exists transactions_partner_idx              on public.transactions (partner_id);
create index if not exists transactions_operational_event_idx    on public.transactions (operational_event_id);
create index if not exists obligations_project_idx               on public.obligations (project_id);
create index if not exists obligations_partner_idx               on public.obligations (partner_id);
create index if not exists obligations_document_idx              on public.obligations (document_id);
create index if not exists obligations_source_transaction_idx    on public.obligations (source_transaction_id);
create index if not exists settlements_obligation_idx            on public.settlements (obligation_id);
create index if not exists settlements_receipt_document_idx      on public.settlements (receipt_document_id);
create index if not exists settlement_allocations_settlement_idx on public.settlement_allocations (settlement_id);
create index if not exists settlement_allocations_obligation_idx on public.settlement_allocations (obligation_id);
create index if not exists operational_events_asset_idx          on public.operational_events (asset_id);
create index if not exists operational_events_project_idx        on public.operational_events (project_id);
create index if not exists operational_events_document_idx       on public.operational_events (document_id);
create index if not exists operational_events_transaction_idx    on public.operational_events (linked_transaction_id);
create index if not exists stock_adjustments_asset_idx           on public.stock_adjustments (asset_id);
create index if not exists stock_adjustments_project_idx         on public.stock_adjustments (project_id);
