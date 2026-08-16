-- F6 — Currency & Tax Contract.
--
-- Currency: exact-money, deterministic conversion only. A conversion is a
-- recorded fact: an explicit rate snapshot (rational numerator/denominator
-- captured from a stated source on a stated date) plus an append-only
-- conversion log row. Nothing is ever converted implicitly, and no rate is
-- ever invented — read models that need a cross-currency number show
-- NULL + an explicit 'NO_RATE_SNAPSHOT' state when no snapshot exists.
--
-- Tax: an explicit treatment contract registry, not a calculation engine.
-- Terranex records WHO computes each tax (external assessor / not recorded
-- / deferred pending professional advisory) and never posts a computed tax
-- number that the organization has not explicitly declared (BD-010 safe).

-- ===========================================================================
-- 1. Exact rational FX rate snapshots
-- ===========================================================================
create table public.fx_rate_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  base_currency text not null check (base_currency ~ '^[A-Z]{3}$'),
  quote_currency text not null check (quote_currency ~ '^[A-Z]{3}$'),
  rate_numerator bigint not null check (rate_numerator > 0),
  rate_denominator bigint not null check (rate_denominator > 0),
  rate_date date not null,
  rate_source text not null check (rate_source in (
    'EXTERNAL_PROVIDER_STATEMENT','MANUAL_ENTRY'
  )),
  provider_reference text
    check (provider_reference is null or char_length(trim(provider_reference)) between 1 and 200),
  captured_by uuid not null references auth.users(id) on delete restrict,
  captured_at timestamptz not null default now(),
  notes text check (notes is null or char_length(trim(notes)) between 3 and 1000),
  unique (id, organization_id),
  unique (organization_id, base_currency, quote_currency, rate_date),
  check (base_currency <> quote_currency)
);
create index fx_rate_snapshots_pair_date_idx
  on public.fx_rate_snapshots(organization_id, base_currency, quote_currency, rate_date desc);

create or replace function public.f6_guard_fx_snapshot_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'an FX rate snapshot is an immutable captured fact';
end $$;
drop trigger if exists fx_rate_snapshots_immutable on public.fx_rate_snapshots;
create trigger fx_rate_snapshots_immutable
before update or delete on public.fx_rate_snapshots
for each row execute function public.f6_guard_fx_snapshot_immutable();

-- Deterministic exact conversion with half-up rounding:
--   amount * numerator + denominator/2  (integer arithmetic, never floats)
create or replace function public.fx_convert_exact(
  p_amount_minor_units bigint,
  p_rate_numerator bigint,
  p_rate_denominator bigint
) returns bigint language plpgsql immutable set search_path=pg_catalog,public as $$
begin
  if p_amount_minor_units is null or p_amount_minor_units < 0 then
    raise exception 'conversion amount cannot be negative';
  end if;
  if p_amount_minor_units = 0 then
    return 0;
  end if;
  if p_rate_numerator is null or p_rate_numerator <= 0
     or p_rate_denominator is null or p_rate_denominator <= 0 then
    raise exception 'conversion rate must be a positive rational';
  end if;
  return (p_amount_minor_units * p_rate_numerator + p_rate_denominator / 2)
         / p_rate_denominator;
end $$;

