-- GF-008 / S5 — allocation-basis truth.
-- Commitment is not ownership. Allocation weights are independent frozen facts
-- with their own evidence provenance and effective range.

alter table public.s5_allocation_rule_sets
  add column basis_evidence_reference text,
  add column effective_from date,
  add column effective_to date;

alter table public.s5_allocation_rule_sets
  add constraint s5_rule_sets_basis_evidence_check
    check (basis_evidence_reference is not null and char_length(trim(basis_evidence_reference)) between 3 and 200),
  add constraint s5_rule_sets_effective_range_check
    check (effective_from is not null and (effective_to is null or effective_to>=effective_from));

-- Eligibility is defined by the governing version's investor set, while the
-- allocation weights remain independent economics. Never compare entitlement
-- weights to committed or contributed cash.
create or replace function public.s5_validate_rule_set_complete() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_set record; v_expected bigint; v_actual bigint; v_sum numeric;
begin
  select * into v_set from public.s5_allocation_rule_sets where id=new.id;
  select count(*) into v_expected
  from public.commitment_terms ct
  join public.project_participants pp on pp.id=ct.participant_id
  where ct.organization_id=v_set.organization_id
    and ct.agreement_version_id=v_set.governing_version_id
    and pp.project_id=v_set.project_id and pp.role='INVESTOR';
  select count(*),coalesce(sum(weight_numerator::numeric),0)
    into v_actual,v_sum
  from public.s5_allocation_rules where rule_set_id=v_set.id;
  if v_expected=0 or v_actual<>v_expected then
    raise exception 'allocation rules must cover every investor in the governing version exactly once';
  end if;
  if v_sum<>v_set.common_denominator::numeric then
    raise exception 'allocation weights must resolve exactly to 100 percent';
  end if;
  if exists (
    select 1
    from public.commitment_terms ct
    join public.project_participants pp on pp.id=ct.participant_id
    where ct.organization_id=v_set.organization_id
      and ct.agreement_version_id=v_set.governing_version_id
      and pp.project_id=v_set.project_id and pp.role='INVESTOR'
      and not exists (
        select 1 from public.s5_allocation_rules r
        where r.rule_set_id=v_set.id and r.participant_party_id=pp.party_id
      )
  ) then
    raise exception 'allocation rules omit an eligible investor';
  end if;
  return null;
end $$;

-- A closed source must sit wholly inside the frozen basis range. The current S1
-- contract deliberately has no amendment workflow, so crossing a term boundary
-- is rejected rather than silently applying current terms to historical result.
create or replace function public.s5_guard_run_effective_basis() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_start date; v_end date; v_rule record;
begin
  select start_date,end_date into v_start,v_end
  from public.accounting_periods where id=new.source_period_id and organization_id=new.organization_id;
  select * into v_rule from public.s5_allocation_rule_sets
  where id=new.rule_set_id and organization_id=new.organization_id;
  if not found or v_start is null then raise exception 'allocation source/rule scope is incomplete'; end if;
  if v_start<v_rule.effective_from or (v_rule.effective_to is not null and v_end>v_rule.effective_to) then
    raise exception 'closed source period crosses outside the frozen allocation-basis effective range';
  end if;
  return new;
end $$;

drop trigger if exists s5_allocation_runs_effective_basis_guard on public.s5_allocation_runs;
create trigger s5_allocation_runs_effective_basis_guard
before insert on public.s5_allocation_runs
for each row execute function public.s5_guard_run_effective_basis();
