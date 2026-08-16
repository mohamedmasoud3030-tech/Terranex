-- F5 — Approval Policy & Exception Engine.
--
-- A bounded, policy-driven approval/exception layer over the canonical
-- maker/checker + OWNER floors. This is NOT a generic rules engine:
--   * policy domains are a closed, typed set;
--   * the approver role is locked to OWNER — no policy can relax it;
--   * maker/checker segregation is a hard invariant — no policy can relax
--     it;
--   * the only direction a policy can move is stricter: requiring explicit
--     evidence for amounts at/above a threshold;
--   * exceptions follow the canonical pattern
--     violation -> exception -> evidence -> authority -> decision.
--
-- The exception registry unifies, for the first time, the three existing
-- exception families (procurement invoice tolerance, close-run gates, and
-- the new cross-domain approval exceptions) into one read surface.

-- ===========================================================================
-- 1. Approval policies (explicit org-level contract; canonical floors are
--    in the commands and are never relaxable)
-- ===========================================================================
create table public.approval_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  policy_domain text not null check (policy_domain in (
    'OBLIGATION_AUTHORIZATION',
    'PAYMENT_APPROVAL',
    'BUDGET_APPROVAL',
    'BUDGET_EXCEPTION',
    'RETAINAGE_RELEASE',
    'DISPUTE_RESOLUTION'
  )),
  threshold_minor_units bigint check (threshold_minor_units is null or threshold_minor_units > 0),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  evidence_required boolean not null default false,
  active boolean not null default true,
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);
-- One policy row per domain and currency scope (NULL currency = any).
create unique index approval_policies_domain_currency_key
  on public.approval_policies(organization_id, policy_domain, coalesce(currency, ''));
create index approval_policies_org_domain_idx
  on public.approval_policies(organization_id, policy_domain, active);

-- The canonical default (no explicit row): maker/checker + OWNER, no
-- evidence gate. A policy row only ever adds strictness.
create or replace function public.f5_policy_requires_evidence(
  p_organization_id uuid,
  p_domain text,
  p_amount_minor_units bigint,
  p_currency text
) returns boolean language sql stable set search_path=pg_catalog,public as $$
  select coalesce((
    select evidence_required
    from public.approval_policies p
    where p.organization_id = p_organization_id
      and p.policy_domain = p_domain
      and p.active
      and (p.currency is null or p.currency = p_currency)
      and (p.threshold_minor_units is null or p_amount_minor_units >= p.threshold_minor_units)
    order by p.currency is null, p.updated_at desc
    limit 1
  ), false);
$$;

create or replace function public.f5_set_approval_policy(
  p_organization_id uuid,
  p_policy_domain text,
  p_threshold_minor_units bigint,
  p_currency text,
  p_evidence_required boolean,
  p_active boolean,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_policy_domain not in (
    'OBLIGATION_AUTHORIZATION','PAYMENT_APPROVAL','BUDGET_APPROVAL',
    'BUDGET_EXCEPTION','RETAINAGE_RELEASE','DISPUTE_RESOLUTION'
  ) then raise exception 'unknown policy domain'; end if;
  if p_threshold_minor_units is not null and p_threshold_minor_units <= 0 then
    raise exception 'threshold must be positive when set';
  end if;
  if p_currency is not null and p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid policy currency';
  end if;

  insert into public.approval_policies(
    organization_id, policy_domain, threshold_minor_units, currency,
    evidence_required, active, updated_by
  ) values (
    p_organization_id, p_policy_domain, p_threshold_minor_units, p_currency,
    coalesce(p_evidence_required, false), coalesce(p_active, true), v_actor
  )
  on conflict (organization_id, policy_domain, coalesce(currency, ''))
  do update set
    threshold_minor_units = excluded.threshold_minor_units,
    evidence_required = excluded.evidence_required,
    active = excluded.active,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_POLICY_SET', 'approval_policy', v_id,
          jsonb_build_object('policy_domain', p_policy_domain,
                             'threshold_minor_units', p_threshold_minor_units,
                             'currency', p_currency,
                             'evidence_required', coalesce(p_evidence_required, false),
                             'active', coalesce(p_active, true)));
  return v_id;
