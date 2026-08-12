-- GF-007 / S6 — Close read models and RLS surface for the close workspace.
--
-- These views are the only browser-facing read surface for S6. Money is
-- transported as text. Each view is security_invoker so RLS on the base
-- tables continues to apply per requester.

create or replace view public.accounting_periods_read with (security_invoker=on) as
select
  p.id as period_id, p.organization_id, p.project_id, p.reporting_currency,
  p.start_date, p.end_date, p.status, p.version, p.supersedes_period_id,
  p.opened_at, p.opened_by, p.closed_at, p.closed_by, p.source_close_run_id,
  cr.version as source_close_version, cr.snapshot_id as source_close_snapshot_id
from public.accounting_periods p
left join public.close_runs cr on cr.id = p.source_close_run_id;

create or replace view public.close_runs_read with (security_invoker=on) as
select
  cr.id as close_run_id, cr.organization_id, cr.project_id, cr.period_id,
  cr.version, cr.status, cr.source_cutoff_date, cr.generated_at, cr.generated_by,
  cr.reviewed_by, cr.reviewed_at, cr.approved_by, cr.approved_at,
  cr.approval_idempotency_key, cr.notes,
  p.start_date as period_start_date, p.end_date as period_end_date,
  p.reporting_currency, p.supersedes_period_id,
  s.id as snapshot_id, s.content_hash as snapshot_content_hash, s.captured_at as snapshot_captured_at,
  (select count(*) from public.close_run_gates g where g.close_run_id = cr.id and g.result = 'PASS') as passing_gates,
  (select count(*) from public.close_run_gates g where g.close_run_id = cr.id and g.result = 'FAIL') as failing_gates,
  (select count(*) from public.close_run_gates g where g.close_run_id = cr.id and g.result = 'APPROVED_EXCEPTION') as exception_gates,
  (select count(*) from public.close_run_gates g where g.close_run_id = cr.id and g.result = 'NOT_APPLICABLE') as not_applicable_gates
from public.close_runs cr
join public.accounting_periods p on p.id = cr.period_id
left join public.close_run_snapshots s on s.close_run_id = cr.id;

create or replace view public.close_run_gates_read with (security_invoker=on) as
select
  g.id as gate_id, g.organization_id, g.close_run_id, g.gate_code, g.result, g.detail,
  g.evidence, g.evaluated_at, g.exception_id,
  e.status as exception_status, e.reason as exception_reason, e.evidence_reference as exception_evidence_reference,
  e.materiality_comment as exception_materiality_comment,
  e.approved_by as exception_approved_by, e.approved_at as exception_approved_at
from public.close_run_gates g
left join public.close_run_exceptions e on e.id = g.exception_id;

create or replace view public.close_run_exceptions_read with (security_invoker=on) as
select
  e.id as exception_id, e.organization_id, e.close_run_id, e.gate_code, e.reason,
  e.evidence_reference, e.materiality_comment,
  e.requested_by, e.requested_at, e.approved_by, e.approved_at, e.status,
  cr.project_id, cr.period_id
from public.close_run_exceptions e
join public.close_runs cr on cr.id = e.close_run_id;

create or replace view public.close_run_snapshots_read with (security_invoker=on) as
select
  s.id as snapshot_id, s.organization_id, s.close_run_id, s.project_id, s.period_id,
  s.content_hash, s.totals, s.captured_at,
  cr.version as close_version, cr.status as close_status,
  cr.source_cutoff_date, cr.approved_by, cr.approved_at
from public.close_run_snapshots s
join public.close_runs cr on cr.id = s.close_run_id;

create or replace view public.correction_requests_read with (security_invoker=on) as
select
  c.id as correction_id, c.organization_id, c.project_id,
  c.target_batch_id, jb.source_type as target_source_type, jb.transaction_date as target_transaction_date,
  c.source_period_id, c.correction_period_id, c.reason, c.evidence_reference,
  c.status, c.requested_by, c.requested_at, c.reviewed_by, c.reviewed_at,
  c.reversal_batch_id, c.replacement_batch_id
from public.correction_requests c
join public.journal_batches jb on jb.id = c.target_batch_id;

grant select on public.accounting_periods_read, public.close_runs_read,
  public.close_run_gates_read, public.close_run_exceptions_read,
  public.close_run_snapshots_read, public.correction_requests_read to authenticated;
