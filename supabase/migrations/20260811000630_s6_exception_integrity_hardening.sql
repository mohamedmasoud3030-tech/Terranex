-- GF-007 / S6 hardening — close-run exception relational integrity.
--
-- The original composite FK on close_run_exceptions reversed the referenced
-- close_runs column order. A valid exception therefore could not reference
-- its own close run. Correct the FK and make composite-gate recomputation
-- explicit after an approved exception.

alter table public.close_run_exceptions
  drop constraint if exists close_run_exceptions_close_run_id_organization_id_fkey;

alter table public.close_run_exceptions
  add constraint close_run_exceptions_close_run_id_organization_id_fkey
  foreign key (close_run_id, organization_id)
  references public.close_runs(id, organization_id)
  on delete restrict;

create or replace function public.s6_approve_close_run_exception(
  p_organization_id uuid,
  p_exception_id uuid,
  p_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid := auth.uid();
  v_exc record;
  v_hash text;
  v_existing record;
  v_fail_count integer;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;
  if not public.is_active_member(p_organization_id) then
    raise exception 'forbidden';
  end if;
  perform public.s2_require_owner(p_organization_id);

  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  select encode(digest(p_exception_id::text, 'sha256'), 'hex') into v_hash;
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s6-exception:' || trim(p_idempotency_key), 0));

  select * into v_existing
  from public.close_run_exceptions
  where organization_id = p_organization_id
    and approval_idempotency_key = trim(p_idempotency_key);

  if found then
    if v_existing.id <> p_exception_id
       or v_existing.approval_request_hash <> v_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
  end if;

  select * into v_exc
  from public.close_run_exceptions
  where id = p_exception_id
    and organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'exception not found';
  end if;
  if v_exc.status <> 'PENDING' then
    raise exception 'exception already decided';
  end if;

  update public.close_run_exceptions
  set status = 'APPROVED',
      approved_by = v_actor,
      approved_at = now(),
      approval_idempotency_key = trim(p_idempotency_key),
      approval_request_hash = v_hash
  where id = p_exception_id;

  update public.close_run_gates
  set result = 'APPROVED_EXCEPTION',
      exception_id = p_exception_id
  where close_run_id = v_exc.close_run_id
    and gate_code = v_exc.gate_code;

  -- The composite gate reflects only the nine concrete gates. Counting the
  -- composite itself would make a previous FAIL self-perpetuating forever.
  select count(*)::integer into v_fail_count
  from public.close_run_gates
  where close_run_id = v_exc.close_run_id
    and gate_code <> 'CLOSE_REPORT_AND_EXCEPTIONS'
    and result = 'FAIL';

  update public.close_run_gates
  set result = case when v_fail_count = 0 then 'PASS' else 'FAIL' end,
      detail = case when v_fail_count = 0
        then 'close report and exceptions are consistent with the other gate results'
        else format('%s concrete gate(s) still failed; review remaining exceptions before approval', v_fail_count)
      end,
      evidence = jsonb_build_object('failing_concrete_gates', v_fail_count)
  where close_run_id = v_exc.close_run_id
    and gate_code = 'CLOSE_REPORT_AND_EXCEPTIONS';

  insert into public.audit_events(
    organization_id, actor_id, event_type, entity_type, entity_id, payload
  ) values (
    p_organization_id,
    v_actor,
    'CLOSE_RUN_EXCEPTION_APPROVED',
    'close_run_exception',
    p_exception_id,
    jsonb_build_object(
      'close_run_id', v_exc.close_run_id,
      'gate_code', v_exc.gate_code
    )
  );

  return p_exception_id;
end $$;

revoke all on function public.s6_approve_close_run_exception(uuid,uuid,text)
  from public, anon;
grant execute on function public.s6_approve_close_run_exception(uuid,uuid,text)
  to authenticated;
