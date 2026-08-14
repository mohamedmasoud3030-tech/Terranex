-- GF-015 / Field Input Application Foundation.
--
-- Proves the bounded slice end to end:
--   * happy path across Input Item → Input Lot → Input Application,
--     read through the canonical read models, one audit event per
--     new command;
--   * idempotency: same key + same canonical payload returns the same
--     object and does not re-audit; same key + different payload is
--     rejected; no duplicate application row;
--   * project / crop cycle / field / assignment / activity coherence;
--   * activity/category mapping (SEED→PLANT, FERTILIZER→FERTILIZE,
--     CHEMICAL→SPRAY) and rejection of every other combination;
--   * lot expiry and manufacture/expiry ordering;
--   * area rules (positive, assignment unit, not above assigned area);
--   * quantity rules (positive, input item unit);
--   * security: anon execute denied, authenticated direct INSERT
--     denied, direct UPDATE/DELETE of an application denied;
--   * lifecycle isolation: no CropCycle state change;
--   * financial isolation: no journal / accounting / inventory rows.

create or replace function s15_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s15_catch(p_user uuid, p_sql text)
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

create or replace function s15_anon_catch(p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('role', 'anon', false);
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

create or replace function s15_owner_catch(p_sql text)
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

create or replace function s15_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

select id as s15_ag_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s15_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset
select id as s15_farm       from public.farms where internal_reference='FARM-A' \gset
select id as s15_field      from public.fields where identifier='حقل شمال' \gset

-- ---------------------------------------------------------------------------
-- Fixture: a dedicated cycle, an assignment of 4 FEDDAN, and one
-- activity of each input-bearing type plus one that must never accept
-- an input application.
-- ---------------------------------------------------------------------------
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ذرة','مبكرة','موسم 2027-IN',date '2027-05-01',date '2027-09-01',null,null,'s15-cycle-001')$$
  , :'s15_ag_project')) as s15_cycle \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'4','FEDDAN',date '2027-05-01',date '2027-09-01','s15-assign-001')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field')) as s15_assign \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-05-05','PLANT',null,null,'زراعة تقاوي',null,'s15-act-plant')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign')) as s15_act_plant \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-06-01','FERTILIZE',null,null,'تسميد أول',null,'s15-act-fert')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign')) as s15_act_fert \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-06-10','SPRAY',null,null,'رش وقائي',null,'s15-act-spray')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign')) as s15_act_spray \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-06-12','SCOUT',null,null,'معاينة',null,'s15-act-scout')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign')) as s15_act_scout \gset

-- ---------------------------------------------------------------------------
-- 1. Happy path: item, lot, application.
-- ---------------------------------------------------------------------------
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'FERTILIZER','يوريا 46%%','FERT-UREA','كجم','شركة الأسمدة','سماد نيتروجيني','s15-item-fert')$$
  , :'s15_ag_project')) as s15_item_fert \gset

select 1/case when (
  select category = 'FERTILIZER' and application_unit = 'كجم'
     and created_by = '00000000-0000-4000-8000-000000000001'
  from public.input_items where id = :'s15_item_fert'
) then 1 else 0 end as s15_item_created;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'INPUT_ITEM_CREATED' and entity_id = :'s15_item_fert'
) = 1 then 1 else 0 end as s15_item_audit_once;

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-U-2027-01','مورد الوادي',date '2027-01-01',date '2028-01-01','فاتورة 991','s15-lot-fert')$$
  , :'s15_item_fert')) as s15_lot_fert \gset

-- The lot unit is derived from the item, never supplied by the caller.
select 1/case when (
  select unit = 'كجم' and project_id = :'s15_ag_project'::uuid
  from public.input_lots where id = :'s15_lot_fert'
) then 1 else 0 end as s15_lot_unit_derived_from_item;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'INPUT_LOT_CREATED' and entity_id = :'s15_lot_fert'
) = 1 then 1 else 0 end as s15_lot_audit_once;

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','200','كجم','4','FEDDAN','دفعة أولى','قفازات وكمامة','صورة السجل','s15-app-001')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert')) as s15_app \gset

