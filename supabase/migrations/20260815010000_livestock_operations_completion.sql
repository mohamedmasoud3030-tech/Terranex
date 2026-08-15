-- GF-023 — Livestock Operations Completion.
--
-- Bounded operational facts only: optional Animal identity, health/treatment/
-- vaccination and explicit withdrawal windows, reproduction observations linked
-- to the existing GF-022 BIRTH ledger, and feed issues with evidence-aware FCR.
--
-- Deliberately absent: buyers, purchasing, SALE_OUT/PURCHASE_IN, dispatch,
-- revenue, receivables, collections, profitability, Finance posting and
-- Livestock closeout. No inventory balance is inferred for medicine or feed.

-- ---------------------------------------------------------------------------
-- 1. Immutable operational reference and fact tables.
-- ---------------------------------------------------------------------------

create table public.livestock_medicine_products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  product_reference text not null check (char_length(trim(product_reference)) between 1 and 80),
  name text not null check (char_length(trim(name)) between 2 and 160),
  product_kind text not null check (product_kind in ('MEDICINE','VACCINE')),
  active_ingredient text check (active_ingredient is null or char_length(trim(active_ingredient)) between 2 and 200),
  default_withdrawal_days integer not null check (default_withdrawal_days between 0 and 3650),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  unique (organization_id, project_id, product_reference),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index livestock_medicine_products_project_idx
  on public.livestock_medicine_products(project_id, product_kind);

create table public.livestock_animals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  identification_cohort_id uuid not null,
  identifier_type text not null check (identifier_type in ('EAR_TAG','RFID','OTHER')),
  identifier_value text not null check (char_length(trim(identifier_value)) between 1 and 100),
  identifier_normalized text not null check (char_length(identifier_normalized) between 1 and 100),
  sex text not null check (sex in ('MALE','FEMALE','UNKNOWN')),
  birth_date date,
  breed_descriptor text check (breed_descriptor is null or char_length(trim(breed_descriptor)) between 2 and 120),
  identified_at timestamptz not null,
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  identified_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (id, organization_id, project_id, identification_cohort_id),
  unique (organization_id, idempotency_key),
  -- Identifier scope is explicit: type + normalized value is unique inside one
  -- tenant/project. The same physical value in another tenant/project is safe.
  unique (organization_id, project_id, identifier_type, identifier_normalized),
  foreign key (identification_cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint livestock_animal_birth_before_identification check (
    birth_date is null or birth_date <= (identified_at at time zone 'UTC')::date
  )
);
create index livestock_animals_cohort_idx
  on public.livestock_animals(identification_cohort_id, identified_at);

-- Membership is provenance, not a mutable current Cohort column. GF-023 only
-- creates the initial IDENTIFIED membership. A future transfer must be coupled
-- explicitly to quantity/lineage semantics; it must never silently move count.
create table public.livestock_animal_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  animal_id uuid not null,
  cohort_id uuid not null,
  effective_at timestamptz not null,
  membership_type text not null check (membership_type = 'IDENTIFIED'),
  provenance_reference text check (provenance_reference is null or char_length(trim(provenance_reference)) between 2 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  unique (id, organization_id, project_id),
  unique (animal_id),
  foreign key (animal_id, organization_id, project_id, cohort_id)
    references public.livestock_animals(id, organization_id, project_id, identification_cohort_id)
    on delete restrict,
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict
);
create index livestock_animal_memberships_cohort_idx
  on public.livestock_animal_memberships(cohort_id, effective_at);

create table public.livestock_health_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  animal_id uuid,
  event_type text not null check (event_type in ('OBSERVATION','DIAGNOSIS','TREATMENT','VACCINATION')),
  condition_classification text check (condition_classification is null or condition_classification in (
    'INFECTIOUS','PARASITIC','INJURY','RESPIRATORY','DIGESTIVE','REPRODUCTIVE','NUTRITIONAL','OTHER'
  )),
  condition_name text check (condition_name is null or char_length(trim(condition_name)) between 2 and 200),
  medicine_product_id uuid,
  dose_quantity numeric(18,3) check (dose_quantity is null or dose_quantity > 0),
  dose_unit text check (dose_unit is null or dose_unit in ('ML','MG','G','DOSE','TABLET')),
  administration_route text check (administration_route is null or administration_route in ('ORAL','INJECTION','TOPICAL','OTHER')),
  effective_at timestamptz not null,
  practitioner_name text not null check (char_length(trim(practitioner_name)) between 2 and 160),
  withdrawal_period_days integer check (withdrawal_period_days is null or withdrawal_period_days between 0 and 3650),
  withdrawal_ends_at timestamptz,
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (animal_id, organization_id, project_id)
    references public.livestock_animals(id, organization_id, project_id) on delete restrict,
  foreign key (medicine_product_id, organization_id, project_id)
    references public.livestock_medicine_products(id, organization_id, project_id) on delete restrict
);
create index livestock_health_events_cohort_idx
  on public.livestock_health_events(cohort_id, effective_at desc);
create index livestock_health_events_withdrawal_idx
  on public.livestock_health_events(project_id, withdrawal_ends_at)
  where withdrawal_ends_at is not null;

create table public.livestock_reproduction_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  subject_animal_id uuid,
  event_type text not null check (event_type in ('BREEDING_SERVICE','PREGNANCY_CHECK','BIRTH_OUTCOME','WEANING')),
  subject_count integer not null check (subject_count > 0),
  service_method text check (service_method is null or service_method in ('NATURAL','ARTIFICIAL_INSEMINATION','OTHER')),
  pregnancy_status text check (pregnancy_status is null or pregnancy_status in ('POSITIVE','NEGATIVE','INCONCLUSIVE')),
  expected_birth_date date,
  observed_live_birth_count integer check (observed_live_birth_count is null or observed_live_birth_count >= 0),
  stillbirth_count integer check (stillbirth_count is null or stillbirth_count >= 0),
  birth_quantity_effect text check (birth_quantity_effect is null or birth_quantity_effect in ('OBSERVATION_ONLY','GF022_BIRTH')),
  birth_quantity_event_id uuid,
  weaned_count integer check (weaned_count is null or weaned_count > 0),
  dam_animal_id uuid,
  sire_animal_id uuid,
  effective_at timestamptz not null,
  performed_by_name text not null check (char_length(trim(performed_by_name)) between 2 and 160),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  unique (birth_quantity_event_id),
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (subject_animal_id, organization_id, project_id)
    references public.livestock_animals(id, organization_id, project_id) on delete restrict,
  foreign key (dam_animal_id, organization_id, project_id)
    references public.livestock_animals(id, organization_id, project_id) on delete restrict,
  foreign key (sire_animal_id, organization_id, project_id)
    references public.livestock_animals(id, organization_id, project_id) on delete restrict,
  foreign key (birth_quantity_event_id, organization_id, project_id, cohort_id)
    references public.livestock_quantity_events(id, organization_id, project_id, cohort_id) on delete restrict
);
create index livestock_reproduction_events_cohort_idx
  on public.livestock_reproduction_events(cohort_id, effective_at desc);

