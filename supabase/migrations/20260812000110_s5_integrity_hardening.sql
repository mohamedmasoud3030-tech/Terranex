-- GF-008 / S5 — integrity hardening.
-- Keep the proven S2 source-posting guard unchanged and add an S5-specific
-- source guard. This avoids changing historical S2 concurrency semantics.

create or replace function public.s2_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('CONTRIBUTION_CASH_ATTRIBUTION','COST_OBLIGATION','PAYMENT') then
    perform pg_advisory_xact_lock(hashtextextended(
      's2-active-source:' || new.organization_id::text || ':' || new.source_type || ':' || new.source_id::text,
      0
    ));

    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'source already has an active posting';
    end if;
  end if;
  return new;
end $$;

create or replace function public.s5_guard_one_active_source_posting() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type in ('S5_ALLOCATION','S5_DISTRIBUTION_APPROVAL','S5_DISTRIBUTION_PAYMENT') then
    perform pg_advisory_xact_lock(hashtextextended(
      's5-active-source:' || new.organization_id::text || ':' || new.source_type || ':' || new.source_id::text,
      0
    ));

    if exists (
      select 1 from public.journal_batches jb
      where jb.source_type = new.source_type
        and jb.source_id = new.source_id
        and jb.organization_id = new.organization_id
        and not exists (
          select 1 from public.journal_batches rb
          where rb.reversal_of_batch_id = jb.id
        )
    ) then
      raise exception 'S5 source already has an active posting';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists journal_batches_s5_one_active_source_guard on public.journal_batches;
create trigger journal_batches_s5_one_active_source_guard
before insert on public.journal_batches
for each row execute function public.s5_guard_one_active_source_posting();

-- PostgreSQL does not provide min(uuid) on every supported installation.
-- Resolve the single open period with an explicit count and lookup instead.
create or replace function public.s5_require_open_posting_date(
  p_organization_id uuid,p_project_id uuid,p_posting_date date
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_count integer;
begin
  if p_posting_date is null then raise exception 'posting date is required'; end if;
  select count(*) into v_count
  from public.accounting_periods
  where organization_id=p_organization_id and project_id=p_project_id
    and status='OPEN' and p_posting_date between start_date and end_date;
  if v_count<>1 then raise exception 'S5 posting requires exactly one OPEN accounting period covering the posting date'; end if;
  select id into v_id
  from public.accounting_periods
  where organization_id=p_organization_id and project_id=p_project_id
    and status='OPEN' and p_posting_date between start_date and end_date
  limit 1;
  return v_id;
end $$;
revoke all on function public.s5_require_open_posting_date(uuid,uuid,date) from public,anon,authenticated;
