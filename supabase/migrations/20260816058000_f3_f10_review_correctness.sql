-- F3–F10 review fixes — financial and operational correctness (P0/P1).
--
-- This migration addresses the audit findings against PR #147:
--   1. F9/F10 reversal netting: reversals and their reversed originals must
--      both be excluded, so the net effect of a corrected posting is zero.
--   2. F4 budget ceiling concurrency: a per-budget-line advisory lock
--      serializes check+post so parallel authorizations cannot overshoot.
--   3. F4 revision gap: while a REVISED successor is still DRAFT, the last
--      SUPERSEDED (previously approved) version keeps enforcing its ceiling.
--   4. F4 overlap race: budget approval serializes per project so the
--      non-overlap trigger check is race-free.
--   5. F5 budget exceptions: currency must match the budget currency; the
--      relief sum is filtered by currency.
--   6. F5 tiered approvals: explicit min_approvers policies (1-3 distinct
--      approvers, always OWNER) recorded in an append-only signoff ledger.
--   7. F5 reject/resubmit: REJECTED exceptions can be resubmitted as new
--      OPEN exceptions with a replaces link.
--   8. F5 evidence gates wired for BUDGET_EXCEPTION decisions, retention
--      releases (RETAINAGE_RELEASE) and dispute resolutions
--      (DISPUTE_RESOLUTION).
--   9. F5 VOID is a normal OWNER decision (opener can never decide).
--  10. F3 retention release requires the milestone to belong to the same
--      project as the obligation.
--  11. F3 MILESTONE_SCHEDULE becomes usable: f3_set_obligation_schedule RPC.
--  12. F7 dispute counters use the derived is_disputed flag; only PREPARED
--      close runs count as in-flight; a new OPEN_APPROVAL_EXCEPTIONS gate
--      blocks closing a period with open approval exceptions.
--  13. F8 removes the invented retention-due signal and adds source ids to
--      every signal so each one links to its authoritative subjects.
--  14. F6 adds f6_record_fx_conversion_by_snapshot so the UI never has to
--      restate currencies the snapshot already declares.

-- ===========================================================================
-- 1. F5 schema: tiered approvals, exception actionability, resubmit
-- ===========================================================================
alter table public.approval_policies
  add column min_approvers smallint not null default 1
    check (min_approvers between 1 and 3);

alter table public.approval_exceptions
  add column severity text not null default 'MEDIUM'
    check (severity in ('LOW','MEDIUM','HIGH','CRITICAL')),
  add column owner_id uuid references auth.users(id) on delete restrict,
  add column due_date date,
  add column replaces_exception_id uuid
    references public.approval_exceptions(id) on delete restrict;

create table public.approval_signoffs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  subject_type text not null check (subject_type in (
    'cost_obligation','project_budget','cost_payment_proposal','approval_exception'
  )),
  subject_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  tier smallint not null check (tier between 1 and 3),
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, subject_type, subject_id, actor_id)
);
create index approval_signoffs_subject_idx
  on public.approval_signoffs(organization_id, subject_type, subject_id);

create or replace function public.f5_guard_signoffs_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'approval signoffs are append-only';
end $$;
drop trigger if exists approval_signoffs_append_only on public.approval_signoffs;
create trigger approval_signoffs_append_only
before update or delete on public.approval_signoffs
for each row execute function public.f5_guard_signoffs_append_only();

-- Required distinct approvers for a domain+currency+amount under the active
-- policies (default: the canonical single-OWNER floor).
create or replace function public.f5_approval_required(
  p_organization_id uuid,
  p_domain text,
  p_amount_minor_units bigint,
  p_currency text
) returns smallint language sql stable set search_path=pg_catalog,public as $$
  select coalesce((
    select p.min_approvers
    from public.approval_policies p
    where p.organization_id = p_organization_id
      and p.policy_domain = p_domain
      and p.active
      and (p.currency is null or p.currency = coalesce(p_currency, ''))
      and (p.threshold_minor_units is null
           or (p_amount_minor_units is not null
               and p_amount_minor_units >= p.threshold_minor_units))
    order by p.currency is null, p.updated_at desc
    limit 1
  ), 1);
$$;

create or replace function public.f5_signoffs_count(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid
) returns integer language sql stable security definer set search_path=pg_catalog,public as $$
  select count(*)::integer
  from public.approval_signoffs s
  where s.organization_id = p_organization_id
    and s.subject_type = p_subject_type
    and s.subject_id = p_subject_id;
$$;

create or replace function public.f5_has_signed(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_actor_id uuid
) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select exists (
    select 1 from public.approval_signoffs s
    where s.organization_id = p_organization_id
      and s.subject_type = p_subject_type
      and s.subject_id = p_subject_id
      and s.actor_id = p_actor_id
  );
$$;

-- Records one signoff. Raises unless the caller is allowed to add a new
-- distinct approver below/at the required tier count.
create or replace function public.f5_record_signoff(
  p_organization_id uuid,
  p_domain text,
  p_amount_minor_units bigint,
  p_currency text,
  p_subject_type text,
  p_subject_id uuid,
  p_actor_id uuid
) returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_required smallint;
  v_recorded integer;
begin
  if public.f5_has_signed(p_organization_id, p_subject_type, p_subject_id, p_actor_id) then
    raise exception 'approver already signed; a different approver is required';
  end if;
  v_required := public.f5_approval_required(p_organization_id, p_domain,
    p_amount_minor_units, p_currency);
  v_recorded := public.f5_signoffs_count(p_organization_id, p_subject_type, p_subject_id);
  if v_recorded + 1 > v_required then
    raise exception 'tiered approval is already complete';
  end if;
  insert into public.approval_signoffs(
    organization_id, subject_type, subject_id, actor_id, tier
  ) values (
    p_organization_id, p_subject_type, p_subject_id, p_actor_id, v_recorded + 1
  );
  return v_recorded + 1;
end $$;

create or replace function public.f5_approval_complete(
  p_organization_id uuid,
  p_domain text,
  p_amount_minor_units bigint,
  p_currency text,
  p_subject_type text,
  p_subject_id uuid
) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
  select public.f5_signoffs_count(p_organization_id, p_subject_type, p_subject_id)
       >= public.f5_approval_required(p_organization_id, p_domain,
            p_amount_minor_units, p_currency);
$$;

-- ===========================================================================
-- 2. F3: retention release — evidence + project coherence + policy gate
-- ===========================================================================
alter table public.cost_obligation_retention_releases
  add column evidence_reference text
    check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 500);

create or replace function public.f3_release_obligation_retention(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_release_date date,
  p_reason text,
  p_milestone_id uuid,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid; v_status text;
  v_project uuid; v_currency text;
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
    || coalesce(p_milestone_id::text, '') || '|'
    || coalesce(nullif(trim(p_evidence_reference), ''), ''), 'sha256'), 'hex') into v_hash;

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

  select status, project_id, currency into v_status, v_project, v_currency
  from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if v_status is null then raise exception 'obligation not found'; end if;
  if v_status <> 'AUTHORIZED' then
    raise exception 'retention can only be released on an authorized obligation';
  end if;
  if p_milestone_id is not null and not exists (
    select 1 from public.project_milestones
    where id = p_milestone_id and organization_id = p_organization_id
      and project_id = v_project
      and status = 'ACHIEVED'
  ) then raise exception 'retention release milestone must be an achieved milestone of the same project'; end if;

  -- F5 policy: an active RETAINAGE_RELEASE policy may require evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'RETAINAGE_RELEASE', p_amount_minor_units, v_currency)
     and p_evidence_reference is null then
    raise exception 'approval policy requires evidence for this retention release';
  end if;

  insert into public.cost_obligation_retention_releases(
    organization_id, obligation_id, amount_minor_units, release_date, reason,
    milestone_id, evidence_reference, released_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_obligation_id, p_amount_minor_units, p_release_date,
    trim(p_reason), p_milestone_id, nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_RETENTION_RELEASED', 'cost_obligation',
          p_obligation_id, jsonb_build_object('release_id', v_id,
              'amount_minor_units', p_amount_minor_units, 'release_date', p_release_date));
  return v_id;
