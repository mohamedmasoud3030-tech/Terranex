-- Controlled manual adjustment entry (additive).
--
-- Adds one journal source type, MANUAL_ADJUSTMENT, and one owner-only command
-- that posts a balanced, single-currency reclassification between a closed
-- list of ledger roles. It goes through the same journal tables, balance guard,
-- open-period guard, immutability triggers and reverse_journal_batch as every
-- other posting, so period close and reversal keep working unchanged.
--
-- Cash, payables, receivables, revenue, capital and distribution roles are NOT
-- postable by hand: those facts must come from their own commands and evidence.
-- Nothing here deletes or rewrites existing rows.

alter table public.journal_batches drop constraint if exists journal_batches_source_type_check;
alter table public.journal_batches add constraint journal_batches_source_type_check check (source_type in (
  'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT','REVERSAL',
  'PROPERTY_SALE_RECOGNITION','PROPERTY_SALE_COLLECTION',
  'S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT',
  'S7_OPENING_IMPORT','AGRICULTURE_SALE_RECOGNITION','AGRICULTURE_SALE_COLLECTION',
  'LIVESTOCK_SALE_RECOGNITION','LIVESTOCK_SALE_COLLECTION',
  'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION','SUPPLIER_ADVANCE_APPLICATION',
  'PROPERTY_RENTAL_RECOGNITION','PROPERTY_RENTAL_COLLECTION',
  'MANUAL_ADJUSTMENT'
));

create table if not exists public.manual_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null,
  entry_date date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  memo text not null check (char_length(trim(memo)) between 5 and 500),
  evidence_reference text not null check (char_length(trim(evidence_reference)) between 3 and 200),
  journal_batch_id uuid not null,
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict,
  foreign key (journal_batch_id, organization_id)
    references public.journal_batches(id, organization_id) on delete restrict
);
alter table public.manual_adjustments enable row level security;
alter table public.manual_adjustments force row level security;
drop policy if exists manual_adjustments_member_read on public.manual_adjustments;
create policy manual_adjustments_member_read on public.manual_adjustments
  for select to authenticated using (public.is_active_member(organization_id));
revoke all on public.manual_adjustments from public, anon, authenticated;
grant select on public.manual_adjustments to authenticated;

create or replace function public.post_manual_adjustment(
  p_organization_id uuid,
  p_project_id uuid,
  p_entry_date date,
  p_currency text,
  p_memo text,
  p_evidence_reference text,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_project_currency text;
  v_hash text; v_existing record;
  v_id uuid := gen_random_uuid(); v_batch uuid := gen_random_uuid();
  v_line jsonb; v_role text; v_side text; v_amount bigint; v_account uuid;
  v_debit bigint := 0; v_credit bigint := 0; v_count int := 0;
  v_allowed text[] := array['PROJECT_EXPENSE','DEVELOPMENT_WIP','PREPAID_ASSET'];
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_memo is null or char_length(trim(p_memo)) not between 5 and 500 then raise exception 'memo required'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then
    raise exception 'evidence reference required';
  end if;
  if p_entry_date is null or p_entry_date > current_date then raise exception 'invalid entry date'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 2 and 20 then
    raise exception 'between 2 and 20 lines required';
  end if;

  select reporting_currency into v_project_currency from public.investment_projects
   where id = p_project_id and organization_id = p_organization_id;
  if v_project_currency is null then raise exception 'project not found'; end if;
  if p_currency <> v_project_currency then raise exception 'currency must match project reporting currency'; end if;

  v_hash := public.r5_sha256(jsonb_build_object(
    'project_id', p_project_id, 'entry_date', p_entry_date, 'currency', p_currency,
    'memo', trim(p_memo), 'evidence', trim(p_evidence_reference), 'lines', p_lines
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':manual-adjustment:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.manual_adjustments
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  -- Validate every line before writing anything.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_role := v_line->>'account_role';
    v_side := v_line->>'side';
    if v_role is null or not (v_role = any (v_allowed)) then
      raise exception 'account role not postable by hand';
    end if;
    if v_side not in ('DEBIT','CREDIT') then raise exception 'side must be DEBIT or CREDIT'; end if;
    begin
      v_amount := (v_line->>'amount_minor_units')::bigint;
    exception when others then raise exception 'invalid amount';
    end;
    if v_amount is null or v_amount <= 0 then raise exception 'amount must be positive'; end if;
    if v_side = 'DEBIT' then v_debit := v_debit + v_amount; else v_credit := v_credit + v_amount; end if;
    v_count := v_count + 1;
  end loop;
  if v_debit <> v_credit or v_debit <= 0 then raise exception 'entry must balance'; end if;

  insert into public.journal_batches(
    id, organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    v_batch, p_organization_id, p_project_id, 'MANUAL_ADJUSTMENT', v_id, p_entry_date,
    'manual-adjustment-batch-' || v_id::text, v_hash, v_actor
  );
  -- All lines in one statement so the statement-level balance guard sees them together.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units, credit_minor_units,
    currency, transaction_date
  )
  select v_batch, p_organization_id, p_project_id, sa.id,
         case when l->>'side' = 'DEBIT' then (l->>'amount_minor_units')::bigint else 0 end,
         case when l->>'side' = 'CREDIT' then (l->>'amount_minor_units')::bigint else 0 end,
         p_currency, p_entry_date
  from jsonb_array_elements(p_lines) l
  join public.semantic_accounts sa on sa.role = l->>'account_role';

  insert into public.manual_adjustments(
    id, organization_id, project_id, entry_date, currency, memo, evidence_reference,
    journal_batch_id, idempotency_key, request_hash, created_by
  ) values (
    v_id, p_organization_id, p_project_id, p_entry_date, p_currency, trim(p_memo),
    trim(p_evidence_reference), v_batch, trim(p_idempotency_key), v_hash, v_actor
  );
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'MANUAL_ADJUSTMENT_POSTED', 'manual_adjustment', v_id,
    jsonb_build_object('project_id', p_project_id, 'journal_batch_id', v_batch,
      'currency', p_currency, 'line_count', v_count, 'total_minor_units', v_debit));
  return v_id;
end $$;

revoke all on function public.post_manual_adjustment(uuid,uuid,date,text,text,text,jsonb,text) from public, anon;
grant execute on function public.post_manual_adjustment(uuid,uuid,date,text,text,text,jsonb,text) to authenticated;
