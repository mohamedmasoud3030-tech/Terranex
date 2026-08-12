-- GF-008 / S5 — source concurrency and PostgreSQL portability hardening.
-- The base S5 migration intentionally broadens the existing active-source
-- check. Serialize the check in a small earlier trigger instead of redefining
-- the proven S2 guard body a second time.

create or replace function public.s5_lock_material_journal_source() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
begin
  if new.source_type <> 'REVERSAL' then
    perform pg_advisory_xact_lock(hashtextextended(
      'active-journal-source:' || new.organization_id::text || ':' ||
      new.source_type || ':' || new.source_id::text,
      0
    ));
  end if;
  return new;
end $$;

drop trigger if exists journal_batches_00_source_lock on public.journal_batches;
create trigger journal_batches_00_source_lock
before insert on public.journal_batches
for each row execute function public.s5_lock_material_journal_source();

-- PostgreSQL does not provide min(uuid) on every supported installation.
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
