-- ===========================================================================
-- PRE-OWNER POLICY-SAFETY BOUNDARY (corrective engineering).
--
-- This migration makes policy-dependent investor-economics runtime fail closed
-- until the target company's funding/investor/distribution policy is explicitly
-- approved. It resolves NO business decision, invents NO target-company policy,
-- and adds NO placeholder percentages or fake approved policy rows.
--
-- It preserves every historical mechanism (tables, views, RPCs, journals,
-- reversals, reads) while blocking NEW policy-dependent writes:
--
--   * S5 allocation/distribution writes require an approved
--     `INVESTOR_ECONOMICS` policy authority (BD-004/006/008 remain OPEN,
--     so the registry starts EMPTY and the chain is policy-inert);
--   * the OWNER-gated `attach_contribution_cash` posting requires an approved
--     `CAPITAL_CONTRIBUTION` policy authority (BD-002/005 remain OPEN), so a
--     cash receipt is no longer silently classified as contributed capital;
--   * S1 governing-agreement activation and capital-call issuance are raised
--     to the strongest already-approved authority (OWNER), closing the
--     active-MEMBER governance gap (BD-002/003/005 remain OPEN);
--   * the stale S5 allocable-result source (Real Estate sale result only) is
--     truthfully read-labeled (COMMENT + terminology matrix) so it is no longer
--     read as the universal `REALIZED_RESULT`;
--   * the S5 capacity bridge is relabeled a historical/conservative technical
--     capacity bridge, not a company distributable-cash policy (BD-008 OPEN);
--   * S5 distribution payments can now participate in the SAME shared
--     bank-line reconciliation primitive as every other real cash movement;
--   * the pilot acceptance report no longer surfaces partner-capital or
--     investor-statement values as technical-readiness facts.
--
-- Recorded by ADR `docs/decisions/0033_PRE_OWNER_POLICY_SAFETY_BOUNDARY.md`.
-- ===========================================================================

-- ===========================================================================
-- 1. Policy-activation authority registry (default EMPTY = policy-inert).
--    A row is inserted ONLY by an explicit owner/professional approval flow
--    that is NOT part of this corrective migration. No rows are seeded here.
-- ===========================================================================
create table public.policy_authority (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  scope text not null check (scope in ('INVESTOR_ECONOMICS','CAPITAL_CONTRIBUTION')),
  status text not null default 'APPROVED' check (status = 'APPROVED'),
  policy_version text not null check (char_length(trim(policy_version)) between 1 and 80),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  approved_by uuid not null references auth.users(id) on delete restrict,
  approved_at timestamptz not null default now(),
  unique (organization_id, scope),
  unique (id, organization_id)
);

alter table public.policy_authority enable row level security;
alter table public.policy_authority force row level security;
create policy policy_authority_read on public.policy_authority for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.policy_authority from anon, authenticated;
grant select on public.policy_authority to authenticated;

-- ===========================================================================
-- 2. Canonical policy gate. Fails closed with a stable domain error while no
--    approved policy authority exists for the requested scope.
-- ===========================================================================
create or replace function public.require_policy_activated(p_organization_id uuid, p_scope text)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if p_scope not in ('INVESTOR_ECONOMICS','CAPITAL_CONTRIBUTION') then
    raise exception 'unknown policy scope';
  end if;
  if not exists (
    select 1 from public.policy_authority a
    where a.organization_id = p_organization_id
      and a.scope = p_scope
      and a.status = 'APPROVED'
  ) then
    raise exception 'target-company investor policy is not activated';
  end if;
end $$;
revoke all on function public.require_policy_activated(uuid,text) from public, anon, authenticated;

-- ===========================================================================
-- 3. S5 policy gate. Every NEW allocation/distribution write — through the RPCs
--    or any other path — requires an approved INVESTOR_ECONOMICS policy. The
--    four S5 write tables are the database boundary of the mechanism.
-- ===========================================================================
create or replace function public.s5_require_investor_policy_trigger() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  perform public.require_policy_activated(new.organization_id, 'INVESTOR_ECONOMICS');
  return new;
