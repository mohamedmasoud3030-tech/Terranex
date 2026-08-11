-- GF-003 / S1 — Terms & Funding vertical slice.
-- Delivers: parties/participants, immutable activated agreement versions with
-- commitment terms, issued capital calls, idempotent contributions, and an
-- exact derived partner/project capital rollforward. No GL, no ownership terms,
-- no approvals engine, no distributions in this slice.

-- 1. Project lifecycle gains FUNDING (entered when an agreement activates).
alter table public.investment_projects
  drop constraint if exists investment_projects_lifecycle_state_check;
alter table public.investment_projects
  add constraint investment_projects_lifecycle_state_check
  check (lifecycle_state in ('DRAFT','FUNDING'));

-- 2. Parties (tenant-scoped identity). Minimum depth: a legal name and kind.
create table if not exists public.parties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  legal_name text not null check (char_length(trim(legal_name)) between 2 and 160),
  party_type text not null default 'PERSON' check (party_type in ('PERSON','ORGANIZATION')),
  created_at timestamptz not null default now(),
  unique (id, organization_id)
);
create index if not exists parties_org_idx on public.parties(organization_id);

-- 3. Project participants. S1 only needs investors; the role is constrained now
--    so later roles are an explicit, reviewed change rather than free text.
create table if not exists public.project_participants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  party_id uuid not null references public.parties(id) on delete restrict,
  role text not null check (role in ('INVESTOR')),
  created_at timestamptz not null default now(),
  unique (organization_id, project_id, party_id),
  unique (organization_id, id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict
);
create index if not exists participants_project_idx on public.project_participants(project_id);

-- 4. Investment agreement envelope. One agreement per project in S1; a new
--    version supersedes the prior active version atomically.
create table if not exists public.investment_agreements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','SUPERSEDED')),
  current_version_id uuid,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists agreements_project_idx on public.investment_agreements(project_id);
-- At most one agreement envelope per project in S1 (revised via versions).
create unique index if not exists agreements_one_per_project
  on public.investment_agreements(project_id);

-- 5. Agreement versions. A version is an immutable snapshot once ACTIVE.
create table if not exists public.agreement_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  agreement_id uuid not null references public.investment_agreements(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  version_no integer not null check (version_no > 0),
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','SUPERSEDED')),
  effective_date date not null,
  terms_hash text not null,
  activated_at timestamptz,
  activated_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (agreement_id, version_no),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (agreement_id, organization_id)
    references public.investment_agreements(id, organization_id) on delete restrict
);
-- At most one active version per project.
create unique index if not exists agreement_versions_one_active
  on public.agreement_versions(project_id) where status = 'ACTIVE';

-- 6. Commitment terms belong to a specific version and freeze with it.
create table if not exists public.commitment_terms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  agreement_version_id uuid not null references public.agreement_versions(id) on delete restrict,
  participant_id uuid not null references public.project_participants(id) on delete restrict,
  commitment_minor_units bigint not null check (commitment_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  unique (agreement_version_id, participant_id),
  foreign key (organization_id, agreement_version_id)
    references public.agreement_versions(organization_id, id) on delete restrict,
  foreign key (organization_id, participant_id)
    references public.project_participants(organization_id, id) on delete restrict
);

-- 7. Capital calls and lines. A call is issued against an active agreement
--    version and never mutates economics after issue; it can only be cancelled.
create table if not exists public.capital_calls (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  agreement_version_id uuid not null references public.agreement_versions(id) on delete restrict,
  status text not null default 'ISSUED' check (status in ('ISSUED','CANCELLED')),
  reference text,
  due_date date not null,
  issued_at timestamptz not null default now(),
  issued_by uuid references auth.users(id) on delete restrict,
  cancelled_at timestamptz,
  unique (organization_id, id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, agreement_version_id)
    references public.agreement_versions(organization_id, id) on delete restrict
);
create index if not exists capital_calls_version_idx on public.capital_calls(agreement_version_id);

create table if not exists public.capital_call_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  capital_call_id uuid not null references public.capital_calls(id) on delete restrict,
  participant_id uuid not null references public.project_participants(id) on delete restrict,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  foreign key (organization_id, capital_call_id)
    references public.capital_calls(organization_id, id) on delete restrict,
  foreign key (organization_id, participant_id)
    references public.project_participants(organization_id, id) on delete restrict,
  unique (capital_call_id, participant_id)
);