create table public.livestock_feed_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  item_reference text not null check (char_length(trim(item_reference)) between 1 and 80),
  name text not null check (char_length(trim(name)) between 2 and 160),
  feed_category text not null check (feed_category in ('ROUGHAGE','CONCENTRATE','SUPPLEMENT','MINERAL','OTHER')),
  issue_unit text not null check (issue_unit in ('KG','LITER')),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  unique (organization_id, project_id, item_reference),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index livestock_feed_items_project_idx
  on public.livestock_feed_items(project_id, feed_category);

create table public.livestock_feed_issues (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  cohort_id uuid not null,
  feed_item_id uuid not null,
  quantity numeric(18,3) not null check (quantity > 0),
  unit text not null check (unit in ('KG','LITER')),
  effective_at timestamptz not null,
  feeding_period_start date,
  feeding_period_end date,
  issued_by_name text not null check (char_length(trim(issued_by_name)) between 2 and 160),
  evidence_reference text check (evidence_reference is null or char_length(trim(evidence_reference)) between 2 and 200),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 2000),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (cohort_id, organization_id, project_id)
    references public.livestock_cohorts(id, organization_id, project_id) on delete restrict,
  foreign key (feed_item_id, organization_id, project_id)
    references public.livestock_feed_items(id, organization_id, project_id) on delete restrict,
  constraint livestock_feed_period_complete check (
    (feeding_period_start is null and feeding_period_end is null) or
    (feeding_period_start is not null and feeding_period_end is not null and feeding_period_start <= feeding_period_end)
  )
);
create index livestock_feed_issues_cohort_idx
  on public.livestock_feed_issues(cohort_id, effective_at desc);

-- ---------------------------------------------------------------------------
-- 2. Privileged-path invariant guards.
-- ---------------------------------------------------------------------------

create function public.gf023_normalize_identifier(p_identifier text)
returns text language sql immutable set search_path=pg_catalog
as $$
  select upper(regexp_replace(trim(coalesce(p_identifier, '')), '[[:space:]-]+', '', 'g'))
$$;

