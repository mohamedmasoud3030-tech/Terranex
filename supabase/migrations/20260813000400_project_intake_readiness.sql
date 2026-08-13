-- Guided real-project intake readiness.
--
-- This is NOT a second workflow engine and NOT a second ledger. S0–S7 remain
-- the only path that creates parties, agreements, cash, property, journals, or
-- opening postings. These tables store operator declarations that the intake
-- contract requires and that no existing command currently holds:
--   * freeze date (control pack §2)
--   * signed control totals before S7 staging (control pack §4)
--   * agreement title/reference (DS-04; S1 stores effective date + commitments)
--   * organization / project evidence references (DS-01 / DS-02)
--   * conditional-section applicability (DS-06/07/10/12/13/14/15/16)
--   * genuine modelling gaps for unmappable balances (DS-09 / ADR 0009 §1)
--   * DS-17 evidence-register identifiers (never document blobs)
--
-- None of these rows post a journal line. Browser roles never write the tables.

-- ===========================================================================
-- 1. Tables
-- ===========================================================================
create table public.project_intake_declarations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  freeze_date date,
  freeze_evidence_reference text
    check (freeze_evidence_reference is null
      or char_length(trim(freeze_evidence_reference)) between 3 and 200),
  freeze_recorded_by uuid references auth.users(id) on delete restrict,
  freeze_recorded_at timestamptz,
  declared_debit_total_minor_units bigint
    check (declared_debit_total_minor_units is null or declared_debit_total_minor_units >= 0),
  declared_credit_total_minor_units bigint
    check (declared_credit_total_minor_units is null or declared_credit_total_minor_units >= 0),
  control_totals_evidence_reference text
    check (control_totals_evidence_reference is null
      or char_length(trim(control_totals_evidence_reference)) between 3 and 200),
  control_totals_declared_by uuid references auth.users(id) on delete restrict,
  control_totals_declared_at timestamptz,
  agreement_title_or_reference text
    check (agreement_title_or_reference is null
      or char_length(trim(agreement_title_or_reference)) between 2 and 160),
  organization_evidence_reference text
    check (organization_evidence_reference is null
      or char_length(trim(organization_evidence_reference)) between 3 and 200),
  project_evidence_reference text
    check (project_evidence_reference is null
      or char_length(trim(project_evidence_reference)) between 3 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_intake_declarations_one_per_project unique (project_id),
  unique (id, organization_id),
  unique (project_id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint project_intake_declarations_freeze_complete check (
    (freeze_date is null) = (freeze_evidence_reference is null)
    and (freeze_date is null) = (freeze_recorded_by is null)
    and (freeze_date is null) = (freeze_recorded_at is null)
  ),
  constraint project_intake_declarations_totals_complete check (
    (declared_debit_total_minor_units is null) = (declared_credit_total_minor_units is null)
    and (declared_debit_total_minor_units is null) = (control_totals_evidence_reference is null)
    and (declared_debit_total_minor_units is null) = (control_totals_declared_by is null)
    and (declared_debit_total_minor_units is null) = (control_totals_declared_at is null)
  ),
  constraint project_intake_declarations_totals_balanced check (
    declared_debit_total_minor_units is null
    or declared_debit_total_minor_units = declared_credit_total_minor_units
  )
);

create table public.project_intake_section_applicability (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  section_code text not null check (section_code in (
    'HISTORICAL_CALLS',
    'HISTORICAL_CONTRIBUTIONS',
    'ACQUISITION_BASIS',
    'DEVELOPMENT_BASELINE',
    'UNPAID_SUPPLIERS',
    'SALES_DISPOSITIONS',
    'HISTORICAL_DISTRIBUTIONS',
    'BANK_STATEMENTS'
  )),
  applicable boolean not null,
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  evidence_reference text
    check (evidence_reference is null
      or char_length(trim(evidence_reference)) between 3 and 200),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  unique (project_id, section_code),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

create table public.project_intake_modelling_gaps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  source_reference text not null check (char_length(trim(source_reference)) between 3 and 200),
  description text not null check (char_length(trim(description)) between 3 and 500),
  amount_minor_units bigint check (amount_minor_units is null or amount_minor_units > 0),
  currency text not null default 'EGP' check (currency = 'EGP'),
  why_unmappable text not null check (char_length(trim(why_unmappable)) between 3 and 1000),
  status text not null default 'OPEN' check (status in ('OPEN','COMMERCIALLY_ACCEPTED')),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  resolution_evidence_reference text
    check (resolution_evidence_reference is null
      or char_length(trim(resolution_evidence_reference)) between 3 and 200),
  unique (project_id, source_reference),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  constraint project_intake_modelling_gaps_resolution_check check (
    (status = 'OPEN' and resolved_by is null and resolved_at is null
      and resolution_evidence_reference is null)
    or (status = 'COMMERCIALLY_ACCEPTED' and resolved_by is not null
      and resolved_at is not null and resolution_evidence_reference is not null)
  )
);

create table public.project_intake_evidence_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  evidence_identifier text not null check (char_length(trim(evidence_identifier)) between 3 and 200),
  linked_fact text not null check (char_length(trim(linked_fact)) between 3 and 200),
  customer_storage_location text not null check (char_length(trim(customer_storage_location)) between 3 and 300),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  unique (organization_id, evidence_identifier),
  unique (id, organization_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);

create index project_intake_declarations_org_idx
  on public.project_intake_declarations(organization_id);
create index project_intake_section_applicability_project_idx
  on public.project_intake_section_applicability(project_id);
create index project_intake_modelling_gaps_project_idx
  on public.project_intake_modelling_gaps(project_id, status);
create index project_intake_evidence_items_project_idx
  on public.project_intake_evidence_items(project_id);

-- ===========================================================================
-- 2. Immutability: no deletes; freeze date is set-once; gaps are append-only
--    except the documented commercial-acceptance transition.
-- ===========================================================================
create or replace function public.intake_guard_append_only() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'intake declarations are append-only operator facts';
end $$;

create trigger project_intake_declarations_no_delete
  before delete on public.project_intake_declarations
  for each row execute function public.intake_guard_append_only();
create trigger project_intake_section_applicability_no_delete
  before delete on public.project_intake_section_applicability
  for each row execute function public.intake_guard_append_only();
create trigger project_intake_modelling_gaps_no_delete
  before delete on public.project_intake_modelling_gaps
  for each row execute function public.intake_guard_append_only();
create trigger project_intake_evidence_items_no_delete
  before delete on public.project_intake_evidence_items
  for each row execute function public.intake_guard_append_only();

create or replace function public.intake_guard_declaration_update() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  if old.organization_id <> new.organization_id or old.project_id <> new.project_id then
    raise exception 'intake declaration tenant scope is immutable';
  end if;
  if old.freeze_date is not null
     and (new.freeze_date is distinct from old.freeze_date
       or new.freeze_evidence_reference is distinct from old.freeze_evidence_reference
       or new.freeze_recorded_by is distinct from old.freeze_recorded_by
       or new.freeze_recorded_at is distinct from old.freeze_recorded_at) then
    raise exception 'freeze date is set-once; a later extract is a new dated record, not a rewrite';
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger project_intake_declarations_update_guard
  before update on public.project_intake_declarations
  for each row execute function public.intake_guard_declaration_update();

create or replace function public.intake_guard_modelling_gap_update() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  if old.organization_id <> new.organization_id
     or old.project_id <> new.project_id
     or old.source_reference <> new.source_reference
     or old.description <> new.description
     or old.amount_minor_units is distinct from new.amount_minor_units
     or old.currency <> new.currency
     or old.why_unmappable <> new.why_unmappable
     or old.recorded_by <> new.recorded_by
     or old.recorded_at <> new.recorded_at then
    raise exception 'a modelling gap cannot be rewritten; commercially accept it or leave it open';
  end if;
  if old.status = 'COMMERCIALLY_ACCEPTED' then
    raise exception 'a commercially accepted modelling gap is immutable';
  end if;
  if new.status <> 'COMMERCIALLY_ACCEPTED' then
    raise exception 'the only permitted modelling-gap transition is OPEN -> COMMERCIALLY_ACCEPTED';
  end if;
  return new;
end $$;

create trigger project_intake_modelling_gaps_update_guard
  before update on public.project_intake_modelling_gaps
  for each row execute function public.intake_guard_modelling_gap_update();

create or replace function public.intake_guard_evidence_item_immutable() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'evidence-register identifiers are append-only';
end $$;

create trigger project_intake_evidence_items_no_update
  before update on public.project_intake_evidence_items
  for each row execute function public.intake_guard_evidence_item_immutable();

-- ===========================================================================
-- 3. Helpers
-- ===========================================================================
create or replace function public.intake_require_project(
  p_organization_id uuid, p_project_id uuid
) returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not exists (
    select 1 from public.investment_projects
    where id = p_project_id and organization_id = p_organization_id
  ) then
    raise exception 'project not found';
  end if;
end $$;
revoke all on function public.intake_require_project(uuid, uuid) from public, anon, authenticated;

create or replace function public.intake_has_active_posted_opening(
  p_organization_id uuid, p_project_id uuid
) returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select exists (
    select 1
    from public.s7_opening_imports i
    where i.organization_id = p_organization_id
      and i.project_id = p_project_id
      and i.status = 'POSTED'
      and not exists (
        select 1 from public.journal_batches rb
        where rb.reversal_of_batch_id = i.journal_batch_id
      )
  )
$$;
revoke all on function public.intake_has_active_posted_opening(uuid, uuid) from public, anon, authenticated;

create or replace function public.intake_ensure_declaration(
  p_organization_id uuid, p_project_id uuid
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_id uuid;
begin
  insert into public.project_intake_declarations(organization_id, project_id)
  values (p_organization_id, p_project_id)
  on conflict (project_id) do update
    set updated_at = public.project_intake_declarations.updated_at
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.intake_ensure_declaration(uuid, uuid) from public, anon, authenticated;

create or replace function public.intake_require_safe_evidence(p_value text, p_label text)
returns text language plpgsql immutable set search_path = pg_catalog, public as $$
declare v_text text;
begin
  v_text := public.s7_normalize_text(p_value);
  if v_text is null
     or char_length(v_text) not between 3 and 200
     or public.s7_has_unsafe_control_characters(v_text) then
    raise exception '% is required (3-200 characters)', p_label;
  end if;
  return v_text;
end $$;
revoke all on function public.intake_require_safe_evidence(text, text) from public, anon, authenticated;

-- ===========================================================================
-- 4. Commands — OWNER only, never post journals
-- ===========================================================================
create or replace function public.intake_record_freeze_date(
  p_organization_id uuid,
  p_project_id uuid,
  p_freeze_date date,
  p_evidence_reference text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_existing date;
  v_evidence text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);
  if p_freeze_date is null then raise exception 'freeze date is required'; end if;
  v_evidence := public.intake_require_safe_evidence(p_evidence_reference, 'freeze evidence reference');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-freeze:' || p_project_id::text, 0));

  v_id := public.intake_ensure_declaration(p_organization_id, p_project_id);
  select freeze_date into v_existing
  from public.project_intake_declarations
  where id = v_id
  for update;

  if v_existing is not null then
    if v_existing = p_freeze_date then
      return v_id;
    end if;
    raise exception 'freeze date is set-once; a later extract is a new dated record, not a rewrite';
  end if;

  if public.intake_has_active_posted_opening(p_organization_id, p_project_id) then
    raise exception 'freeze date cannot change after a posted opening import';
  end if;

  update public.project_intake_declarations set
    freeze_date = p_freeze_date,
    freeze_evidence_reference = v_evidence,
    freeze_recorded_by = v_actor,
    freeze_recorded_at = now()
  where id = v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_FREEZE_DATE_RECORDED', 'project_intake_declaration', v_id,
    jsonb_build_object('project_id', p_project_id, 'freeze_date', p_freeze_date,
      'evidence_reference', v_evidence));
  return v_id;
end $$;

create or replace function public.intake_declare_control_totals(
  p_organization_id uuid,
  p_project_id uuid,
  p_declared_debit_total text,
  p_declared_credit_total text,
  p_evidence_reference text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_debit bigint;
  v_credit bigint;
  v_evidence text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);
  v_debit := public.s7_parse_minor_units(p_declared_debit_total);
  v_credit := public.s7_parse_minor_units(p_declared_credit_total);
  if v_debit is null or v_credit is null then
    raise exception 'declared control totals must be non-negative integer minor units';
  end if;
  if v_debit <> v_credit then
    raise exception 'declared debit total must equal declared credit total; Terranex does not accept a plug';
  end if;
  v_evidence := public.intake_require_safe_evidence(p_evidence_reference, 'control-totals evidence reference');

  if public.intake_has_active_posted_opening(p_organization_id, p_project_id) then
    raise exception 'signed control totals cannot change after a posted opening import';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-totals:' || p_project_id::text, 0));

  v_id := public.intake_ensure_declaration(p_organization_id, p_project_id);
  update public.project_intake_declarations set
    declared_debit_total_minor_units = v_debit,
    declared_credit_total_minor_units = v_credit,
    control_totals_evidence_reference = v_evidence,
    control_totals_declared_by = v_actor,
    control_totals_declared_at = now()
  where id = v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_CONTROL_TOTALS_DECLARED', 'project_intake_declaration', v_id,
    jsonb_build_object('project_id', p_project_id,
      'declared_debit_total_minor_units', v_debit,
      'declared_credit_total_minor_units', v_credit,
      'evidence_reference', v_evidence));
  return v_id;
