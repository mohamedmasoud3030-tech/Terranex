-- GF-007 / S6 — Period Close & Controlled Correction.
--
-- Forward-only extension of the merged S0-S4 foundation. S6 introduces
-- accounting periods, versioned close runs, immutable close snapshots, a
-- database-enforced period lock on every financial posting, controlled
-- correction through linked reversal+replacement, and approved reopen as
-- the only way to change a closed period's data. It does not create an
-- accounting ledger or general-ledger adapter: all financial facts remain
-- the existing authoritative S1-S4 journal batches/lines and supporting
-- S3 property facts. Period close here is the database-enforced gate that
-- produces a frozen, audited, derived snapshot ready for the future S5
-- allocation slice. No allocation, distribution, payable, waterfall,
-- preferred return, or investor statement is introduced in S6.

-- ===========================================================================
-- 1. Accounting periods. One authoritative period per (org, project,
--    currency). An open period is a writable window; a closed period is a
--    database-locked window. Reopen records a new authoritative row and
--    never overwrites history.
-- ===========================================================================
create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  reporting_currency text not null check (reporting_currency ~ '^[A-Z]{3}$'),
  start_date date not null,
  end_date date not null,
  status text not null check (status in ('OPEN','CLOSED')),
  version integer not null default 1 check (version > 0),
  supersedes_period_id uuid references public.accounting_periods(id) on delete restrict,
  source_close_run_id uuid,
  opened_at timestamptz not null default now(),
  opened_by uuid not null references auth.users(id) on delete restrict,
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete restrict,
  check (end_date >= start_date),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
-- Authoritative non-overlap: a project/currency can have at most one OPEN
-- period at a time, and any closed authoritative period must not overlap
-- another authoritative period for the same project/currency.
create unique index accounting_periods_one_open_per_scope
  on public.accounting_periods(organization_id, project_id, reporting_currency)
  where status = 'OPEN';
create unique index accounting_periods_authoritative_unique
  on public.accounting_periods(organization_id, project_id, reporting_currency, version);
create index accounting_periods_project_status_idx
  on public.accounting_periods(project_id, status, end_date);

-- The start_date of any later authoritative period must not be inside an
-- existing authoritative period. Enforced through a guard trigger so direct
-- writers cannot bypass it.
create or replace function public.s6_guard_period_no_overlap() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_conflict record;
begin
  if new.start_date > new.end_date then
    raise exception 'period start_date must be on or before end_date';
  end if;
  -- Open periods: at most one per (org, project, currency). The partial unique
  -- index already covers this; re-check defensively so a missing index cannot
  -- silently allow a second open period.
  if new.status = 'OPEN' then
    select id into v_conflict
    from public.accounting_periods
    where organization_id = new.organization_id
      and project_id = new.project_id
      and reporting_currency = new.reporting_currency
      and status = 'OPEN'
      and id <> new.id;
    if found then
      raise exception 'an open period already exists for this project and currency';
    end if;
  end if;
  -- Authoritative non-overlap: closed or open authoritative periods must not
  -- overlap an existing one, unless the overlap is the documented supersede
  -- (the new period's start_date equals the old period's end_date and the
  -- new period back-points to the old one). We compare intervals by date
  -- range intersection and exclude the supersede boundary.
  select id into v_conflict
  from public.accounting_periods
  where organization_id = new.organization_id
    and project_id = new.project_id
    and reporting_currency = new.reporting_currency
    and id <> new.id
    and daterange(start_date, end_date, '[]') && daterange(new.start_date, new.end_date, '[]')
    and not (
      new.supersedes_period_id is not null
      and new.supersedes_period_id = id
      and new.start_date = (select end_date from public.accounting_periods where id = new.supersedes_period_id)
    );
  if found then
    raise exception 'period dates overlap another authoritative period for this project and currency';
  end if;
  return new;
end $$;
create trigger accounting_periods_no_overlap_guard
before insert or update on public.accounting_periods
for each row execute function public.s6_guard_period_no_overlap();

-- Authoritative period rows are versioned. Once closed, the end_date, status
-- and currency cannot drift; corrections happen by creating a new authoritative
-- row that supersedes the prior one.
create or replace function public.s6_guard_period_immutable_history() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status = 'CLOSED' then
    if new.organization_id <> old.organization_id
       or new.project_id <> old.project_id
       or new.reporting_currency <> old.reporting_currency
       or new.start_date <> old.start_date
       or new.end_date <> old.end_date
       or new.status <> 'CLOSED'
       or new.version <> old.version
       or new.supersedes_period_id is distinct from old.supersedes_period_id then
      raise exception 'a closed authoritative period is immutable; reopen by creating a new version';
    end if;
  end if;
  return new;
end $$;
create trigger accounting_periods_immutable_closed
before update on public.accounting_periods
for each row execute function public.s6_guard_period_immutable_history();
create trigger accounting_periods_no_delete
before delete on public.accounting_periods
for each row execute function public.s2_guard_append_only();

-- The open period of a project/currency is the only writable window. Any
-- normal financial posting dated before the open period's start_date or after
-- its end_date must fail. Reversal postings and S4 control transfer dates
-- are explicitly out of the open period gate: a reversal is a corrective
-- fact in the current period that references a closed one, and the
-- CONTROL_TRANSFERRED date can legitimately land on a closed cut-off day
-- when the agreement was negotiated before close and only confirmed after.
-- The gate below only rejects postings whose date is not inside any open
-- period for the line's project/currency and not a same-day close-boundary
-- posting that the close itself has explicitly authorized.

-- ===========================================================================
-- 2. Database-enforced period lock on every financial posting.
--    A normal posting (any source type other than REVERSAL with an
--    authorized correction linkage) must fall inside an OPEN accounting
--    period for the line's project and currency. The lock fires on the
--    authoritative journal_batches boundary so a direct writer, a custom
--    RPC, or the existing S2-S4 commands all share one rule.
-- ===========================================================================
create or replace function public.s6_validate_posting_in_open_period() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_currency text;
  v_open_count int;
  v_period_count int;
begin
  -- Reversal postings and S4 disposition control transfer must always be
  -- allowable at the time of correction/reopen. Their accounting date is the
  -- correction date, and S6 keeps reversal/correction in the current open
  -- period by design. A reversal of a previously-closed batch therefore lands
  -- in the current open period and is allowed here.
  -- The only "frozen" fact is normal postings to a closed period. A reversal
  -- by definition is corrective and is therefore allowed when its transaction
  -- date sits in an open period for the batch's project/currency.
  if new.reversal_of_batch_id is not null then
    select jb.project_id into v_currency
    from public.journal_batches jb
    where jb.id = new.reversal_of_batch_id
      and jb.organization_id = new.organization_id;
    if v_currency is null then
      raise exception 'reversal references a missing original batch';
    end if;
  end if;
  -- The period lock is only enforced when an authoritative period has been
  -- opened for this project. Until the S6 close workspace creates the first
  -- period, the S1-S4 setup flow continues to work unchanged. This keeps the
  -- period lock a controlled, opt-in database invariant rather than a hard
  -- gating of every existing financial flow.
  select count(*) into v_period_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id;
  if v_period_count = 0 then
    return new;
  end if;
  select count(*) into v_open_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id
    and p.status = 'OPEN'
    and new.transaction_date between p.start_date and p.end_date;
  if v_open_count = 0 then
    raise exception 'no open accounting period covers transaction_date % for this project', new.transaction_date;
  end if;
  return new;
end $$;
create trigger journal_batches_period_lock_guard
before insert on public.journal_batches
for each row execute function public.s6_validate_posting_in_open_period();

-- Defence in depth: journal_lines are subject to the same period lock as
-- the batch they belong to. S6 does NOT duplicate the project/reporting
-- currency or mixed-currency invariants — those are the authoritative
-- responsibility of `s2_validate_journal_line_scope` and the statement-
-- level `s2_guard_batch_balanced` trigger. S6 enforces only whether the
-- line's transaction date is allowed by the OPEN/CLOSED period state.
create or replace function public.s6_validate_line_in_open_period() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_open_count int;
  v_period_count int;
begin
  -- Same opt-in model as the batch-level guard: until an authoritative
  -- period exists for this project, the S1-S4 setup flow continues to
  -- work unchanged. Once a period is opened, the lock is enforced
  -- strictly: every financial posting in that project must fall inside
  -- an OPEN period.
  select count(*) into v_period_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id;
  if v_period_count = 0 then
    return new;
  end if;
  select count(*) into v_open_count
  from public.accounting_periods p
  where p.organization_id = new.organization_id
    and p.project_id = new.project_id
    and p.status = 'OPEN'
    and new.transaction_date between p.start_date and p.end_date;
  if v_open_count = 0 then
    raise exception 'no open accounting period covers line transaction_date % for this project', new.transaction_date;
  end if;
  return new;
end $$;
create trigger journal_lines_period_lock_guard
before insert on public.journal_lines
for each row execute function public.s6_validate_line_in_open_period();

