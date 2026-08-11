-- GF-005 / S3 — Real Estate Sector Operation vertical slice.
-- Delivers: property assets, parcels, acquisition records, capitalizable cost
-- items that form the carrying amount, and management valuations.
-- No disposition, sale, or revenue recognition in this slice.

-- 1. Property assets: economic assets acquired/controlled by a project.
create table if not exists public.property_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  display_name text not null check (char_length(trim(display_name)) between 2 and 160),
  strategy text not null check (strategy in ('ACQUIRE_HOLD','DEVELOP_SELL','LAND_TRADE')),
  jurisdiction text,
  title_status text check (title_status in ('PENDING','CLEAR','DISPUTED','LEASED')),
  lifecycle_state text not null default 'CANDIDATE' check (lifecycle_state in (
    'CANDIDATE','DUE_DILIGENCE','ACQUIRING','HELD','DEVELOPING','DISPOSING','DISPOSED'
  )),
  acquired_on date,
  acquisition_cost_minor_units bigint check (acquisition_cost_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index if not exists property_assets_project_idx on public.property_assets(project_id);

-- 2. Parcels: cadastral/title identifiers within a property asset.
create table if not exists public.parcels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_asset_id uuid not null references public.property_assets(id) on delete restrict,
  parcel_reference text not null check (char_length(trim(parcel_reference)) between 2 and 120),
  area_sq_meters numeric(12,2) check (area_sq_meters > 0),
  legal_description text,
  geo_boundary jsonb,
  created_at timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (organization_id, property_asset_id)
    references public.property_assets(organization_id, id) on delete restrict
);
create index if not exists parcels_asset_idx on public.parcels(property_asset_id);

-- 3. Property cost items: capitalizable or expensed costs that form carrying amount.
--    These are authoritative posted facts derived from obligations or direct entries.
create table if not exists public.property_cost_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null references public.property_assets(id) on delete restrict,
  parcel_id uuid references public.parcels(id) on delete restrict,
  cost_category text not null check (char_length(trim(cost_category)) between 2 and 80),
  is_capitalizable boolean not null default true,
  cost_minor_units bigint not null check (cost_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  description text,
  occurred_on date not null,
  obligation_id uuid references public.obligations(id) on delete restrict,
  journal_batch_id uuid references public.journal_batches(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recorded_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, property_asset_id)
    references public.property_assets(organization_id, id) on delete restrict,
  foreign key (organization_id, parcel_id)
    references public.parcels(organization_id, id) on delete restrict,
  foreign key (organization_id, obligation_id)
    references public.obligations(organization_id, id) on delete restrict,
  foreign key (organization_id, journal_batch_id)
    references public.journal_batches(organization_id, id) on delete restrict
);
create index if not exists property_cost_items_asset_idx on public.property_cost_items(property_asset_id);
create index if not exists property_cost_items_parcel_idx on public.property_cost_items(parcel_id);

-- 4. Valuations: dated estimates with method/source, separate from realized result.
create table if not exists public.property_valuations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  property_asset_id uuid not null references public.property_assets(id) on delete restrict,
  effective_date date not null,
  valuer_source text not null check (char_length(trim(valuer_source)) between 2 and 160),
  method text not null check (char_length(trim(method)) between 2 and 80),
  valuation_minor_units bigint not null check (valuation_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  assumptions text,
  confidence text check (confidence in ('LOW','MEDIUM','HIGH')),
  status text not null default 'PROPOSED' check (status in ('PROPOSED','APPROVED','REJECTED')),
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  recorded_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (organization_id, property_asset_id)
    references public.property_assets(organization_id, id) on delete restrict
);
create index if not exists property_valuations_asset_idx on public.property_valuations(property_asset_id);

-- 5. RLS: default deny, member reads, no browser writes.
alter table public.property_assets enable row level security;
alter table public.parcels enable row level security;
alter table public.property_cost_items enable row level security;
alter table public.property_valuations enable row level security;
alter table public.property_assets force row level security;
alter table public.parcels force row level security;
alter table public.property_cost_items force row level security;
alter table public.property_valuations force row level security;

create policy property_assets_read on public.property_assets for select to authenticated
  using (public.is_active_member(organization_id));
create policy parcels_read on public.parcels for select to authenticated
  using (public.is_active_member(organization_id));
create policy property_cost_items_read on public.property_cost_items for select to authenticated
  using (public.is_active_member(organization_id));
create policy property_valuations_read on public.property_valuations for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.property_assets, public.parcels, public.property_cost_items,
  public.property_valuations from anon, authenticated;
grant select on public.property_assets, public.parcels, public.property_cost_items,
  public.property_valuations to authenticated;

-- 6. Immutability guards.
create or replace function public.s3_guard_append_only() returns trigger
language plpgsql as $$
begin
  raise exception using
    message = case tg_table_name
      when 'property_cost_items' then 'property cost items are immutable posted facts'
      when 'property_valuations' then 'valuations are immutable once proposed'
      else 'record is append-only' end,
    errcode = 'P0001';
end $$;