end $$;

create or replace function public.intake_record_setup_references(
  p_organization_id uuid,
  p_project_id uuid,
  p_agreement_title_or_reference text,
  p_organization_evidence_reference text,
  p_project_evidence_reference text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_title text;
  v_org_ev text;
  v_proj_ev text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);

  v_title := public.s7_normalize_text(p_agreement_title_or_reference);
  if v_title is not null then
    if char_length(v_title) not between 2 and 160
       or public.s7_has_unsafe_control_characters(v_title) then
      raise exception 'invalid agreement title or reference';
    end if;
  end if;
  if p_organization_evidence_reference is not null
     and btrim(p_organization_evidence_reference) <> '' then
    v_org_ev := public.intake_require_safe_evidence(
      p_organization_evidence_reference, 'organization evidence reference');
  end if;
  if p_project_evidence_reference is not null
     and btrim(p_project_evidence_reference) <> '' then
    v_proj_ev := public.intake_require_safe_evidence(
      p_project_evidence_reference, 'project evidence reference');
  end if;
  if v_title is null and v_org_ev is null and v_proj_ev is null then
    raise exception 'at least one setup reference is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-setup:' || p_project_id::text, 0));

  v_id := public.intake_ensure_declaration(p_organization_id, p_project_id);
  update public.project_intake_declarations set
    agreement_title_or_reference = coalesce(v_title, agreement_title_or_reference),
    organization_evidence_reference = coalesce(v_org_ev, organization_evidence_reference),
    project_evidence_reference = coalesce(v_proj_ev, project_evidence_reference)
  where id = v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_SETUP_REFERENCES_RECORDED', 'project_intake_declaration', v_id,
    jsonb_build_object('project_id', p_project_id,
      'agreement_title_or_reference', v_title,
      'organization_evidence_reference', v_org_ev,
      'project_evidence_reference', v_proj_ev));
  return v_id;
