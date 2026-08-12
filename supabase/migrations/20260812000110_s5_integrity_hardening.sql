-- GF-008 / S5 — integrity hardening.
-- Keep the proven S2 source-posting guard unchanged and add an S5-specific
-- source guard. This avoids changing historical S2 concurrency semantics.

create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT') then
    perform pg_advisory_xact_lock(hashtextextended(
      's2-active-source:' || new.organization_id::text || ':' || new.source_type || ':' || new.source_id::text,
      0
    ));

    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'source already has an active posting';
    end if;
  end if;
  return new;
end $$;

create or replace function public.s5_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT') then
    perform pg_advisory_xact_lock(hashtextextended(
      's5-active-source:' || new.organization_id::text || ':' || new.source_type || ':' || new.source_id::text,
      0
    ));

    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'S5 source already has an active posting';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists journal_batches_s5_one_active_source_guard on public.journal_batches;
create trigger journal_batches_s5_one_active_source_guard
before insert on public.journal_batches
for each row execute function public.s5_guard_one_active_source_posting();

-- PostgreSQL does not provide min(uuid) on every supported installation.
-- Resolve the single open period with an explicit count and lookup instead.
create or replace function public.s5_require_open_posting_date(
  p_organization_id uuid,p_project_id uuid,p_posting_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_count integer;
begin
  if p_posting_date is null then raise exception 'posting date is required'; end if;
  select count(*) into v_count
  from public.accounting_periods
  where organization_id=p_organization_id and project_id=p_project_id
    and status='OPEN' and p_posting_date between start_date and end_date;
  if v_count<>1 then raise exception 'S5 posting requires exactly one OPEN accounting period covering the posting date'; end if;
  select id into v_id
  from public.accounting_periods
  where organization_id=p_organization_id and project_id=p_project_id
    and status='OPEN' and p_posting_date between start_date and end_date
  limit 1;
  return v_id;
end $$;
revoke all on function public.s5_require_open_posting_date(uuid,uuid,date) from public,anon,authenticated;

-- A policy named PRO_RATA is not allowed to carry arbitrary weights. At the
-- deferred rule-set boundary, prove every supplied ratio is exactly equal to
-- the governing agreement's commitment ratio using integer cross-products.
create or replace function public.s5_validate_rule_set_complete() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_set record; v_expected bigint; v_actual bigint; v_sum numeric; v_total_commitment numeric;
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

  if v_set.policy='PRO_RATA' then
    select coalesce(sum(ct.commitment_minor_units::numeric),0) into v_total_commitment
    from public.commitment_terms ct
    join public.project_participants pp on pp.id=ct.participant_id
    where ct.organization_id=v_set.organization_id
      and ct.agreement_version_id=v_set.governing_version_id
      and pp.project_id=v_set.project_id and pp.role='INVESTOR';
    if v_total_commitment<=0 then
      raise exception 'PRO_RATA requires positive governing commitments';
    end if;
    if exists (
      select 1
      from public.s5_allocation_rules r
      join public.project_participants pp
        on pp.organization_id=r.organization_id and pp.project_id=r.project_id
       and pp.party_id=r.participant_party_id and pp.role='INVESTOR'
      join public.commitment_terms ct
        on ct.organization_id=r.organization_id and ct.participant_id=pp.id
       and ct.agreement_version_id=r.governing_version_id
      where r.rule_set_id=v_set.id
        and r.weight_numerator::numeric*v_total_commitment
            <> ct.commitment_minor_units::numeric*v_set.common_denominator::numeric
    ) then
      raise exception 'PRO_RATA weights must exactly match governing commitment ratios';
    end if;
  end if;
  return null;
end $$;
