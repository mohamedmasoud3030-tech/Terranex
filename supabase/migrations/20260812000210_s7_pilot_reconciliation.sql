-- GF-009 / S7 — Pilot reconciliation checkpoints.
--
-- During a controlled pilot the customer keeps operating their existing
-- spreadsheet/accounting process in parallel. This slice records that external
-- control total as *evidence* and compares it against the value Terranex
-- derives from its own posted journal.
--
-- Hard rules:
--   * the external value is never a ledger fact and never posts anything;
--   * the Terranex value is always recomputed inside PostgreSQL from posted
--     journal lines — it is never supplied by the browser;
--   * the variance is an exact integer in minor units;
--   * zero variance is recorded explicitly, not implied by silence;
--   * a non-zero variance always creates a visible exception with an owner,
--     severity, status and resolution trail;
--   * sign-off is immutable and enforces maker/checker.

-- ===========================================================================
-- 1. Authoritative checkpoint derivation (server/DB side only).
-- ===========================================================================
create or replace function public.s7_authoritative_checkpoint_value(
  p_organization_id uuid, p_project_id uuid, p_checkpoint_code text, p_as_of_date date
) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_currency text; v_value numeric;
begin
  select reporting_currency into v_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;
  if p_as_of_date is null then raise exception 'as-of date is required'; end if;

  if p_checkpoint_code = 'PROJECT_CASH' then
    select coalesce(sum(jl.debit_minor_units::numeric - jl.credit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'SUPPLIER_OBLIGATION_POSITION' then
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'SUPPLIER_PAYABLE'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'CUSTOMER_RECEIVABLE_POSITION' then
    select coalesce(sum(jl.debit_minor_units::numeric - jl.credit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'CUSTOMER_RECEIVABLE'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'REALIZED_RESULT' then
    -- Same economic definition S5 allocates from: recognized sale revenue less
    -- derecognized cost of sale less posted selling cost.
    select coalesce(sum(
      case
        when sa.role = 'REAL_ESTATE_SALE_REVENUE' then jl.credit_minor_units::numeric - jl.debit_minor_units::numeric
        when sa.role = 'REAL_ESTATE_COST_OF_SALE' then -(jl.debit_minor_units::numeric - jl.credit_minor_units::numeric)
        when sa.role = 'PROJECT_EXPENSE' and pci.cost_category = 'SELLING'
          then -(jl.debit_minor_units::numeric - jl.credit_minor_units::numeric)
        else 0
      end), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id
    left join public.property_cost_items pci
      on pci.cost_obligation_id = jl.obligation_id and pci.organization_id = jl.organization_id
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date
      and (sa.role in ('REAL_ESTATE_SALE_REVENUE','REAL_ESTATE_COST_OF_SALE')
        or (sa.role = 'PROJECT_EXPENSE' and pci.cost_category = 'SELLING'));

  elsif p_checkpoint_code = 'CONTRIBUTED_CAPITAL' then
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'CONTRIBUTED_CAPITAL'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'PARTNER_CAPITAL' then
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id
      and sa.role in ('CONTRIBUTED_CAPITAL','PARTNER_CAPITAL')
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'DISTRIBUTION_PAYABLE' then
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'DISTRIBUTION_PAYABLE'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date;

  elsif p_checkpoint_code = 'DISTRIBUTION_PAID' then
    select coalesce(sum(jl.debit_minor_units::numeric - jl.credit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.journal_batches jb on jb.id = jl.batch_id and jb.organization_id = jl.organization_id
    join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'DISTRIBUTION_PAYABLE'
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.transaction_date <= p_as_of_date
      and jb.source_type = 'S5_DISTRIBUTION_PAYMENT';

  elsif p_checkpoint_code = 'INVESTOR_STATEMENT_TOTAL' then
    -- Total closing partner capital across every investor, restricted to
    -- party-dimensioned capital lines so it traces line-by-line to the
    -- investor statement rather than to an aggregate.
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) into v_value
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id
      and sa.role in ('CONTRIBUTED_CAPITAL','PARTNER_CAPITAL')
    where jl.organization_id = p_organization_id and jl.project_id = p_project_id
      and jl.currency = v_currency and jl.party_id is not null
      and jl.transaction_date <= p_as_of_date;

  else
    raise exception 'unsupported reconciliation checkpoint %', p_checkpoint_code;
  end if;

  return v_value::bigint;
end $$;
revoke all on function public.s7_authoritative_checkpoint_value(uuid,uuid,text,date) from public, anon, authenticated;

-- ===========================================================================
-- 2. Checkpoint and exception tables.
-- ===========================================================================
create table public.s7_reconciliation_checkpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  checkpoint_code text not null check (checkpoint_code in (
    'PROJECT_CASH','SUPPLIER_OBLIGATION_POSITION','CUSTOMER_RECEIVABLE_POSITION',
    'REALIZED_RESULT','CONTRIBUTED_CAPITAL','PARTNER_CAPITAL',
    'DISTRIBUTION_PAYABLE','DISTRIBUTION_PAID','INVESTOR_STATEMENT_TOTAL'
  )),
  as_of_date date not null,
  reporting_currency text not null check (reporting_currency ~ '^[A-Z]{3}$'),
  external_value_minor_units bigint not null,
  terranex_value_minor_units bigint not null,
  variance_minor_units bigint not null,
  external_source_reference text not null check (char_length(trim(external_source_reference)) between 3 and 200),
  external_evidence_reference text not null check (char_length(trim(external_evidence_reference)) between 3 and 200),
  status text not null check (status in ('MATCHED','VARIANCE','SIGNED_OFF')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  signed_off_by uuid references auth.users(id) on delete restrict,
  signed_off_at timestamptz,
  sign_off_evidence_reference text check (sign_off_evidence_reference is null
    or char_length(trim(sign_off_evidence_reference)) between 3 and 200),
  content_hash text not null check (char_length(content_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  sign_off_idempotency_key text check (sign_off_idempotency_key is null
    or char_length(sign_off_idempotency_key) between 8 and 120),
  -- The variance is a derived integer fact, never a stored opinion.
  constraint s7_checkpoint_variance_check
    check (variance_minor_units = external_value_minor_units - terranex_value_minor_units),
  constraint s7_checkpoint_status_check check (
    (status = 'MATCHED' and variance_minor_units = 0 and signed_off_by is null)
    or (status = 'VARIANCE' and variance_minor_units <> 0 and signed_off_by is null)
    or (status = 'SIGNED_OFF' and signed_off_by is not null and signed_off_at is not null
        and sign_off_evidence_reference is not null)
  ),
  -- Maker/checker: the operator who recorded the checkpoint can never be the
  -- operator who signs it off.
  constraint s7_checkpoint_maker_checker_check
    check (signed_off_by is null or signed_off_by <> prepared_by),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index s7_reconciliation_checkpoints_project_idx
  on public.s7_reconciliation_checkpoints(project_id, checkpoint_code, as_of_date desc);
create unique index s7_reconciliation_checkpoints_sign_off_key
  on public.s7_reconciliation_checkpoints(organization_id, sign_off_idempotency_key)
  where sign_off_idempotency_key is not null;

create table public.s7_reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  checkpoint_id uuid not null,
  severity text not null check (severity in ('LOW','MEDIUM','HIGH','CRITICAL')),
  status text not null default 'OPEN' check (status in ('OPEN','RESOLVED')),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  variance_minor_units bigint not null check (variance_minor_units <> 0),
  detail text not null check (char_length(trim(detail)) between 3 and 2000),
  resolution text check (resolution is null or char_length(trim(resolution)) between 3 and 2000),
  resolution_evidence_reference text check (resolution_evidence_reference is null
    or char_length(trim(resolution_evidence_reference)) between 3 and 200),
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  raised_at timestamptz not null default now(),
  constraint s7_reconciliation_exception_resolution_check check (
    (status = 'OPEN' and resolved_by is null and resolved_at is null
      and resolution is null and resolution_evidence_reference is null)
    or (status = 'RESOLVED' and resolved_by is not null and resolved_at is not null
      and resolution is not null and resolution_evidence_reference is not null)
  ),
  unique (id, organization_id),
  foreign key (checkpoint_id, organization_id, project_id)
    references public.s7_reconciliation_checkpoints(id, organization_id, project_id) on delete restrict
);
create index s7_reconciliation_exceptions_open_idx
  on public.s7_reconciliation_exceptions(project_id, status, severity);
-- A checkpoint carries at most one open exception at a time.
create unique index s7_reconciliation_exceptions_one_open
  on public.s7_reconciliation_exceptions(checkpoint_id) where status = 'OPEN';

-- ---------------------------------------------------------------------------
-- 2a. Immutability. A recorded checkpoint's economics never change; only the
--     sign-off columns may be filled once, and a signed-off row is frozen.
-- ---------------------------------------------------------------------------
create or replace function public.s7_guard_checkpoint_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.organization_id <> new.organization_id
     or old.project_id <> new.project_id
     or old.checkpoint_code <> new.checkpoint_code
     or old.as_of_date <> new.as_of_date
     or old.reporting_currency <> new.reporting_currency
     or old.external_value_minor_units <> new.external_value_minor_units
     or old.terranex_value_minor_units <> new.terranex_value_minor_units
     or old.variance_minor_units <> new.variance_minor_units
     or old.external_source_reference <> new.external_source_reference
     or old.external_evidence_reference <> new.external_evidence_reference
     or old.prepared_by <> new.prepared_by
     or old.content_hash <> new.content_hash
     or old.idempotency_key <> new.idempotency_key then
    raise exception 'a recorded reconciliation checkpoint is immutable; record a new checkpoint instead';
  end if;
  if old.status = 'SIGNED_OFF' then
    raise exception 'a signed-off reconciliation checkpoint is immutable';
  end if;
  if new.status <> 'SIGNED_OFF' and new.status <> old.status then
    raise exception 'invalid reconciliation checkpoint transition % -> %', old.status, new.status;
  end if;
  return new;
end $$;
create trigger s7_reconciliation_checkpoints_immutable
before update on public.s7_reconciliation_checkpoints
for each row execute function public.s7_guard_checkpoint_immutable();

create or replace function public.s7_guard_reconciliation_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'reconciliation facts are append-only';
end $$;
create trigger s7_reconciliation_checkpoints_no_delete
before delete on public.s7_reconciliation_checkpoints
for each row execute function public.s7_guard_reconciliation_append_only();
create trigger s7_reconciliation_exceptions_no_delete
before delete on public.s7_reconciliation_exceptions
for each row execute function public.s7_guard_reconciliation_append_only();

create or replace function public.s7_guard_exception_immutable() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if old.organization_id <> new.organization_id
     or old.project_id <> new.project_id
     or old.checkpoint_id <> new.checkpoint_id
     or old.variance_minor_units <> new.variance_minor_units
     or old.raised_at <> new.raised_at then
    raise exception 'a raised reconciliation exception is immutable';
  end if;
  if old.status = 'RESOLVED' then
    raise exception 'a resolved reconciliation exception is immutable';
  end if;
  return new;
end $$;
create trigger s7_reconciliation_exceptions_immutable
before update on public.s7_reconciliation_exceptions
for each row execute function public.s7_guard_exception_immutable();

-- ===========================================================================
-- 3. Record a checkpoint. The external number is evidence; PostgreSQL supplies
--    the authoritative number and the variance.
-- ===========================================================================
create or replace function public.s7_record_reconciliation_checkpoint(
  p_organization_id uuid,
  p_project_id uuid,
  p_checkpoint_code text,
  p_as_of_date date,
  p_external_value_minor_units bigint,
  p_external_source_reference text,
  p_external_evidence_reference text,
  p_exception_owner_id uuid,
  p_exception_severity text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_existing record; v_id uuid;
  v_currency text; v_terranex bigint; v_variance bigint; v_hash text; v_owner uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_external_value_minor_units is null then
    raise exception 'an external control total is required';
  end if;
  if p_as_of_date is null then raise exception 'as-of date is required'; end if;
  if p_external_source_reference is null
     or char_length(trim(p_external_source_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_external_source_reference) then
    raise exception 'an external source reference is required';
  end if;
  if p_external_evidence_reference is null
     or char_length(trim(p_external_evidence_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_external_evidence_reference) then
    raise exception 'an external evidence reference is required';
  end if;

  select reporting_currency into v_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;

  v_terranex := public.s7_authoritative_checkpoint_value(
    p_organization_id, p_project_id, p_checkpoint_code, p_as_of_date);
  v_variance := p_external_value_minor_units - v_terranex;

  if v_variance <> 0 then
    if p_exception_severity is null or p_exception_severity not in ('LOW','MEDIUM','HIGH','CRITICAL') then
      raise exception 'a non-zero variance requires an explicit exception severity';
    end if;
    v_owner := coalesce(p_exception_owner_id, v_actor);
    if not exists (
      select 1 from public.memberships m
      where m.organization_id = p_organization_id and m.user_id = v_owner and m.status = 'ACTIVE'
    ) then
      raise exception 'the exception owner must be an active member of this organization';
    end if;
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'checkpoint_code', p_checkpoint_code,
    'as_of_date', p_as_of_date, 'external_value', p_external_value_minor_units,
    'source_reference', trim(p_external_source_reference)
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-reconciliation:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.s7_reconciliation_checkpoints
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.s7_reconciliation_checkpoints(
    organization_id, project_id, checkpoint_code, as_of_date, reporting_currency,
    external_value_minor_units, terranex_value_minor_units, variance_minor_units,
    external_source_reference, external_evidence_reference, status,
    prepared_by, content_hash, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_checkpoint_code, p_as_of_date, v_currency,
    p_external_value_minor_units, v_terranex, v_variance,
    trim(p_external_source_reference), trim(p_external_evidence_reference),
    case when v_variance = 0 then 'MATCHED' else 'VARIANCE' end,
    v_actor, v_hash, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  if v_variance <> 0 then
    insert into public.s7_reconciliation_exceptions(
      organization_id, project_id, checkpoint_id, severity, status, owner_user_id,
      variance_minor_units, detail
    ) values (
      p_organization_id, p_project_id, v_id, p_exception_severity, 'OPEN', v_owner,
      v_variance,
      format('%s variance of %s minor units against external source %s as of %s',
        p_checkpoint_code, v_variance, trim(p_external_source_reference), p_as_of_date)
    );
  end if;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_RECONCILIATION_CHECKPOINT_RECORDED',
    's7_reconciliation_checkpoint', v_id,
    jsonb_build_object('project_id', p_project_id, 'checkpoint_code', p_checkpoint_code,
      'as_of_date', p_as_of_date, 'external_value_minor_units', p_external_value_minor_units,
      'terranex_value_minor_units', v_terranex, 'variance_minor_units', v_variance));
  return v_id;
end $$;

-- ===========================================================================
-- 4. Resolve an exception. Resolution is a documented act, not a deletion.
-- ===========================================================================
create or replace function public.s7_resolve_reconciliation_exception(
  p_organization_id uuid, p_exception_id uuid, p_resolution text,
  p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_exception record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_resolution is null or char_length(trim(p_resolution)) not between 3 and 2000
     or public.s7_has_unsafe_control_characters(p_resolution) then
    raise exception 'a resolution statement is required';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_evidence_reference) then
    raise exception 'a resolution evidence reference is required';
  end if;
  select * into v_exception from public.s7_reconciliation_exceptions
  where id = p_exception_id and organization_id = p_organization_id for update;
  if not found then raise exception 'reconciliation exception not found'; end if;
  if v_exception.status = 'RESOLVED' then return p_exception_id; end if;
  update public.s7_reconciliation_exceptions set
    status = 'RESOLVED', resolution = trim(p_resolution),
    resolution_evidence_reference = trim(p_evidence_reference),
    resolved_by = v_actor, resolved_at = now()
  where id = p_exception_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_RECONCILIATION_EXCEPTION_RESOLVED',
    's7_reconciliation_exception', p_exception_id,
    jsonb_build_object('project_id', v_exception.project_id,
      'checkpoint_id', v_exception.checkpoint_id, 'severity', v_exception.severity,
      'variance_minor_units', v_exception.variance_minor_units));
  return p_exception_id;
end $$;

-- ===========================================================================
-- 5. Immutable sign-off with maker/checker.
-- ===========================================================================
create or replace function public.s7_sign_off_reconciliation_checkpoint(
  p_organization_id uuid, p_checkpoint_id uuid, p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_checkpoint record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_evidence_reference) then
    raise exception 'a sign-off evidence reference is required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-reconciliation-signoff:' || p_checkpoint_id::text, 0));
  select * into v_checkpoint from public.s7_reconciliation_checkpoints
  where id = p_checkpoint_id and organization_id = p_organization_id for update;
  if not found then raise exception 'reconciliation checkpoint not found'; end if;
  if v_checkpoint.status = 'SIGNED_OFF' then
    if v_checkpoint.sign_off_idempotency_key = trim(p_idempotency_key) then return p_checkpoint_id; end if;
    raise exception 'reconciliation checkpoint is already signed off';
  end if;
  if exists (
    select 1 from public.s7_reconciliation_exceptions e
    where e.checkpoint_id = p_checkpoint_id and e.status = 'OPEN'
  ) then
    raise exception 'reconciliation checkpoint has an unresolved exception; resolve it before sign-off';
  end if;
  update public.s7_reconciliation_checkpoints set
    status = 'SIGNED_OFF', signed_off_by = v_actor, signed_off_at = now(),
    sign_off_evidence_reference = trim(p_evidence_reference),
    sign_off_idempotency_key = trim(p_idempotency_key)
  where id = p_checkpoint_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_RECONCILIATION_CHECKPOINT_SIGNED_OFF',
    's7_reconciliation_checkpoint', p_checkpoint_id,
    jsonb_build_object('project_id', v_checkpoint.project_id,
      'checkpoint_code', v_checkpoint.checkpoint_code,
      'as_of_date', v_checkpoint.as_of_date,
      'variance_minor_units', v_checkpoint.variance_minor_units));
  return p_checkpoint_id;
end $$;

-- ===========================================================================
-- 6. Read models.
-- ===========================================================================
create or replace view public.s7_reconciliation_checkpoints_read with (security_invoker=on) as
select
  c.id as checkpoint_id,
  c.organization_id,
  c.project_id,
  c.checkpoint_code,
  c.as_of_date,
  c.reporting_currency,
  c.external_value_minor_units::text as external_value_minor_units,
  c.terranex_value_minor_units::text as terranex_value_minor_units,
  c.variance_minor_units::text as variance_minor_units,
  (c.variance_minor_units = 0) as is_zero_variance,
  public.s7_export_safe_text(c.external_source_reference) as external_source_reference,
  public.s7_export_safe_text(c.external_evidence_reference) as external_evidence_reference,
  c.status,
  c.prepared_by,
  c.prepared_at,
  c.signed_off_by,
  c.signed_off_at,
  public.s7_export_safe_text(c.sign_off_evidence_reference) as sign_off_evidence_reference,
  c.content_hash,
  coalesce(x.open_exceptions, 0) as open_exception_count,
  x.max_open_severity
from public.s7_reconciliation_checkpoints c
left join lateral (
  select count(*) filter (where e.status = 'OPEN') as open_exceptions,
         max(case e.severity
               when 'CRITICAL' then 4 when 'HIGH' then 3 when 'MEDIUM' then 2 else 1 end)
           filter (where e.status = 'OPEN') as severity_rank,
         (array_agg(e.severity order by case e.severity
               when 'CRITICAL' then 4 when 'HIGH' then 3 when 'MEDIUM' then 2 else 1 end desc)
          filter (where e.status = 'OPEN'))[1] as max_open_severity
  from public.s7_reconciliation_exceptions e
  where e.checkpoint_id = c.id
) x on true;

create or replace view public.s7_reconciliation_exceptions_read with (security_invoker=on) as
select
  e.id as exception_id,
  e.organization_id,
  e.project_id,
  e.checkpoint_id,
  c.checkpoint_code,
  c.as_of_date,
  e.severity,
  e.status,
  e.owner_user_id,
  e.variance_minor_units::text as variance_minor_units,
  public.s7_export_safe_text(e.detail) as detail,
  public.s7_export_safe_text(e.resolution) as resolution,
  public.s7_export_safe_text(e.resolution_evidence_reference) as resolution_evidence_reference,
  e.resolved_by,
  e.resolved_at,
  e.raised_at
from public.s7_reconciliation_exceptions e
join public.s7_reconciliation_checkpoints c
  on c.id = e.checkpoint_id and c.organization_id = e.organization_id;

-- ===========================================================================
-- 7. Default-deny RLS and exact command permissions.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['s7_reconciliation_checkpoints','s7_reconciliation_exceptions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t || '_read', t);
    execute format('revoke all on public.%I from anon,authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

grant select on public.s7_reconciliation_checkpoints_read,
  public.s7_reconciliation_exceptions_read to authenticated;

revoke all on function public.s7_record_reconciliation_checkpoint(uuid,uuid,text,date,bigint,text,text,uuid,text,text) from public, anon;
revoke all on function public.s7_resolve_reconciliation_exception(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.s7_sign_off_reconciliation_checkpoint(uuid,uuid,text,text) from public, anon;

grant execute on function
  public.s7_record_reconciliation_checkpoint(uuid,uuid,text,date,bigint,text,text,uuid,text,text),
  public.s7_resolve_reconciliation_exception(uuid,uuid,text,text,text),
  public.s7_sign_off_reconciliation_checkpoint(uuid,uuid,text,text)
to authenticated;