end $$;

create or replace function public.intake_declare_section_applicability(
  p_organization_id uuid,
  p_project_id uuid,
  p_section_code text,
  p_applicable boolean,
  p_reason text,
  p_evidence_reference text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_code text;
  v_reason text;
  v_evidence text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);
  v_code := upper(coalesce(public.s7_normalize_text(p_section_code), ''));
  if v_code not in (
    'HISTORICAL_CALLS','HISTORICAL_CONTRIBUTIONS','ACQUISITION_BASIS','DEVELOPMENT_BASELINE',
    'UNPAID_SUPPLIERS','SALES_DISPOSITIONS','HISTORICAL_DISTRIBUTIONS','BANK_STATEMENTS'
  ) then
    raise exception 'unknown intake section code';
  end if;
  if p_applicable is null then raise exception 'section applicability is required'; end if;
  v_reason := public.s7_normalize_text(p_reason);
  if v_reason is null or char_length(v_reason) not between 3 and 500
     or public.s7_has_unsafe_control_characters(v_reason) then
    raise exception 'a reason is required (3-500 characters)';
  end if;
  if p_evidence_reference is not null and btrim(p_evidence_reference) <> '' then
    v_evidence := public.intake_require_safe_evidence(p_evidence_reference, 'section evidence reference');
  end if;
  if public.intake_has_active_posted_opening(p_organization_id, p_project_id)
     and v_code in ('UNPAID_SUPPLIERS','SALES_DISPOSITIONS','HISTORICAL_DISTRIBUTIONS') then
    raise exception 'opening-position applicability cannot change after a posted opening import';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-section:' || p_project_id::text || ':' || v_code, 0));

  insert into public.project_intake_section_applicability(
    organization_id, project_id, section_code, applicable, reason, evidence_reference, recorded_by
  ) values (
    p_organization_id, p_project_id, v_code, p_applicable, v_reason, v_evidence, v_actor
  )
  on conflict (project_id, section_code) do update set
    applicable = excluded.applicable,
    reason = excluded.reason,
    evidence_reference = excluded.evidence_reference,
    recorded_by = excluded.recorded_by,
    recorded_at = now()
  returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_SECTION_APPLICABILITY_DECLARED',
    'project_intake_section_applicability', v_id,
    jsonb_build_object('project_id', p_project_id, 'section_code', v_code,
      'applicable', p_applicable, 'reason', v_reason));
  return v_id;
