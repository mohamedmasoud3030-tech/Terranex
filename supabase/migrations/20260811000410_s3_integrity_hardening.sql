-- GF-005 / S3 integrity hardening discovered during independent red-team review.
-- Forward-only: preserve the delivered S3 migration while tightening evidence currency,
-- normalized hierarchy alignment, and payload-bound budget idempotency.

-- ---------------------------------------------------------------------------
-- 1. Property-state evidence must be CURRENT, EFFECTIVE, and cover the asset.
-- A property-level control covers the whole asset. Otherwise every parcel must
-- have a current effective PASSED record of the required type. A later
-- PENDING/FAILED/EXPIRED record supersedes an older PASSED record for its scope.
-- ---------------------------------------------------------------------------
create or replace function public.s3_has_current_effective_control(
  p_property_asset_id uuid,
  p_record_type text
) returns boolean
language sql stable set search_path=pg_catalog,public as $$
  with property_latest as (
    select c.status,c.effective_date,c.expiry_date
    from public.property_control_records c
    where c.property_asset_id=p_property_asset_id
      and c.record_type=p_record_type
      and c.parcel_id is null
    order by c.recorded_at desc,c.id desc
    limit 1
  ), parcel_latest as (
    select distinct on (c.parcel_id)
      c.parcel_id,c.status,c.effective_date,c.expiry_date
    from public.property_control_records c
    where c.property_asset_id=p_property_asset_id
      and c.record_type=p_record_type
      and c.parcel_id is not null
    order by c.parcel_id,c.recorded_at desc,c.id desc
  ), asset_parcels as (
    select p.id
    from public.parcels p
    where p.property_asset_id=p_property_asset_id
  )
  select
    exists (
      select 1 from property_latest c
      where c.status='PASSED'
        and c.effective_date is not null
        and c.effective_date<=current_date
        and (c.expiry_date is null or c.expiry_date>=current_date)
    )
    or (
      exists (select 1 from asset_parcels)
      and not exists (
        select 1
        from asset_parcels p
        left join parcel_latest c on c.parcel_id=p.id
        where c.parcel_id is null
           or c.status<>'PASSED'
           or c.effective_date is null
           or c.effective_date>current_date
           or (c.expiry_date is not null and c.expiry_date<current_date)
      )
    );
$$;

-- The stable lifecycle transition trigger is defined once in the S3 base
-- migration and consumes this migration's refined evidence policy helper.
revoke all on function public.s3_has_current_effective_control(uuid,text)
from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 2. When both parcel and phase dimensions are supplied, they cannot disagree.
-- A property-wide phase (phase.parcel_id IS NULL) may still be narrowed to a
-- parcel by the fact. A parcel-scoped phase may never be paired with another
-- parcel on a budget line, cost classification, or sector event.
-- ---------------------------------------------------------------------------
create or replace function public.s3_validate_phase_parcel_alignment() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_phase_parcel uuid;
begin
  if new.phase_id is null or new.parcel_id is null then
    return new;
  end if;

  select p.parcel_id into v_phase_parcel
  from public.development_phases p
  where p.id=new.phase_id
    and p.organization_id=new.organization_id
    and p.project_id=new.project_id
    and p.property_asset_id=new.property_asset_id;

  if found and v_phase_parcel is not null and v_phase_parcel<>new.parcel_id then
    raise exception 'phase and parcel dimensions must belong to the same operational scope';
  end if;
  return new;
end $$;

create trigger property_budget_phase_parcel_guard
before insert on public.property_budget_lines
for each row execute function public.s3_validate_phase_parcel_alignment();

create trigger property_cost_phase_parcel_guard
before insert on public.property_cost_items
for each row execute function public.s3_validate_phase_parcel_alignment();

create trigger real_estate_event_phase_parcel_guard
before insert on public.real_estate_events
for each row execute function public.s3_validate_phase_parcel_alignment();

-- NULL is a real dimension value here. PostgreSQL's default UNIQUE semantics
-- treat NULLs as distinct, which could permit duplicate budget dimensions.
create unique index property_budget_line_dimensions_nullsafe_uq
  on public.property_budget_lines(budget_version_id,parcel_id,phase_id,cost_category)
  nulls not distinct;