create or replace function public.f6_record_fx_rate_snapshot(
  p_organization_id uuid,
  p_base_currency text,
  p_quote_currency text,
  p_rate_numerator bigint,
  p_rate_denominator bigint,
  p_rate_date date,
  p_rate_source text,
  p_provider_reference text,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_base_currency is null or p_base_currency !~ '^[A-Z]{3}$'
     or p_quote_currency is null or p_quote_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid snapshot currencies';
  end if;
  if p_base_currency = p_quote_currency then
    raise exception 'a snapshot requires two different currencies';
  end if;
  if p_rate_numerator is null or p_rate_numerator <= 0
     or p_rate_denominator is null or p_rate_denominator <= 0 then
    raise exception 'snapshot rate must be a positive rational';
  end if;
  if p_rate_date is null then raise exception 'snapshot date required'; end if;
  if p_rate_source not in ('EXTERNAL_PROVIDER_STATEMENT','MANUAL_ENTRY') then
    raise exception 'snapshot source must be EXTERNAL_PROVIDER_STATEMENT or MANUAL_ENTRY';
  end if;

  select encode(digest(p_base_currency || '|' || p_quote_currency || '|'
    || p_rate_numerator::text || '|' || p_rate_denominator::text || '|'
    || p_rate_date::text || '|' || p_rate_source || '|'
    || coalesce(nullif(trim(p_provider_reference), ''), ''), 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f6-fx-snapshot:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.fx_rate_snapshots
  where organization_id = p_organization_id
    and base_currency = p_base_currency and quote_currency = p_quote_currency
    and rate_date = p_rate_date;
  if found then
    if v_existing.rate_numerator <> p_rate_numerator
       or v_existing.rate_denominator <> p_rate_denominator then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.fx_rate_snapshots(
    organization_id, base_currency, quote_currency, rate_numerator,
    rate_denominator, rate_date, rate_source, provider_reference,
    captured_by, notes
  ) values (
    p_organization_id, p_base_currency, p_quote_currency, p_rate_numerator,
    p_rate_denominator, p_rate_date, p_rate_source,
    nullif(trim(p_provider_reference), ''), v_actor, nullif(trim(p_notes), '')
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'FX_RATE_SNAPSHOT_CAPTURED', 'fx_rate_snapshot', v_id,
          jsonb_build_object('base_currency', p_base_currency,
                             'quote_currency', p_quote_currency,
                             'rate_numerator', p_rate_numerator,
                             'rate_denominator', p_rate_denominator,
                             'rate_date', p_rate_date, 'rate_source', p_rate_source));
  return v_id;
end $$;

-- ===========================================================================
-- 2. Append-only conversion log
-- ===========================================================================
create table public.fx_conversion_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid references public.investment_projects(id) on delete restrict,
  source_amount_minor_units bigint not null check (source_amount_minor_units > 0),
  source_currency text not null check (source_currency ~ '^[A-Z]{3}$'),
  target_currency text not null check (target_currency ~ '^[A-Z]{3}$'),
  rate_snapshot_id uuid not null references public.fx_rate_snapshots(id) on delete restrict,
  converted_amount_minor_units bigint not null check (converted_amount_minor_units > 0),
  conversion_date date not null,
  purpose text not null check (purpose in ('REPORTING_ROLLUP','DISCLOSURE','RECONCILIATION')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  check (source_currency <> target_currency)
);
create index fx_conversion_log_project_idx
  on public.fx_conversion_log(project_id, conversion_date);

create or replace function public.f6_guard_fx_conversion_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'an FX conversion log row is an immutable recorded fact';
end $$;
drop trigger if exists fx_conversion_log_append_only on public.fx_conversion_log;
create trigger fx_conversion_log_append_only
before update or delete on public.fx_conversion_log
for each row execute function public.f6_guard_fx_conversion_append_only();

create or replace function public.f6_record_fx_conversion(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_amount_minor_units bigint,
  p_source_currency text,
  p_target_currency text,
  p_rate_snapshot_id uuid,
  p_conversion_date date,
  p_purpose text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text; v_existing record; v_id uuid;
  v_snapshot public.fx_rate_snapshots%rowtype;
  v_converted bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_source_amount_minor_units is null or p_source_amount_minor_units <= 0 then
    raise exception 'conversion amount must be positive';
  end if;
  if p_source_currency is null or p_source_currency !~ '^[A-Z]{3}$'
     or p_target_currency is null or p_target_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid conversion currencies';
  end if;
  if p_source_currency = p_target_currency then
    raise exception 'conversion requires two different currencies';
  end if;
  if p_conversion_date is null then raise exception 'conversion date required'; end if;
  if p_purpose not in ('REPORTING_ROLLUP','DISCLOSURE','RECONCILIATION') then
    raise exception 'purpose must be REPORTING_ROLLUP, DISCLOSURE or RECONCILIATION';
  end if;
  if p_project_id is not null and not exists (
    select 1 from public.investment_projects
    where id = p_project_id and organization_id = p_organization_id
  ) then raise exception 'project not found'; end if;

  select * into v_snapshot from public.fx_rate_snapshots
  where id = p_rate_snapshot_id and organization_id = p_organization_id;
  if not found then raise exception 'rate snapshot not found'; end if;
  if v_snapshot.base_currency <> p_source_currency
     or v_snapshot.quote_currency <> p_target_currency then
    raise exception 'rate snapshot currencies do not match the conversion';
  end if;
  if v_snapshot.rate_date > p_conversion_date then
    raise exception 'rate snapshot date cannot be after the conversion date';
  end if;
  v_converted := public.fx_convert_exact(
    p_source_amount_minor_units, v_snapshot.rate_numerator, v_snapshot.rate_denominator);

  select encode(digest(coalesce(p_project_id::text, '') || '|'
    || p_source_amount_minor_units::text || '|' || p_source_currency || '|'
    || p_target_currency || '|' || p_rate_snapshot_id::text || '|'
    || p_conversion_date::text || '|' || p_purpose, 'sha256'), 'hex')
    into v_hash;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f6-fx-conversion:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.fx_conversion_log
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  insert into public.fx_conversion_log(
    organization_id, project_id, source_amount_minor_units, source_currency,
    target_currency, rate_snapshot_id, converted_amount_minor_units,
    conversion_date, purpose, recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_source_amount_minor_units,
    p_source_currency, p_target_currency, p_rate_snapshot_id, v_converted,
    p_conversion_date, p_purpose, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'FX_CONVERSION_RECORDED', 'fx_conversion_log', v_id,
          jsonb_build_object('source_amount_minor_units', p_source_amount_minor_units,
                             'source_currency', p_source_currency,
                             'target_currency', p_target_currency,
                             'converted_amount_minor_units', v_converted,
                             'rate_snapshot_id', p_rate_snapshot_id));
  return v_id;
end $$;

-- ===========================================================================
-- 3. Organization reporting currency (explicit consolidation basis)
-- ===========================================================================
alter table public.organizations
  add column reporting_currency text
    check (reporting_currency is null or reporting_currency ~ '^[A-Z]{3}$');

create or replace function public.f6_set_org_reporting_currency(
  p_organization_id uuid,
  p_reporting_currency text,
  p_idempotency_key text
) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_reporting_currency is not null
     and nullif(trim(p_reporting_currency), '') is not null
     and p_reporting_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid reporting currency';
  end if;
  update public.organizations
     set reporting_currency = nullif(trim(p_reporting_currency), '')
   where id = p_organization_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'ORG_REPORTING_CURRENCY_SET', 'organization',
          p_organization_id, jsonb_build_object('reporting_currency',
            nullif(trim(p_reporting_currency), '')));
end $$;

-- ===========================================================================
-- 4. Tax treatment contract registry (explicit; no calculation engine)
-- ===========================================================================
create table public.tax_registry (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_domain text not null check (tax_domain in (
    'VALUE_ADDED','INCOME','WITHHOLDING','PROPERTY','PAYROLL','OTHER_DECLARED'
  )),
  tax_name text not null check (char_length(trim(tax_name)) between 2 and 160),
  applies_to text not null check (applies_to in (
    'SALES_REVENUE','PROCUREMENT_SPEND','INVESTOR_DISTRIBUTIONS',
    'PROJECT_INCOME','ASSET_TRANSFERS'
  )),
  treatment_status text not null check (treatment_status in (
    'ASSESSED_EXTERNALLY_AND_RECORDED',
    'ASSESSED_EXTERNALLY_NOT_RECORDED',
    'DEFERRED_PENDING_TAX_ADVISORY'
  )),
  authority text check (authority is null or char_length(trim(authority)) between 2 and 200),
  effective_from date not null default current_date,
  effective_to date,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  notes text not null check (char_length(trim(notes)) between 3 and 1000),
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, tax_domain, tax_name),
  check (effective_to is null or effective_to >= effective_from)
);
create index tax_registry_org_status_idx on public.tax_registry(organization_id, status);

create or replace function public.f6_register_tax_treatment(
  p_organization_id uuid,
  p_tax_domain text,
  p_tax_name text,
  p_applies_to text,
  p_treatment_status text,
  p_authority text,
  p_effective_from date,
  p_effective_to date,
  p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  if p_tax_domain not in (
    'VALUE_ADDED','INCOME','WITHHOLDING','PROPERTY','PAYROLL','OTHER_DECLARED'
  ) then raise exception 'unknown tax domain'; end if;
  if p_tax_name is null or char_length(trim(p_tax_name)) not between 2 and 160 then
    raise exception 'tax name must be 2-160 characters';
  end if;
  if p_applies_to not in (
    'SALES_REVENUE','PROCUREMENT_SPEND','INVESTOR_DISTRIBUTIONS',
    'PROJECT_INCOME','ASSET_TRANSFERS'
  ) then raise exception 'unknown tax application scope'; end if;
  if p_treatment_status not in (
    'ASSESSED_EXTERNALLY_AND_RECORDED',
    'ASSESSED_EXTERNALLY_NOT_RECORDED',
    'DEFERRED_PENDING_TAX_ADVISORY'
  ) then raise exception 'unknown tax treatment status'; end if;
  if p_notes is null or char_length(trim(p_notes)) not between 3 and 1000 then
    raise exception 'treatment notes must be 3-1000 characters';
  end if;
  if p_effective_to is not null and p_effective_from is not null
     and p_effective_to < p_effective_from then
    raise exception 'effective_to cannot precede effective_from';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':f6-tax:' || trim(p_idempotency_key), 0));
  insert into public.tax_registry(
    organization_id, tax_domain, tax_name, applies_to, treatment_status,
    authority, effective_from, effective_to, notes, updated_by
  ) values (
    p_organization_id, p_tax_domain, trim(p_tax_name), p_applies_to,
    p_treatment_status, nullif(trim(p_authority), ''),
    coalesce(p_effective_from, current_date), p_effective_to,
    trim(p_notes), v_actor
  )
  on conflict (organization_id, tax_domain, tax_name)
  do update set
    applies_to = excluded.applies_to,
    treatment_status = excluded.treatment_status,
    authority = excluded.authority,
    effective_from = excluded.effective_from,
    effective_to = excluded.effective_to,
    notes = excluded.notes,
    status = 'ACTIVE',
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'TAX_TREATMENT_REGISTERED', 'tax_registry', v_id,
          jsonb_build_object('tax_domain', p_tax_domain, 'tax_name', trim(p_tax_name),
                             'treatment_status', p_treatment_status));
  return v_id;