end $$;

-- Historical 7-argument signature kept as a thin wrapper (no evidence).
create or replace function public.f3_release_obligation_retention(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_release_date date,
  p_reason text,
  p_milestone_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  return public.f3_release_obligation_retention(
    p_organization_id, p_obligation_id, p_amount_minor_units, p_release_date,
    p_reason, p_milestone_id, null, p_idempotency_key);
end $$;

-- ===========================================================================
-- 3. F3: dispute resolution — evidence + policy gate
-- ===========================================================================
alter table public.cost_obligation_disputes
  add column resolution_evidence_reference text
    check (resolution_evidence_reference is null
        or char_length(trim(resolution_evidence_reference)) between 3 and 500);

create or replace function public.f3_resolve_obligation_dispute(
  p_organization_id uuid,
  p_dispute_id uuid,
  p_resolution_note text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_dispute record;
  v_amount bigint; v_currency text;
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

  select encode(digest(p_dispute_id::text || '|' || trim(p_resolution_note) || '|'
    || coalesce(nullif(trim(p_evidence_reference), ''), ''), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-dispute-resolve:' || trim(p_idempotency_key), 0));
  select * into v_dispute from public.cost_obligation_disputes
  where id = p_dispute_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'dispute not found'; end if;
  if v_dispute.status = 'RESOLVED' then
    if v_dispute.resolution_note = trim(p_resolution_note)
       and v_dispute.resolution_evidence_reference
           is not distinct from nullif(trim(p_evidence_reference), '') then
      return v_dispute.id;
    end if;
    raise exception 'dispute is already resolved';
  end if;
  if v_dispute.opened_by = v_actor then
    raise exception 'maker/checker: the dispute opener cannot resolve it';
  end if;

  select o.amount_minor_units, o.currency into v_amount, v_currency
  from public.cost_obligations o
  where o.id = v_dispute.obligation_id and o.organization_id = p_organization_id;
  if public.f5_policy_requires_evidence(
       p_organization_id, 'DISPUTE_RESOLUTION', v_amount, v_currency)
     and p_evidence_reference is null then
    raise exception 'approval policy requires evidence for this dispute resolution';
  end if;

  update public.cost_obligation_disputes
     set status = 'RESOLVED', resolved_by = v_actor, resolved_at = now(),
         resolution_note = trim(p_resolution_note),
         resolution_evidence_reference = nullif(trim(p_evidence_reference), '')
   where id = p_dispute_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_DISPUTE_RESOLVED', 'cost_obligation',
          v_dispute.obligation_id, jsonb_build_object('dispute_id', p_dispute_id));
  return p_dispute_id;
end $$;

-- Historical 4-argument signature kept as a thin wrapper (no evidence).
create or replace function public.f3_resolve_obligation_dispute(
  p_organization_id uuid,
  p_dispute_id uuid,
  p_resolution_note text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  return public.f3_resolve_obligation_dispute(
    p_organization_id, p_dispute_id, p_resolution_note, null, p_idempotency_key);
end $$;

-- ===========================================================================
-- 4. F3: obligation schedule RPC (MILESTONE_SCHEDULE becomes usable)
-- ===========================================================================
create or replace function public.f3_set_obligation_schedule(
  p_organization_id uuid,
  p_obligation_id uuid,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_obligation record;
  v_line record;
  v_declared_retention bigint;
  v_total numeric := 0;
  v_retention_total numeric := 0;
  v_line_numbers int[] := '{}';
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'schedule lines must be a JSON array';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f3-schedule:' || p_obligation_id::text, 0));
  select * into v_obligation from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.status <> 'DRAFT' then
    raise exception 'schedule lines can only be set while the obligation is a draft';
  end if;

  select coalesce(t.retention_minor_units, 0) into v_declared_retention
  from public.cost_obligation_terms t
  where t.obligation_id = p_obligation_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (v_line.value->>'line_number') is null
       or (v_line.value->>'line_number')::int not between 1 and 999 then
      raise exception 'schedule line number must be 1-999';
    end if;
    if v_line_numbers @> array[(v_line.value->>'line_number')::int] then
      raise exception 'duplicate schedule line number %', (v_line.value->>'line_number')::int;
    end if;
    v_line_numbers := v_line_numbers || (v_line.value->>'line_number')::int;
    if (v_line.value->>'amount_minor_units') is null
       or (v_line.value->>'amount_minor_units')::bigint <= 0 then
      raise exception 'schedule line amount must be positive';
    end if;
    if coalesce((v_line.value->>'is_retention_line'), 'false') not in ('true','false') then
      raise exception 'invalid retention line flag';
    end if;
    if (v_line.value->>'is_retention_line') = 'true' then
      if (v_line.value->>'milestone_id') is not null then
        raise exception 'a retention line cannot reference a milestone';
      end if;
      v_retention_total := v_retention_total + (v_line.value->>'amount_minor_units')::numeric;
    else
      v_total := v_total + (v_line.value->>'amount_minor_units')::numeric;
    end if;
    if (v_line.value->>'milestone_id') is not null
       and not exists (
         select 1 from public.project_milestones m
         where m.id = (v_line.value->>'milestone_id')::uuid
           and m.organization_id = p_organization_id
           and m.project_id = v_obligation.project_id
       ) then
      raise exception 'schedule milestone must belong to the same project';
    end if;
  end loop;

  if v_total > v_obligation.amount_minor_units::numeric then
    raise exception 'scheduled total exceeds the obligation amount';
  end if;
  if v_retention_total > v_declared_retention::numeric then
    raise exception 'scheduled retention exceeds the declared retention';
  end if;

  delete from public.cost_obligation_schedule_lines
  where obligation_id = p_obligation_id;

  insert into public.cost_obligation_schedule_lines(
    organization_id, obligation_id, line_number, due_date, amount_minor_units,
    milestone_id, is_retention_line, created_by
  )
  select p_organization_id, p_obligation_id,
         (l.value->>'line_number')::int,
         nullif(l.value->>'due_date', '')::date,
         (l.value->>'amount_minor_units')::bigint,
         nullif(l.value->>'milestone_id', '')::uuid,
         coalesce(l.value->>'is_retention_line', 'false') = 'true',
         v_actor
  from jsonb_array_elements(p_lines) l;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'OBLIGATION_SCHEDULE_SET', 'cost_obligation',
          p_obligation_id, jsonb_build_object('line_count', jsonb_array_length(p_lines)));
  return p_obligation_id;
end $$;

-- ===========================================================================
-- 5. F5: set approval policy — min_approvers support
-- ===========================================================================
create or replace function public.f5_set_approval_policy(
  p_organization_id uuid,
  p_policy_domain text,
  p_threshold_minor_units bigint,
  p_currency text,
  p_evidence_required boolean,
  p_active boolean,
  p_min_approvers smallint,
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
  if p_min_approvers is null or p_min_approvers not between 1 and 3 then
    raise exception 'min approvers must be 1-3';
  end if;

  insert into public.approval_policies(
    organization_id, policy_domain, threshold_minor_units, currency,
    evidence_required, active, min_approvers, updated_by
  ) values (
    p_organization_id, p_policy_domain, p_threshold_minor_units, p_currency,
    coalesce(p_evidence_required, false), coalesce(p_active, true),
    p_min_approvers, v_actor
  )
  on conflict (organization_id, policy_domain, coalesce(currency, ''))
  do update set
    threshold_minor_units = excluded.threshold_minor_units,
    evidence_required = excluded.evidence_required,
    active = excluded.active,
    min_approvers = excluded.min_approvers,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_POLICY_SET', 'approval_policy', v_id,
          jsonb_build_object('policy_domain', p_policy_domain,
                             'threshold_minor_units', p_threshold_minor_units,
                             'currency', p_currency,
                             'evidence_required', coalesce(p_evidence_required, false),
                             'active', coalesce(p_active, true),
                             'min_approvers', p_min_approvers));
  return v_id;
end $$;

-- Historical 7-argument signature (single approver) kept as a wrapper.
create or replace function public.f5_set_approval_policy(
  p_organization_id uuid,
  p_policy_domain text,
  p_threshold_minor_units bigint,
  p_currency text,
  p_evidence_required boolean,
  p_active boolean,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  return public.f5_set_approval_policy(
    p_organization_id, p_policy_domain, p_threshold_minor_units, p_currency,
    p_evidence_required, p_active, 1::smallint, p_idempotency_key);
end $$;

-- ===========================================================================
-- 6. F5: open exception — currency coherence + actionability fields
-- ===========================================================================
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
  p_severity text,
  p_owner_id uuid,
  p_due_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
  v_currency text; v_budget_currency text;
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
  if p_severity is null or p_severity not in ('LOW','MEDIUM','HIGH','CRITICAL') then
    raise exception 'invalid exception severity';
  end if;
  if not exists (select 1 from public.investment_projects
                 where id = p_project_id and organization_id = p_organization_id) then
    raise exception 'project not found';
  end if;

  v_currency := p_currency;
  if p_exception_domain = 'BUDGET_CEILING' and p_subject_type = 'project_budget_line'
     and p_subject_id is not null then
    select b.currency into v_budget_currency
    from public.project_budgets b
    join public.project_budget_lines bl on bl.budget_id = b.id
    where bl.id = p_subject_id and b.organization_id = p_organization_id;
    if v_budget_currency is null then
      raise exception 'budget line not found';
    end if;
    if p_currency is null then
      v_currency := v_budget_currency;
    elsif p_currency <> v_budget_currency then
      raise exception 'budget exception currency must match the budget currency';
    end if;
  end if;

  select encode(digest(p_project_id::text || '|' || p_exception_domain || '|'
    || p_subject_type || '|' || coalesce(p_subject_id::text, '') || '|'
    || coalesce(p_amount_minor_units::text, '') || '|'
    || coalesce(v_currency, '') || '|' || trim(p_reason) || '|'
    || coalesce(p_severity, '') || '|' || coalesce(p_due_date::text, ''), 'sha256'), 'hex')
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
    severity, owner_id, due_date, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_exception_domain, p_subject_type,
    p_subject_id, p_amount_minor_units, v_currency, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), v_actor,
    p_severity, coalesce(p_owner_id, v_actor), p_due_date,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_EXCEPTION_OPENED', 'approval_exception', v_id,
          jsonb_build_object('project_id', p_project_id,
                             'exception_domain', p_exception_domain,
                             'subject_type', p_subject_type,
                             'subject_id', p_subject_id,
                             'severity', p_severity));
  return v_id;
end $$;

-- Historical 10-argument signature kept as a wrapper.
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
begin
  return public.f5_open_approval_exception(
    p_organization_id, p_project_id, p_exception_domain, p_subject_type,
    p_subject_id, p_amount_minor_units, p_currency, p_reason,
    p_evidence_reference, 'MEDIUM', null, null, p_idempotency_key);
end $$;

-- ===========================================================================
-- 7. F5: decide exception — consistent VOID, evidence gate, tiered signoffs
-- ===========================================================================
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
  v_required smallint; v_recorded integer; v_tier integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
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
  if v_exception.opened_by = v_actor then
    raise exception 'maker/checker: the exception opener cannot decide it';
  end if;

  -- F5 policy: an active BUDGET_EXCEPTION policy may require evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'BUDGET_EXCEPTION',
       v_exception.amount_minor_units, v_exception.currency)
     and v_exception.evidence_reference is null then
    raise exception 'approval policy requires evidence for exception decisions';
  end if;

  v_required := public.f5_approval_required(p_organization_id, 'BUDGET_EXCEPTION',
    v_exception.amount_minor_units, v_exception.currency);
  v_recorded := public.f5_signoffs_count(p_organization_id, 'approval_exception', p_exception_id);
  if v_recorded + 1 < v_required then
    v_tier := public.f5_record_signoff(p_organization_id, 'BUDGET_EXCEPTION',
      v_exception.amount_minor_units, v_exception.currency,
      'approval_exception', p_exception_id, v_actor);
    insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
    values (p_organization_id, v_actor, 'APPROVAL_EXCEPTION_SIGNOFF', 'approval_exception',
            p_exception_id, jsonb_build_object('tier', v_tier, 'decision', p_decision));
    return p_exception_id;
  end if;

  perform public.f5_record_signoff(p_organization_id, 'BUDGET_EXCEPTION',
    v_exception.amount_minor_units, v_exception.currency,
    'approval_exception', p_exception_id, v_actor);

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
-- 8. F5: resubmit a REJECTED exception as a new OPEN exception
-- ===========================================================================
create or replace function public.f5_resubmit_exception(
  p_organization_id uuid,
  p_exception_id uuid,
  p_reason text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_exception record; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 1000 then
    raise exception 'resubmission reason must be 3-1000 characters';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f5-exception-resubmit:' || trim(p_idempotency_key), 0));
  select * into v_exception from public.approval_exceptions
  where id = p_exception_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'exception not found'; end if;
  if v_exception.status <> 'REJECTED' then
    raise exception 'only a rejected exception can be resubmitted';
  end if;

  insert into public.approval_exceptions(
    organization_id, project_id, exception_domain, subject_type, subject_id,
    amount_minor_units, currency, reason, evidence_reference, opened_by,
    severity, owner_id, due_date, replaces_exception_id, idempotency_key, request_hash
  ) values (
    p_organization_id, v_exception.project_id, v_exception.exception_domain,
    v_exception.subject_type, v_exception.subject_id,
    v_exception.amount_minor_units, v_exception.currency, trim(p_reason),
    nullif(trim(p_evidence_reference), ''), v_actor,
    v_exception.severity, v_exception.owner_id, v_exception.due_date,
    v_exception.id, trim(p_idempotency_key),
    encode(digest(p_exception_id::text || '|' || trim(p_reason), 'sha256'), 'hex')
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'APPROVAL_EXCEPTION_RESUBMITTED', 'approval_exception',
          v_id, jsonb_build_object('replaces_exception_id', v_exception.id));
  return v_id;
end $$;

-- ===========================================================================
-- 9. F4: budget approval — per-project serialization (overlap race) and
--    tiered signoffs with continuation
-- ===========================================================================
create or replace function public.f4_approve_project_budget(
  p_organization_id uuid,
  p_budget_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_budget public.project_budgets%rowtype;
  v_total bigint; v_required smallint; v_recorded integer; v_tier integer;
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

  -- Serialize all approvals of one project so the non-overlap trigger check
  -- is race-free.
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f4-budget-project-approve:' || v_budget.project_id::text, 0));

  select coalesce(sum(amount_minor_units), 0)::bigint into v_total
  from public.project_budget_lines where budget_id = p_budget_id;

  if v_budget.status = 'APPROVED' then
    -- Tiered continuation: an approved budget may receive further distinct
    -- approver signoffs while the policy requires them.
    v_required := public.f5_approval_required(p_organization_id, 'BUDGET_APPROVAL',
      v_total, v_budget.currency);
    v_recorded := public.f5_signoffs_count(p_organization_id, 'project_budget', p_budget_id);
    if v_recorded < v_required then
      if v_budget.prepared_by = v_actor then
        raise exception 'maker/checker: the budget preparer cannot approve it';
      end if;
      v_tier := public.f5_record_signoff(p_organization_id, 'BUDGET_APPROVAL',
        v_total, v_budget.currency, 'project_budget', p_budget_id, v_actor);
      insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
      values (p_organization_id, v_actor, 'BUDGET_APPROVAL_SIGNOFF', 'project_budget', p_budget_id,
              jsonb_build_object('tier', v_tier));
    end if;
    return v_budget.id;
  end if;
  if v_budget.status <> 'DRAFT' then
    raise exception 'only a draft budget can be approved';
  end if;
  if v_budget.prepared_by = v_actor then
    raise exception 'maker/checker: the budget preparer cannot approve it';
  end if;

  -- F5: active approval policy may require explicit evidence.
  if public.f5_policy_requires_evidence(
       p_organization_id, 'BUDGET_APPROVAL', v_total, v_budget.currency) then
    if v_budget.evidence_reference is null then
      raise exception 'approval policy requires evidence for this budget';
    end if;
  end if;

  v_required := public.f5_approval_required(p_organization_id, 'BUDGET_APPROVAL',
    v_total, v_budget.currency);
  v_recorded := public.f5_signoffs_count(p_organization_id, 'project_budget', p_budget_id);
  perform public.f5_record_signoff(p_organization_id, 'BUDGET_APPROVAL',
    v_total, v_budget.currency, 'project_budget', p_budget_id, v_actor);
  if v_recorded + 1 < v_required then
    insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
    values (p_organization_id, v_actor, 'BUDGET_APPROVAL_SIGNOFF', 'project_budget', p_budget_id,
            jsonb_build_object('tier', v_recorded + 1));
    return p_budget_id; -- stays DRAFT until the last signoff
  end if;

  update public.project_budgets
     set status = 'APPROVED', approved_by = v_actor, approved_at = now()
   where id = p_budget_id and organization_id = p_organization_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'BUDGET_APPROVED', 'project_budget', p_budget_id,
          jsonb_build_object('project_id', v_budget.project_id, 'version', v_budget.version));
  return p_budget_id;
end $$;

-- ===========================================================================
-- 10. F4: obligation authorization — budget-line concurrency lock,
--     SUPERSEDED-fallback ceiling, currency-filtered relief, tiered
--     signoffs with continuation
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
  v_required smallint; v_recorded integer; v_tier integer;
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

  -- Tiered continuation: an already-authorized obligation may receive
  -- further distinct approver signoffs while the policy requires them.
  if v_obligation.status = 'AUTHORIZED' then
    v_required := public.f5_approval_required(p_organization_id,
      'OBLIGATION_AUTHORIZATION', v_obligation.amount_minor_units, v_obligation.currency);
    v_recorded := public.f5_signoffs_count(p_organization_id, 'cost_obligation', p_obligation_id);
    if v_recorded < v_required then
      v_tier := public.f5_record_signoff(p_organization_id, 'OBLIGATION_AUTHORIZATION',
        v_obligation.amount_minor_units, v_obligation.currency,
        'cost_obligation', p_obligation_id, v_actor);
      insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
      values (p_organization_id, v_actor, 'OBLIGATION_AUTHORIZATION_SIGNOFF', 'cost_obligation',
              p_obligation_id, jsonb_build_object('tier', v_tier));
      select id into v_batch_id from public.journal_batches
      where source_type = 'COST_OBLIGATION' and source_id = p_obligation_id
        and organization_id = p_organization_id
        and reversal_of_batch_id is null
      order by posted_at desc limit 1;
      return v_batch_id;
    end if;
    raise exception 'only a draft obligation can be authorized';
  end if;
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

  -- F4 budget ceiling: the covering non-draft version enforces its line.
  -- A SUPERSEDED version (whose REVISED successor is still DRAFT) remains
  -- authoritative, so the ceiling never vanishes during a revision.
  select bl.*, b.period_start, b.period_end, b.currency as budget_currency
    into v_budget_line
  from public.project_budgets b
  join public.project_budget_lines bl on bl.budget_id = b.id
  where b.organization_id = p_organization_id
    and b.project_id = v_obligation.project_id
    and b.status in ('APPROVED','SUPERSEDED')
    and b.currency = v_obligation.currency
    and v_obligation.transaction_date between b.period_start and b.period_end
    and bl.cost_treatment = v_obligation.cost_treatment
  order by (b.status = 'APPROVED') desc, b.approved_at desc, b.version desc
  limit 1;

  if found then
    -- Serialize ceiling check+post per budget line: parallel authorizations
    -- cannot both pass the ceiling with stale committed sums.
    perform pg_advisory_xact_lock(hashtextextended(
      p_organization_id::text || ':f4-budget-line:' || v_budget_line.id::text, 0));

    select coalesce(sum(o.amount_minor_units), 0) into v_committed
    from public.cost_obligations o
    where o.organization_id = p_organization_id
      and o.project_id = v_obligation.project_id
      and o.status = 'AUTHORIZED'
      and o.cost_treatment = v_budget_line.cost_treatment
      and o.currency = v_budget_line.budget_currency
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
      and e.status = 'APPROVED'
      and e.currency = v_budget_line.budget_currency;

    if v_committed + v_obligation.amount_minor_units::numeric
         > v_budget_line.amount_minor_units::numeric + v_exception_total then
      raise exception 'budget ceiling exceeded for cost treatment %; an approved budget exception is required',
        v_budget_line.cost_treatment;
    end if;
  end if;

  -- Tiered approval signoff (final check before posting).
  v_required := public.f5_approval_required(p_organization_id,
    'OBLIGATION_AUTHORIZATION', v_obligation.amount_minor_units, v_obligation.currency);
  v_recorded := public.f5_signoffs_count(p_organization_id, 'cost_obligation', p_obligation_id);
  perform public.f5_record_signoff(p_organization_id, 'OBLIGATION_AUTHORIZATION',
    v_obligation.amount_minor_units, v_obligation.currency,
    'cost_obligation', p_obligation_id, v_actor);
  if v_recorded + 1 < v_required then
    insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
    values (p_organization_id, v_actor, 'OBLIGATION_AUTHORIZATION_SIGNOFF', 'cost_obligation',
            p_obligation_id, jsonb_build_object('tier', v_recorded + 1));
    return p_obligation_id; -- stays DRAFT until the last signoff
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
-- 11. F5/F3: payment approval — tiered signoffs with continuation
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
  v_required smallint; v_recorded integer; v_tier integer;
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

  -- Tiered approval: intermediate signoffs keep the proposal PROPOSED.
  v_required := public.f5_approval_required(p_organization_id, 'PAYMENT_APPROVAL',
    v_proposal.amount_minor_units, v_proposal.currency);
  v_recorded := public.f5_signoffs_count(p_organization_id, 'cost_payment_proposal',
    p_payment_proposal_id);
  if v_recorded + 1 < v_required then
    v_tier := public.f5_record_signoff(p_organization_id, 'PAYMENT_APPROVAL',
      v_proposal.amount_minor_units, v_proposal.currency,
      'cost_payment_proposal', p_payment_proposal_id, v_actor);
    insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
    values (p_organization_id, v_actor, 'PAYMENT_APPROVAL_SIGNOFF', 'cost_payment_proposal',
            p_payment_proposal_id, jsonb_build_object('tier', v_tier));
    return p_payment_proposal_id;
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
      and jb.reversal_of_batch_id is null
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

  perform public.f5_record_signoff(p_organization_id, 'PAYMENT_APPROVAL',
    v_proposal.amount_minor_units, v_proposal.currency,
    'cost_payment_proposal', p_payment_proposal_id, v_actor);

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
-- 12. F9: reversal netting — exclude reversal batches AND reversed originals
-- ===========================================================================
create or replace view public.project_financial_position_read with (security_invoker=on) as
with active_postings as (
  select jl.organization_id, jl.project_id, jl.account_id, sa.role,
         jl.debit_minor_units, jl.credit_minor_units, jl.currency
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb
      where rb.reversal_of_batch_id = jb.id
    )
),
by_role as (
  select organization_id, project_id, currency, role,
         sum(debit_minor_units) as debits,
         sum(credit_minor_units) as credits
  from active_postings
  group by organization_id, project_id, currency, role
),
positions as (
  select organization_id, project_id, currency,
    coalesce(sum(case when role = 'BANK_CASH' then debits - credits else 0 end), 0)
      as cash_balance_minor_units,
    coalesce(sum(case when role = 'CUSTOMER_RECEIVABLE' then debits - credits else 0 end), 0)
      as receivable_open_minor_units,
    coalesce(sum(case when role in (
      'REAL_ESTATE_SALE_REVENUE','AGRICULTURE_SALE_REVENUE','LIVESTOCK_SALE_REVENUE'
    ) then credits - debits else 0 end), 0) as revenue_recognized_minor_units,
    coalesce(sum(case when role = 'REAL_ESTATE_COST_OF_SALE' then debits - credits else 0 end), 0)
      as cost_of_sale_minor_units,
    coalesce(sum(case when role = 'PROJECT_EXPENSE' then debits - credits else 0 end), 0)
      as expense_posted_minor_units,
    coalesce(sum(case when role = 'DEVELOPMENT_WIP' then debits - credits else 0 end), 0)
      as wip_posted_minor_units,
    coalesce(sum(case when role = 'CONTRIBUTED_CAPITAL' then credits - debits else 0 end), 0)
      as contributions_received_minor_units
  from by_role
  group by organization_id, project_id, currency
),
payable as (
  select organization_id, project_id, currency,
    sum(outstanding_minor_units::bigint) as payable_open_minor_units,
    sum(paid_minor_units::bigint) as paid_minor_units,
    sum(retention_remaining_minor_units::bigint) as retention_held_minor_units,
    sum(retention_minor_units::bigint) as retention_declared_minor_units,
    count(*) filter (where is_disputed) as disputed_obligations,
    count(*) filter (where aging_bucket like 'OVERDUE%'
                          and outstanding_minor_units::bigint > 0)
      as overdue_obligations,
    sum(case when aging_bucket like 'OVERDUE%'
        then outstanding_minor_units::bigint else 0 end) as overdue_outstanding_minor_units
  from public.cost_obligation_due_read
  where status = 'AUTHORIZED' and is_reversed = false
  group by organization_id, project_id, currency
),
budget as (
  select organization_id, project_id, currency,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as budget_expense_minor_units,
    sum(budget_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as budget_wip_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as committed_expense_minor_units,
    sum(committed_obligations_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as committed_wip_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'EXPENSE')
      as available_expense_minor_units,
    sum(effective_remaining_minor_units::bigint) filter (where cost_treatment = 'CAPITALIZABLE_WIP')
      as available_wip_minor_units
  from public.project_budget_consumption_read
  group by organization_id, project_id, currency
)
select
  p.id as project_id,
  p.organization_id,
  p.name as project_name,
  p.sector,
  p.reporting_currency as currency,
  coalesce(pos.cash_balance_minor_units, 0)::text as cash_balance_minor_units,
  coalesce(pos.receivable_open_minor_units, 0)::text as receivable_open_minor_units,
  coalesce(pos.revenue_recognized_minor_units, 0)::text as revenue_recognized_minor_units,
  coalesce(pos.cost_of_sale_minor_units, 0)::text as cost_of_sale_minor_units,
  coalesce(pos.expense_posted_minor_units, 0)::text as expense_posted_minor_units,
  coalesce(pos.wip_posted_minor_units, 0)::text as wip_posted_minor_units,
  coalesce(pos.contributions_received_minor_units, 0)::text as contributions_received_minor_units,
  coalesce(py.payable_open_minor_units, 0)::text as payable_open_minor_units,
  coalesce(py.paid_minor_units, 0)::text as paid_minor_units,
  coalesce(py.retention_held_minor_units, 0)::text as retention_held_minor_units,
  coalesce(py.retention_declared_minor_units, 0)::text as retention_declared_minor_units,
  coalesce(py.disputed_obligations, 0) as disputed_obligations,
  coalesce(py.overdue_obligations, 0) as overdue_obligations,
  coalesce(py.overdue_outstanding_minor_units, 0)::text as overdue_outstanding_minor_units
from public.investment_projects p
left join positions pos
  on pos.project_id = p.id
 and pos.currency = p.reporting_currency
left join payable py
  on py.project_id = p.id
 and py.currency = p.reporting_currency
left join budget bg
  on bg.project_id = p.id
 and bg.currency = p.reporting_currency
where true
  and (pos.project_id is not null or py.project_id is not null
       or bg.project_id is not null
       or exists (select 1 from public.cost_obligations o where o.project_id = p.id)
       or exists (select 1 from public.project_budgets b
                  where b.project_id = p.id and b.status = 'APPROVED'));

-- ===========================================================================
-- 13. F7: period close health — correct dispute counters and in-flight set
-- ===========================================================================
create or replace view public.period_close_health_read with (security_invoker=on) as
with scope as (
  select distinct organization_id, project_id, reporting_currency
  from public.accounting_periods
),
open_period as (
  select organization_id, project_id, reporting_currency,
         id as open_period_id, start_date as open_period_start,
         end_date as open_period_end, version as open_period_version
  from public.accounting_periods
  where status = 'OPEN'
),
latest_closed as (
  select distinct on (organization_id, project_id, reporting_currency)
         organization_id, project_id, reporting_currency,
         id as last_closed_period_id, closed_at as last_closed_at,
         closed_by as last_closed_by, version as last_closed_version
  from public.accounting_periods
  where status = 'CLOSED'
  order by organization_id, project_id, reporting_currency, closed_at desc
),
in_flight as (
  select cr.organization_id, cr.project_id,
         count(*) filter (where cr.status = 'PREPARED') as open_close_runs,
         count(*) filter (where cr.status = 'APPROVED') as approved_close_runs
  from public.close_runs cr
  group by cr.organization_id, cr.project_id
),
open_exceptions as (
  select e.organization_id, cr.project_id, count(*) as open_close_exceptions
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id, count(*) as open_correction_requests
  from public.correction_requests
  where status = 'REQUESTED'
  group by organization_id, project_id
),
contract_state as (
  select d.organization_id, d.project_id,
         count(distinct case when d.is_disputed then d.obligation_id end)
           as open_disputes,
         count(distinct case when d.payment_blocked then d.obligation_id end)
           as payment_blocked_obligations,
         count(distinct case when d.status = 'AUTHORIZED'
            and d.aging_bucket like 'OVERDUE%'
            and d.outstanding_minor_units::bigint > 0 then d.obligation_id end)
           as overdue_obligations
  from public.cost_obligation_due_read d
  group by d.organization_id, d.project_id
)
select
  s.organization_id,
  s.project_id,
  s.reporting_currency,
  op.open_period_id,
  op.open_period_start,
  op.open_period_end,
  op.open_period_version,
  lc.last_closed_period_id,
  lc.last_closed_at,
  lc.last_closed_by,
  lc.last_closed_version,
  coalesce(inf.open_close_runs, 0) as open_close_runs,
  coalesce(inf.approved_close_runs, 0) as approved_close_runs,
  coalesce(oe.open_close_exceptions, 0) as open_close_exceptions,
  coalesce(oc.open_correction_requests, 0) as open_correction_requests,
  coalesce(cs.open_disputes, 0) as open_disputes,
  coalesce(cs.payment_blocked_obligations, 0) as payment_blocked_obligations,
  coalesce(cs.overdue_obligations, 0) as overdue_obligations,
  case
    when op.open_period_id is null then 'NO_OPEN_PERIOD'
    when coalesce(inf.open_close_runs, 0) > 0 then 'CLOSE_RUN_IN_FLIGHT'
    when coalesce(oc.open_correction_requests, 0) > 0 then 'CORRECTION_IN_FLIGHT'
    when coalesce(cs.overdue_obligations, 0) > 0 then 'OVERDUE_OBLIGATIONS'
    when coalesce(cs.open_disputes, 0) > 0 then 'OPEN_DISPUTES'
    else 'CLEAN'
  end as close_health
from scope s
left join open_period op
  on op.organization_id = s.organization_id and op.project_id = s.project_id
 and op.reporting_currency = s.reporting_currency
left join latest_closed lc
  on lc.organization_id = s.organization_id and lc.project_id = s.project_id
 and lc.reporting_currency = s.reporting_currency
left join in_flight inf
  on inf.organization_id = s.organization_id and inf.project_id = s.project_id
left join open_exceptions oe
  on oe.organization_id = s.organization_id and oe.project_id = s.project_id
left join open_corrections oc
  on oc.organization_id = s.organization_id and oc.project_id = s.project_id
left join contract_state cs
  on cs.organization_id = s.organization_id and cs.project_id = s.project_id;

-- ===========================================================================
-- 14. F7: OPEN_APPROVAL_EXCEPTIONS close gate
-- ===========================================================================
-- The gate evaluation chain is preserved exactly:
--   s6_evaluate_gate (authorization wrapper) -> s6_evaluate_gate_impl
--   (intercepts SECTOR_CUT_OFF / ASSET_SECTOR_ROLLFORWARDS /
--    OPEN_APPROVAL_EXCEPTIONS) -> s6_evaluate_gate_core (original evaluator).
-- Only the impl gains one new intercept; the wrapper and core stay untouched.

create or replace function public.s6_evaluate_gate_impl(
  p_organization_id uuid,
  p_project_id uuid,
  p_period_id uuid,
  p_gate_code text
) returns table(result text, detail text, evidence jsonb)
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_period record;
  v_open_exceptions bigint;
  v_mismatched bigint;
  v_batches bigint;
  v_assets bigint;
  v_phases bigint;
  v_milestones bigint;
  v_missing_asset_history bigint;
  v_missing_phase_history bigint;
  v_missing_milestone_history bigint;
  v_missing_total bigint;
begin
  if p_gate_code not in ('SECTOR_CUT_OFF', 'ASSET_SECTOR_ROLLFORWARDS',
     'OPEN_APPROVAL_EXCEPTIONS') then
    return query
      select g.result, g.detail, g.evidence
      from public.s6_evaluate_gate_core(
        p_organization_id,
        p_project_id,
        p_period_id,
        p_gate_code
      ) g;
    return;
  end if;

  if p_gate_code = 'OPEN_APPROVAL_EXCEPTIONS' then
    select count(*) into v_open_exceptions
    from public.approval_exceptions e
    where e.organization_id = p_organization_id
      and e.project_id = p_project_id
      and e.status = 'OPEN';
    if v_open_exceptions = 0 then
      return query select 'PASS'::text,
        'no open approval exceptions block close',
        jsonb_build_object('open_approval_exceptions', 0);
    else
      return query select 'FAIL'::text,
        format('%s open approval exceptions block close', v_open_exceptions),
        jsonb_build_object('open_approval_exceptions', v_open_exceptions);
    end if;
    return;
  end if;

  select * into v_period
  from public.accounting_periods p
  where p.id = p_period_id
    and p.organization_id = p_organization_id
    and p.project_id = p_project_id;

  if not found then
    raise exception 'period not found for this project';
  end if;

  if p_gate_code = 'SECTOR_CUT_OFF' then
    -- A batch in another period is not a cut-off failure for this close.
    -- The material failure is a header/line mismatch that makes a posting
    -- straddle this period boundary or claim the wrong project.
    select count(*) into v_mismatched
    from public.journal_batches jb
    join public.journal_lines jl
      on jl.batch_id = jb.id
     and jl.organization_id = jb.organization_id
    where jb.organization_id = p_organization_id
      and jb.project_id = p_project_id
      and (
        jb.transaction_date between v_period.start_date and v_period.end_date
        or jl.transaction_date between v_period.start_date and v_period.end_date
      )
      and (
        jl.project_id <> jb.project_id
        or jl.transaction_date <> jb.transaction_date
      );

    select count(*) into v_batches
    from public.journal_batches jb
    where jb.organization_id = p_organization_id
      and jb.project_id = p_project_id
      and jb.transaction_date between v_period.start_date and v_period.end_date;

    if v_mismatched = 0 then
      return query select
        'PASS'::text,
        format('%s batch(es) belong to this period and none straddle the cut-off', v_batches),
        jsonb_build_object(
          'batches_in_cut_off', v_batches,
          'header_line_date_mismatches', 0,
          'scope', 'current_period_only'
        );
    else
      return query select
        'FAIL'::text,
        format('%s journal line(s) straddle the period cut-off because header and line dates disagree', v_mismatched),
        jsonb_build_object(
          'batches_in_cut_off', v_batches,
          'header_line_date_mismatches', v_mismatched,
          'scope', 'current_period_only'
        );
    end if;
    return;
  end if;

  -- ASSET_SECTOR_ROLLFORWARDS
  -- S3 stores operational state as append-only history. A CANDIDATE,
  -- DUE_DILIGENCE or ACQUIRING asset is a valid business state and does not
  -- by itself block financial close. What close must prove is that every
  -- sector object has the authoritative history required to reproduce its
  -- current state.
  select count(*) into v_assets
  from public.property_assets a
  where a.organization_id = p_organization_id
    and a.project_id = p_project_id;

  select count(*) into v_missing_asset_history
  from public.property_assets a
  where a.organization_id = p_organization_id
    and a.project_id = p_project_id
    and not exists (
      select 1
      from public.property_asset_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.property_asset_id = a.id
    );

  select count(*) into v_phases
  from public.development_phases p
  where p.organization_id = p_organization_id
    and p.project_id = p_project_id;

  select count(*) into v_missing_phase_history
  from public.development_phases p
  where p.organization_id = p_organization_id
    and p.project_id = p_project_id
    and not exists (
      select 1
      from public.development_phase_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.phase_id = p.id
    );

  select count(*) into v_milestones
  from public.development_milestones m
  where m.organization_id = p_organization_id
    and m.project_id = p_project_id;

  select count(*) into v_missing_milestone_history
  from public.development_milestones m
  where m.organization_id = p_organization_id
    and m.project_id = p_project_id
    and not exists (
      select 1
      from public.development_milestone_state_history h
      where h.organization_id = p_organization_id
        and h.project_id = p_project_id
        and h.milestone_id = m.id
    );

  v_missing_total := v_missing_asset_history
    + v_missing_phase_history
    + v_missing_milestone_history;

  if v_missing_total = 0 then
    return query select
      'PASS'::text,
      format(
        'sector rollforward reconciles from append-only history: %s asset(s), %s phase(s), %s milestone(s)',
        v_assets, v_phases, v_milestones
      ),
      jsonb_build_object(
        'assets', v_assets,
        'phases', v_phases,
        'milestones', v_milestones,
        'missing_asset_history', 0,
        'missing_phase_history', 0,
        'missing_milestone_history', 0,
        'open_operational_states_allowed', true
      );
  else
    return query select
      'FAIL'::text,
      format('%s sector object(s) cannot be reproduced from authoritative state history', v_missing_total),
      jsonb_build_object(
        'assets', v_assets,
        'phases', v_phases,
        'milestones', v_milestones,
        'missing_asset_history', v_missing_asset_history,
        'missing_phase_history', v_missing_phase_history,
        'missing_milestone_history', v_missing_milestone_history
      );
  end if;
end $$;

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
    'PARTNER_CAPITAL_ROLLFORWARD',
    'OPEN_APPROVAL_EXCEPTIONS'
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

-- ===========================================================================
-- 14b. Unified exception registry — actionability columns exposed
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
  e.reason,
  e.severity,
  e.owner_id,
  e.due_date,
  e.replaces_exception_id
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
  i.reason,
  'MEDIUM'::text as severity,
  i.created_by as owner_id,
  null::date as due_date,
  null::uuid as replaces_exception_id
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
  c.reason,
  'MEDIUM'::text as severity,
  c.requested_by as owner_id,
  null::date as due_date,
  null::uuid as replaces_exception_id
from public.close_run_exceptions c
join public.close_runs cr on cr.id = c.close_run_id;

-- ===========================================================================
-- 15. F8: integrity signals without invented facts, with source ids
-- ===========================================================================
create or replace view public.financial_integrity_signals_read with (security_invoker=on) as
with unbalanced as (
  select jb.organization_id, jb.project_id,
         'UNBALANCED_BATCHES'::text as signal_code,
         'قيد غير متوازن (دين ≠ دائن)'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(jb.id) as source_ids
  from public.journal_batches jb
  join public.journal_lines jl on jl.batch_id = jb.id
  group by jb.organization_id, jb.project_id, jb.id
  having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units)
),
overdue as (
  select organization_id, project_id,
         'OVERDUE_OBLIGATIONS'::text as signal_code,
         'التزامات مستحقة متأخرة السداد'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(outstanding_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(obligation_id) as source_ids
  from public.cost_obligation_due_read
  where status = 'AUTHORIZED'
    and is_reversed = false
    and aging_bucket like 'OVERDUE%'
    and outstanding_minor_units::bigint > 0
  group by organization_id, project_id, currency
),
disputes as (
  select d.organization_id, o.project_id,
         'OPEN_DISPUTES'::text as signal_code,
         'نزاعات مفتوحة على التزامات'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(o.id) as source_ids
  from public.cost_obligation_disputes d
  join public.cost_obligations o on o.id = d.obligation_id
  where d.status = 'OPEN'
  group by d.organization_id, o.project_id
),
unreconciled_payments as (
  select organization_id, project_id,
         'UNRECONCILED_PAYMENTS'::text as signal_code,
         'مدفوعات غير مطابقة بكشف البنك'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(payment_id) as source_ids
  from public.payment_status_read
  where is_reversed = false and is_reconciled = false
  group by organization_id, project_id, currency
),
unmatched_statements as (
  select organization_id, project_id,
         'UNMATCHED_STATEMENT_LINES'::text as signal_code,
         'سطور كشف بنك غير مطابقة'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units::bigint)::text as amount_minor_units,
         currency,
         array_agg(line_id) as source_ids
  from public.bank_statement_line_status_read
  where is_reconciled = false
  group by organization_id, project_id, currency
),
open_budget_exceptions as (
  select organization_id, project_id,
         'OPEN_BUDGET_EXCEPTIONS'::text as signal_code,
         'استثناءات موازنة بانتظار القرار'::text as signal_label_ar,
         'CRITICAL'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units)::text as amount_minor_units,
         currency,
         array_agg(id) as source_ids
  from public.approval_exceptions
  where status = 'OPEN' and exception_domain = 'BUDGET_CEILING'
  group by organization_id, project_id, currency
),
open_invoice_exceptions as (
  select organization_id, project_id,
         'OPEN_INVOICE_EXCEPTIONS'::text as signal_code,
         'استثناءات فواتير موردين بانتظار القرار'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(id) as source_ids
  from public.procurement_invoice_exceptions
  where status = 'OPEN'
  group by organization_id, project_id
),
open_close_exceptions as (
  select e.organization_id, cr.project_id,
         'OPEN_CLOSE_EXCEPTIONS'::text as signal_code,
         'استثناءات إقفال فترة بانتظار القرار'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(e.id) as source_ids
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id,
         'OPEN_CORRECTION_REQUESTS'::text as signal_code,
         'طلبات تصحيح بانتظار المراجعة'::text as signal_label_ar,
         'WARNING'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(id) as source_ids
  from public.correction_requests
  where status = 'REQUESTED'
  group by organization_id, project_id
),
stale_drafts as (
  select organization_id, project_id,
         'STALE_DRAFT_OBLIGATIONS'::text as signal_code,
         'التزامات مسودة قديمة بلا قرار'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         sum(amount_minor_units)::text as amount_minor_units,
         currency,
         array_agg(id) as source_ids
  from public.cost_obligations
  where status = 'DRAFT' and created_at < now() - interval '30 days'
  group by organization_id, project_id, currency
),
no_budget as (
  select o.organization_id, o.project_id,
         'NO_APPROVED_BUDGET'::text as signal_code,
         'نشاط مالي بدون موازنة معتمدة'::text as signal_label_ar,
         'INFO'::text as severity,
         count(distinct o.id) as subject_count,
         null::text as amount_minor_units, null::text as currency,
         array_agg(distinct o.id) as source_ids
  from public.cost_obligations o
  where o.status = 'AUTHORIZED'
    and not exists (
      select 1 from public.project_budgets b
      where b.project_id = o.project_id
        and b.organization_id = o.organization_id
        and b.status = 'APPROVED'
    )
  group by o.organization_id, o.project_id
),
near_ceiling as (
  select organization_id, project_id,
         'BUDGET_NEAR_CEILING'::text as signal_code,
         'استهلاك الموازنة قرب السقف (٩٠٪+)'::text as signal_label_ar,
         'INFO'::text as severity,
         count(*) as subject_count,
         null::text as amount_minor_units, currency,
         array_agg(budget_line_id) as source_ids
  from public.project_budget_consumption_read
  where budget_minor_units::bigint > 0
    and (committed_obligations_minor_units::bigint * 100)
        >= (budget_minor_units::bigint * 90)
  group by organization_id, project_id, currency
),
fx_gap as (
  select o.id as organization_id, null::uuid as project_id,
         'ORG_FX_GAP'::text as signal_code,
         'عملة تقارير معلنة بدون سعر صرف مسجل'::text as signal_label_ar,
         'INFO'::text as severity,
         count(distinct p.id) as subject_count,
         null::text as amount_minor_units,
         o.reporting_currency as currency,
         array_agg(distinct p.id) as source_ids
  from public.organizations o
  join public.investment_projects p
    on p.organization_id = o.id
   and p.reporting_currency is distinct from o.reporting_currency
  where o.reporting_currency is not null
    and not exists (
      select 1 from public.fx_rate_snapshots s
      where s.organization_id = o.id
        and s.base_currency = p.reporting_currency
        and s.quote_currency = o.reporting_currency
        and s.rate_date <= current_date
    )
  group by o.id, o.reporting_currency
)
select * from unbalanced
union all select * from overdue
union all select * from disputes
union all select * from unreconciled_payments
union all select * from unmatched_statements
union all select * from open_budget_exceptions
union all select * from open_invoice_exceptions
union all select * from open_close_exceptions
union all select * from open_corrections
union all select * from stale_drafts
union all select * from no_budget
union all select * from near_ceiling
union all select * from fx_gap;

-- ===========================================================================
-- 16. F6: conversion by snapshot (currencies derived from the snapshot)
-- ===========================================================================
create or replace function public.f6_record_fx_conversion_by_snapshot(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_amount_minor_units bigint,
  p_rate_snapshot_id uuid,
  p_conversion_date date,
  p_purpose text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
  v_snapshot public.fx_rate_snapshots%rowtype;
  v_converted bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_source_amount_minor_units is null or p_source_amount_minor_units <= 0 then
    raise exception 'conversion amount must be positive';
  end if;
  if p_conversion_date is null then raise exception 'conversion date required'; end if;
  if p_purpose not in ('REPORTING_ROLLUP','DISCLOSURE','RECONCILIATION') then
    raise exception 'purpose must be REPORTING_ROLLUP, DISCLOSURE or RECONCILIATION';
  end if;
  if p_project_id is not null and not exists (
    select 1 from public.investment_projects
    where id = p_project_id and organization_id = p_organization_id
  ) then raise exception 'project not found'; end if;

  select * into v_snapshot from public.fx_rate_snapshots
  where id = p_rate_snapshot_id and organization_id = p_organization_id;
  if not found then raise exception 'rate snapshot not found'; end if;
  if v_snapshot.rate_date > p_conversion_date then
    raise exception 'rate snapshot date cannot be after the conversion date';
  end if;
  v_converted := public.fx_convert_exact(
    p_source_amount_minor_units, v_snapshot.rate_numerator, v_snapshot.rate_denominator);

  select encode(digest(coalesce(p_project_id::text, '') || '|'
    || p_source_amount_minor_units::text || '|'
    || v_snapshot.base_currency || '|' || v_snapshot.quote_currency || '|'
    || p_rate_snapshot_id::text || '|'
    || p_conversion_date::text || '|' || p_purpose, 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f6-fx-conversion:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.fx_conversion_log
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.fx_conversion_log(
    organization_id, project_id, source_amount_minor_units, source_currency,
    target_currency, rate_snapshot_id, converted_amount_minor_units,
    conversion_date, purpose, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_source_amount_minor_units,
    v_snapshot.base_currency, v_snapshot.quote_currency, p_rate_snapshot_id,
    v_converted, p_conversion_date, p_purpose, v_actor,
    trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'FX_CONVERSION_RECORDED', 'fx_conversion_log', v_id,
          jsonb_build_object('source_amount_minor_units', p_source_amount_minor_units,
                             'source_currency', v_snapshot.base_currency,
                             'target_currency', v_snapshot.quote_currency,
                             'converted_amount_minor_units', v_converted,
                             'rate_snapshot_id', p_rate_snapshot_id));
  return v_id;
end $$;

-- ===========================================================================
-- 17. RLS / privileges for the new surface
-- ===========================================================================
alter table public.approval_signoffs enable row level security;
alter table public.approval_signoffs force row level security;
create policy approval_signoffs_read on public.approval_signoffs for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.approval_signoffs from public, anon, authenticated;
grant select on public.approval_signoffs to authenticated;

grant execute on function public.f5_approval_required(uuid,text,bigint,text) to authenticated;
grant execute on function public.f5_signoffs_count(uuid,text,uuid) to authenticated;
grant execute on function public.f5_has_signed(uuid,text,uuid,uuid) to authenticated;
grant execute on function public.f5_approval_complete(uuid,text,bigint,text,text,uuid) to authenticated;
revoke all on function public.f5_record_signoff(uuid,text,bigint,text,text,uuid,uuid) from public, anon;
grant execute on function public.f5_record_signoff(uuid,text,bigint,text,text,uuid,uuid) to authenticated;

revoke all on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,smallint,text) from public, anon;
grant execute on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,smallint,text) to authenticated;
revoke all on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,text) from public, anon;
grant execute on function public.f5_set_approval_policy(uuid,text,bigint,text,boolean,boolean,text) to authenticated;

revoke all on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text,uuid,date,text) from public, anon;
grant execute on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text,uuid,date,text) to authenticated;
revoke all on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text) from public, anon;
grant execute on function public.f5_open_approval_exception(uuid,uuid,text,text,uuid,bigint,text,text,text,text) to authenticated;

