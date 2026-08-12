-- GF-009 / S7 — UAT evidence and the machine-verifiable acceptance report.
--
-- Two facts are deliberately kept apart and can never be conflated:
--
--   * a **technical rehearsal**, which the automated suite performs and which
--     the system may mark itself; and
--   * a **human UAT acceptance**, which only a named human reviewer can grant,
--     against a named external evidence reference.
--
-- The system therefore cannot ever mark customer acceptance on its own. A UAT
-- task stays PENDING until a real reviewer accepts it with real evidence, and
-- the acceptance report reports the human gate separately from every automated
-- technical gate.

-- ===========================================================================
-- 1. UAT tasks.
-- ===========================================================================
create table public.s7_uat_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  task_code text not null check (task_code ~ '^S7-UAT-[A-Z0-9-]{2,40}$'),
  title text not null check (char_length(trim(title)) between 3 and 200),
  expected_outcome text not null check (char_length(trim(expected_outcome)) between 3 and 2000),
  status text not null default 'PENDING' check (status in ('PENDING','EXECUTED','ACCEPTED','REJECTED')),
  executed_by uuid references auth.users(id) on delete restrict,
  executed_at timestamptz,
  execution_evidence_reference text check (execution_evidence_reference is null
    or char_length(trim(execution_evidence_reference)) between 3 and 200),
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  acceptance_evidence_reference text check (acceptance_evidence_reference is null
    or char_length(trim(acceptance_evidence_reference)) between 3 and 200),
  notes text check (notes is null or char_length(trim(notes)) <= 2000),
  rejection_reason text check (rejection_reason is null or char_length(trim(rejection_reason)) between 3 and 2000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint s7_uat_executed_columns_check check (
    (status in ('PENDING')) = (executed_by is null and executed_at is null)
  ),
  constraint s7_uat_accepted_columns_check check (
    (status = 'ACCEPTED') =
    (reviewed_by is not null and reviewed_at is not null and acceptance_evidence_reference is not null)
  ),
  constraint s7_uat_rejected_columns_check check (
    (status = 'REJECTED') = (rejection_reason is not null and reviewed_by is not null)
  ),
  -- A human acceptance is a second pair of eyes: the operator who executed the
  -- task can never accept their own execution.
  constraint s7_uat_maker_checker_check
    check (reviewed_by is null or executed_by is null or reviewed_by <> executed_by),
  unique (organization_id, project_id, task_code),
  unique (id, organization_id),
  unique (id, organization_id, project_id),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index s7_uat_tasks_project_idx on public.s7_uat_tasks(project_id, status);

create or replace function public.s7_guard_uat_task_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_allowed boolean;
begin
  if old.organization_id <> new.organization_id
     or old.project_id <> new.project_id
     or old.task_code <> new.task_code
     or old.expected_outcome <> new.expected_outcome
     or old.created_by <> new.created_by then
    raise exception 'a UAT task definition is immutable';
  end if;
  if old.status = 'ACCEPTED' then
    raise exception 'an accepted UAT task is immutable';
  end if;
  if old.status = new.status then return new; end if;
  v_allowed := (old.status, new.status) in (
    ('PENDING','EXECUTED'),
    ('EXECUTED','ACCEPTED'),
    ('EXECUTED','REJECTED'),
    ('REJECTED','EXECUTED')
  );
  if not v_allowed then
    raise exception 'invalid UAT task transition % -> %', old.status, new.status;
  end if;
  return new;
end $$;
create trigger s7_uat_tasks_transition_guard
before update on public.s7_uat_tasks
for each row execute function public.s7_guard_uat_task_transition();

create or replace function public.s7_guard_uat_append_only() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  raise exception 'UAT evidence is append-only';
end $$;
create trigger s7_uat_tasks_no_delete
before delete on public.s7_uat_tasks
for each row execute function public.s7_guard_uat_append_only();

-- ===========================================================================
-- 2. Technical rehearsal records. These are explicitly *not* UAT.
-- ===========================================================================
create table public.s7_pilot_rehearsals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid not null references public.investment_projects(id) on delete restrict,
  rehearsal_code text not null check (rehearsal_code in (
    'END_TO_END_CYCLE','BACKUP_RESTORE','ACCESS_REVOCATION'
  )),
  result text not null check (result in ('PASS','FAIL')),
  detail text not null check (char_length(trim(detail)) between 3 and 2000),
  evidence jsonb not null default '{}'::jsonb,
  executed_by uuid not null references auth.users(id) on delete restrict,
  executed_at timestamptz not null default now(),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 120),
  request_hash text not null check (char_length(request_hash) = 64),
  unique (id, organization_id),
  unique (organization_id, idempotency_key),
  foreign key (project_id, organization_id)
    references public.investment_projects(id, organization_id) on delete restrict
);
create index s7_pilot_rehearsals_project_idx
  on public.s7_pilot_rehearsals(project_id, rehearsal_code, executed_at desc);

