-- F4 — Project Budget Control: versioned budget + revision workflow +
-- ceiling enforcement at obligation authorization + consumption/forecast
-- read models.
--
-- Canonical rules honored here:
--   * Budget is an additive control layer over the existing Finance Core.
--     No second ledger: budget lines are ceilings, consumption is derived
--     from authoritative posted facts (authorized obligations, journal
--     postings, procurement commitments).
--   * Budget categories are exactly the canonical cost treatments
--     EXPENSE / CAPITALIZABLE_WIP. No invented account taxonomy.
--   * Budget period ranges never overlap for APPROVED budgets of one
--     project; a revision supersedes the previous version and starts a new
--     version of the same range.
--   * The ceiling is enforced at obligation authorization (per the P1
--     canonical audit decision). An approved BUDGET_CEILING exception
--     raises the effective ceiling by its explicit amount.
--   * Purchase-order open commitments are shown but never silently mapped
--     to a cost treatment the order did not declare.
--   * All money is bigint minor units; the client sees text through
--     *_read views. All commands are idempotent and advisory-lock safe.
--
-- NOTE: `authorize_cost_obligation` below needs the approved-exception
-- relief from the F5 exception registry. PL/pgSQL binds static SQL at
-- creation time, so that one lookup uses EXECUTE (deferred resolution)
-- and the exception table itself is created by the F5 migration that
-- immediately follows this file. Migrations always apply in order, and
-- the consumption read model that joins the F5 registry lives in the F5
-- migration for the same reason.

-- ===========================================================================
-- 1. Budgets
-- ===========================================================================
create table public.project_budgets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  budget_type text not null check (budget_type in ('ORIGINAL','REVISED')),
  version integer not null check (version >= 1),
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','SUPERSEDED')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text not null check (char_length(trim(description)) between 3 and 1000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  superseded_by_budget_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  unique (organization_id, project_id, period_start, period_end, version),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint project_budgets_period_check check (period_end >= period_start),
  constraint project_budgets_state_check check (
    (status = 'DRAFT' and approved_by is null and approved_at is null)
    or (status = 'APPROVED' and approved_by is not null and approved_at is not null
        and approved_by <> prepared_by)
    or (status = 'SUPERSEDED' and approved_by is not null and approved_at is not null
        and superseded_by_budget_id is not null)
  )
);
create index project_budgets_project_status_idx
  on public.project_budgets(project_id, status, period_start);

-- Approved budgets of one project must not overlap in time; superseded
-- versions keep their historical range.
create or replace function public.f4_guard_budget_no_overlap() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.status = 'APPROVED' and exists (
    select 1 from public.project_budgets b
    where b.organization_id = new.organization_id
      and b.project_id = new.project_id
      and b.status = 'APPROVED'
      and b.id is distinct from new.id
      and b.period_start <= new.period_end
      and b.period_end >= new.period_start
  ) then
    raise exception 'approved budget periods must not overlap for the same project';
  end if;
  return new;
end $$;
drop trigger if exists project_budgets_no_overlap on public.project_budgets;
create trigger project_budgets_no_overlap
before insert or update of status, period_start, period_end on public.project_budgets
for each row execute function public.f4_guard_budget_no_overlap();

-- Approved and superseded budgets are immutable except for the approved ->
-- superseded transition performed by the supersede command.
create or replace function public.f4_guard_budget_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'DRAFT' then
      raise exception 'only a draft budget can be deleted';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  -- UPDATE
  if old.status <> 'DRAFT' then
    if old.status = 'APPROVED' and new.status = 'SUPERSEDED'
       and new.superseded_by_budget_id is not null
       and new.id = old.id
       and new.organization_id = old.organization_id
       and new.project_id = old.project_id
       and new.period_start = old.period_start
       and new.period_end = old.period_end
       and new.budget_type = old.budget_type
       and new.version = old.version
       and new.currency = old.currency
       and new.description = old.description
       and new.prepared_by = old.prepared_by
       and new.approved_by = old.approved_by then
      return new;
    end if;
    raise exception 'an approved budget is immutable';
  end if;
  return new;