create function public.gf023_require_idempotency_key(p_key text)
returns void language plpgsql immutable set search_path=pg_catalog as $$
begin
  if p_key is null or char_length(trim(p_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
end $$;

create function public.gf023_validate_operational_target(
  p_organization_id uuid,
  p_project_id uuid,
  p_cohort_id uuid,
  p_animal_id uuid,
  p_effective_at timestamptz,
  p_allow_zero_quantity boolean default false
) returns void language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  v_quantity integer;
begin
  perform public.gf020_require_project(p_organization_id, p_project_id);
  perform public.gf021_require_active_cohort(p_organization_id, p_project_id, p_cohort_id);
  if p_effective_at is null then raise exception 'invalid livestock operational effective time'; end if;
  if p_effective_at < public.gf022_cohort_inception_at(p_cohort_id) then
    raise exception 'livestock operational effective time precedes Cohort inception';
  end if;

  -- Serialize with every GF-022 quantity command, then read the same as-of
  -- quantity resolver. This closes identify/health/feed vs quantity races.
  perform public.gf022_lock_cohort_quantity(p_cohort_id);
  v_quantity := public.livestock_cohort_quantity_as_of(p_cohort_id, p_effective_at);
  if not p_allow_zero_quantity and v_quantity <= 0 then
    raise exception 'livestock Cohort has no positive quantity at the operational effective time';
  end if;

  if p_animal_id is not null and not exists (
    select 1
      from public.livestock_animals a
      join public.livestock_animal_memberships m
        on (m.animal_id, m.organization_id, m.project_id) =
           (a.id, a.organization_id, a.project_id)
     where a.id = p_animal_id
       and a.organization_id = p_organization_id
       and a.project_id = p_project_id
       and m.cohort_id = p_cohort_id
       and m.effective_at <= p_effective_at
  ) then
    raise exception 'livestock Animal is not a member of the Cohort at the effective time';
  end if;
end $$;

create function public.gf023_validate_animal() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_quantity integer;
  v_identified integer;
begin
  new.identifier_normalized := public.gf023_normalize_identifier(new.identifier_value);
  if char_length(new.identifier_normalized) not between 1 and 100 then
    raise exception 'invalid livestock Animal identifier';
  end if;
  perform public.gf023_validate_operational_target(
    new.organization_id, new.project_id, new.identification_cohort_id,
    null, new.identified_at, false
  );
  v_quantity := public.livestock_cohort_quantity_as_of(new.identification_cohort_id, new.identified_at);
  select count(*) into v_identified
    from public.livestock_animals a
   where a.identification_cohort_id = new.identification_cohort_id
     and a.identified_at <= new.identified_at;
  if v_identified + 1 > v_quantity then
    raise exception 'identified Animal count exceeds Cohort quantity at the effective time';
  end if;
  return new;
end $$;

create function public.gf023_validate_animal_membership() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_animal record;
begin
  select * into v_animal from public.livestock_animals where id = new.animal_id;
  if not found
     or (v_animal.organization_id, v_animal.project_id, v_animal.identification_cohort_id)
        <> (new.organization_id, new.project_id, new.cohort_id)
     or v_animal.identified_at <> new.effective_at then
    raise exception 'livestock Animal membership must match identification provenance';
  end if;
  return new;
end $$;

create function public.gf023_validate_animal_membership_shape() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_animal_id uuid; v_count integer;
begin
  -- Trigger NEW has a table-specific record shape. JSON extraction avoids
  -- resolving a non-existent animal_id field when fired on livestock_animals.
  v_animal_id := coalesce(
    (to_jsonb(new)->>'animal_id')::uuid,
    (to_jsonb(new)->>'id')::uuid
  );
  select count(*) into v_count from public.livestock_animal_memberships where animal_id = v_animal_id;
  if v_count <> 1 then
    raise exception 'livestock Animal requires exactly one identification membership';
  end if;
  return null;
end $$;

create function public.gf023_validate_health_event() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_product record;
begin
  perform public.gf023_validate_operational_target(
    new.organization_id, new.project_id, new.cohort_id,
    new.animal_id, new.effective_at, false
  );

  if new.event_type in ('OBSERVATION','DIAGNOSIS') then
    if new.condition_name is null then
      raise exception 'livestock observation or diagnosis requires a condition';
    end if;
    if new.event_type = 'DIAGNOSIS' and new.condition_classification is null then
      raise exception 'livestock diagnosis requires a condition classification';
    end if;
    if new.medicine_product_id is not null or new.dose_quantity is not null
       or new.dose_unit is not null or new.administration_route is not null
       or new.withdrawal_period_days is not null or new.withdrawal_ends_at is not null then
      raise exception 'livestock observation or diagnosis must not carry administration fields';
    end if;
  else
    if new.medicine_product_id is null or new.dose_quantity is null
       or new.dose_unit is null or new.administration_route is null then
      raise exception 'livestock treatment or vaccination requires product, dose, unit and route';
    end if;
    select * into v_product from public.livestock_medicine_products
     where id = new.medicine_product_id
       and organization_id = new.organization_id
       and project_id = new.project_id;
    if not found then raise exception 'livestock medicine product not found'; end if;
    if (new.event_type = 'TREATMENT' and v_product.product_kind <> 'MEDICINE')
       or (new.event_type = 'VACCINATION' and v_product.product_kind <> 'VACCINE') then
      raise exception 'livestock medicine product kind does not match the health event';
    end if;
    -- Withdrawal is a frozen administration fact, derived from the immutable
    -- product reference. Zero explicitly means no withdrawal interval.
    new.withdrawal_period_days := v_product.default_withdrawal_days;
    new.withdrawal_ends_at := new.effective_at + make_interval(days => v_product.default_withdrawal_days);
  end if;
  return new;
end $$;

create function public.gf023_validate_reproduction_event() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_birth record; v_parent record;
begin
  perform public.gf023_validate_operational_target(
    new.organization_id, new.project_id, new.cohort_id,
    new.subject_animal_id, new.effective_at,
    new.event_type = 'BIRTH_OUTCOME'
  );
  if new.subject_animal_id is not null and new.subject_count <> 1 then
    raise exception 'individual reproduction event subject count must equal one';
  end if;
  if new.event_type <> 'BIRTH_OUTCOME'
     and new.subject_count > public.livestock_cohort_quantity_as_of(new.cohort_id, new.effective_at) then
    raise exception 'reproduction subject count exceeds Cohort quantity at the effective time';
  end if;
  if new.expected_birth_date is not null
     and new.expected_birth_date < (new.effective_at at time zone 'UTC')::date then
    raise exception 'expected birth date cannot precede the reproduction event';
  end if;

  if new.event_type = 'BREEDING_SERVICE' then
    if new.service_method is null then raise exception 'breeding service method is required'; end if;
    if new.pregnancy_status is not null or new.observed_live_birth_count is not null
       or new.stillbirth_count is not null or new.birth_quantity_effect is not null
       or new.birth_quantity_event_id is not null or new.weaned_count is not null
       or new.dam_animal_id is not null or new.sire_animal_id is not null then
      raise exception 'invalid breeding service fields';
    end if;
  elsif new.event_type = 'PREGNANCY_CHECK' then
    if new.pregnancy_status is null then raise exception 'pregnancy check status is required'; end if;
    if new.pregnancy_status <> 'POSITIVE' and new.expected_birth_date is not null then
      raise exception 'expected birth date requires a positive pregnancy check';
    end if;
    if new.service_method is not null or new.observed_live_birth_count is not null
       or new.stillbirth_count is not null or new.birth_quantity_effect is not null
       or new.birth_quantity_event_id is not null or new.weaned_count is not null
       or new.dam_animal_id is not null or new.sire_animal_id is not null then
      raise exception 'invalid pregnancy check fields';
    end if;
  elsif new.event_type = 'BIRTH_OUTCOME' then
    if new.observed_live_birth_count is null or new.stillbirth_count is null
       or new.birth_quantity_effect is null
       or new.observed_live_birth_count + new.stillbirth_count <= 0 then
      raise exception 'birth outcome requires observed live/stillbirth counts and quantity effect';
    end if;
    if new.service_method is not null or new.pregnancy_status is not null
       or new.expected_birth_date is not null or new.weaned_count is not null then
      raise exception 'invalid birth outcome fields';
    end if;
    if new.birth_quantity_effect = 'GF022_BIRTH' then
      if new.observed_live_birth_count <= 0 or new.birth_quantity_event_id is null then
        raise exception 'authoritative birth outcome requires a GF-022 BIRTH event';
      end if;
      select * into v_birth from public.livestock_quantity_events
       where id = new.birth_quantity_event_id
         and organization_id = new.organization_id
         and project_id = new.project_id
         and cohort_id = new.cohort_id;
      if not found or v_birth.event_type <> 'BIRTH'
         or v_birth.quantity <> new.observed_live_birth_count
         or v_birth.effective_at <> new.effective_at then
        raise exception 'reproduction birth outcome does not match the GF-022 BIRTH event';
      end if;
    elsif new.birth_quantity_event_id is not null then
      raise exception 'observation-only birth outcome must not link a quantity event';
    end if;
  else
    if new.weaned_count is null then raise exception 'weaning requires a weaned count'; end if;
    if new.weaned_count > public.livestock_cohort_quantity_as_of(new.cohort_id, new.effective_at) then
      raise exception 'weaned count exceeds Cohort quantity at the effective time';
    end if;
    if new.service_method is not null or new.pregnancy_status is not null
       or new.expected_birth_date is not null or new.observed_live_birth_count is not null
       or new.stillbirth_count is not null or new.birth_quantity_effect is not null
       or new.birth_quantity_event_id is not null or new.dam_animal_id is not null
       or new.sire_animal_id is not null then
      raise exception 'invalid weaning fields';
    end if;
  end if;

  if new.dam_animal_id is not null then
    select sex into v_parent from public.livestock_animals
     where id = new.dam_animal_id and organization_id = new.organization_id and project_id = new.project_id;
    if not found or v_parent.sex <> 'FEMALE' then raise exception 'livestock dam must reference a female Animal'; end if;
  end if;
  if new.sire_animal_id is not null then
    select sex into v_parent from public.livestock_animals
     where id = new.sire_animal_id and organization_id = new.organization_id and project_id = new.project_id;
    if not found or v_parent.sex <> 'MALE' then raise exception 'livestock sire must reference a male Animal'; end if;
  end if;
  if new.dam_animal_id is not null and new.dam_animal_id = new.sire_animal_id then
    raise exception 'livestock dam and sire must be distinct';
  end if;
  return new;
end $$;

create function public.gf023_validate_feed_issue() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_unit text;
begin
  perform public.gf023_validate_operational_target(
    new.organization_id, new.project_id, new.cohort_id,
    null, new.effective_at, false
  );
  select issue_unit into v_unit from public.livestock_feed_items
   where id = new.feed_item_id
     and organization_id = new.organization_id
     and project_id = new.project_id;
  if v_unit is null then raise exception 'livestock feed item not found'; end if;
  if new.unit <> v_unit then raise exception 'livestock feed issue unit does not match the feed item'; end if;
  return new;
end $$;

-- Sector and append-only guards protect owner/import paths too.
do $$
declare t text;
begin
  foreach t in array array[
    'livestock_medicine_products','livestock_animals','livestock_animal_memberships',
    'livestock_health_events','livestock_reproduction_events',
    'livestock_feed_items','livestock_feed_issues'
  ] loop
    execute format('create trigger %I before insert on public.%I for each row execute function public.gf020_sector_guard()', t || '_sector_guard', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.gf021_immutable()', t || '_no_change', t);
  end loop;
end $$;

create trigger livestock_animals_validate
  before insert on public.livestock_animals
  for each row execute function public.gf023_validate_animal();
create trigger livestock_animal_memberships_validate
  before insert on public.livestock_animal_memberships
  for each row execute function public.gf023_validate_animal_membership();
create constraint trigger livestock_animals_membership_shape
  after insert on public.livestock_animals
  deferrable initially deferred
  for each row execute function public.gf023_validate_animal_membership_shape();
create constraint trigger livestock_memberships_shape
  after insert on public.livestock_animal_memberships
  deferrable initially deferred
  for each row execute function public.gf023_validate_animal_membership_shape();
create trigger livestock_health_events_validate
  before insert on public.livestock_health_events
  for each row execute function public.gf023_validate_health_event();
create trigger livestock_reproduction_events_validate
  before insert on public.livestock_reproduction_events
  for each row execute function public.gf023_validate_reproduction_event();
create trigger livestock_feed_issues_validate
  before insert on public.livestock_feed_issues
  for each row execute function public.gf023_validate_feed_issue();

-- ---------------------------------------------------------------------------
-- 3. Server-authoritative, payload-bound commands with same-transaction audit.
-- ---------------------------------------------------------------------------

create function public.create_livestock_medicine_product(
  p_organization_id uuid, p_project_id uuid, p_product_reference text,
  p_name text, p_product_kind text, p_active_ingredient text,
  p_default_withdrawal_days integer, p_notes text, p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_kind text:=upper(trim(coalesce(p_product_kind,'')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||upper(trim(coalesce(p_product_reference,'')))||'|'||trim(coalesce(p_name,''))||'|'||v_kind||'|'||coalesce(trim(p_active_ingredient),'')||'|'||coalesce(p_default_withdrawal_days::text,'')||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-product:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_medicine_products where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if char_length(trim(coalesce(p_product_reference,''))) not between 1 and 80 then raise exception 'invalid livestock medicine product reference'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'invalid livestock medicine product name'; end if;
  if v_kind not in ('MEDICINE','VACCINE') then raise exception 'invalid livestock medicine product kind'; end if;
  if p_default_withdrawal_days is null or p_default_withdrawal_days not between 0 and 3650 then raise exception 'invalid livestock withdrawal period'; end if;
  begin
    insert into public.livestock_medicine_products(organization_id,project_id,product_reference,name,product_kind,active_ingredient,default_withdrawal_days,notes,created_by,idempotency_key,request_hash)
    values(p_organization_id,p_project_id,upper(trim(p_product_reference)),trim(p_name),v_kind,nullif(trim(p_active_ingredient),''),p_default_withdrawal_days,nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  exception when unique_violation then raise exception 'livestock medicine product reference already exists'; end;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_MEDICINE_PRODUCT_CREATED','livestock_medicine_product',v_id,jsonb_build_object('project_id',p_project_id,'product_kind',v_kind));
  return v_id;
end $$;

create function public.identify_livestock_animal(
  p_organization_id uuid, p_project_id uuid, p_cohort_id uuid,
  p_identifier_type text, p_identifier_value text, p_sex text,
  p_birth_date date, p_breed_descriptor text, p_identified_at timestamptz,
  p_evidence_reference text, p_notes text, p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_type text:=upper(trim(coalesce(p_identifier_type,''))); v_sex text:=upper(trim(coalesce(p_sex,'')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||p_cohort_id::text||'|'||v_type||'|'||public.gf023_normalize_identifier(p_identifier_value)||'|'||v_sex||'|'||coalesce(p_birth_date::text,'')||'|'||coalesce(trim(p_breed_descriptor),'')||'|'||coalesce(p_identified_at::text,'')||'|'||coalesce(trim(p_evidence_reference),'')||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-animal:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_animals where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if v_type not in ('EAR_TAG','RFID','OTHER') then raise exception 'invalid livestock Animal identifier type'; end if;
  if char_length(public.gf023_normalize_identifier(p_identifier_value)) not between 1 and 100 then raise exception 'invalid livestock Animal identifier'; end if;
  if v_sex not in ('MALE','FEMALE','UNKNOWN') then raise exception 'invalid livestock Animal sex'; end if;
  if p_identified_at is null then raise exception 'invalid livestock Animal identification time'; end if;
  begin
    insert into public.livestock_animals(organization_id,project_id,identification_cohort_id,identifier_type,identifier_value,identifier_normalized,sex,birth_date,breed_descriptor,identified_at,evidence_reference,notes,identified_by,idempotency_key,request_hash)
    values(p_organization_id,p_project_id,p_cohort_id,v_type,trim(p_identifier_value),public.gf023_normalize_identifier(p_identifier_value),v_sex,p_birth_date,nullif(trim(p_breed_descriptor),''),p_identified_at,nullif(trim(p_evidence_reference),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  exception when unique_violation then raise exception 'livestock Animal identifier already exists'; end;
  insert into public.livestock_animal_memberships(organization_id,project_id,animal_id,cohort_id,effective_at,membership_type,provenance_reference,recorded_by)
  values(p_organization_id,p_project_id,v_id,p_cohort_id,p_identified_at,'IDENTIFIED',nullif(trim(p_evidence_reference),''),v_actor);
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_ANIMAL_IDENTIFIED','livestock_animal',v_id,jsonb_build_object('project_id',p_project_id,'cohort_id',p_cohort_id,'identifier_type',v_type,'quantity_effect',0));
  return v_id;
end $$;

create function public.record_livestock_health_event(
  p_organization_id uuid, p_project_id uuid, p_cohort_id uuid, p_animal_id uuid,
  p_event_type text, p_condition_classification text, p_condition_name text,
  p_medicine_product_id uuid, p_dose_quantity numeric, p_dose_unit text,
  p_administration_route text, p_effective_at timestamptz,
  p_practitioner_name text, p_evidence_reference text, p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_type text:=upper(trim(coalesce(p_event_type,'')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||p_cohort_id::text||'|'||coalesce(p_animal_id::text,'')||'|'||v_type||'|'||upper(trim(coalesce(p_condition_classification,'')))||'|'||coalesce(trim(p_condition_name),'')||'|'||coalesce(p_medicine_product_id::text,'')||'|'||coalesce(p_dose_quantity::text,'')||'|'||upper(trim(coalesce(p_dose_unit,'')))||'|'||upper(trim(coalesce(p_administration_route,'')))||'|'||coalesce(p_effective_at::text,'')||'|'||trim(coalesce(p_practitioner_name,''))||'|'||coalesce(trim(p_evidence_reference),'')||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-health:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_health_events where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if v_type not in ('OBSERVATION','DIAGNOSIS','TREATMENT','VACCINATION') then raise exception 'invalid livestock health event type'; end if;
  if char_length(trim(coalesce(p_practitioner_name,''))) not between 2 and 160 then raise exception 'invalid livestock health event actor'; end if;
  insert into public.livestock_health_events(organization_id,project_id,cohort_id,animal_id,event_type,condition_classification,condition_name,medicine_product_id,dose_quantity,dose_unit,administration_route,effective_at,practitioner_name,evidence_reference,notes,recorded_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,p_cohort_id,p_animal_id,v_type,nullif(upper(trim(coalesce(p_condition_classification,''))),''),nullif(trim(p_condition_name),''),p_medicine_product_id,p_dose_quantity,nullif(upper(trim(coalesce(p_dose_unit,''))),''),nullif(upper(trim(coalesce(p_administration_route,''))),''),p_effective_at,trim(p_practitioner_name),nullif(trim(p_evidence_reference),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_HEALTH_EVENT_RECORDED','livestock_health_event',v_id,jsonb_build_object('project_id',p_project_id,'cohort_id',p_cohort_id,'animal_id',p_animal_id,'event_type',v_type));
  return v_id;
end $$;

create function public.record_livestock_reproduction_event(
  p_organization_id uuid, p_project_id uuid, p_cohort_id uuid, p_subject_animal_id uuid,
  p_event_type text, p_subject_count integer, p_service_method text,
  p_pregnancy_status text, p_expected_birth_date date,
  p_observed_live_birth_count integer, p_stillbirth_count integer,
  p_birth_quantity_effect text, p_weaned_count integer,
  p_dam_animal_id uuid, p_sire_animal_id uuid, p_effective_at timestamptz,
  p_performed_by_name text, p_evidence_reference text, p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_birth uuid; v_type text:=upper(trim(coalesce(p_event_type,''))); v_effect text:=nullif(upper(trim(coalesce(p_birth_quantity_effect,''))),'');
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||p_cohort_id::text||'|'||coalesce(p_subject_animal_id::text,'')||'|'||v_type||'|'||coalesce(p_subject_count::text,'')||'|'||upper(trim(coalesce(p_service_method,'')))||'|'||upper(trim(coalesce(p_pregnancy_status,'')))||'|'||coalesce(p_expected_birth_date::text,'')||'|'||coalesce(p_observed_live_birth_count::text,'')||'|'||coalesce(p_stillbirth_count::text,'')||'|'||coalesce(v_effect,'')||'|'||coalesce(p_weaned_count::text,'')||'|'||coalesce(p_dam_animal_id::text,'')||'|'||coalesce(p_sire_animal_id::text,'')||'|'||coalesce(p_effective_at::text,'')||'|'||trim(coalesce(p_performed_by_name,''))||'|'||coalesce(trim(p_evidence_reference),'')||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-reproduction:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_reproduction_events where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if v_type not in ('BREEDING_SERVICE','PREGNANCY_CHECK','BIRTH_OUTCOME','WEANING') then raise exception 'invalid livestock reproduction event type'; end if;
  if p_subject_count is null or p_subject_count<=0 then raise exception 'invalid livestock reproduction subject count'; end if;
  if char_length(trim(coalesce(p_performed_by_name,''))) not between 2 and 160 then raise exception 'invalid livestock reproduction actor'; end if;

  -- The only authoritative birth quantity is the existing GF-022 command. It
  -- executes inside this transaction and its returned event is linked below.
  if v_type='BIRTH_OUTCOME' and v_effect='GF022_BIRTH' then
    if p_observed_live_birth_count is null or p_observed_live_birth_count<=0 then raise exception 'authoritative birth outcome requires a positive live birth count'; end if;
    v_birth:=public.record_livestock_birth(
      p_organization_id,p_project_id,p_cohort_id,p_observed_live_birth_count,p_effective_at,
      p_evidence_reference,p_notes,
      'gf023-birth-'||substring(public.gf020_hash(p_organization_id::text||'|'||trim(p_idempotency_key)) from 1 for 48)
    );
  end if;

  insert into public.livestock_reproduction_events(organization_id,project_id,cohort_id,subject_animal_id,event_type,subject_count,service_method,pregnancy_status,expected_birth_date,observed_live_birth_count,stillbirth_count,birth_quantity_effect,birth_quantity_event_id,weaned_count,dam_animal_id,sire_animal_id,effective_at,performed_by_name,evidence_reference,notes,recorded_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,p_cohort_id,p_subject_animal_id,v_type,p_subject_count,nullif(upper(trim(coalesce(p_service_method,''))),''),nullif(upper(trim(coalesce(p_pregnancy_status,''))),''),p_expected_birth_date,p_observed_live_birth_count,p_stillbirth_count,v_effect,v_birth,p_weaned_count,p_dam_animal_id,p_sire_animal_id,p_effective_at,trim(p_performed_by_name),nullif(trim(p_evidence_reference),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_REPRODUCTION_EVENT_RECORDED','livestock_reproduction_event',v_id,jsonb_build_object('project_id',p_project_id,'cohort_id',p_cohort_id,'event_type',v_type,'birth_quantity_effect',v_effect,'birth_quantity_event_id',v_birth));
  return v_id;
end $$;

create function public.create_livestock_feed_item(
  p_organization_id uuid, p_project_id uuid, p_item_reference text,
  p_name text, p_feed_category text, p_issue_unit text, p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_category text:=upper(trim(coalesce(p_feed_category,''))); v_unit text:=upper(trim(coalesce(p_issue_unit,'')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||upper(trim(coalesce(p_item_reference,'')))||'|'||trim(coalesce(p_name,''))||'|'||v_category||'|'||v_unit||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-feed-item:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_feed_items where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if char_length(trim(coalesce(p_item_reference,''))) not between 1 and 80 then raise exception 'invalid livestock feed item reference'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'invalid livestock feed item name'; end if;
  if v_category not in ('ROUGHAGE','CONCENTRATE','SUPPLEMENT','MINERAL','OTHER') then raise exception 'invalid livestock feed category'; end if;
  if v_unit not in ('KG','LITER') then raise exception 'invalid livestock feed unit'; end if;
  begin
    insert into public.livestock_feed_items(organization_id,project_id,item_reference,name,feed_category,issue_unit,notes,created_by,idempotency_key,request_hash)
    values(p_organization_id,p_project_id,upper(trim(p_item_reference)),trim(p_name),v_category,v_unit,nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  exception when unique_violation then raise exception 'livestock feed item reference already exists'; end;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_FEED_ITEM_CREATED','livestock_feed_item',v_id,jsonb_build_object('project_id',p_project_id,'feed_category',v_category,'issue_unit',v_unit));
  return v_id;
end $$;

create function public.record_livestock_feed_issue(
  p_organization_id uuid, p_project_id uuid, p_cohort_id uuid,
  p_feed_item_id uuid, p_quantity numeric, p_unit text, p_effective_at timestamptz,
  p_feeding_period_start date, p_feeding_period_end date,
  p_issued_by_name text, p_evidence_reference text, p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_row record; v_id uuid; v_unit text:=upper(trim(coalesce(p_unit,'')));
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.gf023_require_idempotency_key(p_idempotency_key);
  v_hash:=public.gf020_hash(p_project_id::text||'|'||p_cohort_id::text||'|'||p_feed_item_id::text||'|'||coalesce(p_quantity::text,'')||'|'||v_unit||'|'||coalesce(p_effective_at::text,'')||'|'||coalesce(p_feeding_period_start::text,'')||'|'||coalesce(p_feeding_period_end::text,'')||'|'||trim(coalesce(p_issued_by_name,''))||'|'||coalesce(trim(p_evidence_reference),'')||'|'||coalesce(trim(p_notes),''));
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':gf023-feed-issue:'||trim(p_idempotency_key),0));
  select * into v_row from public.livestock_feed_issues where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then if v_row.request_hash<>v_hash then raise exception 'idempotency key payload mismatch'; end if; return v_row.id; end if;
  perform public.gf020_require_project(p_organization_id,p_project_id);
  if p_quantity is null or p_quantity<=0 then raise exception 'invalid livestock feed quantity'; end if;
  if char_length(trim(coalesce(p_issued_by_name,''))) not between 2 and 160 then raise exception 'invalid livestock feed issue actor'; end if;
  insert into public.livestock_feed_issues(organization_id,project_id,cohort_id,feed_item_id,quantity,unit,effective_at,feeding_period_start,feeding_period_end,issued_by_name,evidence_reference,notes,recorded_by,idempotency_key,request_hash)
  values(p_organization_id,p_project_id,p_cohort_id,p_feed_item_id,p_quantity,v_unit,p_effective_at,p_feeding_period_start,p_feeding_period_end,trim(p_issued_by_name),nullif(trim(p_evidence_reference),''),nullif(trim(p_notes),''),v_actor,trim(p_idempotency_key),v_hash) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'LIVESTOCK_FEED_ISSUE_RECORDED','livestock_feed_issue',v_id,jsonb_build_object('project_id',p_project_id,'cohort_id',p_cohort_id,'feed_item_id',p_feed_item_id,'quantity',p_quantity,'unit',v_unit));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Operator-safe read models. UUIDs remain machine keys, never labels.
-- ---------------------------------------------------------------------------

create view public.livestock_medicine_products_read with (security_invoker=on) as
select id,organization_id,project_id,product_reference,name,product_kind,
       active_ingredient,default_withdrawal_days,notes,created_by,created_at
from public.livestock_medicine_products;

create view public.livestock_animals_read with (security_invoker=on) as
select a.id,a.organization_id,a.project_id,a.identification_cohort_id as cohort_id,
       c.cohort_reference,a.identifier_type,a.identifier_value,a.sex,a.birth_date,
       a.breed_descriptor,a.identified_at,a.evidence_reference,a.notes,
       a.identified_by,a.recorded_at,
       'IDENTIFIED'::text as identity_status,
       0::integer as identification_quantity_effect
from public.livestock_animals a
join public.livestock_cohorts c
  on (c.id,c.organization_id,c.project_id)=(a.identification_cohort_id,a.organization_id,a.project_id);

create view public.livestock_health_events_read with (security_invoker=on) as
select e.id,e.organization_id,e.project_id,e.cohort_id,c.cohort_reference,
       e.animal_id,a.identifier_value as animal_identifier,
       e.event_type,e.condition_classification,e.condition_name,
       e.medicine_product_id,p.product_reference,p.name as product_name,
       e.dose_quantity::text as dose_quantity,e.dose_unit,e.administration_route,
       e.effective_at,e.practitioner_name,e.withdrawal_period_days,e.withdrawal_ends_at,
       case
         when e.withdrawal_period_days is null or e.withdrawal_period_days=0 then 'NONE'
         when e.withdrawal_ends_at > current_timestamp then 'ACTIVE'
         else 'ENDED'
       end as withdrawal_status,
       e.evidence_reference,e.notes,e.recorded_by,e.recorded_at
from public.livestock_health_events e
join public.livestock_cohorts c
  on (c.id,c.organization_id,c.project_id)=(e.cohort_id,e.organization_id,e.project_id)
left join public.livestock_animals a
  on (a.id,a.organization_id,a.project_id)=(e.animal_id,e.organization_id,e.project_id)
left join public.livestock_medicine_products p
  on (p.id,p.organization_id,p.project_id)=(e.medicine_product_id,e.organization_id,e.project_id);

create view public.livestock_active_withdrawals with (security_invoker=on) as
select * from public.livestock_health_events_read
where withdrawal_status='ACTIVE';

create view public.livestock_reproduction_events_read with (security_invoker=on) as
select e.id,e.organization_id,e.project_id,e.cohort_id,c.cohort_reference,
       e.subject_animal_id,sa.identifier_value as subject_animal_identifier,
       e.event_type,e.subject_count,e.service_method,e.pregnancy_status,
       e.expected_birth_date,e.observed_live_birth_count,e.stillbirth_count,
       e.birth_quantity_effect,e.birth_quantity_event_id,
       (e.birth_quantity_effect='GF022_BIRTH') as affects_authoritative_quantity,
       e.weaned_count,e.dam_animal_id,da.identifier_value as dam_identifier,
       e.sire_animal_id,si.identifier_value as sire_identifier,
       e.effective_at,e.performed_by_name,e.evidence_reference,e.notes,
       e.recorded_by,e.recorded_at
from public.livestock_reproduction_events e
join public.livestock_cohorts c
  on (c.id,c.organization_id,c.project_id)=(e.cohort_id,e.organization_id,e.project_id)
left join public.livestock_animals sa
  on (sa.id,sa.organization_id,sa.project_id)=(e.subject_animal_id,e.organization_id,e.project_id)
left join public.livestock_animals da
  on (da.id,da.organization_id,da.project_id)=(e.dam_animal_id,e.organization_id,e.project_id)
left join public.livestock_animals si
  on (si.id,si.organization_id,si.project_id)=(e.sire_animal_id,e.organization_id,e.project_id);

create view public.livestock_feed_items_read with (security_invoker=on) as
select id,organization_id,project_id,item_reference,name,feed_category,issue_unit,
       notes,created_by,created_at
from public.livestock_feed_items;

create view public.livestock_feed_issues_read with (security_invoker=on) as
select i.id,i.organization_id,i.project_id,i.cohort_id,c.cohort_reference,
       i.feed_item_id,f.item_reference,f.name as feed_item_name,f.feed_category,
       i.quantity::text as quantity,i.unit,i.effective_at,
       i.feeding_period_start,i.feeding_period_end,i.issued_by_name,
       i.evidence_reference,i.notes,i.recorded_by,i.recorded_at
from public.livestock_feed_issues i
join public.livestock_cohorts c
  on (c.id,c.organization_id,c.project_id)=(i.cohort_id,i.organization_id,i.project_id)
join public.livestock_feed_items f
  on (f.id,f.organization_id,f.project_id)=(i.feed_item_id,i.organization_id,i.project_id);

-- FCR is available only from two consecutive evidenced COHORT_TOTAL weights,
-- evidenced KG feed, positive gain, and no quantity event in the interval.
-- Every other case returns a reason code and NULL, never a fabricated ratio.
create view public.livestock_feed_conversion_metrics with (security_invoker=on) as
with ranked_weights as (
  select w.*,
         row_number() over(partition by w.cohort_id order by w.effective_at desc,w.recorded_at desc,w.id desc) rn
  from public.livestock_weight_events w
  where w.effective_at <= current_timestamp
), windows as (
  select c.id cohort_id,c.organization_id,c.project_id,c.cohort_reference,
         (max(w.id::text) filter(where w.rn=1))::uuid latest_weight_event_id,
         max(w.effective_at) filter(where w.rn=1) latest_weight_at,
         max(w.method) filter(where w.rn=1) latest_method,
         max(w.weight_value) filter(where w.rn=1) latest_weight,
         max(w.evidence_reference) filter(where w.rn=1) latest_evidence,
         (max(w.id::text) filter(where w.rn=2))::uuid previous_weight_event_id,
         max(w.effective_at) filter(where w.rn=2) previous_weight_at,
         max(w.method) filter(where w.rn=2) previous_method,
         max(w.weight_value) filter(where w.rn=2) previous_weight,
         max(w.evidence_reference) filter(where w.rn=2) previous_evidence
  from public.livestock_cohorts c
  left join ranked_weights w on w.cohort_id=c.id and w.rn<=2
  group by c.id,c.organization_id,c.project_id,c.cohort_reference
), evidence as (
  select x.*,
         coalesce(f.feed_count,0) feed_issue_count,
         f.feed_kg,
         coalesce(f.non_kg_count,0) non_kg_count,
         coalesce(f.missing_evidence_count,0) missing_feed_evidence_count,
         exists(select 1 from public.livestock_quantity_events q
                where q.cohort_id=x.cohort_id
                  and q.effective_at>x.previous_weight_at
                  and q.effective_at<=x.latest_weight_at) population_changed
  from windows x
  left join lateral (
    select count(*) feed_count,
           sum(i.quantity) filter(where i.unit='KG') feed_kg,
           count(*) filter(where i.unit<>'KG') non_kg_count,
           count(*) filter(where i.evidence_reference is null) missing_evidence_count
      from public.livestock_feed_issues i
     where i.cohort_id=x.cohort_id
       and i.effective_at>x.previous_weight_at
       and i.effective_at<=x.latest_weight_at
  ) f on x.previous_weight_at is not null
), classified as (
  select e.*,
    case
      when previous_weight_event_id is null then 'INSUFFICIENT_WEIGHT_EVENTS'
      when latest_method<>'COHORT_TOTAL' or previous_method<>'COHORT_TOTAL' then 'INCOMPARABLE_WEIGHT_BASIS'
      when latest_evidence is null or previous_evidence is null then 'INSUFFICIENT_EVIDENCE'
      when population_changed then 'POPULATION_CHANGED'
      when feed_issue_count=0 then 'NO_FEED_EVIDENCE'
      when non_kg_count>0 then 'INCOMPARABLE_FEED_UNIT'
      when missing_feed_evidence_count>0 then 'INSUFFICIENT_EVIDENCE'
      when latest_weight<=previous_weight then 'NO_POSITIVE_WEIGHT_GAIN'
      else 'AVAILABLE'
    end metric_status
  from evidence e
)
select cohort_id,organization_id,project_id,cohort_reference,
       previous_weight_event_id,previous_weight_at,latest_weight_event_id,latest_weight_at,
       case when metric_status='AVAILABLE' then feed_kg::text else null end feed_quantity_kg,
       case when metric_status='AVAILABLE' then (latest_weight-previous_weight)::text else null end weight_gain_kg,
       case when metric_status='AVAILABLE' then round(feed_kg/(latest_weight-previous_weight),4)::text else null end fcr,
       metric_status
from classified;

-- ---------------------------------------------------------------------------
-- 5. Default-deny RLS and least-privilege grants.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'livestock_medicine_products','livestock_animals','livestock_animal_memberships',
    'livestock_health_events','livestock_reproduction_events',
    'livestock_feed_items','livestock_feed_issues'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',t||'_read',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

revoke all on
  public.livestock_medicine_products_read,public.livestock_animals_read,
  public.livestock_health_events_read,public.livestock_active_withdrawals,
  public.livestock_reproduction_events_read,public.livestock_feed_items_read,
  public.livestock_feed_issues_read,public.livestock_feed_conversion_metrics
from public,anon;
grant select on
  public.livestock_medicine_products_read,public.livestock_animals_read,
  public.livestock_health_events_read,public.livestock_active_withdrawals,
  public.livestock_reproduction_events_read,public.livestock_feed_items_read,
  public.livestock_feed_issues_read,public.livestock_feed_conversion_metrics
 to authenticated;

revoke all on function
  public.gf023_normalize_identifier(text),public.gf023_require_idempotency_key(text),
  public.gf023_validate_operational_target(uuid,uuid,uuid,uuid,timestamptz,boolean),
  public.gf023_validate_animal(),public.gf023_validate_animal_membership(),
  public.gf023_validate_animal_membership_shape(),public.gf023_validate_health_event(),
  public.gf023_validate_reproduction_event(),public.gf023_validate_feed_issue()
from public,anon,authenticated;

revoke all on function
  public.create_livestock_medicine_product(uuid,uuid,text,text,text,text,integer,text,text),
  public.identify_livestock_animal(uuid,uuid,uuid,text,text,text,date,text,timestamptz,text,text,text),
  public.record_livestock_health_event(uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,text,text,timestamptz,text,text,text,text),
  public.record_livestock_reproduction_event(uuid,uuid,uuid,uuid,text,integer,text,text,date,integer,integer,text,integer,uuid,uuid,timestamptz,text,text,text,text),
  public.create_livestock_feed_item(uuid,uuid,text,text,text,text,text,text),
  public.record_livestock_feed_issue(uuid,uuid,uuid,uuid,numeric,text,timestamptz,date,date,text,text,text,text)
from public,anon;
grant execute on function
  public.create_livestock_medicine_product(uuid,uuid,text,text,text,text,integer,text,text),
  public.identify_livestock_animal(uuid,uuid,uuid,text,text,text,date,text,timestamptz,text,text,text),
  public.record_livestock_health_event(uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,text,text,timestamptz,text,text,text,text),
  public.record_livestock_reproduction_event(uuid,uuid,uuid,uuid,text,integer,text,text,date,integer,integer,text,integer,uuid,uuid,timestamptz,text,text,text,text),
  public.create_livestock_feed_item(uuid,uuid,text,text,text,text,text,text),
  public.record_livestock_feed_issue(uuid,uuid,uuid,uuid,numeric,text,timestamptz,date,date,text,text,text,text)
 to authenticated;

comment on table public.livestock_animals is
  'Optional identity only. A Cohort never requires one Animal row per head and identification changes quantity by zero.';
comment on view public.livestock_active_withdrawals is
  'Operational withdrawal facts only; no sale-blocking or commercial decision is implemented by GF-023.';
comment on view public.livestock_feed_conversion_metrics is
  'Evidence-aware FCR. NULL plus metric_status is authoritative whenever numerator/denominator evidence is insufficient.';
