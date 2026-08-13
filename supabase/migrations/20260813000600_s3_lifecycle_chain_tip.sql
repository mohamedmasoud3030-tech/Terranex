-- S3 lifecycle histories are causal linked lists. `changed_at` is an audit
-- timestamp, not an ordering key: PostgreSQL `now()` is transaction-stable, so
-- several valid transitions inside one transaction can share the same time.
-- Ordering equal timestamps by random UUID can therefore choose an ancestor as
-- the current state. Derive current state and every predecessor from the unique
-- unconsumed chain tip instead.

create or replace function public.s3_property_history_tip_id(p_property_asset_id uuid)
returns uuid language sql stable set search_path=pg_catalog,public as $$
  select h.id
  from public.property_asset_state_history h
  where h.property_asset_id = p_property_asset_id
    and not exists (
      select 1 from public.property_asset_state_history next_h
      where next_h.property_asset_id = h.property_asset_id
        and next_h.previous_history_id = h.id
    )
$$;

create or replace function public.s3_phase_history_tip_id(p_phase_id uuid)
returns uuid language sql stable set search_path=pg_catalog,public as $$
  select h.id
  from public.development_phase_state_history h
  where h.phase_id = p_phase_id
    and not exists (
      select 1 from public.development_phase_state_history next_h
      where next_h.phase_id = h.phase_id
        and next_h.previous_history_id = h.id
    )
$$;

create or replace function public.s3_milestone_history_tip_id(p_milestone_id uuid)
returns uuid language sql stable set search_path=pg_catalog,public as $$
  select h.id
  from public.development_milestone_state_history h
  where h.milestone_id = p_milestone_id
    and not exists (
      select 1 from public.development_milestone_state_history next_h
      where next_h.milestone_id = h.milestone_id
        and next_h.previous_history_id = h.id
    )
$$;

revoke all on function public.s3_property_history_tip_id(uuid),
  public.s3_phase_history_tip_id(uuid), public.s3_milestone_history_tip_id(uuid)
  from public, anon, authenticated;

create or replace function public.s3_current_property_state(p_property_asset_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state
  from public.property_asset_state_history h
  where h.id = public.s3_property_history_tip_id(p_property_asset_id)
$$;

create or replace function public.s3_current_phase_state(p_phase_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state
  from public.development_phase_state_history h
  where h.id = public.s3_phase_history_tip_id(p_phase_id)
$$;

create or replace function public.s3_current_milestone_state(p_milestone_id uuid)
returns text language sql stable set search_path=pg_catalog,public as $$
  select h.new_state
  from public.development_milestone_state_history h
  where h.id = public.s3_milestone_history_tip_id(p_milestone_id)
$$;

-- Preserve the existing S3/S4 business rules verbatim. Only replace the stale
-- timestamp/UUID predecessor lookup in the three commands and three trigger
-- validators. Using pg_get_functiondef here intentionally preserves the S4
-- EXITING/DISPOSED extension and any earlier security hardening.
do $rewrite_lifecycle$
declare
  v_oid regprocedure;
  v_definition text;
  v_rewritten text;
begin
  v_oid := 'public.transition_property_asset(uuid,uuid,text,text,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := replace(
    v_definition,
    '(select h.id from public.property_asset_state_history h where h.property_asset_id=p_property_asset_id order by h.changed_at desc,h.id desc limit 1)',
    'public.s3_property_history_tip_id(p_property_asset_id)'
  );
  if v_rewritten = v_definition then raise exception 'property transition predecessor rewrite did not match'; end if;
  execute v_rewritten;

  v_oid := 'public.transition_development_phase(uuid,uuid,text,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := replace(
    v_definition,
    '(select h.id from public.development_phase_state_history h where h.phase_id=p_phase_id order by h.changed_at desc,h.id desc limit 1)',
    'public.s3_phase_history_tip_id(p_phase_id)'
  );
  if v_rewritten = v_definition then raise exception 'phase transition predecessor rewrite did not match'; end if;
  execute v_rewritten;

  v_oid := 'public.transition_development_milestone(uuid,uuid,text,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := replace(
    v_definition,
    '(select h.id from public.development_milestone_state_history h where h.milestone_id=p_milestone_id order by h.changed_at desc,h.id desc limit 1)',
    'public.s3_milestone_history_tip_id(p_milestone_id)'
  );
  if v_rewritten = v_definition then raise exception 'milestone transition predecessor rewrite did not match'; end if;
  execute v_rewritten;

  v_oid := 'public.s3_validate_property_transition()'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := regexp_replace(
    v_definition,
    'from public[.]property_asset_state_history h where h[.]property_asset_id=new[.]property_asset_id[[:space:]]+order by h[.]changed_at desc,h[.]id desc limit 1;',
    'from public.property_asset_state_history h where h.id=public.s3_property_history_tip_id(new.property_asset_id);',
    'g'
  );
  if v_rewritten = v_definition then raise exception 'property transition validator rewrite did not match'; end if;
  execute v_rewritten;

  v_oid := 'public.s3_validate_phase_transition()'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := regexp_replace(
    v_definition,
    'from public[.]development_phase_state_history h where h[.]phase_id=new[.]phase_id[[:space:]]+order by h[.]changed_at desc,h[.]id desc limit 1;',
    'from public.development_phase_state_history h where h.id=public.s3_phase_history_tip_id(new.phase_id);',
    'g'
  );
  if v_rewritten = v_definition then raise exception 'phase transition validator rewrite did not match'; end if;
  execute v_rewritten;

  v_oid := 'public.s3_validate_milestone_transition()'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_rewritten := regexp_replace(
    v_definition,
    'from public[.]development_milestone_state_history h where h[.]milestone_id=new[.]milestone_id[[:space:]]+order by h[.]changed_at desc,h[.]id desc limit 1;',
    'from public.development_milestone_state_history h where h.id=public.s3_milestone_history_tip_id(new.milestone_id);',
    'g'
  );
  if v_rewritten = v_definition then raise exception 'milestone transition validator rewrite did not match'; end if;
  execute v_rewritten;