-- Scope is derived from the activity: project, cycle, field, assignment.
select 1/case when (
  select project_id = :'s15_ag_project'::uuid
     and crop_cycle_id = :'s15_cycle'::uuid
     and field_id = :'s15_field'::uuid
     and assignment_id = :'s15_assign'::uuid
     and activity_type = 'FERTILIZE'
     and input_category = 'FERTILIZER'
     and unit = 'كجم'
     and applied_area_unit = 'FEDDAN'
     and recorded_by = '00000000-0000-4000-8000-000000000001'
  from public.input_applications where id = :'s15_app'
) then 1 else 0 end as s15_application_scope_derived;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'INPUT_APPLICATION_RECORDED' and entity_id = :'s15_app'
) = 1 then 1 else 0 end as s15_application_audit_once;

-- 1b. Canonical read models return the operator-facing projection,
--     including the derived (never stored) application rate.
select 1/case when s15_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.input_applications_read
     where id = %L and application_rate = '50.000000' and lot_expiry_status = 'VALID'
       and input_item_name = 'يوريا 46%%' and lot_reference = 'LOT-U-2027-01'$$
  , :'s15_app')) = 1 then 1 else 0 end as s15_read_model_projection;

select 1/case when s15_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.input_items_read where id = %L$$, :'s15_item_fert'))
  = 1 then 1 else 0 end as s15_items_read_visible;

select 1/case when s15_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.input_lots_read where id = %L and expiry_status in ('VALID','EXPIRED','NO_EXPIRY')$$
  , :'s15_lot_fert')) = 1 then 1 else 0 end as s15_lots_read_visible;

-- ---------------------------------------------------------------------------
-- 2. Idempotency.
-- ---------------------------------------------------------------------------
-- Same key + same canonical payload → same row. '200.00' and '4.0'
-- normalize to the stored numeric(20,6) payload, so presentation
-- formatting is not a false mismatch.
select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','200.00','كجم','4.0','FEDDAN','دفعة أولى','قفازات وكمامة','صورة السجل','s15-app-001')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert')) = :'s15_app'
  then 1 else 0 end as s15_idempotent_same_payload;

select 1/case when (
  select count(*) from public.input_applications where idempotency_key = 's15-app-001'
) = 1 then 1 else 0 end as s15_no_duplicate_application;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'INPUT_APPLICATION_RECORDED' and entity_id = :'s15_app'
) = 1 then 1 else 0 end as s15_idempotent_replay_does_not_re_audit;

-- Same key + different payload → explicit rejection.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','250','كجم','4','FEDDAN','دفعة أولى','قفازات وكمامة','صورة السجل','s15-app-001')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%idempotency key payload mismatch%' then 1 else 0 end
  as s15_payload_mismatch_rejected;

select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'FERTILIZER','يوريا 46%%','FERT-UREA','كجم','شركة الأسمدة','سماد نيتروجيني','s15-item-fert')$$
  , :'s15_ag_project')) = :'s15_item_fert' then 1 else 0 end as s15_item_idempotent;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'SEED','يوريا 46%%','FERT-UREA','كجم',null,null,'s15-item-fert')$$
  , :'s15_ag_project')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s15_item_payload_mismatch_rejected;

select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-U-2027-01','مورد الوادي',date '2027-01-01',date '2028-01-01','فاتورة 991','s15-lot-fert')$$
  , :'s15_item_fert')) = :'s15_lot_fert' then 1 else 0 end as s15_lot_idempotent;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-OTHER',null,null,null,null,'s15-lot-fert')$$
  , :'s15_item_fert')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s15_lot_payload_mismatch_rejected;

-- ---------------------------------------------------------------------------
-- 3. Activity / category coherence.
-- ---------------------------------------------------------------------------
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'SEED','تقاوي ذرة هجين','SEED-MAIZE','كجم',null,null,'s15-item-seed')$$
  , :'s15_ag_project')) as s15_item_seed \gset
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-S-2027-01',null,null,date '2028-06-01',null,'s15-lot-seed')$$
  , :'s15_item_seed')) as s15_lot_seed \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'CHEMICAL','مبيد حشري','CHEM-INSECT','لتر',null,null,'s15-item-chem')$$
  , :'s15_ag_project')) as s15_item_chem \gset
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-C-2027-01',null,null,date '2028-03-01',null,'s15-lot-chem')$$
  , :'s15_item_chem')) as s15_lot_chem \gset

