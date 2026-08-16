-- F3 — Contract Finance: payment terms, schedules, milestones, retention,
-- disputes and due/aging on top of the existing cost_obligations backbone.
--
-- Canonical rules honored here:
--   * An authorized obligation is immutable; every contract-finance fact
--     (terms, schedule, retention, dispute) is either set while the
--     obligation is DRAFT or appended to a separate append-only register.
--   * Retention never creates a second ledger: the full payable is posted
--     at authorization; the withheld portion only blocks payment until an
--     explicit release is recorded. No new journal entries are invented.
--   * Disputes block payment but never mutate the posted obligation.
--   * All money is bigint minor units; the client sees text through *_read
--     views. All commands are idempotent with advisory-lock replay safety.
--   * No guessed business policy: terms are explicit data entered by an
--     authorized actor; there is no auto-computed due date except the
--     explicit NET_DAYS/FIXED_DATE/MILESTONE_SCHEDULE arithmetic declared
--     below.

-- ===========================================================================
-- 1. Project milestones (project-level contract/achievement landmarks)
-- ===========================================================================
create table public.project_milestones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  code text not null check (char_length(trim(code)) between 2 and 40),
  label_ar text not null check (char_length(trim(label_ar)) between 2 and 200),
  planned_date date,
  status text not null default 'PENDING' check (status in ('PENDING','ACHIEVED')),
  achieved_date date,
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, project_id, code),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint project_milestones_state_check check (
    (status = 'PENDING' and achieved_date is null)
    or (status = 'ACHIEVED' and achieved_date is not null)
  )
);
create index project_milestones_project_status_idx
  on public.project_milestones(project_id, status);

-- An achieved milestone is a locked fact. Only the PENDING -> ACHIEVED
-- transition is allowed, and it is only performed through the command.
create or replace function public.f3_guard_milestone_lifecycle() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'PENDING' then
      raise exception 'an achieved milestone cannot be deleted';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  -- UPDATE
  if old.status <> 'PENDING' then
    raise exception 'an achieved milestone is immutable';
  end if;
  if new.status = 'ACHIEVED' and new.achieved_date is null then
    raise exception 'achieved milestone requires achieved date';
  end if;
  if new.status = 'PENDING' and new.achieved_date is not null then
    raise exception 'pending milestone cannot carry achieved date';
  end if;
  return new;
end $$;
drop trigger if exists project_milestones_lifecycle on public.project_milestones;
create trigger project_milestones_lifecycle
before update or delete on public.project_milestones
for each row execute function public.f3_guard_milestone_lifecycle();

-- ===========================================================================
-- 2. Obligation payment terms (one explicit contract per obligation)
-- ===========================================================================
create table public.cost_obligation_terms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  obligation_id uuid not null,
  terms_type text not null check (terms_type in (
    'FIXED_DATE','NET_DAYS','MILESTONE_SCHEDULE'
  )),
  due_date date,
  net_days integer check (net_days is null or net_days between 1 and 730),
  retention_minor_units bigint not null default 0
    check (retention_minor_units >= 0),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 1000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, obligation_id),
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete cascade,
  constraint cost_obligation_terms_shape_check check (
    (terms_type = 'FIXED_DATE' and due_date is not null and net_days is null)
    or (terms_type = 'NET_DAYS' and net_days is not null and due_date is null)
    or (terms_type = 'MILESTONE_SCHEDULE' and due_date is null and net_days is null)
  )
);
create index cost_obligation_terms_obligation_idx
  on public.cost_obligation_terms(obligation_id);

-- Terms may only exist / change while the obligation is a DRAFT. Retention
-- must always be strictly below the obligation amount (you cannot withhold
-- the entire payable and call it terms).
create or replace function public.f3_guard_terms_draft_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_status text;
  v_amount bigint;
begin
  if tg_op = 'DELETE' then
    select status into v_status from public.cost_obligations
    where id = old.obligation_id;
    if not found then
      -- Parent draft obligation deletion cascade: the only allowed delete.
      return old;
    end if;
    if v_status <> 'DRAFT' then
      raise exception 'payment terms cannot be removed from an authorized obligation';
    end if;
    return old;
  end if;
  select status, amount_minor_units into v_status, v_amount
  from public.cost_obligations
  where id = new.obligation_id;
  if not found then raise exception 'obligation not found'; end if;
  if v_status <> 'DRAFT' then
    raise exception 'payment terms can only be set while the obligation is a draft';
  end if;
  if new.retention_minor_units >= v_amount then
    raise exception 'retention must be strictly less than the obligation amount';
  end if;
  return new;
