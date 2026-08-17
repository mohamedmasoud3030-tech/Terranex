-- S6 corrective engineering — replay safety for material commands that
-- historically had no idempotency contract. Existing domain implementations
-- are preserved by rename; this migration adds only command identity, replay,
-- authorization, and compatibility boundaries.

create table public.s6_command_receipts (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  command_type text not null check (command_type in (
    'CREATE_ACCOUNTING_PERIOD',
    'PREPARE_CLOSE_RUN',
    'REQUEST_CLOSE_EXCEPTION',
    'REOPEN_PERIOD',
    'REQUEST_CORRECTION'
  )),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  result_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (organization_id, command_type, idempotency_key)
);

alter table public.s6_command_receipts enable row level security;
revoke all on public.s6_command_receipts from public, anon, authenticated;

create trigger s6_command_receipts_no_update
before update on public.s6_command_receipts
for each row execute function public.s2_guard_append_only();
create trigger s6_command_receipts_no_delete
before delete on public.s6_command_receipts
for each row execute function public.s2_guard_append_only();

-- Build the SHA-256 helper with digest schema-qualified at definition time.
-- Hosted Supabase may place pgcrypto in extensions; plain PostgreSQL usually
-- places it in public. The function itself retains a locked search_path.
do $s6_hash$
declare
  v_pgcrypto_schema text;
begin
  select n.nspname into v_pgcrypto_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'pgcrypto extension is required';
  end if;

  execute format($fn$
    create or replace function public.s6_command_request_hash(p_payload jsonb)
    returns text language sql immutable set search_path=pg_catalog,public as
    $body$ select encode(%I.digest(p_payload::text, 'sha256'), 'hex') $body$
  $fn$, v_pgcrypto_schema);
end
$s6_hash$;
revoke all on function public.s6_command_request_hash(jsonb)
  from public, anon, authenticated;

create or replace function public.s6_begin_replay_safe_command(
  p_organization_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_payload jsonb,
  out request_hash text,
  out replay_result_id uuid
) language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_existing record;
begin
  if p_command_type not in (
    'CREATE_ACCOUNTING_PERIOD','PREPARE_CLOSE_RUN','REQUEST_CLOSE_EXCEPTION',
    'REOPEN_PERIOD','REQUEST_CORRECTION'
  ) then
    raise exception 'invalid S6 command type';
  end if;
  if p_idempotency_key is null
     or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;

  p_idempotency_key := trim(p_idempotency_key);
  request_hash := public.s6_command_request_hash(p_payload);

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_command_type || ':' || p_idempotency_key,
    0
  ));

  select r.request_hash, r.result_id into v_existing
  from public.s6_command_receipts r
  where r.organization_id = p_organization_id
    and r.command_type = p_command_type
    and r.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash <> request_hash then
      raise exception 'idempotency key payload mismatch';
    end if;
    replay_result_id := v_existing.result_id;
  else
    replay_result_id := null;
  end if;
end $$;
revoke all on function public.s6_begin_replay_safe_command(uuid,text,text,jsonb)
  from public, anon, authenticated;

-- Preserve the effective domain bodies untouched. Existing close/correction
-- semantics, locks, gates and audit behavior remain authoritative here.
alter function public.s6_create_accounting_period(uuid,uuid,date,date)
  rename to s6_create_accounting_period_impl;
alter function public.s6_prepare_close_run(uuid,uuid,uuid,text)
  rename to s6_prepare_close_run_impl;
alter function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text)
  rename to s6_request_close_run_exception_impl;
alter function public.s6_reopen_period(uuid,uuid,uuid,text,text)
  rename to s6_reopen_period_impl;
alter function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text)
  rename to s6_request_correction_impl;

revoke all on function public.s6_create_accounting_period_impl(uuid,uuid,date,date)
  from public,anon,authenticated;
revoke all on function public.s6_prepare_close_run_impl(uuid,uuid,uuid,text)
  from public,anon,authenticated;
revoke all on function public.s6_request_close_run_exception_impl(uuid,uuid,text,text,text,text)
  from public,anon,authenticated;
