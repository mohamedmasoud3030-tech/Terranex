-- GF-017 / Agricultural Land Asset, Acquisition & Control.
--
-- Adds the Agriculture-specific investment/legal-control object that sits
-- before the existing operational Farm. This is deliberately not a universal
-- asset engine and does not change Real Estate's PropertyAsset -> Parcel ->
-- Acquisition/control model.
--
-- Financial boundary: agreed purchase consideration is a contract fact. It is
-- not payment, carrying amount, valuation, or CropCycle operating cost. A
-- matching shared-core obligation may be referenced, but this migration never
-- creates an obligation, payment, contribution, journal batch, or journal line.

-- ===========================================================================
-- 1. Durable Agriculture land asset and control/acquisition fact
-- ===========================================================================
create table public.agricultural_land_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 160),
  internal_reference text not null check (char_length(trim(internal_reference)) between 1 and 80),
  legal_reference text check (legal_reference is null or char_length(trim(legal_reference)) between 1 and 160),
  legal_area_quantity numeric(20,6) not null check (legal_area_quantity > 0),
  area_unit text not null check (area_unit in ('M2','HECTARE','FEDDAN')),
  legal_location_description text check (
    legal_location_description is null
    or char_length(trim(legal_location_description)) between 2 and 1000
  ),
  control_basis text not null check (control_basis in (
    'PURCHASED','LEASED','CONTRIBUTED_IN_KIND','MANAGED_FOR_OWNER'
  )),
  control_start_date date not null,
  control_end_date date,
  counterparty_party_id uuid,
  agreement_reference text not null check (char_length(trim(agreement_reference)) between 2 and 200),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  agreed_consideration_minor_units bigint check (agreed_consideration_minor_units > 0),
  consideration_currency text check (consideration_currency ~ '^[A-Z]{3}$'),
  consideration_obligation_id uuid,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  check (control_end_date is null or control_end_date >= control_start_date),
  check (
    (agreed_consideration_minor_units is null and consideration_currency is null and consideration_obligation_id is null)
    or
    (control_basis = 'PURCHASED' and agreed_consideration_minor_units is not null and consideration_currency is not null)
  ),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (counterparty_party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  foreign key (consideration_obligation_id, organization_id)
    references public.cost_obligations(id, organization_id) on delete restrict
);
create unique index agricultural_land_assets_project_reference_key
  on public.agricultural_land_assets(organization_id, project_id, lower(internal_reference));
create index agricultural_land_assets_project_idx
  on public.agricultural_land_assets(project_id);

