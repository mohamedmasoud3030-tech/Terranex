-- GF-007 / S6 hardening — controlled carrying-source correction state.
--
-- S4 carrying-cost provenance is an immutable financial fact. S6 added only
-- correction metadata (`status` + `reversal_correction_request_id`) but left
-- the original blanket UPDATE trigger in place, making the documented S6
-- correction command impossible to execute. Preserve every S4 economic and
-- provenance field exactly; permit only the correction-state transition that
-- is linked to the same approved correction chain.

create or replace function public.s6_guard_carrying_source_correction_transition()
returns trigger
language plpgsql
set search_path=pg_catalog,public
as $$
declare
  v_correction record;
  v_recognition_batch_id uuid;
begin
  if old.status <> 'ACTIVE' then
    raise exception 'S4 carrying-cost correction state is final once reversed or superseded';
  end if;

  if new.status not in ('REVERSED','SUPERSEDED') then
    raise exception 'S4 carrying-cost source may only transition from ACTIVE to REVERSED or SUPERSEDED';
  end if;

  if new.reversal_correction_request_id is null then
    raise exception 'S4 carrying-cost source reversal requires a correction_request reference';
  end if;

  -- Economics and original provenance are immutable. Only the S6 correction
  -- metadata introduced after S4 may change.
  if new.id <> old.id
     or new.organization_id <> old.organization_id
     or new.project_id <> old.project_id
     or new.recognition_id <> old.recognition_id
     or new.property_cost_item_id <> old.property_cost_item_id
     or new.obligation_id <> old.obligation_id
     or new.journal_batch_id <> old.journal_batch_id
     or new.journal_line_id <> old.journal_line_id
     or new.amount_minor_units <> old.amount_minor_units
     or new.currency <> old.currency
     or new.policy_reference <> old.policy_reference
     or new.created_at <> old.created_at then
    raise exception 'confirmed S4 carrying-cost economics and provenance are immutable';
  end if;

  select r.journal_batch_id
    into v_recognition_batch_id
  from public.property_sale_recognitions r
  where r.id = old.recognition_id
    and r.organization_id = old.organization_id
    and r.project_id = old.project_id;

  if v_recognition_batch_id is null then
    raise exception 'carrying-cost source recognition not found';
  end if;

  select * into v_correction
  from public.correction_requests c
  where c.id = new.reversal_correction_request_id
    and c.organization_id = old.organization_id
    and c.project_id = old.project_id
    and c.target_batch_id = v_recognition_batch_id;

  if not found or v_correction.status not in ('APPROVED','EXECUTED') then
    raise exception 'carrying-cost source reversal requires the matching APPROVED correction_request';
  end if;

  return new;
end $$;

-- Replace only the UPDATE half of the original S4 blanket immutable trigger.
-- DELETE remains impossible and uses the canonical S4 immutable guard.
drop trigger if exists property_sale_carrying_sources_immutable
  on public.property_sale_carrying_cost_sources;

drop trigger if exists property_sale_carrying_sources_status_transition
  on public.property_sale_carrying_cost_sources;
create trigger property_sale_carrying_sources_status_transition
before update on public.property_sale_carrying_cost_sources
for each row execute function public.s6_guard_carrying_source_correction_transition();

drop trigger if exists property_sale_carrying_sources_no_delete
  on public.property_sale_carrying_cost_sources;
create trigger property_sale_carrying_sources_no_delete
before delete on public.property_sale_carrying_cost_sources
for each row execute function public.s4_guard_immutable();