create trigger s7_pilot_rehearsals_immutable
before update or delete on public.s7_pilot_rehearsals
for each row execute function public.s7_guard_uat_append_only();

-- ===========================================================================
-- 3. Commands.
-- ===========================================================================
create or replace function public.s7_register_uat_task(
  p_organization_id uuid, p_project_id uuid, p_task_code text, p_title text,
  p_expected_outcome text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_task_code is null or upper(trim(p_task_code)) !~ '^S7-UAT-[A-Z0-9-]{2,40}$' then
    raise exception 'invalid UAT task code';
  end if;
  if p_title is null or char_length(trim(p_title)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_title) then
    raise exception 'a UAT task title is required';
  end if;
  if p_expected_outcome is null or char_length(trim(p_expected_outcome)) not between 3 and 2000
     or public.s7_has_unsafe_control_characters(p_expected_outcome) then
    raise exception 'an expected outcome is required';
  end if;
  if not exists (
    select 1 from public.investment_projects
    where id = p_project_id and organization_id = p_organization_id
  ) then raise exception 'project not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-uat-register:' || upper(trim(p_task_code)), 0));
  select id into v_id from public.s7_uat_tasks
  where organization_id = p_organization_id and project_id = p_project_id
    and task_code = upper(trim(p_task_code));
  if v_id is not null then return v_id; end if;

  insert into public.s7_uat_tasks(
    organization_id, project_id, task_code, title, expected_outcome, created_by
  ) values (
    p_organization_id, p_project_id, upper(trim(p_task_code)), trim(p_title),
    trim(p_expected_outcome), v_actor
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_UAT_TASK_REGISTERED', 's7_uat_task', v_id,
    jsonb_build_object('project_id', p_project_id, 'task_code', upper(trim(p_task_code))));
  return v_id;
end $$;