revoke all on function public.f5_resubmit_exception(uuid,uuid,text,text,text) from public, anon;
grant execute on function public.f5_resubmit_exception(uuid,uuid,text,text,text) to authenticated;

revoke all on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text,text) from public, anon;
grant execute on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text,text) to authenticated;
revoke all on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text) from public, anon;
grant execute on function public.f3_release_obligation_retention(uuid,uuid,bigint,date,text,uuid,text) to authenticated;

revoke all on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text,text) from public, anon;
grant execute on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text,text) to authenticated;
revoke all on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text) from public, anon;
grant execute on function public.f3_resolve_obligation_dispute(uuid,uuid,text,text) to authenticated;

revoke all on function public.f3_set_obligation_schedule(uuid,uuid,jsonb,text) from public, anon;
grant execute on function public.f3_set_obligation_schedule(uuid,uuid,jsonb,text) to authenticated;

revoke all on function public.f6_record_fx_conversion_by_snapshot(uuid,uuid,bigint,uuid,date,text,text) from public, anon;
grant execute on function public.f6_record_fx_conversion_by_snapshot(uuid,uuid,bigint,uuid,date,text,text) to authenticated;

revoke all on function public.f4_approve_project_budget(uuid,uuid,text) from public, anon;
grant execute on function public.f4_approve_project_budget(uuid,uuid,text) to authenticated;
revoke all on function public.authorize_cost_obligation(uuid,uuid,text) from public, anon;
grant execute on function public.authorize_cost_obligation(uuid,uuid,text) to authenticated;
revoke all on function public.approve_cost_payment(uuid,uuid,text) from public, anon;
grant execute on function public.approve_cost_payment(uuid,uuid,text) to authenticated;
revoke all on function public.f5_decide_approval_exception(uuid,uuid,text,text,text) from public, anon;
grant execute on function public.f5_decide_approval_exception(uuid,uuid,text,text,text) to authenticated;
revoke all on function public.s6_evaluate_gate(uuid,uuid,uuid,text) from public, anon;
grant execute on function public.s6_evaluate_gate(uuid,uuid,uuid,text) to authenticated;
revoke all on function public.s6_prepare_close_run(uuid,uuid,uuid,text) from public, anon;
grant execute on function public.s6_prepare_close_run(uuid,uuid,uuid,text) to authenticated;
