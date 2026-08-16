-- R5 reconciliation hardening.
--
-- Different idempotency keys racing or retrying against the same rental
-- collection / bank statement line must fail at the command boundary with a
-- stable domain error, not leak a storage-level UNIQUE violation. The row
-- locks below also serialize those competing attempts.

create or replace function public.reconcile_property_rental_collection(
  p_organization_id uuid,p_collection_id uuid,p_statement_line_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_collection public.property_rental_collections%rowtype;
  v_line record; v_existing record; v_hash text; v_id uuid:=gen_random_uuid();
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  v_hash:=public.r5_sha256(p_collection_id::text||'|'||p_statement_line_id::text);
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':r5-rental-reconcile:'||trim(p_idempotency_key),0));

  -- True replay wins before mutable-state checks.
  select * into v_existing
  from public.property_rental_collection_reconciliations
  where organization_id=p_organization_id
    and idempotency_key=trim(p_idempotency_key);
  if found then
    if v_existing.collection_id<>p_collection_id
       or v_existing.statement_line_id<>p_statement_line_id
       or v_existing.request_hash<>v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  -- Lock the economic objects, not only the idempotency key. This serializes
  -- two different request keys aimed at the same collection or bank line.
  select * into v_collection
  from public.property_rental_collections
  where id=p_collection_id and organization_id=p_organization_id
  for update;
  if not found then raise exception 'rental collection not found'; end if;
  if exists(
    select 1 from public.journal_batches rb
    where rb.reversal_of_batch_id=v_collection.journal_batch_id
  ) then
    raise exception 'reversed rental collection cannot be reconciled';
  end if;

  select * into v_line
  from public.bank_statement_lines
  where id=p_statement_line_id and organization_id=p_organization_id
  for update;
  if not found then raise exception 'bank statement line not found'; end if;

  -- Re-check only after both row locks are held. A concurrent competing
  -- transaction may have committed while this caller was waiting.
  if exists(
    select 1 from public.property_rental_collection_reconciliations rr
    where rr.organization_id=p_organization_id
      and rr.collection_id=p_collection_id
  ) then
    raise exception 'rental collection already reconciled';
  end if;
  if exists(
    select 1 from public.bank_statement_reconciliation_allocations a
    where a.organization_id=p_organization_id
      and a.statement_line_id=p_statement_line_id
  ) then
    raise exception 'bank statement line already reconciled';
  end if;

  if v_line.project_id<>v_collection.project_id
     or v_line.cash_account_id<>v_collection.cash_account_id
     or v_line.currency<>v_collection.currency then
    raise exception 'rental collection and bank line must use the same project cash account and currency';
  end if;
  if v_line.amount_minor_units<>v_collection.amount_minor_units
     or v_line.amount_minor_units<=0 then
    raise exception 'positive bank statement amount must equal the rental collection';
  end if;

  insert into public.property_rental_collection_reconciliations(
    id,organization_id,project_id,collection_id,statement_line_id,cash_account_id,currency,
    matched_by,idempotency_key,request_hash
  ) values(
    v_id,p_organization_id,v_collection.project_id,p_collection_id,p_statement_line_id,
    v_collection.cash_account_id,v_collection.currency,v_actor,trim(p_idempotency_key),v_hash
  );

  insert into public.audit_events(
    organization_id,actor_id,event_type,entity_type,entity_id,payload
  ) values(
    p_organization_id,v_actor,'PROPERTY_RENTAL_COLLECTION_RECONCILED',
    'property_rental_collection_reconciliation',v_id,
    jsonb_build_object(
      'project_id',v_collection.project_id,
      'collection_id',p_collection_id,
      'statement_line_id',p_statement_line_id,
      'accounting_effect','NONE'
    )
  );
  return v_id;
end $$;

revoke all on function public.reconcile_property_rental_collection(uuid,uuid,uuid,text)
  from public,anon;
grant execute on function public.reconcile_property_rental_collection(uuid,uuid,uuid,text)
  to authenticated;