-- 8. Contributions: append-only posted facts. The idempotency key guarantees a
--    retried command cannot create a second economic effect.
create table if not exists public.contributions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  agreement_version_id uuid not null references public.agreement_versions(id) on delete restrict,
  capital_call_id uuid not null references public.capital_calls(id) on delete restrict,
  participant_id uuid not null references public.project_participants(id) on delete restrict,
  contribution_minor_units bigint not null check (contribution_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  occurred_on date not null,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recorded_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, agreement_version_id)
    references public.agreement_versions(organization_id, id) on delete restrict,
  foreign key (organization_id, capital_call_id)
    references public.capital_calls(organization_id, id) on delete restrict,
  foreign key (organization_id, participant_id)
    references public.project_participants(organization_id, id) on delete restrict
);
create index if not exists contributions_project_idx on public.contributions(project_id);
create index if not exists contributions_call_idx on public.contributions(capital_call_id);

-- 9. RLS: default deny, member reads, no browser writes.
alter table public.parties enable row level security;
alter table public.project_participants enable row level security;
alter table public.investment_agreements enable row level security;
alter table public.agreement_versions enable row level security;
alter table public.commitment_terms enable row level security;
alter table public.capital_calls enable row level security;
alter table public.capital_call_lines enable row level security;
alter table public.contributions enable row level security;
alter table public.parties force row level security;
alter table public.project_participants force row level security;
alter table public.investment_agreements force row level security;
alter table public.agreement_versions force row level security;
alter table public.commitment_terms force row level security;
alter table public.capital_calls force row level security;
alter table public.capital_call_lines force row level security;
alter table public.contributions force row level security;

create policy parties_read on public.parties for select to authenticated
  using (public.is_active_member(organization_id));
create policy participants_read on public.project_participants for select to authenticated
  using (public.is_active_member(organization_id));
create policy agreements_read on public.investment_agreements for select to authenticated
  using (public.is_active_member(organization_id));
create policy versions_read on public.agreement_versions for select to authenticated
  using (public.is_active_member(organization_id));
create policy commitments_read on public.commitment_terms for select to authenticated
  using (public.is_active_member(organization_id));
create policy calls_read on public.capital_calls for select to authenticated
  using (public.is_active_member(organization_id));
create policy call_lines_read on public.capital_call_lines for select to authenticated
  using (public.is_active_member(organization_id));
create policy contributions_read on public.contributions for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.parties, public.project_participants, public.investment_agreements,
  public.agreement_versions, public.commitment_terms, public.capital_calls,
  public.capital_call_lines, public.contributions from anon, authenticated;
grant select on public.parties, public.project_participants, public.investment_agreements,
  public.agreement_versions, public.commitment_terms, public.capital_calls,
  public.capital_call_lines, public.contributions to authenticated;
-- Browser clients never hold INSERT/UPDATE/DELETE on tenant-owned tables. The
-- single temporary UPDATE below is exercised only by the S1 test suite to prove
-- the immutability trigger rejects it; we revoke it again after the assertion.
-- In normal runtime there is no direct table write path.

-- 10. Immutability guards.
create or replace function public.s1_guard_agreement_version_immutable() returns trigger language plpgsql as $$
begin
  if old is not null and old.status <> 'DRAFT' then
    raise exception using
      message = 'agreement version is immutable once activated',
      errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;

create or replace function public.s1_guard_commitment_terms_immutable() returns trigger language plpgsql as $$
declare v_status text;
begin
  select status into v_status from public.agreement_versions where id = old.agreement_version_id;
  if v_status is not null and v_status <> 'DRAFT' then
    raise exception using
      message = 'commitment terms are immutable once the agreement version is activated',
      errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;

create or replace function public.s1_guard_append_only() returns trigger language plpgsql as $$
begin
  raise exception using
    message = case tg_table_name
      when 'contributions' then 'contributions are append-only posted facts'
      when 'capital_call_lines' then 'capital call lines are immutable once issued'
      else 'record is append-only' end,
    errcode = 'P0001';
end $$;

drop trigger if exists agreement_versions_immutable on public.agreement_versions;
create trigger agreement_versions_immutable before update or delete on public.agreement_versions
  for each row execute function public.s1_guard_agreement_version_immutable();
drop trigger if exists commitment_terms_immutable on public.commitment_terms;
create trigger commitment_terms_immutable before update or delete on public.commitment_terms
  for each row execute function public.s1_guard_commitment_terms_immutable();
