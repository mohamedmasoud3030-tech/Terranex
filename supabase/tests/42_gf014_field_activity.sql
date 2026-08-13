-- GF-014 / Field Activity Foundation.
--
-- Proves valid creation, idempotency, payload mismatch, validation,
-- Real Estate rejection, assignment coherence, append-only / direct
-- write denial, and that recording an activity does not advance
-- CropCycle lifecycle state.

create or replace function s14_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s14_catch(p_user uuid, p_sql text)
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

create or replace function s14_with_auth(p_user uuid, p_sql text)
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

create or replace function s14_owner_catch(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    return v_msg;
  end;
  return 'NO_EXCEPTION';
end $$;

select id as s14_ag_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s14_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset
select id as s14_farm from public.farms where internal_reference='FARM-A' \gset
select id as s14_field from public.fields where identifier='حقل شمال' \gset

-- Dedicated cycle + assignment for field activities so we do not
-- collide with GF-013 unique (org, project, season, crop).
select s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'برسيم','بلدي','موسم 2026/2027-FA',date '2026-11-01',date '2027-04-01',null,null,'s14-cycle-001')$$
  , :'s14_ag_project')) as s14_cycle \gset

select s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'2.5','FEDDAN',date '2026-11-01',date '2027-04-01','s14-assign-001')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field')) as s14_assign \gset

-- 1. Valid activity creation.
select s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','IRRIGATE','12.5','م³','ري صباحي','سجل ري','s14-act-001')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign')) as s14_act \gset

select 1/case when (
  select activity_type = 'IRRIGATE' and recorded_by = '00000000-0000-4000-8000-000000000001'
  from public.field_activities where id = :'s14_act'
) then 1 else 0 end as s14_valid_create;

select 1/case when exists (
  select 1 from public.audit_events
  where event_type = 'FIELD_ACTIVITY_CREATED' and entity_id = :'s14_act'
) then 1 else 0 end as s14_audit_recorded;

-- Activity must not advance CropCycle lifecycle.
select 1/case when public.agriculture_current_cycle_state(:'s14_cycle') = 'PLANNED'
  then 1 else 0 end as s14_does_not_advance_lifecycle;

-- 2. Same idempotency key + same payload returns the same row.
select 1/case when s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','IRRIGATE','12.5','م³','ري صباحي','سجل ري','s14-act-001')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign')) = :'s14_act'
  then 1 else 0 end as s14_idempotent_same_payload;

-- 3. Same key + different payload is rejected.
select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-16','PLANT',null,null,null,null,'s14-act-001')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%idempotency key payload mismatch%' then 1 else 0 end
  as s14_payload_mismatch_rejected;

-- 4. Invalid activity type / date / quantity-unit combinations.
select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','HARVEST',null,null,null,null,'s14-act-bad-type')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%invalid activity type%' then 1 else 0 end as s14_invalid_type_rejected;

select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,null,'SCOUT',null,null,null,null,'s14-act-bad-date')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%invalid activity date%' then 1 else 0 end as s14_invalid_date_rejected;

select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','SCOUT','3',null,null,null,'s14-act-qty-only')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%quantity and unit must be provided together%' then 1 else 0 end
  as s14_qty_without_unit_rejected;

select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','SCOUT',null,'ساعة',null,null,'s14-act-unit-only')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%quantity and unit must be provided together%' then 1 else 0 end
  as s14_unit_without_qty_rejected;

select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','SCOUT','-1','ساعة',null,null,'s14-act-neg')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%quantity must be positive%' then 1 else 0 end
  as s14_non_positive_qty_rejected;

-- Optional pair both omitted is valid.
select 1/case when s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-18','SCOUT',null,null,'معاينة',null,'s14-act-002')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign')) is not null
  then 1 else 0 end as s14_optional_qty_omitted_ok;

-- 5. Activity cannot attach to a Real Estate project.
select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','WEED',null,null,null,null,'s14-act-re')$$
  , :'s14_re_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%agriculture project not found%' then 1 else 0 end
  as s14_rejects_real_estate_project;

-- 6. Activity cannot use a Field not assigned to its CropCycle.
-- Create a second field with no assignment to this cycle.
select s14_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل جنوب','8','FEDDAN',null,null,'s14-field-unassigned')$$
  , :'s14_ag_project', :'s14_farm')) as s14_field_b \gset

select 1/case when s14_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-15','WEED',null,null,null,null,'s14-act-unassigned')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field_b', :'s14_assign'))
  like '%crop cycle field assignment not found%' then 1 else 0 end
  as s14_rejects_unassigned_field;

-- 7. Direct authenticated INSERT/UPDATE/DELETE is denied.
select 1/case when s14_with_auth('00000000-0000-4000-8000-000000000001', format(
  $$insert into public.field_activities(
      organization_id, project_id, crop_cycle_id, field_id, assignment_id,
      activity_date, activity_type, recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2026-11-20','OTHER',
      '00000000-0000-4000-8000-000000000001','s14-direct-ins','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  like '%permission denied%' then 1 else 0 end as s14_direct_insert_denied;

select 1/case when s14_owner_catch(format(
  $$update public.field_activities set notes = 'تعديل' where id = %L$$
  , :'s14_act')) like '%append-only%' then 1 else 0 end as s14_update_rejected;

select 1/case when s14_owner_catch(format(
  $$delete from public.field_activities where id = %L$$
  , :'s14_act')) like '%append-only%' then 1 else 0 end as s14_delete_rejected;

-- 8. Tenant B cannot read or create against Tenant A.
insert into public.organizations(id, name)
  values ('20000000-0000-4000-8000-000000000099', 'منظمة باء-ب')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role)
  values ('20000000-0000-4000-8000-000000000099', '00000000-0000-4000-8000-000000000002', 'OWNER')
  on conflict (organization_id, user_id) do nothing;

select 1/case when s14_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_field_activity('20000000-0000-4000-8000-000000000099',%L,%L,%L,%L,date '2026-11-15','OTHER',null,null,null,null,'s14-cross')$$
  , :'s14_ag_project', :'s14_cycle', :'s14_field', :'s14_assign'))
  is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s14_tenant_b_create_rejected;

create or replace function s14_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

select 1/case when s14_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.field_activities_read') = 0 then 1 else 0 end
  as s14_tenant_b_cannot_read;

reset role;
select 'S14 Field Activity foundation PASS' as result;