end $$;

-- ===========================================================================
-- 2. Cross-domain approval exceptions registry
-- ===========================================================================
create table public.approval_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  exception_domain text not null check (exception_domain in (
    'BUDGET_CEILING',
    'PAYMENT_BLOCKED',
    'INVOICE_TOLERANCE',
    'CLOSE_GATE',
    'DISPUTE_HOLD',
    'OTHER_DISCLOSED'
  )),
  subject_type text not null check (subject_type in (
    'project_budget_line','cost_obligation','cost_payment_proposal',
    'supplier_invoice','close_run','project_milestone','none'
  )),
  subject_id uuid,
  amount_minor_units bigint check (amount_minor_units is null or amount_minor_units > 0),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500),
  status text not null default 'OPEN' check (status in ('OPEN','APPROVED','REJECTED','VOID')),
  opened_by uuid not null references auth.users(id) on delete restrict,
  opened_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  decision_note text
    check (decision_note is null or char_length(trim(decision_note)) between 3 and 1000),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  decide_idempotency_key text
    check (decide_idempotency_key is null or char_length(decide_idempotency_key) between 8 and 120),
  decide_request_hash text
    check (decide_request_hash is null or char_length(decide_request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint approval_exceptions_state_check check (
    (status = 'OPEN' and decided_by is null and decided_at is null and decision_note is null)
    or (status in ('APPROVED','REJECTED','VOID') and decided_by is not null
        and decided_at is not null and decision_note is not null)
  ),
  constraint approval_exceptions_maker_checker_check check (
    decided_by is null or decided_by <> opened_by
  )
);
create index approval_exceptions_project_status_idx
  on public.approval_exceptions(project_id, status);
create index approval_exceptions_subject_idx
  on public.approval_exceptions(subject_type, subject_id, status);
create unique index approval_exceptions_decide_key
  on public.approval_exceptions(organization_id, decide_idempotency_key)
  where decide_idempotency_key is not null;

create or replace function public.f5_guard_exception_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'approval exceptions are append-only';
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  -- UPDATE
  if old.status <> 'OPEN' and new.status is distinct from old.status then
    raise exception 'a decided exception cannot change its decision';
  end if;
  if old.id is distinct from new.id
     or old.organization_id is distinct from new.organization_id
     or old.project_id is distinct from new.project_id
     or old.exception_domain is distinct from new.exception_domain
     or old.subject_type is distinct from new.subject_type
     or old.subject_id is distinct from new.subject_id
     or old.amount_minor_units is distinct from new.amount_minor_units
     or old.reason is distinct from new.reason
     or old.opened_by is distinct from new.opened_by
     or old.opened_at is distinct from new.opened_at then
    raise exception 'approval exceptions are append-only';
  end if;
  return new;
end $$;
drop trigger if exists approval_exceptions_append_only on public.approval_exceptions;
create trigger approval_exceptions_append_only
before update or delete on public.approval_exceptions
for each row execute function public.f5_guard_exception_append_only();

-- 2.1 Open an exception (any active member).
create or replace function public.f5_open_approval_exception(
  p_organization_id uuid,
  p_project_id uuid,
  p_exception_domain text,
  p_subject_type text,
  p_subject_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_reason text,
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
  if p_exception_domain not in (
    'BUDGET_CEILING','PAYMENT_BLOCKED','INVOICE_TOLERANCE','CLOSE_GATE',
    'DISPUTE_HOLD','OTHER_DISCLOSED'
  ) then raise exception 'unknown exception domain'; end if;
  if p_subject_type not in (
    'project_budget_line','cost_obligation','cost_payment_proposal',
    'supplier_invoice','close_run','project_milestone','none'
  ) then raise exception 'unknown exception subject type'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 1000 then
    raise exception 'exception reason must be 3-1000 characters';
  end if;
  if p_subject_type <> 'none' and p_subject_id is null then
    raise exception 'exception subject id required';
  end if;
  if p_amount_minor_units is not null and p_amount_minor_units <= 0 then
    raise exception 'exception amount must be positive when set';
  end if;
  if p_currency is not null and p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid exception currency';
  end if;
  if not exists (select 1 from public.investment_projects
                 where id = p_project_id and organization_id = p_organization_id) then
    raise exception 'project not found';
  end if;

  select encode(digest(p_project_id::text || '|' || p_exception_domain || '|'
    || p_subject_type || '|' || coalesce(p_subject_id::text, '') || '|'
    || coalesce(p_amount_minor_units::text, '') || '|'
    || coalesce(p_currency, '') || '|' || trim(p_reason), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f5-exception:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.approval_exceptions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.approval_exceptions(
    organization_id, project_id, exception_domain, subject_type, subject_id,
    amount_minor_units, currency, reason, evidence_reference, opened_by,
    idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_exception_domain, p_subject_type,
    p_subject_id, p_amount_minor_units, p_currency, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_EXCEPTION_OPENED', 'approval_exception', v_id,
          jsonb_build_object('project_id', p_project_id,
                             'exception_domain', p_exception_domain,
                             'subject_type', p_subject_type,
                             'subject_id', p_subject_id));
  return v_id;
end $$;

-- 2.2 Decide an exception (OWNER; cannot be the opener; VOID is the
--     opener's withdrawal path).
create or replace function public.f5_decide_approval_exception(
  p_organization_id uuid,
  p_exception_id uuid,
  p_decision text,
  p_decision_note text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_exception record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_decision not in ('APPROVED','REJECTED','VOID') then
    raise exception 'decision must be APPROVED, REJECTED or VOID';
  end if;
  if p_decision_note is null or char_length(trim(p_decision_note)) not between 3 and 1000 then
    raise exception 'decision note must be 3-1000 characters';
  end if;
  v_hash := encode(digest(p_exception_id::text || '|' || p_decision || '|'
    || trim(p_decision_note), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f5-exception-decide:' || trim(p_idempotency_key), 0));
  select * into v_exception from public.approval_exceptions
  where id = p_exception_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'exception not found'; end if;
  if v_exception.status <> 'OPEN' then
    if v_exception.status = p_decision
       and v_exception.decision_note = trim(p_decision_note) then
      return v_exception.id;
    end if;
    raise exception 'exception is already decided';
  end if;
  if p_decision <> 'VOID' then
    perform public.s2_require_owner(p_organization_id);
    if v_exception.opened_by = v_actor then
      raise exception 'maker/checker: the exception opener cannot approve it';
    end if;
  elsif v_exception.opened_by <> v_actor and not public.s2_is_owner(p_organization_id) then
    raise exception 'forbidden: only the opener or the organization owner can void an exception';
  end if;

  update public.approval_exceptions
     set status = p_decision,
         decided_by = v_actor,
         decided_at = now(),
         decision_note = trim(p_decision_note),
         decide_idempotency_key = trim(p_idempotency_key),
         decide_request_hash = v_hash
   where id = p_exception_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_EXCEPTION_DECIDED', 'approval_exception',
          p_exception_id, jsonb_build_object('decision', p_decision));
  return p_exception_id;
end $$;

-- ===========================================================================
-- 3. Payment evidence gate support
-- ===========================================================================
alter table public.cost_payment_proposals
  add column evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500);

-- The R4 transition guard is extended (same two controlled transitions
-- plus one new one): a PROPOSED proposal may only change its
-- evidence_reference while it stays PROPOSED. Everything else remains
-- immutable exactly as before.
create or replace function public.r4_guard_payment_proposal_transition()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'payment proposal is immutable; do not delete it';
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.project_id is distinct from old.project_id
     or new.obligation_id is distinct from old.obligation_id
     or new.cash_account_id is distinct from old.cash_account_id
     or new.amount_minor_units is distinct from old.amount_minor_units
     or new.currency is distinct from old.currency
     or new.payment_date is distinct from old.payment_date
     or new.prepared_by is distinct from old.prepared_by
     or new.prepared_at is distinct from old.prepared_at
     or new.idempotency_key is distinct from old.idempotency_key
     or new.request_hash is distinct from old.request_hash
     or new.created_at is distinct from old.created_at then
    raise exception 'payment proposal commercial truth is immutable';
  end if;
  if old.status = 'PROPOSED' and new.status = 'APPROVED'
     and old.approved_by is null and new.approved_by is not null
     and old.approved_at is null and new.approved_at is not null
     and old.approval_idempotency_key is null and new.approval_idempotency_key is not null
     and old.approval_request_hash is null and new.approval_request_hash is not null
     and old.project_payment_id is null and new.project_payment_id is null then
    return new;
  end if;
  if old.status = 'APPROVED' and new.status = 'POSTED'
     and new.approved_by is not distinct from old.approved_by
     and new.approved_at is not distinct from old.approved_at
     and new.approval_idempotency_key is not distinct from old.approval_idempotency_key
     and new.approval_request_hash is not distinct from old.approval_request_hash
     and old.project_payment_id is null and new.project_payment_id is not null then
    return new;
  end if;
  -- F5: a PROPOSED proposal may attach/detach its evidence reference only.
  if old.status = 'PROPOSED' and new.status = 'PROPOSED'
     and new.evidence_reference is distinct from old.evidence_reference
     and new.approved_by is null and new.approved_at is null
     and new.approval_idempotency_key is null and new.approval_request_hash is null
     and new.project_payment_id is null then
    return new;
  end if;
  raise exception 'invalid payment proposal transition';
end $$;

create or replace function public.f5_attach_payment_evidence(
  p_organization_id uuid,
  p_payment_proposal_id uuid,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_proposal record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 500 then
    raise exception 'evidence reference must be 3-500 characters';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f5-payment-evidence:' || trim(p_idempotency_key), 0));
  select * into v_proposal from public.cost_payment_proposals
  where id = p_payment_proposal_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'payment proposal not found'; end if;
  if v_proposal.status <> 'PROPOSED' then
    raise exception 'evidence can only be attached to a proposed payment';
  end if;
  if v_proposal.prepared_by <> v_actor then
    raise exception 'only the payment preparer can attach evidence';
  end if;
  update public.cost_payment_proposals
     set evidence_reference = trim(p_evidence_reference)
   where id = p_payment_proposal_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_EVIDENCE_ATTACHED', 'cost_payment_proposal',
          p_payment_proposal_id, jsonb_build_object('evidence_reference', trim(p_evidence_reference)));
  return p_payment_proposal_id;
end $$;

-- ===========================================================================
-- 4. Policy enforcement wired into the canonical commands.
--    Each redefinition preserves the previous behavior exactly and adds
--    only the evidence gate from the active policy (default: no gate).
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

  -- F5: active approval policy may require explicit evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'OBLIGATION_AUTHORIZATION',
       v_obligation.amount_minor_units, v_obligation.currency) then
    if not exists (
      select 1 from public.cost_obligation_terms t
      where t.obligation_id = p_obligation_id
        and t.evidence_reference is not null
    ) then
      raise exception 'approval policy requires evidence for this obligation';
    end if;
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

    select coalesce(sum(e.amount_minor_units), 0) into v_exception_total
    from public.approval_exceptions e
    where e.organization_id = p_organization_id
      and e.project_id = v_obligation.project_id
      and e.exception_domain = 'BUDGET_CEILING'
      and e.subject_type = 'project_budget_line'
      and e.subject_id = v_budget_line.id
      and e.status = 'APPROVED';

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

  -- F5: active approval policy may require explicit evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'BUDGET_APPROVAL',
       coalesce((select sum(amount_minor_units) from public.project_budget_lines
                 where budget_id = p_budget_id), 0)::bigint,
       v_budget.currency) then
    if v_budget.evidence_reference is null then
      raise exception 'approval policy requires evidence for this budget';
    end if;
  end if;

  update public.project_budgets
     set status = 'APPROVED', approved_by = v_actor, approved_at = now()
   where id = p_budget_id and organization_id = p_organization_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_APPROVED', 'project_budget', p_budget_id,
          jsonb_build_object('project_id', v_budget.project_id, 'version', v_budget.version));
  return p_budget_id;
end $$;

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

  -- F5: active approval policy may require explicit evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'PAYMENT_APPROVAL',
       v_proposal.amount_minor_units, v_proposal.currency) then
    if v_proposal.evidence_reference is null then
      raise exception 'approval policy requires evidence for this payment';
    end if;
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
-- 5. Budget consumption read model (F4 deliverable placed here because it
--    joins the exception registry created in this migration)
--    Consumption is attributed to the currently APPROVED version of each
--    period range only; superseded versions keep their plan amounts in
--    project_budgets_read without double-counting consumption.
-- ===========================================================================
create or replace view public.project_budget_consumption_read with (security_invoker=on) as
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
  bl.id as budget_line_id,
  bl.cost_treatment,
  bl.amount_minor_units::text as budget_minor_units,
  coalesce(ob.obligations_minor_units, 0)::text as committed_obligations_minor_units,
  coalesce(pd.paid_minor_units, 0)::text as paid_minor_units,
  coalesce(exc.exception_minor_units, 0)::text as approved_exception_minor_units,
  (bl.amount_minor_units - coalesce(ob.obligations_minor_units, 0))::text
    as authorization_remaining_minor_units,
  (bl.amount_minor_units + coalesce(exc.exception_minor_units, 0)
    - coalesce(ob.obligations_minor_units, 0))::text as effective_remaining_minor_units,
  greatest(bl.amount_minor_units + coalesce(exc.exception_minor_units, 0),
           coalesce(ob.obligations_minor_units, 0))::text as forecast_final_minor_units
from public.project_budgets b
join public.project_budget_lines bl on bl.budget_id = b.id
left join (
  select o.cost_treatment, sum(o.amount_minor_units) as obligations_minor_units,
         b2.id as budget_id
  from public.cost_obligations o
  join public.project_budgets b2
    on b2.project_id = o.project_id
   and o.transaction_date between b2.period_start and b2.period_end
  where b2.status = 'APPROVED'
    and o.status = 'AUTHORIZED'
    and exists (
      select 1 from public.journal_batches jb
      where jb.source_type = 'COST_OBLIGATION' and jb.source_id = o.id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    )
  group by o.cost_treatment, b2.id
) ob on ob.budget_id = b.id and ob.cost_treatment = bl.cost_treatment
left join (
  select o.cost_treatment, b2.id as budget_id,
         sum(jl.debit_minor_units) as paid_minor_units
  from public.journal_batches jb
  join public.project_payments pp on pp.id = jb.source_id
  join public.cost_obligations o on o.id = pp.obligation_id
  join public.project_budgets b2
    on b2.project_id = o.project_id
   and b2.status = 'APPROVED'
   and jb.transaction_date between b2.period_start and b2.period_end
  join public.journal_lines jl on jl.batch_id = jb.id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'SUPPLIER_PAYABLE'
  where jb.source_type = 'PAYMENT'
    and jl.debit_minor_units > 0
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by o.cost_treatment, b2.id
) pd on pd.budget_id = b.id and pd.cost_treatment = bl.cost_treatment
left join (
  select subject_id as budget_line_id, sum(amount_minor_units) as exception_minor_units
  from public.approval_exceptions
  where exception_domain = 'BUDGET_CEILING'
    and subject_type = 'project_budget_line'
    and status = 'APPROVED'
  group by subject_id
) exc on exc.budget_line_id = bl.id
where b.status = 'APPROVED';

-- ===========================================================================
-- 6. Unified exception registry read model (all financial domains)
-- ===========================================================================
create or replace view public.approval_exception_registry_read with (security_invoker=on) as
select
  e.id as exception_id,
  e.organization_id,
  e.project_id,
  e.exception_domain as domain,
  e.subject_type,
  e.subject_id,
  e.exception_domain as exception_kind,
  e.amount_minor_units::text as amount_minor_units,
  e.currency,
  e.status,
  e.opened_by,
  e.opened_at,
  e.decided_by,
  e.decided_at,
  e.reason
from public.approval_exceptions e
union all
select
  i.id as exception_id,
  i.organization_id,
  i.project_id,
  'INVOICE_TOLERANCE'::text as domain,
  'supplier_invoice'::text as subject_type,
  i.supplier_invoice_id as subject_id,
  i.exception_type as exception_kind,
  (case when i.expected_minor_units is not null and i.actual_minor_units is not null
        then abs(i.actual_minor_units - i.expected_minor_units)
        else null end)::text as amount_minor_units,
  i.currency,
  i.status,
  i.created_by as opened_by,
  i.created_at as opened_at,
  i.approved_by as decided_by,
  i.approved_at as decided_at,
  i.reason
from public.procurement_invoice_exceptions i
union all
select
  c.id as exception_id,
  c.organization_id,
  cr.project_id,
  'CLOSE_GATE'::text as domain,
  'close_run'::text as subject_type,
  c.close_run_id as subject_id,
  c.gate_code as exception_kind,
  null::text as amount_minor_units,
  null::text as currency,
  c.status,
  c.requested_by as opened_by,
  c.requested_at as opened_at,
  c.approved_by as decided_by,
  c.approved_at as decided_at,
  c.reason
from public.close_run_exceptions c
join public.close_runs cr on cr.id = c.close_run_id;

create or replace view public.approval_policies_read with (security_invoker=on) as
select
  p.id as policy_id,
  p.organization_id,
  p.policy_domain,
  p.threshold_minor_units::text as threshold_minor_units,
  p.currency,
  p.evidence_required,
  p.active,
  p.updated_by,
  p.updated_at
from public.approval_policies p;

-- ===========================================================================
-- 6. RLS / privileges
-- ===========================================================================
alter table public.approval_policies enable row level security;
alter table public.approval_policies force row level security;
alter table public.approval_exceptions enable row level security;
alter table public.approval_exceptions force row level security;

create policy approval_policies_read on public.approval_policies for select to authenticated
  using (public.is_active_member(organization_id));
create policy approval_exceptions_read on public.approval_exceptions for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.approval_policies, public.approval_exceptions
  from public, anon, authenticated;
grant select on public.approval_policies, public.approval_exceptions to authenticated;
grant select on public.approval_exception_registry_read, public.approval_policies_read,
  public.project_budget_consumption_read to authenticated;
grant execute on function public.f5_policy_requires_evidence(uuid,text,bigint,text) to authenticated;

revoke all on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,text) from public, anon;
revoke all on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text) from public, anon;
revoke all on function public.f5_decide_approval_exception(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.f5_attach_payment_evidence(uuid,uuid,text,text) from public, anon;
revoke all on function public.authorize_cost_obligation(uuid,uuid,text) from public, anon;
revoke all on function public.f4_approve_project_budget(uuid,uuid,text) from public, anon;
revoke all on function public.approve_cost_payment(uuid,uuid,text) from public, anon;

grant execute on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,text) to authenticated;
grant execute on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text) to authenticated;
grant execute on function public.f5_decide_approval_exception(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.f5_attach_payment_evidence(uuid,uuid,text,text) to authenticated;
grant execute on function public.authorize_cost_obligation(uuid,uuid,text) to authenticated;
grant execute on function public.f4_approve_project_budget(uuid,uuid,text) to authenticated;
grant execute on function public.approve_cost_payment(uuid,uuid,text) to authenticated;
