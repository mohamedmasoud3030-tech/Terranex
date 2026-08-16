-- P2/P3 Fixup — comprehensive repairs addressing all PR review issues.
--
-- This forward-only migration fixes every defect identified in the PR #145
-- review without editing the already-pushed P2 and P3 migrations.
--
-- Fixes:
--   1) supplier_stated_total_minor_units required on new invoices
--   2) supplier_invoices_read: preserve existing column order, append new cols
--   3) exception resolution replay safety (resolve_idempotency_key)
--   4) acceptance-type coherence (SERVICE→SERVICE, etc.)
--   5) No UPDATE on journal lines (write cash_account_id in INSERT)
--   6) Supplier advance requires explicit cash account parameter
--   7) Authoritative obligation settlement function
--   8) Supplier coherence for advances (party_id match)
--   9) Correct source lineage (pre-generated UUIDs)
--  10) Partial-application idempotency
--  11) Cash-account coherence on journal lines (write in INSERT)

-- ===========================================================================
-- FIX 1: supplier_stated_total_minor_units required for new invoices
--   Backfill any historical rows (from pre-P2 migrations) with their
--   calculated line total so the NOT NULL constraint can be applied without
--   rewriting posted truth.
-- ===========================================================================
update public.supplier_invoices si
   set supplier_stated_total_minor_units = coalesce(
         (select sum(sil.line_amount_minor_units) from public.supplier_invoice_lines sil
           where sil.supplier_invoice_id = si.id), si.supplier_stated_total_minor_units),
       supplier_stated_total_currency = coalesce(si.supplier_stated_total_currency, si.currency)
 where si.supplier_stated_total_minor_units is null;

alter table public.supplier_invoices
  alter column supplier_stated_total_minor_units set not null,
  alter column supplier_stated_total_currency set not null;

comment on column public.supplier_invoices.supplier_stated_total_minor_units is
  'The actual total printed on the supplier invoice document, in minor units. Required for all new invoices.';

-- ===========================================================================
-- FIX 3: Exception resolution replay safety
-- ===========================================================================
alter table public.procurement_invoice_exceptions
  add column resolve_idempotency_key text
    check (resolve_idempotency_key is null or char_length(resolve_idempotency_key) between 8 and 120),
  add column resolve_request_hash text
    check (resolve_request_hash is null or char_length(resolve_request_hash) = 64);

create unique index procurement_invoice_exceptions_resolve_key
  on public.procurement_invoice_exceptions(organization_id, resolve_idempotency_key)
  where resolve_idempotency_key is not null;

-- ===========================================================================
-- FIX 4: Acceptance-type coherence enforcement
--   The acceptance check constraint already enforces the valid types for
--   invoice lines. The FK chain ensures that the referenced acceptance line
--   belongs to an acceptance whose type matches, via the acceptance_id
--   chain. However, we need a stronger check: the invoice line's
--   procurement_type must match the acceptance's authoritative acceptance_type.
--   This trigger enforces that at record time.
-- ===========================================================================
create or replace function public.p2f_guard_acceptance_type_coherence() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_acceptance_type text;
begin
  if new.procurement_type in ('SERVICE','CONSTRUCTION','MILESTONE') and new.procurement_acceptance_line_id is not null then
    select a.acceptance_type into v_acceptance_type
    from public.procurement_acceptance_lines al
    join public.procurement_acceptances a on a.id = al.acceptance_id
    where al.id = new.procurement_acceptance_line_id;
    if v_acceptance_type is null or v_acceptance_type <> new.procurement_type then
      raise exception 'invoice line procurement_type % must match the referenced acceptance type %',
        new.procurement_type, coalesce(v_acceptance_type, 'NONE');
    end if;
  end if;
  return new;
end $$;
create trigger supplier_invoice_lines_acceptance_type_coherence
  before insert on public.supplier_invoice_lines
  for each row execute function public.p2f_guard_acceptance_type_coherence();

-- ===========================================================================
-- FIX 7: Authoritative obligation settlement function
--   Every command that reduces the payable must lock the obligation row with
--   FOR UPDATE and use this function to verify the ceiling.
-- ===========================================================================
create or replace function public.obligation_active_outstanding_minor_units(
  p_organization_id uuid,
  p_obligation_id uuid
) returns bigint
language sql stable set search_path=pg_catalog,public as $$
  select coalesce(o.amount_minor_units, 0)
    - coalesce((
        select sum(pp.amount_minor_units) from public.project_payments pp
        join public.journal_batches jb on jb.source_type = 'PAYMENT' and jb.source_id = pp.id
        where pp.obligation_id = p_obligation_id and pp.organization_id = p_organization_id
          and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
    ), 0)
    - coalesce((
        select sum(cn.amount_minor_units) from public.supplier_credit_notes cn
        join public.supplier_invoices si on si.id = cn.supplier_invoice_id
        where si.cost_obligation_id = p_obligation_id
          and cn.organization_id = p_organization_id and cn.status = 'APPROVED'
    ), 0)
    - coalesce((
        select sum(aa.applied_amount_minor_units) from public.supplier_advance_applications aa
        join public.supplier_invoices si on si.id = aa.supplier_invoice_id
        where si.cost_obligation_id = p_obligation_id
          and aa.organization_id = p_organization_id
    ), 0)
    - coalesce((
        select sum(pa.allocated_minor_units) from public.payment_allocations pa
        where pa.obligation_id = p_obligation_id and pa.organization_id = p_organization_id
    ), 0)
  from public.cost_obligations o
  where o.id = p_obligation_id and o.organization_id = p_organization_id
