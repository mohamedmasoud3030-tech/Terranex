-- GF-003 / S1 hardening after transplant onto the current Greenfield foundation.
-- Keeps S1 narrow while closing retry, concurrency, scope-integrity, and exact-read gaps.

-- Material draft/call commands need durable idempotency just like contributions.
alter table public.agreement_versions add column if not exists idempotency_key text;
update public.agreement_versions
set idempotency_key = 'legacy-version-' || id::text
where idempotency_key is null;
alter table public.agreement_versions alter column idempotency_key set not null;
alter table public.agreement_versions
  drop constraint if exists agreement_versions_idempotency_key_check;
alter table public.agreement_versions
  add constraint agreement_versions_idempotency_key_check
  check (char_length(idempotency_key) between 8 and 120);
create unique index if not exists agreement_versions_org_idempotency_uidx
  on public.agreement_versions(organization_id, idempotency_key);

alter table public.capital_calls add column if not exists idempotency_key text;
alter table public.capital_calls add column if not exists request_hash text;
update public.capital_calls
set idempotency_key = 'legacy-call-' || id::text,
    request_hash = encode(digest(id::text, 'sha256'), 'hex')
where idempotency_key is null or request_hash is null;
alter table public.capital_calls alter column idempotency_key set not null;
alter table public.capital_calls alter column request_hash set not null;
alter table public.capital_calls
  drop constraint if exists capital_calls_idempotency_key_check;
alter table public.capital_calls
  add constraint capital_calls_idempotency_key_check
  check (char_length(idempotency_key) between 8 and 120);
create unique index if not exists capital_calls_org_idempotency_uidx
  on public.capital_calls(organization_id, idempotency_key);

-- Database-level project-scope integrity. Browser DML remains denied, but invalid
-- same-tenant cross-project references must also be impossible for privileged writers.
create or replace function public.s1_validate_commitment_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_version_project uuid; v_participant_project uuid;
begin
  select project_id into v_version_project
  from public.agreement_versions
  where id = new.agreement_version_id and organization_id = new.organization_id;
  select project_id into v_participant_project
  from public.project_participants
  where id = new.participant_id and organization_id = new.organization_id;
  if v_version_project is null or v_participant_project is null
     or v_version_project <> v_participant_project then
    raise exception 'commitment participant must belong to the agreement project';
  end if;
  return new;
end $$;

drop trigger if exists commitment_scope_guard on public.commitment_terms;
create trigger commitment_scope_guard before insert or update on public.commitment_terms
  for each row execute function public.s1_validate_commitment_scope();

create or replace function public.s1_validate_capital_call_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1 from public.agreement_versions av
    where av.id = new.agreement_version_id
      and av.organization_id = new.organization_id
      and av.project_id = new.project_id
  ) then
    raise exception 'capital call agreement version must belong to the same project';
  end if;
  return new;
end $$;

drop trigger if exists capital_call_scope_guard on public.capital_calls;
create trigger capital_call_scope_guard before insert or update on public.capital_calls
  for each row execute function public.s1_validate_capital_call_scope();

create or replace function public.s1_validate_call_line_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1
    from public.capital_calls cc
    join public.project_participants pp
      on pp.id = new.participant_id
     and pp.organization_id = new.organization_id
    where cc.id = new.capital_call_id
      and cc.organization_id = new.organization_id
      and pp.project_id = cc.project_id
  ) then
    raise exception 'capital call participant must belong to the call project';
  end if;
  return new;
end $$;

drop trigger if exists capital_call_line_scope_guard on public.capital_call_lines;
create trigger capital_call_line_scope_guard before insert or update on public.capital_call_lines
  for each row execute function public.s1_validate_call_line_scope();