end $$;

create or replace function public.f6_deactivate_tax_treatment(
  p_organization_id uuid,
  p_tax_registry_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'idempotency key must be 8-120 characters';
  end if;
  update public.tax_registry
     set status = 'INACTIVE', updated_by = v_actor, updated_at = now()
   where id = p_tax_registry_id and organization_id = p_organization_id;
  if not found then raise exception 'tax treatment not found'; end if;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'TAX_TREATMENT_DEACTIVATED', 'tax_registry', p_tax_registry_id,
          jsonb_build_object('status', 'INACTIVE'));
  return p_tax_registry_id;
end $$;

-- ===========================================================================
-- 5. Read models
-- ===========================================================================
create or replace view public.fx_rate_snapshots_read with (security_invoker=on) as
select
  s.id as snapshot_id,
  s.organization_id,
  s.base_currency,
  s.quote_currency,
  s.rate_numerator::text as rate_numerator,
  s.rate_denominator::text as rate_denominator,
  s.rate_date,
  s.rate_source,
  s.provider_reference,
  s.captured_by,
  s.captured_at,
  s.notes
from public.fx_rate_snapshots s;

create or replace view public.fx_conversion_log_read with (security_invoker=on) as
select
  c.id as conversion_id,
  c.organization_id,
  c.project_id,
  c.source_amount_minor_units::text as source_amount_minor_units,
  c.source_currency,
  c.target_currency,
  c.rate_snapshot_id,
  c.converted_amount_minor_units::text as converted_amount_minor_units,
  c.conversion_date,
  c.purpose,
  c.recorded_by,
  c.recorded_at,
  s.rate_numerator::text as rate_numerator,
  s.rate_denominator::text as rate_denominator,
  s.rate_date as snapshot_rate_date,
  s.rate_source
