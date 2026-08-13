-- GF-013 / Agriculture field-area invariant hardening.
--
-- The server-authoritative command `assign_crop_cycle_to_field` already
-- enforces the capacity invariant with FOR UPDATE on the Field row and
-- a per-command advisory lock. This migration adds a defence-in-depth
-- row trigger that re-checks the same invariant at the table boundary
-- so the invariant also holds for any direct INSERT (including test
-- fixtures). It does not replace the command-level check; it is the
-- last line of defence.
--
-- Boundary semantics (per GF-013 spec):
--   * assigned area is strictly positive;
--   * assigned area unit equals the Field's area unit;
--   * planned ranges are inclusive-start, exclusive-end;
--   * two ranges that touch (a.end = b.start) are NOT overlapping;
--   * for the Field, the sum of assigned areas for any non-cancelled
--     cycle whose planned range overlaps the new one must not exceed
--     the Field's area.

create or replace function public.s8a_guard_field_assignment_invariant()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_field record;
  v_total numeric(20,6);
begin
  select * into v_field
    from public.fields
   where id = new.field_id
     and organization_id = new.organization_id
   for share;
  if not found then
    raise exception 'field not found for assignment';
  end if;
  if new.assigned_area_unit <> v_field.area_unit then
    raise exception 'assigned area unit (%) must match the field area unit (%)',
      new.assigned_area_unit, v_field.area_unit;
  end if;
  select coalesce(sum(a.assigned_area_quantity), 0)
    into v_total
    from public.crop_cycle_field_assignments a
    join public.crop_cycles c on c.id = a.crop_cycle_id
   where a.field_id = new.field_id
     and a.organization_id = new.organization_id
     and a.id <> new.id
     and coalesce(public.agriculture_current_cycle_state(c.id), 'PLANNED') <> 'CANCELLED'
     and a.planned_start_date < new.planned_end_date
     and a.planned_end_date   > new.planned_start_date;
  if v_total + new.assigned_area_quantity > v_field.area_quantity then
    raise exception 'field area capacity exceeded: existing=%, new=%, field=%, unit=%',
      v_total, new.assigned_area_quantity, v_field.area_quantity, v_field.area_unit;
  end if;
  return new;
end $$;

drop trigger if exists crop_cycle_field_assignments_capacity_check
  on public.crop_cycle_field_assignments;
create trigger crop_cycle_field_assignments_capacity_check
  before insert on public.crop_cycle_field_assignments
  for each row execute function public.s8a_guard_field_assignment_invariant();