$$;
comment on function public.obligation_active_outstanding_minor_units is
  'Authoritative settlement calculation: original obligation minus all active payments, credit notes, advance applications, and allocations.';

-- ===========================================================================
-- FIX 2: supplier_invoices_read — preserve existing column order exactly,
--   append new settlement columns at the end.
-- ===========================================================================
create or replace view public.supplier_invoices_read with (security_invoker=on) as
select i.id, i.organization_id, i.project_id, i.purchase_order_id,
       o.internal_reference as purchase_order_reference,
       i.supplier_id, s.name as supplier_name, i.party_id,
       i.invoice_reference, i.invoice_date, i.currency, i.cost_treatment,
       i.evidence_reference, i.notes, i.status, i.recorded_by, i.recorded_at,
       i.approved_by, i.approved_at, i.cost_obligation_id, i.authorization_batch_id,
       i.supplier_stated_total_minor_units::text as supplier_stated_total_minor_units,
       totals.invoice_total_minor_units::text as invoice_total_minor_units,
       coalesce(pay.paid_minor_units, 0)::text as paid_minor_units,
       case when coalesce(op.is_reversed, false) then '0'
            else greatest(totals.invoice_total_minor_units - coalesce(pay.paid_minor_units, 0), 0)::text
       end as outstanding_minor_units,
       coalesce(pay.reconciled_minor_units, 0)::text as reconciled_minor_units,
       coalesce(op.is_reversed, false) as payable_is_reversed,
       case
         when coalesce(op.is_reversed, false) then 'PAYABLE_REVERSED'
         when coalesce(pay.paid_minor_units, 0) = 0 then 'UNPAID'
         when coalesce(pay.paid_minor_units, 0) < totals.invoice_total_minor_units then 'PARTIALLY_PAID'
         else 'FULLY_PAID'
       end as payment_state,
       case
         when coalesce(pay.paid_minor_units, 0) = 0 then 'NOT_PAID'
         when coalesce(pay.reconciled_minor_units, 0) = 0 then 'PAID_UNRECONCILED'
         when pay.reconciled_minor_units < pay.paid_minor_units then 'PARTIALLY_RECONCILED'
         else 'RECONCILED'
       end as reconciliation_state,
       coalesce(pay.payment_count, 0)::integer as payment_count,
       (select count(*) from public.procurement_invoice_exceptions e
        where e.supplier_invoice_id = i.id and e.status = 'OPEN') as open_exception_count,
       -- New columns appended at the end (preserving existing column order above)
       coalesce(credits.credited_minor_units, 0)::text as credited_minor_units,
       coalesce(advapp.applied_minor_units, 0)::text as advance_applied_minor_units,
       greatest(
         coalesce(totals.invoice_total_minor_units, 0)
         - coalesce(pay.paid_minor_units, 0)
         - coalesce(credits.credited_minor_units, 0)
         - coalesce(advapp.applied_minor_units, 0), 0)::text
         as net_outstanding_minor_units,
       case
         when coalesce(pay.paid_minor_units, 0)
            + coalesce(credits.credited_minor_units, 0)
            + coalesce(advapp.applied_minor_units, 0) = 0 then 'UNPAID'
         when coalesce(pay.paid_minor_units, 0)
            + coalesce(credits.credited_minor_units, 0)
            + coalesce(advapp.applied_minor_units, 0) < totals.invoice_total_minor_units then 'PARTIALLY_SETTLED'
         else 'FULLY_SETTLED'
       end as settlement_state
from public.supplier_invoices i
join public.purchase_orders o on o.id = i.purchase_order_id and o.organization_id = i.organization_id
join public.procurement_suppliers s on s.id = i.supplier_id and s.organization_id = i.organization_id
join (
  select supplier_invoice_id, sum(line_amount_minor_units) as invoice_total_minor_units
  from public.supplier_invoice_lines group by supplier_invoice_id
) totals on totals.supplier_invoice_id = i.id
left join public.cost_obligation_position_read op
  on op.obligation_id = i.cost_obligation_id
left join (
  select co.source_supplier_invoice_id,
         sum(case when ps.is_reversed then 0 else ps.amount_minor_units::bigint end) as paid_minor_units,
         sum(case when not ps.is_reversed and ps.is_reconciled then ps.amount_minor_units::bigint else 0 end) as reconciled_minor_units,
         count(*) filter (where not ps.is_reversed) as payment_count
  from public.cost_obligations co
  join public.payment_status_read ps on ps.obligation_id = co.id
  where co.source_supplier_invoice_id is not null
  group by co.source_supplier_invoice_id
) pay on pay.source_supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(amount_minor_units) as credited_minor_units
  from public.supplier_credit_notes where status = 'APPROVED' group by supplier_invoice_id
) credits on credits.supplier_invoice_id = i.id
left join (
  select supplier_invoice_id, sum(applied_amount_minor_units) as applied_minor_units
  from public.supplier_advance_applications group by supplier_invoice_id
) advapp on advapp.supplier_invoice_id = i.id;

