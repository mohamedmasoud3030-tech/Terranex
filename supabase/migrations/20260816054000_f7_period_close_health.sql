-- F7 — Period Close Health.
--
-- The close/correction machinery (S6) is verified against the mission exit
-- criteria in docs/F7_PERIOD_CLOSE_AUDIT.md. This migration adds the one
-- management surface that was missing: a per-scope health read model that
-- shows, for every project/currency, the open period, the latest closed
-- period, any close runs or exceptions in flight, open correction requests,
-- and the F3 dispute/overdue state — so a controller can see in one view
-- whether the close pipeline is clean without joining raw tables.

create or replace view public.period_close_health_read with (security_invoker=on) as
with scope as (
  select distinct organization_id, project_id, reporting_currency
  from public.accounting_periods
),
open_period as (
  select organization_id, project_id, reporting_currency,
         id as open_period_id, start_date as open_period_start,
         end_date as open_period_end, version as open_period_version
  from public.accounting_periods
  where status = 'OPEN'
),
latest_closed as (
  select distinct on (organization_id, project_id, reporting_currency)
         organization_id, project_id, reporting_currency,
         id as last_closed_period_id, closed_at as last_closed_at,
         closed_by as last_closed_by, version as last_closed_version
  from public.accounting_periods
  where status = 'CLOSED'
  order by organization_id, project_id, reporting_currency, closed_at desc
),
in_flight as (
  select cr.organization_id, cr.project_id,
         count(*) filter (where cr.status <> 'APPROVED') as open_close_runs,
         count(*) filter (where cr.status = 'APPROVED') as approved_close_runs
  from public.close_runs cr
  group by cr.organization_id, cr.project_id
),
open_exceptions as (
  select e.organization_id, cr.project_id, count(*) as open_close_exceptions
  from public.close_run_exceptions e
  join public.close_runs cr on cr.id = e.close_run_id
  where e.status = 'PENDING'
  group by e.organization_id, cr.project_id
),
open_corrections as (
  select organization_id, project_id, count(*) as open_correction_requests
  from public.correction_requests
  where status = 'REQUESTED'
  group by organization_id, project_id
),
contract_state as (
  select d.organization_id, d.project_id,
         count(distinct case when d.status = 'OPEN' then d.obligation_id end)
           as open_disputes,
         count(distinct case when d.status = 'OPEN' and d.is_disputed
            then d.obligation_id end) as payment_blocked_obligations,
         count(distinct case when d.status = 'AUTHORIZED'
            and d.aging_bucket like 'OVERDUE%'
            and d.outstanding_minor_units::bigint > 0 then d.obligation_id end)
           as overdue_obligations
  from public.cost_obligation_due_read d
  group by d.organization_id, d.project_id
)
select
  s.organization_id,
  s.project_id,
  s.reporting_currency,
  op.open_period_id,
  op.open_period_start,
  op.open_period_end,
  op.open_period_version,
  lc.last_closed_period_id,
  lc.last_closed_at,
  lc.last_closed_by,
  lc.last_closed_version,
  coalesce(inf.open_close_runs, 0) as open_close_runs,
  coalesce(inf.approved_close_runs, 0) as approved_close_runs,
  coalesce(oe.open_close_exceptions, 0) as open_close_exceptions,
  coalesce(oc.open_correction_requests, 0) as open_correction_requests,
  coalesce(cs.open_disputes, 0) as open_disputes,
  coalesce(cs.payment_blocked_obligations, 0) as payment_blocked_obligations,
  coalesce(cs.overdue_obligations, 0) as overdue_obligations,
  case
    when op.open_period_id is null then 'NO_OPEN_PERIOD'
    when coalesce(inf.open_close_runs, 0) > 0 then 'CLOSE_RUN_IN_FLIGHT'
    when coalesce(oc.open_correction_requests, 0) > 0 then 'CORRECTION_IN_FLIGHT'
    when coalesce(cs.overdue_obligations, 0) > 0 then 'OVERDUE_OBLIGATIONS'
    when coalesce(cs.open_disputes, 0) > 0 then 'OPEN_DISPUTES'
    else 'CLEAN'
  end as close_health
from scope s
left join open_period op
  on op.organization_id = s.organization_id and op.project_id = s.project_id
 and op.reporting_currency = s.reporting_currency
left join latest_closed lc
  on lc.organization_id = s.organization_id and lc.project_id = s.project_id
 and lc.reporting_currency = s.reporting_currency
left join in_flight inf
  on inf.organization_id = s.organization_id and inf.project_id = s.project_id
left join open_exceptions oe
  on oe.organization_id = s.organization_id and oe.project_id = s.project_id
left join open_corrections oc
  on oc.organization_id = s.organization_id and oc.project_id = s.project_id
left join contract_state cs
  on cs.organization_id = s.organization_id and cs.project_id = s.project_id;

grant select on public.period_close_health_read to authenticated;
