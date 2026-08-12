-- GF-005 / S3 truthful workspace projection.
-- The property card must not present the newest single parcel record as though it
-- represented whole-asset title/possession. Expose PASSED only when current
-- effective evidence covers the complete asset; otherwise expose INCOMPLETE.

-- Safe for authenticated reads: this helper is SECURITY INVOKER and therefore
-- remains constrained by the caller's RLS visibility on property controls/parcels.
grant execute on function public.s3_has_current_effective_control(uuid,text) to authenticated;

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
  order by h.changed_at desc,h.id desc limit 1
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

grant select on public.property_asset_workspace_read to authenticated;
