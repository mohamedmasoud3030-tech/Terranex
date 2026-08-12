-- GF-008 / S5 — Allocation & Distribution (forward-only)
-- Exact minor-unit arithmetic; source is an approved immutable S6 snapshot.

drop trigger if exists semantic_accounts_locked on public.semantic_accounts;
alter table public.semantic_accounts drop constraint if exists semantic_accounts_role_check;
alter table public.semantic_accounts add constraint semantic_accounts_role_check check (role in
 ('BANK_CASH','CONTRIBUTED_CAPITAL','SUPPLIER_PAYABLE','PROJECT_EXPENSE','DEVELOPMENT_WIP','CUSTOMER_RECEIVABLE','REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE','PROJECT_RESULT_CLEARING','PARTNER_CAPITAL','DISTRIBUTION_PAYABLE'));
insert into public.semantic_accounts(role,label_ar) values
 ('PROJECT_RESULT_CLEARING','تسوية نتيجة المشروع'),('PARTNER_CAPITAL','رأس مال الشريك'),('DISTRIBUTION_PAYABLE','توزيعات مستحقة الدفع') on conflict (role) do nothing;
create trigger semantic_accounts_locked before insert or update or delete on public.semantic_accounts for each row execute function public.s2_guard_semantic_accounts_locked();
alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in ('CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL','PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION','S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT'));

create table public.s5_allocation_rules (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 project_id uuid not null references public.investment_projects(id),
 governing_version_id uuid not null,
 participant_party_id uuid not null,
 policy text not null check(policy in ('PRO_RATA','FIXED_SHARES')),
 weight_numerator bigint not null check(weight_numerator>0),
 weight_denominator bigint not null check(weight_denominator>0),
 version integer not null default 1 check(version > 0),
 prepared_by uuid not null references auth.users(id),
 prepared_at timestamptz not null default now(),
 unique(organization_id,project_id,governing_version_id,participant_party_id),
 unique(id,organization_id),
 foreign key(participant_party_id,organization_id) references public.parties(id,organization_id),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id),
 foreign key(governing_version_id,organization_id) references public.agreement_versions(id,organization_id)
);

create table public.s5_allocation_runs (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 project_id uuid not null references public.investment_projects(id),
 period_id uuid not null,
 close_run_id uuid not null,
 close_snapshot_id uuid not null,
 snapshot_content_hash text not null check(length(snapshot_content_hash)=64),
 governing_version_id uuid not null,
 policy text not null check(policy in('PRO_RATA','FIXED_SHARES')),
 algorithm_version text not null default 'S5-LARGEST-REMAINDER-V1',
 reporting_currency text not null check(reporting_currency ~ '^[A-Z]{3}$'),
 source_category text not null,
 source_amount_minor_units bigint not null check(source_amount_minor_units>=0),
 status text not null default 'PREPARED' check(status in('PREPARED','APPROVED')),
 content_hash text not null check(length(content_hash)=64),
 prepared_by uuid not null references auth.users(id),
 prepared_at timestamptz not null default now(),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 idempotency_key text not null,
 request_hash text not null check(length(request_hash)=64),
 prior_run_id uuid references public.s5_allocation_runs(id),
 unique(organization_id,idempotency_key),
 unique(id,organization_id),
 foreign key(close_snapshot_id,organization_id) references public.close_run_snapshots(id,organization_id),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id),
 foreign key(period_id,organization_id) references public.accounting_periods(id,organization_id),
 foreign key(close_run_id,organization_id) references public.close_runs(id,organization_id),
 foreign key(governing_version_id,organization_id) references public.agreement_versions(id,organization_id)
);

create table public.s5_allocation_lines (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 run_id uuid not null,
 participant_party_id uuid not null,
 weight_numerator bigint not null,
 weight_denominator bigint not null,
 exact_floor_minor_units bigint not null,
 remainder_numerator numeric(78,0) not null,
 allocated_minor_units bigint not null check(allocated_minor_units>=0),
 currency text not null check(currency ~ '^[A-Z]{3}$'),
 unique(run_id,participant_party_id),
 unique(id,organization_id),
 foreign key(run_id,organization_id) references public.s5_allocation_runs(id,organization_id),
 foreign key(participant_party_id,organization_id) references public.parties(id,organization_id)
);

create table public.s5_distributions (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 project_id uuid not null references public.investment_projects(id),
 allocation_run_id uuid not null,
 participant_party_id uuid not null,
 amount_minor_units bigint not null check(amount_minor_units>0),
 approved_amount_minor_units bigint,
 paid_minor_units bigint not null default 0 check(paid_minor_units>=0),
 status text not null default 'PREPARED' check(status in('PREPARED','APPROVED','PARTIALLY_PAID','PAID')),
 currency text not null check(currency ~ '^[A-Z]{3}$'),
 prepared_by uuid not null references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 idempotency_key text not null,
 request_hash text not null check(length(request_hash)=64),
 unique(organization_id,idempotency_key),
 unique(id,organization_id),
 foreign key(allocation_run_id,organization_id) references public.s5_allocation_runs(id,organization_id),
 foreign key(participant_party_id,organization_id) references public.parties(id,organization_id),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id)
);