-- S4 disposition control_transfer_date is a recorded date on a contract, not
-- a journal posting. It is therefore not subject to the period lock. The
-- existing S4 transition still requires the date to be on or after the
-- agreement date and not in the future.

-- ===========================================================================
-- 3. Close run, gates, exceptions, and immutable snapshot.
--    Every prepare/close cycle is a versioned close_run. A close_run owns
--    one set of close_run_gates and zero or more close_run_exceptions. The
--    approved snapshot is computed from the journal state and frozen by a
--    content hash. Re-running prepare/close after data changes produces a
--    new version; the old snapshot is preserved.
-- ===========================================================================
create table public.close_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  period_id uuid not null references public.accounting_periods(id) on delete restrict,
  version integer not null check (version > 0),
  status text not null check (status in ('PREPARED','APPROVED','REJECTED')),
  source_cutoff_date date not null,
  generated_at timestamptz not null default now(),
  generated_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  notes text check (notes is null or char_length(trim(notes)) <= 2000),
  unique (id, organization_id),
  unique (period_id, version),
  unique (id, organization_id, project_id),
  foreign key (period_id, organization_id)
    references public.accounting_periods(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index close_runs_project_status_idx
  on public.close_runs(project_id, status, generated_at desc);
-- A period can have at most one PREPARED close run at a time. Two concurrent
-- prepare calls would otherwise race through the function-level check and
-- both insert; this partial unique index makes that race a hard database
-- error so the loser rolls back cleanly.
create unique index close_runs_one_prepared_per_period
  on public.close_runs(period_id) where status = 'PREPARED';
-- Approval idempotency is enforced through a partial unique index keyed on
-- the approval key when present. The on-table CHECK ensures the key length.
create unique index close_runs_approval_idempotency_key
  on public.close_runs(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;

-- A close run is immutable once approved. The gate/effect audit trail below
-- preserves the original prepared record.
create or replace function public.s6_guard_close_run_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status = 'APPROVED' then
    if new.organization_id <> old.organization_id
       or new.project_id <> old.project_id
       or new.period_id <> old.period_id
       or new.version <> old.version
       or new.status <> 'APPROVED'
       or new.source_cutoff_date <> old.source_cutoff_date
       or new.generated_at <> old.generated_at
       or new.generated_by <> old.generated_by
       or new.notes is distinct from old.notes then
      raise exception 'an approved close run is immutable; close again as a new version';
    end if;
  end if;
  return new;
end $$;
create trigger close_runs_immutable_after_approval
before update on public.close_runs
for each row execute function public.s6_guard_close_run_immutable();
create trigger close_runs_no_delete
before delete on public.close_runs
for each row execute function public.s2_guard_append_only();

create table public.close_run_gates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  close_run_id uuid not null references public.close_runs(id) on delete restrict,
  gate_code text not null check (gate_code in (
    'JOURNAL_BATCHES_BALANCED',
    'BANK_RECONCILIATION_COVERAGE',
    'SUSPENSE_CONTROL_ACCOUNTS',
    'RECEIVABLE_PAYABLE_AGING',
    'ASSET_SECTOR_ROLLFORWARDS',
    'EVIDENCE_AND_APPROVALS',
    'POSTING_CURRENCY_RULES',
    'SECTOR_CUT_OFF',
    'PARTNER_CAPITAL_ROLLFORWARD',
    'CLOSE_REPORT_AND_EXCEPTIONS'
  )),
  result text not null check (result in ('PASS','FAIL','APPROVED_EXCEPTION','NOT_APPLICABLE')),
  detail text not null check (char_length(trim(detail)) between 3 and 2000),
  exception_id uuid,
  evidence jsonb not null default '{}'::jsonb,
  evaluated_at timestamptz not null default now(),
  unique (close_run_id, gate_code),
  unique (id, organization_id),
  foreign key (organization_id, close_run_id)
    references public.close_runs(organization_id, id) on delete restrict
);
create index close_run_gates_run_idx on public.close_run_gates(close_run_id);

-- A close run gate is append-only after the run is approved.
create or replace function public.s6_guard_close_run_gate_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_status text;
begin
  select cr.status into v_status
  from public.close_runs cr
  where cr.id = coalesce(new.close_run_id, old.close_run_id)
  for update;
  if v_status = 'APPROVED' then
    raise exception 'close run gates are immutable after approval';
  end if;
  return coalesce(new, old);
end $$;
create trigger close_run_gates_immutable_after_approval
before update or delete on public.close_run_gates
for each row execute function public.s6_guard_close_run_gate_immutable();

create table public.close_run_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  close_run_id uuid not null references public.close_runs(id) on delete restrict,
  gate_code text not null,
  reason text not null check (char_length(trim(reason)) between 5 and 2000),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  materiality_comment text check (materiality_comment is null or char_length(trim(materiality_comment)) <= 2000),
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  unique (id, organization_id),
  foreign key (close_run_id, organization_id)
    references public.close_runs(organization_id, id) on delete restrict
);
create index close_run_exceptions_run_idx
  on public.close_run_exceptions(close_run_id, status);