drop trigger if exists property_cost_items_immutable on public.property_cost_items;
create trigger property_cost_items_immutable before update or delete on public.property_cost_items
  for each row execute function public.s3_guard_append_only();

-- Valuations can be updated for approval status only.
create or replace function public.s3_guard_valuation_immutable() returns trigger
language plpgsql as $$
begin
  if old is not null and old.status <> 'PROPOSED' then
    raise exception 'valuation is immutable once approved or rejected';
  end if;
  if old is not null and (old.valuation_minor_units is distinct from new.valuation_minor_units
                          or old.effective_date is distinct from new.effective_date
                          or old.method is distinct from new.method) then
    raise exception 'valuation economic terms are immutable';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists property_valuations_immutable on public.property_valuations;
create trigger property_valuations_immutable before update or delete on public.property_valuations
  for each row execute function public.s3_guard_valuation_immutable();

-- 7. Read views: cast int8 to text for exact JavaScript transport.
create or replace view public.property_assets_read with (security_invoker=on) as
select id, organization_id, project_id, display_name, strategy, jurisdiction,
       title_status, lifecycle_state, acquired_on,
       acquisition_cost_minor_units::text as acquisition_cost_minor_units, currency, created_at
from public.property_assets;

create or replace view public.property_cost_items_read with (security_invoker=on) as
select id, organization_id, project_id, property_asset_id, parcel_id, cost_category,
       is_capitalizable, cost_minor_units::text as cost_minor_units, currency,
       description, occurred_on, created_at
from public.property_cost_items;

create or replace view public.property_valuations_read with (security_invoker=on) as
select id, organization_id, project_id, property_asset_id, effective_date, valuer_source,
       method, valuation_minor_units::text as valuation_minor_units, currency, assumptions,
       confidence, status, approved_at, created_at
from public.property_valuations;

create or replace view public.property_carrying_amount with (security_invoker=on) as
select
  pa.organization_id,
  pa.project_id,
  pa.id as property_asset_id,
  pa.currency,
  coalesce(pa.acquisition_cost_minor_units, 0) +
    coalesce(sum(pci.cost_minor_units) filter (where pci.is_capitalizable), 0) as carrying_amount_minor_units
from public.property_assets pa
left join public.property_cost_items pci
  on pci.property_asset_id = pa.id and pci.organization_id = pa.organization_id
where pa.lifecycle_state <> 'DISPOSED'
group by pa.organization_id, pa.project_id, pa.id, pa.currency, pa.acquisition_cost_minor_units;

grant select on public.property_assets_read, public.property_cost_items_read,
  public.property_valuations_read, public.property_carrying_amount to authenticated;

-- 8. Server-authoritative commands.
create or replace function public.create_property_asset(
  p_organization_id uuid,
  p_project_id uuid,
  p_display_name text,
  p_strategy text,
  p_jurisdiction text,
  p_title_status text,
  p_acquired_on date,
  p_acquisition_cost_minor_units bigint,
  p_currency text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text; v_existing uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_display_name is null or char_length(trim(p_display_name)) not between 2 and 160 then
    raise exception 'invalid property display name';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':property-asset:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.property_assets
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  insert into public.property_assets(
    organization_id, project_id, display_name, strategy, jurisdiction, title_status,
    lifecycle_state, acquired_on, acquisition_cost_minor_units, currency, idempotency_key
  ) values (
    p_organization_id, p_project_id, trim(p_display_name), p_strategy, p_jurisdiction,
    p_title_status, case when p_acquired_on is not null then 'HELD' else 'CANDIDATE' end,
    p_acquired_on, p_acquisition_cost_minor_units, p_currency, trim(p_idempotency_key)
  ) returning id into v_id;

  update public.investment_projects set lifecycle_state = 'OPERATING'
  where id = p_project_id and lifecycle_state in ('DRAFT','FUNDING');

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'PROPERTY_ASSET_CREATED','property_asset', v_id,
          jsonb_build_object('project_id', p_project_id, 'display_name', trim(p_display_name),
                             'strategy', p_strategy));
  return v_id;
end $$;

