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

-- The stable lifecycle transition trigger is defined once in the S3 base
-- migration and consumes this migration's refined evidence policy helper.
revoke all on function public.s3_has_current_effective_control(uuid,text)
from public,anon,authenticated;