-- Valid mappings.
select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-05-05','60','كجم','4','FEDDAN',null,null,null,'s15-app-seed')$$
  , :'s15_act_plant', :'s15_item_seed', :'s15_lot_seed')) is not null
  then 1 else 0 end as s15_seed_plant_ok;

select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-10','2.5','لتر','3','FEDDAN',null,'فترة أمان 7 أيام',null,'s15-app-chem')$$
  , :'s15_act_spray', :'s15_item_chem', :'s15_lot_chem')) is not null
  then 1 else 0 end as s15_chemical_spray_ok;

-- SEED against FERTILIZE is rejected.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-app-bad-1')$$
  , :'s15_act_fert', :'s15_item_seed', :'s15_lot_seed'))
  like '%requires a PLANT activity%' then 1 else 0 end as s15_seed_against_fertilize_rejected;

-- FERTILIZER against PLANT is rejected.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-05-05','10','كجم','1','FEDDAN',null,null,null,'s15-app-bad-2')$$
  , :'s15_act_plant', :'s15_item_fert', :'s15_lot_fert'))
  like '%requires a FERTILIZE activity%' then 1 else 0 end as s15_fertilizer_against_plant_rejected;

-- CHEMICAL against SCOUT is rejected, and SCOUT never accepts an input.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-12','1','لتر','1','FEDDAN',null,null,null,'s15-app-bad-3')$$
  , :'s15_act_scout', :'s15_item_chem', :'s15_lot_chem'))
  like '%does not accept an input application%' then 1 else 0 end
  as s15_chemical_against_scout_rejected;

-- CHEMICAL against FERTILIZE is rejected.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','1','لتر','1','FEDDAN',null,null,null,'s15-app-bad-4')$$
  , :'s15_act_fert', :'s15_item_chem', :'s15_lot_chem'))
  like '%requires a SPRAY activity%' then 1 else 0 end as s15_chemical_against_fertilize_rejected;

-- ---------------------------------------------------------------------------
-- 4. Lot / item coherence.
-- ---------------------------------------------------------------------------
-- A lot that belongs to another item cannot be applied.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-app-bad-lot')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_seed'))
  like '%input lot not found%' then 1 else 0 end as s15_lot_from_other_item_rejected;

-- ---------------------------------------------------------------------------
-- 5. Expiry.
-- ---------------------------------------------------------------------------
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-U-EXPIRED',null,date '2026-01-01',date '2027-05-31',null,'s15-lot-expired')$$
  , :'s15_item_fert')) as s15_lot_expired \gset

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-app-expired')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_expired'))
  like '%expired on%' then 1 else 0 end as s15_expired_lot_rejected;

-- Application exactly on the expiry date is still valid.
select 1/case when s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-05-31','10','كجم','1','FEDDAN',null,null,null,'s15-app-on-expiry')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_expired')) is not null
  then 1 else 0 end as s15_application_on_expiry_date_ok;

-- manufactured_on must not be after expires_on.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-BAD-DATES',null,date '2028-01-01',date '2027-01-01',null,'s15-lot-bad-dates')$$
  , :'s15_item_fert')) like '%manufacture date must not be after the expiry date%'
  then 1 else 0 end as s15_manufacture_after_expiry_rejected;

-- ---------------------------------------------------------------------------
-- 6. Area invariant.
-- ---------------------------------------------------------------------------
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','0','FEDDAN',null,null,null,'s15-area-zero')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area must be positive%' then 1 else 0 end as s15_zero_area_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','-2','FEDDAN',null,null,null,'s15-area-neg')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area must be positive%' then 1 else 0 end as s15_negative_area_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','4.000001','FEDDAN',null,null,null,'s15-area-over')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area exceeds the assigned area%' then 1 else 0 end as s15_area_above_assignment_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','HECTARE',null,null,null,'s15-area-unit')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area unit must be the assignment area unit%' then 1 else 0 end
  as s15_area_unit_mismatch_rejected;

-- GF-015 does not convert units. An unsupported unit is refused, not
-- silently converted.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','ACRE',null,null,null,'s15-area-acre')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  is distinct from 'NO_EXCEPTION' then 1 else 0 end as s15_unknown_area_unit_rejected;

