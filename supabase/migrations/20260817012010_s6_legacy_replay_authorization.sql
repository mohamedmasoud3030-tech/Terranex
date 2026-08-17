-- S6 replay-safety follow-up: legacy compatibility wrappers must authorize
-- before consulting receipts or historical domain rows. An idempotency key is
-- not a secret and legacy payload matching must not become an existence oracle.

revoke all on function public.s6_create_accounting_period(uuid,uuid,date,date) from public,anon,authenticated;
revoke all on function public.s6_prepare_close_run(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.s6_reopen_period(uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;

create or replace function public.s6_create_accounting_period(
  p_organization_id uuid,p_project_id uuid,p_start_date date,p_end_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payload jsonb;
  v_key text;
  v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'start_date',p_start_date,'end_date',p_end_date
  );
  v_key := 'legacy-' || public.s6_command_request_hash(v_payload);
  if not exists(
    select 1 from public.s6_command_receipts
    where organization_id=p_organization_id
      and command_type='CREATE_ACCOUNTING_PERIOD'
      and idempotency_key=v_key
  ) then
    select count(*) into v_count
    from public.accounting_periods
    where organization_id=p_organization_id
      and project_id=p_project_id
      and start_date=p_start_date
      and end_date=p_end_date
      and supersedes_period_id is null;
    if v_count > 0 then
      raise exception 'legacy command payload is ambiguous; refresh client';
    end if;
  end if;
  return public.s6_create_accounting_period(
    p_organization_id,p_project_id,p_start_date,p_end_date,v_key
  );
end $$;

create or replace function public.s6_prepare_close_run(
  p_organization_id uuid,p_project_id uuid,p_period_id uuid,p_notes text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payload jsonb;
  v_key text;
  v_count int;
  v_notes text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_notes := nullif(trim(coalesce(p_notes,'')),'');
  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'period_id',p_period_id,'notes',v_notes
  );
  v_key := 'legacy-' || public.s6_command_request_hash(v_payload);
  if not exists(
    select 1 from public.s6_command_receipts
    where organization_id=p_organization_id
      and command_type='PREPARE_CLOSE_RUN'
      and idempotency_key=v_key
  ) then
    select count(*) into v_count
    from public.close_runs
    where organization_id=p_organization_id
      and project_id=p_project_id
      and period_id=p_period_id
      and notes is not distinct from v_notes;
    if v_count > 0 then
      raise exception 'legacy command payload is ambiguous; refresh client';
    end if;
  end if;
  return public.s6_prepare_close_run(
    p_organization_id,p_project_id,p_period_id,p_notes,v_key
  );
end $$;

create or replace function public.s6_request_close_run_exception(
  p_organization_id uuid,p_close_run_id uuid,p_gate_code text,
  p_reason text,p_evidence_reference text,p_materiality_comment text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payload jsonb;
  v_key text;
  v_count int;
  v_materiality text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_materiality := nullif(trim(coalesce(p_materiality_comment,'')),'');
  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'close_run_id',p_close_run_id,
    'gate_code',p_gate_code,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference),
    'materiality_comment',v_materiality
  );
  v_key := 'legacy-' || public.s6_command_request_hash(v_payload);
  if not exists(
    select 1 from public.s6_command_receipts
    where organization_id=p_organization_id
      and command_type='REQUEST_CLOSE_EXCEPTION'
      and idempotency_key=v_key
  ) then
    select count(*) into v_count
    from public.close_run_exceptions
    where organization_id=p_organization_id
      and close_run_id=p_close_run_id
      and gate_code=p_gate_code
      and reason=trim(p_reason)
      and evidence_reference=trim(p_evidence_reference)
      and materiality_comment is not distinct from v_materiality;
    if v_count > 0 then
      raise exception 'legacy command payload is ambiguous; refresh client';
    end if;
  end if;
  return public.s6_request_close_run_exception(
    p_organization_id,p_close_run_id,p_gate_code,p_reason,
    p_evidence_reference,p_materiality_comment,v_key
  );
end $$;

create or replace function public.s6_reopen_period(
  p_organization_id uuid,p_project_id uuid,p_period_id uuid,
  p_reason text,p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payload jsonb;
  v_key text;
  v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'period_id',p_period_id,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference)
  );
  v_key := 'legacy-' || public.s6_command_request_hash(v_payload);
  if not exists(
    select 1 from public.s6_command_receipts
    where organization_id=p_organization_id
      and command_type='REOPEN_PERIOD'
      and idempotency_key=v_key
  ) then
    select count(*) into v_count
    from public.accounting_periods p
    join public.audit_events a
      on a.organization_id=p.organization_id
     and a.entity_type='accounting_period'
     and a.entity_id=p.id
     and a.event_type='ACCOUNTING_PERIOD_REOPENED'
    where p.organization_id=p_organization_id
      and p.project_id=p_project_id
      and p.supersedes_period_id=p_period_id
      and a.payload->>'reason'=trim(p_reason)
      and a.payload->>'evidence_reference'=trim(p_evidence_reference);
    if v_count > 0 then
      raise exception 'legacy command payload is ambiguous; refresh client';
    end if;
  end if;
  return public.s6_reopen_period(
    p_organization_id,p_project_id,p_period_id,p_reason,
    p_evidence_reference,v_key
  );
end $$;

create or replace function public.s6_request_correction(
  p_organization_id uuid,p_project_id uuid,p_target_batch_id uuid,
  p_source_period_id uuid,p_correction_period_id uuid,
  p_reason text,p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid();
  v_payload jsonb;
  v_key text;
  v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'target_batch_id',p_target_batch_id,'source_period_id',p_source_period_id,
    'correction_period_id',p_correction_period_id,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference)
  );
  v_key := 'legacy-' || public.s6_command_request_hash(v_payload);
  if not exists(
    select 1 from public.s6_command_receipts
    where organization_id=p_organization_id
      and command_type='REQUEST_CORRECTION'
      and idempotency_key=v_key
  ) then
    select count(*) into v_count
    from public.correction_requests
    where organization_id=p_organization_id
      and project_id=p_project_id
      and target_batch_id=p_target_batch_id
      and source_period_id=p_source_period_id
      and correction_period_id=p_correction_period_id
      and reason=trim(p_reason)
      and evidence_reference=trim(p_evidence_reference);
    if v_count > 0 then
      raise exception 'legacy command payload is ambiguous; refresh client';
    end if;
  end if;
  return public.s6_request_correction(
    p_organization_id,p_project_id,p_target_batch_id,p_source_period_id,
    p_correction_period_id,p_reason,p_evidence_reference,v_key
  );
end $$;

grant execute on function public.s6_create_accounting_period(uuid,uuid,date,date) to authenticated;
grant execute on function public.s6_prepare_close_run(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) to authenticated;
grant execute on function public.s6_reopen_period(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
