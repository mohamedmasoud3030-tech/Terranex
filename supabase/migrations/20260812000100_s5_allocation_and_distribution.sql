-- GF-008 / S5 — Allocation & Distribution.
--
-- This slice allocates a closed, approved S6 result snapshot to the exact
-- governing agreement version, posts the allocation to the existing S2
-- journal, approves a distribution liability separately from cash payment,
-- and exposes a reproducible partner-capital statement. Money is bigint minor
-- units. Allocation math is exact integer/rational arithmetic.

-- ===========================================================================
-- 1. Extend the canonical S2 semantic-account and journal-source registries.
-- ===========================================================================
drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in (
  'BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP',
  'CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE',
  'PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE'
));
insert into public.semantic_accounts(role,label_ar) values
  ('PROJECT_RESULT_CLEARING','تسوية نتيجة المشروع'),
  ('PARTNER_CAPITAL','رأس مال الشريك'),
  ('DISTRIBUTION_PAYABLE','توزيعات مستحقة الدفع')
on conflict (role) do nothing;
create trigger semantic_accounts_locked
before insert or update or delete on public.semantic_accounts
for each row execute function public.s2_guard_semantic_accounts_locked();

alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT'
));

-- Make the one-active-posting invariant generic for every material source.
create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type <> 'REVERSAL' and exists (
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
  return new;
end $$;

-- Agreement-version scope must be enforceable by a composite FK.
create unique index if not exists agreement_versions_s5_scope_key
  on public.agreement_versions(id,organization_id,project_id);

-- ===========================================================================
-- 2. Immutable allocation rule set tied to one governing agreement version.
--    A rule set is configured once; changed economics require a new agreement
--    version, never mutation of historical rules.
-- ===========================================================================
create table public.s5_allocation_rule_sets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  governing_version_id uuid not null,
  policy text not null check (policy in ('PRO_RATA','FIXED_SHARES')),
  common_denominator bigint not null check (common_denominator > 0),
  content_hash text not null check (char_length(content_hash)=64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id,idempotency_key),
  unique (organization_id,project_id,governing_version_id),
  unique (id,organization_id),
  unique (id,organization_id,project_id,governing_version_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (governing_version_id,organization_id,project_id)
    references public.agreement_versions(id,organization_id,project_id) on delete restrict
);

create table public.s5_allocation_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  governing_version_id uuid not null,
  rule_set_id uuid not null,
  participant_party_id uuid not null,
  weight_numerator bigint not null check (weight_numerator > 0),
  weight_denominator bigint not null check (weight_denominator > 0),
  created_at timestamptz not null default now(),
  unique (rule_set_id,participant_party_id),
  unique (id,organization_id),
  foreign key (rule_set_id,organization_id,project_id,governing_version_id)
    references public.s5_allocation_rule_sets(id,organization_id,project_id,governing_version_id) on delete restrict,
  foreign key (organization_id,project_id,participant_party_id)
    references public.project_participants(organization_id,project_id,party_id) on delete restrict
);
create index s5_rules_project_idx on public.s5_allocation_rules(project_id,governing_version_id);

create or replace function public.s5_guard_rule_row() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_den bigint;
begin
  select common_denominator into v_den
  from public.s5_allocation_rule_sets
  where id=new.rule_set_id and organization_id=new.organization_id
    and project_id=new.project_id and governing_version_id=new.governing_version_id;
  if v_den is null then raise exception 'allocation rule set scope mismatch'; end if;
  if new.weight_denominator <> v_den then
    raise exception 'all allocation weights must use the rule-set common denominator';
  end if;
  return new;
end $$;
create trigger s5_rule_row_scope_guard
before insert on public.s5_allocation_rules
for each row execute function public.s5_guard_rule_row();

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
create constraint trigger s5_rule_set_complete_guard
after insert on public.s5_allocation_rule_sets
deferrable initially deferred
for each row execute function public.s5_validate_rule_set_complete();

create or replace function public.s5_guard_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'approved S5 facts are append-only; correct by linked reversal and a new run';
end $$;
create trigger s5_rule_sets_immutable
before update or delete on public.s5_allocation_rule_sets
for each row execute function public.s5_guard_append_only();
create trigger s5_rules_immutable
before update or delete on public.s5_allocation_rules
for each row execute function public.s5_guard_append_only();

-- ===========================================================================
-- 3. Allocation run and deterministic line snapshot.
-- ===========================================================================
create table public.s5_allocation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  source_period_id uuid not null,
  close_run_id uuid not null,
  close_snapshot_id uuid not null,
  snapshot_content_hash text not null check (char_length(snapshot_content_hash)=64),
  snapshot_captured_at timestamptz not null,
  governing_version_id uuid not null,
  rule_set_id uuid not null,
  policy text not null check (policy in ('PRO_RATA','FIXED_SHARES')),
  algorithm_version text not null default 'S5-LARGEST-REMAINDER-V1',
  reporting_currency text not null check (reporting_currency ~ '^[A-Z]{3}$'),
  source_category text not null check (source_category in ('REALIZED_RESULT')),
  source_amount_minor_units bigint not null check (source_amount_minor_units<>0),
  status text not null default 'PREPARED' check (status in ('PREPARED','APPROVED')),
  content_hash text not null check (char_length(content_hash)=64),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  posting_date date,
  journal_batch_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash)=64),
  prior_run_id uuid,
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  unique (journal_batch_id),
  check (
    (status='PREPARED' and approved_by is null and approved_at is null and posting_date is null
      and journal_batch_id is null and approval_idempotency_key is null and approval_request_hash is null)
    or
    (status='APPROVED' and approved_by is not null and approved_at is not null and posting_date is not null
      and journal_batch_id is not null and approval_idempotency_key is not null and approval_request_hash is not null)
  ),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (source_period_id,organization_id)
    references public.accounting_periods(id,organization_id) on delete restrict,
  foreign key (close_run_id,organization_id)
    references public.close_runs(id,organization_id) on delete restrict,
  foreign key (close_snapshot_id,organization_id)
    references public.close_run_snapshots(id,organization_id) on delete restrict,
  foreign key (governing_version_id,organization_id,project_id)
    references public.agreement_versions(id,organization_id,project_id) on delete restrict,
  foreign key (rule_set_id,organization_id,project_id,governing_version_id)
    references public.s5_allocation_rule_sets(id,organization_id,project_id,governing_version_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict,
  foreign key (prior_run_id,organization_id)
    references public.s5_allocation_runs(id,organization_id) on delete restrict
);
create unique index s5_runs_approval_key
  on public.s5_allocation_runs(organization_id,approval_idempotency_key)
  where approval_idempotency_key is not null;
