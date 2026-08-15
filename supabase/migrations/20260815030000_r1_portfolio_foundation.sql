-- R1 — Portfolio Foundation.
--
-- Implements the first safe runtime slice of the canonical management
-- hierarchy Organization → Investment Portfolio → Investment Project
-- (docs/greenfield, R0 realignment, roadmap R1).
--
-- Scope is deliberately narrow and management-only:
--
--   * An InvestmentPortfolio is an organization-scoped management and
--     reporting parent. It is NOT a fund, legal entity, SPV, pooled
--     vehicle, investor pool, accounting entity, or second ledger.
--   * An Investment Project keeps AT MOST ONE current parent portfolio.
--     This follows the canonical ERD
--     (INVESTMENT_PORTFOLIO ||--o{ INVESTMENT_PROJECT : groups) and the
--     R0 rule that Portfolio membership never merges project identity,
--     sector objects, agreements, ledgers, or lifecycle.
--   * Membership is stored as assignment rows that are only ever
--     soft-closed (removed_at), so historical membership remains
--     explainable and append-only in spirit: no delete, no rewrite.
--   * No ownership, capital, contribution, allocation, distribution,
--     fee, reserve, netting, or investor column exists here. Those
--     remain OPEN business decisions (BD-001 … BD-012).
--
-- Reuses the shared core: organizations/memberships/is_active_member,
-- investment_projects, audit_events, the GF-013 idempotent
-- security-definer command pattern, and the S3/GF-013 causal lifecycle
-- chain pattern. Nothing existing is mutated: every existing project
-- simply has no parent portfolio until one is explicitly assigned.

-- ===========================================================================
-- 1. InvestmentPortfolio — management/reporting parent
-- ===========================================================================
create table if not exists public.investment_portfolios (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 120),
  description text
    check (description is null or char_length(trim(description)) between 3 and 2000),
  status text not null default 'DRAFT'
    check (status in ('DRAFT','ACTIVE','ARCHIVED')),
  -- Descriptive management reference only. Grants no permission and
  -- infers no ownership; must be an ACTIVE member of the same
  -- organization when set (enforced by trigger below).
  responsible_manager_id uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id)
);
create index if not exists investment_portfolios_org_idx
  on public.investment_portfolios(organization_id);

-- Manager must be an ACTIVE member of the portfolio's organization at
-- the moment the reference is written. Later membership revocation does
-- not rewrite the portfolio (the reference is descriptive history).
create or replace function public.r1_guard_portfolio_manager_membership()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.responsible_manager_id is not null
     and not exists (
       select 1 from public.memberships m
        where m.organization_id = new.organization_id
          and m.user_id = new.responsible_manager_id
          and m.status = 'ACTIVE'
     ) then
    raise exception 'responsible manager must be an active member of the portfolio organization';
  end if;
  return new;
end $$;
revoke all on function public.r1_guard_portfolio_manager_membership()
  from public, anon, authenticated;

drop trigger if exists portfolio_manager_membership_guard on public.investment_portfolios;
create trigger portfolio_manager_membership_guard
before insert or update of responsible_manager_id on public.investment_portfolios
for each row execute function public.r1_guard_portfolio_manager_membership();

-- ===========================================================================
-- 2. Portfolio lifecycle — causal state-history chain (S3/GF-013 pattern)
-- ===========================================================================
create table if not exists public.investment_portfolio_state_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  portfolio_id uuid not null,
  previous_history_id uuid,
  previous_status text
    check (previous_status is null or previous_status in ('DRAFT','ACTIVE','ARCHIVED')),
  new_status text not null check (new_status in ('DRAFT','ACTIVE','ARCHIVED')),
  reason text check (reason is null or char_length(trim(reason)) between 3 and 500),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (portfolio_id, previous_history_id),
  check ((previous_status is null and previous_history_id is null)
      or (previous_status is not null and previous_history_id is not null)),
  foreign key (previous_history_id, organization_id)
    references public.investment_portfolio_state_history(id, organization_id) on delete restrict,
  foreign key (portfolio_id, organization_id)
    references public.investment_portfolios(id, organization_id) on delete restrict
);
create unique index if not exists portfolio_one_initial_status
  on public.investment_portfolio_state_history(portfolio_id) where previous_status is null;
