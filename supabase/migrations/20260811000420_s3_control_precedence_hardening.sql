-- GF-005 / S3 control-precedence hardening.
-- A property-wide control is applicable to every parcel, but a later parcel-specific
-- control supersedes it for that parcel. Conversely, a later property-wide control
-- supersedes earlier parcel-specific records. Material lifecycle transitions that
-- depend on control must use the latest applicable evidence for every parcel.

create or replace function public.s3_has_current_effective_control(
  p_property_asset_id uuid,
  p_record_type text
) returns boolean
language sql stable set search_path=pg_catalog,public as $$
  with asset_parcels as (
    select p.id
    from public.parcels p
    where p.property_asset_id=p_property_asset_id
  ), property_latest as (
    select c.status,c.effective_date,c.expiry_date
    from public.property_control_records c
    where c.property_asset_id=p_property_asset_id
      and c.record_type=p_record_type
      and c.parcel_id is null
    order by c.recorded_at desc,c.id desc
    limit 1
  ), parcel_coverage as (
    select p.id as parcel_id,
           current_control.status,
           current_control.effective_date,
           current_control.expiry_date
    from asset_parcels p
    left join lateral (
      select c.status,c.effective_date,c.expiry_date
      from public.property_control_records c
      where c.property_asset_id=p_property_asset_id
        and c.record_type=p_record_type
        and (c.parcel_id is null or c.parcel_id=p.id)
      order by c.recorded_at desc,c.id desc
      limit 1
    ) current_control on true
  )
  select case
    when exists(select 1 from asset_parcels) then
      not exists (
        select 1
        from parcel_coverage c
        where c.status is distinct from 'PASSED'
           or c.effective_date is null
           or c.effective_date>current_date
           or (c.expiry_date is not null and c.expiry_date<current_date)
      )
    else
      exists (
        select 1
        from property_latest c
        where c.status='PASSED'
          and c.effective_date is not null
          and c.effective_date<=current_date
          and (c.expiry_date is null or c.expiry_date>=current_date)
      )
    end;
$$;

create or replace function public.s3_validate_property_transition() returns trigger
language plpgsql set search_path=pg_catalog,public as $$
declare v_current text; v_current_history uuid;
begin
  perform 1 from public.property_assets a where a.id = new.property_asset_id for update;
  select h.id,h.new_state into v_current_history,v_current
  from public.property_asset_state_history h where h.property_asset_id=new.property_asset_id
  order by h.changed_at desc,h.id desc limit 1;

  if public.s3_validate_history_predecessor(
    v_current_history,v_current,new.previous_history_id,new.previous_state,new.new_state,'CANDIDATE'
  ) then return new; end if;

  if not ((v_current = 'CANDIDATE' and new.new_state = 'DUE_DILIGENCE')
       or (v_current = 'DUE_DILIGENCE' and new.new_state = 'ACQUIRING')
       or (v_current = 'ACQUIRING' and new.new_state = 'HELD')
       or (v_current = 'HELD' and new.new_state = 'DEVELOPING')
       or (v_current = 'DEVELOPING' and new.new_state = 'HELD')) then
    raise exception 'invalid property lifecycle transition: % -> %', v_current, new.new_state;
  end if;

  if v_current = 'DUE_DILIGENCE' and new.new_state = 'ACQUIRING' then
    if not exists (
      select 1 from public.property_acquisitions a
      where a.property_asset_id = new.property_asset_id
    ) then
      raise exception 'acquiring requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'ACQUISITION_CHECK') then
      raise exception 'acquiring requires current effective passed acquisition due-diligence coverage';
    end if;
  end if;

  if v_current = 'ACQUIRING' and new.new_state = 'HELD' then
    if not exists (
      select 1 from public.property_acquisitions a
      where a.property_asset_id = new.property_asset_id
    ) then
      raise exception 'held requires a recorded acquisition contract';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE') then
      raise exception 'held requires current effective passed title coverage';
    end if;
    if not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'held requires current effective passed possession coverage';
    end if;
  end if;

  if v_current = 'HELD' and new.new_state = 'DEVELOPING' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'development requires current effective title and possession coverage';
    end if;
    if not exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'ACTIVE'
    ) then raise exception 'developing requires an active development phase'; end if;
  end if;

  if v_current = 'DEVELOPING' and new.new_state = 'HELD' then
    if not public.s3_has_current_effective_control(new.property_asset_id,'TITLE')
       or not public.s3_has_current_effective_control(new.property_asset_id,'POSSESSION') then
      raise exception 'returning to held requires current effective title and possession coverage';
    end if;
    if exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'ACTIVE'
    ) then raise exception 'returning to held requires no active development phase'; end if;
    if not exists (
      select 1 from public.development_phases p
      where p.property_asset_id = new.property_asset_id
        and public.s3_current_phase_state(p.id) = 'COMPLETED'
    ) then raise exception 'returning to held requires a completed development phase'; end if;
  end if;

  return new;
end $$;

revoke all on function public.s3_has_current_effective_control(uuid,text)
from public,anon,authenticated;