-- ---------------------------------------------------------------------------
-- 7. Quantity invariant.
-- ---------------------------------------------------------------------------
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','0','كجم','1','FEDDAN',null,null,null,'s15-qty-zero')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%application quantity must be positive%' then 1 else 0 end as s15_zero_quantity_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','-5','كجم','1','FEDDAN',null,null,null,'s15-qty-neg')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%application quantity must be positive%' then 1 else 0 end as s15_negative_quantity_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','لتر','1','FEDDAN',null,null,null,'s15-qty-unit')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%application unit must be the input item unit%' then 1 else 0 end
  as s15_quantity_unit_mismatch_rejected;

-- ---------------------------------------------------------------------------
-- 8. Project / field / assignment coherence.
-- ---------------------------------------------------------------------------
-- An item created against a Real Estate project is refused.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'SEED','تقاوي','x','كجم',null,null,'s15-item-re')$$
  , :'s15_re_project')) like '%agriculture project not found%' then 1 else 0 end
  as s15_real_estate_project_rejected;

-- A second Agriculture project in the same tenant: its item cannot be
-- applied through this project's activity.
select s15_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع زراعي ثانٍ','GF015-AG-A2','x','AGRICULTURE')$$
) as s15_project_b \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'FERTILIZER','يوريا مشروع ثانٍ','FERT-P2','كجم',null,null,'s15-item-p2')$$
  , :'s15_project_b')) as s15_item_p2 \gset
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-P2',null,null,null,null,'s15-lot-p2')$$
  , :'s15_item_p2')) as s15_lot_p2 \gset

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-cross-project')$$
  , :'s15_act_fert', :'s15_item_p2', :'s15_lot_p2'))
  like '%input item not found%' then 1 else 0 end as s15_cross_project_item_rejected;

-- A FieldActivity from another assignment cannot be reused with this
-- project's item: create a second assignment + activity on a different
-- field and prove the derived scope follows the activity, not a guess.
select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field('10000000-0000-4000-8000-000000000001',%L,%L,'حقل مدخلات-٢','6','FEDDAN',null,null,'s15-field-b')$$
  , :'s15_ag_project', :'s15_farm')) as s15_field_b \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'2','FEDDAN',date '2027-05-01',date '2027-09-01','s15-assign-b')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field_b')) as s15_assign_b \gset

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_field_activity('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-06-02','FERTILIZE',null,null,null,null,'s15-act-fert-b')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field_b', :'s15_assign_b')) as s15_act_fert_b \gset

-- The second activity's assignment caps the applied area at 2 FEDDAN.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-02','10','كجم','4','FEDDAN',null,null,null,'s15-app-b-over')$$
  , :'s15_act_fert_b', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area exceeds the assigned area%' then 1 else 0 end
  as s15_second_assignment_area_cap_enforced;

select s15_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-02','10','كجم','2','FEDDAN',null,null,null,'s15-app-b-ok')$$
  , :'s15_act_fert_b', :'s15_item_fert', :'s15_lot_fert')) as s15_app_b \gset

select 1/case when (
  select field_id = :'s15_field_b'::uuid and assignment_id = :'s15_assign_b'::uuid
  from public.input_applications where id = :'s15_app_b'
) then 1 else 0 end as s15_scope_follows_activity;

-- A guessed field activity id is refused.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001','99999999-0000-4000-8000-000000000099',%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-app-guess')$$
  , :'s15_item_fert', :'s15_lot_fert'))
  like '%field activity not found%' then 1 else 0 end as s15_guessed_activity_rejected;

