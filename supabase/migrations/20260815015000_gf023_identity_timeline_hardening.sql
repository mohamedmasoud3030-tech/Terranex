-- GF-023 review hardening — temporal integrity for optional Animal identity.
--
-- A backdated identity must not invalidate any already-accepted later identity
-- checkpoint. Identity remains a zero-quantity provenance fact; this hardening
-- deliberately does not infer individual life status from later Cohort-level
-- mortality, sale, split, merge, or other quantity events.

create or replace function public.gf023_validate_animal() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_checkpoint timestamptz;
  v_quantity integer;
  v_identified integer;
begin
  new.identifier_normalized := public.gf023_normalize_identifier(new.identifier_value);
  if char_length(new.identifier_normalized) not between 1 and 100 then
    raise exception 'invalid livestock Animal identifier';
  end if;

  -- Reuse the authoritative GF-022 per-Cohort lock and validate the insertion
  -- instant first. This also serializes against concurrent quantity commands.
  perform public.gf023_validate_operational_target(
    new.organization_id, new.project_id, new.identification_cohort_id,
    null, new.identified_at, false
  );

  -- A retroactive identity is visible at every later identity checkpoint. The
  -- new fact is valid only if the resulting identified count remains supported
  -- at its own instant and at every already-accepted later identification
  -- instant. We intentionally do not add arbitrary later quantity checkpoints:
  -- GF-023 has no individual death/transfer/current-status model, so doing that
  -- would falsely treat every identified Animal as permanently active.
  for v_checkpoint in
    select checkpoints.checkpoint
    from (
      select new.identified_at as checkpoint
      union
      select a.identified_at
      from public.livestock_animals a
      where a.identification_cohort_id = new.identification_cohort_id
        and a.identified_at > new.identified_at
    ) as checkpoints
    order by checkpoints.checkpoint
  loop
    select count(*) into v_identified
    from public.livestock_animals a
    where a.identification_cohort_id = new.identification_cohort_id
      and a.identified_at <= v_checkpoint;

    -- NEW is not visible yet because this is a BEFORE INSERT trigger.
    v_identified := v_identified + 1;
    v_quantity := public.livestock_cohort_quantity_as_of(
      new.identification_cohort_id, v_checkpoint
    );

    if v_identified > v_quantity then
      raise exception 'identified Animal count exceeds Cohort quantity at the effective timeline';
    end if;
  end loop;

  return new;
end $$;

-- Keep the helper internal after CREATE OR REPLACE regardless of inherited ACL.
revoke all on function public.gf023_validate_animal()
from public, anon, authenticated;