-- A Farm is an operating location. Linking it to an investment land asset does
-- not rewrite Farm identity and does not fabricate links for existing rows.
create table public.farm_land_asset_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  land_asset_id uuid not null,
  farm_id uuid not null,
  linked_by uuid not null references auth.users(id) on delete restrict,
  linked_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (farm_id),
  unique (land_asset_id, farm_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, project_id),
  foreign key (land_asset_id, organization_id, project_id)
    references public.agricultural_land_assets(id, organization_id, project_id) on delete restrict,
  foreign key (farm_id, organization_id, project_id)
    references public.farms(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index farm_land_asset_links_asset_idx on public.farm_land_asset_links(land_asset_id);
create index farm_land_asset_links_project_idx on public.farm_land_asset_links(project_id);

-- ===========================================================================
-- 2. Append-only guards
-- ===========================================================================
create or replace function public.gf017_guard_land_facts_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'agricultural land asset and farm linkage facts are immutable';
end $$;

create trigger agricultural_land_assets_immutable
before update or delete on public.agricultural_land_assets
for each row execute function public.gf017_guard_land_facts_immutable();

create trigger farm_land_asset_links_immutable
before update or delete on public.farm_land_asset_links
for each row execute function public.gf017_guard_land_facts_immutable();

-- ===========================================================================
-- 3. Commands
-- ===========================================================================
create or replace function public.create_agricultural_land_asset(
  p_organization_id uuid,
  p_project_id uuid,
  p_name text,
  p_internal_reference text,
  p_legal_reference text,
  p_legal_area_quantity numeric,
  p_area_unit text,
  p_legal_location_description text,
  p_control_basis text,
  p_control_start_date date,
  p_control_end_date date,
  p_counterparty_party_id uuid,
  p_agreement_reference text,
  p_evidence_reference text,
  p_agreed_consideration_minor_units bigint,
  p_consideration_currency text,
  p_consideration_obligation_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing public.agricultural_land_assets%rowtype;
  v_obligation public.cost_obligations%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
    where p.id=p_project_id and p.organization_id=p_organization_id and p.sector='AGRICULTURE'
  ) then raise exception 'agriculture project not found'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 160 then
    raise exception 'invalid agricultural land asset name';
  end if;
  if p_internal_reference is null or char_length(trim(p_internal_reference)) not between 1 and 80 then
    raise exception 'invalid agricultural land asset reference';
  end if;
  if p_legal_reference is not null and char_length(trim(p_legal_reference)) not between 1 and 160 then
    raise exception 'invalid agricultural land legal reference';
  end if;
  if p_legal_area_quantity is null or p_legal_area_quantity <= 0 then
    raise exception 'agricultural land area must be positive';
  end if;
  if p_area_unit not in ('M2','HECTARE','FEDDAN') then
    raise exception 'invalid agricultural land area unit';
  end if;
  if p_legal_location_description is not null
     and char_length(trim(p_legal_location_description)) not between 2 and 1000 then
    raise exception 'invalid agricultural land location description';
  end if;
  if p_control_basis not in ('PURCHASED','LEASED','CONTRIBUTED_IN_KIND','MANAGED_FOR_OWNER') then
    raise exception 'invalid agricultural land control basis';
  end if;
  if p_control_start_date is null then raise exception 'control start date is required'; end if;
  if p_control_end_date is not null and p_control_end_date < p_control_start_date then
    raise exception 'control end date must not precede start date';
  end if;
  if p_counterparty_party_id is null or not exists (
    select 1 from public.parties p
    where p.id=p_counterparty_party_id and p.organization_id=p_organization_id
  ) then raise exception 'land counterparty not found'; end if;
  if p_agreement_reference is null or char_length(trim(p_agreement_reference)) not between 2 and 200 then
    raise exception 'land agreement reference is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'land control evidence is required';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  if p_control_basis='PURCHASED' then
    if (p_agreed_consideration_minor_units is null) <> (p_consideration_currency is null) then
      raise exception 'purchase consideration and currency must be provided together';
    end if;
    if p_agreed_consideration_minor_units is not null and p_agreed_consideration_minor_units <= 0 then
      raise exception 'purchase consideration must be positive';
    end if;
    if p_consideration_currency is not null and p_consideration_currency !~ '^[A-Z]{3}$' then
      raise exception 'invalid purchase consideration currency';
    end if;
  elsif p_agreed_consideration_minor_units is not null
     or p_consideration_currency is not null
     or p_consideration_obligation_id is not null then
    raise exception 'consideration is only supported for purchased land';
  end if;

  if p_consideration_obligation_id is not null then
    if p_agreed_consideration_minor_units is null then
      raise exception 'linked obligation requires recorded purchase consideration';
    end if;
    select * into v_obligation
    from public.cost_obligations o
    where o.id=p_consideration_obligation_id and o.organization_id=p_organization_id;
    if not found or v_obligation.project_id<>p_project_id then
      raise exception 'land consideration obligation must belong to the same project';
    end if;
    if v_obligation.amount_minor_units<>p_agreed_consideration_minor_units
       or v_obligation.currency<>p_consideration_currency then
      raise exception 'land consideration obligation must match agreed consideration';
    end if;
  end if;

  select encode(digest(jsonb_build_object(
    'project_id',p_project_id,
    'name',trim(p_name),
    'internal_reference',trim(p_internal_reference),
    'legal_reference',nullif(trim(p_legal_reference),''),
    'legal_area_quantity',p_legal_area_quantity::numeric(20,6),
    'area_unit',p_area_unit,
    'legal_location_description',nullif(trim(p_legal_location_description),''),
    'control_basis',p_control_basis,
    'control_start_date',p_control_start_date,
    'control_end_date',p_control_end_date,
    'counterparty_party_id',p_counterparty_party_id,
    'agreement_reference',trim(p_agreement_reference),
    'evidence_reference',trim(p_evidence_reference),
    'agreed_consideration_minor_units',p_agreed_consideration_minor_units,
    'consideration_currency',p_consideration_currency,
    'consideration_obligation_id',p_consideration_obligation_id
  )::text,'sha256'),'hex') into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf017-land:' || trim(p_idempotency_key),0));
  select * into v_existing from public.agricultural_land_assets
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Serialize the project natural key so callers receive a stable domain error
  -- instead of a raw unique violation.
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_project_id::text || ':gf017-land-ref:'
    || lower(trim(p_internal_reference)),0));
  if exists (
    select 1 from public.agricultural_land_assets a
    where a.organization_id=p_organization_id and a.project_id=p_project_id
      and lower(a.internal_reference)=lower(trim(p_internal_reference))
  ) then raise exception 'agricultural land asset reference already exists'; end if;

  insert into public.agricultural_land_assets(
    organization_id,project_id,name,internal_reference,legal_reference,
    legal_area_quantity,area_unit,legal_location_description,control_basis,
    control_start_date,control_end_date,counterparty_party_id,
    agreement_reference,evidence_reference,agreed_consideration_minor_units,
    consideration_currency,consideration_obligation_id,recorded_by,
    idempotency_key,request_hash
  ) values (
    p_organization_id,p_project_id,trim(p_name),trim(p_internal_reference),
    nullif(trim(p_legal_reference),''),p_legal_area_quantity::numeric(20,6),
    p_area_unit,nullif(trim(p_legal_location_description),''),p_control_basis,
    p_control_start_date,p_control_end_date,p_counterparty_party_id,
    trim(p_agreement_reference),trim(p_evidence_reference),
    p_agreed_consideration_minor_units,p_consideration_currency,
    p_consideration_obligation_id,v_actor,trim(p_idempotency_key),v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id,actor_id,event_type,entity_type,entity_id,payload
  ) values (
    p_organization_id,v_actor,'AGRICULTURAL_LAND_ASSET_RECORDED',
    'agricultural_land_asset',v_id,
    jsonb_build_object(
      'project_id',p_project_id,'control_basis',p_control_basis,
      'counterparty_party_id',p_counterparty_party_id,
      'consideration_recorded',p_agreed_consideration_minor_units is not null,
      'accounting_effect','NONE','payment_effect','NONE'
    )
  );
  return v_id;