end $$;

create or replace function public.intake_report_modelling_gap(
  p_organization_id uuid,
  p_project_id uuid,
  p_source_reference text,
  p_description text,
  p_amount_minor_units text,
  p_why_unmappable text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_source text;
  v_desc text;
  v_why text;
  v_amount bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);
  v_source := public.intake_require_safe_evidence(p_source_reference, 'source reference');
  v_desc := public.s7_normalize_text(p_description);
  if v_desc is null or char_length(v_desc) not between 3 and 500
     or public.s7_has_unsafe_control_characters(v_desc) then
    raise exception 'modelling-gap description is required (3-500 characters)';
  end if;
  v_why := public.s7_normalize_text(p_why_unmappable);
  if v_why is null or char_length(v_why) not between 3 and 1000
     or public.s7_has_unsafe_control_characters(v_why) then
    raise exception 'why the balance is unmappable is required';
  end if;
  if p_amount_minor_units is not null and btrim(p_amount_minor_units) <> '' then
    v_amount := public.s7_parse_minor_units(p_amount_minor_units);
    if v_amount is null or v_amount <= 0 then
      raise exception 'modelling-gap amount must be a positive integer minor-unit value when supplied';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-gap:' || p_project_id::text || ':' || v_source, 0));

  select id into v_id
  from public.project_intake_modelling_gaps
  where project_id = p_project_id and source_reference = v_source;
  if v_id is not null then
    return v_id;
  end if;

  insert into public.project_intake_modelling_gaps(
    organization_id, project_id, source_reference, description,
    amount_minor_units, currency, why_unmappable, recorded_by
  ) values (
    p_organization_id, p_project_id, v_source, v_desc,
    v_amount, 'EGP', v_why, v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_MODELLING_GAP_REPORTED', 'project_intake_modelling_gap', v_id,
    jsonb_build_object('project_id', p_project_id, 'source_reference', v_source,
      'amount_minor_units', v_amount, 'why_unmappable', v_why));
  return v_id;