-- ---------------------------------------------------------------------------
-- 9. Security.
-- ---------------------------------------------------------------------------
select 1/case when s15_anon_catch(format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','10','كجم','1','FEDDAN',null,null,null,'s15-anon')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%permission denied%' then 1 else 0 end as s15_anon_execute_denied;

select 1/case when s15_anon_catch('select public.create_input_item(''10000000-0000-4000-8000-000000000001'',''00000000-0000-4000-8000-000000000000'',''SEED'',''x'',null,''كجم'',null,null,''s15-anon-item'')')
  like '%permission denied%' then 1 else 0 end as s15_anon_item_execute_denied;

select 1/case when s15_anon_catch('select public.create_input_lot(''10000000-0000-4000-8000-000000000001'',''00000000-0000-4000-8000-000000000000'',''x'',null,null,null,null,''s15-anon-lot'')')
  like '%permission denied%' then 1 else 0 end as s15_anon_lot_execute_denied;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$insert into public.input_applications(
      organization_id, project_id, crop_cycle_id, field_id, assignment_id,
      field_activity_id, input_item_id, input_lot_id, input_category, activity_type,
      application_date, quantity, unit, applied_area_quantity, applied_area_unit,
      recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,%L,'FERTILIZER','FERTILIZE',
      date '2027-06-01','1','كجم','1','FEDDAN','00000000-0000-4000-8000-000000000001',
      's15-direct-ins','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign',
    :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%permission denied%' then 1 else 0 end as s15_direct_application_insert_denied;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$insert into public.input_items(
      organization_id, project_id, category, name, application_unit,
      created_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,'SEED','x','كجم',
      '00000000-0000-4000-8000-000000000001','s15-direct-item',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project')) like '%permission denied%' then 1 else 0 end
  as s15_direct_item_insert_denied;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$insert into public.input_lots(
      organization_id, project_id, input_item_id, lot_reference, unit,
      created_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,'x','كجم',
      '00000000-0000-4000-8000-000000000001','s15-direct-lot',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project', :'s15_item_fert')) like '%permission denied%' then 1 else 0 end
  as s15_direct_lot_insert_denied;

-- Direct UPDATE / DELETE is refused even for the fixture owner.
select 1/case when s15_owner_catch(format(
  $$update public.input_applications set quantity = '1' where id = %L$$, :'s15_app'))
  like '%append-only%' then 1 else 0 end as s15_application_update_rejected;

select 1/case when s15_owner_catch(format(
  $$delete from public.input_applications where id = %L$$, :'s15_app'))
  like '%append-only%' then 1 else 0 end as s15_application_delete_rejected;

select 1/case when s15_owner_catch(format(
  $$update public.input_items set name = 'x' where id = %L$$, :'s15_item_fert'))
  like '%immutable%' then 1 else 0 end as s15_item_update_rejected;

select 1/case when s15_owner_catch(format(
  $$update public.input_lots set expires_on = date '2099-01-01' where id = %L$$, :'s15_lot_fert'))
  like '%immutable%' then 1 else 0 end as s15_lot_update_rejected;

-- Even privileged direct SQL cannot bypass the area / expiry invariants.
select 1/case when s15_owner_catch(format(
  $$insert into public.input_applications(
      organization_id, project_id, crop_cycle_id, field_id, assignment_id,
      field_activity_id, input_item_id, input_lot_id, input_category, activity_type,
      application_date, quantity, unit, applied_area_quantity, applied_area_unit,
      recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,%L,'FERTILIZER','FERTILIZE',
      date '2027-06-01','1','كجم','9','FEDDAN','00000000-0000-4000-8000-000000000001',
      's15-owner-area','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign',
    :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%applied area exceeds the assigned area%' then 1 else 0 end
  as s15_direct_sql_area_invariant_enforced;

select 1/case when s15_owner_catch(format(
  $$insert into public.input_applications(
      organization_id, project_id, crop_cycle_id, field_id, assignment_id,
      field_activity_id, input_item_id, input_lot_id, input_category, activity_type,
      application_date, quantity, unit, applied_area_quantity, applied_area_unit,
      recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,%L,'FERTILIZER','FERTILIZE',
      date '2027-06-01','1','كجم','1','FEDDAN','00000000-0000-4000-8000-000000000001',
      's15-owner-expired','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign',
    :'s15_act_fert', :'s15_item_fert', :'s15_lot_expired'))
  like '%expired on%' then 1 else 0 end as s15_direct_sql_expiry_invariant_enforced;

-- A guessed activity of the wrong type cannot be forced in by direct SQL:
-- the composite FK to (field_activity_id, ..., activity_type) refuses it.
select 1/case when s15_owner_catch(format(
  $$insert into public.input_applications(
      organization_id, project_id, crop_cycle_id, field_id, assignment_id,
      field_activity_id, input_item_id, input_lot_id, input_category, activity_type,
      application_date, quantity, unit, applied_area_quantity, applied_area_unit,
      recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,%L,%L,%L,'FERTILIZER','FERTILIZE',
      date '2027-06-12','1','كجم','1','FEDDAN','00000000-0000-4000-8000-000000000001',
      's15-owner-scout','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s15_ag_project', :'s15_cycle', :'s15_field', :'s15_assign',
    :'s15_act_scout', :'s15_item_fert', :'s15_lot_fert'))
  is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s15_direct_sql_activity_mapping_enforced;

-- ---------------------------------------------------------------------------
-- 10. Lifecycle isolation.
-- ---------------------------------------------------------------------------
select 1/case when public.agriculture_current_cycle_state(:'s15_cycle') = 'PLANNED'
  then 1 else 0 end as s15_does_not_advance_lifecycle;

select 1/case when (
  select count(*) from public.crop_cycle_state_history where crop_cycle_id = :'s15_cycle'
) = 1 then 1 else 0 end as s15_no_extra_lifecycle_history;

-- ---------------------------------------------------------------------------
-- 11. Financial isolation: no accounting / inventory side effect exists.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) from public.journal_batches
  where source_type ilike '%input%' or source_id = :'s15_app'
) = 0 then 1 else 0 end as s15_no_journal_batch;

select 1/case when (
  select count(*) from public.cost_obligations where project_id = :'s15_ag_project'
) = 0 then 1 else 0 end as s15_no_cost_obligation;

select 1/case when (
  select count(*) from public.project_payments where project_id = :'s15_ag_project'
) = 0 then 1 else 0 end as s15_no_payment;

select 1/case when (
  select count(*) from public.accounting_periods where project_id = :'s15_ag_project'
) = 0 then 1 else 0 end as s15_no_accounting_period;

select 1/case when (
  select count(*) from public.s5_distributions where project_id = :'s15_ag_project'
) = 0 then 1 else 0 end as s15_no_distribution;

-- No fake inventory columns exist anywhere in the GF-015 tables.
select 1/case when (
  select count(*) from information_schema.columns
  where table_schema = 'public'
    and table_name in ('input_items','input_lots','input_applications')
    and column_name in (
      'available_stock','current_quantity','remaining_quantity','lot_balance',
      'received_quantity','available_quantity','on_hand_quantity','unit_cost',
      'purchase_price','valuation_amount'
    )
) = 0 then 1 else 0 end as s15_no_fake_inventory_or_costing_columns;

-- GF-016 legitimately introduced harvest/inventory primitives, so the old
-- "no deferred tables" assertion is replaced: the GF-015 input tables must
-- remain identity/traceability records with no stock balance, and no sale,
-- valuation, or accounting artifact may have been fabricated.
select 1/case when (
  select count(*) from information_schema.tables
  where table_schema = 'public'
    and table_name in ('sale_orders','purchase_orders','warehouses','inventory_valuations','buyers','invoices','receivables')
) = 0 then 1 else 0 end as s15_no_sale_or_procurement_scaffolded;

-- ---------------------------------------------------------------------------
-- 12. Two-tenant isolation.
-- ---------------------------------------------------------------------------
insert into public.organizations(id, name)
  values ('20000000-0000-4000-8000-000000000099', 'منظمة باء-ب')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role)
  values ('20000000-0000-4000-8000-000000000099', '00000000-0000-4000-8000-000000000002', 'OWNER')
  on conflict (organization_id, user_id) do nothing;

select 1/case when s15_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.input_items_read') = 0 then 1 else 0 end
  as s15_tenant_b_cannot_read_items;
select 1/case when s15_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.input_lots_read') = 0 then 1 else 0 end
  as s15_tenant_b_cannot_read_lots;
select 1/case when s15_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.input_applications_read') = 0 then 1 else 0 end
  as s15_tenant_b_cannot_read_applications;

-- Tenant B cannot create against Tenant A's project.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_input_item('20000000-0000-4000-8000-000000000099',%L,'SEED','x','x','كجم',null,null,'s15-tb-item')$$
  , :'s15_ag_project')) like '%agriculture project not found%' then 1 else 0 end
  as s15_tenant_b_item_against_tenant_a_project_rejected;

-- Tenant B cannot reference Tenant A ids from its own organization.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_input_lot('20000000-0000-4000-8000-000000000099',%L,'x',null,null,null,null,'s15-tb-lot')$$
  , :'s15_item_fert')) like '%input item not found%' then 1 else 0 end
  as s15_tenant_b_lot_against_tenant_a_item_rejected;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.record_input_application('20000000-0000-4000-8000-000000000099',%L,%L,%L,date '2027-06-01','1','كجم','1','FEDDAN',null,null,null,'s15-tb-app')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%field activity not found%' then 1 else 0 end
  as s15_tenant_b_application_against_tenant_a_ids_rejected;

-- Tenant B cannot borrow Tenant A's organization id either.
select 1/case when s15_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.record_input_application('10000000-0000-4000-8000-000000000001',%L,%L,%L,date '2027-06-01','1','كجم','1','FEDDAN',null,null,null,'s15-tb-app-2')$$
  , :'s15_act_fert', :'s15_item_fert', :'s15_lot_fert'))
  like '%forbidden%' then 1 else 0 end
  as s15_tenant_b_cannot_borrow_tenant_a_organization;