create or replace function public.record_property_cost_item(
  p_organization_id uuid,
  p_project_id uuid,
  p_property_asset_id uuid,
  p_parcel_id uuid,
  p_cost_category text,
  p_is_capitalizable boolean,
  p_cost_minor_units bigint,
  p_currency text,
  p_description text,
  p_occurred_on date,
  p_obligation_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text; v_existing uuid;
  v_batch_id uuid; v_wip_account uuid; v_payable_account uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_cost_minor_units is null or p_cost_minor_units <= 0 then
    raise exception 'cost amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_occurred_on is null then raise exception 'cost date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_cost_category is null or char_length(trim(p_cost_category)) not between 2 and 80 then
    raise exception 'cost category required';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (select 1 from public.property_assets
                 where id = p_property_asset_id and organization_id = p_organization_id
                   and project_id = p_project_id) then
    raise exception 'property asset not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':property-cost:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.property_cost_items
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  -- If capitalizable and no obligation provided, create a journal batch for WIP.
  if p_is_capitalizable and p_obligation_id is null then
    v_wip_account := public.ensure_financial_account(p_organization_id, 'development_wip', 'أعمال تحت التنفيذ', p_currency);
    v_payable_account := public.ensure_financial_account(p_organization_id, 'accrued_cost', 'تكاليف مستحقة', p_currency);

    insert into public.journal_batches(
      organization_id, project_id, status, source_type, source_id, source_version,
      posting_date, description, idempotency_key, posted_by
    ) values (
      p_organization_id, p_project_id, 'POSTED', 'property_cost', gen_random_uuid(), 1,
      p_occurred_on, 'تكلفة عقارية: ' || coalesce(p_description, trim(p_cost_category)),
      trim(p_idempotency_key) || ':cost', v_actor
    ) returning id into v_batch_id;

    insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, sector_object_type, sector_object_id, cost_category, description)
    values (p_organization_id, v_batch_id, v_wip_account, p_cost_minor_units, 0, p_currency, 'property_asset', p_property_asset_id, trim(p_cost_category), p_description);

    insert into public.journal_lines(organization_id, batch_id, account_id, debit_minor_units, credit_minor_units, currency, cost_category, description)
    values (p_organization_id, v_batch_id, v_payable_account, 0, p_cost_minor_units, p_currency, trim(p_cost_category), p_description);
  end if;

  insert into public.property_cost_items(
    organization_id, project_id, property_asset_id, parcel_id, cost_category, is_capitalizable,
    cost_minor_units, currency, description, occurred_on, obligation_id, journal_batch_id,
    idempotency_key, recorded_by
  ) values (
    p_organization_id, p_project_id, p_property_asset_id, p_parcel_id, trim(p_cost_category),
    p_is_capitalizable, p_cost_minor_units, p_currency, p_description, p_occurred_on,
    p_obligation_id, v_batch_id, trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'PROPERTY_COST_RECORDED','property_cost_item', v_id,
          jsonb_build_object('project_id', p_project_id, 'property_asset_id', p_property_asset_id,
                             'cost_minor_units', p_cost_minor_units, 'currency', p_currency,
                             'is_capitalizable', p_is_capitalizable));
  return v_id;
end $$;

create or replace function public.record_property_valuation(
  p_organization_id uuid,
  p_project_id uuid,
  p_property_asset_id uuid,
  p_effective_date date,
  p_valuer_source text,
  p_method text,
  p_valuation_minor_units bigint,
  p_currency text,
  p_assumptions text,
  p_confidence text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid; v_project_currency text; v_existing uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_valuation_minor_units is null or p_valuation_minor_units <= 0 then
    raise exception 'valuation amount must be positive';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_effective_date is null then raise exception 'valuation effective date required'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_valuer_source is null or char_length(trim(p_valuer_source)) not between 2 and 160 then
    raise exception 'valuer/source required';
  end if;
  if p_method is null or char_length(trim(p_method)) not between 2 and 80 then
    raise exception 'valuation method required';
  end if;

  select reporting_currency into v_project_currency
  from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project currency'; end if;

  if not exists (select 1 from public.property_assets
                 where id = p_property_asset_id and organization_id = p_organization_id
                   and project_id = p_project_id) then
    raise exception 'property asset not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':valuation:' || trim(p_idempotency_key), 0));
  select id into v_existing from public.property_valuations
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if v_existing is not null then return v_existing; end if;

  insert into public.property_valuations(
    organization_id, project_id, property_asset_id, effective_date, valuer_source, method,
    valuation_minor_units, currency, assumptions, confidence, status, idempotency_key, recorded_by
  ) values (
    p_organization_id, p_project_id, p_property_asset_id, p_effective_date, trim(p_valuer_source),
    trim(p_method), p_valuation_minor_units, p_currency, p_assumptions, p_confidence, 'PROPOSED',
    trim(p_idempotency_key), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values (p_organization_id, v_actor, 'VALUATION_RECORDED','property_valuation', v_id,
          jsonb_build_object('project_id', p_project_id, 'property_asset_id', p_property_asset_id,
                             'valuation_minor_units', p_valuation_minor_units, 'currency', p_currency,
                             'effective_date', p_effective_date));
  return v_id;
end $$;

revoke all on function public.create_property_asset(uuid,uuid,text,text,text,text,date,bigint,text,text) from public, anon;
revoke all on function public.record_property_cost_item(uuid,uuid,uuid,uuid,text,boolean,bigint,text,text,date,uuid,text) from public, anon;
revoke all on function public.record_property_valuation(uuid,uuid,uuid,date,text,text,bigint,text,text,text,text) from public, anon;
grant execute on function public.create_property_asset(uuid,uuid,text,text,text,text,date,bigint,text,text),
  public.record_property_cost_item(uuid,uuid,uuid,uuid,text,boolean,bigint,text,text,date,uuid,text),
  public.record_property_valuation(uuid,uuid,uuid,date,text,text,bigint,text,text,text,text)
to authenticated;
