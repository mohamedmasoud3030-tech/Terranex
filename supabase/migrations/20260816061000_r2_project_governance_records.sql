-- R2 — Project governance records: canonical RiskItem + DecisionRecord.
--
-- This slice deliberately does NOT introduce a universal Asset table. Sector
-- asset roots remain authoritative and project-bounded. These records close the
-- separate governance gap named by the canonical InvestmentProject aggregate
-- and roll to the current Portfolio only as read projections.

-- ===========================================================================
-- 1. Project-authoritative immutable facts
-- ===========================================================================
create table public.project_risk_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 3 and 160),
  description text not null check (char_length(trim(description)) between 3 and 2000),
  severity text not null check (severity in ('LOW','MEDIUM','HIGH','CRITICAL')),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  due_date date,
  source_reference text check (source_reference is null or char_length(trim(source_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  unique (organization_id,idempotency_key),
  unique (id,project_id,organization_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);

create table public.project_risk_resolutions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  risk_item_id uuid not null,
  outcome text not null check (char_length(trim(outcome)) between 3 and 1000),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 3 and 200),
  resolved_by uuid not null references auth.users(id) on delete restrict,
  resolved_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  unique (risk_item_id),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  foreign key (risk_item_id,project_id,organization_id)
    references public.project_risk_items(id,project_id,organization_id) on delete restrict
);

create table public.project_decision_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 3 and 160),
  decision_text text not null check (char_length(trim(decision_text)) between 3 and 4000),
  rationale text check (rationale is null or char_length(trim(rationale)) between 3 and 4000),
  decision_date date not null,
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  foreign key (project_id,organization_id)
    references public.investment_projects(id,organization_id) on delete restrict
);

create index project_risk_items_project_idx
  on public.project_risk_items(organization_id,project_id,severity,recorded_at desc);
create index project_risk_resolutions_project_idx
  on public.project_risk_resolutions(organization_id,project_id,resolved_at desc);
create index project_decision_records_project_idx
  on public.project_decision_records(organization_id,project_id,decision_date desc,recorded_at desc);

-- Recorded governance facts are corrected by a new fact, never by destructive
-- UPDATE/DELETE. Risk state is derived from the one immutable resolution fact.
create or replace function public.r2_governance_append_only()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'project governance records are append-only';
end $$;

create trigger project_risk_items_append_only
before update or delete on public.project_risk_items
for each row execute function public.r2_governance_append_only();
create trigger project_risk_resolutions_append_only
before update or delete on public.project_risk_resolutions
for each row execute function public.r2_governance_append_only();
create trigger project_decision_records_append_only
before update or delete on public.project_decision_records
for each row execute function public.r2_governance_append_only();

-- ===========================================================================
-- 2. Read models: Project truth first, Portfolio is current management context
-- ===========================================================================
create or replace view public.project_risk_items_read with (security_invoker=on) as
select
  r.id as risk_item_id,r.organization_id,r.project_id,r.title,r.description,r.severity,
  r.owner_user_id,r.due_date,r.source_reference,r.recorded_by,r.recorded_at,
  case when x.id is null then 'OPEN' else 'RESOLVED' end as status,
  x.id as resolution_id,x.outcome as resolution_outcome,x.evidence_reference as resolution_evidence_reference,
  x.resolved_by,x.resolved_at
from public.project_risk_items r
left join public.project_risk_resolutions x on x.risk_item_id=r.id;

create or replace view public.portfolio_project_risks_read with (security_invoker=on) as
select
  a.portfolio_id,
  r.risk_item_id,r.organization_id,r.project_id,r.title,r.description,r.severity,
  r.owner_user_id,r.due_date,r.source_reference,r.recorded_by,r.recorded_at,
  r.status,r.resolution_id,r.resolution_outcome,r.resolution_evidence_reference,
  r.resolved_by,r.resolved_at
from public.project_risk_items_read r
join public.portfolio_project_assignments a
  on a.organization_id=r.organization_id
 and a.investment_project_id=r.project_id
 and a.removed_at is null;

create or replace view public.portfolio_project_decisions_read with (security_invoker=on) as
select
  a.portfolio_id,d.id as decision_record_id,d.organization_id,d.project_id,
  d.title,d.decision_text,d.rationale,d.decision_date,d.evidence_reference,
  d.recorded_by,d.recorded_at
from public.project_decision_records d
join public.portfolio_project_assignments a
  on a.organization_id=d.organization_id
 and a.investment_project_id=d.project_id
 and a.removed_at is null;

