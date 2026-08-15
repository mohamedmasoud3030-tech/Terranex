-- GF-023 review hardening — temporal integrity for optional Animal identity.
--
-- A backdated identity must not make any already-known later point in the
-- Cohort timeline contain more identified Animals than the authoritative
-- GF-022 quantity ledger supports. Identity remains a zero-quantity fact.

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

  -- Because Animal facts are immutable, a retroactive insert affects identity
  -- count at every later instant. Validate the resulting timeline at the new
  -- identity instant, every later existing identity checkpoint, and every
  -- already-known later GF-022 quantity checkpoint. This prevents a T2 identity
  -- followed by a backdated T1 identity from silently producing 2 identities
  -- against a one-head Cohort at T2.
  for v_checkpoint in
    select checkpoints.checkpoint
    from (
      select new.identified_at as checkpoint
      union
      select a.identified_at
      from public.livestock_animals a
      where a.identification_cohort_id = new.identification_cohort_id
        and a.identified_at > new.identified_at
      union
      select q.effective_at
      from public.livestock_quantity_events q
      where q.cohort_id = new.identification_cohort_id
        and q.effective_at > new.identified_at
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