from public.fx_conversion_log c
join public.fx_rate_snapshots s on s.id = c.rate_snapshot_id;

create or replace view public.tax_registry_read with (security_invoker=on) as
select
  t.id as tax_registry_id,
  t.organization_id,
  t.tax_domain,
  t.tax_name,
  t.applies_to,
  t.treatment_status,
  t.authority,
  t.effective_from,
  t.effective_to,
  t.status,
  t.notes,
  t.updated_by,
  t.updated_at
from public.tax_registry t;

-- ===========================================================================
-- 6. RLS / privileges
-- ===========================================================================
alter table public.fx_rate_snapshots enable row level security;
alter table public.fx_rate_snapshots force row level security;
alter table public.fx_conversion_log enable row level security;
alter table public.fx_conversion_log force row level security;
alter table public.tax_registry enable row level security;
alter table public.tax_registry force row level security;

create policy fx_rate_snapshots_read on public.fx_rate_snapshots for select to authenticated
  using (public.is_active_member(organization_id));
create policy fx_conversion_log_read on public.fx_conversion_log for select to authenticated
  using (public.is_active_member(organization_id));
create policy tax_registry_read on public.tax_registry for select to authenticated
  using (public.is_active_member(organization_id));

revoke all on public.fx_rate_snapshots, public.fx_conversion_log, public.tax_registry
  from public, anon, authenticated;