create or replace function public.s1_validate_contribution_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if not exists (
    select 1
    from public.capital_calls cc
    join public.project_participants pp
      on pp.id = new.participant_id
     and pp.organization_id = new.organization_id
    join public.agreement_versions av
      on av.id = new.agreement_version_id
     and av.organization_id = new.organization_id
    where cc.id = new.capital_call_id
      and cc.organization_id = new.organization_id
      and cc.project_id = new.project_id
      and cc.agreement_version_id = new.agreement_version_id
      and pp.project_id = new.project_id
      and av.project_id = new.project_id
  ) then
    raise exception 'contribution references must belong to one project and governing version';
  end if;
  return new;
end $$;

drop trigger if exists contribution_scope_guard on public.contributions;
create trigger contribution_scope_guard before insert on public.contributions
  for each row execute function public.s1_validate_contribution_scope();

-- Read-facing views cast int8 money to text so PostgREST/JavaScript cannot round
-- values before the UI formats them. Authoritative storage remains bigint.
create or replace view public.commitment_terms_read with (security_invoker=on) as
select id, organization_id, agreement_version_id, participant_id,
       commitment_minor_units::text as commitment_minor_units, currency, created_at
from public.commitment_terms;

create or replace view public.capital_call_lines_read with (security_invoker=on) as
select id, organization_id, capital_call_id, participant_id,
       amount_minor_units::text as amount_minor_units, currency
from public.capital_call_lines;

create or replace view public.contributions_read with (security_invoker=on) as
select id, organization_id, project_id, agreement_version_id, capital_call_id,
       participant_id, contribution_minor_units::text as contribution_minor_units,
       currency, occurred_on, created_at
from public.contributions;

create or replace view public.partner_capital_position_read with (security_invoker=on) as
select organization_id, project_id, agreement_version_id, participant_id,
       commitment_minor_units::text as commitment_minor_units,
       called_minor_units::text as called_minor_units,
       contributed_minor_units::text as contributed_minor_units,
       receivable_minor_units::text as receivable_minor_units,
       currency
from public.partner_capital_position;

create or replace view public.project_capital_position_read with (security_invoker=on) as
select organization_id, project_id, currency,
       committed_minor_units::text as committed_minor_units,
       called_minor_units::text as called_minor_units,
       contributed_minor_units::text as contributed_minor_units,
       receivable_minor_units::text as receivable_minor_units
from public.project_capital_position;

grant select on public.commitment_terms_read, public.capital_call_lines_read,
  public.contributions_read, public.partner_capital_position_read,
  public.project_capital_position_read to authenticated;

-- Draft creation: same idempotency key + same economic payload returns the same
-- version. Agreement-row locking serializes version numbering.
revoke all on function public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[]) from authenticated;
drop function public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[]);

