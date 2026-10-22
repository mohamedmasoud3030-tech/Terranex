-- S6 reopen chain: boundary-day sharing must be transitive.
--
-- `s6_reopen_period_impl` creates the successor period starting exactly on
-- the closed period's end_date and back-points to it via
-- `supersedes_period_id`. The original non-overlap guard exempted that
-- shared boundary day only against the directly superseded row. When the
-- superseded period is itself a one-day reopen successor (start = end =
-- its predecessor's end), the new period also touches the predecessor at
-- the same boundary day and the guard incorrectly rejected a legitimate
-- reopen (surfaced by supabase/tests/21_s5_concurrency.sh).
--
-- Fix: for a superseding period, sharing exactly one boundary day
-- (new.start_date = existing.end_date) is not an overlap, regardless of
-- which authoritative period in the chain owns that boundary. Genuine
-- range intersections (more than the shared boundary day) are still
-- rejected, and non-superseding periods get no exemption.

create or replace function public.s6_guard_period_no_overlap()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare v_conflict record;
begin
  if new.start_date > new.end_date then
    raise exception 'period start_date must be on or before end_date';
  end if;

  if new.status = 'OPEN' then
    select id into v_conflict
    from public.accounting_periods
    where organization_id = new.organization_id
      and project_id = new.project_id
      and reporting_currency = new.reporting_currency
      and status = 'OPEN'
      and id <> new.id;
    if found then
      raise exception 'an open period already exists for this project and currency';
    end if;
  end if;

  select id into v_conflict
  from public.accounting_periods
  where organization_id = new.organization_id
    and project_id = new.project_id
    and reporting_currency = new.reporting_currency
    and id <> new.id
    and daterange(start_date, end_date, '[]') && daterange(new.start_date, new.end_date, '[]')
    and not (
      new.supersedes_period_id is not null
      and new.start_date = end_date
    );
  if found then
    raise exception 'period dates overlap another authoritative period for this project and currency';
  end if;

  return new;
end $function$;
