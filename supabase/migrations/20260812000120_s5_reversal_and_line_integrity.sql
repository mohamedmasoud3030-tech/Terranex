-- GF-008 / S5 — reversal dependency and deterministic-allocation hardening.
-- Financial facts stay append-only. Reversal is supported through the shared
-- journal correction path, but downstream S5 dependencies must be reversed in
-- the correct order and an allocation may only be approved when every stored
-- line exactly matches the canonical largest-remainder calculation.

-- Every allocation line must belong to the frozen rule set and carry its exact
-- weight/currency, including privileged/direct writes.
create or replace function public.s5_guard_allocation_line_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_run record; v_rule record;
begin
  select * into v_run
  from public.s5_allocation_runs
  where id=new.run_id and organization_id=new.organization_id and project_id=new.project_id;
  if not found then raise exception 'allocation line run scope mismatch'; end if;
  if v_run.status<>'PREPARED' then raise exception 'allocation lines can only be created while the run is PREPARED'; end if;
  if new.currency<>v_run.reporting_currency then raise exception 'allocation line currency must match run currency'; end if;

  select r.* into v_rule
  from public.s5_allocation_rules r
  where r.rule_set_id=v_run.rule_set_id
    and r.organization_id=v_run.organization_id
    and r.project_id=v_run.project_id
    and r.governing_version_id=v_run.governing_version_id
    and r.participant_party_id=new.participant_party_id;
  if not found then raise exception 'allocation line participant is not eligible under the frozen rule set'; end if;
  if new.weight_numerator<>v_rule.weight_numerator or new.weight_denominator<>v_rule.weight_denominator then
    raise exception 'allocation line weight must match the frozen rule set';
  end if;
  return new;
end $$;
drop trigger if exists s5_allocation_lines_scope_guard on public.s5_allocation_lines;
create trigger s5_allocation_lines_scope_guard
before insert on public.s5_allocation_lines
for each row execute function public.s5_guard_allocation_line_scope();

-- Recompute the exact expected largest-remainder result from immutable inputs.
create or replace function public.s5_allocation_lines_are_canonical(p_run_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
with run as (
  select * from public.s5_allocation_runs where id=p_run_id
), raw as (
  select r.participant_party_id,r.weight_numerator,r.weight_denominator,
    trunc(abs(run.source_amount_minor_units::numeric)*r.weight_numerator::numeric/r.weight_denominator::numeric)::bigint as floor_units,
    mod(abs(run.source_amount_minor_units::numeric)*r.weight_numerator::numeric,r.weight_denominator::numeric) as remainder_num,
    case when run.source_amount_minor_units<0 then -1::bigint else 1::bigint end as sign,
    abs(run.source_amount_minor_units::numeric) as source_abs,
    run.reporting_currency
  from run
  join public.s5_allocation_rules r on r.rule_set_id=run.rule_set_id
), ranked as (
  select raw.*,
    row_number() over(order by remainder_num desc,participant_party_id::text asc) as remainder_rank,
    (source_abs-sum(floor_units::numeric) over())::bigint as residual_units
  from raw
), expected as (
  select participant_party_id,weight_numerator,weight_denominator,
    sign*floor_units as exact_floor_minor_units,
    remainder_num as remainder_numerator,
    case when remainder_rank<=residual_units then 1 else 0 end::smallint as rounding_award_minor_units,
    sign*(floor_units+case when remainder_rank<=residual_units then 1 else 0 end) as allocated_minor_units,
    reporting_currency as currency
  from ranked
), actual as (
  select participant_party_id,weight_numerator,weight_denominator,exact_floor_minor_units,
    remainder_numerator,rounding_award_minor_units,allocated_minor_units,currency
  from public.s5_allocation_lines where run_id=p_run_id
), mismatch as (
  (select * from expected except select * from actual)
  union all
  (select * from actual except select * from expected)
)
select not exists(select 1 from mismatch)
   and (select count(*) from actual)=(select count(*) from expected)
   and (select coalesce(sum(allocated_minor_units),0) from actual)
       =(select source_amount_minor_units from run)
$$;
revoke all on function public.s5_allocation_lines_are_canonical(uuid) from public,anon,authenticated;

-- Layer the canonical-line proof beside the base PREPARED -> APPROVED immutable
-- transition guard instead of copying that lifecycle guard into another migration.
create or replace function public.s5_guard_run_canonical_lines() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status='PREPARED' and new.status='APPROVED'
     and not public.s5_allocation_lines_are_canonical(old.id) then
    raise exception 'allocation lines do not match the canonical largest-remainder calculation';
  end if;
  return new;
end $$;
drop trigger if exists s5_allocation_runs_canonical_guard on public.s5_allocation_runs;
create trigger s5_allocation_runs_canonical_guard
before update on public.s5_allocation_runs
for each row execute function public.s5_guard_run_canonical_lines();

-- Distribution facts always depend on an active approved allocation.
create or replace function public.s5_guard_distribution_active_allocation() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_run record; v_line bigint;
begin
  select * into v_run
  from public.s5_allocation_runs
  where id=new.allocation_run_id and organization_id=new.organization_id and project_id=new.project_id;
  if not found or v_run.status<>'APPROVED' or v_run.journal_batch_id is null then
    raise exception 'distribution requires an approved allocation run';
  end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_run.journal_batch_id) then
    raise exception 'distribution requires an active approved allocation run';
  end if;
  select allocated_minor_units into v_line
  from public.s5_allocation_lines
  where run_id=v_run.id and participant_party_id=new.participant_party_id;
  if v_line is null or v_line<=0 then
    raise exception 'participant has no positive allocation in this run';
  end if;
  if new.currency<>v_run.reporting_currency then
    raise exception 'distribution currency must match the allocation run';
  end if;
  return new;