grant select on public.fx_rate_snapshots, public.fx_conversion_log, public.tax_registry
  to authenticated;
grant select on public.fx_rate_snapshots_read, public.fx_conversion_log_read,
  public.tax_registry_read to authenticated;
grant execute on function public.fx_convert_exact(bigint,bigint,bigint) to authenticated;

revoke all on function public.f6_record_fx_rate_snapshot(uuid,text,text,bigint,bigint,date,text,text,text,text) from public, anon;
revoke all on function public.f6_record_fx_conversion(uuid,uuid,bigint,text,text,uuid,date,text,text) from public, anon;
revoke all on function public.f6_set_org_reporting_currency(uuid,text,text) from public, anon;
revoke all on function public.f6_register_tax_treatment(uuid,text,text,text,text,text,date,date,text,text) from public, anon;
revoke all on function public.f6_deactivate_tax_treatment(uuid,uuid,text) from public, anon;

grant execute on function public.f6_record_fx_rate_snapshot(uuid,text,text,bigint,bigint,date,text,text,text,text) to authenticated;
grant execute on function public.f6_record_fx_conversion(uuid,uuid,bigint,text,text,uuid,date,text,text) to authenticated;
grant execute on function public.f6_set_org_reporting_currency(uuid,text,text) to authenticated;
grant execute on function public.f6_register_tax_treatment(uuid,text,text,text,text,text,date,date,text,text) to authenticated;
grant execute on function public.f6_deactivate_tax_treatment(uuid,uuid,text) to authenticated;