revoke all on function public.s6_reopen_period_impl(uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.s6_request_correction_impl(uuid,uuid,uuid,uuid,uuid,text,text)
  from public,anon,authenticated;

-- Keyed public commands. Authorization is deliberately checked before receipt
-- lookup: an idempotency key is never treated as a capability or secret.
create or replace function public.s6_create_accounting_period(
  p_organization_id uuid, p_project_id uuid, p_start_date date, p_end_date date,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_payload jsonb; v_hash text; v_replay uuid; v_result uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'start_date',p_start_date,'end_date',p_end_date
  );
  select request_hash,replay_result_id into v_hash,v_replay
  from public.s6_begin_replay_safe_command(
    p_organization_id,'CREATE_ACCOUNTING_PERIOD',p_idempotency_key,v_payload
  );
  if v_replay is not null then return v_replay; end if;

  v_result := public.s6_create_accounting_period_impl(
    p_organization_id,p_project_id,p_start_date,p_end_date
  );
  insert into public.s6_command_receipts(
    organization_id,command_type,idempotency_key,request_hash,result_id,created_by
  ) values (
    p_organization_id,'CREATE_ACCOUNTING_PERIOD',trim(p_idempotency_key),v_hash,v_result,v_actor
  );
  return v_result;
end $$;

create or replace function public.s6_prepare_close_run(
  p_organization_id uuid, p_project_id uuid, p_period_id uuid, p_notes text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_payload jsonb; v_hash text; v_replay uuid; v_result uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'period_id',p_period_id,'notes',nullif(trim(coalesce(p_notes,'')),'')
  );
  select request_hash,replay_result_id into v_hash,v_replay
  from public.s6_begin_replay_safe_command(
    p_organization_id,'PREPARE_CLOSE_RUN',p_idempotency_key,v_payload
  );
  if v_replay is not null then return v_replay; end if;

  v_result := public.s6_prepare_close_run_impl(
    p_organization_id,p_project_id,p_period_id,p_notes
  );
  insert into public.s6_command_receipts(
    organization_id,command_type,idempotency_key,request_hash,result_id,created_by
  ) values (
    p_organization_id,'PREPARE_CLOSE_RUN',trim(p_idempotency_key),v_hash,v_result,v_actor
  );
  return v_result;
end $$;

create or replace function public.s6_request_close_run_exception(
  p_organization_id uuid, p_close_run_id uuid, p_gate_code text,
  p_reason text, p_evidence_reference text, p_materiality_comment text,
  p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_payload jsonb; v_hash text; v_replay uuid; v_result uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'close_run_id',p_close_run_id,
    'gate_code',p_gate_code,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference),
    'materiality_comment',nullif(trim(coalesce(p_materiality_comment,'')),'')
  );
  select request_hash,replay_result_id into v_hash,v_replay
  from public.s6_begin_replay_safe_command(
    p_organization_id,'REQUEST_CLOSE_EXCEPTION',p_idempotency_key,v_payload
  );
  if v_replay is not null then return v_replay; end if;

  v_result := public.s6_request_close_run_exception_impl(
    p_organization_id,p_close_run_id,p_gate_code,p_reason,p_evidence_reference,p_materiality_comment
  );
  insert into public.s6_command_receipts(
    organization_id,command_type,idempotency_key,request_hash,result_id,created_by
  ) values (
    p_organization_id,'REQUEST_CLOSE_EXCEPTION',trim(p_idempotency_key),v_hash,v_result,v_actor
  );
  return v_result;
end $$;

create or replace function public.s6_reopen_period(
  p_organization_id uuid, p_project_id uuid, p_period_id uuid,
  p_reason text, p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_payload jsonb; v_hash text; v_replay uuid; v_result uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);

  v_payload := jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'period_id',p_period_id,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference)
  );
  select request_hash,replay_result_id into v_hash,v_replay
  from public.s6_begin_replay_safe_command(
    p_organization_id,'REOPEN_PERIOD',p_idempotency_key,v_payload
  );
  if v_replay is not null then return v_replay; end if;

  v_result := public.s6_reopen_period_impl(
    p_organization_id,p_project_id,p_period_id,p_reason,p_evidence_reference
  );
  insert into public.s6_command_receipts(
    organization_id,command_type,idempotency_key,request_hash,result_id,created_by
  ) values (
    p_organization_id,'REOPEN_PERIOD',trim(p_idempotency_key),v_hash,v_result,v_actor
  );
  return v_result;
end $$;

