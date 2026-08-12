-- GF-008 / S5 — allocation-basis truth.
-- Commitment is not ownership. Keep the already-frozen rule economics intact
-- and store independent evidence/effective-date provenance in a one-to-one
-- append-only companion fact instead of redefining the rule validator.

create table public.s5_allocation_rule_basis (
  rule_set_id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  governing_version_id uuid not null,
  basis_evidence_reference text not null
    check (char_length(trim(basis_evidence_reference)) between 3 and 200),
  effective_from date not null,
  effective_to date,
  basis_hash text not null check (char_length(basis_hash)=64),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (rule_set_id,organization_id),
  foreign key (rule_set_id,organization_id,project_id,governing_version_id)
    references public.s5_allocation_rule_sets(id,organization_id,project_id,governing_version_id) on delete restrict,
  check (effective_to is null or effective_to>=effective_from)
);

create trigger s5_allocation_rule_basis_immutable
before update or delete on public.s5_allocation_rule_basis
for each row execute function public.s5_guard_append_only();

alter table public.s5_allocation_rule_basis enable row level security;
alter table public.s5_allocation_rule_basis force row level security;
create policy s5_allocation_rule_basis_read on public.s5_allocation_rule_basis
for select to authenticated using (public.is_active_member(organization_id));
revoke all on public.s5_allocation_rule_basis from anon,authenticated;
grant select on public.s5_allocation_rule_basis to authenticated;

-- A closed source must sit wholly inside the frozen independent basis range.
create or replace function public.s5_guard_run_effective_basis() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_start date; v_end date; v_basis record;
begin
  select start_date,end_date into v_start,v_end
  from public.accounting_periods
  where id=new.source_period_id and organization_id=new.organization_id;

  select * into v_basis
  from public.s5_allocation_rule_basis
  where rule_set_id=new.rule_set_id and organization_id=new.organization_id;

  if not found or v_start is null then
    raise exception 'allocation source/rule basis provenance is incomplete';
  end if;
  if v_start<v_basis.effective_from
     or (v_basis.effective_to is not null and v_end>v_basis.effective_to) then
    raise exception 'closed source period crosses outside the frozen allocation-basis effective range';
  end if;
  return new;
end $$;

drop trigger if exists s5_allocation_runs_effective_basis_guard on public.s5_allocation_runs;
create trigger s5_allocation_runs_effective_basis_guard
before insert on public.s5_allocation_runs
for each row execute function public.s5_guard_run_effective_basis();