-- ===========================================================================
-- 3. Server-authoritative commands
-- ===========================================================================
create or replace function public.record_project_risk(
  p_organization_id uuid,p_project_id uuid,p_title text,p_description text,p_severity text,
  p_owner_user_id uuid,p_due_date date,p_source_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists(select 1 from public.investment_projects p where p.id=p_project_id and p.organization_id=p_organization_id) then
    raise exception 'project not found';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 160 then raise exception 'invalid risk title'; end if;
  if p_description is null or char_length(trim(p_description)) not between 3 and 2000 then raise exception 'invalid risk description'; end if;
  if p_severity not in ('LOW','MEDIUM','HIGH','CRITICAL') then raise exception 'invalid risk severity'; end if;
  if not exists(select 1 from public.memberships m where m.organization_id=p_organization_id and m.user_id=p_owner_user_id and m.status='ACTIVE') then
    raise exception 'risk owner must be an active organization member';
  end if;
  if p_source_reference is not null and char_length(trim(p_source_reference)) not between 3 and 200 then raise exception 'invalid risk source reference'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash:=encode(digest(
    p_project_id::text||'|'||trim(p_title)||'|'||trim(p_description)||'|'||p_severity||'|'||
    p_owner_user_id::text||'|'||coalesce(p_due_date::text,'')||'|'||coalesce(trim(p_source_reference),''),
    'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r2-risk:'||trim(p_idempotency_key),0));
  select * into v_existing from public.project_risk_items
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.project_risk_items(
    id,organization_id,project_id,title,description,severity,owner_user_id,due_date,source_reference,
    recorded_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,p_project_id,trim(p_title),trim(p_description),p_severity,p_owner_user_id,
    p_due_date,nullif(trim(p_source_reference),''),v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROJECT_RISK_RECORDED','project_risk_item',v_id,
    jsonb_build_object('project_id',p_project_id,'severity',p_severity,'owner_user_id',p_owner_user_id,'due_date',p_due_date));
  return v_id;
end $$;

create or replace function public.resolve_project_risk(
  p_organization_id uuid,p_risk_item_id uuid,p_outcome text,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text; v_existing record; v_risk record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_outcome is null or char_length(trim(p_outcome)) not between 3 and 1000 then raise exception 'risk resolution outcome required'; end if;
  if p_evidence_reference is not null and char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'invalid risk resolution evidence reference'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash:=encode(digest(p_risk_item_id::text||'|'||trim(p_outcome)||'|'||coalesce(trim(p_evidence_reference),''),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r2-risk-resolution:'||trim(p_idempotency_key),0));
  select * into v_existing from public.project_risk_resolutions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_risk from public.project_risk_items
  where id=p_risk_item_id and organization_id=p_organization_id for update;
  if not found then raise exception 'project risk not found'; end if;
  if exists(select 1 from public.project_risk_resolutions x where x.risk_item_id=p_risk_item_id) then
    raise exception 'project risk already resolved';
  end if;

  insert into public.project_risk_resolutions(
    id,organization_id,project_id,risk_item_id,outcome,evidence_reference,resolved_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,v_risk.project_id,p_risk_item_id,trim(p_outcome),nullif(trim(p_evidence_reference),''),
    v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROJECT_RISK_RESOLVED','project_risk_resolution',v_id,
    jsonb_build_object('project_id',v_risk.project_id,'risk_item_id',p_risk_item_id));
  return v_id;
end $$;

create or replace function public.record_project_decision(
  p_organization_id uuid,p_project_id uuid,p_title text,p_decision_text text,p_rationale text,
  p_decision_date date,p_evidence_reference text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text; v_existing record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if not exists(select 1 from public.investment_projects p where p.id=p_project_id and p.organization_id=p_organization_id) then
    raise exception 'project not found';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 160 then raise exception 'invalid decision title'; end if;
  if p_decision_text is null or char_length(trim(p_decision_text)) not between 3 and 4000 then raise exception 'invalid decision text'; end if;
  if p_rationale is not null and char_length(trim(p_rationale)) not between 3 and 4000 then raise exception 'invalid decision rationale'; end if;
  if p_decision_date is null or p_decision_date>current_date then raise exception 'decision date must be effective'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'decision evidence reference required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  v_hash:=encode(digest(
    p_project_id::text||'|'||trim(p_title)||'|'||trim(p_decision_text)||'|'||coalesce(trim(p_rationale),'')||'|'||
    p_decision_date::text||'|'||trim(p_evidence_reference),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':r2-decision:'||trim(p_idempotency_key),0));
  select * into v_existing from public.project_decision_records
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.project_decision_records(
    id,organization_id,project_id,title,decision_text,rationale,decision_date,evidence_reference,
    recorded_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,p_project_id,trim(p_title),trim(p_decision_text),nullif(trim(p_rationale),''),
    p_decision_date,trim(p_evidence_reference),v_actor,trim(p_idempotency_key),v_hash
  );
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'PROJECT_DECISION_RECORDED','project_decision_record',v_id,
    jsonb_build_object('project_id',p_project_id,'decision_date',p_decision_date,'evidence_reference',trim(p_evidence_reference)));
  return v_id;
end $$;

-- ===========================================================================
-- 4. Default-deny RLS / ACL
-- ===========================================================================
alter table public.project_risk_items enable row level security;
alter table public.project_risk_items force row level security;
alter table public.project_risk_resolutions enable row level security;
alter table public.project_risk_resolutions force row level security;
alter table public.project_decision_records enable row level security;
alter table public.project_decision_records force row level security;

create policy project_risk_items_read_policy on public.project_risk_items
for select to authenticated using (public.is_active_member(organization_id));
create policy project_risk_resolutions_read_policy on public.project_risk_resolutions
for select to authenticated using (public.is_active_member(organization_id));
create policy project_decision_records_read_policy on public.project_decision_records
for select to authenticated using (public.is_active_member(organization_id));

revoke all on public.project_risk_items,public.project_risk_resolutions,public.project_decision_records from public,anon,authenticated;
grant select on public.project_risk_items,public.project_risk_resolutions,public.project_decision_records to authenticated;
revoke all on public.project_risk_items_read,public.portfolio_project_risks_read,public.portfolio_project_decisions_read from public,anon;
grant select on public.project_risk_items_read,public.portfolio_project_risks_read,public.portfolio_project_decisions_read to authenticated;

revoke all on function public.r2_governance_append_only() from public,anon,authenticated;
revoke all on function public.record_project_risk(uuid,uuid,text,text,text,uuid,date,text,text) from public,anon;
revoke all on function public.resolve_project_risk(uuid,uuid,text,text,text) from public,anon;
revoke all on function public.record_project_decision(uuid,uuid,text,text,text,date,text,text) from public,anon;
grant execute on function public.record_project_risk(uuid,uuid,text,text,text,uuid,date,text,text) to authenticated;
grant execute on function public.resolve_project_risk(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.record_project_decision(uuid,uuid,text,text,text,date,text,text) to authenticated;