create index if not exists portfolio_state_timeline_idx
  on public.investment_portfolio_state_history(portfolio_id, changed_at, id);

create or replace function public.investment_portfolio_history_tip_id(p_portfolio_id uuid)
returns uuid language sql stable set search_path=pg_catalog,public as $$
  select h.id
  from public.investment_portfolio_state_history h
  where h.portfolio_id = p_portfolio_id
    and not exists (
      select 1 from public.investment_portfolio_state_history next_h
      where next_h.portfolio_id = h.portfolio_id
        and next_h.previous_history_id = h.id
    )
$$;

create or replace function public.investment_portfolio_current_status(p_portfolio_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_status
  from public.investment_portfolio_state_history h
  where h.id = public.investment_portfolio_history_tip_id(p_portfolio_id)
$$;

revoke all on function public.investment_portfolio_history_tip_id(uuid),
  public.investment_portfolio_current_status(uuid)
  from public, anon, authenticated;

-- Chain/column coherence: every appended history row must agree with the
-- authoritative status column at the moment of append. The initial row
-- must record the just-created status; a transition row must record the
-- not-yet-updated current status as its predecessor. Commands therefore
-- append history first and update the column second, inside one
-- transaction.
create or replace function public.r1_guard_portfolio_history_coherence()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
declare
  v_current text;
begin
  select p.status into v_current
  from public.investment_portfolios p
  where p.id = new.portfolio_id
    and p.organization_id = new.organization_id;
  if v_current is null then
    raise exception 'portfolio not found';
  end if;
  if new.previous_status is null then
    if new.new_status <> v_current then
      raise exception 'initial portfolio status history must match the portfolio status';
    end if;
  elsif new.previous_status <> v_current then
    raise exception 'portfolio status history predecessor must match the current portfolio status';
  end if;
  return new;
end $$;
revoke all on function public.r1_guard_portfolio_history_coherence()
  from public, anon, authenticated;

drop trigger if exists portfolio_history_coherence_guard
  on public.investment_portfolio_state_history;
create trigger portfolio_history_coherence_guard
before insert on public.investment_portfolio_state_history
for each row execute function public.r1_guard_portfolio_history_coherence();

-- Append-only lifecycle history: corrections append, never rewrite.
create or replace function public.r1_guard_portfolio_history_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'portfolio status history is append-only';
end $$;
revoke all on function public.r1_guard_portfolio_history_append_only()
  from public, anon, authenticated;

drop trigger if exists portfolio_state_history_append_only
  on public.investment_portfolio_state_history;
create trigger portfolio_state_history_append_only
before update or delete on public.investment_portfolio_state_history
for each row execute function public.r1_guard_portfolio_history_append_only();

-- ===========================================================================
-- 3. Portfolio ↔ Project membership
--    One current parent portfolio per project; rows are soft-closed so
--    history remains explainable. Organization coherence is enforced by
--    the composite foreign keys: both sides must belong to the single
--    assignment organization_id.
-- ===========================================================================
create table if not exists public.portfolio_project_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  portfolio_id uuid not null,
  investment_project_id uuid not null,
  assigned_by uuid not null references auth.users(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  removed_by uuid references auth.users(id) on delete restrict,
  removed_at timestamptz,
  removal_reason text
    check (removal_reason is null or char_length(trim(removal_reason)) between 3 and 500),
  -- The assignment key/hash above belongs to the assign command and is
  -- immutable. The removal command owns its own idempotency columns,
  -- written exactly once by the one-way soft close, so a completed
  -- removal can be replayed safely without rewriting assignment facts.
  removal_idempotency_key text
    check (removal_idempotency_key is null
        or char_length(removal_idempotency_key) between 8 and 120),
  removal_request_hash text
    check (removal_request_hash is null or char_length(removal_request_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (organization_id, idempotency_key),
  unique (organization_id, removal_idempotency_key),
  unique (id, organization_id),
  foreign key (portfolio_id, organization_id)
    references public.investment_portfolios(id, organization_id) on delete restrict,
  foreign key (investment_project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  check ((removed_at is null and removed_by is null and removal_reason is null
          and removal_idempotency_key is null and removal_request_hash is null)
      or (removed_at is not null and removed_by is not null and removal_reason is not null
          and removal_idempotency_key is not null and removal_request_hash is not null))
);
-- One current parent portfolio per project (canonical management hierarchy).
create unique index if not exists portfolio_one_current_parent_per_project
  on public.portfolio_project_assignments(investment_project_id) where removed_at is null;
create index if not exists portfolio_assignments_portfolio_idx
  on public.portfolio_project_assignments(portfolio_id);

-- Membership rows are never deleted and never rewritten; the only
-- permitted mutation is the one-way soft close that records removal.
create or replace function public.r1_guard_assignment_removal_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.removed_at is not null then
    raise exception 'portfolio membership removal is final';
  end if;
  if new.id <> old.id
     or new.organization_id <> old.organization_id
     or new.portfolio_id <> old.portfolio_id
     or new.investment_project_id <> old.investment_project_id
     or new.assigned_by <> old.assigned_by
     or new.assigned_at <> old.assigned_at
     or new.idempotency_key <> old.idempotency_key
     or new.request_hash <> old.request_hash then
    raise exception 'portfolio membership facts are immutable';
  end if;
  if new.removed_at is null or new.removed_by is null or new.removal_reason is null
     or new.removal_idempotency_key is null or new.removal_request_hash is null then
    raise exception 'portfolio membership removal requires remover, time, reason, and command key';
  end if;
  return new;
end $$;
revoke all on function public.r1_guard_assignment_removal_only()
  from public, anon, authenticated;

drop trigger if exists portfolio_assignment_removal_only
  on public.portfolio_project_assignments;
create trigger portfolio_assignment_removal_only
before update on public.portfolio_project_assignments
for each row execute function public.r1_guard_assignment_removal_only();

create or replace function public.r1_guard_assignment_no_delete()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'portfolio membership history is append-only';
end $$;
revoke all on function public.r1_guard_assignment_no_delete()
  from public, anon, authenticated;

drop trigger if exists portfolio_assignment_no_delete
  on public.portfolio_project_assignments;
create trigger portfolio_assignment_no_delete
before delete on public.portfolio_project_assignments
for each row execute function public.r1_guard_assignment_no_delete();

-- ===========================================================================
-- 4. Server-authoritative commands
-- ===========================================================================

-- 4.1 Create a portfolio (always starts in DRAFT).
create or replace function public.create_investment_portfolio(
  p_organization_id uuid,
  p_name text,
  p_description text,
  p_responsible_manager_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 120 then
    raise exception 'invalid portfolio name';
  end if;
  if p_description is not null and char_length(trim(p_description)) not between 3 and 2000 then
    raise exception 'invalid portfolio description';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(trim(p_name) || '|'
         || coalesce(trim(p_description),'') || '|'
         || coalesce(p_responsible_manager_id::text,''), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-portfolio:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.investment_portfolios
   where organization_id = p_organization_id
     and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.investment_portfolios(
    organization_id, name, description, status, responsible_manager_id,
    created_by, idempotency_key, request_hash
  ) values (
    p_organization_id, trim(p_name),
    nullif(trim(p_description), ''),
    'DRAFT', p_responsible_manager_id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.investment_portfolio_state_history(
    organization_id, portfolio_id, previous_history_id, previous_status,
    new_status, reason, changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_id, null, null,
    'DRAFT', null, v_actor,
    encode(digest(trim(p_idempotency_key) || ':initial-status', 'sha256'), 'hex'),
    v_hash
  );

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PORTFOLIO_CREATED', 'investment_portfolio', v_id,
    jsonb_build_object(
      'name', trim(p_name),
      'responsible_manager_id', p_responsible_manager_id
    )
  );
  return v_id;
end $$;

-- 4.2 Update safe management metadata (name/description/manager).
--     Convergent command: re-applying the same payload yields the same
--     state, so retries are safe. ARCHIVED portfolios are read-only.
create or replace function public.update_investment_portfolio_metadata(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_name text,
  p_description text,
  p_responsible_manager_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_portfolio record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 120 then
    raise exception 'invalid portfolio name';
  end if;
  if p_description is not null and char_length(trim(p_description)) not between 3 and 2000 then
    raise exception 'invalid portfolio description';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-portfolio-update:' || trim(p_idempotency_key), 0));

  select * into v_portfolio
    from public.investment_portfolios
   where id = p_portfolio_id
     and organization_id = p_organization_id
   for update;
  if not found then raise exception 'portfolio not found'; end if;
  if v_portfolio.status = 'ARCHIVED' then
    raise exception 'archived portfolio metadata is read-only';
  end if;

  if coalesce(v_portfolio.name,'') = trim(p_name)
     and coalesce(v_portfolio.description,'') = coalesce(nullif(trim(p_description),''),'')
     and v_portfolio.responsible_manager_id is not distinct from p_responsible_manager_id then
    -- Idempotent no-op: identical metadata already stored.
    return v_portfolio.id;
  end if;

  update public.investment_portfolios
     set name = trim(p_name),
         description = nullif(trim(p_description), ''),
         responsible_manager_id = p_responsible_manager_id,
         updated_at = now()
   where id = p_portfolio_id
     and organization_id = p_organization_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PORTFOLIO_METADATA_UPDATED', 'investment_portfolio',
    p_portfolio_id,
    jsonb_build_object(
      'name', trim(p_name),
      'responsible_manager_id', p_responsible_manager_id,
      'idempotency_key', trim(p_idempotency_key)
    )
  );
  return p_portfolio_id;
end $$;

-- 4.3 Controlled lifecycle transition (version/state aware).
create or replace function public.transition_investment_portfolio(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_expected_status text,
  p_new_status text,
  p_reason text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_portfolio record;
  v_tip uuid;
  v_current_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid portfolio transition reason';
  end if;
  if p_new_status not in ('DRAFT','ACTIVE','ARCHIVED') then
    raise exception 'invalid new portfolio status';
  end if;

  select encode(digest(p_portfolio_id::text || '|' || p_expected_status || '|'
         || p_new_status || '|' || trim(p_reason), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-portfolio-transition:' || trim(p_idempotency_key), 0));

  select * into v_existing
    from public.investment_portfolio_state_history
   where organization_id = p_organization_id
     and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_portfolio
    from public.investment_portfolios
   where id = p_portfolio_id
     and organization_id = p_organization_id
   for update;
  if not found then raise exception 'portfolio not found'; end if;

  v_tip := public.investment_portfolio_history_tip_id(p_portfolio_id);
  if v_tip is null then raise exception 'portfolio has no lifecycle history'; end if;
  select new_status into v_current_status
    from public.investment_portfolio_state_history
   where id = v_tip;

  if v_current_status <> p_expected_status then
    raise exception 'expected portfolio status mismatch: current=% requested=%',
      v_current_status, p_expected_status;
  end if;

  -- Documented R1 transition table. Activation creates no rights,
  -- capital, postings, or ownership; archiving never touches member
  -- projects. No backward or re-asserting transition exists.
  if not (
       (v_current_status = 'DRAFT'  and p_new_status = 'ACTIVE')
    or (v_current_status = 'DRAFT'  and p_new_status = 'ARCHIVED')
    or (v_current_status = 'ACTIVE' and p_new_status = 'ARCHIVED')
  ) then
    raise exception 'invalid portfolio transition: % -> %', v_current_status, p_new_status;
  end if;

  -- Append history first; the coherence trigger validates the
  -- predecessor against the still-current status column.
  insert into public.investment_portfolio_state_history(
    organization_id, portfolio_id, previous_history_id, previous_status,
    new_status, reason, changed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_portfolio_id, v_tip, v_current_status,
    p_new_status, trim(p_reason), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  update public.investment_portfolios
     set status = p_new_status,
         updated_at = now()
   where id = p_portfolio_id
     and organization_id = p_organization_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PORTFOLIO_TRANSITIONED', 'investment_portfolio',
    p_portfolio_id,
    jsonb_build_object(
      'previous_status', v_current_status,
      'new_status', p_new_status,
      'reason', trim(p_reason)
    )
  );
  return v_id;
end $$;

-- 4.4 Assign an existing same-organization project to an ACTIVE portfolio.
--     The project keeps its identity, sector, agreements, ledger, and
--     lifecycle; only the management parent is recorded.
create or replace function public.assign_project_to_portfolio(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_project_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_portfolio record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_portfolio_id::text || '|' || p_project_id::text, 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-assignment:' || p_project_id::text, 0));

  select * into v_existing
    from public.portfolio_project_assignments
   where organization_id = p_organization_id
     and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_portfolio
    from public.investment_portfolios
   where id = p_portfolio_id
     and organization_id = p_organization_id
   for update;
  if not found then raise exception 'portfolio not found'; end if;
  if v_portfolio.status <> 'ACTIVE' then
    raise exception 'projects can only be assigned to an active portfolio';
  end if;

  if not exists (
    select 1 from public.investment_projects p
     where p.id = p_project_id
       and p.organization_id = p_organization_id
  ) then
    raise exception 'project not found in portfolio organization';
  end if;

  if exists (
    select 1 from public.portfolio_project_assignments a
     where a.investment_project_id = p_project_id
       and a.organization_id = p_organization_id
       and a.removed_at is null
  ) then
    raise exception 'project already assigned to a portfolio';
  end if;

  insert into public.portfolio_project_assignments(
    organization_id, portfolio_id, investment_project_id, assigned_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_portfolio_id, p_project_id, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_ASSIGNED_TO_PORTFOLIO',
    'portfolio_project_assignment', v_id,
    jsonb_build_object(
      'portfolio_id', p_portfolio_id,
      'investment_project_id', p_project_id
    )
  );
  return v_id;
end $$;

-- 4.5 Remove a project from its current portfolio (soft close).
--     Never deletes or rewrites the project or its history.
create or replace function public.remove_project_from_portfolio(
  p_organization_id uuid,
  p_portfolio_id uuid,
  p_project_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_assignment record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid portfolio membership removal reason';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_portfolio_id::text || '|' || p_project_id::text || '|'
         || trim(p_reason), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-assignment:' || p_project_id::text, 0));

  -- Idempotency first: a completed removal replayed with its own key is
  -- a no-op returning the same membership row even though the live
  -- membership no longer exists.
  select * into v_existing
    from public.portfolio_project_assignments
   where organization_id = p_organization_id
     and removal_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.removal_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_assignment
    from public.portfolio_project_assignments
   where investment_project_id = p_project_id
     and portfolio_id = p_portfolio_id
     and organization_id = p_organization_id
     and removed_at is null
   for update;
  if not found then
    raise exception 'portfolio membership not found';
  end if;

  update public.portfolio_project_assignments
     set removed_by = v_actor,
         removed_at = now(),
         removal_reason = trim(p_reason),
         removal_idempotency_key = trim(p_idempotency_key),
         removal_request_hash = v_hash
   where id = v_assignment.id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_REMOVED_FROM_PORTFOLIO',
    'portfolio_project_assignment', v_assignment.id,
    jsonb_build_object(
      'portfolio_id', p_portfolio_id,
      'investment_project_id', p_project_id,
      'reason', trim(p_reason)
    )
  );
  return v_assignment.id;
end $$;

-- 4.6 Move a project between portfolios atomically (close current
--     membership and open the new one in one transaction).
create or replace function public.move_project_to_portfolio(
  p_organization_id uuid,
  p_project_id uuid,
  p_target_portfolio_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_assignment record;
  v_target record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'invalid portfolio membership move reason';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_project_id::text || '|' || p_target_portfolio_id::text || '|'
         || trim(p_reason), 'sha256'), 'hex')
    into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r1-assignment:' || p_project_id::text, 0));

  select * into v_existing
    from public.portfolio_project_assignments
   where organization_id = p_organization_id
     and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_target
    from public.investment_portfolios
   where id = p_target_portfolio_id
     and organization_id = p_organization_id
   for update;
  if not found then raise exception 'portfolio not found'; end if;
  if v_target.status <> 'ACTIVE' then
    raise exception 'projects can only be moved to an active portfolio';
  end if;

  select * into v_assignment
    from public.portfolio_project_assignments
   where investment_project_id = p_project_id
     and organization_id = p_organization_id
     and removed_at is null
   for update;
  if not found then
    raise exception 'project is not assigned to a portfolio; assign it instead';
  end if;
  if v_assignment.portfolio_id = p_target_portfolio_id then
    raise exception 'project is already in the target portfolio';
  end if;

  update public.portfolio_project_assignments
     set removed_by = v_actor,
         removed_at = now(),
         removal_reason = trim(p_reason),
         removal_idempotency_key =
           encode(digest(trim(p_idempotency_key) || ':move-removal', 'sha256'), 'hex'),
         removal_request_hash = v_hash
   where id = v_assignment.id;

  insert into public.portfolio_project_assignments(
    organization_id, portfolio_id, investment_project_id, assigned_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_target_portfolio_id, p_project_id, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_MOVED_BETWEEN_PORTFOLIOS',
    'portfolio_project_assignment', v_id,
    jsonb_build_object(
      'investment_project_id', p_project_id,
      'from_portfolio_id', v_assignment.portfolio_id,
      'to_portfolio_id', p_target_portfolio_id,
      'reason', trim(p_reason)
    )
  );
  return v_id;
end $$;

-- ===========================================================================
-- 5. Default-deny RLS, forced RLS, and read models
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'investment_portfolios',
    'investment_portfolio_state_history',
    'portfolio_project_assignments'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_active_member(organization_id))',
      t || '_read', t
    );
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- security_invoker read views for the canonical application read path.
create or replace view public.investment_portfolios_read with (security_invoker=on) as
select id, organization_id, name, description, status,
       responsible_manager_id, created_by, created_at, updated_at
from public.investment_portfolios;

create or replace view public.investment_portfolio_state_history_read
  with (security_invoker=on) as
select h.id, h.organization_id, h.portfolio_id, h.previous_status,
       h.new_status, h.reason, h.changed_by, h.changed_at
from public.investment_portfolio_state_history h;

create or replace view public.portfolio_project_assignments_read
  with (security_invoker=on) as
select a.id, a.organization_id, a.portfolio_id, a.investment_project_id,
       p.name as project_name,
       p.sector as project_sector,
       p.internal_reference as project_internal_reference,
       p.lifecycle_state as project_lifecycle_state,
       a.assigned_by, a.assigned_at, a.removed_by, a.removed_at,
       a.removal_reason
from public.portfolio_project_assignments a
join public.investment_projects p
  on p.id = a.investment_project_id
 and p.organization_id = a.organization_id;

grant select on
  public.investment_portfolios_read,
  public.investment_portfolio_state_history_read,
  public.portfolio_project_assignments_read
to authenticated;

-- ===========================================================================
-- 6. Command grants
-- ===========================================================================
revoke all on function
  public.create_investment_portfolio(uuid,text,text,uuid,text),
  public.update_investment_portfolio_metadata(uuid,uuid,text,text,uuid,text),
  public.transition_investment_portfolio(uuid,uuid,text,text,text,text),
  public.assign_project_to_portfolio(uuid,uuid,uuid,text),
  public.remove_project_from_portfolio(uuid,uuid,uuid,text,text),
  public.move_project_to_portfolio(uuid,uuid,uuid,text,text)
  from public, anon;
grant execute on function
  public.create_investment_portfolio(uuid,text,text,uuid,text),
  public.update_investment_portfolio_metadata(uuid,uuid,text,text,uuid,text),
  public.transition_investment_portfolio(uuid,uuid,text,text,text,text),
  public.assign_project_to_portfolio(uuid,uuid,uuid,text),
  public.remove_project_from_portfolio(uuid,uuid,uuid,text,text),
  public.move_project_to_portfolio(uuid,uuid,uuid,text,text)
to authenticated;

-- R1 functions are created after the repository-wide pgcrypto
-- compatibility migration. Reapply its portable qualification rule so this
-- batch works whether pgcrypto is installed in public, extensions, or
-- another extension schema. CREATE OR REPLACE preserves function identity
-- and grants.
do $pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'R1 requires the pgcrypto extension';
  end if;

  for v_record in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten := regexp_replace(
        v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
        'g'
      );
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