drop trigger if exists contributions_immutable on public.contributions;
create trigger contributions_immutable before update or delete on public.contributions
  for each row execute function public.s1_guard_append_only();
drop trigger if exists capital_call_lines_immutable on public.capital_call_lines;
create trigger capital_call_lines_immutable before update or delete on public.capital_call_lines
  for each row execute function public.s1_guard_append_only();

-- 11. Authoritative, derived capital rollforward. There are no editable balance
--     columns anywhere; these views recompute from posted records.
create or replace view public.partner_capital_position
  with (security_invoker=on) as
select
  ct.organization_id,
  av.project_id,
  av.id as agreement_version_id,
  pp.id as participant_id,
  ct.commitment_minor_units,
  ct.currency,
  coalesce(called.called_minor_units, 0) as called_minor_units,
  coalesce(paid.contributed_minor_units, 0) as contributed_minor_units,
  coalesce(called.called_minor_units, 0) - coalesce(paid.contributed_minor_units, 0) as receivable_minor_units
from public.commitment_terms ct
join public.agreement_versions av on av.id = ct.agreement_version_id
join public.project_participants pp on pp.id = ct.participant_id
left join (
  select ccl.participant_id, cc.agreement_version_id, cc.organization_id,
         sum(ccl.amount_minor_units) as called_minor_units
  from public.capital_call_lines ccl
  join public.capital_calls cc on cc.id = ccl.capital_call_id
  where cc.status = 'ISSUED'
  group by ccl.participant_id, cc.agreement_version_id, cc.organization_id
) called on called.participant_id = pp.id
       and called.agreement_version_id = av.id
       and called.organization_id = ct.organization_id
left join (
  select c.participant_id, c.agreement_version_id, c.organization_id,
         sum(c.contribution_minor_units) as contributed_minor_units
  from public.contributions c
  group by c.participant_id, c.agreement_version_id, c.organization_id
) paid on paid.participant_id = pp.id
     and paid.agreement_version_id = av.id
     and paid.organization_id = ct.organization_id;

create or replace view public.project_capital_position
  with (security_invoker=on) as
select
  p.organization_id,
  p.id as project_id,
  p.reporting_currency as currency,
  coalesce(sum(pos.commitment_minor_units), 0) as committed_minor_units,
  coalesce(sum(pos.called_minor_units), 0) as called_minor_units,
  coalesce(sum(pos.contributed_minor_units), 0) as contributed_minor_units,
  coalesce(sum(pos.receivable_minor_units), 0) as receivable_minor_units
from public.investment_projects p
left join public.agreement_versions av
  on av.project_id = p.id and av.status = 'ACTIVE'
left join public.partner_capital_position pos
  on pos.agreement_version_id = av.id and pos.organization_id = p.organization_id
group by p.organization_id, p.id, p.reporting_currency;

grant select on public.partner_capital_position, public.project_capital_position to authenticated;

-- 12. Server-authoritative commands.
create or replace function public.create_party(
  p_organization_id uuid, p_legal_name text, p_party_type text default 'PERSON'
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_legal_name is null or char_length(trim(p_legal_name)) not between 2 and 160 then
    raise exception 'invalid party name';
  end if;
  if p_party_type not in ('PERSON','ORGANIZATION') then raise exception 'invalid party type'; end if;
  insert into public.parties(organization_id, legal_name, party_type)
  values (p_organization_id, trim(p_legal_name), p_party_type) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'PARTY_CREATED','party', v_id,
          jsonb_build_object('legal_name', trim(p_legal_name), 'party_type', p_party_type));
  return v_id;
end $$;

create or replace function public.add_project_participant(
  p_organization_id uuid, p_project_id uuid, p_party_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.investment_projects
                 where id = p_project_id and organization_id = p_organization_id) then
    raise exception 'project not found';
  end if;
  if not exists (select 1 from public.parties
                 where id = p_party_id and organization_id = p_organization_id) then
    raise exception 'party not found';
  end if;
  begin
    insert into public.project_participants(organization_id, project_id, party_id, role)
    values (p_organization_id, p_project_id, p_party_id, 'INVESTOR') returning id into v_id;
  exception when unique_violation then
    raise exception 'participant already exists';
  end;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'PARTICIPANT_ADDED','project_participant', v_id,
          jsonb_build_object('project_id', p_project_id, 'party_id', p_party_id, 'role','INVESTOR'));
  return v_id;
