-- P3 — authoritative settlement commands and mixed-settlement concurrency.

-- Active outstanding payable: original authorized obligation less every active
-- settlement fact. Reversed settlement batches no longer reduce outstanding.
create or replace function public.obligation_active_outstanding_minor_units(
  p_organization_id uuid,
  p_obligation_id uuid
) returns bigint
language sql stable set search_path=pg_catalog,public as $$
  select o.amount_minor_units
    - coalesce((
        select sum(pp.amount_minor_units)
        from public.project_payments pp
        join public.journal_batches jb
          on jb.source_type='PAYMENT' and jb.source_id=pp.id
        where pp.organization_id=p_organization_id
          and pp.obligation_id=p_obligation_id
          and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
      ),0)
    - coalesce((
        select sum(pa.allocated_minor_units)
        from public.payment_allocations pa
        where pa.organization_id=p_organization_id
          and pa.obligation_id=p_obligation_id
          and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=pa.journal_batch_id)
      ),0)
    - coalesce((
        select sum(sa.applied_amount_minor_units)
        from public.supplier_advance_applications sa
        where sa.organization_id=p_organization_id
          and sa.obligation_id=p_obligation_id
          and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=sa.journal_batch_id)
      ),0)
    - coalesce((
        select sum(cn.amount_minor_units)
        from public.supplier_credit_notes cn
        where cn.organization_id=p_organization_id
          and cn.obligation_id=p_obligation_id
          and cn.status='APPROVED'
          and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=cn.authorization_batch_id)
      ),0)
  from public.cost_obligations o
  where o.organization_id=p_organization_id and o.id=p_obligation_id
$$;

-- One active posting per P3 business source, matching the existing S2 rule.
create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in (
    'CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT',
    'SUPPLIER_CREDIT_NOTE','UNAPPLIED_PAYMENT','PAYMENT_ALLOCATION','SUPPLIER_ADVANCE_APPLICATION'
  ) then
    if exists(
      select 1 from public.journal_batches jb
      where jb.source_type=new.source_type
        and jb.source_id=new.source_id
        and jb.organization_id=new.organization_id
        and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=jb.id)
    ) then raise exception 'source already has an active posting'; end if;
  end if;
  return new;
end $$;

-- Ordinary supplier payments must share the same serialization boundary as
-- credits/allocations/advance applications. The existing payment command also
-- locks the obligation; this trigger is defence in depth for every writer.
create or replace function public.p3_guard_project_payment_settlement() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_outstanding bigint;
begin
  perform 1 from public.cost_obligations
   where id=new.obligation_id and organization_id=new.organization_id
   for update;
  if not found then raise exception 'obligation not found'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(new.organization_id,new.obligation_id);
  if v_outstanding is null or new.amount_minor_units>v_outstanding then
    raise exception 'payment exceeds current outstanding payable';
  end if;
  return new;
end $$;
create trigger p3_project_payment_settlement_guard
before insert on public.project_payments
for each row execute function public.p3_guard_project_payment_settlement();