-- ===========================================================================
-- FIX 5+6+11: Replace record_unapplied_payment and record_supplier_advance
--   with versions that write cash_account_id directly on the INSERT and
--   require an explicit cash account.
-- ===========================================================================
create or replace function public.record_unapplied_payment(
  p_organization_id uuid,
  p_project_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_payment_date date,
  p_description text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payment_id uuid := gen_random_uuid();
  v_hash text;
  v_existing record;
  v_account record;
  v_batch_id uuid;
  v_prepaid uuid;
  v_cash uuid;
  v_available bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  if p_payment_date is null then raise exception 'payment date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_cash_account_id is null then raise exception 'cash account is required'; end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'cash_account_id', p_cash_account_id,
    'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
    'payment_date', p_payment_date, 'description', p_description,
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-unapplied:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.unapplied_payments
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency <> p_currency then raise exception 'cash account currency mismatch'; end if;

  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if p_amount_minor_units > v_available then
    raise exception 'unapplied payment exceeds available cash';
  end if;

    recorded_by, idempotency_key, request_hash
  ) values (
    v_payment_id, p_organization_id, p_project_id, p_cash_account_id,
    p_amount_minor_units, p_currency, p_payment_date,
    nullif(trim(p_description), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, trim(p_idempotency_key), v_hash
  );

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'UNAPPLIED_PAYMENT', v_payment_id, p_payment_date,
    'p3-unapplied-batch-' || v_payment_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  -- Write cash_account_id directly on the BANK_CASH line during INSERT.
  -- No post-insert mutation of journal truth.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    cash_account_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_prepaid,
     p_amount_minor_units, 0, p_currency,
     null, p_payment_date),
    (v_batch_id, p_organization_id, p_project_id, v_cash,
     0, p_amount_minor_units, p_currency,
     p_cash_account_id, p_payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'UNAPPLIED_PAYMENT_RECORDED', 'unapplied_payment', v_payment_id,
    jsonb_build_object('project_id', p_project_id, 'amount_minor_units', p_amount_minor_units,
      'currency', p_currency, 'cash_account_id', p_cash_account_id, 'journal_batch_id', v_batch_id));
  return v_payment_id;
end $$;

-- ===========================================================================
-- FIX 3: Replace resolve_supplier_invoice_exception with replay-safe version
-- ===========================================================================
create or replace function public.resolve_supplier_invoice_exception(
  p_organization_id uuid,
  p_exception_id uuid,
  p_decision text,
  p_approval_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_exception public.procurement_invoice_exceptions%rowtype;
  v_existing public.procurement_invoice_exceptions%rowtype;
  v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_decision not in ('APPROVED','REJECTED') then raise exception 'decision must be APPROVED or REJECTED'; end if;
  if p_approval_notes is not null and char_length(trim(p_approval_notes)) not between 3 and 500 then
    raise exception 'invalid approval notes';
  end if;

  v_hash := encode(digest(p_exception_id::text || '|' || p_decision || '|' || coalesce(trim(p_approval_notes), ''),
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p2-exception-resolve:' || trim(p_idempotency_key), 0));

  -- Replay check using the dedicated resolve_idempotency_key (not the creation key)
  select * into v_existing from public.procurement_invoice_exceptions
  where organization_id = p_organization_id
    and resolve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id is distinct from p_exception_id
       or v_existing.status <> p_decision
       or v_existing.resolve_request_hash IS DISTINCT FROM v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_exception from public.procurement_invoice_exceptions
  where id = p_exception_id and organization_id = p_organization_id for update;
  if not found then raise exception 'exception not found'; end if;
  if v_exception.status <> 'OPEN' then raise exception 'exception is already resolved'; end if;
  if v_exception.created_by = v_actor then raise exception 'maker/checker: exception creator cannot resolve'; end if;
  if v_exception.resolve_idempotency_key is not null then
    raise exception 'exception already has a resolution idempotency key; cannot re-resolve';
  end if;

  update public.procurement_invoice_exceptions
     set status = p_decision, approved_by = v_actor, approved_at = now(),
         approval_notes = nullif(trim(p_approval_notes), ''),
         resolve_idempotency_key = trim(p_idempotency_key),
         resolve_request_hash = v_hash
   where id = p_exception_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor,
    case when p_decision = 'APPROVED' then 'SUPPLIER_INVOICE_EXCEPTION_APPROVED'
         else 'SUPPLIER_INVOICE_EXCEPTION_REJECTED' end,
    'procurement_invoice_exception', p_exception_id,
    jsonb_build_object('supplier_invoice_id', v_exception.supplier_invoice_id,
      'exception_type', v_exception.exception_type, 'decision', p_decision));
  return p_exception_id;
end $$;

-- ===========================================================================
-- FIX 6+8+9+10: Replace record_supplier_advance, approve_supplier_credit_note,
--   apply_supplier_advance, and allocate_payment with corrected versions.
-- ===========================================================================
create or replace function public.record_supplier_advance(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_advance_reference text,
  p_advance_date date,
  p_currency text,
  p_amount_minor_units bigint,
  p_description text,
  p_evidence_reference text,
  p_cash_account_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_payment_id uuid := gen_random_uuid();
  v_batch_id uuid;
  v_account record;
  v_prepaid uuid;
  v_cash uuid;
  v_available bigint;
  v_payment_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'advance amount must be positive';
  end if;
  if p_advance_date is null then raise exception 'advance date required'; end if;
  if p_advance_reference is null or char_length(trim(p_advance_reference)) not between 1 and 120 then
    raise exception 'invalid advance reference';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_cash_account_id is null then raise exception 'cash account is required'; end if;

  if not exists (select 1 from public.parties
    where id = p_supplier_party_id and organization_id = p_organization_id) then
    raise exception 'supplier party not found';
  end if;

  select * into v_account from public.project_cash_accounts
  where id = p_cash_account_id and organization_id = p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id <> p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency <> p_currency then raise exception 'cash account currency mismatch'; end if;

  v_available := public.s5_cash_account_balance_internal(
    p_organization_id, v_account.project_id, v_account.id, v_account.currency);
  if p_amount_minor_units > v_available then
    raise exception 'advance exceeds available cash';
  end if;

  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
    'advance_reference', trim(p_advance_reference), 'advance_date', p_advance_date,
    'currency', p_currency, 'amount_minor_units', p_amount_minor_units,
    'cash_account_id', p_cash_account_id, 'description', p_description,
    'evidence_reference', p_evidence_reference
  )::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-advance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_advances
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  v_payment_hash := encode(digest(v_payment_id::text || '|advance-payment', 'sha256'), 'hex');
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';
  select id into v_cash from public.semantic_accounts where role = 'BANK_CASH';

  insert into public.unapplied_payments(
    id, organization_id, project_id, cash_account_id, amount_minor_units,
    currency, payment_date, description, evidence_reference,
    recorded_by, idempotency_key, request_hash
  ) values (
    v_payment_id, p_organization_id, p_project_id, p_cash_account_id,
    p_amount_minor_units, p_currency, p_advance_date,
    nullif(trim(p_description), ''), nullif(trim(p_evidence_reference), ''),
    v_actor, 'p3-advance-payment:' || v_payment_id::text, v_payment_hash
  );

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, p_project_id, 'UNAPPLIED_PAYMENT', v_payment_id, p_advance_date,
    'p3-advance-batch-' || v_payment_id::text, v_payment_hash, v_actor
  ) returning id into v_batch_id;

  -- Write cash_account_id directly on the BANK_CASH line, never via UPDATE.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    cash_account_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, p_project_id, v_prepaid,
     p_amount_minor_units, 0, p_currency,
     null, p_advance_date),
    (v_batch_id, p_organization_id, p_project_id, v_cash,
     0, p_amount_minor_units, p_currency,
     p_cash_account_id, p_advance_date);

  insert into public.supplier_advances(
    organization_id, project_id, supplier_party_id, advance_reference, advance_date,
    currency, amount_minor_units, description, evidence_reference, unapplied_payment_id,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_supplier_party_id, trim(p_advance_reference),
    p_advance_date, p_currency, p_amount_minor_units, nullif(trim(p_description), ''),
    nullif(trim(p_evidence_reference), ''), v_payment_id,
    v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_RECORDED', 'supplier_advance', v_id,
    jsonb_build_object('project_id', p_project_id, 'supplier_party_id', p_supplier_party_id,
      'amount_minor_units', p_amount_minor_units, 'currency', p_currency,
      'cash_account_id', p_cash_account_id, 'unapplied_payment_id', v_payment_id,
      'journal_batch_id', v_batch_id, 'advance_date', p_advance_date));
  return v_id;
