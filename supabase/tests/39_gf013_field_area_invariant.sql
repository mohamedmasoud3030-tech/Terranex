-- GF-013 / Agriculture field-area invariant.
--
-- Proves the database-level invariant:
--   * Assigned area is positive.
--   * Assigned area unit equals the Field's area unit.
--   * For overlapping (half-open) ranges of non-cancelled cycles, the
--     total assigned area never exceeds the Field's area.
--   * Two ranges that touch (a.end = b.start) are NOT considered
--     overlapping; both fit if each individually fits.

create or replace function s13b_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
end $$;

create or replace function s13b_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

-- Reuse the agriculture project and farm from the previous suite.
select id as s13b_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s13b_farm    from public.farms where internal_reference = 'FARM-A' \gset

-- Create a fresh field of 10 FEDDAN for capacity tests.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل السعة 10 ف','10','FEDDAN',null,null,'s13b-field-001')$$
  , :'s13b_project', :'s13b_farm')) as s13b_field \gset

-- A pair of crop cycles for the capacity test.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'قمح','a','سعة-1',date '2026-10-01',date '2027-03-01','3000','كجم/فدان','s13b-cycle-A')$$
  , :'s13b_project')) as s13b_cycle_a \gset
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'شوفان','b','سعة-2',date '2026-12-01',date '2027-02-01','1500','كجم/فدان','s13b-cycle-B')$$
  , :'s13b_project')) as s13b_cycle_b \gset

-- Cycle A: assign 6 FEDDAN (under capacity).
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'6','FEDDAN',date '2026-10-01',date '2027-03-01','s13b-assign-A')$$
  , :'s13b_project', :'s13b_cycle_a', :'s13b_field')) as s13b_ass_a \gset

-- Cycle B: tries to assign 5 FEDDAN that fully overlaps Cycle A.
-- Combined with Cycle A's 6 FEDDAN, total would be 11 FEDDAN, exceeding
-- the 10-FED field capacity. Must fail.
select 1/case when s13b_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'5','FEDDAN',date '2026-12-01',date '2027-02-01','s13b-assign-B')$$
  , :'s13b_project', :'s13b_cycle_b', :'s13b_field')) like '%field area capacity exceeded%' then 1 else 0 end
  as s13b_capacity_exceeded_rejected;

-- Cycle B: assign 4 FEDDAN. Combined 6 + 4 = 10 FEDDAN = capacity. OK.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'4','FEDDAN',date '2026-12-01',date '2027-02-01','s13b-assign-B2')$$
  , :'s13b_project', :'s13b_cycle_b', :'s13b_field')) as s13b_ass_b \gset

-- Now a NEW cycle that does not overlap must be allowed even if its
-- area is the full field — half-open [start, end) means boundary-
-- touching ranges do not overlap.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'برسيم','c','سعة-3',date '2027-03-01',date '2027-08-01','2500','كجم/فدان','s13b-cycle-C')$$
  , :'s13b_project')) as s13b_cycle_c \gset

-- Boundary-touching non-overlapping assignment: 10 FEDDAN starting on
-- 2027-03-01 (Cycle A ended 2027-03-01; half-open means no overlap).
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'10','FEDDAN',date '2027-03-01',date '2027-08-01','s13b-assign-C')$$
  , :'s13b_project', :'s13b_cycle_c', :'s13b_field')) as s13b_ass_c \gset

-- Assigned area must be positive.
select 1/case when s13b_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'0','FEDDAN',date '2028-01-01',date '2028-02-01','s13b-assign-zero')$$
  , :'s13b_project', :'s13b_cycle_c', :'s13b_field')) like '%assigned area must be positive%' then 1 else 0 end
  as s13b_assigned_area_positive;

-- Unit must match.
select 1/case when s13b_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'1000','M2',date '2028-03-01',date '2028-04-01','s13b-assign-m2')$$
  , :'s13b_project', :'s13b_cycle_c', :'s13b_field')) like '%assigned area unit%must match%' then 1 else 0 end
  as s13b_unit_must_match_field;

-- Cancelling Cycle A frees its capacity. A new cycle overlapping
-- Cycle A's range can now be assigned.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','CANCELLED','إلغاء الدورة','مذكرة','s13b-cancel-A')$$
  , :'s13a_cycle3'));  -- dummy, will fail; just placeholder
-- Cancel cycle A (it is still PLANNED).
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','CANCELLED','إلغاء الدورة','مذكرة','s13b-cancel-A-real')$$
  , :'s13b_cycle_a'));
select 1/case when public.agriculture_current_cycle_state(:'s13b_cycle_a') = 'CANCELLED' then 1 else 0 end
  as s13b_cycle_a_cancelled;

-- A new cycle in the same range can now be assigned up to capacity.
select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'شعير','d','سعة-4',date '2026-10-15',date '2027-02-15','2000','كجم/فدان','s13b-cycle-D')$$
  , :'s13b_project')) as s13b_cycle_d \gset

select s13b_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'7','FEDDAN',date '2026-11-01',date '2027-01-15','s13b-assign-D')$$
  , :'s13b_project', :'s13b_cycle_d', :'s13b_field')) as s13b_ass_d \gset

reset role;
select 'S13 field-area invariant PASS' as result;