end $$;
drop trigger if exists cost_obligation_terms_draft_only on public.cost_obligation_terms;
create trigger cost_obligation_terms_draft_only
before insert or update or delete on public.cost_obligation_terms
for each row execute function public.f3_guard_terms_draft_only();

-- ===========================================================================
-- 3. Obligation payment schedule lines (milestone-linked plan)
-- ===========================================================================
create table public.cost_obligation_schedule_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  obligation_id uuid not null,
  line_number integer not null check (line_number between 1 and 999),
  due_date date,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  milestone_id uuid,
  is_retention_line boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, obligation_id, line_number),
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete cascade,
  foreign key (milestone_id, organization_id)
    references public.project_milestones(id, organization_id) on delete restrict,
  constraint cost_obligation_schedule_lines_retention_shape_check check (
    (is_retention_line = false) or (is_retention_line = true and milestone_id is null)
  )
);
create index cost_obligation_schedule_lines_obligation_idx
  on public.cost_obligation_schedule_lines(obligation_id, line_number);
create index cost_obligation_schedule_lines_milestone_idx
  on public.cost_obligation_schedule_lines(milestone_id);

-- Draft-only schedule lines, plus the plan arithmetic:
--   * total scheduled amount never exceeds the obligation amount,
--   * scheduled retention lines never exceed the declared retention.
create or replace function public.f3_guard_schedule_draft_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_status text;
begin
  if tg_op = 'DELETE' then
    select status into v_status from public.cost_obligations
    where id = old.obligation_id;
    if not found then
      -- Parent draft obligation deletion cascade: the only allowed delete.
      return old;
    end if;
    if v_status <> 'DRAFT' then
      raise exception 'schedule lines cannot be removed from an authorized obligation';
    end if;
    return old;
  end if;
  select status into v_status from public.cost_obligations
  where id = new.obligation_id;
  if not found then raise exception 'obligation not found'; end if;
  if v_status <> 'DRAFT' then
    raise exception 'schedule lines can only be set while the obligation is a draft';
  end if;
  return new;
end $$;
drop trigger if exists cost_obligation_schedule_draft_only on public.cost_obligation_schedule_lines;
create trigger cost_obligation_schedule_draft_only
before insert or update or delete on public.cost_obligation_schedule_lines
for each row execute function public.f3_guard_schedule_draft_only();

create or replace function public.f3_guard_schedule_totals() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_obligation_id uuid;
  v_amount bigint; v_retention bigint;
  v_total numeric; v_retention_total numeric;
begin
  if tg_op = 'DELETE' then
    v_obligation_id := old.obligation_id;
  else
    v_obligation_id := new.obligation_id;
  end if;
  select o.amount_minor_units, coalesce(t.retention_minor_units, 0)
    into v_amount, v_retention
  from public.cost_obligations o
  left join public.cost_obligation_terms t on t.obligation_id = o.id
  where o.id = v_obligation_id;
  if not found then
    -- Parent draft obligation deletion cascade: nothing left to verify.
    return null;
  end if;
  select coalesce(sum(amount_minor_units), 0) into v_total
  from public.cost_obligation_schedule_lines
  where obligation_id = v_obligation_id;
  select coalesce(sum(amount_minor_units), 0) into v_retention_total
  from public.cost_obligation_schedule_lines
  where obligation_id = v_obligation_id
    and is_retention_line;
  if v_total > v_amount then
    raise exception 'scheduled total exceeds the obligation amount';
  end if;
  if v_retention_total > v_retention then
    raise exception 'scheduled retention exceeds the declared retention';
  end if;
  return null;
end $$;
drop trigger if exists cost_obligation_schedule_totals on public.cost_obligation_schedule_lines;
create trigger cost_obligation_schedule_totals
after insert or update or delete on public.cost_obligation_schedule_lines
for each row execute function public.f3_guard_schedule_totals();

-- ===========================================================================
-- 4. Dispute register (append-only; blocks payment while OPEN)
-- ===========================================================================
create table public.cost_obligation_disputes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  obligation_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  status text not null default 'OPEN' check (status in ('OPEN','RESOLVED')),
  opened_by uuid not null references auth.users(id) on delete restrict,
  opened_at timestamptz not null default now(),
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  resolution_note text
    check (resolution_note is null or char_length(trim(resolution_note)) between 3 and 1000),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  constraint cost_obligation_disputes_state_check check (
    (status = 'OPEN' and resolved_by is null and resolved_at is null and resolution_note is null)
    or (status = 'RESOLVED' and resolved_by is not null and resolved_at is not null
        and resolution_note is not null)
  )
);
-- At most one OPEN dispute per obligation; resolved history is preserved.
create unique index cost_obligation_disputes_one_open
  on public.cost_obligation_disputes(organization_id, obligation_id)
  where status = 'OPEN';