-- ---------------------------------------------------------------------------
-- 13. RLS / grant posture.
-- ---------------------------------------------------------------------------
select 1/case when (
  select bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class
  where relname in ('input_items','input_lots','input_applications')
    and relnamespace = 'public'::regnamespace
) then 1 else 0 end as s15_rls_enabled_and_forced;

select 1/case when (
  select bool_and(p.proconfig @> array['search_path=pg_catalog, public'])
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('create_input_item','create_input_lot','record_input_application')
) then 1 else 0 end as s15_commands_have_pinned_search_path;

select 1/case when (
  select bool_and(p.prosecdef)
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('create_input_item','create_input_lot','record_input_application')
) then 1 else 0 end as s15_commands_are_security_definer;

select 1/case when (
  select bool_and(
    exists (
      select 1 from unnest(coalesce(c.reloptions, '{}')) as o(opt)
      where opt in ('security_invoker=on','security_invoker=true')
    )
  )
  from pg_class c
  where c.relname in ('input_items_read','input_lots_read','input_applications_read')
    and c.relnamespace = 'public'::regnamespace
) then 1 else 0 end as s15_read_views_are_security_invoker;

select 1/case when (
  select count(*) from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name in ('input_items','input_lots','input_applications')
    and grantee in ('authenticated','anon','PUBLIC')
    and privilege_type in ('INSERT','UPDATE','DELETE')
) = 0 then 1 else 0 end as s15_no_direct_dml_grants;

