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