create index cost_obligation_disputes_status_idx
  on public.cost_obligation_disputes(organization_id, status);

create or replace function public.f3_guard_dispute_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'dispute records are append-only';
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  -- UPDATE
  if old.status = 'RESOLVED' and new.status = 'OPEN' then
    raise exception 'a resolved dispute cannot be reopened; open a new dispute';
  end if;
  if old.id is distinct from new.id
     or old.obligation_id is distinct from new.obligation_id
     or old.opened_by is distinct from new.opened_by
     or old.opened_at is distinct from new.opened_at
     or old.reason is distinct from new.reason then
    raise exception 'dispute records are append-only';
  end if;
  if new.status = 'RESOLVED' and new.resolved_by = new.opened_by then
    raise exception 'maker/checker: the dispute opener cannot resolve it';
  end if;
  return new;
end $$;
drop trigger if exists cost_obligation_disputes_append_only on public.cost_obligation_disputes;
create trigger cost_obligation_disputes_append_only
before update or delete on public.cost_obligation_disputes
for each row execute function public.f3_guard_dispute_append_only();

-- ===========================================================================
-- 5. Retention release register (append-only; releases the withheld payable)
-- ===========================================================================
create table public.cost_obligation_retention_releases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  obligation_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  release_date date not null,
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  milestone_id uuid,
  released_by uuid not null references auth.users(id) on delete restrict,
  released_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (milestone_id, organization_id)
    references public.project_milestones(id, organization_id) on delete restrict
);
create index cost_obligation_retention_releases_obligation_idx
  on public.cost_obligation_retention_releases(obligation_id);

create or replace function public.f3_guard_retention_release_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'retention releases are append-only';
  end if;
  return new;
end $$;
drop trigger if exists cost_obligation_retention_releases_append_only on public.cost_obligation_retention_releases;
create trigger cost_obligation_retention_releases_append_only
before update or delete on public.cost_obligation_retention_releases
for each row execute function public.f3_guard_retention_release_append_only();

-- Releases can never exceed the declared retention.
create or replace function public.f3_guard_retention_release_ceiling() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_retention bigint; v_released numeric;
begin
  select coalesce(t.retention_minor_units, 0) into v_retention
  from public.cost_obligation_terms t where t.obligation_id = new.obligation_id;
  select coalesce(sum(amount_minor_units), 0) into v_released
  from public.cost_obligation_retention_releases
  where obligation_id = new.obligation_id;
  if v_retention <= 0 then
    raise exception 'this obligation declares no retention';
  end if;
  if v_released + new.amount_minor_units > v_retention then
    raise exception 'retention release exceeds the declared retention';
  end if;
  return new;
end $$;
drop trigger if exists cost_obligation_retention_release_ceiling on public.cost_obligation_retention_releases;
create trigger cost_obligation_retention_release_ceiling
before insert on public.cost_obligation_retention_releases
for each row execute function public.f3_guard_retention_release_ceiling();

-- ===========================================================================
-- 6. Commands
-- ===========================================================================