create or replace function public.record_unapplied_payment(
  p_organization_id uuid,
  p_project_id uuid,
  p_party_id uuid,
  p_cash_account_id uuid,
  p_amount_minor_units bigint,
  p_currency text,
  p_payment_date date,
  p_description text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid();
  v_id uuid:=gen_random_uuid();
  v_batch_id uuid:=gen_random_uuid();
  v_hash text;
  v_existing public.unapplied_payments%rowtype;
  v_account public.project_cash_accounts%rowtype;
  v_prepaid uuid; v_cash uuid; v_available bigint;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'payment amount must be positive'; end if;
  if p_payment_date is null then raise exception 'payment date required'; end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' then raise exception 'invalid currency'; end if;
  if not exists(select 1 from public.parties p where p.id=p_party_id and p.organization_id=p_organization_id) then raise exception 'payment party not found'; end if;

  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'party_id',p_party_id,'cash_account_id',p_cash_account_id,
    'amount_minor_units',p_amount_minor_units,'currency',p_currency,'payment_date',p_payment_date,
    'description',p_description,'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-unapplied:'||trim(p_idempotency_key),0));
  select * into v_existing from public.unapplied_payments
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_account from public.project_cash_accounts
   where id=p_cash_account_id and organization_id=p_organization_id for update;
  if not found then raise exception 'cash account not found'; end if;
  if v_account.project_id<>p_project_id then raise exception 'cash account does not belong to project'; end if;
  if v_account.currency<>p_currency then raise exception 'cash account currency mismatch'; end if;
  v_available:=public.s5_cash_account_balance_internal(p_organization_id,p_project_id,p_cash_account_id,p_currency);
  if p_amount_minor_units>v_available then raise exception 'unapplied payment exceeds available cash'; end if;

  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  select id into v_cash from public.semantic_accounts where role='BANK_CASH';
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,p_project_id,'UNAPPLIED_PAYMENT',v_id,p_payment_date,
    'p3-unapplied-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,cash_account_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,p_project_id,v_prepaid,p_amount_minor_units,0,p_currency,null,p_party_id,p_payment_date),
    (v_batch_id,p_organization_id,p_project_id,v_cash,0,p_amount_minor_units,p_currency,p_cash_account_id,p_party_id,p_payment_date);
  insert into public.unapplied_payments(id,organization_id,project_id,party_id,cash_account_id,amount_minor_units,currency,payment_date,
    description,evidence_reference,journal_batch_id,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_party_id,p_cash_account_id,p_amount_minor_units,p_currency,p_payment_date,
    nullif(trim(p_description),''),nullif(trim(p_evidence_reference),''),v_batch_id,v_actor,trim(p_idempotency_key),v_hash);
  insert into public.audit_events(organization_id,actor_id,event_type,entity_type,entity_id,payload)
  values(p_organization_id,v_actor,'UNAPPLIED_PAYMENT_RECORDED','unapplied_payment',v_id,
    jsonb_build_object('project_id',p_project_id,'party_id',p_party_id,'amount_minor_units',p_amount_minor_units,'currency',p_currency,'journal_batch_id',v_batch_id));
  return v_id;
end $$;