create or replace function public.s6_request_correction(
  p_organization_id uuid, p_project_id uuid, p_target_batch_id uuid,
  p_source_period_id uuid, p_correction_period_id uuid,
  p_reason text, p_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid := auth.uid(); v_payload jsonb; v_hash text; v_replay uuid; v_result uuid;
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
  select request_hash,replay_result_id into v_hash,v_replay
  from public.s6_begin_replay_safe_command(
    p_organization_id,'REQUEST_CORRECTION',p_idempotency_key,v_payload
  );
  if v_replay is not null then return v_replay; end if;

  v_result := public.s6_request_correction_impl(
    p_organization_id,p_project_id,p_target_batch_id,p_source_period_id,
    p_correction_period_id,p_reason,p_evidence_reference
  );
  insert into public.s6_command_receipts(
    organization_id,command_type,idempotency_key,request_hash,result_id,created_by
  ) values (
    p_organization_id,'REQUEST_CORRECTION',trim(p_idempotency_key),v_hash,v_result,v_actor
  );
  return v_result;
end $$;

revoke all on function public.s6_create_accounting_period(uuid,uuid,date,date,text) from public,anon;
revoke all on function public.s6_prepare_close_run(uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text,text) from public,anon;
revoke all on function public.s6_reopen_period(uuid,uuid,uuid,text,text,text) from public,anon;
revoke all on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text,text) from public,anon;
grant execute on function public.s6_create_accounting_period(uuid,uuid,date,date,text) to authenticated;
grant execute on function public.s6_prepare_close_run(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text,text) to authenticated;
grant execute on function public.s6_reopen_period(uuid,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text,text) to authenticated;

-- Historical backfill. A deterministic legacy key is created only when one
-- normalized request payload maps to exactly one historical result.
with x as (
  select p.*,
    jsonb_build_object(
      'organization_id',p.organization_id,'project_id',p.project_id,
      'start_date',p.start_date,'end_date',p.end_date
    ) payload,
    count(*) over (partition by p.organization_id,p.project_id,p.start_date,p.end_date) n
  from public.accounting_periods p
  where p.supersedes_period_id is null
)
insert into public.s6_command_receipts(
  organization_id,command_type,idempotency_key,request_hash,result_id,created_by,created_at
)
select organization_id,'CREATE_ACCOUNTING_PERIOD',
  'legacy-'||public.s6_command_request_hash(payload),
  public.s6_command_request_hash(payload),id,opened_by,opened_at
from x where n=1 on conflict do nothing;

with x as (
  select r.*,
    jsonb_build_object(
      'organization_id',r.organization_id,'project_id',r.project_id,
      'period_id',r.period_id,'notes',nullif(trim(coalesce(r.notes,'')),'')
    ) payload,
    count(*) over (
      partition by r.organization_id,r.project_id,r.period_id,
                   nullif(trim(coalesce(r.notes,'')),'')
    ) n
  from public.close_runs r
)
insert into public.s6_command_receipts(
  organization_id,command_type,idempotency_key,request_hash,result_id,created_by,created_at
)
select organization_id,'PREPARE_CLOSE_RUN',
  'legacy-'||public.s6_command_request_hash(payload),
  public.s6_command_request_hash(payload),id,generated_by,generated_at
from x where n=1 on conflict do nothing;

with x as (
  select e.*,
    jsonb_build_object(
      'organization_id',e.organization_id,'close_run_id',e.close_run_id,
      'gate_code',e.gate_code,'reason',trim(e.reason),
      'evidence_reference',trim(e.evidence_reference),
      'materiality_comment',nullif(trim(coalesce(e.materiality_comment,'')),'')
    ) payload,
    count(*) over (
      partition by e.organization_id,e.close_run_id,e.gate_code,trim(e.reason),
                   trim(e.evidence_reference),nullif(trim(coalesce(e.materiality_comment,'')),'')
    ) n
  from public.close_run_exceptions e
)
insert into public.s6_command_receipts(
  organization_id,command_type,idempotency_key,request_hash,result_id,created_by,created_at
)
select organization_id,'REQUEST_CLOSE_EXCEPTION',
  'legacy-'||public.s6_command_request_hash(payload),
  public.s6_command_request_hash(payload),id,requested_by,requested_at
from x where n=1 on conflict do nothing;