end $$;
drop trigger if exists project_budgets_immutable on public.project_budgets;
create trigger project_budgets_immutable
before update or delete on public.project_budgets
for each row execute function public.f4_guard_budget_immutable();

-- ===========================================================================
-- 2. Budget lines (ceiling per canonical cost treatment)
-- ===========================================================================
create table public.project_budget_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  budget_id uuid not null,
  cost_treatment text not null check (cost_treatment in ('EXPENSE','CAPITALIZABLE_WIP')),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 1000),
  unique (id, organization_id),
  unique (organization_id, budget_id, cost_treatment),
  foreign key (budget_id, organization_id)
    references public.project_budgets(id, organization_id) on delete cascade
);
create index project_budget_lines_budget_idx on public.project_budget_lines(budget_id);

-- Lines are editable only while their budget is a draft.
create or replace function public.f4_guard_budget_lines_draft_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_status text;
begin
  if tg_op = 'DELETE' then
    select status into v_status from public.project_budgets
    where id = old.budget_id;
    if v_status is null then
      -- Parent draft budget deletion cascade: the only allowed delete.
      return old;
    end if;
    if v_status <> 'DRAFT' then
      raise exception 'budget lines cannot be removed from an approved budget';
    end if;
    return old;
  end if;
  select status into v_status from public.project_budgets
  where id = new.budget_id;
  if v_status is null then raise exception 'budget not found'; end if;
  if v_status <> 'DRAFT' then
    raise exception 'budget lines can only change while the budget is a draft';
  end if;
  return new;
end $$;
drop trigger if exists project_budget_lines_draft_only on public.project_budget_lines;
create trigger project_budget_lines_draft_only
before insert or update or delete on public.project_budget_lines
for each row execute function public.f4_guard_budget_lines_draft_only();

-- ===========================================================================
-- 3. Commands
-- ===========================================================================

