-- GF-009 / S7 — Controlled opening import (Real Estate pilot onboarding).
--
-- One customer opening position is imported into an existing Real Estate
-- project through an explicit, auditable lifecycle:
--
--   DRAFT -> VALIDATED -> READY_FOR_APPROVAL -> APPROVED -> POSTED
--   with terminal REJECTED / FAILED branches.
--
-- The importer is deliberately NOT a universal ETL tool. It accepts a fixed
-- set of Real-Estate opening mapping codes that resolve to the *existing*
-- locked semantic account roles, and it posts exactly one balanced canonical
-- journal batch through the same S2 invariants every other slice uses. S7
-- adds no semantic account role: an opening position that cannot be expressed
-- with the roles the product already owns is a real modelling gap and is
-- reported as such rather than absorbed into an invented account.
--
-- Money is bigint minor units. Balances are never written directly.
-- Corrections use the existing linked-reversal command, never an edit of a
-- posted fact.

-- ===========================================================================
-- 1. Journal source registry extension.
-- ===========================================================================
alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT'
));

-- ===========================================================================
-- 2. Deterministic text/number safety helpers.
--    Import text is normalized exactly once, checked for control characters,
--    and neutralized against CSV formula injection on the way out.
-- ===========================================================================
create or replace function public.s7_normalize_text(p_value text)
returns text language sql immutable set search_path=pg_catalog,public as $$
  select nullif(
    btrim(regexp_replace(
      translate(coalesce(p_value, ''), '٠١٢٣٤٥٦٧٨٩٫٬', '0123456789.,'),
      '[[:space:]]+', ' ', 'g'
    )),
  '')
$$;

create or replace function public.s7_has_unsafe_control_characters(p_value text)
returns boolean language sql immutable set search_path=pg_catalog,public as $$
  select coalesce(p_value, '') ~ '[\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]'
$$;