end $$;

create or replace function public.link_farm_to_agricultural_land_asset(
  p_organization_id uuid,
  p_project_id uuid,
  p_land_asset_id uuid,
  p_farm_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing public.farm_land_asset_links%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if not exists (
    select 1 from public.investment_projects p
    where p.id=p_project_id and p.organization_id=p_organization_id and p.sector='AGRICULTURE'
  ) then raise exception 'agriculture project not found'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(jsonb_build_object(
    'project_id',p_project_id,'land_asset_id',p_land_asset_id,'farm_id',p_farm_id
  )::text,'sha256'),'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':gf017-farm-link:' || trim(p_idempotency_key),0));
  select * into v_existing from public.farm_land_asset_links
  where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  if not exists (
    select 1 from public.agricultural_land_assets a
    where a.id=p_land_asset_id and a.organization_id=p_organization_id and a.project_id=p_project_id
  ) then raise exception 'agricultural land asset not found in project'; end if;
  perform 1 from public.farms f
  where f.id=p_farm_id and f.organization_id=p_organization_id and f.project_id=p_project_id
  for update;
  if not found then raise exception 'farm not found in project'; end if;
  if exists (select 1 from public.farm_land_asset_links l where l.farm_id=p_farm_id) then
    raise exception 'farm already linked to an agricultural land asset';
  end if;

  insert into public.farm_land_asset_links(
    organization_id,project_id,land_asset_id,farm_id,linked_by,
    idempotency_key,request_hash
  ) values (
    p_organization_id,p_project_id,p_land_asset_id,p_farm_id,v_actor,
    trim(p_idempotency_key),v_hash
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id,actor_id,event_type,entity_type,entity_id,payload
  ) values (
    p_organization_id,v_actor,'FARM_LINKED_TO_AGRICULTURAL_LAND_ASSET',
    'farm_land_asset_link',v_id,
    jsonb_build_object(
      'project_id',p_project_id,'land_asset_id',p_land_asset_id,'farm_id',p_farm_id
    )
  );
  return v_id;
end $$;

-- ===========================================================================
-- 4. Default-deny RLS and security-invoker read models
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['agricultural_land_assets','farm_land_asset_links'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_active_member(organization_id))',t||'_read',t
    );
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