-- ---------------------------------------------------------------------------
-- 3. Preserve NULL positions in budget idempotency payloads. array_to_string()
-- omits NULL elements, so [NULL,A] and [A,NULL] previously hashed identically.
-- JSONB preserves array order and NULL positions.
-- ---------------------------------------------------------------------------
create or replace function public.propose_property_budget(
  p_organization_id uuid, p_property_asset_id uuid, p_currency text,
  p_basis_notes text, p_parcel_ids uuid[], p_phase_ids uuid[],
  p_cost_categories text[], p_amount_minor_units bigint[], p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid();
  v_id uuid;
  v_project uuid;
  v_project_currency text;
  v_hash text;
  v_existing record;
  v_version integer;
  v_n integer;
  i integer;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;

  select a.project_id,p.reporting_currency into v_project,v_project_currency
  from public.property_assets a
  join public.investment_projects p on p.id=a.project_id
  where a.id=p_property_asset_id and a.organization_id=p_organization_id;
  if v_project is null then raise exception 'property asset not found'; end if;
  if p_currency<>v_project_currency then raise exception 'budget currency must match project currency'; end if;
  if p_basis_notes is null or char_length(trim(p_basis_notes)) not between 3 and 1000 then raise exception 'budget basis notes required'; end if;

  v_n:=array_length(p_cost_categories,1);
  if v_n is null or v_n<1
     or array_length(p_amount_minor_units,1)<>v_n
     or coalesce(array_length(p_parcel_ids,1),v_n)<>v_n
     or coalesce(array_length(p_phase_ids,1),v_n)<>v_n then
    raise exception 'budget line arrays must have equal non-zero length';
  end if;
  for i in 1..v_n loop
    if p_cost_categories[i] not in (
      'ACQUISITION','LEGAL_DUE_DILIGENCE','SITE_PREPARATION','CONSTRUCTION',
      'PROFESSIONAL_FEES','HOLDING','OTHER'
    ) or p_amount_minor_units[i] is null or p_amount_minor_units[i]<=0 then
      raise exception 'invalid budget line at position %',i;
    end if;
  end loop;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  select encode(digest(
    jsonb_build_object(
      'property_asset_id',p_property_asset_id,
      'currency',p_currency,
      'basis_notes',trim(p_basis_notes),
      'parcel_ids',to_jsonb(p_parcel_ids),
      'phase_ids',to_jsonb(p_phase_ids),
      'cost_categories',to_jsonb(p_cost_categories),
      'amount_minor_units',to_jsonb(p_amount_minor_units)
    )::text,
    'sha256'
  ),'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':s3-budget:'||trim(p_idempotency_key),0));
  select * into v_existing
  from public.property_budget_versions
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  perform 1 from public.property_assets where id=p_property_asset_id for update;
  select coalesce(max(version_no),0)+1 into v_version
  from public.property_budget_versions where property_asset_id=p_property_asset_id;

  insert into public.property_budget_versions(
    organization_id,project_id,property_asset_id,version_no,currency,basis_notes,
    prepared_by,idempotency_key,request_hash
  ) values(
    p_organization_id,v_project,p_property_asset_id,v_version,p_currency,trim(p_basis_notes),
    v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;

  for i in 1..v_n loop
    insert into public.property_budget_lines(
      organization_id,project_id,property_asset_id,budget_version_id,
      parcel_id,phase_id,cost_category,amount_minor_units
    ) values(
      p_organization_id,v_project,p_property_asset_id,v_id,
      p_parcel_ids[i],p_phase_ids[i],p_cost_categories[i],p_amount_minor_units[i]
    );
  end loop;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(
    p_organization_id,v_actor,'PROPERTY_BUDGET_PROPOSED','property_budget_version',v_id,
    jsonb_build_object('project_id',v_project,'property_asset_id',p_property_asset_id,'version_no',v_version,'line_count',v_n,'currency',p_currency)
  );
  return v_id;
end $$;

revoke all on function public.propose_property_budget(uuid,uuid,text,text,uuid[],uuid[],text[],bigint[],text)
from public,anon;
grant execute on function public.propose_property_budget(uuid,uuid,text,text,uuid[],uuid[],text[],bigint[],text)
to authenticated;
