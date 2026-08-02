-- Migration: hard guard that the active equity_pct of partners on a project
-- never sums to more than 100%, even if an UPDATE bypasses change_ownership_atomic.
-- Date: 2026-08-02

create or replace function public.trg_validate_project_equity_sum()
returns trigger language plpgsql as $$
declare
  v_sum numeric;
begin
  -- Re-validate all equity_pcts of the affected project that are still active.
  select coalesce(sum(equity_pct), 0)
    into v_sum
    from public.project_partners
   where project_id = coalesce(new.project_id, old.project_id)
     and effective_to is null;

  if v_sum > 100.0001 then
    raise exception 'مجموع نسب الملكية للمشروع يتجاوز 100%% (الإجمالي الحالي %s%%)', round(v_sum, 2);
  end if;
  return coalesce(new, old);
end; $$;

drop trigger if exists trg_validate_project_equity_sum on public.project_partners;
create trigger trg_validate_project_equity_sum
after insert or update or delete on public.project_partners
for each row execute function public.trg_validate_project_equity_sum();