-- ---------------------------------------------------------------------------
-- Natural-key collisions are reported as domain errors, not as raw
-- constraint-name leaks. A distinct idempotency key with a colliding
-- item name (or lot reference) must fail with an explainable message.
-- ---------------------------------------------------------------------------
select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_item('10000000-0000-4000-8000-000000000001',%L,'FERTILIZER','  يوريا 46%%  ','OTHER-REF','كجم',null,null,'s15-item-fert-dup')$$
  , :'s15_ag_project')) = 'input item already exists for this project and category'
then 1 else 0 end as s15_duplicate_item_name_is_domain_error;

select 1/case when s15_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_input_lot('10000000-0000-4000-8000-000000000001',%L,'LOT-U-2027-01',null,null,null,null,'s15-lot-fert-dup')$$
  , :'s15_item_fert')) = 'input lot reference already exists for this input item'
then 1 else 0 end as s15_duplicate_lot_reference_is_domain_error;

-- The rejected duplicates must not have created rows.
select 1/case when (
  select count(*) from public.input_items
  where project_id = :'s15_ag_project'::uuid and category = 'FERTILIZER'
    and lower(trim(name)) = 'يوريا 46%'
) = 1 then 1 else 0 end as s15_duplicate_item_not_inserted;

select 1/case when (
  select count(*) from public.input_lots
  where input_item_id = :'s15_item_fert'::uuid and lot_reference = 'LOT-U-2027-01'
) = 1 then 1 else 0 end as s15_duplicate_lot_not_inserted;

reset role;
select 'S15 Field Input Application foundation PASS' as result;
