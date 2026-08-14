-- GF-021 temporal-policy clarification.
--
-- WeightEvent is an immutable dated observation in GF-021; this slice does not
-- derive a singular "current weight" from it. Therefore future-dated weight
-- rows are allowed as effective-dated log entries and cannot change current
-- placement or current quantity. Movement and GF-022 quantity/operation facts
-- remain forbidden in the future by 20260814001910.
--
-- The as-of population guard still applies to weight metadata: sample/measured
-- counts are validated against quantity at the WeightEvent's effective time.
create or replace function public.gf022_review_weight_guard() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare
  v_opening_at timestamptz;
  v_quantity integer;
begin
  perform public.gf021_require_active_cohort(
    new.organization_id, new.project_id, new.cohort_id
  );
  v_opening_at := public.livestock_cohort_opening_effective_at(new.cohort_id);
  if new.effective_at < v_opening_at then
    raise exception 'livestock weight effective time precedes cohort opening';
  end if;

  v_quantity := public.gf022_lock_cohort_quantity_as_of(
    new.cohort_id, new.effective_at
  );
  if v_quantity <= 0 then
    raise exception 'livestock cohort has zero quantity for this operation';
  end if;
  if new.measured_animal_count is not null
     and new.measured_animal_count > v_quantity then
    raise exception 'livestock measured animal count exceeds quantity as of effective time';
  end if;
  if new.sample_size is not null and new.sample_size > v_quantity then
    raise exception 'livestock sample size exceeds quantity as of effective time';
  end if;
  return new;
end $$;