end $$;
revoke all on function public.s5_require_investor_policy_trigger() from public, anon, authenticated;

create trigger s5_allocation_rule_sets_policy_gate
before insert or update on public.s5_allocation_rule_sets
for each row execute function public.s5_require_investor_policy_trigger();
create trigger s5_allocation_runs_policy_gate
before insert or update on public.s5_allocation_runs
for each row execute function public.s5_require_investor_policy_trigger();
create trigger s5_distributions_policy_gate
before insert or update on public.s5_distributions
for each row execute function public.s5_require_investor_policy_trigger();
create trigger s5_distribution_payments_policy_gate
before insert or update on public.s5_distribution_payments
for each row execute function public.s5_require_investor_policy_trigger();

-- ===========================================================================
-- 4. Contribution-cash posting gate. Recording a Contribution remains a
--    non-posting fact. The explicit OWNER-gated cash-attachment command that
--    posts Dr BANK_CASH / Cr CONTRIBUTED_CAPITAL now also requires an approved
--    CAPITAL_CONTRIBUTION policy (BD-002/005 OPEN). CASH RECEIPT is never
--    CONTRIBUTED CAPITAL by implication.
-- ===========================================================================
create or replace function public.attach_contribution_cash(
  p_organization_id uuid,
  p_project_id uuid,
  p_contribution_id uuid,
  p_cash_account_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_contribution record;
  v_batch_id uuid; v_hash text; v_existing record;
  v_bank_cash uuid; v_capital uuid; v_party uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.require_policy_activated(p_organization_id, 'CAPITAL_CONTRIBUTION');
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select id, project_id, participant_id, contribution_minor_units, currency, occurred_on
    into v_contribution
  from public.contributions
  where id = p_contribution_id and organization_id = p_organization_id;
  if not found then raise exception 'contribution not found'; end if;
  if v_contribution.project_id <> p_project_id then
    raise exception 'contribution does not belong to project';
  end if;

  if not exists (
    select 1 from public.project_cash_accounts ca
    where ca.id = p_cash_account_id
      and ca.organization_id = p_organization_id
      and ca.project_id = p_project_id
  ) then raise exception 'cash account not found for project'; end if;

  select encode(digest(
    p_contribution_id::text || '|' || p_cash_account_id::text, 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':contribution-cash:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.journal_batches
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash
       or v_existing.source_type <> 'CONTRIBUTION_CASH_ATTRIBUTION'
       or v_existing.source_id <> p_contribution_id then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  if exists (
    select 1 from public.journal_batches jb
    where jb.source_type = 'CONTRIBUTION_CASH_ATTRIBUTION'
      and jb.source_id = p_contribution_id
      and jb.organization_id = p_organization_id
      and not exists (
        select 1 from public.journal_batches rb
        where rb.reversal_of_batch_id = jb.id
      )
  ) then raise exception 'contribution is already posted to project cash'; end if;

  select id into v_bank_cash from public.semantic_accounts where role = 'BANK_CASH';
  select id into v_capital from public.semantic_accounts where role = 'CONTRIBUTED_CAPITAL';
  select party_id into v_party from public.project_participants
  where id = v_contribution.participant_id and organization_id = p_organization_id;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'CONTRIBUTION_CASH_ATTRIBUTION', p_contribution_id,
    v_contribution.occurred_on, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_bank_cash,
     v_contribution.contribution_minor_units, 0, v_contribution.currency,
     p_cash_account_id, null, v_contribution.occurred_on),
    (v_batch_id, p_organization_id, p_project_id, v_capital,
     0, v_contribution.contribution_minor_units, v_contribution.currency,
     null, v_party, v_contribution.occurred_on);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'CONTRIBUTION_CASH_POSTED', 'journal_batch', v_batch_id,
          jsonb_build_object('project_id', p_project_id,
                             'contribution_id', p_contribution_id,
                             'cash_account_id', p_cash_account_id,
                             'contribution_minor_units', v_contribution.contribution_minor_units,
                             'currency', v_contribution.currency));
  return v_batch_id;
end $$;
revoke all on function public.attach_contribution_cash(uuid,uuid,uuid,uuid,text) from public, anon;
grant execute on function public.attach_contribution_cash(uuid,uuid,uuid,uuid,text) to authenticated;

-- ===========================================================================
-- 5. S1 governing-authority boundary. Activating the one governing agreement
--    (which freezes participant membership and moves the Project to FUNDING)
--    and issuing a policy-bearing capital call now require OWNER, not mere
--    active membership. Drafting/recording facts remain member-level because
--    they cannot activate economic behavior.
-- ===========================================================================
create or replace function public.activate_agreement_version(
  p_organization_id uuid, p_version_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid; v_agreement uuid; v_status text; v_count int; v_current uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  select project_id, agreement_id, status into v_project, v_agreement, v_status
  from public.agreement_versions
  where id = p_version_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'agreement version not found'; end if;

  select current_version_id into v_current
  from public.investment_agreements
  where id = v_agreement and organization_id = p_organization_id
  for update;

  if v_status = 'ACTIVE' and v_current = p_version_id then
    return p_version_id;
  end if;
  if v_status <> 'DRAFT' then raise exception 'only a draft version can be activated'; end if;
  if v_current is not null and v_current <> p_version_id then
    raise exception 'agreement amendment activation is deferred; the existing version remains governing';
  end if;

  select count(*) into v_count from public.commitment_terms
  where agreement_version_id = p_version_id;
  if v_count < 1 then raise exception 'agreement version has no commitment terms'; end if;

  update public.agreement_versions
     set status = 'ACTIVE', activated_at = now(), activated_by = v_actor
   where id = p_version_id and status = 'DRAFT';
  if not found then raise exception 'only a draft version can be activated'; end if;

  update public.investment_agreements
     set status = 'ACTIVE', current_version_id = p_version_id
   where id = v_agreement;
  update public.investment_projects
     set lifecycle_state = 'FUNDING'
   where id = v_project and lifecycle_state = 'DRAFT';

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'AGREEMENT_VERSION_ACTIVATED','agreement_version', p_version_id,
          jsonb_build_object('project_id', v_project, 'agreement_id', v_agreement));
  return p_version_id;
end $$;

create or replace function public.create_capital_call(
  p_organization_id uuid,
  p_project_id uuid,
  p_agreement_version_id uuid,
  p_due_date date,
  p_reference text,
  p_participant_ids uuid[],
  p_amounts bigint[],
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_call_id uuid; v_currency text; v_i int; v_commitment bigint; v_already_called bigint;
  v_ref text; v_hash text; v_existing_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_due_date is null then raise exception 'due date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'at least one call line is required';
  end if;
  if array_length(p_participant_ids,1) <> array_length(p_amounts,1) then
    raise exception 'participants and amounts length mismatch';
  end if;
  if (select count(*) from unnest(p_participant_ids) x)
     <> (select count(distinct x) from unnest(p_participant_ids) x) then
    raise exception 'duplicate participant in capital call';
  end if;

  if not exists (
    select 1 from public.agreement_versions
    where id = p_agreement_version_id and project_id = p_project_id
      and organization_id = p_organization_id and status = 'ACTIVE'
  ) then raise exception 'capital call requires an active agreement version'; end if;

  select reporting_currency into v_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;

  v_ref := nullif(trim(coalesce(p_reference,'')),'');
  if v_ref is not null and char_length(v_ref) > 80 then raise exception 'reference too long'; end if;

  for v_i in 1..array_length(p_participant_ids,1) loop
    if p_amounts[v_i] is null or p_amounts[v_i] <= 0 then
      raise exception 'call amount must be positive';
    end if;
  end loop;

  select encode(digest(
    p_project_id::text || '|' || p_agreement_version_id::text || '|' || p_due_date::text || '|'
    || coalesce(v_ref,'') || '|' || (select string_agg(pair, ',' order by pair) from unnest(
      array(select p_participant_ids[i]::text || ':' || p_amounts[i]::text
            from generate_series(1, array_length(p_participant_ids,1)) as i)
    ) pair), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':capital-call:' || trim(p_idempotency_key), 0));
  select id, request_hash into v_call_id, v_existing_hash
  from public.capital_calls
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_call_id;
  end if;

  perform 1
  from public.commitment_terms
  where agreement_version_id = p_agreement_version_id
    and participant_id = any(p_participant_ids)
  order by participant_id
  for update;

  for v_i in 1..array_length(p_participant_ids,1) loop
    select ct.commitment_minor_units into v_commitment
    from public.commitment_terms ct
    where ct.agreement_version_id = p_agreement_version_id
      and ct.participant_id = p_participant_ids[v_i];
    if v_commitment is null then raise exception 'participant has no commitment on this version'; end if;

    select coalesce(sum(ccl.amount_minor_units),0) into v_already_called
    from public.capital_call_lines ccl
    join public.capital_calls cc on cc.id = ccl.capital_call_id
    where cc.agreement_version_id = p_agreement_version_id
      and cc.status = 'ISSUED'
      and ccl.participant_id = p_participant_ids[v_i];
    if v_already_called + p_amounts[v_i] > v_commitment then
      raise exception 'capital call exceeds participant commitment';
    end if;
  end loop;

  insert into public.capital_calls(
    organization_id, project_id, agreement_version_id, status, due_date, reference,
    issued_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_agreement_version_id, 'ISSUED', p_due_date,
    v_ref, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_call_id;

  for v_i in 1..array_length(p_participant_ids,1) loop
    insert into public.capital_call_lines(
      organization_id, capital_call_id, participant_id, amount_minor_units, currency
    ) values (
      p_organization_id, v_call_id, p_participant_ids[v_i], p_amounts[v_i], v_currency
    );
  end loop;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'CAPITAL_CALL_ISSUED','capital_call', v_call_id,
          jsonb_build_object('project_id', p_project_id,
                             'agreement_version_id', p_agreement_version_id,
                             'due_date', p_due_date, 'reference', v_ref));
  return v_call_id;
end $$;
revoke all on function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[],text) from public, anon;
grant execute on function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[],text) to authenticated;

