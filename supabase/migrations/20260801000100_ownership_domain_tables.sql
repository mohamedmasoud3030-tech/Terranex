-- =============================================================================
-- Terranex — Phase 2B — Ownership domain tables
-- =============================================================================
-- Adds effective-dated ownership tracking, append-only partner ledger, and
-- immutable distribution records.
--
-- Tables:
--   equity_change_events    — time-based ownership change log
--   partner_ledger_entries  — append-only partner financial ledger
--   distributions           — profit distribution header
--   distribution_allocations — per-partner frozen shares
--
-- All tables follow the existing pattern: owner_id uuid not null default auth.uid(),
-- composite unique (id, owner_id), FK to parent entities via (id, owner_id).
-- Money columns are numeric(18,4). Dates that clients send as YYYY-MM-DD are date.
-- =============================================================================

-- ─── New enum types ──────────────────────────────────────────────────────────

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_equity_change_type') then
    create type public.terranex_equity_change_type as enum ('entry', 'increase', 'decrease', 'exit', 'correction');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_ledger_entry_type') then
    create type public.terranex_ledger_entry_type as enum (
      'capital_contribution', 'withdrawal', 'distribution_entitlement',
      'distribution_payment', 'correction', 'reversal'
    );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_distribution_status') then
    create type public.terranex_distribution_status as enum ('draft', 'approved', 'paid', 'reversed');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'terranex_distribution_allocation_status') then
    create type public.terranex_distribution_allocation_status as enum ('due', 'paid', 'reversed');
  end if;
end $$;