end $$;

create or replace function public.intake_accept_modelling_gap(
  p_organization_id uuid,
  p_gap_id uuid,
  p_resolution_evidence_reference text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_gap record;
  v_evidence text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_evidence := public.intake_require_safe_evidence(
    p_resolution_evidence_reference, 'commercial-acceptance evidence reference');

  select * into v_gap
  from public.project_intake_modelling_gaps
  where id = p_gap_id and organization_id = p_organization_id
  for update;
  if not found then raise exception 'modelling gap not found'; end if;
  if v_gap.status = 'COMMERCIALLY_ACCEPTED' then return v_gap.id; end if;

  update public.project_intake_modelling_gaps set
    status = 'COMMERCIALLY_ACCEPTED',
    resolved_by = v_actor,
    resolved_at = now(),
    resolution_evidence_reference = v_evidence
  where id = p_gap_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_MODELLING_GAP_ACCEPTED', 'project_intake_modelling_gap', p_gap_id,
    jsonb_build_object('project_id', v_gap.project_id, 'source_reference', v_gap.source_reference,
      'evidence_reference', v_evidence));
  return p_gap_id;
end $$;

create or replace function public.intake_record_evidence_item(
  p_organization_id uuid,
  p_project_id uuid,
  p_evidence_identifier text,
  p_linked_fact text,
  p_customer_storage_location text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_identifier text;
  v_fact text;
  v_location text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  perform public.intake_require_project(p_organization_id, p_project_id);
  v_identifier := public.intake_require_safe_evidence(p_evidence_identifier, 'evidence identifier');
  v_fact := public.s7_normalize_text(p_linked_fact);
  if v_fact is null or char_length(v_fact) not between 3 and 200
     or public.s7_has_unsafe_control_characters(v_fact) then
    raise exception 'linked fact is required (3-200 characters)';
  end if;
  v_location := public.s7_normalize_text(p_customer_storage_location);
  if v_location is null or char_length(v_location) not between 3 and 300
     or public.s7_has_unsafe_control_characters(v_location) then
    raise exception 'customer storage location is required (3-300 characters)';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':intake-evidence:' || v_identifier, 0));

  select id into v_id
  from public.project_intake_evidence_items
  where organization_id = p_organization_id and evidence_identifier = v_identifier;
  if v_id is not null then
    return v_id;
  end if;

  insert into public.project_intake_evidence_items(
    organization_id, project_id, evidence_identifier, linked_fact,
    customer_storage_location, recorded_by
  ) values (
    p_organization_id, p_project_id, v_identifier, v_fact, v_location, v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'INTAKE_EVIDENCE_ITEM_RECORDED', 'project_intake_evidence_item', v_id,
    jsonb_build_object('project_id', p_project_id, 'evidence_identifier', v_identifier,
      'linked_fact', v_fact));
  return v_id;