-- 3.1 Create a draft budget with explicit lines (any active member).
create or replace function public.f4_create_project_budget(
  p_organization_id uuid,
  p_project_id uuid,
  p_period_start date,
  p_period_end date,
  p_budget_type text,
  p_currency text,
  p_description text,
  p_evidence_reference text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_budget uuid; v_version integer;
  v_project_currency text;
  v_line record; v_line_count integer := 0;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'invalid budget period';
  end if;
  if p_budget_type not in ('ORIGINAL','REVISED') then
    raise exception 'budget type must be ORIGINAL or REVISED';
  end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 1000 then
    raise exception 'budget description must be 3-1000 characters';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one budget line is required';
  end if;

  select reporting_currency into v_project_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid currency';
  end if;
  if p_currency <> v_project_currency then
    raise exception 'budget currency must match the project reporting currency';
  end if;

  select encode(digest(p_project_id::text || '|' || p_period_start::text || '|'
    || p_period_end::text || '|' || p_budget_type || '|' || p_currency || '|'
    || trim(p_description) || '|' || coalesce(p_lines::text, ''), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f4-budget:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.project_budgets
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from public.project_budgets
  where organization_id = p_organization_id and project_id = p_project_id
    and period_start = p_period_start and period_end = p_period_end;

  insert into public.project_budgets(
    organization_id, project_id, period_start, period_end, budget_type,
    version, currency, description, evidence_reference, prepared_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_period_start, p_period_end,
    p_budget_type, v_version, p_currency, trim(p_description),
    nullif(trim(p_evidence_reference), ''), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_budget;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if v_line.value->>'cost_treatment' not in ('EXPENSE','CAPITALIZABLE_WIP') then
      raise exception 'budget line cost treatment must be EXPENSE or CAPITALIZABLE_WIP';
    end if;
    if (v_line.value->>'amount_minor_units') is null
       or (v_line.value->>'amount_minor_units')::bigint <= 0 then
      raise exception 'budget line amount must be a positive integer';
    end if;
    insert into public.project_budget_lines(
      organization_id, budget_id, cost_treatment, amount_minor_units, notes
    ) values (
      p_organization_id, v_budget, v_line.value->>'cost_treatment',
      (v_line.value->>'amount_minor_units')::bigint,
      nullif(trim(coalesce(v_line.value->>'notes', '')), '')
    );
    v_line_count := v_line_count + 1;
  end loop;
  if v_line_count = 0 then
    raise exception 'at least one budget line is required';
  end if;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_DRAFTED', 'project_budget', v_budget,
          jsonb_build_object('project_id', p_project_id, 'period_start', p_period_start,
                             'period_end', p_period_end, 'budget_type', p_budget_type,
                             'version', v_version));
  return v_budget;
end $$;

-- 3.2 Approve a draft budget (OWNER, maker/checker).
create or replace function public.f4_approve_project_budget(
  p_organization_id uuid,
  p_budget_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_budget public.project_budgets%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  v_hash := encode(digest(p_budget_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f4-budget-approve:' || trim(p_idempotency_key), 0));
  select * into v_budget from public.project_budgets
  where id = p_budget_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'budget not found'; end if;
  if v_budget.status = 'APPROVED' then return v_budget.id; end if;
  if v_budget.status <> 'DRAFT' then
    raise exception 'only a draft budget can be approved';
  end if;
  if v_budget.prepared_by = v_actor then
    raise exception 'maker/checker: the budget preparer cannot approve it';
  end if;

  update public.project_budgets
     set status = 'APPROVED', approved_by = v_actor, approved_at = now()
   where id = p_budget_id and organization_id = p_organization_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_APPROVED', 'project_budget', p_budget_id,
          jsonb_build_object('project_id', v_budget.project_id, 'version', v_budget.version));
  return p_budget_id;
end $$;

-- 3.3 Supersede an approved budget: closes the current version and opens
--     a REVISED draft (version + 1) over the same period with copied lines.
create or replace function public.f4_supersede_project_budget(
  p_organization_id uuid,
  p_budget_id uuid,
  p_description text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_budget public.project_budgets%rowtype;
  v_new_budget uuid; v_new_version integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 1000 then
    raise exception 'revision description must be 3-1000 characters';
  end if;
  v_hash := encode(digest(p_budget_id::text || '|supersede|' || trim(p_description),
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f4-budget-supersede:' || trim(p_idempotency_key), 0));
  select * into v_budget from public.project_budgets
  where id = p_budget_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'budget not found'; end if;
  if v_budget.status = 'SUPERSEDED' then return v_budget.superseded_by_budget_id; end if;
  if v_budget.status <> 'APPROVED' then
    raise exception 'only an approved budget can be superseded';
  end if;

  select coalesce(max(version), 0) + 1 into v_new_version
  from public.project_budgets
  where organization_id = p_organization_id and project_id = v_budget.project_id
    and period_start = v_budget.period_start and period_end = v_budget.period_end;

  insert into public.project_budgets(
    organization_id, project_id, period_start, period_end, budget_type,
    version, currency, description, prepared_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_budget.project_id, v_budget.period_start,
    v_budget.period_end, 'REVISED', v_new_version, v_budget.currency,
    trim(p_description), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_new_budget;

  insert into public.project_budget_lines(
    organization_id, budget_id, cost_treatment, amount_minor_units, notes
  )
  select p_organization_id, v_new_budget, cost_treatment, amount_minor_units, notes
  from public.project_budget_lines
  where budget_id = v_budget.id;

  update public.project_budgets
     set status = 'SUPERSEDED', superseded_by_budget_id = v_new_budget
   where id = v_budget.id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_SUPERSEDED', 'project_budget', v_budget.id,
          jsonb_build_object('replaced_by_budget_id', v_new_budget));
  return v_new_budget;
end $$;

-- 3.4 Delete a draft budget (the preparer or the OWNER).
create or replace function public.f4_delete_draft_budget(
  p_organization_id uuid,
  p_budget_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_budget public.project_budgets%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  select * into v_budget from public.project_budgets
  where id = p_budget_id and organization_id = p_organization_id
  for update;
  if not found then return p_budget_id; -- idempotent: already gone
  end if;
  if v_budget.status <> 'DRAFT' then
    raise exception 'only a draft budget can be deleted';
  end if;
  if v_budget.prepared_by <> v_actor and not public.s2_is_owner(p_organization_id) then
    raise exception 'forbidden: only the preparer or the organization owner can delete a draft budget';
  end if;
  delete from public.project_budgets
  where id = p_budget_id and organization_id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_DRAFT_DELETED', 'project_budget', p_budget_id,
          jsonb_build_object('project_id', v_budget.project_id));
  return p_budget_id;
end $$;

-- ===========================================================================
-- 4. Ceiling enforcement at obligation authorization.
--    The budget whose period contains the obligation date, when one exists,
--    caps the committed amount per cost treatment. An APPROVED
--    BUDGET_CEILING exception (F5 registry) raises the ceiling by its
--    explicit amount; nothing else can.
-- ===========================================================================
create or replace function public.authorize_cost_obligation(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_batch_id uuid; v_hash text; v_existing record;
  v_obligation record; v_debit_account uuid; v_payable_account uuid;
  v_budget_line record; v_committed numeric; v_exception_total numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select encode(digest(p_obligation_id::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':obligation-authorize:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.journal_batches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.source_type <> 'COST_OBLIGATION'
       or v_existing.source_id <> p_obligation_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_obligation
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'DRAFT' then
    raise exception 'only a draft obligation can be authorized';
  end if;

  -- F4 budget ceiling: an approved budget covering the transaction date
  -- enforces its treatment line.
  select bl.*, b.period_start, b.period_end into v_budget_line
  from public.project_budgets b
  join public.project_budget_lines bl on bl.budget_id = b.id
  where b.organization_id = p_organization_id
    and b.project_id = v_obligation.project_id
    and b.status = 'APPROVED'
    and v_obligation.transaction_date between b.period_start and b.period_end
    and bl.cost_treatment = v_obligation.cost_treatment
  order by b.approved_at desc, b.version desc
  limit 1;

  if found then
    select coalesce(sum(o.amount_minor_units), 0) into v_committed
    from public.cost_obligations o
    where o.organization_id = p_organization_id
      and o.project_id = v_obligation.project_id
      and o.status = 'AUTHORIZED'
      and o.cost_treatment = v_budget_line.cost_treatment
      and o.transaction_date between v_budget_line.period_start and v_budget_line.period_end
      and exists (
        select 1 from public.journal_batches jb
        where jb.source_type = 'COST_OBLIGATION' and jb.source_id = o.id
          and not exists (
            select 1 from public.journal_batches rb
            where rb.reversal_of_batch_id = jb.id
          )
      );

    -- Deferred lookup: the registry table is created by the F5 migration
    -- that follows this one; EXECUTE binds at call time.
    execute 'select coalesce(sum(e.amount_minor_units), 0)
             from public.approval_exceptions e
             where e.organization_id = $1
               and e.project_id = $2
               and e.exception_domain = ''BUDGET_CEILING''
               and e.subject_type = ''project_budget_line''
               and e.subject_id = $3
               and e.status = ''APPROVED'''
      into v_exception_total
      using p_organization_id, v_obligation.project_id, v_budget_line.id;

    if v_committed + v_obligation.amount_minor_units::numeric
         > v_budget_line.amount_minor_units::numeric + v_exception_total then
      raise exception 'budget ceiling exceeded for cost treatment %; an approved budget exception is required',
        v_budget_line.cost_treatment;
    end if;
  end if;

  select id into v_payable_account from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  if v_obligation.cost_treatment = 'EXPENSE' then
    select id into v_debit_account from public.semantic_accounts where role = 'PROJECT_EXPENSE';
  else
    select id into v_debit_account from public.semantic_accounts where role = 'DEVELOPMENT_WIP';
  end if;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_obligation.project_id, 'COST_OBLIGATION', p_obligation_id,
    v_obligation.transaction_date, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_obligation.project_id, v_debit_account,
     v_obligation.amount_minor_units, 0, v_obligation.currency,
     p_obligation_id, v_obligation.party_id, v_obligation.transaction_date),
    (v_batch_id, p_organization_id, v_obligation.project_id, v_payable_account,
     0, v_obligation.amount_minor_units, v_obligation.currency,
     p_obligation_id, v_obligation.party_id, v_obligation.transaction_date);

  update public.cost_obligations
     set status = 'AUTHORIZED', authorized_by = v_actor, authorized_at = now()
   where id = p_obligation_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_AUTHORIZED', 'cost_obligation', p_obligation_id,
          jsonb_build_object('project_id', v_obligation.project_id,
                             'journal_batch_id', v_batch_id,
                             'amount_minor_units', v_obligation.amount_minor_units,
                             'currency', v_obligation.currency,
                             'cost_treatment', v_obligation.cost_treatment));
  return v_batch_id;
end $$;

-- ===========================================================================
-- 5. Read models
--
-- (The consumption read model joins the F5 exception registry and lives in
-- the F5 migration. The purchase-commitment and budget-list models below
-- have no forward dependencies.)
-- ===========================================================================

-- Open purchase-order commitments falling inside each approved budget
-- period. POs do not declare a cost treatment, so they are reported as
-- their own unallocated commitment row — never silently mapped.
create or replace view public.project_budget_purchase_commitment_read with (security_invoker=on) as
select
  b.id as budget_id,
  b.organization_id,
  b.project_id,
  b.period_start,
  b.period_end,
  b.currency,
  'UNALLOCATED_PURCHASE_COMMITMENT'::text as commitment_class,
  coalesce(sum(pc.remaining_commitment_minor_units::bigint), 0)::text
    as open_commitment_minor_units
from public.project_budgets b
left join public.project_procurement_commitments_read pc
  on pc.project_id = b.project_id
 and pc.committed_at::date between b.period_start and b.period_end
 and pc.currency = b.currency
where b.status = 'APPROVED'
group by b.id, b.organization_id, b.project_id, b.period_start, b.period_end, b.currency;

create or replace view public.project_budgets_read with (security_invoker=on) as
select
  b.id as budget_id,
  b.organization_id,
  b.project_id,
  b.period_start,
  b.period_end,
  b.budget_type,
  b.version,
  b.status,
  b.currency,
  b.description,
  b.evidence_reference,
  b.prepared_by,
  b.approved_by,
  b.approved_at,
  b.superseded_by_budget_id,
  b.created_at,
  coalesce(sum(bl.amount_minor_units), 0)::text as total_budget_minor_units
from public.project_budgets b
left join public.project_budget_lines bl on bl.budget_id = b.id
group by b.id, b.organization_id, b.project_id, b.period_start, b.period_end,
         b.budget_type, b.version, b.status, b.currency, b.description,
         b.evidence_reference, b.prepared_by, b.approved_by, b.approved_at,
         b.superseded_by_budget_id, b.created_at;

-- ===========================================================================
-- 6. RLS / privileges
-- ===========================================================================
alter table public.project_budgets enable row level security;
alter table public.project_budgets force row level security;
alter table public.project_budget_lines enable row level security;
alter table public.project_budget_lines force row level security;

create policy project_budgets_read on public.project_budgets for select to authenticated
  using (public.is_active_member(organization_id));
create policy project_budget_lines_read on public.project_budget_lines for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.project_budgets, public.project_budget_lines
  from public, anon, authenticated;
grant select on public.project_budgets, public.project_budget_lines to authenticated;
grant select on public.project_budget_purchase_commitment_read,
  public.project_budgets_read to authenticated;

revoke all on function public.f4_create_project_budget(uuid,uuid,date,date,text,text,text,text,jsonb,text) from public, anon;
revoke all on function public.f4_approve_project_budget(uuid,uuid,text) from public, anon;
revoke all on function public.f4_supersede_project_budget(uuid,uuid,text,text) from public, anon;
revoke all on function public.f4_delete_draft_budget(uuid,uuid,text) from public, anon;
revoke all on function public.authorize_cost_obligation(uuid,uuid,text) from public, anon;

grant execute on function public.f4_create_project_budget(uuid,uuid,date,date,text,text,text,text,jsonb,text) to authenticated;
grant execute on function public.f4_approve_project_budget(uuid,uuid,text) to authenticated;
grant execute on function public.f4_supersede_project_budget(uuid,uuid,text,text) to authenticated;
grant execute on function public.f4_delete_draft_budget(uuid,uuid,text) to authenticated;
grant execute on function public.authorize_cost_obligation(uuid,uuid,text) to authenticated;
