-- H1 — Project cost classification (ADR 0034 §3).
--
-- WHY THIS EXISTS
--   The management operating result must be able to distinguish:
--     (a) cost the operator has attributed to an operating unit;
--     (b) cost the operator declares to be project/farm/site overhead;
--     (c) cost the operator declares to be outside the management result;
--     (d) eligible cost that has not been classified yet.
--   Without this axis, any remainder is ambiguous: a perfectly classified project
--   with genuine overhead would report incomplete coverage forever.
--
-- WHY A NEW FACT WAS NECESSARY (ADR 0034 §3.2)
--   No existing column expresses attributability:
--     * cost_obligations.cost_treatment is an ACCOUNTING treatment
--       (EXPENSE | CAPITALIZABLE_WIP), not an attributability state;
--     * *_cost_attributions.cost_category / property_cost_items.cost_category is a
--       DESTINATION category recorded only once attribution has already happened, so
--       its absence is precisely the quantity being measured.
--   This migration therefore adds the minimum new authoritative fact: the operator's
--   own assertion about a cost they have chosen NOT to attribute.
--
-- WHAT THIS MIGRATION DOES NOT DO
--   * It does not duplicate, replace or generalise any sector attribution table.
--     Crop cycles, livestock cohorts and property assets remain the sole owners of
--     "which operating unit consumed this cost".
--   * It does not create a rules engine, a configurable policy, or a guessed default.
--     The residual state is UNCLASSIFIED and is never silently treated as overhead.
--
-- Immutability: rows are append-only. A classification is withdrawn by recording a
-- reversal row, exactly like crop_cycle_cost_attributions / livestock_cohort_cost_attributions.