create table public.s5_distribution_payments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 distribution_id uuid not null,
 project_id uuid not null,
 amount_minor_units bigint not null check(amount_minor_units>0),
 payment_date date not null,
 idempotency_key text not null,
 request_hash text not null check(length(request_hash)=64),
 unique(organization_id,idempotency_key),
 unique(id,organization_id),
 foreign key(distribution_id,organization_id) references public.s5_distributions(id,organization_id),
 foreign key(project_id,organization_id) references public.investment_projects(id,organization_id)
);

-- Commands are SECURITY DEFINER and deliberately do not expose browser writes.
create or replace function public.s5_prepare_allocation(
 p_organization_id uuid,p_project_id uuid,p_close_snapshot_id uuid,p_governing_version_id uuid,
 p_source_category text,p_source_amount_minor_units bigint,p_policy text,p_reporting_currency text,
 p_idempotency_key text,p_request_hash text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 v_id uuid;
 v_actor uuid:=auth.uid();
 v_snapshot record;
begin
 if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
 select s.*,c.status close_status into v_snapshot
 from public.close_run_snapshots s
 join public.close_runs c on c.id=s.close_run_id and c.organization_id=s.organization_id
 where s.id=p_close_snapshot_id and s.organization_id=p_organization_id
 for share;
 if v_snapshot.close_status<>'APPROVED' then raise exception 'allocation requires approved snapshot'; end if;
 if v_snapshot.project_id <> p_project_id then raise exception 'snapshot does not belong to project'; end if;
 insert into public.s5_allocation_runs(
   organization_id,project_id,period_id,close_run_id,close_snapshot_id,snapshot_content_hash,
   governing_version_id,policy,reporting_currency,source_category,source_amount_minor_units,
   content_hash,prepared_by,idempotency_key,request_hash
 ) values(
   p_organization_id,p_project_id,v_snapshot.period_id,v_snapshot.close_run_id,v_snapshot.id,
   v_snapshot.content_hash,p_governing_version_id,p_policy,p_reporting_currency,p_source_category,
   p_source_amount_minor_units,encode(digest(p_request_hash||v_snapshot.content_hash,'sha256'),'hex'),
   v_actor,p_idempotency_key,p_request_hash
 ) on conflict(organization_id,idempotency_key) do update
   set request_hash=excluded.request_hash
 returning id into v_id;
 return v_id;
end $$;

create or replace function public.s5_approve_allocation(
 p_run_id uuid,p_organization_id uuid,p_idempotency_key text,p_request_hash text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v uuid;
begin
 if not exists(select 1 from public.memberships where organization_id=p_organization_id and user_id=auth.uid() and role='OWNER' and status='ACTIVE') then raise exception 'owner approval required'; end if;
 update public.s5_allocation_runs
 set status='APPROVED',approved_by=auth.uid(),approved_at=now()
 where id=p_run_id and organization_id=p_organization_id and status='PREPARED'
 returning id into v;
 if v is null then raise exception 'run unavailable or already approved'; end if;
 return v;
end $$;

revoke all on function public.s5_prepare_allocation(uuid,uuid,uuid,uuid,text,bigint,text,text,text,text),public.s5_approve_allocation(uuid,uuid,text,text) from public,anon;
grant execute on function public.s5_prepare_allocation(uuid,uuid,uuid,uuid,text,bigint,text,text,text,text),public.s5_approve_allocation(uuid,uuid,text,text) to authenticated;

alter table public.s5_allocation_rules enable row level security;
alter table public.s5_allocation_runs enable row level security;
alter table public.s5_allocation_lines enable row level security;
alter table public.s5_distributions enable row level security;
alter table public.s5_distribution_payments enable row level security;
create policy s5_rules_read on public.s5_allocation_rules for select to authenticated using(public.is_active_member(organization_id));
create policy s5_runs_read on public.s5_allocation_runs for select to authenticated using(public.is_active_member(organization_id));
create policy s5_lines_read on public.s5_allocation_lines for select to authenticated using(public.is_active_member(organization_id));
create policy s5_dist_read on public.s5_distributions for select to authenticated using(public.is_active_member(organization_id));
create policy s5_pay_read on public.s5_distribution_payments for select to authenticated using(public.is_active_member(organization_id));
revoke all on public.s5_allocation_rules,public.s5_allocation_runs,public.s5_allocation_lines,public.s5_distributions,public.s5_distribution_payments from anon,authenticated;
grant select on public.s5_allocation_rules,public.s5_allocation_runs,public.s5_allocation_lines,public.s5_distributions,public.s5_distribution_payments to authenticated;

create or replace view public.s5_allocation_runs_read with(security_invoker=on) as
select * from public.s5_allocation_runs;

create or replace view public.s5_partner_capital_statement_read with(security_invoker=on) as
select
  jl.organization_id,
  jl.project_id,
  jl.party_id as participant_party_id,
  sum(case when sa.role='PARTNER_CAPITAL' then jl.credit_minor_units-jl.debit_minor_units else 0 end)::text as closing_capital
from public.journal_lines jl
join public.journal_batches jb on jb.id=jl.batch_id and jb.organization_id=jl.organization_id
join public.semantic_accounts sa on sa.id=jl.account_id
group by jl.organization_id,jl.project_id,jl.party_id;

grant select on public.s5_allocation_runs_read,public.s5_partner_capital_statement_read to authenticated;