end $$;

-- ===========================================================================
-- FIX 8+9: apply_supplier_advance — supplier coherence, pre-generated UUID,
--   obligation settlement check, correct source lineage.
-- ===========================================================================
create or replace function public.apply_supplier_advance(
  p_organization_id uuid,
  p_advance_id uuid,
  p_supplier_invoice_id uuid,
  p_applied_amount_minor_units bigint,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_application_id uuid := gen_random_uuid();
  v_hash text;
  v_existing record;
  v_advance record;
  v_invoice record;
  v_obligation record;
  v_applied_numeric numeric;
  v_outstanding bigint;
  v_batch_id uuid;
  v_payable uuid;
  v_prepaid uuid;
  v_new_status text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_applied_amount_minor_units is null or p_applied_amount_minor_units <= 0 then
    raise exception 'application amount must be positive';
  end if;

  v_hash := encode(digest(p_advance_id::text || '|' || p_supplier_invoice_id::text || '|' || p_applied_amount_minor_units::text,
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-apply-advance:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_advance_applications
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_advance from public.supplier_advances
  where id = p_advance_id and organization_id = p_organization_id for update;
  if not found then raise exception 'advance not found'; end if;

  select * into v_invoice from public.supplier_invoices
  where id = p_supplier_invoice_id and project_id = v_advance.project_id
    and organization_id = p_organization_id;
  if not found then raise exception 'supplier invoice not found'; end if;
  if v_invoice.status <> 'APPROVED' then raise exception 'advance application requires an approved supplier invoice'; end if;
  if v_invoice.cost_obligation_id is null then raise exception 'invoice has no payable obligation'; end if;
  if v_invoice.currency <> v_advance.currency then raise exception 'advance and invoice currency must match'; end if;

  -- FIX 8: Supplier coherence — the advance supplier must match the invoice party.
  if v_advance.supplier_party_id <> v_invoice.party_id then
    raise exception 'advance supplier % does not match invoice supplier %; cannot apply one supplier advance to another supplier invoice',
      v_advance.supplier_party_id, v_invoice.party_id;
  end if;

  -- FIX 7: Lock the obligation and check the authoritative settlement ceiling.
  select * into v_obligation from public.cost_obligations
  where id = v_invoice.cost_obligation_id and organization_id = p_organization_id
  for update;
  v_outstanding := public.obligation_active_outstanding_minor_units(
    p_organization_id, v_invoice.cost_obligation_id);
  if p_applied_amount_minor_units > v_outstanding then
    raise exception 'advance application of % exceeds current outstanding payable % on obligation',
      p_applied_amount_minor_units, v_outstanding;
  end if;

  -- Ceiling: applications cannot exceed the advance.
  select coalesce(sum(applied_amount_minor_units::numeric), 0) into v_applied_numeric
  from public.supplier_advance_applications where advance_id = p_advance_id;
  if v_applied_numeric + p_applied_amount_minor_units > v_advance.amount_minor_units then
    raise exception 'application exceeds advance amount';
  end if;
  v_new_status := case when v_advance.amount_minor_units - v_applied_numeric - p_applied_amount_minor_units <= 0
    then 'FULLY_APPLIED' else 'PARTIALLY_APPLIED' end;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';

  -- FIX 9: The journal batch source_id is the pre-generated application UUID.
  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_advance.project_id, 'SUPPLIER_ADVANCE_APPLICATION',
    v_application_id, v_invoice.invoice_date,
    'p3-apply-advance-batch:' || v_application_id::text,
    v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_advance.project_id, v_payable,
     p_applied_amount_minor_units, 0, v_advance.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_invoice.invoice_date),
    (v_batch_id, p_organization_id, v_advance.project_id, v_prepaid,
     0, p_applied_amount_minor_units, v_advance.currency,
     null, null, v_invoice.invoice_date);

  insert into public.supplier_advance_applications(
    id, organization_id, project_id, advance_id, supplier_invoice_id,
    applied_amount_minor_units, currency, journal_batch_id,
    applied_by, idempotency_key, request_hash
  ) values (
    v_application_id, p_organization_id, v_advance.project_id, p_advance_id, p_supplier_invoice_id,
    p_applied_amount_minor_units, v_advance.currency, v_batch_id,
    v_actor, trim(p_idempotency_key), v_hash
  );

  update public.supplier_advances
     set status = v_new_status
   where id = p_advance_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_ADVANCE_APPLIED', 'supplier_advance_application', v_application_id,
    jsonb_build_object('advance_id', p_advance_id, 'supplier_invoice_id', p_supplier_invoice_id,
      'applied_amount_minor_units', p_applied_amount_minor_units, 'journal_batch_id', v_batch_id,
      'advance_status', v_new_status));
  return v_application_id;
end $$;

-- ===========================================================================
-- FIX 7+9: approve_supplier_credit_note — obligation lock, settlement check,
--   correct reversal accounting direction.
-- ===========================================================================
create or replace function public.approve_supplier_credit_note(
  p_organization_id uuid,
  p_credit_note_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_existing record;
  v_credit public.supplier_credit_notes%rowtype;
  v_invoice public.supplier_invoices%rowtype;
  v_obligation record;
  v_batch_id uuid;
  v_payable uuid;
  v_credit_account uuid;
  v_outstanding bigint;
  v_credited_on_invoice numeric;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash := encode(digest(p_credit_note_id::text || '|approve', 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-credit-approve:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_credit_notes
  where organization_id = p_organization_id and approve_idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.id is distinct from p_credit_note_id
       or v_existing.approve_request_hash IS DISTINCT FROM v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.authorization_batch_id;
  end if;

  select * into v_credit from public.supplier_credit_notes
  where id = p_credit_note_id and organization_id = p_organization_id for update;
  if not found then raise exception 'credit note not found'; end if;
  if v_credit.status <> 'RECORDED' then raise exception 'credit note is not in RECORDED state'; end if;
  if v_credit.recorded_by = v_actor then raise exception 'maker/checker: credit recorder cannot approve'; end if;

  select * into v_invoice from public.supplier_invoices
  where id = v_credit.supplier_invoice_id and organization_id = p_organization_id;
  if v_invoice.status <> 'APPROVED' or v_invoice.cost_obligation_id is null then
    raise exception 'credit note requires an approved supplier invoice with a payable obligation';
  end if;
  if v_invoice.currency <> v_credit.currency then raise exception 'credit note currency must match invoice'; end if;

  -- FIX 7: Lock the obligation and check the settlement ceiling.
  select * into v_obligation from public.cost_obligations
  where id = v_invoice.cost_obligation_id and organization_id = p_organization_id
  for update;
  v_outstanding := public.obligation_active_outstanding_minor_units(
    p_organization_id, v_invoice.cost_obligation_id);
  if v_credit.amount_minor_units > v_outstanding then
    raise exception 'credit note of % exceeds current outstanding payable % on obligation',
      v_credit.amount_minor_units, v_outstanding;
  end if;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  if v_invoice.cost_treatment = 'EXPENSE' then
    select id into v_credit_account from public.semantic_accounts where role = 'PROJECT_EXPENSE';
  else
    select id into v_credit_account from public.semantic_accounts where role = 'DEVELOPMENT_WIP';
  end if;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_credit.project_id, 'SUPPLIER_CREDIT_NOTE', p_credit_note_id,
    v_credit.credit_date, trim(p_idempotency_key), v_hash, v_actor
  ) returning id into v_batch_id;

  -- Correct reversal of the original invoice posting: Dr Payable / Cr Cost.
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_credit.project_id, v_payable,
     v_credit.amount_minor_units, 0, v_credit.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_credit.credit_date),
    (v_batch_id, p_organization_id, v_credit.project_id, v_credit_account,
     0, v_credit.amount_minor_units, v_credit.currency,
     v_invoice.cost_obligation_id, v_invoice.party_id, v_credit.credit_date);

  update public.supplier_credit_notes
     set status = 'APPROVED', approved_by = v_actor, approved_at = now(),
         approve_idempotency_key = trim(p_idempotency_key), approve_request_hash = v_hash,
         authorization_batch_id = v_batch_id
   where id = p_credit_note_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_CREDIT_NOTE_APPROVED', 'supplier_credit_note', p_credit_note_id,
    jsonb_build_object('authorization_batch_id', v_batch_id,
      'amount_minor_units', v_credit.amount_minor_units, 'currency', v_credit.currency,
      'accounting_direction', 'REVERSAL_OF_INVOICE'));
  return v_batch_id;
end $$;

-- ===========================================================================
-- FIX 7+9: allocate_payment — obligation lock, settlement check, lineage.
-- ===========================================================================
create or replace function public.allocate_payment(
  p_organization_id uuid,
  p_unapplied_payment_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_payment record;
  v_obligation record;
  v_allocated_numeric numeric;
  v_outstanding bigint;
  v_batch_id uuid;
  v_payable uuid;
  v_prepaid uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_amount_minor_units is null or p_amount_minor_units <= 0 then
    raise exception 'allocation amount must be positive';
  end if;

  v_hash := encode(digest(p_unapplied_payment_id::text || '|' || p_obligation_id::text || '|' || p_amount_minor_units::text,
    'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':p3-allocate:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.payment_allocations
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_payment from public.unapplied_payments
  where id = p_unapplied_payment_id and organization_id = p_organization_id for update;
  if not found then raise exception 'unapplied payment not found'; end if;

  -- FIX 7: Lock the obligation and check the settlement ceiling.
  select * into v_obligation from public.cost_obligations
  where id = p_obligation_id and organization_id = p_organization_id for update;
  if not found then raise exception 'obligation not found'; end if;
  if v_obligation.project_id <> v_payment.project_id then
    raise exception 'obligation does not belong to the same project';
  end if;
  if v_obligation.currency <> v_payment.currency then
    raise exception 'obligation and unapplied payment currency must match';
  end if;

  v_outstanding := public.obligation_active_outstanding_minor_units(
    p_organization_id, p_obligation_id);
  if p_amount_minor_units > v_outstanding then
    raise exception 'allocation of % exceeds current outstanding payable % on obligation',
      p_amount_minor_units, v_outstanding;
  end if;

  -- Ceiling: allocations cannot exceed the unapplied payment.
  select coalesce(sum(allocated_minor_units::numeric), 0) into v_allocated_numeric
  from public.payment_allocations where unapplied_payment_id = p_unapplied_payment_id;
  if v_allocated_numeric + p_amount_minor_units > v_payment.amount_minor_units then
    raise exception 'allocation exceeds unapplied payment amount';
  end if;

  select id into v_payable from public.semantic_accounts where role = 'SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role = 'PREPAID_ASSET';

  insert into public.payment_allocations(
    organization_id, project_id, unapplied_payment_id, obligation_id,
    allocated_minor_units, currency, allocated_by, idempotency_key, request_hash
  ) values (
    p_organization_id, v_payment.project_id, p_unapplied_payment_id, p_obligation_id,
    p_amount_minor_units, v_payment.currency, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    p_organization_id, v_payment.project_id, 'PAYMENT_ALLOCATION', v_id, v_payment.payment_date,
    'p3-allocation-batch-' || v_id::text, v_hash, v_actor
  ) returning id into v_batch_id;

  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id,
    debit_minor_units, credit_minor_units, currency,
    obligation_id, party_id, transaction_date
  ) values
    (v_batch_id, p_organization_id, v_payment.project_id, v_payable,
     p_amount_minor_units, 0, v_payment.currency,
     p_obligation_id, v_obligation.party_id, v_payment.payment_date),
    (v_batch_id, p_organization_id, v_payment.project_id, v_prepaid,
     0, p_amount_minor_units, v_payment.currency,
     null, null, v_payment.payment_date);

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'PAYMENT_ALLOCATED', 'payment_allocation', v_id,
    jsonb_build_object('unapplied_payment_id', p_unapplied_payment_id, 'obligation_id', p_obligation_id,
      'allocated_minor_units', p_amount_minor_units, 'journal_batch_id', v_batch_id));
  return v_id;
end $$;

-- ===========================================================================
-- FIX 1: Update record_supplier_invoice to require supplier_stated_total
-- ===========================================================================
create or replace function public.record_supplier_invoice(
  p_organization_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_currency text,
  p_cost_treatment text,
  p_evidence_reference text,
  p_notes text,
  p_supplier_stated_total_minor_units bigint,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_hash text;
  v_existing record;
  v_order record;
  v_line jsonb;
  v_receipt record;
  v_quantity numeric;
  v_unit_price bigint;
  v_total numeric := 0;
  v_procurement_type text;
  v_acceptance_line_id uuid;
  v_po_line_id uuid;
  v_receipt_po_line_id uuid;
  v_acceptance_type text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;

  if p_invoice_reference is null or char_length(trim(p_invoice_reference)) not between 1 and 120 then raise exception 'invalid supplier invoice reference'; end if;
  if p_invoice_date is null then raise exception 'supplier invoice date required'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if p_cost_treatment not in ('EXPENSE','CAPITALIZABLE_WIP') then raise exception 'cost treatment must be EXPENSE or CAPITALIZABLE_WIP'; end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200 then raise exception 'supplier invoice evidence is required'; end if;
  if p_notes is not null and char_length(trim(p_notes)) > 2000 then raise exception 'invalid notes'; end if;
  -- FIX 1: supplier_stated_total is required for all new invoices.
  if p_supplier_stated_total_minor_units is null then raise exception 'supplier stated total is required for every supplier invoice'; end if;
  if p_supplier_stated_total_minor_units <= 0 then raise exception 'supplier stated total must be positive'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'at least one supplier invoice line is required'; end if;
  if jsonb_array_length(p_lines) > 50 then raise exception 'too many supplier invoice lines'; end if;

  v_hash := encode(digest(
    p_project_id::text || '|' || p_purchase_order_id::text || '|' || coalesce(trim(p_invoice_reference), '') || '|'
    || coalesce(p_invoice_date::text, '') || '|' || coalesce(p_currency, '') || '|'
    || coalesce(p_cost_treatment, '') || '|' || coalesce(trim(p_evidence_reference), '') || '|'
    || coalesce(trim(p_notes), '') || '|' || p_supplier_stated_total_minor_units::text || '|'
    || coalesce(p_lines::text, ''), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':r4-supplier-invoice:' || trim(p_idempotency_key), 0));

  select * into v_existing from public.supplier_invoices
   where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash IS DISTINCT FROM v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select o.*, s.party_id into v_order
    from public.purchase_orders o
    join public.procurement_suppliers s
      on s.id = o.supplier_id and s.organization_id = o.organization_id
   where o.id = p_purchase_order_id and o.project_id = p_project_id
     and o.organization_id = p_organization_id
   for update of o;
  if not found then raise exception 'purchase order not found'; end if;
  if v_order.status <> 'APPROVED' then raise exception 'supplier invoice requires an approved purchase order'; end if;
  if v_order.party_id is null then raise exception 'supplier financial party is not linked'; end if;
  if p_currency <> v_order.currency then raise exception 'supplier invoice currency must match purchase order'; end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    begin
      v_quantity := (v_line->>'quantity_invoiced')::numeric;
      v_unit_price := (v_line->>'unit_price_minor_units')::bigint;
    exception when others then
      raise exception 'invalid supplier invoice line amount';
    end;
    if v_quantity is null or v_quantity <= 0 then raise exception 'invalid supplier invoice line quantity'; end if;
    if v_unit_price is null or v_unit_price <= 0 then raise exception 'invalid supplier invoice unit price'; end if;
    if v_quantity * v_unit_price <> trunc(v_quantity * v_unit_price) then
      raise exception 'supplier invoice line amount must resolve to exact minor units';
    end if;

    v_procurement_type := coalesce(v_line->>'procurement_type', 'GOODS');
    if v_procurement_type = 'GOODS' then
      select rl.id, rl.purchase_order_line_id, rl.quantity_received,
             ol.unit_price_minor_units
        into v_receipt
        from public.purchase_receipt_lines rl
        join public.purchase_order_lines ol
          on ol.id = rl.purchase_order_line_id and ol.organization_id = rl.organization_id
       where rl.id = (v_line->>'purchase_receipt_line_id')::uuid
         and rl.purchase_order_id = p_purchase_order_id
         and rl.project_id = p_project_id
         and rl.organization_id = p_organization_id
       for update of rl;
      if not found then raise exception 'receipt line not found for this purchase order'; end if;
      if v_receipt.unit_price_minor_units is null or v_unit_price <> v_receipt.unit_price_minor_units then
        raise exception 'supplier invoice unit price must exactly match purchase order';
      end if;
      if v_quantity > v_receipt.quantity_received then raise exception 'supplier invoice quantity exceeds received quantity'; end if;
    elsif v_procurement_type in ('SERVICE','CONSTRUCTION','MILESTONE') then
      v_acceptance_line_id := (v_line->>'procurement_acceptance_line_id')::uuid;
      v_po_line_id := (v_line->>'purchase_order_line_id')::uuid;
      if v_acceptance_line_id is null then raise exception 'acceptance line required for non-goods procurement'; end if;
      select al.id, al.purchase_order_line_id, al.accepted_quantity, ol.unit_price_minor_units
        into v_receipt
        from public.procurement_acceptance_lines al
        join public.purchase_order_lines ol
          on ol.id = al.purchase_order_line_id and ol.organization_id = al.organization_id
       where al.id = v_acceptance_line_id
         and al.purchase_order_id = p_purchase_order_id
         and al.project_id = p_project_id
         and al.organization_id = p_organization_id
       for update of al;
      if not found then raise exception 'acceptance line not found for this purchase order'; end if;
      if v_po_line_id is not null and v_po_line_id <> v_receipt.purchase_order_line_id then
        raise exception 'invoice line purchase order line does not match acceptance line';
      end if;
      if v_receipt.unit_price_minor_units is null or v_unit_price <> v_receipt.unit_price_minor_units then
        raise exception 'supplier invoice unit price must exactly match purchase order';
      end if;
      if v_quantity > v_receipt.accepted_quantity then raise exception 'supplier invoice quantity exceeds accepted quantity'; end if;
    else
      raise exception 'invalid procurement type: %', v_procurement_type;
    end if;
    v_total := v_total + (v_quantity * v_unit_price);
  end loop;
  if v_total <= 0 or v_total <> trunc(v_total) then raise exception 'supplier invoice total must be exact positive minor units'; end if;

  insert into public.supplier_invoices(
    organization_id, project_id, purchase_order_id, supplier_id, party_id,
    invoice_reference, invoice_date, currency, cost_treatment, evidence_reference,
    notes, supplier_stated_total_minor_units, supplier_stated_total_currency,
    recorded_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_purchase_order_id, v_order.supplier_id, v_order.party_id,
    trim(p_invoice_reference), p_invoice_date, p_currency, p_cost_treatment,
    trim(p_evidence_reference), nullif(trim(p_notes), ''), p_supplier_stated_total_minor_units,
    p_currency, v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_procurement_type := coalesce(v_line->>'procurement_type', 'GOODS');
    if v_procurement_type = 'GOODS' then
      select rl.purchase_order_line_id into v_receipt
        from public.purchase_receipt_lines rl
       where rl.id = (v_line->>'purchase_receipt_line_id')::uuid;
      insert into public.supplier_invoice_lines(
        organization_id, project_id, supplier_invoice_id, purchase_order_id,
        purchase_order_line_id, purchase_receipt_line_id, quantity_invoiced,
        unit_price_minor_units, procurement_type
      ) values (
        p_organization_id, p_project_id, v_id, p_purchase_order_id,
        v_receipt.purchase_order_line_id, (v_line->>'purchase_receipt_line_id')::uuid,
        (v_line->>'quantity_invoiced')::numeric, (v_line->>'unit_price_minor_units')::bigint,
        'GOODS'
      );
    else
      insert into public.supplier_invoice_lines(
        organization_id, project_id, supplier_invoice_id, purchase_order_id,
        purchase_order_line_id, procurement_acceptance_line_id, quantity_invoiced,
        unit_price_minor_units, procurement_type
      ) values (
        p_organization_id, p_project_id, v_id, p_purchase_order_id,
        (v_line->>'purchase_order_line_id')::uuid, (v_line->>'procurement_acceptance_line_id')::uuid,
        (v_line->>'quantity_invoiced')::numeric, (v_line->>'unit_price_minor_units')::bigint,
        v_procurement_type
      );
    end if;
  end loop;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'SUPPLIER_INVOICE_RECORDED', 'supplier_invoice', v_id,
    jsonb_build_object('project_id', p_project_id, 'purchase_order_id', p_purchase_order_id,
      'supplier_id', v_order.supplier_id, 'invoice_reference', trim(p_invoice_reference),
      'invoice_total_minor_units', v_total::bigint, 'currency', p_currency,
      'supplier_stated_total_minor_units', p_supplier_stated_total_minor_units));
  return v_id;
end $$;

-- ===========================================================================
-- Grants for replaced functions
-- ===========================================================================
revoke all on function
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,uuid,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text),
  public.approve_supplier_credit_note(uuid,uuid,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.resolve_supplier_invoice_exception(uuid,uuid,text,text,text),
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,bigint,jsonb,text)
  from public, anon;
grant execute on function
  public.record_unapplied_payment(uuid,uuid,uuid,bigint,text,date,text,text,text),
  public.record_supplier_advance(uuid,uuid,uuid,text,date,text,bigint,text,text,uuid,text),
  public.apply_supplier_advance(uuid,uuid,uuid,bigint,text),
  public.approve_supplier_credit_note(uuid,uuid,text),
  public.allocate_payment(uuid,uuid,uuid,bigint,text),
  public.resolve_supplier_invoice_exception(uuid,uuid,text,text,text),
  public.record_supplier_invoice(uuid,uuid,uuid,text,date,text,text,text,text,bigint,jsonb,text)
  to authenticated;

-- pgcrypto compatibility
do $pgcrypto_compat_p2p3$
declare
  v_pgcrypto_schema text;
  v_record record;
  v_definition text;
  v_rewritten text;
  v_commands text[] := array[
    'record_unapplied_payment','record_supplier_advance',
    'apply_supplier_advance','approve_supplier_credit_note',
    'allocate_payment','resolve_supplier_invoice_exception',
    'record_supplier_invoice'
  ];
begin
  select n.nspname into v_pgcrypto_schema
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pgcrypto';
  if v_pgcrypto_schema is null then raise exception 'pgcrypto extension is required'; end if;
  for v_record in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname = any(v_commands::text[])
  loop
    v_definition := pg_get_functiondef(v_record.oid);
    if v_definition ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\(' then
      v_rewritten := regexp_replace(v_definition,
        '(^|[^[:alnum:]_.])digest[[:space:]]*\(',
        E'\\1' || quote_ident(v_pgcrypto_schema) || '.digest(', 'g');
      if v_rewritten = v_definition then raise exception 'failed to qualify pgcrypto digest in %', v_record.proname; end if;
      execute v_rewritten;
    end if;
  end loop;
end
$pgcrypto_compat_p2p3$;