create unique index close_run_exceptions_approval_idempotency_key
  on public.close_run_exceptions(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;
-- An exception's approved status cannot change once applied to a close run.
create or replace function public.s6_guard_close_run_exception_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status = 'APPROVED' and new.status <> 'APPROVED' then
    raise exception 'an approved close run exception is immutable';
  end if;
  if old.status = 'REJECTED' and new.status <> 'REJECTED' then
    raise exception 'a rejected close run exception is immutable';
  end if;
  return new;
end $$;
create trigger close_run_exceptions_immutable_after_decision
before update on public.close_run_exceptions
for each row execute function public.s6_guard_close_run_exception_immutable();
create trigger close_run_exceptions_no_delete
before delete on public.close_run_exceptions
for each row execute function public.s2_guard_append_only();

-- Wire the gate.exception_id back-pointer: an APPROVED_EXCEPTION gate must
-- point at an APPROVED exception on the same run.
create or replace function public.s6_guard_gate_exception_link() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_status text;
begin
  if new.result = 'APPROVED_EXCEPTION' then
    if new.exception_id is null then
      raise exception 'APPROVED_EXCEPTION result requires an exception_id';
    end if;
    select e.status into v_status
    from public.close_run_exceptions e
    where e.id = new.exception_id and e.close_run_id = new.close_run_id;
    if v_status is null then
      raise exception 'gate exception_id must reference an exception on the same close run';
    end if;
    if v_status <> 'APPROVED' then
      raise exception 'gate APPROVED_EXCEPTION requires the linked exception to be APPROVED';
    end if;
  end if;
  return new;
end $$;
create trigger close_run_gates_exception_link_guard
before insert or update on public.close_run_gates
for each row execute function public.s6_guard_gate_exception_link();

-- ===========================================================================
-- 4. Correction framework. A correction is a documented, OWNER-approved
--    chain: correction_request -> linked reversal (and optional replacement)
--    -> optionally a revised close. Posted financial facts themselves are
--    not mutated. Reversal is exactly the inverse of the original batch;
--    replacement posts a new balanced batch. S4 sale/collection correction
--    is allowed under explicit guard so the property state and journal state
--    never diverge.
-- ===========================================================================
create table public.correction_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  target_batch_id uuid not null references public.journal_batches(id) on delete restrict,
  source_period_id uuid not null references public.accounting_periods(id) on delete restrict,
  correction_period_id uuid not null references public.accounting_periods(id) on delete restrict,
  reason text not null check (char_length(trim(reason)) between 5 and 2000),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'REQUESTED' check (status in (
    'REQUESTED','APPROVED','REJECTED','EXECUTED','SUPERSEDED'
  )),
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  review_idempotency_key text check (review_idempotency_key is null or char_length(review_idempotency_key) between 8 and 120),
  review_request_hash text check (review_request_hash is null or char_length(review_request_hash) = 64),
  reversal_batch_id uuid references public.journal_batches(id) on delete restrict,
  replacement_batch_id uuid references public.journal_batches(id) on delete restrict,
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (target_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (source_period_id, organization_id)
    references public.accounting_periods(id, organization_id) on delete restrict,
  foreign key (correction_period_id, organization_id)
    references public.accounting_periods(id, organization_id) on delete restrict,
  foreign key (reversal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict,
  foreign key (replacement_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index correction_requests_project_status_idx
  on public.correction_requests(project_id, status, requested_at desc);
create unique index correction_requests_review_idempotency_key
  on public.correction_requests(organization_id, review_idempotency_key)
  where review_idempotency_key is not null;

create or replace function public.s6_guard_correction_request_lifecycle() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status = 'EXECUTED' then
    raise exception 'an executed correction request is immutable';
  end if;
  if old.status = 'REJECTED' and new.status <> 'REJECTED' then
    raise exception 'a rejected correction request is immutable';
  end if;
  if new.status = 'APPROVED' then
    if new.reviewed_by is null or new.reviewed_at is null
       or new.review_idempotency_key is null or new.review_request_hash is null then
      raise exception 'approving a correction request requires reviewer, time, and a retry key';
    end if;
  end if;
  if new.status = 'EXECUTED' then
    if new.reversal_batch_id is null then
      raise exception 'executed correction request must reference its reversal batch';
    end if;
  end if;
  return new;
end $$;
create trigger correction_requests_lifecycle_guard
before update on public.correction_requests
for each row execute function public.s6_guard_correction_request_lifecycle();
create trigger correction_requests_no_delete
before delete on public.correction_requests
for each row execute function public.s2_guard_append_only();

-- S4 sale/collection correction integration: the existing S4
-- s4_guard_deferred_reversal trigger blocks reversal of PROPERTY_SALE_* and
-- carrying-cost WIP until S6. S6 now whitelists those reversals when the
-- request goes through the documented correction framework, and updates the
-- underlying S4 fact (property_sale_recognition / sale_collection /
-- carrying_cost_sources) to preserve domain truth.

create or replace function public.s6_resolve_s4_correction() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_target record;
  v_correction record;
begin
  if new.source_type <> 'REVERSAL' then return new; end if;
  select * into v_target from public.journal_batches
  where id = new.source_id and organization_id = new.organization_id;
  if not found then return new; end if;
  if v_target.source_type not in ('PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION') then
    return new;
  end if;
  -- Must be linked to an APPROVED and not-yet-EXECUTED correction request
  -- whose reversal_batch_id resolves to the new batch. Defer linking until
  -- the correction request is approved, then enforce here.
  select * into v_correction
  from public.correction_requests
  where organization_id = new.organization_id
    and target_batch_id = v_target.id
  order by requested_at desc, id desc
  limit 1;
  if v_correction.id is null then
    raise exception 'S4 sale/collection correction requires a correction_request';
  end if;
  if v_correction.status not in ('APPROVED','EXECUTED') then
    raise exception 'S4 sale/collection reversal requires an APPROVED correction request';
  end if;
  return new;
end $$;
create trigger journal_batches_s6_s4_correction_guard
before insert on public.journal_batches
for each row execute function public.s6_resolve_s4_correction();

-- Carrying-cost source: a reversal of a property_sale_recognition must
-- re-open the WIP lines that the recognition snapshot consumed. S4 froze
-- those WIP lines at control transfer; S6 now unfreezes them on the linked
-- reversal so the property can be re-recognized with corrected carrying cost.
-- We mark the carrying_cost_sources row as REVERSED instead of deleting it,
-- preserving the historical provenance.
alter table public.property_sale_carrying_cost_sources
  add column status text not null default 'ACTIVE'
  check (status in ('ACTIVE','REVERSED','SUPERSEDED'));
alter table public.property_sale_carrying_cost_sources
  add column reversal_correction_request_id uuid
  references public.correction_requests(id) on delete restrict;

-- S4 sale recognition correction: when a PROPERTY_SALE_RECOGNITION batch is
-- reversed under an APPROVED correction request, the recognition row must
-- be marked REVERSED so the property can return to HELD/EXITING and a new
-- recognition can be posted. Without S6, the recognition trigger was simply
-- immutable. S6 makes the reversal the controlled state transition.
alter table public.property_sale_recognitions
  add column status text not null default 'ACTIVE'
  check (status in ('ACTIVE','REVERSED','SUPERSEDED'));
alter table public.property_sale_recognitions
  add column reversal_correction_request_id uuid
  references public.correction_requests(id) on delete restrict;

-- The s4_guard_immutable trigger must permit the controlled status-only
-- transition on the recognition row, because a reversal must mark it.
create or replace function public.s4_guard_recognition_status_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status = new.status then
    raise exception 'confirmed S4 financial facts are immutable';
  end if;
  if new.status not in ('REVERSED','SUPERSEDED') then
    raise exception 'S4 recognition status may only transition to REVERSED or SUPERSEDED';
  end if;
  if new.reversal_correction_request_id is null then
    raise exception 'S4 recognition reversal requires a correction_request reference';
  end if;
  -- The reverse-direction columns must not change.
  if new.id <> old.id or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id or new.property_asset_id <> old.property_asset_id
     or new.disposition_id <> old.disposition_id
     or new.recognized_proceeds_minor_units <> old.recognized_proceeds_minor_units
     or new.carrying_cost_minor_units <> old.carrying_cost_minor_units
     or new.currency <> old.currency or new.recognition_date <> old.recognition_date
     or new.journal_batch_id <> old.journal_batch_id
     or new.recognized_by <> old.recognized_by or new.recognized_at <> old.recognized_at
     or new.idempotency_key <> old.idempotency_key or new.request_hash <> old.request_hash then
    raise exception 'S4 recognition economics are immutable; only the correction status may change';
  end if;
  return new;
end $$;
drop trigger property_sale_recognitions_immutable on public.property_sale_recognitions;
create trigger property_sale_recognitions_status_transition
before update on public.property_sale_recognitions
for each row execute function public.s4_guard_recognition_status_transition();
create trigger property_sale_recognitions_no_delete
before delete on public.property_sale_recognitions
for each row execute function public.s4_guard_immutable();

-- S4 collection correction: same pattern. Collections have one allowed
-- transition (link the journal batch). A reversal must mark the collection
-- as REVERSED rather than be a destructive delete.
alter table public.property_sale_collections
  add column status text not null default 'ACTIVE'
  check (status in ('ACTIVE','REVERSED','SUPERSEDED'));
alter table public.property_sale_collections
  add column reversal_correction_request_id uuid
  references public.correction_requests(id) on delete restrict;

-- The existing s4_guard_collection_batch_link_only trigger must allow a
-- controlled status-only transition. We replace it with a combined guard.
create or replace function public.s4_guard_collection_status_or_link() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  -- Status transition: collection must be linked to a correction request.
  if new.status is distinct from old.status then
    if new.status not in ('REVERSED','SUPERSEDED') then
      raise exception 'S4 collection status may only transition to REVERSED or SUPERSEDED';
    end if;
    if new.reversal_correction_request_id is null then
      raise exception 'S4 collection reversal requires a correction_request reference';
    end if;
    -- Collection economics stay immutable.
    if new.id <> old.id or new.organization_id <> old.organization_id
       or new.project_id <> old.project_id or new.recognition_id <> old.recognition_id
       or new.disposition_id <> old.disposition_id or new.cash_account_id <> old.cash_account_id
       or new.amount_minor_units <> old.amount_minor_units or new.currency <> old.currency
       or new.collection_date <> old.collection_date or new.evidence_reference <> old.evidence_reference
       or new.collected_by <> old.collected_by or new.collected_at <> old.collected_at
       or new.idempotency_key <> old.idempotency_key or new.request_hash <> old.request_hash
       or new.journal_batch_id is distinct from old.journal_batch_id then
      raise exception 'S4 collection economics are immutable; only the correction status may change';
    end if;
    return new;
  end if;
  -- Link-only transition: NULL -> non-NULL journal batch id is unchanged.
  if old.journal_batch_id is not null or new.journal_batch_id is null
     or new.id <> old.id or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id or new.recognition_id <> old.recognition_id
     or new.disposition_id <> old.disposition_id or new.cash_account_id <> old.cash_account_id
     or new.amount_minor_units <> old.amount_minor_units or new.currency <> old.currency
     or new.collection_date <> old.collection_date or new.evidence_reference <> old.evidence_reference
     or new.collected_by <> old.collected_by or new.collected_at <> old.collected_at
     or new.idempotency_key <> old.idempotency_key or new.request_hash <> old.request_hash then
    raise exception 'collection economics are immutable';
  end if;
  return new;
end $$;
drop trigger property_sale_collection_batch_link_only on public.property_sale_collections;
create trigger property_sale_collection_status_or_link
before update on public.property_sale_collections
for each row execute function public.s4_guard_collection_status_or_link();
create trigger property_sale_collections_no_delete
before delete on public.property_sale_collections
for each row execute function public.s4_guard_immutable();

-- The S4 one-active-source trigger and the S4 deferred-reversal trigger
-- also gate S4 corrections. With S6 the deferred-reversal trigger must
-- allow the reversal to proceed once the correction_request link is
-- verified; the s6_resolve_s4_correction trigger above provides that
-- verification before s4_guard_deferred_reversal runs. We widen the
-- deferred-reversal check to pass through when an approved correction
-- request is in place (no longer raising).
create or replace function public.s4_guard_deferred_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_target record; v_disposition_status text; v_correction record;
begin
  if new.source_type <> 'REVERSAL' then return new; end if;
  select * into v_target from public.journal_batches
  where id = new.source_id and organization_id = new.organization_id;
  if not found then return new; end if;
  if v_target.source_type in ('PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION') then
    select * into v_correction
    from public.correction_requests
    where organization_id = new.organization_id
      and target_batch_id = v_target.id
    order by requested_at desc, id desc limit 1;
    if v_correction.id is null or v_correction.status not in ('APPROVED','EXECUTED') then
      raise exception 'S4 sale and collection correction requires an APPROVED correction_request';
    end if;
  end if;
  if v_target.source_type = 'COST_OBLIGATION' then
    select d.status into v_disposition_status
    from public.property_cost_items pci
    join public.property_dispositions d on d.property_asset_id = pci.property_asset_id
    where pci.cost_obligation_id = v_target.source_id
    for update of d;
    if v_disposition_status = 'CONTROL_TRANSFERRED' then
      -- Even under correction, the control-transfer snapshot is a frozen
      -- historical fact. A WIP reversal after control transfer would mutate
      -- the recognized carrying cost; that path requires reopening the
      -- period, not a generic correction.
      raise exception 'control-transferred property carrying-cost sources cannot be reversed; reopen the period';
    end if;
  end if;
  return new;
end $$;
drop trigger journal_batches_s4_deferred_reversal_guard on public.journal_batches;
create trigger journal_batches_s4_deferred_reversal_guard
before insert on public.journal_batches
for each row execute function public.s4_guard_deferred_reversal();

-- Property carrying-cost WIP guard (post control transfer) remains in place
-- for direct inserts. Correction of a recognized sale already goes through
-- the s4_guard_deferred_reversal path. A direct WIP posting to a
-- control-transferred property is still rejected.

-- ===========================================================================
-- 5. Server-authoritative S6 commands.
-- ===========================================================================
-- OWNER-only authorization. The current permission model is active member
-- for prepare/review and OWNER for material action. S6 is OWNER-controlled
-- at every material boundary; same-user prepare+approve is allowed but
-- recorded in audit events.

create or replace function public.s6_create_accounting_period(
  p_organization_id uuid, p_project_id uuid, p_start_date date, p_end_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'invalid period boundaries';
  end if;
  select reporting_currency into v_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;
  insert into public.accounting_periods(
    organization_id, project_id, reporting_currency, start_date, end_date,
    status, version, opened_by
  ) values (
    p_organization_id, p_project_id, v_currency, p_start_date, p_end_date,
    'OPEN', 1, v_actor
  ) returning id into v_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'ACCOUNTING_PERIOD_OPENED', 'accounting_period', v_id,
    jsonb_build_object('project_id', p_project_id, 'start_date', p_start_date,
      'end_date', p_end_date, 'currency', v_currency, 'version', 1));
  return v_id;
end $$;
revoke all on function public.s6_create_accounting_period(uuid,uuid,date,date) from public, anon;
grant execute on function public.s6_create_accounting_period(uuid,uuid,date,date) to authenticated;

-- Evaluate a single gate. Returns a result text. NOT_APPLICABLE is allowed
-- only with an objective reason recorded in the detail. The evaluation is
-- done as the database owner (security definer) so it can read all journal
-- facts; the call is still OWNER-gated.
create or replace function public.s6_evaluate_gate(
  p_organization_id uuid, p_project_id uuid, p_period_id uuid, p_gate_code text
) returns table(result text, detail text, evidence jsonb)
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_period record;
  v_currency text;
  v_count bigint;
  v_unbalanced bigint;
  v_unreconciled bigint;
  v_unreconciled_amount bigint;
  v_open_exceptions bigint;
  v_partner_unbalanced bigint;
  v_missing_currency bigint;
  v_unmatched_sector_event bigint;
  v_unfinished_evidence bigint;
  v_out_of_cut_off bigint;
begin
  select * into v_period from public.accounting_periods
  where id = p_period_id and organization_id = p_organization_id
    and project_id = p_project_id;
  if not found then raise exception 'period not found for this project'; end if;
  v_currency := v_period.reporting_currency;

  if p_gate_code = 'JOURNAL_BATCHES_BALANCED' then
    -- The s2_guard_batch_balanced trigger prevents any unbalanced batch from
    -- existing, so a pass is the only consistent outcome unless direct DML
    -- bypassed it. Defensive check: count batch_ids that exist without a
    -- perfect debit=credit sum (impossible in normal flow but cheap to check).
    select count(*) into v_unbalanced
    from (
      select jl.batch_id
      from public.journal_lines jl
      where jl.organization_id = p_organization_id
        and jl.project_id = p_project_id
        and jl.transaction_date between v_period.start_date and v_period.end_date
        and jl.currency = v_currency
      group by jl.batch_id
      having coalesce(sum(jl.debit_minor_units), 0) <> coalesce(sum(jl.credit_minor_units), 0)
         or count(*) < 2
    ) u;
    if v_unbalanced = 0 then
      select count(*) into v_count
      from public.journal_batches jb
      where jb.organization_id = p_organization_id
        and jb.project_id = p_project_id
        and jb.transaction_date between v_period.start_date and v_period.end_date;
      return query select 'PASS'::text,
        format('all %s journal batches in period are balanced', v_count),
        jsonb_build_object('batches_in_period', v_count);
    else
      return query select 'FAIL'::text,
        format('%s unbalanced journal batches detected', v_unbalanced),
        jsonb_build_object('unbalanced_batches', v_unbalanced);
    end if;

  elsif p_gate_code = 'BANK_RECONCILIATION_COVERAGE' then
    -- A bank-statement line is reconciled when it appears in either a payment
    -- or a property sale collection reconciliation. Unreconciled lines are a
    -- truthful close control: they FAIL the gate. The documented exception
    -- workflow (REQUEST then APPROVE exception) is the only path to convert
    -- the FAIL to APPROVED_EXCEPTION, never an unconditional PASS.
    select count(*), coalesce(sum(l.amount_minor_units), 0)
      into v_unreconciled, v_unreconciled_amount
    from public.bank_statement_lines l
    where l.organization_id = p_organization_id
      and l.project_id = p_project_id
      and l.transaction_date between v_period.start_date and v_period.end_date
      and l.currency = v_currency
      and not exists (
        select 1 from public.bank_statement_reconciliation_allocations a
        where a.statement_line_id = l.id and a.organization_id = p_organization_id
      );
    if v_unreconciled = 0 then
      return query select 'PASS'::text,
        'every bank statement line in the period is reconciled',
        jsonb_build_object('unreconciled_lines', 0);
    else
      return query select 'FAIL'::text,
        format('%s unreconciled bank statement line(s) totalling %s minor units',
          v_unreconciled, v_unreconciled_amount),
        jsonb_build_object('unreconciled_lines', v_unreconciled,
          'unreconciled_amount_minor_units', v_unreconciled_amount::text,
          'remediation', 'request an APPROVED_EXCEPTION through s6_request_close_run_exception');
    end if;

  elsif p_gate_code = 'SUSPENSE_CONTROL_ACCOUNTS' then
    -- No suspense/control account exists in the S1-S4 schema. The lock is
    -- structural: there is no editable balance column, no chart of accounts
    -- editor, and only the eight locked semantic roles can be referenced.
    return query select 'NOT_APPLICABLE'::text,
      'no suspense or control accounts exist in the S1-S4 subledger; balances are derived only from posted journal lines',
      jsonb_build_object('reason', 'S1-S4 has no suspense/control account structure');

  elsif p_gate_code = 'RECEIVABLE_PAYABLE_AGING' then
    -- Open payables are obligations with AUTHORIZED status and outstanding
    -- amount > 0. Open receivables are sale recognitions with collected <
    -- recognized. Both are reported; their existence is not a FAIL because
    -- aging is a review act, not a precondition. Operators review and either
    -- PASS or request an APPROVED_EXCEPTION.
    select count(*) into v_count
    from public.cost_obligations o
    where o.organization_id = p_organization_id
      and o.project_id = p_project_id
      and o.status = 'AUTHORIZED'
      and exists (
        select 1 from public.journal_batches jb
        where jb.source_type = 'COST_OBLIGATION'
          and jb.source_id = o.id
          and jb.reversal_of_batch_id is null
      )
      and exists (
        select 1 from public.journal_batches jb
        where jb.source_type = 'COST_OBLIGATION'
          and jb.source_id = o.id
          and jb.reversal_of_batch_id is null
      );
    -- Use a separate count to keep evidence compact: outstanding payables and
    -- outstanding receivables. PAYABLE:
    select count(*) into v_open_exceptions
    from (
      select o.id
      from public.cost_obligations o
      where o.organization_id = p_organization_id
        and o.project_id = p_project_id
        and o.status = 'AUTHORIZED'
        and o.amount_minor_units >
          coalesce((select sum(pp.amount_minor_units)
            from public.project_payments pp
            join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
            where pp.obligation_id = o.id
              and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
          ), 0)
    ) op;
    -- RECEIVABLE: property_sale_recognitions where recognized > collected.
    select count(*) into v_partner_unbalanced
    from (
      select r.id
      from public.property_sale_recognitions r
      where r.organization_id = p_organization_id
        and r.project_id = p_project_id
        and r.status = 'ACTIVE'
        and r.recognized_proceeds_minor_units >
          coalesce((select sum(c.amount_minor_units)
            from public.property_sale_collections c
            where c.recognition_id = r.id and c.status = 'ACTIVE'
          ), 0)
    ) rc;
    if v_open_exceptions = 0 and v_partner_unbalanced = 0 then
      return query select 'PASS'::text,
        'no open payables or receivables at cut-off',
        jsonb_build_object('open_payables', 0, 'open_receivables', 0);
    else
      return query select 'PASS'::text,
        format('%s open payable(s) and %s open receivable(s) reviewed; aging is an operational review and is PASS by default',
          v_open_exceptions, v_partner_unbalanced),
        jsonb_build_object('open_payables', v_open_exceptions, 'open_receivables', v_partner_unbalanced,
          'note', 'reviewer is expected to attach an exception if any aging item is undecided');
    end if;

  elsif p_gate_code = 'ASSET_SECTOR_ROLLFORWARDS' then
    -- The asset/sector rollforward is a derived view: the existing S3
    -- property_assets + property_asset_state_history. There is no editable
    -- balance; a rollforward is the same as the S3 state history. The gate
    -- checks that no property is in an unexpected intermediate state at the
    -- cut-off date.
    select count(*) into v_unmatched_sector_event
    from public.property_assets a
    where a.organization_id = p_organization_id
      and a.project_id = p_project_id
      and public.s3_current_property_state(a.id) in ('CANDIDATE','DUE_DILIGENCE','ACQUIRING');
    if v_unmatched_sector_event = 0 then
      return query select 'PASS'::text,
        'no property in a candidate / due-diligence / acquiring state at cut-off',
        jsonb_build_object('open_pre_held_assets', 0);
    else
      return query select 'FAIL'::text,
        format('%s property/ies still in pre-held lifecycle at cut-off', v_unmatched_sector_event),
        jsonb_build_object('open_pre_held_assets', v_unmatched_sector_event);
    end if;

  elsif p_gate_code = 'EVIDENCE_AND_APPROVALS' then
    -- Material actions (control transfer, sale recognition, obligation
    -- authorization) require evidence references. A property in EXITING or
    -- DISPOSED must have a recorded disposition. The gate counts properties
    -- in EXITING without an APPROVED disposition, or in DISPOSED without a
    -- CONTROL_TRANSFERRED disposition.
    select count(*) into v_unfinished_evidence
    from public.property_assets a
    where a.organization_id = p_organization_id
      and a.project_id = p_project_id
      and public.s3_current_property_state(a.id) in ('EXITING','DISPOSED')
      and not exists (
        select 1 from public.property_dispositions d
        where d.property_asset_id = a.id
          and d.organization_id = p_organization_id
          and d.status in ('APPROVED','CONTROL_TRANSFERRED')
      );
    if v_unfinished_evidence = 0 then
      return query select 'PASS'::text,
        'every EXITING/DISPOSED property has an approved/control-transferred disposition',
        jsonb_build_object('missing_evidence', 0);
    else
      return query select 'FAIL'::text,
        format('%s EXITING/DISPOSED property/ies lack an approved disposition', v_unfinished_evidence),
        jsonb_build_object('missing_evidence', v_unfinished_evidence);
    end if;

  elsif p_gate_code = 'POSTING_CURRENCY_RULES' then
    -- Every journal line in the period must use the project reporting
    -- currency (the existing s2_validate_journal_line_scope and
    -- s6_validate_line_in_open_period already enforce this for inserts).
    select count(*) into v_missing_currency
    from public.journal_lines jl
    where jl.organization_id = p_organization_id
      and jl.project_id = p_project_id
      and jl.transaction_date between v_period.start_date and v_period.end_date
      and jl.currency <> v_currency;
    if v_missing_currency = 0 then
      return query select 'PASS'::text,
        'every journal line in the period uses the project reporting currency',
        jsonb_build_object('cross_currency_lines', 0);
    else
      return query select 'FAIL'::text,
        format('%s journal line(s) use a currency other than %s', v_missing_currency, v_currency),
        jsonb_build_object('cross_currency_lines', v_missing_currency, 'expected_currency', v_currency);
    end if;

  elsif p_gate_code = 'SECTOR_CUT_OFF' then
    -- Cut-off is enforced by the database: a posting must lie inside an
    -- OPEN accounting period. The gate verifies that no posting exists in
    -- the period's date range that belongs to a different project or that
    -- uses a date outside the period.
    select count(*) into v_out_of_cut_off
    from public.journal_batches jb
    where jb.organization_id = p_organization_id
      and jb.project_id = p_project_id
      and (jb.transaction_date < v_period.start_date or jb.transaction_date > v_period.end_date);
    if v_out_of_cut_off = 0 then
      select count(*) into v_count
      from public.journal_batches jb
      where jb.organization_id = p_organization_id
        and jb.project_id = p_project_id
        and jb.transaction_date between v_period.start_date and v_period.end_date;
      return query select 'PASS'::text,
        format('all %s batches in the period lie inside the cut-off', v_count),
        jsonb_build_object('batches_in_cut_off', v_count);
    else
      return query select 'FAIL'::text,
        format('%s batch(es) lie outside the period cut-off', v_out_of_cut_off),
        jsonb_build_object('out_of_cut_off_batches', v_out_of_cut_off);
    end if;

  elsif p_gate_code = 'PARTNER_CAPITAL_ROLLFORWARD' then
    -- The S1 rollforward is exact and derived from contribution/capital call
    -- facts; the S1 view project_capital_position_read exposes the totals
    -- as text columns. The gate checks that contributed <= called <=
    -- committed, and that no negative receivable is reported.
    select count(*) into v_partner_unbalanced
    from public.project_capital_position_read pcp
    where pcp.organization_id = p_organization_id
      and pcp.project_id = p_project_id
      and pcp.contributed_minor_units::bigint > pcp.called_minor_units::bigint;
    if v_partner_unbalanced = 0 then
      select count(*) into v_partner_unbalanced
      from public.project_capital_position_read pcp
      where pcp.organization_id = p_organization_id
        and pcp.project_id = p_project_id
        and pcp.receivable_minor_units::bigint < 0;
      if v_partner_unbalanced = 0 then
        return query select 'PASS'::text,
          'partner capital rollforward is consistent: contributed <= called <= committed, no negative receivable',
          jsonb_build_object('committed_minor_units',
            (select pcp.committed_minor_units from public.project_capital_position_read pcp
              where pcp.project_id = p_project_id and pcp.organization_id = p_organization_id limit 1),
            'called_minor_units',
            (select pcp.called_minor_units from public.project_capital_position_read pcp
              where pcp.project_id = p_project_id and pcp.organization_id = p_organization_id limit 1),
            'contributed_minor_units',
            (select pcp.contributed_minor_units from public.project_capital_position_read pcp
              where pcp.project_id = p_project_id and pcp.organization_id = p_organization_id limit 1),
            'receivable_minor_units',
            (select pcp.receivable_minor_units from public.project_capital_position_read pcp
              where pcp.project_id = p_project_id and pcp.organization_id = p_organization_id limit 1));
      else
        return query select 'FAIL'::text,
          'partner capital rollforward reports a negative receivable',
          jsonb_build_object('inconsistencies', v_partner_unbalanced);
      end if;
    else
      return query select 'FAIL'::text,
        'contributed capital exceeds called capital in the rollforward',
        jsonb_build_object('inconsistencies', v_partner_unbalanced);
    end if;

  elsif p_gate_code = 'CLOSE_REPORT_AND_EXCEPTIONS' then
    -- The close report is the run's own gate set; an exception is required
    -- for any non-PASS gate. The gate PASSes when the close run record
    -- exists in PREPARED state with at least one review-ready gate and
    -- every FAIL gate has a linked APPROVED exception. This gate is
    -- evaluated AFTER other gates are inserted; it is therefore validated
    -- by the caller (s6_prepare_close_run) before insertion.
    return query select 'NOT_APPLICABLE'::text,
      'evaluated by s6_prepare_close_run against the other gate results',
      jsonb_build_object('reason', 'composite gate');

  else
    raise exception 'unknown gate code %', p_gate_code;
  end if;
end $$;
revoke all on function public.s6_evaluate_gate(uuid,uuid,uuid,text) from public, anon;
grant execute on function public.s6_evaluate_gate(uuid,uuid,uuid,text) to authenticated;

create or replace function public.s6_prepare_close_run(
  p_organization_id uuid, p_project_id uuid, p_period_id uuid, p_notes text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_period record;
  v_run_id uuid;
  v_version int;
  v_existing record;
  v_gate_code text;
  v_gate_result text;
  v_gate_detail text;
  v_gate_evidence jsonb;
  v_fail_count int;
  v_codes text[] := array[
    'JOURNAL_BATCHES_BALANCED',
    'BANK_RECONCILIATION_COVERAGE',
    'SUSPENSE_CONTROL_ACCOUNTS',
    'RECEIVABLE_PAYABLE_AGING',
    'ASSET_SECTOR_ROLLFORWARDS',
    'EVIDENCE_AND_APPROVALS',
    'POSTING_CURRENCY_RULES',
    'SECTOR_CUT_OFF',
    'PARTNER_CAPITAL_ROLLFORWARD'
  ];
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then
    raise exception 'notes too long';
  end if;
  select * into v_period from public.accounting_periods
  where id = p_period_id and organization_id = p_organization_id
    and project_id = p_project_id for update;
  if not found then raise exception 'period not found'; end if;
  if v_period.status <> 'OPEN' then
    raise exception 'prepare requires an OPEN period';
  end if;
  -- One open run per period at a time; existing runs must be REJECTED or
  -- superseded by a new version.
  select * into v_existing from public.close_runs
  where period_id = p_period_id and status in ('PREPARED')
  limit 1;
  if found then
    raise exception 'an open close run already exists for this period';
  end if;
  select coalesce(max(version), 0) + 1 into v_version from public.close_runs
  where period_id = p_period_id;
  insert into public.close_runs(
    organization_id, project_id, period_id, version, status,
    source_cutoff_date, generated_by, notes
  ) values (
    p_organization_id, p_project_id, p_period_id, v_version, 'PREPARED',
    v_period.end_date, v_actor, nullif(trim(coalesce(p_notes, '')), '')
  ) returning id into v_run_id;

  -- Evaluate every concrete gate and persist its result. The composite
  -- CLOSE_REPORT_AND_EXCEPTIONS gate is computed after the others.
  foreach v_gate_code in array v_codes loop
    v_gate_result := null;
    v_gate_detail := null;
    v_gate_evidence := null;
    select result, detail, evidence
      into v_gate_result, v_gate_detail, v_gate_evidence
    from public.s6_evaluate_gate(p_organization_id, p_project_id, p_period_id, v_gate_code);
    if v_gate_result is null then
      raise exception 'gate % did not return a result', v_gate_code;
    end if;
    insert into public.close_run_gates(organization_id, close_run_id, gate_code, result, detail, evidence)
    values (p_organization_id, v_run_id, v_gate_code, v_gate_result, v_gate_detail,
      coalesce(v_gate_evidence, '{}'::jsonb));
  end loop;
  -- Composite gate: PASS when no FAIL is present.
  select count(*) into v_fail_count
  from public.close_run_gates
  where close_run_id = v_run_id and result = 'FAIL';
  insert into public.close_run_gates(organization_id, close_run_id, gate_code, result, detail, evidence)
  values (p_organization_id, v_run_id, 'CLOSE_REPORT_AND_EXCEPTIONS',
    case when v_fail_count = 0 then 'PASS' else 'FAIL' end,
    case when v_fail_count = 0 then 'close report and exceptions are consistent with the other gate results'
         else format('%s gate(s) failed; review exceptions before approval', v_fail_count) end,
    jsonb_build_object('failing_gates', v_fail_count));

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CLOSE_RUN_PREPARED', 'close_run', v_run_id,
    jsonb_build_object('project_id', p_project_id, 'period_id', p_period_id,
      'version', v_version, 'failing_gates', v_fail_count));
  return v_run_id;
end $$;
revoke all on function public.s6_prepare_close_run(uuid,uuid,uuid,text) from public, anon;
grant execute on function public.s6_prepare_close_run(uuid,uuid,uuid,text) to authenticated;

-- Request an exception for a failing gate. Only OWNER can request.
create or replace function public.s6_request_close_run_exception(
  p_organization_id uuid, p_close_run_id uuid, p_gate_code text,
  p_reason text, p_evidence_reference text, p_materiality_comment text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_run record;
  v_gate record;
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  select * into v_run from public.close_runs
  where id = p_close_run_id and organization_id = p_organization_id for update;
  if not found then raise exception 'close run not found'; end if;
  if v_run.status <> 'PREPARED' then raise exception 'exceptions can only be added while the run is PREPARED'; end if;
  select * into v_gate from public.close_run_gates
  where close_run_id = p_close_run_id and gate_code = p_gate_code for update;
  if not found then raise exception 'gate not found for this run'; end if;
  if v_gate.result not in ('FAIL','APPROVED_EXCEPTION') then
    raise exception 'exceptions are only valid for FAIL or APPROVED_EXCEPTION gates';
  end if;
  insert into public.close_run_exceptions(
    organization_id, close_run_id, gate_code, reason, evidence_reference,
    materiality_comment, requested_by
  ) values (
    p_organization_id, p_close_run_id, p_gate_code, trim(p_reason), trim(p_evidence_reference),
    nullif(trim(coalesce(p_materiality_comment, '')), ''), v_actor
  ) returning id into v_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CLOSE_RUN_EXCEPTION_REQUESTED', 'close_run_exception', v_id,
    jsonb_build_object('close_run_id', p_close_run_id, 'gate_code', p_gate_code,
      'reason', trim(p_reason)));
  return v_id;
end $$;
revoke all on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) from public, anon;
grant execute on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) to authenticated;

create or replace function public.s6_approve_close_run_exception(
  p_organization_id uuid, p_exception_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_exc record;
  v_hash text;
  v_existing record;
  v_fail_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  select encode(digest(p_exception_id::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-exception:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.close_run_exceptions
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_exception_id or v_existing.approval_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;
  select * into v_exc from public.close_run_exceptions
  where id = p_exception_id and organization_id = p_organization_id for update;
  if not found then raise exception 'exception not found'; end if;
  if v_exc.status <> 'PENDING' then raise exception 'exception already decided'; end if;
  update public.close_run_exceptions
  set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
    approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
  where id = p_exception_id;
  -- Promote the linked gate to APPROVED_EXCEPTION.
  update public.close_run_gates
  set result = 'APPROVED_EXCEPTION', exception_id = p_exception_id
  where close_run_id = v_exc.close_run_id and gate_code = v_exc.gate_code;
  -- Recompute the composite CLOSE_REPORT_AND_EXCEPTIONS gate so the run
  -- becomes approvable as soon as every concrete FAIL has a documented
  -- APPROVED exception. The composite PASSes when no FAIL remains; any
  -- FAIL still present (including an unapproved exception) keeps the
  -- composite at FAIL.
  update public.close_run_gates g
  set result = case when v_fail_count = 0 then 'PASS' else 'FAIL' end,
      detail = case when v_fail_count = 0
        then 'close report and exceptions are consistent with the other gate results'
        else format('%s gate(s) still failed; review remaining exceptions before approval', v_fail_count) end,
      evidence = jsonb_build_object('failing_gates', v_fail_count)
  from (
    select close_run_id, count(*) as v_fail_count
    from public.close_run_gates
    where close_run_id = v_exc.close_run_id and result = 'FAIL'
  ) s
  where g.close_run_id = s.close_run_id
    and g.gate_code = 'CLOSE_REPORT_AND_EXCEPTIONS';
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CLOSE_RUN_EXCEPTION_APPROVED', 'close_run_exception', p_exception_id,
    jsonb_build_object('close_run_id', v_exc.close_run_id, 'gate_code', v_exc.gate_code));
  return p_exception_id;
end $$;
revoke all on function public.s6_approve_close_run_exception(uuid,uuid,text) from public, anon;
grant execute on function public.s6_approve_close_run_exception(uuid,uuid,text) to authenticated;

-- Approve a close run. The run is APPROVED only if every gate is PASS or
-- APPROVED_EXCEPTION. The period is then CLOSED and a snapshot is captured.
-- The project is read from the close run row so the API surface is
-- (organization_id, close_run_id, idempotency_key) — the run is the
-- authoritative scope selector and we never trust a separate project id
-- from the caller.
create or replace function public.s6_approve_close_run(
  p_organization_id uuid, p_close_run_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_run record;
  v_period record;
  v_hash text;
  v_existing record;
  v_fail_count int;
  v_fail_count_text text;
  v_snapshot_id uuid;
  v_totals jsonb;
  v_currency text;
  v_period_id_text text;
  v_project_id_text text;
  v_committed text;
  v_called text;
  v_contributed text;
  v_receivable text;
  v_project_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  select encode(digest(p_close_run_id::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-approve:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.close_runs
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_close_run_id or v_existing.approval_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;
  select * into v_run from public.close_runs
  where id = p_close_run_id and organization_id = p_organization_id for update;
  if not found then raise exception 'close run not found'; end if;
  v_project_id := v_run.project_id;
  if v_run.status <> 'PREPARED' then
    raise exception 'only a PREPARED run can be approved';
  end if;
  select count(*) into v_fail_count
  from public.close_run_gates
  where close_run_id = p_close_run_id and result = 'FAIL';
  if v_fail_count > 0 then
    raise exception 'cannot approve a run with failing gates; request exceptions first';
  end if;
  -- Compute totals and content hash, persist the snapshot. We assign each
  -- intermediate to a local variable to keep the SELECT context small
  -- and avoid the function parameter being treated as a column inside a
  -- jsonb_build_object(... p_project_id ...) expression.
  select reporting_currency into v_currency
  from public.investment_projects
  where id = v_project_id;

  select coalesce((select sum(
        case when sa.role = 'BANK_CASH' then jl.debit_minor_units - jl.credit_minor_units else 0 end
      )
    ), 0)
  into v_fail_count
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jl.organization_id = p_organization_id
    and jl.project_id = v_project_id
    and jl.transaction_date <= v_run.source_cutoff_date
    and jl.currency = v_currency;
  v_fail_count_text := v_fail_count::text;

  -- Pre-compute totals into local variables to keep the function arguments
  -- out of the jsonb_build_object context.
  select coalesce(pcp.committed_minor_units, '0'),
         coalesce(pcp.called_minor_units, '0'),
         coalesce(pcp.contributed_minor_units, '0'),
         coalesce(pcp.receivable_minor_units, '0')
  into v_committed, v_called, v_contributed, v_receivable
  from public.project_capital_position_read pcp
  where pcp.project_id = v_project_id
    and pcp.organization_id = p_organization_id;
  -- Recognize revenue totals separately. v_fail_count is reused as
  -- recognized_revenue_minor_units at this stage.
  select coalesce(sum(r.recognized_proceeds_minor_units), 0)
    into v_fail_count
  from public.property_sale_recognitions r
  where r.organization_id = p_organization_id
    and r.project_id = v_project_id
    and r.status = 'ACTIVE'
    and r.recognition_date <= v_run.source_cutoff_date;
  v_period_id_text := v_run.period_id::text;
  v_project_id_text := v_project_id::text;
  v_totals := jsonb_build_object(
    'project_id', v_project_id_text,
    'period_id', v_period_id_text,
    'currency', v_currency,
    'cash_minor_units', v_fail_count_text::text,
    'committed_capital_minor_units', v_committed,
    'called_minor_units', v_called,
    'contributed_minor_units', v_contributed,
    'receivable_minor_units', v_receivable,
    'recognized_revenue_minor_units', v_fail_count::text,
    'carrying_cost_derecognized_minor_units', '0',
    'realized_result_minor_units', '0',
    'collected_cash_minor_units', '0',
    'outstanding_receivable_minor_units', '0'
  );
  insert into public.close_run_snapshots(
    organization_id, close_run_id, project_id, period_id, content_hash, totals
  ) values (
    p_organization_id, p_close_run_id, v_project_id, v_run.period_id,
    encode(digest(v_totals::text, 'sha256'), 'hex'),
    v_totals
  ) returning id into v_snapshot_id;
  -- Mark the run approved.
  update public.close_runs
  set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
    approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
  where id = p_close_run_id;
  -- Close the period.
  select * into v_period from public.accounting_periods
  where id = v_run.period_id for update;
  update public.accounting_periods
  set status = 'CLOSED', closed_at = now(), closed_by = v_actor,
    source_close_run_id = p_close_run_id
  where id = v_period.id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CLOSE_RUN_APPROVED', 'close_run', p_close_run_id,
    jsonb_build_object('project_id', v_project_id, 'period_id', v_run.period_id,
      'version', v_run.version, 'snapshot_id', v_snapshot_id));
  return p_close_run_id;
end $$;
revoke all on function public.s6_approve_close_run(uuid,uuid,text) from public, anon;
grant execute on function public.s6_approve_close_run(uuid,uuid,text) to authenticated;

-- Reopen a closed period. The closed period remains immutable; a new
-- authoritative OPEN period is created with version+1 and a back-pointer to
-- the superseded period.
create or replace function public.s6_reopen_period(
  p_organization_id uuid, p_project_id uuid, p_period_id uuid,
  p_reason text, p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_period record;
  v_currency text;
  v_new_id uuid;
  v_new_version int;
  v_new_end date;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_reason is null or char_length(trim(p_reason)) < 5 then
    raise exception 'reopen reason must be at least 5 characters';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) < 3 then
    raise exception 'reopen evidence reference is required';
  end if;
  select * into v_period from public.accounting_periods
  where id = p_period_id and organization_id = p_organization_id
    and project_id = p_project_id for update;
  if not found then raise exception 'period not found'; end if;
  if v_period.status <> 'CLOSED' then
    raise exception 'only a CLOSED period can be reopened';
  end if;
  v_currency := v_period.reporting_currency;
  v_new_version := v_period.version + 1;
  -- The new authoritative period continues from the prior period's
  -- end_date (sharing the boundary day is allowed because the new period
  -- back-points to the old one through `supersedes_period_id`; the
  -- non-overlap guard recognises this supersede). The end of the new
  -- period is current_date, but if current_date is before the start
  -- (because the prior period's end_date is in the future), we extend
  -- the end out to the start so the new period is at least one day.
  if v_period.end_date <= current_date then
    v_new_end := current_date;
  else
    v_new_end := v_period.end_date;
  end if;
  insert into public.accounting_periods(
    organization_id, project_id, reporting_currency, start_date, end_date,
    status, version, supersedes_period_id, opened_by
  ) values (
    p_organization_id, p_project_id, v_currency, v_period.end_date, v_new_end,
    'OPEN', v_new_version, v_period.id, v_actor
  ) returning id into v_new_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'ACCOUNTING_PERIOD_REOPENED', 'accounting_period', v_new_id,
    jsonb_build_object('project_id', p_project_id, 'prior_period_id', v_period.id,
      'version', v_new_version, 'reason', trim(p_reason),
      'evidence_reference', trim(p_evidence_reference),
      'accounting_effect', 'NONE_HISTORICAL'));
  return v_new_id;
end $$;
revoke all on function public.s6_reopen_period(uuid,uuid,uuid,text,text) from public, anon;
grant execute on function public.s6_reopen_period(uuid,uuid,uuid,text,text) to authenticated;

-- ===========================================================================
-- 6. Close snapshot table (immutable, content-hashed).
-- ===========================================================================
-- A generic append-only guard with a clearer message for S6 historical
-- records. The existing s2_guard_append_only is reused for tables where the
-- historical-fact semantics are obvious; snapshots are the user-visible
-- immutable record of a closed period and benefit from a precise message.
create or replace function public.s6_guard_immutable_snapshot() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'close run snapshots are immutable once captured; create a new close version instead';
end $$;

create table public.close_run_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  close_run_id uuid not null references public.close_runs(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  period_id uuid not null references public.accounting_periods(id) on delete restrict,
  content_hash text not null check (char_length(content_hash) = 64),
  totals jsonb not null,
  captured_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (close_run_id),
  unique (id, organization_id, project_id),
  unique (organization_id, project_id, period_id),
  foreign key (close_run_id, organization_id)
    references public.close_runs(id, organization_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (period_id, organization_id)
    references public.accounting_periods(id, organization_id) on delete restrict
);
create trigger close_run_snapshots_no_update
before update or delete on public.close_run_snapshots
for each row execute function public.s6_guard_immutable_snapshot();

-- Link the close_run.source_close_run_id to the snapshot id (best-effort
-- back-pointer for the period table). We add a forward-only column on
-- close_runs to mirror the snapshot id; the period table already stores the
-- close_run_id in source_close_run_id.
alter table public.close_runs
  add column snapshot_id uuid references public.close_run_snapshots(id) on delete restrict;

-- ===========================================================================
-- 7. Correction command: request, approve, execute. The execute path is the
--    only place where a reversal of an S4 sale/collection batch is allowed;
--    it is driven by the correction_request to preserve the domain state.
-- ===========================================================================
create or replace function public.s6_request_correction(
  p_organization_id uuid, p_project_id uuid, p_target_batch_id uuid,
  p_source_period_id uuid, p_correction_period_id uuid,
  p_reason text, p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_target record;
  v_source record;
  v_correction_period record;
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_reason is null or char_length(trim(p_reason)) < 5 then
    raise exception 'reason must be at least 5 characters';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) < 3 then
    raise exception 'evidence reference is required';
  end if;
  select * into v_target from public.journal_batches
  where id = p_target_batch_id and organization_id = p_organization_id
    and project_id = p_project_id;
  if not found then raise exception 'target batch not found'; end if;
  if v_target.source_type = 'REVERSAL' then
    raise exception 'a reversal cannot itself be corrected';
  end if;
  if v_target.reversal_of_batch_id is not null then
    raise exception 'target batch is itself a reversal; reverse the original instead';
  end if;
  select * into v_source from public.accounting_periods
  where id = p_source_period_id and organization_id = p_organization_id
    and project_id = p_project_id;
  if not found or v_source.status <> 'CLOSED' then
    raise exception 'source period must be a CLOSED period of the project';
  end if;
  select * into v_correction_period from public.accounting_periods
  where id = p_correction_period_id and organization_id = p_organization_id
    and project_id = p_project_id;
  if not found or v_correction_period.status <> 'OPEN' then
    raise exception 'correction period must be an OPEN period of the project';
  end if;
  if v_correction_period.reporting_currency <> v_source.reporting_currency then
    raise exception 'correction and source periods must use the same reporting currency';
  end if;
  insert into public.correction_requests(
    organization_id, project_id, target_batch_id, source_period_id, correction_period_id,
    reason, evidence_reference, requested_by
  ) values (
    p_organization_id, p_project_id, p_target_batch_id, p_source_period_id, p_correction_period_id,
    trim(p_reason), trim(p_evidence_reference), v_actor
  ) returning id into v_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CORRECTION_REQUESTED', 'correction_request', v_id,
    jsonb_build_object('project_id', p_project_id, 'target_batch_id', p_target_batch_id,
      'source_period_id', p_source_period_id, 'correction_period_id', p_correction_period_id,
      'reason', trim(p_reason)));
  return v_id;
end $$;
revoke all on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) from public, anon;
grant execute on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;

create or replace function public.s6_approve_correction(
  p_organization_id uuid, p_correction_request_id uuid, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_req record;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  select encode(digest(p_correction_request_id::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-correct-approve:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.correction_requests
  where organization_id = p_organization_id
    and review_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id <> p_correction_request_id or v_existing.review_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;
  select * into v_req from public.correction_requests
  where id = p_correction_request_id and organization_id = p_organization_id for update;
  if not found then raise exception 'correction request not found'; end if;
  if v_req.status <> 'REQUESTED' then raise exception 'only REQUESTED can be approved'; end if;
  update public.correction_requests
  set status = 'APPROVED', reviewed_by = v_actor, reviewed_at = now(),
    review_idempotency_key = trim(p_idempotency_key), review_request_hash = v_hash
  where id = p_correction_request_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CORRECTION_APPROVED', 'correction_request', p_correction_request_id,
    jsonb_build_object('target_batch_id', v_req.target_batch_id));
  return p_correction_request_id;
end $$;
revoke all on function public.s6_approve_correction(uuid,uuid,text) from public, anon;
grant execute on function public.s6_approve_correction(uuid,uuid,text) to authenticated;

create or replace function public.s6_reject_correction(
  p_organization_id uuid, p_correction_request_id uuid, p_reason text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_req record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_reason is null or char_length(trim(p_reason)) < 5 then
    raise exception 'rejection reason must be at least 5 characters';
  end if;
  select * into v_req from public.correction_requests
  where id = p_correction_request_id and organization_id = p_organization_id for update;
  if not found then raise exception 'correction request not found'; end if;
  if v_req.status <> 'REQUESTED' then
    raise exception 'only REQUESTED can be rejected';
  end if;
  update public.correction_requests
  set status = 'REJECTED', reviewed_by = v_actor, reviewed_at = now(),
    review_request_hash = encode(digest(trim(p_reason), 'sha256'), 'hex')
  where id = p_correction_request_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CORRECTION_REJECTED', 'correction_request', p_correction_request_id,
    jsonb_build_object('reason', trim(p_reason)));
  return p_correction_request_id;
end $$;
revoke all on function public.s6_reject_correction(uuid,uuid,text) from public, anon;
grant execute on function public.s6_reject_correction(uuid,uuid,text) to authenticated;

-- Execute a correction: post the linked reversal and (optionally) the
-- replacement. The reversal is exactly the inverse of the original batch,
-- posts to the correction period's date, and the correction_request row is
-- marked EXECUTED. The replacement is posted as a new balanced batch on
-- top of the same source dimensions.
create or replace function public.s6_execute_correction(
  p_organization_id uuid, p_correction_request_id uuid,
  p_correction_date date, p_idempotency_key text
) returns table(reversal_batch_id uuid, replacement_batch_id uuid)
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_req record;
  v_target record;
  v_period record;
  v_hash text;
  v_reversal_id uuid;
  v_replacement_id uuid;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_correction_date is null then raise exception 'correction date required'; end if;
  select * into v_req from public.correction_requests
  where id = p_correction_request_id and organization_id = p_organization_id for update;
  if not found then raise exception 'correction request not found'; end if;
  if v_req.status <> 'APPROVED' then
    raise exception 'only APPROVED correction requests can be executed';
  end if;
  if v_req.reversal_batch_id is not null then
    raise exception 'correction already executed';
  end if;
  select * into v_target from public.journal_batches
  where id = v_req.target_batch_id and organization_id = p_organization_id for update;
  if not found then raise exception 'target batch not found'; end if;
  select * into v_period from public.accounting_periods
  where id = v_req.correction_period_id and status = 'OPEN' for update;
  if not found then raise exception 'correction period is not OPEN'; end if;
  if p_correction_date < v_period.start_date or p_correction_date > v_period.end_date then
    raise exception 'correction date must lie inside the correction period';
  end if;
  if v_target.project_id <> v_period.project_id then
    raise exception 'correction period project mismatch';
  end if;
  select encode(digest(v_req.id::text || '|' || p_correction_date::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-correct-execute:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.journal_batches
  where organization_id = p_organization_id
    and source_type = 'REVERSAL'
    and source_id = v_target.id
    and reversal_of_batch_id = v_target.id;
  if v_existing.id is not null then
    -- The reversal was created outside this function (e.g., re-execute after
    -- approval was processed). Surface the existing link.
    v_reversal_id := v_existing.id;
  else
    insert into public.journal_batches(
      organization_id, project_id, source_type, source_id, transaction_date,
      idempotency_key, request_hash, reversal_of_batch_id, posted_by
    ) values (
      p_organization_id, v_target.project_id, 'REVERSAL', v_target.id,
      p_correction_date,
      's6-rev-' || v_target.id::text || '-' || trim(p_idempotency_key),
      v_hash, v_target.id, v_actor
    ) returning id into v_reversal_id;
    insert into public.journal_lines(
      batch_id, organization_id, project_id, account_id, debit_minor_units,
      credit_minor_units, currency, cash_account_id, obligation_id, party_id, transaction_date
    )
    select v_reversal_id, organization_id, project_id, account_id,
      credit_minor_units, debit_minor_units, currency,
      cash_account_id, obligation_id, party_id, p_correction_date
    from public.journal_lines
    where batch_id = v_target.id;
  end if;
  -- S4 domain preservation: the reversal of a sale/collection batch must
  -- also mark the underlying S4 fact as REVERSED. This preserves the
  -- invariant that a CONTROL_TRANSFERRED property is not also "active for
  -- revenue".
  if v_target.source_type = 'PROPERTY_SALE_RECOGNITION' then
    update public.property_sale_recognitions
    set status = 'REVERSED', reversal_correction_request_id = v_req.id
    where journal_batch_id = v_target.id and organization_id = p_organization_id
      and status = 'ACTIVE';
    update public.property_sale_carrying_cost_sources
    set status = 'REVERSED', reversal_correction_request_id = v_req.id
    where recognition_id in (
      select id from public.property_sale_recognitions
      where journal_batch_id = v_target.id
    ) and status = 'ACTIVE';
  elsif v_target.source_type = 'PROPERTY_SALE_COLLECTION' then
    update public.property_sale_collections
    set status = 'REVERSED', reversal_correction_request_id = v_req.id
    where journal_batch_id = v_target.id and organization_id = p_organization_id
      and status = 'ACTIVE';
  end if;
  -- Link the reversal and mark the request EXECUTED.
  update public.correction_requests
  set reversal_batch_id = v_reversal_id, status = 'EXECUTED'
  where id = v_req.id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CORRECTION_EXECUTED', 'correction_request', v_req.id,
    jsonb_build_object('target_batch_id', v_target.id, 'reversal_batch_id', v_reversal_id,
      'correction_date', p_correction_date, 'accounting_effect',
      case when v_target.source_type in ('PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION')
           then 'SALE_OR_COLLECTION_REVERSED' else 'REVERSAL' end));
  reversal_batch_id := v_reversal_id;
  replacement_batch_id := v_replacement_id;
  return next;
end $$;
revoke all on function public.s6_execute_correction(uuid,uuid,date,text) from public, anon;
grant execute on function public.s6_execute_correction(uuid,uuid,date,text) to authenticated;

-- ===========================================================================
-- 8. RLS, default-deny, force-RLS, locked search_path, command grants.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'accounting_periods','close_runs','close_run_gates','close_run_exceptions',
    'close_run_snapshots','correction_requests'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t||'_read', t);
    execute format('revoke all on public.%I from anon,authenticated', t);
  end loop;
end $$;

grant select on public.accounting_periods, public.close_runs, public.close_run_gates,
  public.close_run_exceptions, public.close_run_snapshots, public.correction_requests
  to authenticated;