create unique index s5_one_approved_source
  on public.s5_allocation_runs(organization_id,close_snapshot_id,source_category)
  where status='APPROVED';
create index s5_runs_project_idx on public.s5_allocation_runs(project_id,prepared_at desc);

create table public.s5_allocation_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  run_id uuid not null,
  participant_party_id uuid not null,
  weight_numerator bigint not null check (weight_numerator>0),
  weight_denominator bigint not null check (weight_denominator>0),
  exact_floor_minor_units bigint not null,
  remainder_numerator numeric(78,0) not null check (remainder_numerator>=0),
  rounding_award_minor_units smallint not null check (rounding_award_minor_units in (0,1)),
  allocated_minor_units bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  unique (run_id,participant_party_id),
  unique (id,organization_id),
  foreign key (run_id,organization_id,project_id)
    references public.s5_allocation_runs(id,organization_id,project_id) on delete restrict,
  foreign key (participant_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict
);
create index s5_lines_run_idx on public.s5_allocation_lines(run_id);
create trigger s5_allocation_lines_immutable
before update or delete on public.s5_allocation_lines
for each row execute function public.s5_guard_append_only();

create or replace function public.s5_guard_run_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status<>'PREPARED' or new.status<>'APPROVED'
     or new.id<>old.id or new.organization_id<>old.organization_id or new.project_id<>old.project_id
     or new.source_period_id<>old.source_period_id or new.close_run_id<>old.close_run_id
     or new.close_snapshot_id<>old.close_snapshot_id or new.snapshot_content_hash<>old.snapshot_content_hash
     or new.snapshot_captured_at<>old.snapshot_captured_at or new.governing_version_id<>old.governing_version_id
     or new.rule_set_id<>old.rule_set_id or new.policy<>old.policy or new.algorithm_version<>old.algorithm_version
     or new.reporting_currency<>old.reporting_currency or new.source_category<>old.source_category
     or new.source_amount_minor_units<>old.source_amount_minor_units or new.content_hash<>old.content_hash
     or new.prepared_by<>old.prepared_by or new.prepared_at<>old.prepared_at
     or new.idempotency_key<>old.idempotency_key or new.request_hash<>old.request_hash
     or new.prior_run_id is distinct from old.prior_run_id
     or new.approved_by is null or new.approved_at is null or new.posting_date is null
     or new.journal_batch_id is null or new.approval_idempotency_key is null
     or new.approval_request_hash is null then
    raise exception 'allocation run economics are immutable; only PREPARED to APPROVED is allowed';
  end if;
  return new;
end $$;
create trigger s5_allocation_runs_transition_only
before update on public.s5_allocation_runs
for each row execute function public.s5_guard_run_transition();
create trigger s5_allocation_runs_no_delete
before delete on public.s5_allocation_runs
for each row execute function public.s5_guard_append_only();