with x as (
  select p.organization_id,p.project_id,p.id,p.supersedes_period_id,p.opened_by,p.opened_at,
    jsonb_build_object(
      'organization_id',p.organization_id,'project_id',p.project_id,
      'period_id',p.supersedes_period_id,'reason',trim(a.payload->>'reason'),
      'evidence_reference',trim(a.payload->>'evidence_reference')
    ) payload,
    count(*) over (
      partition by p.organization_id,p.project_id,p.supersedes_period_id,
                   trim(a.payload->>'reason'),trim(a.payload->>'evidence_reference')
    ) n
  from public.accounting_periods p
  join public.audit_events a
    on a.organization_id=p.organization_id
   and a.entity_type='accounting_period'
   and a.entity_id=p.id
   and a.event_type='ACCOUNTING_PERIOD_REOPENED'
  where p.supersedes_period_id is not null
)
insert into public.s6_command_receipts(
  organization_id,command_type,idempotency_key,request_hash,result_id,created_by,created_at
)
select organization_id,'REOPEN_PERIOD',
  'legacy-'||public.s6_command_request_hash(payload),
  public.s6_command_request_hash(payload),id,opened_by,opened_at
from x where n=1 on conflict do nothing;

with x as (
  select r.*,
    jsonb_build_object(
      'organization_id',r.organization_id,'project_id',r.project_id,
      'target_batch_id',r.target_batch_id,'source_period_id',r.source_period_id,
      'correction_period_id',r.correction_period_id,'reason',trim(r.reason),
      'evidence_reference',trim(r.evidence_reference)
    ) payload,
    count(*) over (
      partition by r.organization_id,r.project_id,r.target_batch_id,r.source_period_id,
                   r.correction_period_id,trim(r.reason),trim(r.evidence_reference)
    ) n
  from public.correction_requests r
)
insert into public.s6_command_receipts(
  organization_id,command_type,idempotency_key,request_hash,result_id,created_by,created_at
)
select organization_id,'REQUEST_CORRECTION',
  'legacy-'||public.s6_command_request_hash(payload),
  public.s6_command_request_hash(payload),id,requested_by,requested_at
from x where n=1 on conflict do nothing;

-- Legacy arities remain for cached clients. Every wrapper authorizes before any
-- receipt/history lookup, derives the exact canonical legacy key, and refuses
-- an already-existing unmatched payload rather than guessing its identity.
create or replace function public.s6_create_accounting_period(
  p_organization_id uuid,p_project_id uuid,p_start_date date,p_end_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payload jsonb; v_key text; v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_payload:=jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'start_date',p_start_date,'end_date',p_end_date
  );
  v_key:='legacy-'||public.s6_command_request_hash(v_payload);
  if not exists(select 1 from public.s6_command_receipts where organization_id=p_organization_id and command_type='CREATE_ACCOUNTING_PERIOD' and idempotency_key=v_key) then
    select count(*) into v_count from public.accounting_periods
    where organization_id=p_organization_id and project_id=p_project_id
      and start_date=p_start_date and end_date=p_end_date and supersedes_period_id is null;
    if v_count>0 then raise exception 'legacy command payload is ambiguous; refresh client'; end if;
  end if;
  return public.s6_create_accounting_period(p_organization_id,p_project_id,p_start_date,p_end_date,v_key);
end $$;