end
$rewrite_lifecycle$;

-- Read models must resolve the same causal state as commands. Keep the later
-- workspace-control truth semantics while replacing only state selection.
create or replace view public.property_asset_workspace_read with (security_invoker=on) as
select a.id as property_asset_id,a.organization_id,a.project_id,a.name,a.asset_reference,
       p.strategy,p.jurisdiction,s.new_state as operational_state,s.changed_at as state_changed_at,
       case
         when public.s3_has_current_effective_control(a.id,'TITLE') then 'PASSED'
         when exists(select 1 from public.property_control_records c where c.property_asset_id=a.id and c.record_type='TITLE') then 'INCOMPLETE'
         else null
       end as title_status,
       case when public.s3_has_current_effective_control(a.id,'TITLE') then title.effective_date else null end as title_effective_date,
       case when public.s3_has_current_effective_control(a.id,'TITLE') then title.evidence_reference else null end as title_evidence_reference,
       case
         when public.s3_has_current_effective_control(a.id,'POSSESSION') then 'PASSED'
         when exists(select 1 from public.property_control_records c where c.property_asset_id=a.id and c.record_type='POSSESSION') then 'INCOMPLETE'
         else null
       end as possession_status,
       case when public.s3_has_current_effective_control(a.id,'POSSESSION') then possession.effective_date else null end as possession_effective_date,
       case when public.s3_has_current_effective_control(a.id,'POSSESSION') then possession.evidence_reference else null end as possession_evidence_reference,
       acq.id as acquisition_id,
       case when acq.id is null then 'NOT_RECORDED' else 'CONTRACT_RECORDED' end as acquisition_state,
       acq.contract_reference,acq.contract_date,acq.consideration_minor_units::text as consideration_minor_units,
       acq.closing_costs_minor_units::text as closing_costs_minor_units,acq.currency as acquisition_currency,
       acq.consideration_obligation_id,
       case when acq.consideration_obligation_id is null then 'NOT_LINKED'
            when op.is_reversed then 'OBLIGATION_REVERSED'
            when op.status='DRAFT' then 'OBLIGATION_DRAFT'
            when op.paid_minor_units::bigint=0 then 'UNPAID'
            when op.outstanding_minor_units::bigint=0 then 'PAID'
            else 'PARTIALLY_PAID' end as acquisition_payment_status
from public.property_assets a
join public.real_estate_project_profiles p on p.id=a.profile_id
left join lateral (
  select h.new_state,h.changed_at
  from public.property_asset_state_history h
  where h.property_asset_id=a.id
    and not exists (
      select 1 from public.property_asset_state_history next_h
      where next_h.property_asset_id=h.property_asset_id and next_h.previous_history_id=h.id
    )
) s on true
left join lateral (
  select c.effective_date,c.evidence_reference
  from public.property_control_records c
  where c.property_asset_id=a.id and c.record_type='TITLE'
  order by c.recorded_at desc,c.id desc limit 1
) title on true
left join lateral (
  select c.effective_date,c.evidence_reference
  from public.property_control_records c
  where c.property_asset_id=a.id and c.record_type='POSSESSION'
  order by c.recorded_at desc,c.id desc limit 1
) possession on true
left join public.property_acquisitions acq on acq.property_asset_id=a.id
left join public.cost_obligation_position_read op on op.obligation_id=acq.consideration_obligation_id;

create or replace view public.development_phases_read with (security_invoker=on) as
select p.id as phase_id,p.organization_id,p.project_id,p.property_asset_id,p.parcel_id,p.name,p.sequence_no,
       p.planned_start_date,p.planned_end_date,s.new_state as operational_state,
       active.changed_at as actual_start_at,completed.changed_at as actual_end_at,p.created_at
from public.development_phases p
left join lateral (
  select h.new_state from public.development_phase_state_history h
  where h.phase_id=p.id
    and not exists (
      select 1 from public.development_phase_state_history next_h
      where next_h.phase_id=h.phase_id and next_h.previous_history_id=h.id
    )
) s on true
left join lateral (select min(h.changed_at) as changed_at from public.development_phase_state_history h where h.phase_id=p.id and h.new_state='ACTIVE') active on true
left join lateral (select min(h.changed_at) as changed_at from public.development_phase_state_history h where h.phase_id=p.id and h.new_state='COMPLETED') completed on true;

create or replace view public.development_milestones_read with (security_invoker=on) as
select m.id as milestone_id,m.organization_id,m.project_id,m.property_asset_id,m.phase_id,m.name,m.sequence_no,m.planned_date,
       s.new_state as operational_state,completed.changed_at as completed_at,m.created_at
from public.development_milestones m
left join lateral (
  select h.new_state from public.development_milestone_state_history h
  where h.milestone_id=m.id
    and not exists (
      select 1 from public.development_milestone_state_history next_h
      where next_h.milestone_id=h.milestone_id and next_h.previous_history_id=h.id
    )
) s on true
left join lateral (select min(h.changed_at) as changed_at from public.development_milestone_state_history h where h.milestone_id=m.id and h.new_state='COMPLETED') completed on true;

grant select on public.property_asset_workspace_read,public.development_phases_read,
  public.development_milestones_read to authenticated;
