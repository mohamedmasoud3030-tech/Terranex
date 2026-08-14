-- GF-015 follow-up integrity guard: an input lot cannot be applied before it exists.
--
-- This file shares the GF-015 migration-family prefix intentionally. The existing
-- GF-015 forward-upgrade fixture skips the whole 20260814001200* family when it
-- constructs the pre-GF-015 boundary, while normal ordered replay applies this
-- file immediately after 20260814001200_agriculture_input_application.sql.
--
-- The trigger already installed by the primary GF-015 migration calls this
-- function by OID, so CREATE OR REPLACE strengthens the table boundary without
-- changing grants, RLS, command signatures, or any prior migration on main.

create or replace function public.gf015_guard_input_application_invariants()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_assignment record;
  v_lot record;
begin
  select * into v_assignment
    from public.crop_cycle_field_assignments a
   where a.id = new.assignment_id
     and a.organization_id = new.organization_id
   for share;
  if not found then
    raise exception 'crop cycle field assignment not found for input application';
  end if;
  if new.applied_area_unit <> v_assignment.assigned_area_unit then
    raise exception 'applied area unit (%) must match the assignment area unit (%)',
      new.applied_area_unit, v_assignment.assigned_area_unit;
  end if;
  if new.applied_area_quantity > v_assignment.assigned_area_quantity then
    raise exception 'applied area exceeds the assigned area: applied=%, assigned=%, unit=%',
      new.applied_area_quantity, v_assignment.assigned_area_quantity, v_assignment.assigned_area_unit;
  end if;

  select * into v_lot
    from public.input_lots l
   where l.id = new.input_lot_id
     and l.organization_id = new.organization_id
   for share;
  if not found then
    raise exception 'input lot not found for input application';
  end if;

  if v_lot.manufactured_on is not null and new.application_date < v_lot.manufactured_on then
    raise exception 'input lot manufactured on % cannot be applied on earlier date %',
      v_lot.manufactured_on, new.application_date;
  end if;

  if v_lot.expires_on is not null and new.application_date > v_lot.expires_on then
    raise exception 'input lot expired on % and cannot be applied on %',
      v_lot.expires_on, new.application_date;
  end if;
  return new;
end $$;