end $$;

create or replace function public.create_agreement_draft(
  p_organization_id uuid,
  p_project_id uuid,
  p_effective_date date,
  p_participant_ids uuid[],
  p_commitments bigint[]
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_agreement_id uuid; v_version_id uuid; v_version_no integer;
  v_currency text; v_i int; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_effective_date is null then raise exception 'effective date required'; end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null
     or array_length(p_participant_ids,1) < 1 then
    raise exception 'at least one participant is required';
  end if;
  if array_length(p_participant_ids,1) <> array_length(p_commitments,1) then
    raise exception 'participants and commitments length mismatch';
  end if;
  for v_i in 1..array_length(p_participant_ids,1) loop
    if p_commitments[v_i] is null or p_commitments[v_i] <= 0 then
      raise exception 'commitment must be positive';
    end if;
    if not exists (
      select 1 from public.project_participants pp
      where pp.id = p_participant_ids[v_i]
        and pp.project_id = p_project_id
        and pp.organization_id = p_organization_id
    ) then raise exception 'participant does not belong to project'; end if;
  end loop;

  select reporting_currency into v_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;

  insert into public.investment_agreements(organization_id, project_id, status)
  values (p_organization_id, p_project_id, 'DRAFT')
  on conflict (project_id) do update set status = public.investment_agreements.status
  returning id into v_agreement_id;

  select coalesce(max(version_no),0)+1 into v_version_no
  from public.agreement_versions where agreement_id = v_agreement_id;

  -- Canonical, server-computed hash of the version's economic terms.
  select encode(digest(
    v_agreement_id::text || '|' || v_version_no::text || '|' || p_effective_date::text
    || '|' || v_currency || '|'
    || (select string_agg(pair, ',' order by pair) from unnest(
          array(select p_participant_ids[i]::text || ':' || p_commitments[i]::text
                from generate_series(1, array_length(p_participant_ids,1)) as i)
        ) pair), 'sha256'), 'hex') into v_hash;

  insert into public.agreement_versions(
    organization_id, agreement_id, project_id, version_no, status, effective_date, terms_hash
  ) values (p_organization_id, v_agreement_id, p_project_id, v_version_no, 'DRAFT',
            p_effective_date, v_hash)
  returning id into v_version_id;

  for v_i in 1..array_length(p_participant_ids,1) loop
    insert into public.commitment_terms(
      organization_id, agreement_version_id, participant_id, commitment_minor_units, currency
    ) values (p_organization_id, v_version_id, p_participant_ids[v_i],
              p_commitments[v_i], v_currency);
  end loop;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'AGREEMENT_VERSION_DRAFTED','agreement_version', v_version_id,
          jsonb_build_object('agreement_id', v_agreement_id, 'version_no', v_version_no,
                             'terms_hash', v_hash));
  return v_version_id;
end $$;

create or replace function public.activate_agreement_version(
  p_organization_id uuid, p_version_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid; v_agreement uuid; v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  select project_id, agreement_id into v_project, v_agreement
  from public.agreement_versions
  where id = p_version_id and organization_id = p_organization_id for update;
  if not found then raise exception 'agreement version not found'; end if;

  select count(*) into v_count from public.commitment_terms
  where agreement_version_id = p_version_id;
  if v_count < 1 then raise exception 'agreement version has no commitment terms'; end if;

  -- Supersede any prior active version for this project, then activate this one.
  update public.agreement_versions
     set status = 'SUPERSEDED'
   where project_id = v_project and status = 'ACTIVE' and id <> p_version_id;

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
  p_amounts bigint[]
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_call_id uuid; v_currency text; v_i int; v_commitment bigint; v_already_called bigint;
  v_ref text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_due_date is null then raise exception 'due date required'; end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'at least one call line is required';
  end if;
  if array_length(p_participant_ids,1) <> array_length(p_amounts,1) then
    raise exception 'participants and amounts length mismatch';
  end if;

  if not exists (select 1 from public.agreement_versions
                 where id = p_agreement_version_id and project_id = p_project_id
                   and organization_id = p_organization_id and status = 'ACTIVE') then
    raise exception 'capital call requires an active agreement version';
  end if;

  select reporting_currency into v_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;

  for v_i in 1..array_length(p_participant_ids,1) loop
    if p_amounts[v_i] is null or p_amounts[v_i] <= 0 then
      raise exception 'call amount must be positive';
    end if;
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

  v_ref := nullif(trim(coalesce(p_reference,'')),'');
  if v_ref is not null and char_length(v_ref) > 80 then
    raise exception 'reference too long';
  end if;

  insert into public.capital_calls(
    organization_id, project_id, agreement_version_id, status, due_date, reference, issued_by
  ) values (p_organization_id, p_project_id, p_agreement_version_id, 'ISSUED',
            p_due_date, v_ref, v_actor)
  returning id into v_call_id;

  for v_i in 1..array_length(p_participant_ids,1) loop
    insert into public.capital_call_lines(
      organization_id, capital_call_id, participant_id, amount_minor_units, currency
    ) values (p_organization_id, v_call_id, p_participant_ids[v_i], p_amounts[v_i], v_currency);
  end loop;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'CAPITAL_CALL_ISSUED','capital_call', v_call_id,
          jsonb_build_object('project_id', p_project_id,
                             'agreement_version_id', p_agreement_version_id,
                             'due_date', p_due_date, 'reference', v_ref));
  return v_call_id;
