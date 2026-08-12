-- GF-007 / S6 test-fixture compatibility for historical S2 concurrency.
--
-- The S2 duplicate-posting race reuses contribution `contrib-main-a2-1`.
-- Its immutable occurred_on date is later than the S6 OPEN period created by
-- 16_s6_period_close.sql. Widen only that OPEN test period so the legacy race
-- reaches the S2 idempotency/concurrency invariant through the real S6 period
-- lock. This changes test fixture state only; no production trigger, command,
-- migration, or financial policy is bypassed.

do $$
declare
  v_project uuid;
  v_required_end date;
  v_open_period uuid;
begin
  if to_regclass('public.accounting_periods') is null then
    return;
  end if;

  select p.id into v_project
  from public.investment_projects p
  where p.name = 'مشروع النخيل'
  limit 1;

  select c.occurred_on into v_required_end
  from public.contributions c
  where c.idempotency_key = 'contrib-main-a2-1'
  limit 1;

  select ap.id into v_open_period
  from public.accounting_periods ap
  where ap.organization_id = '10000000-0000-4000-8000-000000000001'
    and ap.project_id = v_project
    and ap.status = 'OPEN'
  order by ap.version desc
  limit 1;

  if v_project is null or v_required_end is null or v_open_period is null then
    raise exception 'S6/S2 concurrency compatibility fixtures are incomplete';
  end if;

  update public.accounting_periods
  set end_date = greatest(end_date, v_required_end)
  where id = v_open_period;

  if not exists (
    select 1
    from public.accounting_periods ap
    where ap.id = v_open_period
      and v_required_end between ap.start_date and ap.end_date
  ) then
    raise exception 'S6 OPEN period does not cover the S2 contribution concurrency date';
  end if;
end $$;

select 1 / case when exists (
  select 1
  from public.accounting_periods ap
  join public.investment_projects p on p.id = ap.project_id
  join public.contributions c on c.project_id = p.id
  where p.name = 'مشروع النخيل'
    and c.idempotency_key = 'contrib-main-a2-1'
    and ap.status = 'OPEN'
    and c.occurred_on between ap.start_date and ap.end_date
) then 1 else 0 end as s6_s2_concurrency_window_ready;