create or replace function public.allocate_payment(
  p_organization_id uuid,
  p_unapplied_payment_id uuid,
  p_obligation_id uuid,
  p_amount_minor_units bigint,
  p_allocation_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.payment_allocations%rowtype; v_payment public.unapplied_payments%rowtype;
  v_obligation public.cost_obligations%rowtype; v_used bigint; v_outstanding bigint;
  v_payable uuid; v_prepaid uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'allocation amount must be positive'; end if;
  if p_allocation_date is null then raise exception 'allocation date required'; end if;
  v_hash:=encode(digest(p_unapplied_payment_id::text||'|'||p_obligation_id::text||'|'||p_amount_minor_units::text||'|'||p_allocation_date::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-allocate:'||trim(p_idempotency_key),0));
  select * into v_existing from public.payment_allocations
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_payment from public.unapplied_payments
   where id=p_unapplied_payment_id and organization_id=p_organization_id for update;
  if not found then raise exception 'unapplied payment not found'; end if;
  if exists(select 1 from public.supplier_advances a where a.unapplied_payment_id=v_payment.id) then
    raise exception 'supplier advance payments must be applied through the supplier advance command';
  end if;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_payment.journal_batch_id) then raise exception 'unapplied payment is reversed'; end if;

  select * into v_obligation from public.cost_obligations
   where id=p_obligation_id and organization_id=p_organization_id for update;
  if not found or v_obligation.status<>'AUTHORIZED' then raise exception 'authorized obligation required'; end if;
  if v_obligation.project_id<>v_payment.project_id then raise exception 'project mismatch'; end if;
  if v_obligation.party_id<>v_payment.party_id then raise exception 'payment beneficiary does not match obligation supplier'; end if;
  if v_obligation.currency<>v_payment.currency then raise exception 'currency mismatch'; end if;

  select coalesce(sum(pa.allocated_minor_units),0) into v_used
   from public.payment_allocations pa
   where pa.unapplied_payment_id=v_payment.id
     and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=pa.journal_batch_id);
  if v_used+p_amount_minor_units>v_payment.amount_minor_units then raise exception 'allocation exceeds unapplied payment balance'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(p_organization_id,p_obligation_id);
  if v_outstanding is null or p_amount_minor_units>v_outstanding then raise exception 'allocation exceeds current outstanding payable'; end if;

  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_obligation.project_id,'PAYMENT_ALLOCATION',v_id,p_allocation_date,
    'p3-allocation-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_obligation.project_id,v_payable,p_amount_minor_units,0,v_obligation.currency,v_obligation.id,v_obligation.party_id,p_allocation_date),
    (v_batch_id,p_organization_id,v_obligation.project_id,v_prepaid,0,p_amount_minor_units,v_obligation.currency,null,v_obligation.party_id,p_allocation_date);
  insert into public.payment_allocations(id,organization_id,project_id,unapplied_payment_id,obligation_id,allocated_minor_units,currency,
    allocation_date,journal_batch_id,allocated_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,v_obligation.project_id,v_payment.id,v_obligation.id,p_amount_minor_units,v_obligation.currency,
    p_allocation_date,v_batch_id,v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.record_supplier_advance(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_party_id uuid,
  p_cash_account_id uuid,
  p_advance_reference text,
  p_advance_date date,
  p_currency text,
  p_amount_minor_units bigint,
  p_description text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_advances%rowtype; v_payment_id uuid; v_child_key text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_advance_reference is null or char_length(trim(p_advance_reference)) not between 1 and 120 then raise exception 'invalid advance reference'; end if;
  if not exists(select 1 from public.parties where id=p_supplier_party_id and organization_id=p_organization_id) then raise exception 'supplier party not found'; end if;
  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'supplier_party_id',p_supplier_party_id,'cash_account_id',p_cash_account_id,
    'advance_reference',trim(p_advance_reference),'advance_date',p_advance_date,'currency',p_currency,
    'amount_minor_units',p_amount_minor_units,'description',p_description,'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-advance:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_advances where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  v_child_key:='p3advpay:'||substr(v_hash,1,32);
  v_payment_id:=public.record_unapplied_payment(p_organization_id,p_project_id,p_supplier_party_id,p_cash_account_id,
    p_amount_minor_units,p_currency,p_advance_date,p_description,p_evidence_reference,v_child_key);
  insert into public.supplier_advances(id,organization_id,project_id,supplier_party_id,unapplied_payment_id,advance_reference,advance_date,
    amount_minor_units,currency,description,evidence_reference,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_supplier_party_id,v_payment_id,trim(p_advance_reference),p_advance_date,
    p_amount_minor_units,p_currency,nullif(trim(p_description),''),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.apply_supplier_advance(
  p_organization_id uuid,
  p_advance_id uuid,
  p_supplier_invoice_id uuid,
  p_applied_amount_minor_units bigint,
  p_application_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_batch_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_advance_applications%rowtype; v_advance public.supplier_advances%rowtype;
  v_invoice public.supplier_invoices%rowtype; v_obligation public.cost_obligations%rowtype;
  v_used bigint; v_outstanding bigint; v_payable uuid; v_prepaid uuid; v_payment_batch uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_applied_amount_minor_units is null or p_applied_amount_minor_units<=0 then raise exception 'application amount must be positive'; end if;
  if p_application_date is null then raise exception 'application date required'; end if;
  v_hash:=encode(digest(p_advance_id::text||'|'||p_supplier_invoice_id::text||'|'||p_applied_amount_minor_units::text||'|'||p_application_date::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-apply:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_advance_applications
   where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  select * into v_advance from public.supplier_advances where id=p_advance_id and organization_id=p_organization_id for update;
  if not found then raise exception 'advance not found'; end if;
  select up.journal_batch_id into v_payment_batch from public.unapplied_payments up where up.id=v_advance.unapplied_payment_id;
  if exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=v_payment_batch) then raise exception 'advance payment is reversed'; end if;
  select * into v_invoice from public.supplier_invoices where id=p_supplier_invoice_id and organization_id=p_organization_id;
  if not found or v_invoice.status<>'APPROVED' or v_invoice.cost_obligation_id is null then raise exception 'approved supplier invoice with payable required'; end if;
  if v_invoice.project_id<>v_advance.project_id then raise exception 'project mismatch'; end if;
  if v_invoice.party_id<>v_advance.supplier_party_id then raise exception 'supplier mismatch'; end if;
  if v_invoice.currency<>v_advance.currency then raise exception 'currency mismatch'; end if;

  select * into v_obligation from public.cost_obligations where id=v_invoice.cost_obligation_id and organization_id=p_organization_id for update;
  if not found or v_obligation.status<>'AUTHORIZED' then raise exception 'authorized obligation required'; end if;
  select coalesce(sum(a.applied_amount_minor_units),0) into v_used from public.supplier_advance_applications a
   where a.advance_id=v_advance.id and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=a.journal_batch_id);
  if v_used+p_applied_amount_minor_units>v_advance.amount_minor_units then raise exception 'application exceeds advance balance'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(p_organization_id,v_obligation.id);
  if v_outstanding is null or p_applied_amount_minor_units>v_outstanding then raise exception 'application exceeds current outstanding payable'; end if;

  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  select id into v_prepaid from public.semantic_accounts where role='PREPAID_ASSET';
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_obligation.project_id,'SUPPLIER_ADVANCE_APPLICATION',v_id,p_application_date,
    'p3-advance-app-batch:'||v_id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_obligation.project_id,v_payable,p_applied_amount_minor_units,0,v_obligation.currency,v_obligation.id,v_obligation.party_id,p_application_date),
    (v_batch_id,p_organization_id,v_obligation.project_id,v_prepaid,0,p_applied_amount_minor_units,v_obligation.currency,null,v_obligation.party_id,p_application_date);
  insert into public.supplier_advance_applications(id,organization_id,project_id,advance_id,supplier_invoice_id,obligation_id,
    applied_amount_minor_units,currency,application_date,journal_batch_id,applied_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,v_obligation.project_id,v_advance.id,v_invoice.id,v_obligation.id,
    p_applied_amount_minor_units,v_obligation.currency,p_application_date,v_batch_id,v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.record_supplier_credit_note(
  p_organization_id uuid,
  p_project_id uuid,
  p_supplier_invoice_id uuid,
  p_credit_reference text,
  p_credit_date date,
  p_currency text,
  p_amount_minor_units bigint,
  p_reason text,
  p_evidence_reference text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_id uuid:=gen_random_uuid(); v_hash text;
  v_existing public.supplier_credit_notes%rowtype; v_invoice public.supplier_invoices%rowtype;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  if p_amount_minor_units is null or p_amount_minor_units<=0 then raise exception 'credit amount must be positive'; end if;
  if p_credit_reference is null or char_length(trim(p_credit_reference)) not between 1 and 120 then raise exception 'invalid credit reference'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'credit reason required'; end if;
  v_hash:=encode(digest(jsonb_build_object(
    'project_id',p_project_id,'supplier_invoice_id',p_supplier_invoice_id,'credit_reference',trim(p_credit_reference),
    'credit_date',p_credit_date,'currency',p_currency,'amount_minor_units',p_amount_minor_units,
    'reason',trim(p_reason),'evidence_reference',p_evidence_reference)::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-credit:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_credit_notes where organization_id=p_organization_id and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;
  select * into v_invoice from public.supplier_invoices where id=p_supplier_invoice_id and organization_id=p_organization_id;
  if not found or v_invoice.project_id<>p_project_id or v_invoice.status<>'APPROVED' or v_invoice.cost_obligation_id is null then
    raise exception 'approved supplier invoice with payable required';
  end if;
  if v_invoice.currency<>p_currency then raise exception 'credit currency must match invoice'; end if;
  insert into public.supplier_credit_notes(id,organization_id,project_id,supplier_invoice_id,obligation_id,credit_reference,
    credit_date,currency,amount_minor_units,reason,evidence_reference,recorded_by,idempotency_key,request_hash)
  values(v_id,p_organization_id,p_project_id,p_supplier_invoice_id,v_invoice.cost_obligation_id,trim(p_credit_reference),
    p_credit_date,p_currency,p_amount_minor_units,trim(p_reason),nullif(trim(p_evidence_reference),''),v_actor,trim(p_idempotency_key),v_hash);
  return v_id;
end $$;

create or replace function public.approve_supplier_credit_note(
  p_organization_id uuid,
  p_credit_note_id uuid,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_hash text; v_credit public.supplier_credit_notes%rowtype;
  v_existing public.supplier_credit_notes%rowtype; v_invoice public.supplier_invoices%rowtype;
  v_obligation public.cost_obligations%rowtype; v_batch_id uuid:=gen_random_uuid();
  v_outstanding bigint; v_payable uuid; v_cost uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then raise exception 'invalid idempotency key'; end if;
  v_hash:=encode(digest(p_credit_note_id::text||'|approve','sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':p3-credit-approve:'||trim(p_idempotency_key),0));
  select * into v_existing from public.supplier_credit_notes
   where organization_id=p_organization_id and approve_idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.id<>p_credit_note_id or v_existing.approve_request_hash is distinct from v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.authorization_batch_id;
  end if;
  select * into v_credit from public.supplier_credit_notes where id=p_credit_note_id and organization_id=p_organization_id for update;
  if not found or v_credit.status<>'RECORDED' then raise exception 'credit note is not available for approval'; end if;
  if v_credit.recorded_by=v_actor then raise exception 'maker/checker: credit recorder cannot approve'; end if;
  select * into v_obligation from public.cost_obligations where id=v_credit.obligation_id and organization_id=p_organization_id for update;
  if not found or v_obligation.status<>'AUTHORIZED' then raise exception 'authorized obligation required'; end if;
  v_outstanding:=public.obligation_active_outstanding_minor_units(p_organization_id,v_obligation.id);
  if v_outstanding is null or v_credit.amount_minor_units>v_outstanding then raise exception 'credit exceeds current outstanding payable'; end if;
  select * into v_invoice from public.supplier_invoices where id=v_credit.supplier_invoice_id and organization_id=p_organization_id;
  select id into v_payable from public.semantic_accounts where role='SUPPLIER_PAYABLE';
  if v_invoice.cost_treatment='EXPENSE' then select id into v_cost from public.semantic_accounts where role='PROJECT_EXPENSE';
  else select id into v_cost from public.semantic_accounts where role='DEVELOPMENT_WIP'; end if;
  insert into public.journal_batches(id,organization_id,project_id,source_type,source_id,transaction_date,idempotency_key,request_hash,posted_by)
  values(v_batch_id,p_organization_id,v_credit.project_id,'SUPPLIER_CREDIT_NOTE',v_credit.id,v_credit.credit_date,
    'p3-credit-batch:'||v_credit.id::text,v_hash,v_actor);
  insert into public.journal_lines(batch_id,organization_id,project_id,account_id,debit_minor_units,credit_minor_units,currency,obligation_id,party_id,transaction_date)
  values
    (v_batch_id,p_organization_id,v_credit.project_id,v_payable,v_credit.amount_minor_units,0,v_credit.currency,v_obligation.id,v_obligation.party_id,v_credit.credit_date),
    (v_batch_id,p_organization_id,v_credit.project_id,v_cost,0,v_credit.amount_minor_units,v_credit.currency,v_obligation.id,v_obligation.party_id,v_credit.credit_date);
  update public.supplier_credit_notes
     set status='APPROVED',approved_by=v_actor,approved_at=now(),authorization_batch_id=v_batch_id,
         approve_idempotency_key=trim(p_idempotency_key),approve_request_hash=v_hash
   where id=v_credit.id;
  return v_batch_id;
end $$;