end $$;

create or replace function public.record_contribution(
  p_organization_id uuid,
  p_project_id uuid,
  p_participant_id uuid,
  p_agreement_version_id uuid,
  p_capital_call_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_occurred_on date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_line_id uuid; v_line_amount bigint; v_paid bigint;
  v_project_currency text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'contribution amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_occurred_on is null then raise exception 'contribution date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;

  select reporting_currency into v_project_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (select 1 from public.agreement_versions
                 where id = p_agreement_version_id and project_id = p_project_id
                   and organization_id = p_organization_id and status = 'ACTIVE') then
    raise exception 'contribution requires an active agreement version';
  end if;
  if not exists (select 1 from public.capital_calls
                 where id = p_capital_call_id and project_id = p_project_id
                   and agreement_version_id = p_agreement_version_id
                   and organization_id = p_organization_id and status = 'ISSUED') then
    raise exception 'capital call not found or not issued';
  end if;

  -- Idempotent replay: same key returns the existing contribution, no new effect.
  select id into v_id from public.contributions
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_id is not null then
    return v_id;
  end if;

  -- Lock the call line and enforce that contributions never exceed the call.
  select id, amount_minor_units into v_line_id, v_line_amount
  from public.capital_call_lines
  where capital_call_id = p_capital_call_id and participant_id = p_participant_id
  for update;
  if v_line_id is null then raise exception 'participant has no line on this capital call'; end if;

  select coalesce(sum(contribution_minor_units),0) into v_paid
  from public.contributions
  where capital_call_id = p_capital_call_id and participant_id = p_participant_id;

  if v_paid + p_amount_minor_units > v_line_amount then
    raise exception 'contribution exceeds remaining capital call amount';
  end if;

  insert into public.contributions(
    organization_id, project_id, participant_id, agreement_version_id, capital_call_id,
    contribution_minor_units, currency, occurred_on, idempotency_key, recorded_by
  ) values (
    p_organization_id, p_project_id, p_participant_id, p_agreement_version_id, p_capital_call_id,
    p_amount_minor_units, p_currency, p_occurred_on, trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'CONTRIBUTION_RECORDED','contribution', v_id,
          jsonb_build_object('project_id', p_project_id,
                             'agreement_version_id', p_agreement_version_id,
                             'capital_call_id', p_capital_call_id,
                             'participant_id', p_participant_id,
                             'contribution_minor_units', p_amount_minor_units,
                             'currency', p_currency,
                             'occurred_on', p_occurred_on));
  return v_id;
end $$;

revoke all on function public.create_party(uuid,text,text) from public, anon;
revoke all on function public.add_project_participant(uuid,uuid,uuid) from public, anon;
revoke all on function public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[]) from public, anon;
revoke all on function public.activate_agreement_version(uuid,uuid) from public, anon;
revoke all on function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[]) from public, anon;
revoke all on function public.record_contribution(uuid,uuid,uuid,uuid,uuid,bigint,text,date,text) from public, anon;
grant execute on function public.create_party(uuid,text,text),
  public.add_project_participant(uuid,uuid,uuid),
  public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[]),
  public.activate_agreement_version(uuid,uuid),
  public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[]),
  public.record_contribution(uuid,uuid,uuid,uuid,uuid,bigint,text,date,text)
to authenticated;