-- ===========================================================================
-- 1. Authoritative operator assertion
-- ===========================================================================
create table public.project_cost_classifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  cost_obligation_id uuid not null,
  classification text not null
    check (classification in ('PROJECT_OVERHEAD','EXCLUDED_FROM_MANAGEMENT_RESULT')),
  -- A mandatory reason is the guard that stops EXCLUDED from becoming an
  -- unaccountable escape hatch. Mirrors property_cost_items.policy_reference.
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  reversal_of_classification_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  unique (reversal_of_classification_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (cost_obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict,
  foreign key (reversal_of_classification_id, organization_id)
    references public.project_cost_classifications(id, organization_id) on delete restrict
);

create index project_cost_classifications_obligation_idx
  on public.project_cost_classifications (organization_id, cost_obligation_id);
create index project_cost_classifications_project_idx
  on public.project_cost_classifications (organization_id, project_id, recorded_at desc);

-- ===========================================================================
-- 2. Guards
-- ===========================================================================
create or replace function public.h1_guard_classification_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'project cost classifications are append-only';
end $$;

drop trigger if exists project_cost_classifications_append_only
  on public.project_cost_classifications;
create trigger project_cost_classifications_append_only
before update or delete on public.project_cost_classifications
for each row execute function public.h1_guard_classification_append_only();

-- At most one ACTIVE classification per obligation. A row is active when it is not
-- itself a reversal and no reversal row points at it.
create or replace function public.h1_guard_one_active_classification()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.reversal_of_classification_id is null then
    if exists (
      select 1
      from public.project_cost_classifications c
      where c.cost_obligation_id = new.cost_obligation_id
        and c.id <> new.id
        and c.reversal_of_classification_id is null
        and not exists (
          select 1 from public.project_cost_classifications r
          where r.reversal_of_classification_id = c.id
        )
    ) then
      raise exception 'an active cost classification already exists for this obligation';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists project_cost_classifications_one_active
  on public.project_cost_classifications;
create trigger project_cost_classifications_one_active
before insert on public.project_cost_classifications
for each row execute function public.h1_guard_one_active_classification();

-- ===========================================================================
-- 3. Commands
-- ===========================================================================
create or replace function public.classify_project_cost(
  p_organization_id uuid,
  p_project_id uuid,
  p_cost_obligation_id uuid,
  p_classification text,
  p_reason text,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_id uuid;
  v_existing public.project_cost_classifications;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_classification not in ('PROJECT_OVERHEAD','EXCLUDED_FROM_MANAGEMENT_RESULT') then
    raise exception 'invalid cost classification';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'a classification reason between 3 and 500 characters is required';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  -- Scope: EXPENSE treatment only. CAPITALIZABLE_WIP obligations post to
  -- DEVELOPMENT_WIP and reach the result through COGS derecognition at disposal;
  -- classifying them here would double count.
  if not exists (
    select 1
    from public.cost_obligation_position_read o
    where o.obligation_id = p_cost_obligation_id
      and o.organization_id = p_organization_id
      and o.project_id = p_project_id
      and o.status = 'AUTHORIZED'
      and o.is_reversed = false
      and o.cost_treatment = 'EXPENSE'
  ) then
    raise exception 'cost obligation is not an active EXPENSE obligation of this project';
  end if;

  v_hash := public.s6_command_request_hash(jsonb_build_object(
    'organization_id', p_organization_id,
    'project_id', p_project_id,
    'cost_obligation_id', p_cost_obligation_id,
    'classification', p_classification,
    'reason', trim(p_reason)
  ));

  select * into v_existing
  from public.project_cost_classifications
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);

  if v_existing.id is not null then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key reuse with a different request';
    end if;
    return v_existing.id;
  end if;

  insert into public.project_cost_classifications (
    organization_id, project_id, cost_obligation_id, classification, reason,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_cost_obligation_id, p_classification, trim(p_reason),
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events (
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_COST_CLASSIFIED', 'project_cost_classification', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'cost_obligation_id', p_cost_obligation_id,
      'classification', p_classification,
      'reason', trim(p_reason)
    )
  );

  return v_id;
end $$;

create or replace function public.reverse_project_cost_classification(
  p_organization_id uuid,
  p_project_id uuid,
  p_classification_id uuid,
  p_reason text,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_id uuid;
  v_target public.project_cost_classifications;
  v_existing public.project_cost_classifications;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then
    raise exception 'a reversal reason between 3 and 500 characters is required';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select * into v_target
  from public.project_cost_classifications
  where id = p_classification_id
    and organization_id = p_organization_id
    and project_id = p_project_id;

  if v_target.id is null then raise exception 'cost classification not found'; end if;
  if v_target.reversal_of_classification_id is not null then
    raise exception 'a reversal row cannot itself be reversed';
  end if;
  if exists (
    select 1 from public.project_cost_classifications r
    where r.reversal_of_classification_id = v_target.id
  ) then
    raise exception 'cost classification is already reversed';
  end if;

  v_hash := public.s6_command_request_hash(jsonb_build_object(
    'organization_id', p_organization_id,
    'project_id', p_project_id,
    'reversal_of_classification_id', p_classification_id,
    'reason', trim(p_reason)
  ));

  select * into v_existing
  from public.project_cost_classifications
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);

  if v_existing.id is not null then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key reuse with a different request';
    end if;
    return v_existing.id;
  end if;

  insert into public.project_cost_classifications (
    organization_id, project_id, cost_obligation_id, classification, reason,
    recorded_by, reversal_of_classification_id, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, v_target.cost_obligation_id, v_target.classification,
    trim(p_reason), v_actor, v_target.id, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events (
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id, v_actor, 'PROJECT_COST_CLASSIFICATION_REVERSED',
    'project_cost_classification', v_id,
    jsonb_build_object(
      'project_id', p_project_id,
      'reversed_classification_id', v_target.id,
      'cost_obligation_id', v_target.cost_obligation_id,
      'classification', v_target.classification,
      'reason', trim(p_reason)
    )
  );

  return v_id;
end $$;

-- ===========================================================================
-- 4. Read model — the derived classification state of every posted project
--    expense line, plus the exact reconciliation identity.
--
--    attributed + overhead + excluded + unclassified + outside_scope
--      = posted project expense            (gated, per project and currency)
-- ===========================================================================
create or replace view public.project_cost_classification_read with (security_invoker=on) as
with expense_lines as (
  -- Same base population as project_financial_position_read.expense_posted_minor_units:
  -- posted PROJECT_EXPENSE lines in batches that are neither reversals nor reversed.
  select
    jl.organization_id,
    jl.project_id,
    jl.obligation_id,
    jl.currency,
    jl.id as journal_line_id,
    (jl.debit_minor_units - jl.credit_minor_units) as expense_minor_units
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa
    on sa.id = jl.account_id and sa.role = 'PROJECT_EXPENSE'
  where jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
),
active_cycle_attributions as (
  select a.source_journal_line_id as journal_line_id
  from public.crop_cycle_cost_attributions a
  where a.reversal_of_attribution_id is null
    and not exists (
      select 1 from public.crop_cycle_cost_attributions r
      where r.reversal_of_attribution_id = a.id
    )
),
active_cohort_attributions as (
  select a.source_journal_line_id as journal_line_id
  from public.livestock_cohort_cost_attributions a
  where a.reversal_of_attribution_id is null
    and not exists (
      select 1 from public.livestock_cohort_cost_attributions r
      where r.reversal_of_attribution_id = a.id
    )
),
active_classifications as (
  select c.cost_obligation_id, c.classification, c.reason, c.recorded_by, c.recorded_at
  from public.project_cost_classifications c
  where c.reversal_of_classification_id is null
    and not exists (
      select 1 from public.project_cost_classifications r
      where r.reversal_of_classification_id = c.id
    )
),
classified_lines as (
  select
    el.organization_id,
    el.project_id,
    el.currency,
    el.journal_line_id,
    el.obligation_id,
    el.expense_minor_units,
    case
      when el.obligation_id is null then 'EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE'
      when aca.journal_line_id is not null then 'ATTRIBUTED_TO_OPERATING_UNIT'
      when aco.journal_line_id is not null then 'ATTRIBUTED_TO_OPERATING_UNIT'
      when exists (
        select 1 from public.property_cost_items pci
        where pci.cost_obligation_id = el.obligation_id
      ) then 'ATTRIBUTED_TO_OPERATING_UNIT'
      when ac.classification = 'PROJECT_OVERHEAD' then 'PROJECT_OVERHEAD'
      when ac.classification = 'EXCLUDED_FROM_MANAGEMENT_RESULT' then 'EXCLUDED_FROM_MANAGEMENT_RESULT'
      else 'UNCLASSIFIED'
    end as classification_state,
    case
      when aca.journal_line_id is not null then 'CROP_CYCLE'
      when aco.journal_line_id is not null then 'LIVESTOCK_COHORT'
      when exists (
        select 1 from public.property_cost_items pci
        where pci.cost_obligation_id = el.obligation_id
      ) then 'PROPERTY_ASSET'
      else null
    end as attribution_kind,
    ac.reason as classification_reason
  from expense_lines el
  left join active_cycle_attributions aca on aca.journal_line_id = el.journal_line_id
  left join active_cohort_attributions aco on aco.journal_line_id = el.journal_line_id
  left join active_classifications ac on ac.cost_obligation_id = el.obligation_id
)
select
  organization_id,
  project_id,
  currency,
  classification_state,
  attribution_kind,
  count(*)::bigint as line_count,
  sum(expense_minor_units)::text as expense_minor_units
from classified_lines
group by organization_id, project_id, currency, classification_state, attribution_kind;

comment on view public.project_cost_classification_read is
  'H1 derived cost-classification state of posted project expense, per project, '
  'currency and state. ATTRIBUTED_TO_OPERATING_UNIT is evidenced by the sector-owned '
  'attribution rows (crop cycle, livestock cohort, property asset); PROJECT_OVERHEAD and '
  'EXCLUDED_FROM_MANAGEMENT_RESULT are operator assertions; UNCLASSIFIED is strictly '
  'residual and is never inferred as overhead; EXPENSE_OUTSIDE_CLASSIFICATION_SCOPE is '
  'expense with no obligation link (for example an opening import) and is reported '
  'separately so it can never masquerade as forgotten attribution.';

-- ===========================================================================
-- 5. RLS and grants — consistent with every other authoritative table.
-- ===========================================================================
alter table public.project_cost_classifications enable row level security;
alter table public.project_cost_classifications force row level security;

create policy project_cost_classifications_read
  on public.project_cost_classifications for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.project_cost_classifications from public, anon, authenticated;
grant select on public.project_cost_classifications to authenticated;

revoke all on function public.classify_project_cost(uuid,uuid,uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.reverse_project_cost_classification(uuid,uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.classify_project_cost(uuid,uuid,uuid,text,text,text)
  to authenticated;
grant execute on function public.reverse_project_cost_classification(uuid,uuid,uuid,text,text)
  to authenticated;

grant select on public.project_cost_classification_read to authenticated;