end $$;

-- ===========================================================================
-- 5. Read models — bigint as text, free text export-safe
-- ===========================================================================
create or replace view public.project_intake_declarations_read
  with (security_invoker = on) as
select
  d.id as declaration_id,
  d.organization_id,
  d.project_id,
  d.freeze_date,
  public.s7_export_safe_text(d.freeze_evidence_reference) as freeze_evidence_reference,
  d.freeze_recorded_by,
  d.freeze_recorded_at,
  d.declared_debit_total_minor_units::text as declared_debit_total_minor_units,
  d.declared_credit_total_minor_units::text as declared_credit_total_minor_units,
  public.s7_export_safe_text(d.control_totals_evidence_reference) as control_totals_evidence_reference,
  d.control_totals_declared_by,
  d.control_totals_declared_at,
  public.s7_export_safe_text(d.agreement_title_or_reference) as agreement_title_or_reference,
  public.s7_export_safe_text(d.organization_evidence_reference) as organization_evidence_reference,
  public.s7_export_safe_text(d.project_evidence_reference) as project_evidence_reference,
  d.created_at,
  d.updated_at
from public.project_intake_declarations d;

create or replace view public.project_intake_section_applicability_read
  with (security_invoker = on) as
select
  a.id as applicability_id,
  a.organization_id,
  a.project_id,
  a.section_code,
  a.applicable,
  public.s7_export_safe_text(a.reason) as reason,
  public.s7_export_safe_text(a.evidence_reference) as evidence_reference,
  a.recorded_by,
  a.recorded_at