create or replace function public.create_agreement_draft(
  p_organization_id uuid,
  p_project_id uuid,
  p_effective_date date,
  p_participant_ids uuid[],
  p_commitments bigint[],
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_agreement_id uuid; v_version_id uuid; v_version_no integer;
  v_currency text; v_i int; v_hash text; v_existing_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_effective_date is null then raise exception 'effective date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null
     or array_length(p_participant_ids,1) < 1 then
    raise exception 'at least one participant is required';
  end if;
  if array_length(p_participant_ids,1) <> array_length(p_commitments,1) then
    raise exception 'participants and commitments length mismatch';
  end if;
  if (select count(*) from unnest(p_participant_ids) x)
     <> (select count(distinct x) from unnest(p_participant_ids) x) then
    raise exception 'duplicate participant in agreement';
  end if;

  select reporting_currency into v_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;

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

  select encode(digest(
    p_project_id::text || '|' || p_effective_date::text || '|' || v_currency || '|'
    || (select string_agg(pair, ',' order by pair) from unnest(
          array(select p_participant_ids[i]::text || ':' || p_commitments[i]::text
                from generate_series(1, array_length(p_participant_ids,1)) as i)
        ) pair), 'sha256'), 'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':agreement-draft:' || trim(p_idempotency_key), 0));
  select id, terms_hash into v_version_id, v_existing_hash
  from public.agreement_versions
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_version_id;
  end if;

  insert into public.investment_agreements(organization_id, project_id, status)
  values (p_organization_id, p_project_id, 'DRAFT')
  on conflict (project_id) do nothing;

  select id into v_agreement_id
  from public.investment_agreements
  where project_id = p_project_id and organization_id = p_organization_id
  for update;
  if v_agreement_id is null then raise exception 'agreement not found'; end if;

  select coalesce(max(version_no),0)+1 into v_version_no
  from public.agreement_versions where agreement_id = v_agreement_id;

  insert into public.agreement_versions(
    organization_id, agreement_id, project_id, version_no, status, effective_date,
    terms_hash, idempotency_key
  ) values (
    p_organization_id, v_agreement_id, p_project_id, v_version_no, 'DRAFT',
    p_effective_date, v_hash, trim(p_idempotency_key)
  ) returning id into v_version_id;

  for v_i in 1..array_length(p_participant_ids,1) loop
    insert into public.commitment_terms(
      organization_id, agreement_version_id, participant_id, commitment_minor_units, currency
    ) values (
      p_organization_id, v_version_id, p_participant_ids[v_i], p_commitments[v_i], v_currency
    );
  end loop;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'AGREEMENT_VERSION_DRAFTED','agreement_version', v_version_id,
          jsonb_build_object('agreement_id', v_agreement_id, 'version_no', v_version_no,
                             'terms_hash', v_hash));
  return v_version_id;
end $$;

-- S1 deliberately supports one governing activation only. Amendment/supersession
-- requires carry-forward rules for prior calls/contributions and is deferred.
create or replace function public.activate_agreement_version(
  p_organization_id uuid, p_version_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project uuid; v_agreement uuid; v_status text; v_count int; v_current uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

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

-- Capital-call issuance is retry-safe and serialized per commitment row, so two
-- concurrent calls cannot both pass the commitment ceiling.
revoke all on function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[]) from authenticated;
drop function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[]);

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

  -- Lock all involved commitment rows in deterministic order before calculating
  -- already-called totals. This is the serialization boundary for concurrent calls.
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

-- Contribution replay is bound to the original payload. Reusing a key for a
-- different economic fact is an error, never a silent success.
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
  v_existing record;
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

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (
    select 1 from public.agreement_versions
    where id = p_agreement_version_id and project_id = p_project_id
      and organization_id = p_organization_id and status = 'ACTIVE'
  ) then raise exception 'contribution requires an active agreement version'; end if;
  if not exists (
    select 1 from public.capital_calls
    where id = p_capital_call_id and project_id = p_project_id
      and agreement_version_id = p_agreement_version_id
      and organization_id = p_organization_id and status = 'ISSUED'
  ) then raise exception 'capital call not found or not issued'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':contribution:' || trim(p_idempotency_key), 0));
  select * into v_existing
  from public.contributions
  where organization_id = p_organization_id
    and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.project_id <> p_project_id
       or v_existing.participant_id <> p_participant_id
       or v_existing.agreement_version_id <> p_agreement_version_id
       or v_existing.capital_call_id <> p_capital_call_id
       or v_existing.contribution_minor_units <> p_amount_minor_units
       or v_existing.currency <> p_currency
       or v_existing.occurred_on <> p_occurred_on then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

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
    p_organization_id, p_project_id, p_participant_id, p_agreement_version_id,
    p_capital_call_id, p_amount_minor_units, p_currency, p_occurred_on,
    trim(p_idempotency_key), v_actor
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

revoke all on function public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[],text) from public, anon;
revoke all on function public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[],text) from public, anon;
revoke all on function public.record_contribution(uuid,uuid,uuid,uuid,uuid,bigint,text,date,text) from public, anon;
grant execute on function public.create_agreement_draft(uuid,uuid,date,uuid[],bigint[],text),
  public.create_capital_call(uuid,uuid,uuid,date,text,uuid[],bigint[],text),
  public.record_contribution(uuid,uuid,uuid,uuid,uuid,bigint,text,date,text)
to authenticated;