-- ─── equity_change_events ────────────────────────────────────────────────────
-- Records every change in a partner's equity percentage. Append-only:
-- corrections are modeled as new events referencing the original.
create table if not exists public.equity_change_events (
  id                      uuid primary key default gen_random_uuid(),
  owner_id                uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id              uuid                               not null,
  partner_id              uuid                               not null,
  effective_date          date                               not null,
  previous_pct            numeric(7, 4)                      not null check (previous_pct >= 0 and previous_pct <= 100),
  new_pct                 numeric(7, 4)                      not null check (new_pct >= 0 and new_pct <= 100),
  change_type             public.terranex_equity_change_type not null,
  consideration_amount    numeric(18, 4)                     check (consideration_amount is null or consideration_amount >= 0),
  consideration_currency  public.terranex_currency,
  frozen_amount_egp       numeric(18, 4)                     check (frozen_amount_egp is null or frozen_amount_egp >= 0),
  supporting_document_id  uuid,
  reason                  text,
  notes                   text,
  created_by              uuid                               not null default auth.uid(),
  created_at              timestamptz                        not null default now(),
  reversal_of_id          uuid,
  constraint equity_change_events_id_owner_key unique (id, owner_id),
  constraint equity_change_events_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint equity_change_events_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint equity_change_events_document_fk foreign key (supporting_document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  constraint equity_change_events_self_ref_fk foreign key (reversal_of_id, owner_id)
    references public.equity_change_events (id, owner_id) on delete restrict,
  -- entry must increase from 0; exit must go to 0
  constraint equity_change_entry_increases check (
    change_type <> 'entry' or (previous_pct = 0 and new_pct > 0)
  ),
  constraint equity_change_exit_decreases check (
    change_type <> 'exit' or (previous_pct > 0 and new_pct = 0)
  ),
  -- consideration currency only when consideration amount is present
  constraint equity_change_consideration_currency check (
    consideration_amount is null or consideration_currency is not null
  )
);

create index if not exists idx_equity_change_events_project_effective
  on public.equity_change_events (project_id, effective_date);
create index if not exists idx_equity_change_events_partner
  on public.equity_change_events (partner_id, project_id);

-- ─── partner_ledger_entries ──────────────────────────────────────────────────
-- Append-only financial record per partner per project. Immutable: reversals
-- are modeled as new entries referencing the original.
create table if not exists public.partner_ledger_entries (
  id                        uuid primary key default gen_random_uuid(),
  owner_id                  uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id                uuid                               not null,
  partner_id                uuid                               not null,
  entry_type                public.terranex_ledger_entry_type  not null,
  amount                    numeric(18, 4)                     not null check (amount > 0),
  currency                  public.terranex_currency           not null,
  fx_rate                   numeric(18, 8)                     not null check (fx_rate > 0),
  amount_egp                numeric(18, 4)                     not null check (amount_egp > 0),
  posting_date              date                               not null,
  supporting_document_id    uuid,
  related_equity_event_id   uuid,
  related_distribution_id   uuid,
  notes                     text,
  reversal_of_id            uuid,
  created_by                uuid                               not null default auth.uid(),
  created_at                timestamptz                        not null default now(),
  constraint partner_ledger_entries_id_owner_key unique (id, owner_id),
  constraint partner_ledger_entries_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint partner_ledger_entries_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint partner_ledger_entries_document_fk foreign key (supporting_document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  constraint partner_ledger_entries_equity_event_fk foreign key (related_equity_event_id, owner_id)
    references public.equity_change_events (id, owner_id) on delete restrict,
  constraint partner_ledger_entries_self_ref_fk foreign key (reversal_of_id, owner_id)
    references public.partner_ledger_entries (id, owner_id) on delete restrict
);

create index if not exists idx_partner_ledger_entries_project_partner
  on public.partner_ledger_entries (project_id, partner_id, posting_date);
create index if not exists idx_partner_ledger_entries_distribution
  on public.partner_ledger_entries (related_distribution_id)
  where related_distribution_id is not null;

-- ─── distributions ───────────────────────────────────────────────────────────
-- Profit distribution header. Snapshots ownership percentages at distribution time.
create table if not exists public.distributions (
  id                        uuid primary key default gen_random_uuid(),
  owner_id                  uuid not null default auth.uid() references auth.users (id) on delete restrict,
  project_id                uuid                               not null,
  distribution_date         date                               not null,
  ownership_as_of_date      date                               not null,
  total_amount              numeric(18, 4)                     not null check (total_amount > 0),
  currency                  public.terranex_currency           not null,
  fx_rate                   numeric(18, 8)                     not null check (fx_rate > 0),
  total_amount_egp          numeric(18, 4)                     not null check (total_amount_egp > 0),
  status                    public.terranex_distribution_status not null default 'draft',
  notes                     text,
  supporting_document_id    uuid,
  created_by                uuid                               not null default auth.uid(),
  created_at                timestamptz                        not null default now(),
  constraint distributions_id_owner_key unique (id, owner_id),
  constraint distributions_project_fk foreign key (project_id, owner_id)
    references public.projects (id, owner_id) on delete restrict,
  constraint distributions_document_fk foreign key (supporting_document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  constraint distributions_dates_ordered check (ownership_as_of_date <= distribution_date)
);

create index if not exists idx_distributions_project_date
  on public.distributions (project_id, distribution_date desc);

-- ─── distribution_allocations ────────────────────────────────────────────────
-- Per-partner share of a distribution. Equity percentage and amounts are frozen
-- at creation. Payment status tracked separately from the header.
create table if not exists public.distribution_allocations (
  id                      uuid primary key default gen_random_uuid(),
  owner_id                uuid not null default auth.uid() references auth.users (id) on delete restrict,
  distribution_id         uuid                                        not null,
  partner_id              uuid                                        not null,
  equity_pct_snapshot     numeric(7, 4)                               not null check (equity_pct_snapshot >= 0 and equity_pct_snapshot <= 100),
  allocated_amount        numeric(18, 4)                              not null check (allocated_amount >= 0),
  allocated_amount_egp    numeric(18, 4)                              not null check (allocated_amount_egp >= 0),
  status                  public.terranex_distribution_allocation_status not null default 'due',
  payment_date            date,
  payment_document_id     uuid,
  related_ledger_entry_id uuid,
  constraint distribution_allocations_id_owner_key unique (id, owner_id),
  constraint distribution_allocations_distribution_fk foreign key (distribution_id, owner_id)
    references public.distributions (id, owner_id) on delete restrict,
  constraint distribution_allocations_partner_fk foreign key (partner_id, owner_id)
    references public.partners (id, owner_id) on delete restrict,
  constraint distribution_allocations_document_fk foreign key (payment_document_id, owner_id)
    references public.documents (id, owner_id) on delete restrict,
  constraint distribution_allocations_ledger_fk foreign key (related_ledger_entry_id, owner_id)
    references public.partner_ledger_entries (id, owner_id) on delete restrict,
  -- each partner appears at most once per distribution
  constraint distribution_allocations_unique_partner unique (distribution_id, partner_id),
  -- payment date only when paid
  constraint distribution_allocations_payment_consistent check (
    (status = 'paid' and payment_date is not null)
    or (status <> 'paid' and payment_date is null)
  )
);

create index if not exists idx_distribution_allocations_distribution
  on public.distribution_allocations (distribution_id);

\echo '=== 2B OWNERSHIP DOMAIN TABLES: MIGRATION COMPLETE ==='