-- A leading =, +, -, @, tab or CR turns a spreadsheet cell into an executable
-- formula. Every free-text value that can be exported or previewed leaves the
-- database already neutralized.
create or replace function public.s7_export_safe_text(p_value text)
returns text language sql immutable set search_path=pg_catalog,public as $$
  select case
    when p_value is null then null
    when p_value ~ '^[=+@\-\t\r]' then '''' || p_value
    else p_value
  end
$$;

-- Strict non-negative integer minor-unit parser. Blank means zero; anything
-- the product would have to guess about returns null and becomes a rejected
-- row rather than a silently coerced amount.
create or replace function public.s7_parse_minor_units(p_value text)
returns bigint language plpgsql immutable set search_path=pg_catalog,public as $$
declare v_text text; v_value bigint;
begin
  v_text := public.s7_normalize_text(p_value);
  if v_text is null then return 0; end if;
  v_text := replace(replace(v_text, ' ', ''), ',', '');
  if v_text !~ '^\d{1,19}$' then return null; end if;
  begin
    v_value := v_text::bigint;
  exception when others then
    return null;
  end;
  return v_value;
end $$;

-- An opening position is an ordinary posting: it may never land in a CLOSED
-- period. S6 keeps period management opt-in until a project opens its first
-- period, and S7 follows exactly that rule instead of inventing a stricter or
-- looser one.
create or replace function public.s7_require_postable_date(
  p_organization_id uuid, p_project_id uuid, p_posting_date date
) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_periods integer; v_open integer;
begin
  if p_posting_date is null then raise exception 'posting date is required'; end if;
  select count(*) into v_periods from public.accounting_periods
  where organization_id = p_organization_id and project_id = p_project_id;
  if v_periods = 0 then return; end if;
  select count(*) into v_open from public.accounting_periods
  where organization_id = p_organization_id and project_id = p_project_id
    and status = 'OPEN' and p_posting_date between start_date and end_date;
  if v_open <> 1 then
    raise exception 'opening import requires exactly one OPEN accounting period covering the posting date';
  end if;
end $$;
revoke all on function public.s7_require_postable_date(uuid,uuid,date) from public, anon, authenticated;

-- ===========================================================================
-- 3. Real-Estate opening mapping registry.
--    Locked exactly like the semantic account registry: an opening file may
--    only use these codes. There is no generic column-mapping engine and no
--    customer-specific mapping fork.
-- ===========================================================================
create table public.s7_opening_mapping_codes (
  code text primary key,
  account_role text not null,
  label_ar text not null check (char_length(trim(label_ar)) between 2 and 120),
  natural_side text not null check (natural_side in ('DEBIT','CREDIT')),
  requires_party boolean not null default false,
  requires_cash_account boolean not null default false,
  created_at timestamptz not null default now()
);
insert into public.s7_opening_mapping_codes(
  code, account_role, label_ar, natural_side, requires_party, requires_cash_account
) values
  ('OPENING_BANK_CASH','BANK_CASH','رصيد نقدية افتتاحي','DEBIT',false,true),
  ('OPENING_DEVELOPMENT_WIP','DEVELOPMENT_WIP','أعمال تطوير تحت التنفيذ افتتاحية','DEBIT',false,false),
  ('OPENING_CUSTOMER_RECEIVABLE','CUSTOMER_RECEIVABLE','مستحق على العملاء افتتاحي','DEBIT',true,false),
  ('OPENING_SUPPLIER_PAYABLE','SUPPLIER_PAYABLE','مستحق للموردين افتتاحي','CREDIT',true,false),
  ('OPENING_CONTRIBUTED_CAPITAL','CONTRIBUTED_CAPITAL','رأس مال مساهم افتتاحي','CREDIT',true,false),
  ('OPENING_DISTRIBUTION_PAYABLE','DISTRIBUTION_PAYABLE','توزيعات معتمدة غير مدفوعة افتتاحية','CREDIT',true,false)
on conflict (code) do nothing;

create or replace function public.s7_guard_mapping_registry_locked() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'opening mapping codes are locked by S7 policy';
end $$;
create trigger s7_opening_mapping_codes_locked
before insert or update or delete on public.s7_opening_mapping_codes
for each row execute function public.s7_guard_mapping_registry_locked();

-- ===========================================================================
-- 4. Opening import batch and rows.
-- ===========================================================================
create table public.s7_opening_imports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  schema_version text not null check (schema_version ~ '^S7\.OPENING\.V[0-9]{1,3}$'),
  source_file_name text not null check (char_length(trim(source_file_name)) between 3 and 200),
  source_file_checksum text not null check (source_file_checksum ~ '^[0-9a-f]{64}$'),
  reporting_currency text not null check (reporting_currency ~ '^[A-Z]{3}$'),
  status text not null default 'DRAFT' check (status in (
    'DRAFT','VALIDATED','READY_FOR_APPROVAL','APPROVED','POSTED','REJECTED','FAILED'
  )),
  submitted_row_count integer not null check (submitted_row_count > 0),
  accepted_row_count integer not null default 0 check (accepted_row_count >= 0),
  rejected_row_count integer not null default 0 check (rejected_row_count >= 0),
  declared_debit_total_minor_units bigint not null check (declared_debit_total_minor_units >= 0),
  declared_credit_total_minor_units bigint not null check (declared_credit_total_minor_units >= 0),
  computed_debit_total_minor_units bigint not null default 0 check (computed_debit_total_minor_units >= 0),
  computed_credit_total_minor_units bigint not null default 0 check (computed_credit_total_minor_units >= 0),
  debit_variance_minor_units bigint not null default 0,
  credit_variance_minor_units bigint not null default 0,
  mapping_summary jsonb not null default '{}'::jsonb,
  rejection_summary jsonb not null default '[]'::jsonb,
  failure_reason text check (failure_reason is null or char_length(trim(failure_reason)) between 3 and 2000),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default now(),
  validated_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  review_notes text check (review_notes is null or char_length(trim(review_notes)) <= 2000),
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  posting_date date,
  journal_batch_id uuid,
  snapshot_payload jsonb,
  snapshot_content_hash text check (snapshot_content_hash is null or char_length(snapshot_content_hash) = 64),
  snapshot_captured_at timestamptz,
  content_hash text not null check (char_length(content_hash) = 64),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  approval_idempotency_key text check (approval_idempotency_key is null or char_length(approval_idempotency_key) between 8 and 120),
  approval_request_hash text check (approval_request_hash is null or char_length(approval_request_hash) = 64),
  -- Maker/checker: the operator who prepared an opening import can never be
  -- the operator who approves it, whatever privilege they hold.
  constraint s7_opening_import_maker_checker_check
    check (approved_by is null or approved_by <> prepared_by),
  constraint s7_opening_import_approved_columns_check check (
    (status in ('APPROVED','POSTED')) =
    (approved_by is not null and approved_at is not null and posting_date is not null
      and snapshot_content_hash is not null and snapshot_payload is not null)
  ),
  constraint s7_opening_import_posted_columns_check check (
    (status = 'POSTED') = (journal_batch_id is not null)
  ),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
create index s7_opening_imports_project_idx
  on public.s7_opening_imports(project_id, status, prepared_at desc);
create unique index s7_opening_imports_approval_idempotency_key
  on public.s7_opening_imports(organization_id, approval_idempotency_key)
  where approval_idempotency_key is not null;

create table public.s7_opening_import_rows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  import_id uuid not null,
  row_number integer not null check (row_number > 0),
  mapping_code text not null,
  account_role text,
  party_id uuid,
  cash_account_id uuid,
  debit_minor_units bigint not null default 0 check (debit_minor_units >= 0),
  credit_minor_units bigint not null default 0 check (credit_minor_units >= 0),
  description text not null check (char_length(description) between 1 and 500),
  raw_payload jsonb not null,
  fingerprint text not null check (char_length(fingerprint) = 64),
  status text not null check (status in ('ACCEPTED','REJECTED')),
  reject_reason text check (reject_reason is null or char_length(trim(reject_reason)) between 3 and 200),
  created_at timestamptz not null default now(),
  constraint s7_opening_import_row_status_check check (
    (status = 'REJECTED' and reject_reason is not null)
    or (status = 'ACCEPTED' and reject_reason is null and account_role is not null
        and ((debit_minor_units > 0 and credit_minor_units = 0)
          or (credit_minor_units > 0 and debit_minor_units = 0)))
  ),
  unique (import_id, row_number),
  unique (import_id, fingerprint),
  unique (id, organization_id),
  foreign key (import_id, organization_id, project_id)
    references public.s7_opening_imports(id, organization_id, project_id) on delete restrict,
  foreign key (party_id, organization_id)
    references public.parties(id, organization_id) on delete restrict,
  foreign key (cash_account_id, organization_id)
    references public.project_cash_accounts(id, organization_id) on delete restrict
);
create index s7_opening_import_rows_import_idx
  on public.s7_opening_import_rows(import_id, status, row_number);

-- ---------------------------------------------------------------------------
-- 4a. Lifecycle guard. Economic facts are re-asserted on every transition so
--     no writer can rewrite an import's content while moving its status.
-- ---------------------------------------------------------------------------
create or replace function public.s7_guard_opening_import_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_allowed boolean;
begin
  if old.organization_id <> new.organization_id
     or old.project_id <> new.project_id
     or old.schema_version <> new.schema_version
     or old.source_file_checksum <> new.source_file_checksum
     or old.submitted_row_count <> new.submitted_row_count
     or old.declared_debit_total_minor_units <> new.declared_debit_total_minor_units
     or old.declared_credit_total_minor_units <> new.declared_credit_total_minor_units
     or old.prepared_by <> new.prepared_by
     or old.content_hash <> new.content_hash
     or old.idempotency_key <> new.idempotency_key then
    raise exception 'an opening import declaration is immutable; stage a new import instead';
  end if;
  if old.snapshot_content_hash is not null
     and (new.snapshot_content_hash is distinct from old.snapshot_content_hash
       or new.snapshot_payload::text is distinct from old.snapshot_payload::text) then
    raise exception 'an approved opening import snapshot is immutable';
  end if;
  if old.journal_batch_id is not null and new.journal_batch_id is distinct from old.journal_batch_id then
    raise exception 'a posted opening import cannot be relinked; correct it by linked reversal';
  end if;
  if old.status = new.status then
    return new;
  end if;
  v_allowed := (old.status, new.status) in (
    ('DRAFT','VALIDATED'),('DRAFT','REJECTED'),('DRAFT','FAILED'),
    ('VALIDATED','READY_FOR_APPROVAL'),('VALIDATED','REJECTED'),('VALIDATED','FAILED'),
    ('READY_FOR_APPROVAL','APPROVED'),('READY_FOR_APPROVAL','REJECTED'),('READY_FOR_APPROVAL','FAILED'),
    ('APPROVED','POSTED')
  );
  if not v_allowed then
    raise exception 'invalid opening import transition % -> %', old.status, new.status;
  end if;
  return new;
end $$;
create trigger s7_opening_imports_transition_guard
before update on public.s7_opening_imports
for each row execute function public.s7_guard_opening_import_transition();

create or replace function public.s7_guard_opening_import_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'opening import facts are append-only; correct by linked reversal and a new import';
end $$;
create trigger s7_opening_imports_no_delete
before delete on public.s7_opening_imports
for each row execute function public.s7_guard_opening_import_append_only();

-- Imported rows freeze the moment the batch leaves DRAFT: a validated control
-- total can never be reinterpreted afterwards.
create or replace function public.s7_guard_opening_import_row_frozen() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_status text;
begin
  select status into v_status from public.s7_opening_imports
  where id = coalesce(new.import_id, old.import_id);
  if v_status is not null and v_status <> 'DRAFT' then
    raise exception 'opening import rows are frozen once the import leaves DRAFT';
  end if;
  return coalesce(new, old);
end $$;
create trigger s7_opening_import_rows_frozen
before update or delete on public.s7_opening_import_rows
for each row execute function public.s7_guard_opening_import_row_frozen();

-- Rows must respect the same dimensional rules the journal will enforce, even
-- for a privileged direct writer.
create or replace function public.s7_guard_opening_import_row_scope() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_map record; v_project uuid;
begin
  if new.status = 'REJECTED' then
    return new;
  end if;
  select * into v_map from public.s7_opening_mapping_codes where code = new.mapping_code;
  if not found then raise exception 'unknown opening mapping code %', new.mapping_code; end if;
  if new.account_role <> v_map.account_role then
    raise exception 'opening row account role does not match its mapping code';
  end if;
  if v_map.requires_party and new.party_id is null then
    raise exception 'mapping code % requires a counterparty', new.mapping_code;
  end if;
  if not v_map.requires_party and new.party_id is not null then
    raise exception 'mapping code % does not accept a counterparty', new.mapping_code;
  end if;
  if v_map.requires_cash_account and new.cash_account_id is null then
    raise exception 'mapping code % requires a project cash account', new.mapping_code;
  end if;
  if not v_map.requires_cash_account and new.cash_account_id is not null then
    raise exception 'mapping code % does not accept a project cash account', new.mapping_code;
  end if;
  if new.cash_account_id is not null then
    select project_id into v_project from public.project_cash_accounts
    where id = new.cash_account_id and organization_id = new.organization_id;
    if v_project is null or v_project <> new.project_id then
      raise exception 'opening cash account must belong to the import organization and project';
    end if;
  end if;
  return new;
end $$;
create trigger s7_opening_import_rows_scope_guard
before insert on public.s7_opening_import_rows
for each row execute function public.s7_guard_opening_import_row_scope();

-- An opening import may only be reversed while it is still the newest material
-- posting in its project. Reversing an opening position underneath later
-- operating activity would silently invalidate every downstream balance.
create or replace function public.s7_guard_opening_import_reversal() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_original record;
begin
  if new.source_type <> 'REVERSAL' or new.reversal_of_batch_id is null then return new; end if;
  select * into v_original from public.journal_batches
  where id = new.reversal_of_batch_id and organization_id = new.organization_id;
  if not found or v_original.source_type <> 'S7_OPENING_IMPORT' then return new; end if;
  if exists (
    select 1 from public.journal_batches jb
    where jb.organization_id = v_original.organization_id
      and jb.project_id = v_original.project_id
      and jb.id <> v_original.id
      and jb.source_type <> 'REVERSAL'
      and jb.posted_at > v_original.posted_at
      and not exists (
        select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
      )
  ) then
    raise exception 'opening import has dependent later postings; reverse them first';
  end if;
  return new;
end $$;
-- Named to sort before the period-lock guard so the dependency-ordering error
-- is the one an operator actually sees, and so the invariant is provable for a
-- direct writer and not only through the RPC.
create trigger journal_batches_01_s7_opening_reversal_guard
before insert on public.journal_batches
for each row execute function public.s7_guard_opening_import_reversal();

-- ===========================================================================
-- 5. Stage an opening import (DRAFT).
--    Every row is classified in one transaction into an accepted set and a
--    rejected set with an explicit machine-readable reason. A rejected row
--    never becomes a partial financial fact because nothing posts until
--    approval, and approval refuses any import that still holds rejects.
-- ===========================================================================
create or replace function public.s7_stage_opening_import(
  p_organization_id uuid,
  p_project_id uuid,
  p_schema_version text,
  p_source_file_name text,
  p_source_file_checksum text,
  p_mapping_codes text[],
  p_party_ids uuid[],
  p_cash_account_ids uuid[],
  p_debits text[],
  p_credits text[],
  p_descriptions text[],
  p_declared_debit_total text,
  p_declared_credit_total text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_existing record; v_import uuid; v_currency text;
  v_n integer; v_i integer; v_map record;
  v_code text; v_desc text; v_debit_text text; v_credit_text text;
  v_debit bigint; v_credit bigint; v_reason text; v_role text;
  v_party uuid; v_cash uuid; v_fingerprint text; v_stored_fingerprint text; v_hash text;
  v_declared_debit bigint; v_declared_credit bigint;
  v_pairs text[] := '{}'; v_seen text[] := '{}';
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_schema_version is null or p_schema_version !~ '^S7\.OPENING\.V[0-9]{1,3}$' then
    raise exception 'unsupported opening import schema version';
  end if;
  if p_source_file_checksum is null or lower(trim(p_source_file_checksum)) !~ '^[0-9a-f]{64}$' then
    raise exception 'a sha-256 source file checksum is required';
  end if;
  if p_source_file_name is null
     or char_length(trim(p_source_file_name)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_source_file_name) then
    raise exception 'invalid source file name';
  end if;

  select reporting_currency into v_currency from public.investment_projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_currency is null then raise exception 'project not found'; end if;

  if p_mapping_codes is null or cardinality(p_mapping_codes) = 0 then
    raise exception 'at least one opening row is required';
  end if;
  v_n := cardinality(p_mapping_codes);
  if v_n > 5000 then raise exception 'opening import exceeds the 5000 row limit'; end if;
  if cardinality(p_debits) <> v_n or cardinality(p_credits) <> v_n
     or cardinality(p_descriptions) <> v_n then
    raise exception 'opening import columns length mismatch';
  end if;
  if p_party_ids is not null and cardinality(p_party_ids) <> v_n then
    raise exception 'opening import columns length mismatch';
  end if;
  if p_cash_account_ids is not null and cardinality(p_cash_account_ids) <> v_n then
    raise exception 'opening import columns length mismatch';
  end if;

  v_declared_debit := public.s7_parse_minor_units(p_declared_debit_total);
  v_declared_credit := public.s7_parse_minor_units(p_declared_credit_total);
  if v_declared_debit is null or v_declared_credit is null then
    raise exception 'declared control totals must be non-negative integers';
  end if;

  -- Canonical payload hash over the normalized rows; a retry with the same key
  -- must carry byte-identical economics or be rejected outright.
  for v_i in 1..v_n loop
    v_pairs := v_pairs || (
      upper(coalesce(public.s7_normalize_text(p_mapping_codes[v_i]), '')) || ':' ||
      coalesce((p_party_ids[v_i])::text, '') || ':' ||
      coalesce((p_cash_account_ids[v_i])::text, '') || ':' ||
      coalesce(public.s7_normalize_text(p_debits[v_i]), '') || ':' ||
      coalesce(public.s7_normalize_text(p_credits[v_i]), '') || ':' ||
      lower(coalesce(public.s7_normalize_text(p_descriptions[v_i]), ''))
    );
  end loop;
  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id,
    'schema_version', p_schema_version,
    'checksum', lower(trim(p_source_file_checksum)),
    'declared_debit', v_declared_debit,
    'declared_credit', v_declared_credit,
    'rows', array_to_string(v_pairs, '|')
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-opening-stage:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.s7_opening_imports
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.s7_opening_imports(
    organization_id, project_id, schema_version, source_file_name, source_file_checksum,
    reporting_currency, status, submitted_row_count,
    declared_debit_total_minor_units, declared_credit_total_minor_units,
    content_hash, idempotency_key, request_hash, prepared_by
  ) values (
    p_organization_id, p_project_id, p_schema_version, trim(p_source_file_name),
    lower(trim(p_source_file_checksum)), v_currency, 'DRAFT', v_n,
    v_declared_debit, v_declared_credit,
    v_hash, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_import;

  for v_i in 1..v_n loop
    v_reason := null; v_role := null; v_party := null; v_cash := null;
    v_debit := 0; v_credit := 0;
    v_code := upper(coalesce(public.s7_normalize_text(p_mapping_codes[v_i]), ''));
    v_desc := public.s7_normalize_text(p_descriptions[v_i]);
    v_debit_text := public.s7_normalize_text(p_debits[v_i]);
    v_credit_text := public.s7_normalize_text(p_credits[v_i]);

    select * into v_map from public.s7_opening_mapping_codes where code = v_code;
    if not found then
      v_reason := 'UNKNOWN_MAPPING_CODE';
    else
      v_role := v_map.account_role;
      v_party := p_party_ids[v_i];
      v_cash := p_cash_account_ids[v_i];
    end if;

    if v_reason is null and (
         v_desc is null or char_length(v_desc) > 500
         or public.s7_has_unsafe_control_characters(v_desc)) then
      v_reason := 'DESCRIPTION_INVALID';
    end if;

    if v_reason is null then
      v_debit := coalesce(public.s7_parse_minor_units(v_debit_text), -1);
      v_credit := coalesce(public.s7_parse_minor_units(v_credit_text), -1);
      if v_debit < 0 or v_credit < 0 then
        v_reason := 'INVALID_AMOUNT';
      elsif v_debit = 0 and v_credit = 0 then
        v_reason := 'NO_AMOUNT';
      elsif v_debit > 0 and v_credit > 0 then
        v_reason := 'BOTH_SIDES_SET';
      elsif (v_map.natural_side = 'DEBIT' and v_debit = 0)
         or (v_map.natural_side = 'CREDIT' and v_credit = 0) then
        v_reason := 'SIDE_CONTRADICTS_MAPPING';
      end if;
    end if;

    if v_reason is null then
      if v_map.requires_party then
        if v_party is null then
          v_reason := 'PARTY_REQUIRED';
        elsif not exists (
          select 1 from public.parties p
          where p.id = v_party and p.organization_id = p_organization_id
        ) then
          v_reason := 'PARTY_NOT_IN_ORGANIZATION';
        end if;
      elsif v_party is not null then
        v_reason := 'PARTY_NOT_ALLOWED';
      end if;
    end if;

    if v_reason is null then
      if v_map.requires_cash_account then
        if v_cash is null then
          v_reason := 'CASH_ACCOUNT_REQUIRED';
        elsif not exists (
          select 1 from public.project_cash_accounts ca
          where ca.id = v_cash and ca.organization_id = p_organization_id
            and ca.project_id = p_project_id and ca.currency = v_currency
        ) then
          v_reason := 'CASH_ACCOUNT_OUT_OF_SCOPE';
        end if;
      elsif v_cash is not null then
        v_reason := 'CASH_ACCOUNT_NOT_ALLOWED';
      end if;
    end if;

    -- Deterministic fingerprint: the same external opening fact always hashes
    -- to the same value, so re-sending a file cannot double-count a row.
    v_fingerprint := encode(digest(
      p_organization_id::text || '|' || p_project_id::text || '|' || v_code || '|' ||
      coalesce(v_party::text, '') || '|' || coalesce(v_cash::text, '') || '|' ||
      coalesce(v_debit_text, '') || '|' || coalesce(v_credit_text, '') || '|' ||
      lower(coalesce(v_desc, '')), 'sha256'), 'hex');
    if v_reason is null and v_fingerprint = any(v_seen) then
      v_reason := 'DUPLICATE_ROW_IN_FILE';
    end if;
    v_seen := v_seen || v_fingerprint;
    -- Rejected rows are stored with a row-scoped fingerprint so that two
    -- identical bad rows are both preserved for the operator's reject report.
    v_stored_fingerprint := case
      when v_reason is null then v_fingerprint
      else encode(digest(v_fingerprint || '|rejected|' || v_i::text, 'sha256'), 'hex')
    end;

    insert into public.s7_opening_import_rows(
      organization_id, project_id, import_id, row_number, mapping_code, account_role,
      party_id, cash_account_id, debit_minor_units, credit_minor_units, description,
      raw_payload, fingerprint, status, reject_reason
    ) values (
      p_organization_id, p_project_id, v_import, v_i, v_code,
      case when v_reason is null then v_role end,
      case when v_reason is null then v_party end,
      case when v_reason is null then v_cash end,
      case when v_reason is null then greatest(v_debit, 0) else 0 end,
      case when v_reason is null then greatest(v_credit, 0) else 0 end,
      left(coalesce(v_desc, '(بدون وصف)'), 500),
      jsonb_build_object(
        'mapping_code', v_code,
        'party_id', v_party,
        'cash_account_id', v_cash,
        'debit', v_debit_text,
        'credit', v_credit_text,
        'description', v_desc
      ),
      v_stored_fingerprint,
      case when v_reason is null then 'ACCEPTED' else 'REJECTED' end,
      v_reason
    );
  end loop;

  update public.s7_opening_imports i set
    accepted_row_count = (select count(*) from public.s7_opening_import_rows r
                          where r.import_id = v_import and r.status = 'ACCEPTED'),
    rejected_row_count = (select count(*) from public.s7_opening_import_rows r
                          where r.import_id = v_import and r.status = 'REJECTED')
  where i.id = v_import;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_OPENING_IMPORT_STAGED', 's7_opening_import', v_import,
    jsonb_build_object('project_id', p_project_id, 'schema_version', p_schema_version,
      'source_file_checksum', lower(trim(p_source_file_checksum)),
      'submitted_row_count', v_n, 'content_hash', v_hash));
  return v_import;
end $$;

-- ===========================================================================
-- 6. Validate an opening import (DRAFT -> VALIDATED | REJECTED).
--    Validation is the exact-reconciliation gate: rejects, internal balance,
--    and declared-vs-computed control totals must all be clean.
-- ===========================================================================
create or replace function public.s7_validate_opening_import(
  p_organization_id uuid, p_import_id uuid, p_idempotency_key text
) returns text language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_import record;
  v_debit bigint; v_credit bigint; v_mapping jsonb; v_rejects jsonb;
  v_status text; v_reason text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-opening-validate:' || p_import_id::text, 0));
  select * into v_import from public.s7_opening_imports
  where id = p_import_id and organization_id = p_organization_id for update;
  if not found then raise exception 'opening import not found'; end if;
  if v_import.status in ('VALIDATED','REJECTED') then return v_import.status; end if;
  if v_import.status <> 'DRAFT' then
    raise exception 'only a DRAFT opening import can be validated';
  end if;

  select coalesce(sum(debit_minor_units), 0), coalesce(sum(credit_minor_units), 0)
    into v_debit, v_credit
  from public.s7_opening_import_rows
  where import_id = p_import_id and status = 'ACCEPTED';

  select coalesce(jsonb_object_agg(mapping_code, detail), '{}'::jsonb) into v_mapping
  from (
    select mapping_code,
           jsonb_build_object(
             'accepted_rows', count(*),
             'debit_minor_units', sum(debit_minor_units)::text,
             'credit_minor_units', sum(credit_minor_units)::text
           ) as detail
    from public.s7_opening_import_rows
    where import_id = p_import_id and status = 'ACCEPTED'
    group by mapping_code
  ) m;

  select coalesce(jsonb_agg(jsonb_build_object('row_number', row_number, 'reason', reject_reason)
                            order by row_number), '[]'::jsonb) into v_rejects
  from public.s7_opening_import_rows
  where import_id = p_import_id and status = 'REJECTED';

  if v_import.rejected_row_count > 0 then
    v_status := 'REJECTED';
    v_reason := format('%s rejected row(s) must be corrected at source and re-imported',
                       v_import.rejected_row_count);
  elsif v_debit <= 0 or v_debit <> v_credit then
    v_status := 'REJECTED';
    v_reason := format('opening rows are unbalanced: debits %s vs credits %s', v_debit, v_credit);
  elsif v_debit <> v_import.declared_debit_total_minor_units
     or v_credit <> v_import.declared_credit_total_minor_units then
    v_status := 'REJECTED';
    v_reason := format('control totals do not reconcile: declared %s/%s vs computed %s/%s',
      v_import.declared_debit_total_minor_units, v_import.declared_credit_total_minor_units,
      v_debit, v_credit);
  else
    v_status := 'VALIDATED';
    v_reason := null;
  end if;

  update public.s7_opening_imports set
    status = v_status,
    validated_at = now(),
    computed_debit_total_minor_units = v_debit,
    computed_credit_total_minor_units = v_credit,
    debit_variance_minor_units = v_debit - v_import.declared_debit_total_minor_units,
    credit_variance_minor_units = v_credit - v_import.declared_credit_total_minor_units,
    mapping_summary = v_mapping,
    rejection_summary = v_rejects,
    failure_reason = v_reason
  where id = p_import_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_OPENING_IMPORT_VALIDATED', 's7_opening_import', p_import_id,
    jsonb_build_object('project_id', v_import.project_id, 'result', v_status,
      'accepted_row_count', v_import.accepted_row_count,
      'rejected_row_count', v_import.rejected_row_count,
      'computed_debit_total_minor_units', v_debit,
      'computed_credit_total_minor_units', v_credit,
      'reason', v_reason));
  return v_status;
end $$;

-- ===========================================================================
-- 7. Review an opening import (VALIDATED -> READY_FOR_APPROVAL).
-- ===========================================================================
create or replace function public.s7_review_opening_import(
  p_organization_id uuid, p_import_id uuid, p_review_notes text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_import record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_review_notes is not null and (char_length(trim(p_review_notes)) > 2000
     or public.s7_has_unsafe_control_characters(p_review_notes)) then
    raise exception 'invalid review notes';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-opening-review:' || p_import_id::text, 0));
  select * into v_import from public.s7_opening_imports
  where id = p_import_id and organization_id = p_organization_id for update;
  if not found then raise exception 'opening import not found'; end if;
  if v_import.status = 'READY_FOR_APPROVAL' then return v_import.id; end if;
  if v_import.status <> 'VALIDATED' then
    raise exception 'only a VALIDATED opening import can be marked ready for approval';
  end if;
  update public.s7_opening_imports set
    status = 'READY_FOR_APPROVAL', reviewed_by = v_actor, reviewed_at = now(),
    review_notes = nullif(trim(coalesce(p_review_notes, '')), '')
  where id = p_import_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_OPENING_IMPORT_REVIEWED', 's7_opening_import', p_import_id,
    jsonb_build_object('project_id', v_import.project_id,
      'accepted_row_count', v_import.accepted_row_count));
  return p_import_id;
end $$;

-- ===========================================================================
-- 8. Approve and post an opening import
--    (READY_FOR_APPROVAL -> APPROVED -> POSTED).
-- ===========================================================================
create or replace function public.s7_approve_opening_import(
  p_organization_id uuid, p_import_id uuid, p_posting_date date, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_import record; v_hash text; v_batch uuid;
  v_snapshot jsonb; v_snapshot_hash text; v_debit bigint; v_credit bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  v_hash := encode(digest(jsonb_build_object(
    'import_id', p_import_id, 'posting_date', p_posting_date)::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-opening-approve:' || p_import_id::text, 0));
  select * into v_import from public.s7_opening_imports
  where id = p_import_id and organization_id = p_organization_id for update;
  if not found then raise exception 'opening import not found'; end if;
  if v_import.status = 'POSTED' then
    if v_import.approval_idempotency_key = trim(p_idempotency_key)
       and v_import.approval_request_hash = v_hash then
      return v_import.journal_batch_id;
    end if;
    raise exception 'opening import is already posted';
  end if;
  if v_import.status <> 'READY_FOR_APPROVAL' then
    raise exception 'only an opening import that is ready for approval can be approved';
  end if;
  if exists (
    select 1 from public.s7_opening_imports other
    where other.organization_id = p_organization_id
      and other.approval_idempotency_key = trim(p_idempotency_key)
      and other.id <> p_import_id
  ) then raise exception 'idempotency key payload mismatch'; end if;

  -- No destructive overwrite: a project holds at most one active opening
  -- position. Superseding one requires an explicit linked reversal first.
  if exists (
    select 1 from public.s7_opening_imports other
    join public.journal_batches jb on jb.id = other.journal_batch_id
    where other.organization_id = p_organization_id
      and other.project_id = v_import.project_id
      and other.status = 'POSTED'
      and not exists (
        select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
      )
  ) then
    raise exception 'project already has an active posted opening import; reverse it first';
  end if;

  perform public.s7_require_postable_date(p_organization_id, v_import.project_id, p_posting_date);

  select coalesce(sum(debit_minor_units), 0), coalesce(sum(credit_minor_units), 0)
    into v_debit, v_credit
  from public.s7_opening_import_rows
  where import_id = p_import_id and status = 'ACCEPTED';
  if v_debit <= 0 or v_debit <> v_credit then
    raise exception 'opening import does not reconcile exactly; approval refused';
  end if;
  if v_debit <> v_import.declared_debit_total_minor_units
     or v_credit <> v_import.declared_credit_total_minor_units then
    raise exception 'opening import control totals changed since validation; approval refused';
  end if;
  if v_import.rejected_row_count > 0 then
    raise exception 'opening import still has rejected rows; approval refused';
  end if;

  select jsonb_build_object(
    'import_id', p_import_id,
    'project_id', v_import.project_id,
    'schema_version', v_import.schema_version,
    'source_file_checksum', v_import.source_file_checksum,
    'reporting_currency', v_import.reporting_currency,
    'posting_date', p_posting_date,
    'accepted_row_count', v_import.accepted_row_count,
    'debit_total_minor_units', v_debit::text,
    'credit_total_minor_units', v_credit::text,
    'mapping_summary', v_import.mapping_summary,
    'rows', coalesce(jsonb_agg(jsonb_build_object(
      'row_number', r.row_number,
      'mapping_code', r.mapping_code,
      'account_role', r.account_role,
      'party_id', r.party_id,
      'cash_account_id', r.cash_account_id,
      'debit_minor_units', r.debit_minor_units::text,
      'credit_minor_units', r.credit_minor_units::text,
      'fingerprint', r.fingerprint
    ) order by r.row_number), '[]'::jsonb)
  ) into v_snapshot
  from public.s7_opening_import_rows r
  where r.import_id = p_import_id and r.status = 'ACCEPTED';
  v_snapshot_hash := encode(digest(v_snapshot::text, 'sha256'), 'hex');

  update public.s7_opening_imports set
    status = 'APPROVED', approved_by = v_actor, approved_at = now(),
    posting_date = p_posting_date,
    snapshot_payload = v_snapshot, snapshot_content_hash = v_snapshot_hash,
    snapshot_captured_at = now(),
    approval_idempotency_key = trim(p_idempotency_key), approval_request_hash = v_hash
  where id = p_import_id;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_import.project_id, 'S7_OPENING_IMPORT', p_import_id, p_posting_date,
    trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency, cash_account_id, party_id, transaction_date
  )
  select v_batch, p_organization_id, v_import.project_id, sa.id,
    r.debit_minor_units, r.credit_minor_units, v_import.reporting_currency,
    r.cash_account_id, r.party_id, p_posting_date
  from public.s7_opening_import_rows r
  join public.semantic_accounts sa on sa.role = r.account_role
  where r.import_id = p_import_id and r.status = 'ACCEPTED'
  order by r.row_number;

  update public.s7_opening_imports set status = 'POSTED', journal_batch_id = v_batch
  where id = p_import_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_OPENING_IMPORT_POSTED', 's7_opening_import', p_import_id,
    jsonb_build_object('project_id', v_import.project_id, 'posting_date', p_posting_date,
      'journal_batch_id', v_batch, 'snapshot_content_hash', v_snapshot_hash,
      'debit_total_minor_units', v_debit, 'credit_total_minor_units', v_credit));
  return v_batch;
end $$;

-- ===========================================================================
-- 9. Reject an opening import explicitly (operator decision).
-- ===========================================================================
create or replace function public.s7_reject_opening_import(
  p_organization_id uuid, p_import_id uuid, p_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_import record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 2000
     or public.s7_has_unsafe_control_characters(p_reason) then
    raise exception 'a rejection reason is required';
  end if;
  select * into v_import from public.s7_opening_imports
  where id = p_import_id and organization_id = p_organization_id for update;
  if not found then raise exception 'opening import not found'; end if;
  if v_import.status = 'REJECTED' then return p_import_id; end if;
  if v_import.status in ('POSTED','APPROVED','FAILED') then
    raise exception 'a posted or closed opening import cannot be rejected; use linked reversal';
  end if;
  update public.s7_opening_imports set status = 'REJECTED', failure_reason = trim(p_reason)
  where id = p_import_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_OPENING_IMPORT_REJECTED', 's7_opening_import', p_import_id,
    jsonb_build_object('project_id', v_import.project_id, 'reason', trim(p_reason)));
  return p_import_id;
end $$;

-- ===========================================================================
-- 10. Read models. Bigint money leaves as text; free text leaves export-safe.
-- ===========================================================================
create or replace view public.s7_opening_imports_read with (security_invoker=on) as
select
  i.id as import_id,
  i.organization_id,
  i.project_id,
  i.schema_version,
  public.s7_export_safe_text(i.source_file_name) as source_file_name,
  i.source_file_checksum,
  i.reporting_currency,
  i.status,
  i.submitted_row_count,
  i.accepted_row_count,
  i.rejected_row_count,
  i.declared_debit_total_minor_units::text as declared_debit_total_minor_units,
  i.declared_credit_total_minor_units::text as declared_credit_total_minor_units,
  i.computed_debit_total_minor_units::text as computed_debit_total_minor_units,
  i.computed_credit_total_minor_units::text as computed_credit_total_minor_units,
  i.debit_variance_minor_units::text as debit_variance_minor_units,
  i.credit_variance_minor_units::text as credit_variance_minor_units,
  (i.debit_variance_minor_units = 0 and i.credit_variance_minor_units = 0
    and i.status in ('VALIDATED','READY_FOR_APPROVAL','APPROVED','POSTED')) as control_totals_match,
  i.mapping_summary,
  i.rejection_summary,
  public.s7_export_safe_text(i.failure_reason) as failure_reason,
  i.prepared_by,
  i.prepared_at,
  i.validated_at,
  i.reviewed_by,
  i.reviewed_at,
  i.approved_by,
  i.approved_at,
  i.posting_date,
  i.journal_batch_id,
  i.snapshot_content_hash,
  i.snapshot_captured_at,
  i.content_hash,
  exists (
    select 1 from public.journal_batches rb where rb.reversal_of_batch_id = i.journal_batch_id
  ) as is_reversed
from public.s7_opening_imports i;

create or replace view public.s7_opening_import_rows_read with (security_invoker=on) as
select
  r.id as row_id,
  r.organization_id,
  r.project_id,
  r.import_id,
  r.row_number,
  r.mapping_code,
  m.label_ar as mapping_label,
  r.account_role,
  r.party_id,
  p.legal_name as party_legal_name,
  r.cash_account_id,
  r.debit_minor_units::text as debit_minor_units,
  r.credit_minor_units::text as credit_minor_units,
  public.s7_export_safe_text(r.description) as description,
  r.status,
  r.reject_reason,
  r.fingerprint
from public.s7_opening_import_rows r
left join public.s7_opening_mapping_codes m on m.code = r.mapping_code
left join public.parties p on p.id = r.party_id and p.organization_id = r.organization_id;

create or replace view public.s7_opening_mapping_codes_read with (security_invoker=on) as
select code, account_role, label_ar, natural_side, requires_party, requires_cash_account
from public.s7_opening_mapping_codes;

-- ===========================================================================
-- 11. Default-deny RLS and exact command permissions.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['s7_opening_imports','s7_opening_import_rows'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t || '_read', t);
    execute format('revoke all on public.%I from anon,authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- The mapping registry is non-tenant reference data: readable, never writable
-- by a client role, and locked against every writer by trigger.
revoke all on public.s7_opening_mapping_codes from anon, authenticated;
grant select on public.s7_opening_mapping_codes to authenticated;

grant select on public.s7_opening_imports_read, public.s7_opening_import_rows_read,
  public.s7_opening_mapping_codes_read to authenticated;

revoke all on function public.s7_normalize_text(text) from public, anon, authenticated;
revoke all on function public.s7_has_unsafe_control_characters(text) from public, anon, authenticated;
revoke all on function public.s7_parse_minor_units(text) from public, anon, authenticated;
revoke all on function public.s7_export_safe_text(text) from public, anon;
revoke all on function public.s7_stage_opening_import(uuid,uuid,text,text,text,text[],uuid[],uuid[],text[],text[],text[],text,text,text) from public, anon;
revoke all on function public.s7_validate_opening_import(uuid,uuid,text) from public, anon;
revoke all on function public.s7_review_opening_import(uuid,uuid,text,text) from public, anon;
revoke all on function public.s7_approve_opening_import(uuid,uuid,date,text) from public, anon;
revoke all on function public.s7_reject_opening_import(uuid,uuid,text,text) from public, anon;

grant execute on function
  public.s7_export_safe_text(text),
  public.s7_stage_opening_import(uuid,uuid,text,text,text,text[],uuid[],uuid[],text[],text[],text[],text,text,text),
  public.s7_validate_opening_import(uuid,uuid,text),
  public.s7_review_opening_import(uuid,uuid,text,text),
  public.s7_approve_opening_import(uuid,uuid,date,text),
  public.s7_reject_opening_import(uuid,uuid,text,text)
to authenticated;