create or replace function public.s7_record_uat_execution(
  p_organization_id uuid, p_task_id uuid, p_evidence_reference text, p_notes text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_task record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_evidence_reference is null or char_length(trim(p_evidence_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_evidence_reference) then
    raise exception 'an execution evidence reference is required';
  end if;
  select * into v_task from public.s7_uat_tasks
  where id = p_task_id and organization_id = p_organization_id for update;
  if not found then raise exception 'UAT task not found'; end if;
  if v_task.status = 'ACCEPTED' then raise exception 'an accepted UAT task is immutable'; end if;
  if v_task.status = 'EXECUTED' and v_task.executed_by = v_actor then return p_task_id; end if;

  update public.s7_uat_tasks set
    status = 'EXECUTED', executed_by = v_actor, executed_at = now(),
    execution_evidence_reference = trim(p_evidence_reference),
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    rejection_reason = null
  where id = p_task_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_UAT_TASK_EXECUTED', 's7_uat_task', p_task_id,
    jsonb_build_object('project_id', v_task.project_id, 'task_code', v_task.task_code));
  return p_task_id;
end $$;

-- Human acceptance. There is no automated path into this command: it always
-- requires an authenticated reviewer who is not the executor, plus a real
-- external evidence reference.
create or replace function public.s7_accept_uat_task(
  p_organization_id uuid, p_task_id uuid, p_acceptance_evidence_reference text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_task record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_acceptance_evidence_reference is null
     or char_length(trim(p_acceptance_evidence_reference)) not between 3 and 200
     or public.s7_has_unsafe_control_characters(p_acceptance_evidence_reference) then
    raise exception 'a customer acceptance evidence reference is required';
  end if;
  select * into v_task from public.s7_uat_tasks
  where id = p_task_id and organization_id = p_organization_id for update;
  if not found then raise exception 'UAT task not found'; end if;
  if v_task.status = 'ACCEPTED' then return p_task_id; end if;
  if v_task.status <> 'EXECUTED' then
    raise exception 'only an executed UAT task can be accepted';
  end if;
  if v_task.executed_by = v_actor then
    raise exception 'the reviewer accepting a UAT task must not be its executor';
  end if;
  update public.s7_uat_tasks set
    status = 'ACCEPTED', reviewed_by = v_actor, reviewed_at = now(),
    acceptance_evidence_reference = trim(p_acceptance_evidence_reference),
    rejection_reason = null
  where id = p_task_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_UAT_TASK_ACCEPTED', 's7_uat_task', p_task_id,
    jsonb_build_object('project_id', v_task.project_id, 'task_code', v_task.task_code,
      'acceptance_evidence_reference', trim(p_acceptance_evidence_reference)));
  return p_task_id;
end $$;

create or replace function public.s7_reject_uat_task(
  p_organization_id uuid, p_task_id uuid, p_rejection_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_task record;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_rejection_reason is null or char_length(trim(p_rejection_reason)) not between 3 and 2000
     or public.s7_has_unsafe_control_characters(p_rejection_reason) then
    raise exception 'a rejection reason is required';
  end if;
  select * into v_task from public.s7_uat_tasks
  where id = p_task_id and organization_id = p_organization_id for update;
  if not found then raise exception 'UAT task not found'; end if;
  if v_task.status = 'REJECTED' then return p_task_id; end if;
  if v_task.status <> 'EXECUTED' then
    raise exception 'only an executed UAT task can be rejected';
  end if;
  if v_task.executed_by = v_actor then
    raise exception 'the reviewer rejecting a UAT task must not be its executor';
  end if;
  update public.s7_uat_tasks set
    status = 'REJECTED', reviewed_by = v_actor, reviewed_at = now(),
    rejection_reason = trim(p_rejection_reason)
  where id = p_task_id;
  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_UAT_TASK_REJECTED', 's7_uat_task', p_task_id,
    jsonb_build_object('project_id', v_task.project_id, 'task_code', v_task.task_code,
      'reason', trim(p_rejection_reason)));
  return p_task_id;
end $$;

create or replace function public.s7_record_pilot_rehearsal(
  p_organization_id uuid, p_project_id uuid, p_rehearsal_code text, p_result text,
  p_detail text, p_evidence jsonb, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid := auth.uid(); v_existing record; v_id uuid; v_hash text;
begin
  if v_actor is null then raise exception 'authentication required'; end if;
  if not public.is_active_member(p_organization_id) then raise exception 'forbidden'; end if;
  perform public.s2_require_owner(p_organization_id);
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) not between 8 and 120 then
    raise exception 'invalid idempotency key';
  end if;
  if p_rehearsal_code not in ('END_TO_END_CYCLE','BACKUP_RESTORE','ACCESS_REVOCATION') then
    raise exception 'unsupported rehearsal code';
  end if;
  if p_result not in ('PASS','FAIL') then raise exception 'invalid rehearsal result'; end if;
  if p_detail is null or char_length(trim(p_detail)) not between 3 and 2000
     or public.s7_has_unsafe_control_characters(p_detail) then
    raise exception 'a rehearsal detail is required';
  end if;
  v_hash := encode(digest(jsonb_build_object(
    'project_id', p_project_id, 'rehearsal_code', p_rehearsal_code,
    'result', p_result, 'detail', trim(p_detail))::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':s7-rehearsal:' || trim(p_idempotency_key), 0));
  select * into v_existing from public.s7_pilot_rehearsals
  where organization_id = p_organization_id and idempotency_key = trim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'idempotency key payload mismatch'; end if;
    return v_existing.id;
  end if;

  insert into public.s7_pilot_rehearsals(
    organization_id, project_id, rehearsal_code, result, detail, evidence,
    executed_by, idempotency_key, request_hash
  ) values (
    p_organization_id, p_project_id, p_rehearsal_code, p_result, trim(p_detail),
    coalesce(p_evidence, '{}'::jsonb), v_actor, trim(p_idempotency_key), v_hash
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_id, event_type, entity_type, entity_id, payload)
  values (p_organization_id, v_actor, 'S7_PILOT_REHEARSAL_RECORDED', 's7_pilot_rehearsal', v_id,
    jsonb_build_object('project_id', p_project_id, 'rehearsal_code', p_rehearsal_code,
      'result', p_result));
  return v_id;
end $$;

-- ===========================================================================
-- 4. Read models, including the machine-verifiable acceptance report.
-- ===========================================================================
create or replace view public.s7_uat_tasks_read with (security_invoker=on) as
select
  t.id as task_id,
  t.organization_id,
  t.project_id,
  t.task_code,
  public.s7_export_safe_text(t.title) as title,
  public.s7_export_safe_text(t.expected_outcome) as expected_outcome,
  t.status,
  t.executed_by,
  t.executed_at,
  public.s7_export_safe_text(t.execution_evidence_reference) as execution_evidence_reference,
  t.reviewed_by,
  t.reviewed_at,
  public.s7_export_safe_text(t.acceptance_evidence_reference) as acceptance_evidence_reference,
  public.s7_export_safe_text(t.notes) as notes,
  public.s7_export_safe_text(t.rejection_reason) as rejection_reason,
  t.created_by,
  t.created_at
from public.s7_uat_tasks t;

create or replace view public.s7_pilot_rehearsals_read with (security_invoker=on) as
select
  r.id as rehearsal_id,
  r.organization_id,
  r.project_id,
  r.rehearsal_code,
  r.result,
  public.s7_export_safe_text(r.detail) as detail,
  r.evidence,
  r.executed_by,
  r.executed_at
from public.s7_pilot_rehearsals r;

-- The acceptance report is derived entirely from posted/recorded facts. Every
-- technical line is machine-verifiable; the human line reports UAT status and
-- never converts an automated PASS into customer acceptance.
create or replace view public.s7_pilot_acceptance_report_read with (security_invoker=on) as
select
  p.id as project_id,
  p.organization_id,
  p.reporting_currency,
  -- Opening import.
  coalesce(imp.posted_imports, 0) as posted_opening_imports,
  coalesce(imp.rejected_rows, 0) as opening_import_rejected_rows,
  coalesce(imp.control_totals_ok, false) as opening_control_totals_match,
  -- Reconciliation.
  coalesce(rec.checkpoints, 0) as reconciliation_checkpoints,
  coalesce(rec.non_zero_variances, 0) as reconciliation_non_zero_variances,
  coalesce(rec.max_abs_variance, 0)::text as reconciliation_max_abs_variance_minor_units,
  coalesce(exc.open_exceptions, 0) as unresolved_exceptions,
  coalesce(exc.open_critical, 0) as unresolved_critical_exceptions,
  -- Cash and ledger integrity.
  coalesce(cash.unreconciled_statement_lines, 0) as unreconciled_bank_statement_lines,
  coalesce(bal.unbalanced_batches, 0) as unbalanced_journal_batches,
  -- Partner capital rollforward: closing must equal the derived rollforward
  -- for every investor, computed from posted lines only.
  coalesce(cap.rollforward_breaks, 0) as partner_capital_rollforward_breaks,
  coalesce(cap.investor_statement_total, 0)::text as investor_statement_total_minor_units,
  -- Technical rehearsals.
  reh.end_to_end_result,
  reh.backup_restore_result,
  reh.access_revocation_result,
  -- Human gate, reported separately and never inferred.
  coalesce(uat.total_tasks, 0) as uat_total_tasks,
  coalesce(uat.accepted_tasks, 0) as uat_accepted_tasks,
  coalesce(uat.rejected_tasks, 0) as uat_rejected_tasks,
  case
    when coalesce(uat.total_tasks, 0) = 0 then 'NOT_STARTED'
    when coalesce(uat.rejected_tasks, 0) > 0 then 'REJECTED'
    when coalesce(uat.accepted_tasks, 0) = uat.total_tasks then 'ACCEPTED'
    else 'PENDING'
  end as human_uat_status
from public.investment_projects p
left join lateral (
  select count(*) filter (where i.status = 'POSTED') as posted_imports,
         coalesce(sum(i.rejected_row_count), 0) as rejected_rows,
         bool_and(i.debit_variance_minor_units = 0 and i.credit_variance_minor_units = 0)
           filter (where i.status = 'POSTED') as control_totals_ok
  from public.s7_opening_imports i
  where i.organization_id = p.organization_id and i.project_id = p.id
) imp on true
left join lateral (
  select count(*) as checkpoints,
         count(*) filter (where c.variance_minor_units <> 0) as non_zero_variances,
         coalesce(max(abs(c.variance_minor_units)), 0) as max_abs_variance
  from public.s7_reconciliation_checkpoints c
  where c.organization_id = p.organization_id and c.project_id = p.id
) rec on true
left join lateral (
  select count(*) filter (where e.status = 'OPEN') as open_exceptions,
         count(*) filter (where e.status = 'OPEN' and e.severity = 'CRITICAL') as open_critical
  from public.s7_reconciliation_exceptions e
  where e.organization_id = p.organization_id and e.project_id = p.id
) exc on true
left join lateral (
  select count(*) as unreconciled_statement_lines
  from public.bank_statement_line_status_read l
  where l.organization_id = p.organization_id and l.project_id = p.id
    and not l.is_reconciled
) cash on true
left join lateral (
  select count(*) as unbalanced_batches
  from (
    select jl.batch_id
    from public.journal_lines jl
    where jl.organization_id = p.organization_id and jl.project_id = p.id
    group by jl.batch_id
    having sum(jl.debit_minor_units) <> sum(jl.credit_minor_units)
  ) b
) bal on true
left join lateral (
  -- The statement's closing capital is cross-checked against an independently
  -- derived journal balance for the same investor, so a break means the read
  -- model and the posted ledger genuinely disagree.
  select count(*) filter (
           where s.closing_capital_minor_units::numeric <> coalesce(led.balance, 0)
         ) as rollforward_breaks,
         coalesce(sum(s.closing_capital_minor_units::numeric), 0) as investor_statement_total
  from public.s5_partner_capital_statement_read s
  left join lateral (
    select coalesce(sum(jl.credit_minor_units::numeric - jl.debit_minor_units::numeric), 0) as balance
    from public.journal_lines jl
    join public.semantic_accounts sa on sa.id = jl.account_id
      and sa.role in ('CONTRIBUTED_CAPITAL','PARTNER_CAPITAL')
    where jl.organization_id = s.organization_id and jl.project_id = s.project_id
      and jl.party_id = s.participant_party_id and jl.currency = s.currency
  ) led on true
  where s.organization_id = p.organization_id and s.project_id = p.id
) cap on true
left join lateral (
  select
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'END_TO_END_CYCLE'))[1] as end_to_end_result,
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'BACKUP_RESTORE'))[1] as backup_restore_result,
    (array_agg(r.result order by r.executed_at desc) filter (where r.rehearsal_code = 'ACCESS_REVOCATION'))[1] as access_revocation_result
  from public.s7_pilot_rehearsals r
  where r.organization_id = p.organization_id and r.project_id = p.id
) reh on true
left join lateral (
  select count(*) as total_tasks,
         count(*) filter (where t.status = 'ACCEPTED') as accepted_tasks,
         count(*) filter (where t.status = 'REJECTED') as rejected_tasks
  from public.s7_uat_tasks t
  where t.organization_id = p.organization_id and t.project_id = p.id
) uat on true;

-- ===========================================================================
-- 5. Default-deny RLS and exact command permissions.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['s7_uat_tasks','s7_pilot_rehearsals'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_member(organization_id))', t || '_read', t);
    execute format('revoke all on public.%I from anon,authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

grant select on public.s7_uat_tasks_read, public.s7_pilot_rehearsals_read,
  public.s7_pilot_acceptance_report_read to authenticated;

revoke all on function public.s7_register_uat_task(uuid,uuid,text,text,text,text) from public, anon;
revoke all on function public.s7_record_uat_execution(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.s7_accept_uat_task(uuid,uuid,text,text) from public, anon;
revoke all on function public.s7_reject_uat_task(uuid,uuid,text,text) from public, anon;
revoke all on function public.s7_record_pilot_rehearsal(uuid,uuid,text,text,text,jsonb,text) from public, anon;

grant execute on function
  public.s7_register_uat_task(uuid,uuid,text,text,text,text),
  public.s7_record_uat_execution(uuid,uuid,text,text,text),
  public.s7_accept_uat_task(uuid,uuid,text,text),
  public.s7_reject_uat_task(uuid,uuid,text,text),
  public.s7_record_pilot_rehearsal(uuid,uuid,text,text,text,jsonb,text)
to authenticated;