-- 6.1 Milestone creation (any active member; idempotent by org+project+code)
create or replace function public.f3_create_project_milestone(
  p_organization_id uuid,
  p_project_id uuid,
  p_code text,
  p_label_ar text,
  p_planned_date date,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_code is null or char_length(trim(p_code)) not between 2 and 40 then
    raise exception 'milestone code must be 2-40 characters';
  end if;
  if p_label_ar is null or char_length(trim(p_label_ar)) not between 2 and 200 then
    raise exception 'milestone label must be 2-200 characters';
  end if;
  if not exists (select 1 from public.investment_projects
                 where id = p_project_id and organization_id = p_organization_id) then
    raise exception 'project not found';
  end if;

  select encode(digest(p_project_id::text || '|' || trim(p_code) || '|'
    || trim(p_label_ar) || '|' || coalesce(p_planned_date::text, '') || '|'
    || coalesce(nullif(trim(p_evidence_reference), ''), ''), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-milestone:' || trim(p_idempotency_key), 0));
  -- Idempotent replay by natural identity (org + project + code).
  select * into v_existing from public.project_milestones
  where organization_id = p_organization_id and project_id = p_project_id
    and code = trim(p_code);
  if found then
    return v_existing.id;
  end if;

  insert into public.project_milestones(
    organization_id, project_id, code, label_ar, planned_date,
    evidence_reference, created_by
  ) values (
    p_organization_id, p_project_id, trim(p_code), trim(p_label_ar),
    p_planned_date, nullif(trim(p_evidence_reference), ''), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'MILESTONE_CREATED', 'project_milestone', v_id,
          jsonb_build_object('project_id', p_project_id, 'code', trim(p_code),
                             'planned_date', p_planned_date));
  return v_id;
end $$;

-- 6.2 Milestone achievement (any active member; locks the milestone)
create or replace function public.f3_achieve_project_milestone(
  p_organization_id uuid,
  p_milestone_id uuid,
  p_achieved_date date,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_achieved_date is null then raise exception 'achieved date required'; end if;

  select encode(digest(p_milestone_id::text || '|' || p_achieved_date::text
    || '|' || coalesce(nullif(trim(p_evidence_reference), ''), ''), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-milestone-achieve:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.audit_events
  where organization_id = p_organization_id
    and event_type = 'MILESTONE_ACHIEVED'
    and entity_id = p_milestone_id
    and payload->>'achieved_hash' = v_hash;
  if found then
    return p_milestone_id;
  end if;

  select id into v_id from public.project_milestones
  where id = p_milestone_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'milestone not found'; end if;

  update public.project_milestones
     set status = 'ACHIEVED',
         achieved_date = p_achieved_date,
         evidence_reference = coalesce(nullif(trim(p_evidence_reference), ''), evidence_reference)
   where id = p_milestone_id and organization_id = p_organization_id
     and status = 'PENDING';
  if not found then raise exception 'milestone is already achieved'; end if;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'MILESTONE_ACHIEVED', 'project_milestone', p_milestone_id,
          jsonb_build_object('achieved_date', p_achieved_date, 'achieved_hash', v_hash));
  return p_milestone_id;
end $$;

-- 6.3 Set obligation payment terms (draft only; one row per obligation)
create or replace function public.f3_set_obligation_terms(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_terms_type text,
  p_due_date date,
  p_net_days integer,
  p_retention_minor_units bigint,
  p_evidence_reference text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_terms_type not in ('FIXED_DATE','NET_DAYS','MILESTONE_SCHEDULE') then
    raise exception 'terms type must be FIXED_DATE, NET_DAYS or MILESTONE_SCHEDULE';
  end if;
  if p_retention_minor_units is null or p_retention_minor_units < 0 then
    raise exception 'retention cannot be negative';
  end if;

  select encode(digest(p_obligation_id::text || '|' || p_terms_type || '|'
    || coalesce(p_due_date::text, '') || '|' || coalesce(p_net_days::text, '') || '|'
    || p_retention_minor_units::text || '|' || coalesce(nullif(trim(p_evidence_reference), ''), '')
    || '|' || coalesce(nullif(trim(p_notes), ''), ''), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-terms:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_obligation_terms
  where organization_id = p_organization_id and obligation_id = p_obligation_id;
  if found then
    if v_existing.terms_type <> p_terms_type
       or v_existing.due_date is distinct from p_due_date
       or v_existing.net_days is distinct from p_net_days
       or v_existing.retention_minor_units is distinct from p_retention_minor_units then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.cost_obligation_terms(
    organization_id, obligation_id, terms_type, due_date, net_days,
    retention_minor_units, evidence_reference, notes, created_by
  ) values (
    p_organization_id, p_obligation_id, p_terms_type, p_due_date, p_net_days,
    p_retention_minor_units, nullif(trim(p_evidence_reference), ''),
    nullif(trim(p_notes), ''), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_TERMS_SET', 'cost_obligation', p_obligation_id,
          jsonb_build_object('terms_type', p_terms_type, 'due_date', p_due_date,
                             'net_days', p_net_days,
                             'retention_minor_units', p_retention_minor_units));
  return v_id;
end $$;

-- 6.4 Open a dispute (any active member; must be an AUTHORIZED obligation)
create or replace function public.f3_open_obligation_dispute(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid; v_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 1000 then
    raise exception 'dispute reason must be 3-1000 characters';
  end if;

  select encode(digest(p_obligation_id::text || '|' || trim(p_reason), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-dispute:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_obligation_disputes
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status into v_status from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if v_status is null then raise exception 'obligation not found'; end if;
  if v_status <> 'AUTHORIZED' then
    raise exception 'a dispute requires an authorized obligation';
  end if;

  insert into public.cost_obligation_disputes(
    organization_id, obligation_id, reason, opened_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_obligation_id, trim(p_reason), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DISPUTE_OPENED', 'cost_obligation', p_obligation_id,
          jsonb_build_object('dispute_id', v_id));
  return v_id;
end $$;

-- 6.5 Resolve a dispute (OWNER only; cannot be the opener)
create or replace function public.f3_resolve_obligation_dispute(
  p_organization_id uuid,
  p_dispute_id uuid,
  p_resolution_note text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_dispute record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_resolution_note is null or char_length(trim(p_resolution_note)) not between 3 and 1000 then
    raise exception 'resolution note must be 3-1000 characters';
  end if;

  select encode(digest(p_dispute_id::text || '|' || trim(p_resolution_note), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-dispute-resolve:' || trim(p_idempotency_key), 0));
  select * into v_dispute from public.cost_obligation_disputes
  where id = p_dispute_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'dispute not found'; end if;
  if v_dispute.status = 'RESOLVED' then
    if v_dispute.resolution_note = trim(p_resolution_note) then
      return v_dispute.id;
    end if;
    raise exception 'dispute is already resolved';
  end if;
  if v_dispute.opened_by = v_actor then
    raise exception 'maker/checker: the dispute opener cannot resolve it';
  end if;

  update public.cost_obligation_disputes
     set status = 'RESOLVED', resolved_by = v_actor, resolved_at = now(),
         resolution_note = trim(p_resolution_note)
   where id = p_dispute_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DISPUTE_RESOLVED', 'cost_obligation',
          v_dispute.obligation_id, jsonb_build_object('dispute_id', p_dispute_id));
  return p_dispute_id;
end $$;

-- 6.6 Release retention (OWNER only; append-only release against the terms)
create or replace function public.f3_release_obligation_retention(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_release_date date,
  p_reason text,
  p_milestone_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid; v_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'release amount must be positive';
  end if;
  if p_release_date is null then raise exception 'release date required'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 1000 then
    raise exception 'release reason must be 3-1000 characters';
  end if;

  select encode(digest(p_obligation_id::text || '|' || p_amount_minor_units::text
    || '|' || p_release_date::text || '|' || trim(p_reason) || '|'
    || coalesce(p_milestone_id::text, ''), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-retention-release:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_obligation_retention_releases
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select status into v_status from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if v_status is null then raise exception 'obligation not found'; end if;
  if v_status <> 'AUTHORIZED' then
    raise exception 'retention can only be released on an authorized obligation';
  end if;
  if p_milestone_id is not null and not exists (
    select 1 from public.project_milestones
    where id = p_milestone_id and organization_id = p_organization_id
      and status = 'ACHIEVED'
  ) then raise exception 'retention release milestone must be achieved'; end if;

  insert into public.cost_obligation_retention_releases(
    organization_id, obligation_id, amount_minor_units, release_date, reason,
    milestone_id, released_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_obligation_id, p_amount_minor_units, p_release_date,
    trim(p_reason), p_milestone_id, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_RETENTION_RELEASED', 'cost_obligation',
          p_obligation_id, jsonb_build_object('release_id', v_id,
              'amount_minor_units', p_amount_minor_units, 'release_date', p_release_date));
  return v_id;
end $$;

-- ===========================================================================
-- 7. Payment approval hardening: disputes block payment; retention reduces
--    the payable ceiling until explicitly released.
-- ===========================================================================
create or replace function public.approve_cost_payment(
  p_organization_id uuid,
  p_payment_proposal_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_proposal public.cost_payment_proposals%rowtype;
  v_existing public.cost_payment_proposals%rowtype;
  v_obligation public.cost_obligations%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_hash text;
  v_paid numeric;
  v_retention bigint; v_released numeric; v_withheld bigint;
  v_available bigint;
  v_payment_id uuid;
  v_batch_id uuid;
  v_payable uuid;
  v_bank_cash uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  v_hash := encode(digest(p_payment_proposal_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':payment-approval:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.cost_payment_proposals
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id is distinct from p_payment_proposal_id
       or v_existing.approval_request_hash is distinct from v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    if v_existing.status = 'POSTED' then return v_existing.project_payment_id; end if;
  end if;

  select * into v_proposal from public.cost_payment_proposals
  where id = p_payment_proposal_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'payment proposal not found'; end if;
  if v_proposal.status = 'POSTED' then
    if v_proposal.approval_idempotency_key is not distinct from trim(p_idempotency_key)
       and v_proposal.approval_request_hash is not distinct from v_hash then
      return v_proposal.project_payment_id;
    end if;
    raise exception 'payment proposal is already posted';
  end if;
  if v_proposal.status <> 'PROPOSED' then raise exception 'payment proposal is not pending'; end if;
  if v_proposal.prepared_by = v_actor then
    raise exception 'maker/checker: payment preparer cannot approve';
  end if;

  select * into v_account from public.project_cash_accounts
  where id = v_proposal.cash_account_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'cash account not found'; end if;
  select * into v_obligation from public.cost_obligations
  where id = v_proposal.obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'AUTHORIZED' then
    raise exception 'payment requires an authorized obligation';
  end if;
  if not exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'COST_OBLIGATION' and jb.source_id = v_obligation.id
      and jb.organization_id = p_organization_id
      and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
  ) then raise exception 'obligation authorization is reversed; no further payments'; end if;
  if v_account.project_id is distinct from v_proposal.project_id
     or v_account.currency is distinct from v_proposal.currency
     or v_obligation.project_id is distinct from v_proposal.project_id
     or v_obligation.currency is distinct from v_proposal.currency then
    raise exception 'payment proposal scope or currency no longer coherent';
  end if;
  if exists (select 1 from public.accounting_periods p
             where p.organization_id = p_organization_id and p.project_id = v_proposal.project_id)
     and not exists (select 1 from public.accounting_periods p
                     where p.organization_id = p_organization_id and p.project_id = v_proposal.project_id
                       and p.status = 'OPEN' and v_proposal.payment_date between p.start_date and p.end_date) then
    raise exception 'no open accounting period covers payment date % for this project', v_proposal.payment_date;
  end if;

  -- F3: an open dispute blocks any payment on the obligation.
  if exists (
    select 1 from public.cost_obligation_disputes d
    where d.obligation_id = v_proposal.obligation_id
      and d.organization_id = p_organization_id
      and d.status = 'OPEN'
  ) then raise exception 'payment blocked: obligation is under an open dispute'; end if;

  -- F3: withheld retention narrows the payable ceiling until released.
  select coalesce(t.retention_minor_units, 0) into v_retention
  from public.cost_obligation_terms t
  where t.obligation_id = v_proposal.obligation_id;
  select coalesce(sum(r.amount_minor_units), 0) into v_released
  from public.cost_obligation_retention_releases r
  where r.obligation_id = v_proposal.obligation_id;
  v_withheld := greatest(v_retention - v_released::bigint, 0);

  select coalesce(sum(pp.amount_minor_units::numeric), 0) into v_paid
  from public.project_payments pp
  join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
  where pp.obligation_id = v_proposal.obligation_id and pp.organization_id = p_organization_id
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id);
  if v_paid + v_proposal.amount_minor_units::numeric
       > v_obligation.amount_minor_units::numeric - v_withheld::numeric then
    raise exception 'payment exceeds releasable payable (retention withheld)';
  end if;
  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if v_proposal.amount_minor_units > v_available then
    raise exception 'payment exceeds available cash';
  end if;

  update public.cost_payment_proposals
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
   where id = v_proposal.id;

  insert into public.project_payments(
    organization_id, project_id, obligation_id, cash_account_id,
    amount_minor_units, currency, payment_date, paid_by,
    idempotency_key, request_hash, payment_proposal_id
  ) values (
    p_organization_id, v_proposal.project_id, v_proposal.obligation_id,
    v_proposal.cash_account_id, v_proposal.amount_minor_units, v_proposal.currency,
    v_proposal.payment_date, v_actor,
    trim(p_idempotency_key), v_proposal.request_hash, v_proposal.id
  ) returning id into v_payment_id;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_bank_cash from public.semantic_accounts where role = 'BANK_CASH';
  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_proposal.project_id, 'PAYMENT', v_payment_id,
    v_proposal.payment_date, 'payment-batch-' || v_payment_id::text,
    v_proposal.request_hash, v_actor
  ) returning id into v_batch_id;
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_proposal.project_id, v_payable,
     v_proposal.amount_minor_units, 0, v_proposal.currency,
     null, v_proposal.obligation_id, v_obligation.party_id, v_proposal.payment_date),
    (v_batch_id, p_organization_id, v_proposal.project_id, v_bank_cash,
     0, v_proposal.amount_minor_units, v_proposal.currency,
     v_proposal.cash_account_id, null, null, v_proposal.payment_date);

  update public.cost_payment_proposals
     set status = 'POSTED', project_payment_id = v_payment_id
   where id = v_proposal.id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values
    (p_organization_id, v_actor, 'PAYMENT_PROPOSAL_APPROVED', 'cost_payment_proposal', v_proposal.id,
     jsonb_build_object('project_id', v_proposal.project_id, 'prepared_by', v_proposal.prepared_by,
       'approved_by', v_actor, 'project_payment_id', v_payment_id,
       'available_cash_minor_units_at_approval', v_available)),
    (p_organization_id, v_actor, 'PAYMENT_POSTED', 'project_payment', v_payment_id,
     jsonb_build_object('project_id', v_proposal.project_id, 'obligation_id', v_proposal.obligation_id,
       'cash_account_id', v_proposal.cash_account_id, 'payment_proposal_id', v_proposal.id,
       'journal_batch_id', v_batch_id, 'amount_minor_units', v_proposal.amount_minor_units,
       'currency', v_proposal.currency, 'payment_date', v_proposal.payment_date));
  return v_payment_id;
end $$;

-- ===========================================================================
-- 8. Read models
-- ===========================================================================

-- Due state per obligation: explicit terms -> computed due date; aging
-- buckets only for outstanding amounts; dispute/retention flags derived.
-- The computed due date is materialized in a subquery because PostgreSQL
-- resolves bare column names inside the SELECT list against the FROM
-- tables (terms.due_date), never against a sibling output alias.
create or replace view public.cost_obligation_due_read with (security_invoker=on) as
select
  d.*,
  d.computed_due_date as due_date,
  case
    when d.terms_id is null then 'NO_TERMS'
    when d.outstanding_minor_units::bigint <= 0 then 'SETTLED'
    when d.computed_due_date is null then 'NO_DUE_DATE'
    when d.computed_due_date < current_date then
      case
        when current_date - d.computed_due_date <= 30 then 'OVERDUE_1_30'
        when current_date - d.computed_due_date <= 60 then 'OVERDUE_31_60'
        when current_date - d.computed_due_date <= 90 then 'OVERDUE_61_90'
        else 'OVERDUE_90_PLUS'
      end
    when d.computed_due_date = current_date then 'DUE_TODAY'
    else 'NOT_DUE'
  end as aging_bucket,
  (current_date - d.computed_due_date) as days_overdue,
  (d.open_dispute_id is not null) as is_disputed,
  (d.open_dispute_id is not null) as payment_blocked,
  (d.outstanding_minor_units::bigint - (
    coalesce(d.retention_minor_units::bigint, 0)
    - coalesce(d.retention_released_minor_units::bigint, 0)
  ))::text as releasable_outstanding_minor_units
from (
  select
    o.id as obligation_id,
    o.organization_id,
    o.project_id,
    o.party_id,
    o.description,
    o.amount_minor_units::text as amount_minor_units,
    o.currency,
    o.transaction_date,
    o.cost_treatment,
    o.status,
    t.id as terms_id,
    t.terms_type,
    case
      when t.terms_type = 'FIXED_DATE' then t.due_date
      when t.terms_type = 'NET_DAYS' then o.transaction_date + t.net_days
      when t.terms_type = 'MILESTONE_SCHEDULE' then (
        select max(s.due_date) from public.cost_obligation_schedule_lines s
        where s.obligation_id = o.id and s.is_retention_line = false
      )
      else null
    end as computed_due_date,
    pos.outstanding_minor_units::text as outstanding_minor_units,
    pos.paid_minor_units::text as paid_minor_units,
    coalesce(pos.is_reversed, false) as is_reversed,
    d.id as open_dispute_id,
    coalesce(t.retention_minor_units, 0)::text as retention_minor_units,
    coalesce(rel.released_minor_units, 0)::text as retention_released_minor_units,
    (coalesce(t.retention_minor_units, 0)
      - coalesce(rel.released_minor_units, 0))::text as retention_remaining_minor_units
  from public.cost_obligations o
  left join public.cost_obligation_terms t on t.obligation_id = o.id
  left join public.cost_obligation_position_read pos on pos.obligation_id = o.id
  left join public.cost_obligation_disputes d
    on d.obligation_id = o.id and d.status = 'OPEN'
  left join (
    select obligation_id, sum(amount_minor_units) as released_minor_units
    from public.cost_obligation_retention_releases
    group by obligation_id
  ) rel on rel.obligation_id = o.id
) d;

-- Project-level aging summary: outstanding money per bucket plus dispute /
-- retention counters. Money grouped per currency; never summed across
-- currencies.
create or replace view public.cost_obligation_aging_read with (security_invoker=on) as
select
  due.organization_id,
  due.project_id,
  due.currency,
  due.aging_bucket,
  count(*) as obligation_count,
  sum(
    case when due.aging_bucket in ('OVERDUE_1_30','OVERDUE_31_60','OVERDUE_61_90','OVERDUE_90_PLUS')
         then due.outstanding_minor_units::bigint else 0 end
  )::text as overdue_outstanding_minor_units,
  sum(due.outstanding_minor_units::bigint)::text as total_outstanding_minor_units,
  coalesce(sum(due.retention_remaining_minor_units::bigint), 0)::text as retention_held_minor_units
from public.cost_obligation_due_read due
where due.status = 'AUTHORIZED' and due.is_reversed = false
group by due.organization_id, due.project_id, due.currency, due.aging_bucket;

-- Schedule lines joined with milestone identity for the management surface.
create or replace view public.cost_obligation_schedule_read with (security_invoker=on) as
select
  s.id as schedule_line_id,
  s.organization_id,
  o.project_id,
  s.obligation_id,
  s.line_number,
  s.due_date,
  s.amount_minor_units::text as amount_minor_units,
  s.milestone_id,
  m.code as milestone_code,
  m.label_ar as milestone_label_ar,
  m.status as milestone_status,
  s.is_retention_line,
  o.currency,
  o.description as obligation_description,
  o.status as obligation_status
from public.cost_obligation_schedule_lines s
join public.cost_obligations o on o.id = s.obligation_id
left join public.project_milestones m on m.id = s.milestone_id;

create or replace view public.project_milestones_read with (security_invoker=on) as
select
  m.id as milestone_id,
  m.organization_id,
  m.project_id,
  m.code,
  m.label_ar,
  m.planned_date,
  m.status,
  m.achieved_date,
  m.evidence_reference,
  m.created_by,
  m.created_at,
  (select count(*) from public.cost_obligation_schedule_lines s
   where s.milestone_id = m.id) as linked_schedule_lines
from public.project_milestones m;

create or replace view public.cost_obligation_retention_releases_read with (security_invoker=on) as
select
  r.id as release_id,
  r.organization_id,
  o.project_id,
  r.obligation_id,
  r.amount_minor_units::text as amount_minor_units,
  r.release_date,
  r.reason,
  r.milestone_id,
  r.released_by,
  r.released_at
from public.cost_obligation_retention_releases r
join public.cost_obligations o on o.id = r.obligation_id;

-- ===========================================================================
-- 9. RLS / privileges
-- ===========================================================================
alter table public.project_milestones enable row level security;
alter table public.project_milestones force row level security;
alter table public.cost_obligation_terms enable row level security;
alter table public.cost_obligation_terms force row level security;
alter table public.cost_obligation_schedule_lines enable row level security;
alter table public.cost_obligation_schedule_lines force row level security;
alter table public.cost_obligation_disputes enable row level security;
alter table public.cost_obligation_disputes force row level security;
alter table public.cost_obligation_retention_releases enable row level security;
alter table public.cost_obligation_retention_releases force row level security;

create policy project_milestones_read on public.project_milestones for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_obligation_terms_read on public.cost_obligation_terms for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_obligation_schedule_lines_read on public.cost_obligation_schedule_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_obligation_disputes_read on public.cost_obligation_disputes for select to authenticated
  using (public.is_active_member(organization_id));
create policy cost_obligation_retention_releases_read on public.cost_obligation_retention_releases for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.project_milestones, public.cost_obligation_terms,
  public.cost_obligation_schedule_lines, public.cost_obligation_disputes,
  public.cost_obligation_retention_releases from public, anon, authenticated;
grant select on public.project_milestones, public.cost_obligation_terms,
  public.cost_obligation_schedule_lines, public.cost_obligation_disputes,
  public.cost_obligation_retention_releases to authenticated;

grant select on public.cost_obligation_due_read, public.cost_obligation_aging_read,
  public.cost_obligation_schedule_read, public.project_milestones_read,
  public.cost_obligation_retention_releases_read to authenticated;

revoke all on function public.f3_create_project_milestone(uuid,uuid,text,text,date,text,text) from public, anon;
revoke all on function public.f3_achieve_project_milestone(uuid,uuid,date,text,text) from public, anon;
revoke all on function public.f3_set_obligation_terms(uuid,uuid,text,date,integer,bigint,text,text,text) from public, anon;
revoke all on function public.f3_open_obligation_dispute(uuid,uuid,text,text) from public, anon;
revoke all on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text) from public, anon;
revoke all on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text) from public, anon;
revoke all on function public.approve_cost_payment(uuid,uuid,text) from public, anon;

grant execute on function public.f3_create_project_milestone(uuid,uuid,text,text,date,text,text) to authenticated;
grant execute on function public.f3_achieve_project_milestone(uuid,uuid,date,text,text) to authenticated;
grant execute on function public.f3_set_obligation_terms(uuid,uuid,text,date,integer,bigint,text,text,text) to authenticated;
grant execute on function public.f3_open_obligation_dispute(uuid,uuid,text,text) to authenticated;
grant execute on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text) to authenticated;
grant execute on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text) to authenticated;
grant execute on function public.approve_cost_payment(uuid,uuid,text) to authenticated;