end $$;
drop trigger if exists s5_distributions_active_allocation_guard on public.s5_distributions;
create trigger s5_distributions_active_allocation_guard
before insert or update on public.s5_distributions
for each row execute function public.s5_guard_distribution_active_allocation();

-- Payment rows are subordinate to an active distribution-approval journal.
create or replace function public.s5_guard_distribution_payment_integrity() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_dist record; v_batch record; v_paid numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    new.organization_id::text||':s5-distribution-payment-integrity:'||new.distribution_id::text,0));

  select * into v_dist
  from public.s5_distributions
  where id=new.distribution_id and organization_id=new.organization_id and project_id=new.project_id;
  if not found or v_dist.status<>'APPROVED' or v_dist.approval_journal_batch_id is null then
    raise exception 'payment requires an approved distribution payable';
  end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_dist.approval_journal_batch_id) then
    raise exception 'payment requires an active distribution payable';
  end if;
  if new.participant_party_id<>v_dist.participant_party_id or new.currency<>v_dist.currency then
    raise exception 'distribution payment participant/currency must match the approved payable';
  end if;
  if not exists(
    select 1 from public.project_cash_accounts ca
    where ca.id=new.cash_account_id and ca.organization_id=new.organization_id
      and ca.project_id=new.project_id and ca.currency=new.currency
  ) then raise exception 'cash account does not belong to the distribution project and currency'; end if;

  select * into v_batch
  from public.journal_batches
  where id=new.journal_batch_id and organization_id=new.organization_id and project_id=new.project_id;
  if not found or v_batch.source_type<>'S5_DISTRIBUTION_PAYMENT' or v_batch.source_id<>new.id then
    raise exception 'distribution payment must reference its canonical S5 payment journal';
  end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_batch.id) then
    raise exception 'new distribution payment cannot reference a reversed journal';
  end if;

  select coalesce(sum(p.amount_minor_units::numeric),0) into v_paid
  from public.s5_distribution_payments p
  where p.distribution_id=new.distribution_id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=p.journal_batch_id);
  if v_paid+new.amount_minor_units::numeric>v_dist.approved_amount_minor_units::numeric then
    raise exception 'distribution payment exceeds approved outstanding payable';
  end if;
  return new;
end $$;
drop trigger if exists s5_distribution_payments_integrity_guard on public.s5_distribution_payments;
create trigger s5_distribution_payments_integrity_guard
before insert on public.s5_distribution_payments
for each row execute function public.s5_guard_distribution_payment_integrity();

-- Shared reversal dependency order: downstream S5 effects must be reversed first.
create or replace function public.s5_guard_reversal_dependencies() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_original record;
begin
  if new.source_type<>'REVERSAL' or new.reversal_of_batch_id is null then return new; end if;
  select * into v_original
  from public.journal_batches
  where id=new.reversal_of_batch_id and organization_id=new.organization_id;
  if not found then return new; end if;

  if v_original.source_type='S5_ALLOCATION' then
    if exists(
      select 1 from public.s5_distributions d
      where d.allocation_run_id=v_original.source_id and d.status='APPROVED'
        and not exists(
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id=d.approval_journal_batch_id
        )
    ) then raise exception 'allocation has active approved distributions; reverse distribution approvals first'; end if;
  elsif v_original.source_type='S5_DISTRIBUTION_APPROVAL' then
    if exists(
      select 1 from public.s5_distribution_payments p
      where p.distribution_id=v_original.source_id
        and not exists(
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id=p.journal_batch_id
        )
    ) then raise exception 'distribution has active payments; reverse payments first'; end if;
  end if;
  return new;
end $$;
drop trigger if exists journal_batches_s5_reversal_dependency_guard on public.journal_batches;
create trigger journal_batches_s5_reversal_dependency_guard
before insert on public.journal_batches
for each row execute function public.s5_guard_reversal_dependencies();

-- Reversal-aware distribution read model. The preceding migration drops the
-- earlier view explicitly because PostgreSQL cannot insert a view column via
-- CREATE OR REPLACE while preserving the old column order.
create view public.s5_distributions_read with (security_invoker=on) as
select d.id as distribution_id,d.organization_id,d.project_id,d.allocation_run_id,d.participant_party_id,
  p.legal_name,d.requested_amount_minor_units::text,d.approved_amount_minor_units::text,d.currency,
  d.evidence_reference,d.status,d.prepared_by,d.prepared_at,d.approved_by,d.approved_at,
  d.approval_posting_date,d.approval_journal_batch_id,
  coalesce(pay.paid,0)::text as paid_minor_units,
  case when approval_reversal.id is not null then '0'
       else greatest(coalesce(d.approved_amount_minor_units,0)::numeric-coalesce(pay.paid,0),0)::text end as outstanding_minor_units,
  (approval_reversal.id is not null) as is_approval_reversed,
  case
    when d.status='PREPARED' then 'PREPARED'
    when approval_reversal.id is not null then 'REVERSED'
    when coalesce(pay.paid,0)=0 then 'APPROVED'
    when coalesce(pay.paid,0)<d.approved_amount_minor_units then 'PARTIALLY_PAID'
    else 'PAID'
  end as settlement_status
from public.s5_distributions d
join public.parties p on p.id=d.participant_party_id and p.organization_id=d.organization_id
left join public.journal_batches approval_reversal
  on approval_reversal.reversal_of_batch_id=d.approval_journal_batch_id
left join lateral (
  select coalesce(sum(dp.amount_minor_units::numeric),0) as paid
  from public.s5_distribution_payments dp
  where dp.distribution_id=d.id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=dp.journal_batch_id)
) pay on true;

grant select on public.s5_distributions_read to authenticated;