-- ===========================================================================
-- 4. Distribution liability and append-only payment facts.
-- ===========================================================================
create table public.s5_distributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  allocation_run_id uuid not null,
  participant_party_id uuid not null,
  requested_amount_minor_units bigint not null check (requested_amount_minor_units>0),
  approved_amount_minor_units bigint,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  status text not null default 'PREPARED' check (status in ('PREPARED','APPROVED')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  approval_posting_date date,
  approval_journal_batch_id uuid,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  unique (id,organization_id,project_id),
  unique (approval_journal_batch_id),
  check (
    (status='PREPARED' and approved_amount_minor_units is null and approved_by is null and approved_at is null
      and approval_posting_date is null and approval_journal_batch_id is null
      and approval_idempotency_key is null and approval_request_hash is null)
    or
    (status='APPROVED' and approved_amount_minor_units=requested_amount_minor_units
      and approved_by is not null and approved_at is not null and approval_posting_date is not null
      and approval_journal_batch_id is not null and approval_idempotency_key is not null
      and approval_request_hash is not null)
  ),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (allocation_run_id,organization_id,project_id)
    references public.s5_allocation_runs(id,organization_id,project_id) on delete restrict,
  foreign key (participant_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict,
  foreign key (approval_journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
);
create unique index s5_distribution_approval_key
  on public.s5_distributions(organization_id,approval_idempotency_key)
  where approval_idempotency_key is not null;
create index s5_distributions_project_idx on public.s5_distributions(project_id,prepared_at desc);

create table public.s5_distribution_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  distribution_id uuid not null,
  participant_party_id uuid not null,
  cash_account_id uuid not null,
  amount_minor_units bigint not null check (amount_minor_units>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  paid_by uuid not null references auth.users(id) on delete restrict,
  paid_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash)=64),
  unique (organization_id,idempotency_key),
  unique (journal_batch_id),
  unique (id,organization_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict,
  foreign key (distribution_id,organization_id,project_id)
    references public.s5_distributions(id,organization_id,project_id) on delete restrict,
  foreign key (participant_party_id,organization_id)
    references public.parties(id,organization_id) on delete restrict,
  foreign key (cash_account_id,organization_id)
    references public.project_cash_accounts(id,organization_id) on delete restrict,
  foreign key (journal_batch_id,organization_id)
    references public.journal_batches(id,organization_id) on delete restrict
);
create index s5_distribution_payments_distribution_idx on public.s5_distribution_payments(distribution_id);
create trigger s5_distribution_payments_immutable
before update or delete on public.s5_distribution_payments
for each row execute function public.s5_guard_append_only();

create or replace function public.s5_guard_distribution_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.status<>'PREPARED' or new.status<>'APPROVED'
     or new.id<>old.id or new.organization_id<>old.organization_id or new.project_id<>old.project_id
     or new.allocation_run_id<>old.allocation_run_id or new.participant_party_id<>old.participant_party_id
     or new.requested_amount_minor_units<>old.requested_amount_minor_units or new.currency<>old.currency
     or new.evidence_reference<>old.evidence_reference or new.prepared_by<>old.prepared_by
     or new.prepared_at<>old.prepared_at or new.idempotency_key<>old.idempotency_key
     or new.request_hash<>old.request_hash or new.approved_amount_minor_units<>old.requested_amount_minor_units
     or new.approved_by is null or new.approved_at is null or new.approval_posting_date is null
     or new.approval_journal_batch_id is null or new.approval_idempotency_key is null
     or new.approval_request_hash is null then
    raise exception 'distribution economics are immutable; only PREPARED to APPROVED is allowed';
  end if;
  return new;
end $$;
create trigger s5_distributions_transition_only
before update on public.s5_distributions
for each row execute function public.s5_guard_distribution_transition();
create trigger s5_distributions_no_delete
before delete on public.s5_distributions
for each row execute function public.s5_guard_append_only();

-- ===========================================================================
-- 5. Internal authoritative balance and period helpers.
-- ===========================================================================
create or replace function public.s5_require_open_posting_date(
  p_organization_id uuid,p_project_id uuid,p_posting_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_count integer;
begin
  if p_posting_date is null then raise exception 'posting date is required'; end if;
  select min(id),count(*) into v_id,v_count
  from public.accounting_periods
  where organization_id=p_organization_id and project_id=p_project_id
    and status='OPEN' and p_posting_date between start_date and end_date;
  if v_count<>1 then raise exception 'S5 posting requires exactly one OPEN accounting period covering the posting date'; end if;
  return v_id;
end $$;
revoke all on function public.s5_require_open_posting_date(uuid,uuid,date) from public,anon,authenticated;

create or replace function public.s5_partner_capital_balance_internal(
  p_organization_id uuid,p_project_id uuid,p_party_id uuid,p_currency text
) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v numeric;
begin
  select coalesce(sum(jl.credit_minor_units::numeric-jl.debit_minor_units::numeric),0)
    into v
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.organization_id=p_organization_id and jl.project_id=p_project_id
    and jl.party_id=p_party_id and jl.currency=p_currency
    and sa.role in ('CONTRIBUTED_CAPITAL','PARTNER_CAPITAL');
  return v::bigint;
end $$;
revoke all on function public.s5_partner_capital_balance_internal(uuid,uuid,uuid,text) from public,anon,authenticated;

create or replace function public.s5_project_distributable_cash_internal(
  p_organization_id uuid,p_project_id uuid,p_currency text
) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_cash numeric:=0; v_supplier numeric:=0; v_distribution numeric:=0; v numeric;
begin
  select
    coalesce(sum(case when sa.role='BANK_CASH' then jl.debit_minor_units::numeric-jl.credit_minor_units::numeric else 0 end),0),
    coalesce(sum(case when sa.role='SUPPLIER_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0),
    coalesce(sum(case when sa.role='DISTRIBUTION_PAYABLE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric else 0 end),0)
  into v_cash,v_supplier,v_distribution
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.organization_id=p_organization_id and jl.project_id=p_project_id and jl.currency=p_currency;
  v:=greatest(v_cash-greatest(v_supplier,0)-greatest(v_distribution,0),0);
  return v::bigint;
end $$;
revoke all on function public.s5_project_distributable_cash_internal(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.s5_cash_account_balance_internal(
  p_organization_id uuid,p_project_id uuid,p_cash_account_id uuid,p_currency text
) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v numeric;
begin
  select coalesce(sum(jl.debit_minor_units::numeric-jl.credit_minor_units::numeric),0) into v
  from public.journal_lines jl
  join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='BANK_CASH'
  where jl.organization_id=p_organization_id and jl.project_id=p_project_id
    and jl.cash_account_id=p_cash_account_id and jl.currency=p_currency;
  return v::bigint;
end $$;
revoke all on function public.s5_cash_account_balance_internal(uuid,uuid,uuid,text) from public,anon,authenticated;

-- Historical realized result is derived as-of the approved close snapshot's
-- capture timestamp. Later S6 reversals therefore cannot rewrite the source of
-- an already prepared allocation, even if a reopened period shares a boundary
-- date with the closed period.
create or replace function public.s5_realized_result_as_of_snapshot(
  p_organization_id uuid,p_project_id uuid,p_close_snapshot_id uuid
) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_snapshot record; v_result numeric;
begin
  select s.id,s.captured_at,s.period_id,s.project_id,s.close_run_id,c.status,
         p.start_date,p.end_date,p.reporting_currency
    into v_snapshot
  from public.close_run_snapshots s
  join public.close_runs c on c.id=s.close_run_id and c.organization_id=s.organization_id
  join public.accounting_periods p on p.id=s.period_id and p.organization_id=s.organization_id
  where s.id=p_close_snapshot_id and s.organization_id=p_organization_id
    and s.project_id=p_project_id;
  if not found or v_snapshot.status<>'APPROVED' then raise exception 'allocation requires an approved S6 close snapshot'; end if;

  select coalesce(sum(
    case
      when sa.role='REAL_ESTATE_SALE_REVENUE' then jl.credit_minor_units::numeric-jl.debit_minor_units::numeric
      when sa.role='REAL_ESTATE_COST_OF_SALE' then -(jl.debit_minor_units::numeric-jl.credit_minor_units::numeric)
      when sa.role='PROJECT_EXPENSE' and pci.cost_category='SELLING' then -(jl.debit_minor_units::numeric-jl.credit_minor_units::numeric)
      else 0
    end
  ),0) into v_result
  from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id and jb.organization_id=jl.organization_id
  join public.semantic_accounts sa on sa.id=jl.account_id
  left join public.property_cost_items pci
    on pci.cost_obligation_id=jl.obligation_id and pci.organization_id=jl.organization_id
  where jl.organization_id=p_organization_id and jl.project_id=p_project_id
    and jl.currency=v_snapshot.reporting_currency
    and jl.transaction_date between v_snapshot.start_date and v_snapshot.end_date
    and jb.posted_at<=v_snapshot.captured_at
    and (
      sa.role in ('REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE')
      or (sa.role='PROJECT_EXPENSE' and pci.cost_category='SELLING')
    );
  return v_result::bigint;
end $$;
revoke all on function public.s5_realized_result_as_of_snapshot(uuid,uuid,uuid) from public,anon,authenticated;

-- ===========================================================================
-- 6. Rule configuration command.
-- ===========================================================================
create or replace function public.s5_configure_allocation_rules(
  p_organization_id uuid,p_project_id uuid,p_governing_version_id uuid,p_policy text,
  p_participant_party_ids uuid[],p_weight_numerators bigint[],p_common_denominator bigint,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_lines jsonb; v_existing record;
  v_expected integer; v_actual integer; v_sum numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_policy not in ('PRO_RATA','FIXED_SHARES') then raise exception 'unsupported allocation policy'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_common_denominator is null or p_common_denominator<=0 then raise exception 'allocation denominator must be positive'; end if;
  if p_participant_party_ids is null or p_weight_numerators is null
     or cardinality(p_participant_party_ids)=0
     or cardinality(p_participant_party_ids)<>cardinality(p_weight_numerators) then
    raise exception 'participant and weight arrays must be non-empty and aligned';
  end if;
  select count(distinct x) into v_actual from unnest(p_participant_party_ids) x;
  if v_actual<>cardinality(p_participant_party_ids) then raise exception 'duplicate participant in allocation rules'; end if;
  if exists(select 1 from unnest(p_weight_numerators) n where n is null or n<=0) then raise exception 'allocation weights must be positive integers'; end if;
  select coalesce(sum(n::numeric),0) into v_sum from unnest(p_weight_numerators) n;
  if v_sum<>p_common_denominator::numeric then raise exception 'allocation weights must resolve exactly to 100 percent'; end if;

  if not exists(
    select 1 from public.agreement_versions v
    where v.id=p_governing_version_id and v.organization_id=p_organization_id
      and v.project_id=p_project_id and v.status='ACTIVE'
  ) then raise exception 'allocation rules require the active governing agreement version'; end if;

  select count(*) into v_expected
  from public.commitment_terms ct
  join public.project_participants pp on pp.id=ct.participant_id
  where ct.organization_id=p_organization_id and ct.agreement_version_id=p_governing_version_id
    and pp.project_id=p_project_id and pp.role='INVESTOR';
  if v_expected<>cardinality(p_participant_party_ids) or exists(
    select 1
    from public.commitment_terms ct
    join public.project_participants pp on pp.id=ct.participant_id
    where ct.organization_id=p_organization_id and ct.agreement_version_id=p_governing_version_id
      and pp.project_id=p_project_id and pp.role='INVESTOR'
      and not (pp.party_id=any(p_participant_party_ids))
  ) then raise exception 'allocation rules must cover every investor in the governing version exactly once'; end if;

  select jsonb_agg(jsonb_build_object('party_id',x.party_id,'numerator',x.numerator) order by x.party_id::text)
    into v_lines
  from unnest(p_participant_party_ids,p_weight_numerators) as x(party_id,numerator);
  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'governing_version_id',p_governing_version_id,
    'policy',p_policy,'common_denominator',p_common_denominator,'lines',v_lines
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-rules:'||trim(p_idempotency_key),0));
  select * into v_existing from public.s5_allocation_rule_sets
    where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  if exists(select 1 from public.s5_allocation_rule_sets where organization_id=p_organization_id and project_id=p_project_id and governing_version_id=p_governing_version_id) then
    raise exception 'allocation rules are already frozen for this governing version';
  end if;

  insert into public.s5_allocation_rule_sets(
    organization_id,project_id,governing_version_id,policy,common_denominator,
    content_hash,idempotency_key,request_hash,created_by
  ) values(
    p_organization_id,p_project_id,p_governing_version_id,p_policy,p_common_denominator,
    v_hash,trim(p_idempotency_key),v_hash,v_actor
  ) returning id into v_id;

  insert into public.s5_allocation_rules(
    organization_id,project_id,governing_version_id,rule_set_id,participant_party_id,
    weight_numerator,weight_denominator
  )
  select p_organization_id,p_project_id,p_governing_version_id,v_id,x.party_id,x.numerator,p_common_denominator
  from unnest(p_participant_party_ids,p_weight_numerators) as x(party_id,numerator);

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_ALLOCATION_RULES_FROZEN','s5_allocation_rule_set',v_id,
    jsonb_build_object('project_id',p_project_id,'governing_version_id',p_governing_version_id,
      'policy',p_policy,'participant_count',cardinality(p_participant_party_ids),'content_hash',v_hash));
  return v_id;
end $$;

-- ===========================================================================
-- 7. Prepare and approve allocation.
-- ===========================================================================
create or replace function public.s5_prepare_allocation(
  p_organization_id uuid,p_project_id uuid,p_close_snapshot_id uuid,
  p_governing_version_id uuid,p_source_category text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid; v_hash text; v_request_hash text; v_existing record;
  v_snapshot record; v_rule_set record; v_source bigint; v_prior uuid; v_sign bigint; v_abs numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_source_category<>'REALIZED_RESULT' then raise exception 'S5 v1 allocates REALIZED_RESULT only'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  select s.*,c.status as close_status,p.reporting_currency,p.start_date,p.end_date
    into v_snapshot
  from public.close_run_snapshots s
  join public.close_runs c on c.id=s.close_run_id and c.organization_id=s.organization_id
  join public.accounting_periods p on p.id=s.period_id and p.organization_id=s.organization_id
  where s.id=p_close_snapshot_id and s.organization_id=p_organization_id and s.project_id=p_project_id
  for share of s,c,p;
  if not found or v_snapshot.close_status<>'APPROVED' then raise exception 'allocation requires an approved S6 close snapshot'; end if;

  select * into v_rule_set from public.s5_allocation_rule_sets
  where organization_id=p_organization_id and project_id=p_project_id
    and governing_version_id=p_governing_version_id;
  if not found then raise exception 'allocation rules are not configured for the governing version'; end if;
  if not exists(select 1 from public.agreement_versions where id=p_governing_version_id and organization_id=p_organization_id and project_id=p_project_id) then
    raise exception 'governing agreement version not found';
  end if;

  v_source:=public.s5_realized_result_as_of_snapshot(p_organization_id,p_project_id,p_close_snapshot_id);
  if v_source=0 then raise exception 'closed snapshot contains no allocable realized result'; end if;

  v_request_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'close_snapshot_id',p_close_snapshot_id,
    'governing_version_id',p_governing_version_id,'source_category',p_source_category
  )::text,'sha256'),'hex');
  v_hash:=encode(digest(jsonb_build_object(
    'snapshot_content_hash',v_snapshot.content_hash,'snapshot_captured_at',v_snapshot.captured_at,
    'source_period_id',v_snapshot.period_id,'rule_set_hash',v_rule_set.content_hash,
    'source_category',p_source_category,'source_amount_minor_units',v_source,
    'algorithm_version','S5-LARGEST-REMAINDER-V1'
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-prepare:'||trim(p_idempotency_key),0));
  select * into v_existing from public.s5_allocation_runs
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select id into v_prior from public.s5_allocation_runs
  where organization_id=p_organization_id and project_id=p_project_id
    and source_category=p_source_category
  order by prepared_at desc,id desc limit 1;

  insert into public.s5_allocation_runs(
    organization_id,project_id,source_period_id,close_run_id,close_snapshot_id,
    snapshot_content_hash,snapshot_captured_at,governing_version_id,rule_set_id,policy,
    reporting_currency,source_category,source_amount_minor_units,content_hash,
    prepared_by,idempotency_key,request_hash,prior_run_id
  ) values(
    p_organization_id,p_project_id,v_snapshot.period_id,v_snapshot.close_run_id,v_snapshot.id,
    v_snapshot.content_hash,v_snapshot.captured_at,p_governing_version_id,v_rule_set.id,v_rule_set.policy,
    v_snapshot.reporting_currency,p_source_category,v_source,v_hash,v_actor,trim(p_idempotency_key),
    v_request_hash,v_prior
  ) returning id into v_id;

  v_sign:=case when v_source<0 then -1 else 1 end;
  v_abs:=abs(v_source::numeric);
  with raw as (
    select r.participant_party_id,r.weight_numerator,r.weight_denominator,
      trunc(v_abs*r.weight_numerator::numeric/r.weight_denominator::numeric)::bigint as floor_units,
      mod(v_abs*r.weight_numerator::numeric,r.weight_denominator::numeric) as remainder_num
    from public.s5_allocation_rules r where r.rule_set_id=v_rule_set.id
  ), ranked as (
    select raw.*,
      row_number() over(order by remainder_num desc,participant_party_id::text asc) as remainder_rank,
      (v_abs-sum(floor_units::numeric) over())::bigint as residual_units
    from raw
  )
  insert into public.s5_allocation_lines(
    organization_id,project_id,run_id,participant_party_id,weight_numerator,weight_denominator,
    exact_floor_minor_units,remainder_numerator,rounding_award_minor_units,allocated_minor_units,currency
  )
  select p_organization_id,p_project_id,v_id,participant_party_id,weight_numerator,weight_denominator,
    v_sign*floor_units,remainder_num,
    case when remainder_rank<=residual_units then 1 else 0 end::smallint,
    v_sign*(floor_units+case when remainder_rank<=residual_units then 1 else 0 end),
    v_snapshot.reporting_currency
  from ranked;

  if (select coalesce(sum(allocated_minor_units),0) from public.s5_allocation_lines where run_id=v_id)<>v_source then
    raise exception 'allocation rounding invariant failed';
  end if;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_ALLOCATION_PREPARED','s5_allocation_run',v_id,
    jsonb_build_object('project_id',p_project_id,'source_period_id',v_snapshot.period_id,
      'close_snapshot_id',v_snapshot.id,'snapshot_content_hash',v_snapshot.content_hash,
      'governing_version_id',p_governing_version_id,'source_amount_minor_units',v_source,
      'currency',v_snapshot.reporting_currency,'content_hash',v_hash));
  return v_id;
end $$;

create or replace function public.s5_approve_allocation(
  p_organization_id uuid,p_run_id uuid,p_posting_date date,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_run record; v_hash text; v_batch uuid; v_clearing uuid; v_capital uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=encode(digest(jsonb_build_object('run_id',p_run_id,'posting_date',p_posting_date)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-allocation-approve:'||trim(p_idempotency_key),0));
  select * into v_run from public.s5_allocation_runs where id=p_run_id and organization_id=p_organization_id for update;
  if not found then raise exception 'allocation run not found'; end if;
  if v_run.status='APPROVED' then
    if v_run.approval_idempotency_key=trim(p_idempotency_key) and v_run.approval_request_hash=v_hash then return v_run.id; end if;
    raise exception 'allocation run is already approved';
  end if;
  if exists(select 1 from public.s5_allocation_runs where organization_id=p_organization_id and approval_idempotency_key=trim(p_idempotency_key) and id<>p_run_id) then
    raise exception 'idempotency key payload mismatch';
  end if;
  if exists(select 1 from public.s5_allocation_runs where organization_id=p_organization_id and close_snapshot_id=v_run.close_snapshot_id and source_category=v_run.source_category and status='APPROVED') then
    raise exception 'this closed source already has an approved allocation';
  end if;
  perform public.s5_require_open_posting_date(p_organization_id,v_run.project_id,p_posting_date);
  if (select coalesce(sum(allocated_minor_units),0) from public.s5_allocation_lines where run_id=p_run_id)<>v_run.source_amount_minor_units then
    raise exception 'allocation lines do not reconcile to source';
  end if;
  select id into v_clearing from public.semantic_accounts where role='PROJECT_RESULT_CLEARING';
  select id into v_capital from public.semantic_accounts where role='PARTNER_CAPITAL';

  insert into public.journal_batches(
    organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    p_organization_id,v_run.project_id,'S5_ALLOCATION',p_run_id,p_posting_date,
    trim(p_idempotency_key),v_hash,v_actor
  ) returning id into v_batch;

  if v_run.source_amount_minor_units>0 then
    insert into public.journal_lines(
      batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,party_id,transaction_date
    )
    select v_batch,p_organization_id,v_run.project_id,v_clearing,v_run.source_amount_minor_units,0,v_run.reporting_currency,null,p_posting_date
    union all
    select v_batch,p_organization_id,v_run.project_id,v_capital,0,l.allocated_minor_units,v_run.reporting_currency,l.participant_party_id,p_posting_date
    from public.s5_allocation_lines l where l.run_id=p_run_id and l.allocated_minor_units>0;
  else
    insert into public.journal_lines(
      batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,party_id,transaction_date
    )
    select v_batch,p_organization_id,v_run.project_id,v_clearing,0,abs(v_run.source_amount_minor_units),v_run.reporting_currency,null,p_posting_date
    union all
    select v_batch,p_organization_id,v_run.project_id,v_capital,abs(l.allocated_minor_units),0,v_run.reporting_currency,l.participant_party_id,p_posting_date
    from public.s5_allocation_lines l where l.run_id=p_run_id and l.allocated_minor_units<0;
  end if;

  update public.s5_allocation_runs set
    status='APPROVED',approved_by=v_actor,approved_at=now(),posting_date=p_posting_date,
    journal_batch_id=v_batch,approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash
  where id=p_run_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_ALLOCATION_APPROVED','s5_allocation_run',p_run_id,
    jsonb_build_object('project_id',v_run.project_id,'source_period_id',v_run.source_period_id,
      'close_snapshot_id',v_run.close_snapshot_id,'posting_date',p_posting_date,'journal_batch_id',v_batch,
      'amount_minor_units',v_run.source_amount_minor_units,'currency',v_run.reporting_currency));
  return p_run_id;
end $$;

-- ===========================================================================
-- 8. Prepare/approve distribution and pay an approved payable.
-- ===========================================================================
create or replace function public.s5_prepare_distribution(
  p_organization_id uuid,p_project_id uuid,p_allocation_run_id uuid,p_participant_party_id uuid,
  p_requested_amount_minor_units bigint,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_run record; v_id uuid; v_hash text; v_existing record; v_capital bigint; v_cash bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_requested_amount_minor_units is null or p_requested_amount_minor_units<=0 then raise exception 'distribution amount must be positive'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'distribution evidence reference is required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  select * into v_run from public.s5_allocation_runs
  where id=p_allocation_run_id and organization_id=p_organization_id and project_id=p_project_id;
  if not found or v_run.status<>'APPROVED' then raise exception 'distribution requires an approved allocation run'; end if;
  if v_run.source_amount_minor_units<=0 then raise exception 'a loss allocation cannot create a distribution'; end if;
  if not exists(select 1 from public.s5_allocation_lines where run_id=p_allocation_run_id and participant_party_id=p_participant_party_id and allocated_minor_units>0) then
    raise exception 'participant has no positive allocation in this run';
  end if;
  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'allocation_run_id',p_allocation_run_id,'participant_party_id',p_participant_party_id,
    'requested_amount_minor_units',p_requested_amount_minor_units,'evidence_reference',trim(p_evidence_reference)
  )::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-distribution-prepare:'||trim(p_idempotency_key),0));
  select * into v_existing from public.s5_distributions where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  v_capital:=public.s5_partner_capital_balance_internal(p_organization_id,p_project_id,p_participant_party_id,v_run.reporting_currency);
  v_cash:=public.s5_project_distributable_cash_internal(p_organization_id,p_project_id,v_run.reporting_currency);
  if p_requested_amount_minor_units>v_capital then raise exception 'requested distribution exceeds participant capital available'; end if;
  if p_requested_amount_minor_units>v_cash then raise exception 'requested distribution exceeds project distributable cash'; end if;
  insert into public.s5_distributions(
    organization_id,project_id,allocation_run_id,participant_party_id,requested_amount_minor_units,
    currency,evidence_reference,prepared_by,idempotency_key,request_hash
  ) values(
    p_organization_id,p_project_id,p_allocation_run_id,p_participant_party_id,p_requested_amount_minor_units,
    v_run.reporting_currency,trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_DISTRIBUTION_PREPARED','s5_distribution',v_id,
    jsonb_build_object('project_id',p_project_id,'allocation_run_id',p_allocation_run_id,
      'participant_party_id',p_participant_party_id,'requested_amount_minor_units',p_requested_amount_minor_units,
      'currency',v_run.reporting_currency,'evidence_reference',trim(p_evidence_reference)));
  return v_id;
end $$;

create or replace function public.s5_approve_distribution(
  p_organization_id uuid,p_distribution_id uuid,p_posting_date date,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_dist record; v_hash text; v_capital bigint; v_cash bigint;
  v_batch uuid; v_capital_account uuid; v_payable uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=encode(digest(jsonb_build_object('distribution_id',p_distribution_id,'posting_date',p_posting_date)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-distribution-approve:'||trim(p_idempotency_key),0));
  select * into v_dist from public.s5_distributions where id=p_distribution_id and organization_id=p_organization_id for update;
  if not found then raise exception 'distribution not found'; end if;
  if v_dist.status='APPROVED' then
    if v_dist.approval_idempotency_key=trim(p_idempotency_key) and v_dist.approval_request_hash=v_hash then return v_dist.id; end if;
    raise exception 'distribution is already approved';
  end if;
  if exists(select 1 from public.s5_distributions where organization_id=p_organization_id and approval_idempotency_key=trim(p_idempotency_key) and id<>p_distribution_id) then
    raise exception 'idempotency key payload mismatch';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-distribution-capacity:'||v_dist.project_id::text,0));
  perform public.s5_require_open_posting_date(p_organization_id,v_dist.project_id,p_posting_date);
  v_capital:=public.s5_partner_capital_balance_internal(p_organization_id,v_dist.project_id,v_dist.participant_party_id,v_dist.currency);
  v_cash:=public.s5_project_distributable_cash_internal(p_organization_id,v_dist.project_id,v_dist.currency);
  if v_dist.requested_amount_minor_units>v_capital then raise exception 'distribution approval exceeds participant capital available'; end if;
  if v_dist.requested_amount_minor_units>v_cash then raise exception 'distribution approval exceeds project distributable cash'; end if;
  select id into v_capital_account from public.semantic_accounts where role='PARTNER_CAPITAL';
  select id into v_payable from public.semantic_accounts where role='DISTRIBUTION_PAYABLE';
  insert into public.journal_batches(
    organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    p_organization_id,v_dist.project_id,'S5_DISTRIBUTION_APPROVAL',p_distribution_id,p_posting_date,
    trim(p_idempotency_key),v_hash,v_actor
  ) returning id into v_batch;
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,party_id,transaction_date
  ) values
    (v_batch,p_organization_id,v_dist.project_id,v_capital_account,v_dist.requested_amount_minor_units,0,v_dist.currency,v_dist.participant_party_id,p_posting_date),
    (v_batch,p_organization_id,v_dist.project_id,v_payable,0,v_dist.requested_amount_minor_units,v_dist.currency,v_dist.participant_party_id,p_posting_date);
  update public.s5_distributions set
    status='APPROVED',approved_amount_minor_units=requested_amount_minor_units,approved_by=v_actor,approved_at=now(),
    approval_posting_date=p_posting_date,approval_journal_batch_id=v_batch,
    approval_idempotency_key=trim(p_idempotency_key),approval_request_hash=v_hash
  where id=p_distribution_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_DISTRIBUTION_APPROVED','s5_distribution',p_distribution_id,
    jsonb_build_object('project_id',v_dist.project_id,'participant_party_id',v_dist.participant_party_id,
      'amount_minor_units',v_dist.requested_amount_minor_units,'currency',v_dist.currency,
      'posting_date',p_posting_date,'journal_batch_id',v_batch));
  return p_distribution_id;
end $$;

create or replace function public.s5_pay_distribution(
  p_organization_id uuid,p_distribution_id uuid,p_cash_account_id uuid,p_amount_minor_units bigint,
  p_payment_date date,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_dist record; v_existing record; v_hash text; v_paid numeric; v_outstanding numeric;
  v_cash bigint; v_payment_id uuid:=gen_random_uuid(); v_batch uuid; v_payable uuid; v_bank uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'distribution payment amount must be positive'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'payment evidence reference is required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=encode(digest(jsonb_build_object(
    'distribution_id',p_distribution_id,'cash_account_id',p_cash_account_id,'amount_minor_units',p_amount_minor_units,
    'payment_date',p_payment_date,'evidence_reference',trim(p_evidence_reference)
  )::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-distribution-pay:'||trim(p_idempotency_key),0));
  select * into v_existing from public.s5_distribution_payments where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_dist from public.s5_distributions where id=p_distribution_id and organization_id=p_organization_id for update;
  if not found or v_dist.status<>'APPROVED' then raise exception 'payment requires an approved distribution payable'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s5-distribution-capacity:'||v_dist.project_id::text,0));
  perform public.s5_require_open_posting_date(p_organization_id,v_dist.project_id,p_payment_date);
  if not exists(select 1 from public.project_cash_accounts ca where ca.id=p_cash_account_id and ca.organization_id=p_organization_id and ca.project_id=v_dist.project_id and ca.currency=v_dist.currency) then
    raise exception 'cash account does not belong to the distribution project and currency';
  end if;
  select coalesce(sum(p.amount_minor_units::numeric),0) into v_paid
  from public.s5_distribution_payments p
  where p.distribution_id=p_distribution_id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=p.journal_batch_id);
  v_outstanding:=v_dist.approved_amount_minor_units::numeric-v_paid;
  if p_amount_minor_units::numeric>v_outstanding then raise exception 'distribution payment exceeds approved outstanding payable'; end if;
  v_cash:=public.s5_cash_account_balance_internal(p_organization_id,v_dist.project_id,p_cash_account_id,v_dist.currency);
  if p_amount_minor_units>v_cash then raise exception 'distribution payment exceeds cash account balance'; end if;
  select id into v_payable from public.semantic_accounts where role='DISTRIBUTION_PAYABLE';
  select id into v_bank from public.semantic_accounts where role='BANK_CASH';
  insert into public.journal_batches(
    organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by
  ) values(
    p_organization_id,v_dist.project_id,'S5_DISTRIBUTION_PAYMENT',v_payment_id,p_payment_date,
    trim(p_idempotency_key),v_hash,v_actor
  ) returning id into v_batch;
  insert into public.journal_lines(
    batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,cash_account_id,party_id,transaction_date
  ) values
    (v_batch,p_organization_id,v_dist.project_id,v_payable,p_amount_minor_units,0,v_dist.currency,null,v_dist.participant_party_id,p_payment_date),
    (v_batch,p_organization_id,v_dist.project_id,v_bank,0,p_amount_minor_units,v_dist.currency,p_cash_account_id,null,p_payment_date);
  insert into public.s5_distribution_payments(
    id,organization_id,project_id,distribution_id,participant_party_id,cash_account_id,
    amount_minor_units,currency,payment_date,evidence_reference,journal_batch_id,paid_by,idempotency_key,request_hash
  ) values(
    v_payment_id,p_organization_id,v_dist.project_id,p_distribution_id,v_dist.participant_party_id,p_cash_account_id,
    p_amount_minor_units,v_dist.currency,p_payment_date,trim(p_evidence_reference),v_batch,v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'S5_DISTRIBUTION_PAID','s5_distribution_payment',v_payment_id,
    jsonb_build_object('project_id',v_dist.project_id,'distribution_id',p_distribution_id,
      'participant_party_id',v_dist.participant_party_id,'cash_account_id',p_cash_account_id,
      'amount_minor_units',p_amount_minor_units,'currency',v_dist.currency,'payment_date',p_payment_date,
      'journal_batch_id',v_batch));
  return v_payment_id;
end $$;

-- ===========================================================================
-- 9. Read models: frozen allocation, distribution settlement, capacity bridge,
--    and exact investor/partner capital rollforward.
-- ===========================================================================
create or replace view public.s5_allocation_runs_read with (security_invoker=on) as
select r.id as allocation_run_id,r.organization_id,r.project_id,r.source_period_id,r.close_run_id,
  r.close_snapshot_id,r.snapshot_content_hash,r.snapshot_captured_at,r.governing_version_id,r.rule_set_id,
  r.policy,r.algorithm_version,r.reporting_currency,r.source_category,r.source_amount_minor_units::text,
  r.status,r.content_hash,r.prepared_by,r.prepared_at,r.approved_by,r.approved_at,r.posting_date,
  r.journal_batch_id,r.prior_run_id,
  coalesce((select sum(l.allocated_minor_units) from public.s5_allocation_lines l where l.run_id=r.id),0)::text as allocated_total_minor_units,
  (select count(*) from public.s5_allocation_lines l where l.run_id=r.id) as line_count,
  exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=r.journal_batch_id) as is_reversed
from public.s5_allocation_runs r;

create or replace view public.s5_allocation_lines_read with (security_invoker=on) as
select l.id as allocation_line_id,l.organization_id,l.project_id,l.run_id,l.participant_party_id,p.legal_name,
  l.weight_numerator::text,l.weight_denominator::text,l.exact_floor_minor_units::text,
  l.remainder_numerator::text,l.rounding_award_minor_units,l.allocated_minor_units::text,l.currency
from public.s5_allocation_lines l
join public.parties p on p.id=l.participant_party_id and p.organization_id=l.organization_id;

create or replace view public.s5_distributions_read with (security_invoker=on) as
select d.id as distribution_id,d.organization_id,d.project_id,d.allocation_run_id,d.participant_party_id,
  p.legal_name,d.requested_amount_minor_units::text,d.approved_amount_minor_units::text,d.currency,
  d.evidence_reference,d.status,d.prepared_by,d.prepared_at,d.approved_by,d.approved_at,
  d.approval_posting_date,d.approval_journal_batch_id,
  coalesce(pay.paid,0)::text as paid_minor_units,
  greatest(coalesce(d.approved_amount_minor_units,0)::numeric-coalesce(pay.paid,0),0)::text as outstanding_minor_units,
  case
    when d.status='PREPARED' then 'PREPARED'
    when coalesce(pay.paid,0)=0 then 'APPROVED'
    when coalesce(pay.paid,0)<d.approved_amount_minor_units then 'PARTIALLY_PAID'
    else 'PAID'
  end as settlement_status
from public.s5_distributions d
join public.parties p on p.id=d.participant_party_id and p.organization_id=d.organization_id
left join lateral (
  select coalesce(sum(dp.amount_minor_units::numeric),0) as paid
  from public.s5_distribution_payments dp
  where dp.distribution_id=d.id
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=dp.journal_batch_id)
) pay on true;

create or replace view public.s5_distribution_capacity_read with (security_invoker=on) as
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
  greatest(cash-greatest(supplier_payable,0)-greatest(distribution_payable,0),0)::text as distributable_cash_minor_units
from project_role_balances;

create or replace view public.s5_partner_capital_statement_read with (security_invoker=on) as
with investor as (
  select distinct pp.organization_id,pp.project_id,pp.party_id
  from public.project_participants pp where pp.role='INVESTOR'
), active_source_lines as (
  select jl.organization_id,jl.project_id,jl.party_id,jl.currency,sa.role,jb.source_type,
    jl.debit_minor_units::numeric debit,jl.credit_minor_units::numeric credit
  from public.journal_lines jl
  join public.journal_batches jb on jb.id=jl.batch_id and jb.organization_id=jl.organization_id
  join public.semantic_accounts sa on sa.id=jl.account_id
  where jl.party_id is not null and jb.source_type<>'REVERSAL'
    and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
), ledger as (
  select organization_id,project_id,party_id,currency,
    coalesce(sum(case when role='CONTRIBUTED_CAPITAL' then credit-debit else 0 end),0) contributions,
    coalesce(sum(case when role='PARTNER_CAPITAL' and source_type='S5_ALLOCATION' and credit>debit then credit-debit else 0 end),0) allocated_income,
    coalesce(sum(case when role='PARTNER_CAPITAL' and source_type='S5_ALLOCATION' and debit>credit then debit-credit else 0 end),0) allocated_loss,
    coalesce(sum(case when role='PARTNER_CAPITAL' and source_type='S5_DISTRIBUTION_APPROVAL' then debit-credit else 0 end),0) distributions
  from active_source_lines
  group by organization_id,project_id,party_id,currency
), paid as (
  select dp.organization_id,dp.project_id,dp.participant_party_id as party_id,dp.currency,
    coalesce(sum(dp.amount_minor_units::numeric),0) paid
  from public.s5_distribution_payments dp
  where not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=dp.journal_batch_id)
  group by dp.organization_id,dp.project_id,dp.participant_party_id,dp.currency
)
select i.organization_id,i.project_id,i.party_id as participant_party_id,p.legal_name,pr.reporting_currency as currency,
  '0'::text as opening_capital_minor_units,
  coalesce(l.contributions,0)::text as contributions_minor_units,
  coalesce(l.allocated_income,0)::text as allocated_income_minor_units,
  coalesce(l.allocated_loss,0)::text as allocated_loss_minor_units,
  coalesce(l.distributions,0)::text as approved_distributions_minor_units,
  coalesce(pd.paid,0)::text as paid_distributions_minor_units,
  (coalesce(l.contributions,0)+coalesce(l.allocated_income,0)-coalesce(l.allocated_loss,0)-coalesce(l.distributions,0))::text as closing_capital_minor_units
from investor i
join public.parties p on p.id=i.party_id and p.organization_id=i.organization_id
join public.investment_projects pr on pr.id=i.project_id and pr.organization_id=i.organization_id
left join ledger l on l.organization_id=i.organization_id and l.project_id=i.project_id and l.party_id=i.party_id and l.currency=pr.reporting_currency
left join paid pd on pd.organization_id=i.organization_id and pd.project_id=i.project_id and pd.party_id=i.party_id and pd.currency=pr.reporting_currency;

create or replace view public.s5_rule_sets_read with (security_invoker=on) as
select rs.id as rule_set_id,rs.organization_id,rs.project_id,rs.governing_version_id,rs.policy,
  rs.common_denominator::text,rs.content_hash,rs.created_by,rs.created_at,
  (select count(*) from public.s5_allocation_rules r where r.rule_set_id=rs.id) as participant_count
from public.s5_allocation_rule_sets rs;

-- ===========================================================================
-- 10. RLS/default deny and exact command permissions.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    's5_allocation_rule_sets','s5_allocation_rules','s5_allocation_runs','s5_allocation_lines',
    's5_distributions','s5_distribution_payments'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

grant select on public.s5_rule_sets_read,public.s5_allocation_runs_read,public.s5_allocation_lines_read,
  public.s5_distributions_read,public.s5_distribution_capacity_read,public.s5_partner_capital_statement_read
to authenticated;

revoke all on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text) from public,anon;
revoke all on function public.s5_prepare_allocation(uuid,uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.s5_approve_allocation(uuid,uuid,date,text) from public,anon;
revoke all on function public.s5_prepare_distribution(uuid,uuid,uuid,uuid,bigint,text,text) from public,anon;
revoke all on function public.s5_approve_distribution(uuid,uuid,date,text) from public,anon;
revoke all on function public.s5_pay_distribution(uuid,uuid,uuid,bigint,date,text,text) from public,anon;

grant execute on function public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text),
  public.s5_prepare_allocation(uuid,uuid,uuid,uuid,text,text),
  public.s5_approve_allocation(uuid,uuid,date,text),
  public.s5_prepare_distribution(uuid,uuid,uuid,uuid,bigint,text,text),
  public.s5_approve_distribution(uuid,uuid,date,text),
  public.s5_pay_distribution(uuid,uuid,uuid,bigint,date,text,text)
to authenticated;