create or replace function public.s6_prepare_close_run(
  p_organization_id uuid,p_project_id uuid,p_period_id uuid,p_notes text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payload jsonb; v_key text; v_count int; v_notes text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_notes:=nullif(trim(coalesce(p_notes,'')),'');
  v_payload:=jsonb_build_object('organization_id',p_organization_id,'project_id',p_project_id,'period_id',p_period_id,'notes',v_notes);
  v_key:='legacy-'||public.s6_command_request_hash(v_payload);
  if not exists(select 1 from public.s6_command_receipts where organization_id=p_organization_id and command_type='PREPARE_CLOSE_RUN' and idempotency_key=v_key) then
    select count(*) into v_count from public.close_runs
    where organization_id=p_organization_id and project_id=p_project_id
      and period_id=p_period_id and notes is not distinct from v_notes;
    if v_count>0 then raise exception 'legacy command payload is ambiguous; refresh client'; end if;
  end if;
  return public.s6_prepare_close_run(p_organization_id,p_project_id,p_period_id,p_notes,v_key);
end $$;

create or replace function public.s6_request_close_run_exception(
  p_organization_id uuid,p_close_run_id uuid,p_gate_code text,
  p_reason text,p_evidence_reference text,p_materiality_comment text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payload jsonb; v_key text; v_count int; v_materiality text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_materiality:=nullif(trim(coalesce(p_materiality_comment,'')),'');
  v_payload:=jsonb_build_object(
    'organization_id',p_organization_id,'close_run_id',p_close_run_id,
    'gate_code',p_gate_code,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference),'materiality_comment',v_materiality
  );
  v_key:='legacy-'||public.s6_command_request_hash(v_payload);
  if not exists(select 1 from public.s6_command_receipts where organization_id=p_organization_id and command_type='REQUEST_CLOSE_EXCEPTION' and idempotency_key=v_key) then
    select count(*) into v_count from public.close_run_exceptions
    where organization_id=p_organization_id and close_run_id=p_close_run_id
      and gate_code=p_gate_code and reason=trim(p_reason)
      and evidence_reference=trim(p_evidence_reference)
      and materiality_comment is not distinct from v_materiality;
    if v_count>0 then raise exception 'legacy command payload is ambiguous; refresh client'; end if;
  end if;
  return public.s6_request_close_run_exception(
    p_organization_id,p_close_run_id,p_gate_code,p_reason,p_evidence_reference,p_materiality_comment,v_key
  );
end $$;

create or replace function public.s6_reopen_period(
  p_organization_id uuid,p_project_id uuid,p_period_id uuid,
  p_reason text,p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payload jsonb; v_key text; v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_payload:=jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'period_id',p_period_id,'reason',trim(p_reason),'evidence_reference',trim(p_evidence_reference)
  );
  v_key:='legacy-'||public.s6_command_request_hash(v_payload);
  if not exists(select 1 from public.s6_command_receipts where organization_id=p_organization_id and command_type='REOPEN_PERIOD' and idempotency_key=v_key) then
    select count(*) into v_count
    from public.accounting_periods p
    join public.audit_events a on a.organization_id=p.organization_id
      and a.entity_type='accounting_period' and a.entity_id=p.id
      and a.event_type='ACCOUNTING_PERIOD_REOPENED'
    where p.organization_id=p_organization_id and p.project_id=p_project_id
      and p.supersedes_period_id=p_period_id
      and trim(a.payload->>'reason')=trim(p_reason)
      and trim(a.payload->>'evidence_reference')=trim(p_evidence_reference);
    if v_count>0 then raise exception 'legacy command payload is ambiguous; refresh client'; end if;
  end if;
  return public.s6_reopen_period(p_organization_id,p_project_id,p_period_id,p_reason,p_evidence_reference,v_key);
end $$;

create or replace function public.s6_request_correction(
  p_organization_id uuid,p_project_id uuid,p_target_batch_id uuid,
  p_source_period_id uuid,p_correction_period_id uuid,p_reason text,p_evidence_reference text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid(); v_payload jsonb; v_key text; v_count int;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  v_payload:=jsonb_build_object(
    'organization_id',p_organization_id,'project_id',p_project_id,
    'target_batch_id',p_target_batch_id,'source_period_id',p_source_period_id,
    'correction_period_id',p_correction_period_id,'reason',trim(p_reason),
    'evidence_reference',trim(p_evidence_reference)
  );
  v_key:='legacy-'||public.s6_command_request_hash(v_payload);
  if not exists(select 1 from public.s6_command_receipts where organization_id=p_organization_id and command_type='REQUEST_CORRECTION' and idempotency_key=v_key) then
    select count(*) into v_count from public.correction_requests
    where organization_id=p_organization_id and project_id=p_project_id
      and target_batch_id=p_target_batch_id and source_period_id=p_source_period_id
      and correction_period_id=p_correction_period_id and reason=trim(p_reason)
      and evidence_reference=trim(p_evidence_reference);
    if v_count>0 then raise exception 'legacy command payload is ambiguous; refresh client'; end if;
  end if;
  return public.s6_request_correction(
    p_organization_id,p_project_id,p_target_batch_id,p_source_period_id,
    p_correction_period_id,p_reason,p_evidence_reference,v_key
  );
end $$;

revoke all on function public.s6_create_accounting_period(uuid,uuid,date,date) from public,anon;
revoke all on function public.s6_prepare_close_run(uuid,uuid,uuid,text) from public,anon;
revoke all on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.s6_reopen_period(uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.s6_create_accounting_period(uuid,uuid,date,date) to authenticated;
grant execute on function public.s6_prepare_close_run(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.s6_request_close_run_exception(uuid,uuid,text,text,text,text) to authenticated;
grant execute on function public.s6_reopen_period(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