-- ===========================================================================
-- 6. Truthful read-labels for the historical S5 allocable-result source.
--    The legacy s5_realized_result_as_of_snapshot derives ONLY Real Estate sale
--    revenue / cost of sale / SELLING expense and predates rental, Agriculture
--    and Livestock revenue. It is policy-inert (section 3) and must never be
--    read as a universal Project realized result (see
--    docs/TERMINOLOGY_REALIZED_RESULT.md for the full terminology matrix).
-- ===========================================================================
comment on function public.s5_realized_result_as_of_snapshot(uuid,uuid,uuid) is
  'Historical Real Estate sale result only (sale revenue - cost of sale - SELLING expense) as-of an approved S6 close snapshot. NOT a universal Project realized result; policy-inert (BD-006 OPEN).';
comment on column public.s5_allocation_runs.source_category is
  'Historical source category. The current value REALIZED_RESULT means Real Estate sale result only; it is NOT a universal Project realized result (BD-006 OPEN).';


-- ===========================================================================
-- 7. Truthful relabel of the S5 capacity bridge. This is a historical,
--    conservative technical capacity computation, NOT a company distributable-
--    cash policy (BD-008 OPEN). The column is renamed so no consumer can read
--    it as legally/accountingly distributable cash.
-- ===========================================================================
drop view if exists public.s5_distribution_capacity_read;
create view public.s5_distribution_capacity_read with (security_invoker=on) as
with project_role_balances as (
  select jl.organization_id,jl.project_id,jl.currency,
    coalesce(sum(case when sa.role='BANK_CASH' then jl.debit_minor_units::numeric-jl.credit_minor_units::numeric else 0 end),0) cash,
    coalesce(sum(case when sa.role='SUPPLIER_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0) supplier_payable,
    coalesce(sum(case when sa.role='DISTRIBUTION_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0) distribution_payable
  from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id
  group by jl.organization_id,jl.project_id,jl.currency
)
select organization_id,project_id,currency,cash::text as cash_minor_units,
  greatest(supplier_payable,0)::text as supplier_payable_minor_units,
  greatest(distribution_payable,0)::text as distribution_payable_minor_units,
  greatest(cash-greatest(supplier_payable,0)-greatest(distribution_payable,0),0)::text as technical_capacity_bridge_minor_units
from project_role_balances;
grant select on public.s5_distribution_capacity_read to authenticated;

-- ===========================================================================
-- 8. Bank reconciliation of S5 distribution payments through the SAME shared
--    one-bank-line reservation primitive used by supplier payments, property
--    sale collections and rental collections. Reconciliation of a posted cash
--    movement is policy-independent; it does not authorize new distributions.
-- ===========================================================================
alter table public.bank_statement_reconciliation_allocations
  drop constraint if exists bank_statement_reconciliation_allocations_match_type_check;
alter table public.bank_statement_reconciliation_allocations
  add constraint bank_statement_reconciliation_allocations_match_type_check check (match_type in (
    'PAYMENT','PROPERTY_SALE_COLLECTION','PROPERTY_RENTAL_COLLECTION','DISTRIBUTION_PAYMENT'
  ));

create table public.s5_distribution_payment_reconciliations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  distribution_payment_id uuid not null,
  statement_line_id uuid not null,
  cash_account_id uuid not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  matched_by uuid not null references auth.users(id) on delete restrict,
  matched_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (id,organization_id),
  unique (organization_id,idempotency_key),
  unique (distribution_payment_id),
  unique (statement_line_id),
  foreign key (distribution_payment_id,organization_id)
    references public.s5_distribution_payments(id,organization_id) on delete restrict,
  foreign key (statement_line_id,organization_id)
    references public.bank_statement_lines(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);

create or replace function public.s5_reserve_distribution_payment_statement_line() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  insert into public.bank_statement_reconciliation_allocations(
    statement_line_id,organization_id,match_type,match_id
  ) values(new.statement_line_id,new.organization_id,'DISTRIBUTION_PAYMENT',new.id);
  return new;
end $$;
revoke all on function public.s5_reserve_distribution_payment_statement_line() from public,anon,authenticated;
create trigger s5_distribution_payment_reconciliation_reserve_statement
before insert on public.s5_distribution_payment_reconciliations
for each row execute function public.s5_reserve_distribution_payment_statement_line();

create trigger s5_distribution_payment_reconciliations_append_only
before update or delete on public.s5_distribution_payment_reconciliations
for each row execute function public.s2_guard_append_only();

alter table public.s5_distribution_payment_reconciliations enable row level security;
alter table public.s5_distribution_payment_reconciliations force row level security;
create policy s5_distribution_payment_reconciliations_read
  on public.s5_distribution_payment_reconciliations for select to authenticated
  using (public.is_active_member(organization_id));
revoke all on public.s5_distribution_payment_reconciliations from anon,authenticated;
grant select on public.s5_distribution_payment_reconciliations to authenticated;

create or replace function public.s5_reconcile_distribution_payment(
  p_organization_id uuid,p_distribution_payment_id uuid,p_statement_line_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payment record; v_line record; v_existing record;
  v_hash text; v_id uuid:=gen_random_uuid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash:=encode(digest(p_distribution_payment_id::text||'|'||p_statement_line_id::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':s5-distribution-reconcile:'||trim(p_idempotency_key),0));

  select * into v_existing
  from public.s5_distribution_payment_reconciliations
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.distribution_payment_id<>p_distribution_payment_id
       or v_existing.statement_line_id<>p_statement_line_id
       or v_existing.request_hash<>v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_payment
  from public.s5_distribution_payments
  where id=p_distribution_payment_id and organization_id=p_organization_id
  for update;
  if not found then raise exception 'distribution payment not found'; end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_payment.journal_batch_id) then
    raise exception 'reversed distribution payment cannot be reconciled';
  end if;

  select * into v_line
  from public.bank_statement_lines
  where id=p_statement_line_id and organization_id=p_organization_id
  for update;
  if not found then raise exception 'bank statement line not found'; end if;

  if exists(
    select 1 from public.s5_distribution_payment_reconciliations rr
    where rr.organization_id=p_organization_id
      and rr.distribution_payment_id=p_distribution_payment_id
  ) then raise exception 'distribution payment already reconciled'; end if;
  if exists(
    select 1 from public.bank_statement_reconciliation_allocations a
    where a.organization_id=p_organization_id
      and a.statement_line_id=p_statement_line_id
  ) then raise exception 'bank statement line already reconciled'; end if;

  if v_line.project_id<>v_payment.project_id
     or v_line.cash_account_id<>v_payment.cash_account_id
     or v_line.currency<>v_payment.currency then
    raise exception 'distribution payment and bank line must use the same project cash account and currency';
  end if;
  if v_line.amount_minor_units<>-v_payment.amount_minor_units then
    raise exception 'negative bank statement amount must equal the distribution payment';
  end if;

  insert into public.s5_distribution_payment_reconciliations(
    id,organization_id,project_id,distribution_payment_id,statement_line_id,cash_account_id,currency,
    matched_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,v_payment.project_id,p_distribution_payment_id,p_statement_line_id,
    v_payment.cash_account_id,v_payment.currency,v_actor,trim(p_idempotency_key),v_hash
  );

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_DISTRIBUTION_PAYMENT_RECONCILED',
    's5_distribution_payment_reconciliation',v_id,
    jsonb_build_object('project_id',v_payment.project_id,
      'distribution_payment_id',p_distribution_payment_id,
      'statement_line_id',p_statement_line_id,'accounting_effect','NONE'));
  return v_id;
end $$;
revoke all on function public.s5_reconcile_distribution_payment(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.s5_reconcile_distribution_payment(uuid,uuid,uuid,text) to authenticated;

-- ===========================================================================
-- 9. Remove policy-dependent partner-capital / investor-statement values from
--    the machine-verifiable acceptance report. They are investor economics,
--    not technical readiness; the report no longer derives or exposes them.
-- ===========================================================================
drop view if exists public.s7_pilot_acceptance_report_read;
create view public.s7_pilot_acceptance_report_read with (security_invoker=on) as
select
  p.id as project_id,
  p.organization_id,
  p.reporting_currency,
  coalesce(imp.posted_imports, 0) as posted_opening_imports,
  coalesce(imp.rejected_rows, 0) as opening_import_rejected_rows,
  coalesce(imp.control_totals_ok, false) as opening_control_totals_match,
  coalesce(rec.checkpoints, 0) as reconciliation_checkpoints,
  coalesce(rec.non_zero_variances, 0) as reconciliation_non_zero_variances,
  coalesce(rec.max_abs_variance, 0)::text as reconciliation_max_abs_variance_minor_units,
  coalesce(exc.open_exceptions, 0) as unresolved_exceptions,
  coalesce(exc.open_critical, 0) as unresolved_critical_exceptions,
  coalesce(cash.unreconciled_statement_lines, 0) as unreconciled_bank_statement_lines,
  coalesce(bal.unbalanced_batches, 0) as unbalanced_journal_batches,
  reh.end_to_end_result,
  reh.backup_restore_result,
  reh.access_revocation_result,
  coalesce(uat.total_tasks, 0) as uat_total_tasks,
  coalesce(uat.accepted_tasks, 0) as uat_accepted_tasks,
  coalesce(uat.rejected_tasks, 0) as uat_rejected_tasks,
  case
    when coalesce(uat.total_tasks, 0) = 0 then 'NOT_STARTED'
    when coalesce(uat.rejected_tasks, 0) > 0 then 'REJECTED'
    when coalesce(uat.accepted_tasks, 0) = uat.total_tasks then 'ACCEPTED'
    else 'PENDING'
  end as human_uat_status
from public.investment_projects p
left join lateral (
  select count(*) filter (where i.status = 'POSTED') as posted_imports,
         coalesce(sum(i.rejected_row_count), 0) as rejected_rows,
         bool_and(i.debit_variance_minor_units = 0 and i.credit_variance_minor_units = 0)
           filter (where i.status = 'POSTED') as control_totals_ok
  from public.s7_opening_imports i
  where i.organization_id = p.organization_id and i.project_id = p.id
) imp on true
left join lateral (
  select count(*) as checkpoints,
         count(*) filter (where c.variance_minor_units <> 0) as non_zero_variances,
         coalesce(max(abs(c.variance_minor_units)), 0) as max_abs_variance
  from public.s7_reconciliation_checkpoints c
  where c.organization_id = p.organization_id and c.project_id = p.id
) rec on true
left join lateral (
  select count(*) filter (where e.status = 'OPEN') as open_exceptions,
         count(*) filter (where e.status = 'OPEN' and e.severity = 'CRITICAL') as open_critical
  from public.s7_reconciliation_exceptions e
  where e.organization_id = p.organization_id and e.project_id = p.id
) exc on true
left join lateral (
  select count(*) as unreconciled_statement_lines
  from public.bank_statement_line_status_read l
  where l.organization_id = p.organization_id and l.project_id = p.id
    and not l.is_reconciled
) cash on true
left join lateral (
  select count(*) as unbalanced_batches
  from (
    select jl.batch_id
    from public.journal_lines jl
    where jl.organization_id = p.organization_id and jl.project_id = p.id
    group by jl.batch_id
    having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units)
  ) b
) bal on true
left join lateral (
  select
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'END_TO_END_CYCLE'))[1] as end_to_end_result,
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'BACKUP_RESTORE'))[1] as backup_restore_result,
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'ACCESS_REVOCATION'))[1] as access_revocation_result
  from public.s7_pilot_rehearsals r
  where r.organization_id = p.organization_id and r.project_id = p.id
) reh on true
left join lateral (
  select count(*) as total_tasks,
         count(*) filter (where t.status = 'ACCEPTED') as accepted_tasks,
         count(*) filter (where t.status = 'REJECTED') as rejected_tasks
  from public.s7_uat_tasks t
  where t.organization_id = p.organization_id and t.project_id = p.id
) uat on true;
grant select on public.s7_pilot_acceptance_report_read to authenticated;

-- ===========================================================================
-- 10. pgcrypto hosted-schema compatibility pass.
--     This migration redefines/adds SECURITY DEFINER functions that call
--     digest(...) unqualified (attach_contribution_cash, create_capital_call,
--     s5_reconcile_distribution_payment). They are created AFTER the earlier
--     qualification passes, so re-run the same
--     bounded pass: keep the locked search_path, qualify only the pgcrypto
--     dependency. CREATE OR REPLACE preserves function identity/grants.
-- ===========================================================================
do $pre_owner_pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_definition text;
  v_rewritten text;
  r record;
begin
  select n.nspname
    into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;

  for r in
    select p.oid, p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid)
        ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\('
    order by p.oid::regprocedure::text
  loop
    v_definition := pg_get_functiondef(r.oid);
    v_rewritten := regexp_replace(
      v_definition,
      '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
      E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(',
      'g'
    );

    if v_rewritten = v_definition then
      raise exception 'failed to qualify pgcrypto digest in %', r.signature;
    end if;

    execute v_rewritten;
  end loop;
end
$pre_owner_pgcrypto_compat$;