create or replace view public.agricultural_land_assets_read with (security_invoker=on) as
select a.id,a.organization_id,a.project_id,a.name,a.internal_reference,
  a.legal_reference,a.legal_area_quantity::text as legal_area_quantity,a.area_unit,
  a.legal_location_description,a.control_basis,a.control_start_date,a.control_end_date,
  a.counterparty_party_id,p.legal_name as counterparty_name,
  a.agreement_reference,a.evidence_reference,
  a.agreed_consideration_minor_units::text as agreed_consideration_minor_units,
  a.consideration_currency,a.consideration_obligation_id,
  a.recorded_by,a.recorded_at,
  (select count(*) from public.farm_land_asset_links l where l.land_asset_id=a.id) as linked_farm_count
from public.agricultural_land_assets a
join public.parties p on p.id=a.counterparty_party_id and p.organization_id=a.organization_id;

create or replace view public.farm_land_asset_links_read with (security_invoker=on) as
select l.id,l.organization_id,l.project_id,l.land_asset_id,l.farm_id,
  a.name as land_asset_name,a.internal_reference as land_asset_reference,
  a.control_basis,a.legal_area_quantity::text as legal_area_quantity,a.area_unit,
  f.name as farm_name,l.linked_by,l.linked_at
from public.farm_land_asset_links l
join public.agricultural_land_assets a on a.id=l.land_asset_id
join public.farms f on f.id=l.farm_id;

grant select on public.agricultural_land_assets_read,
  public.farm_land_asset_links_read to authenticated;

revoke all on function public.create_agricultural_land_asset(
  uuid,uuid,text,text,text,numeric,text,text,text,date,date,uuid,text,text,bigint,text,uuid,text
) from public,anon;
revoke all on function public.link_farm_to_agricultural_land_asset(
  uuid,uuid,uuid,uuid,text
) from public,anon;
grant execute on function public.create_agricultural_land_asset(
  uuid,uuid,text,text,text,numeric,text,text,text,date,date,uuid,text,text,bigint,text,uuid,text
), public.link_farm_to_agricultural_land_asset(uuid,uuid,uuid,uuid,text)
to authenticated;

-- Qualify pgcrypto independently of the extension's installation schema.
do $pgcrypto_compat$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'GF-017 requires the pgcrypto extension'; end if;
  for v_record in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and p.proname in ('create_agricultural_land_asset','link_farm_to_agricultural_land_asset')
  loop
    v_definition:=pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten:=regexp_replace(
        v_definition,'(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1'||quote_ident(v_pgcrypto_schema)||'.digest(','g'
      );
      execute v_rewritten;
    end if;
  end loop;
end $pgcrypto_compat$;