from public.project_intake_section_applicability a;

create or replace view public.project_intake_modelling_gaps_read
  with (security_invoker = on) as
select
  g.id as gap_id,
  g.organization_id,
  g.project_id,
  public.s7_export_safe_text(g.source_reference) as source_reference,
  public.s7_export_safe_text(g.description) as description,
  g.amount_minor_units::text as amount_minor_units,
  g.currency,
  public.s7_export_safe_text(g.why_unmappable) as why_unmappable,
  g.status,
  g.recorded_by,
  g.recorded_at,
  g.resolved_by,
  g.resolved_at,
  public.s7_export_safe_text(g.resolution_evidence_reference) as resolution_evidence_reference
from public.project_intake_modelling_gaps g;

create or replace view public.project_intake_evidence_items_read
  with (security_invoker = on) as
select
  e.id as evidence_item_id,
  e.organization_id,
  e.project_id,
  public.s7_export_safe_text(e.evidence_identifier) as evidence_identifier,
  public.s7_export_safe_text(e.linked_fact) as linked_fact,
  public.s7_export_safe_text(e.customer_storage_location) as customer_storage_location,
  e.recorded_by,
  e.recorded_at
from public.project_intake_evidence_items e;

-- ===========================================================================
-- 6. Default-deny RLS and exact grants
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'project_intake_declarations',
    'project_intake_section_applicability',
    'project_intake_modelling_gaps',
    'project_intake_evidence_items'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))',
      t || '_read', t
    );
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

grant select on
  public.project_intake_declarations_read,
  public.project_intake_section_applicability_read,
  public.project_intake_modelling_gaps_read,
  public.project_intake_evidence_items_read
to authenticated;

revoke all on function public.intake_record_freeze_date(uuid,uuid,date,text) from public, anon;
revoke all on function public.intake_declare_control_totals(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.intake_record_setup_references(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.intake_declare_section_applicability(uuid,uuid,text,boolean,text,text) from public, anon;
revoke all on function public.intake_report_modelling_gap(uuid,uuid,text,text,text,text) from public, anon;
revoke all on function public.intake_accept_modelling_gap(uuid,uuid,text) from public, anon;
revoke all on function public.intake_record_evidence_item(uuid,uuid,text,text,text) from public, anon;

grant execute on function
  public.intake_record_freeze_date(uuid,uuid,date,text),
  public.intake_declare_control_totals(uuid,uuid,text,text,text),
  public.intake_record_setup_references(uuid,uuid,text,text,text),
  public.intake_declare_section_applicability(uuid,uuid,text,boolean,text,text),
  public.intake_report_modelling_gap(uuid,uuid,text,text,text,text),
  public.intake_accept_modelling_gap(uuid,uuid,text),
  public.intake_record_evidence_item(uuid,uuid,text,text,text)
to authenticated;
