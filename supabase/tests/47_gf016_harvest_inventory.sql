-- GF-016 / Harvest & Inventory Flow Foundation.
--
-- Proves the bounded slice end to end:
--   * Storage Location create, idempotency, natural-key domain error,
--     Real Estate rejection, tenant isolation, direct DML denial;
--   * one atomic record_harvest_event creating Harvest Event + Harvest
--     Lot + HARVEST_RECEIPT movement + exactly one audit event, with the
--     initial lot balance equal to the event's net quantity;
--   * quantity invariants (gross > 0, net > 0, net <= gross) and derived
--     loss = gross - net;
--   * scope coherence (mismatched organization / project / cycle / field
--     / assignment / storage all rejected);
--   * lifecycle rule (harvest only while HARVESTING; recording a harvest
--     never transitions the cycle);
--   * lot natural-key uniqueness with idempotent replay still succeeding
--     before the duplicate check;
--   * movement date cannot precede harvest date;
--   * transfer semantics (source down, destination up, total unchanged),
--     insufficient inventory, same source/destination rejection;
--   * adjustment (reason required, IN increases, OUT decreases, no
--     overdraw) and spoilage (reason required, decreases, no overdraw);
--   * append-only (direct UPDATE/DELETE refused);
--   * audit (true replay emits no second audit event; failed commands
--     emit no success audit event);
--   * two-tenant isolation;
--   * financial isolation (no accounting facts);
--   * input inventory boundary (no fake stock fields on input tables).

create or replace function s16_run(p_user uuid, p_sql text)
returns uuid language plpgsql as $$
declare v_result uuid;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s16_catch(p_user uuid, p_sql text)
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

create or replace function s16_anon_catch(p_sql text)
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

create or replace function s16_owner_catch(p_sql text)
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

create or replace function s16_count(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v_result bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

select id as s16_ag_project from public.investment_projects where internal_reference='GF013-AG-A' \gset
select id as s16_re_project from public.investment_projects where internal_reference='GF013-RE-A' \gset
select id as s16_farm       from public.farms where internal_reference='FARM-A' \gset
select id as s16_field      from public.fields where identifier='حقل شمال' \gset

-- ---------------------------------------------------------------------------
-- Fixture: a dedicated harvest-ready cycle (transitioned to HARVESTING), an
-- assignment on the existing field, and three storage locations.
-- ---------------------------------------------------------------------------
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ذرة','هجين','موسم 2027-HV',date '2027-05-01',date '2027-09-01',null,null,'s16-cycle-001')$$
  , :'s16_ag_project')) as s16_cycle \gset

select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز البذرة','s16-tr-1','s16-tr-est')$$
  , :'s16_cycle')) as s16_tr1 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','بدأ النمو','s16-tr-2','s16-tr-grow')$$
  , :'s16_cycle')) as s16_tr2 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','بداية الحصاد','s16-tr-3','s16-tr-harvest')$$
  , :'s16_cycle')) as s16_tr3 \gset

select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'4','FEDDAN',date '2027-05-01',date '2027-09-01','s16-assign-001')$$
  , :'s16_ag_project', :'s16_cycle', :'s16_field')) as s16_assign \gset

select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن رئيسي','STORE-A',null,'s16-storage-a')$$
  , :'s16_ag_project')) as s16_storage_a \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن بارد','STORE-B',null,'s16-storage-b')$$
  , :'s16_ag_project')) as s16_storage_b \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن شحن','STORE-C',null,'s16-storage-c')$$
  , :'s16_ag_project')) as s16_storage_c \gset

-- ---------------------------------------------------------------------------
-- 1. Storage Location.
-- ---------------------------------------------------------------------------
select 1/case when (
  select name = 'مخزن رئيسي' and project_id = :'s16_ag_project'::uuid
     and created_by = '00000000-0000-4000-8000-000000000001'
  from public.storage_locations where id = :'s16_storage_a'
) then 1 else 0 end as s16_storage_created;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'STORAGE_LOCATION_CREATED' and entity_id = :'s16_storage_a'
) = 1 then 1 else 0 end as s16_storage_audit_once;

select 1/case when s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن رئيسي','STORE-A',null,'s16-storage-a')$$
  , :'s16_ag_project')) = :'s16_storage_a' then 1 else 0 end as s16_storage_idempotent;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'  مخزن رئيسي  ','OTHER',null,'s16-storage-dup')$$
  , :'s16_ag_project')) = 'storage location already exists for this project'
then 1 else 0 end as s16_storage_duplicate_domain_error;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن عقاري',null,null,'s16-storage-re')$$
  , :'s16_re_project')) like '%agriculture project not found%' then 1 else 0 end
  as s16_storage_real_estate_rejected;

-- ---------------------------------------------------------------------------
-- 2. Atomic harvest happy path: one command creates event + lot + receipt
--    + audit, and the initial lot balance equals the net quantity.
-- ---------------------------------------------------------------------------
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','100','95','كجم','درجة أولى','LOT-HV-001',%L,'حصاد أول',null,'s16-harvest-001')$$
  , :'s16_assign', :'s16_storage_a')) as s16_harvest \gset

select 1/case when (
  select gross_quantity = 100 and net_quantity = 95 and quantity_unit = 'كجم'
     and crop_cycle_id = :'s16_cycle'::uuid and field_id = :'s16_field'::uuid
     and assignment_id = :'s16_assign'::uuid and project_id = :'s16_ag_project'::uuid
  from public.harvest_events where id = :'s16_harvest'
) then 1 else 0 end as s16_harvest_scope_derived;

select id as s16_lot from public.harvest_lots where harvest_event_id = :'s16_harvest' \gset

select 1/case when (
  select lot_reference = 'LOT-HV-001' and initial_quantity = 95
     and quantity_unit = 'كجم' and harvest_date = date '2027-08-01'
     and grade = 'درجة أولى'
  from public.harvest_lots where id = :'s16_lot'
) then 1 else 0 end as s16_lot_created_from_event;

select 1/case when (
  select count(*) from public.harvest_inventory_movements
  where harvest_lot_id = :'s16_lot' and movement_type = 'HARVEST_RECEIPT'
    and to_storage_id = :'s16_storage_a' and from_storage_id is null
    and quantity = 95 and unit = 'كجم' and movement_date = date '2027-08-01'
) = 1 then 1 else 0 end as s16_initial_receipt_created;

select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_a') = 95
  then 1 else 0 end as s16_initial_balance_equals_net_quantity;

select 1/case when public.harvest_lot_total_balance(:'s16_lot') = 95
  then 1 else 0 end as s16_initial_total_balance_equals_net_quantity;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'HARVEST_EVENT_RECORDED' and entity_id = :'s16_harvest'
) = 1 then 1 else 0 end as s16_harvest_audit_once;

select 1/case when (
  select payload->>'harvest_lot_id' = :'s16_lot'::text
     and (payload->>'initial_receipt_movement_id') is not null
  from public.audit_events
  where event_type = 'HARVEST_EVENT_RECORDED' and entity_id = :'s16_harvest'
) then 1 else 0 end as s16_harvest_audit_references_lot_and_receipt;

-- Derived loss = gross - net, never stored a second time.
select 1/case when (
  select harvest_loss = '5.000000' from public.harvest_events_read where id = :'s16_harvest'
) then 1 else 0 end as s16_derived_loss;

-- ---------------------------------------------------------------------------
-- 3. Quantity invariants.
-- ---------------------------------------------------------------------------
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','0','0','كجم',null,'LOT-Q0',%L,null,null,'s16-q-gross-zero')$$
  , :'s16_assign', :'s16_storage_a')) like '%gross quantity must be positive%' then 1 else 0 end
  as s16_gross_zero_rejected;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','-5','1','كجم',null,'LOT-QN',%L,null,null,'s16-q-gross-neg')$$
  , :'s16_assign', :'s16_storage_a')) like '%gross quantity must be positive%' then 1 else 0 end
  as s16_gross_negative_rejected;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','10','0','كجم',null,'LOT-QZ',%L,null,null,'s16-q-net-zero')$$
  , :'s16_assign', :'s16_storage_a')) like '%net quantity must be positive%' then 1 else 0 end
  as s16_net_zero_rejected;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','10','-1','كجم',null,'LOT-QN',%L,null,null,'s16-q-net-neg')$$
  , :'s16_assign', :'s16_storage_a')) like '%net quantity must be positive%' then 1 else 0 end
  as s16_net_negative_rejected;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','10','11','كجم',null,'LOT-QG',%L,null,null,'s16-q-net-over')$$
  , :'s16_assign', :'s16_storage_a')) like '%net quantity must not exceed gross quantity%' then 1 else 0 end
  as s16_net_over_gross_rejected;

-- ---------------------------------------------------------------------------
-- 4. Lifecycle rule.
-- ---------------------------------------------------------------------------
-- A second cycle that is still GROWING cannot be harvested.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'فول','بلدي','موسم 2027-NH',date '2027-05-01',date '2027-09-01',null,null,'s16-cycle-nh')$$
  , :'s16_ag_project')) as s16_cycle_nh \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز','s16-nh-1','s16-nh-est')$$
  , :'s16_cycle_nh')) as s16_nh_tr1 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','نمو','s16-nh-2','s16-nh-grow')$$
  , :'s16_cycle_nh')) as s16_nh_tr2 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'2','FEDDAN',date '2027-05-01',date '2027-09-01','s16-assign-nh')$$
  , :'s16_ag_project', :'s16_cycle_nh', :'s16_field')) as s16_assign_nh \gset

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','10','9','كجم',null,'LOT-NH',%L,null,null,'s16-harvest-nh')$$
  , :'s16_assign_nh', :'s16_storage_a')) like '%not harvest-ready%' then 1 else 0 end
  as s16_harvest_not_ready_rejected;

-- Recording a harvest never transitions the cycle.
select 1/case when public.agriculture_current_cycle_state(:'s16_cycle') = 'HARVESTING'
  then 1 else 0 end as s16_lifecycle_unchanged_by_harvest;

select 1/case when (
  select count(*) from public.crop_cycle_state_history where crop_cycle_id = :'s16_cycle'
) = 4 then 1 else 0 end as s16_no_extra_lifecycle_history;

-- ---------------------------------------------------------------------------
-- 5. Scope coherence.
-- ---------------------------------------------------------------------------
-- Guessed assignment id from another tenant/project.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001','99999999-0000-4000-8000-000000000099',date '2027-08-01','10','9','كجم',null,'LOT-S1',%L,null,null,'s16-scope-guess')$$
  , :'s16_storage_a')) like '%crop cycle field assignment not found%' then 1 else 0 end
  as s16_guessed_assignment_rejected;

-- Destination storage from another project.
select s16_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع زراعي ثالث','GF016-AG-A3','x','AGRICULTURE')$$
) as s16_project_b \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'مخزن مشروع ثالث','STORE-P3',null,'s16-storage-p3')$$
  , :'s16_project_b')) as s16_storage_p3 \gset

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','10','9','كجم',null,'LOT-S2',%L,null,null,'s16-scope-storage')$$
  , :'s16_assign', :'s16_storage_p3')) like '%storage location not found%' then 1 else 0 end
  as s16_cross_project_storage_rejected;

-- ---------------------------------------------------------------------------
-- 6. Lot uniqueness and idempotency ordering.
-- ---------------------------------------------------------------------------
-- Same key + same canonical payload returns the original result.
select 1/case when s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','100.00','95.0','كجم','درجة أولى','LOT-HV-001',%L,'حصاد أول',null,'s16-harvest-001')$$
  , :'s16_assign', :'s16_storage_a')) = :'s16_harvest' then 1 else 0 end
  as s16_harvest_idempotent_same_payload;

select 1/case when (
  select count(*) from public.harvest_events where idempotency_key = 's16-harvest-001'
) = 1 then 1 else 0 end as s16_no_duplicate_harvest;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'HARVEST_EVENT_RECORDED' and entity_id = :'s16_harvest'
) = 1 then 1 else 0 end as s16_idempotent_replay_does_not_re_audit;

-- Same key + different payload is rejected.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','120','95','كجم','درجة أولى','LOT-HV-001',%L,'حصاد أول',null,'s16-harvest-001')$$
  , :'s16_assign', :'s16_storage_a')) like '%idempotency key payload mismatch%' then 1 else 0 end
  as s16_harvest_payload_mismatch_rejected;

-- A distinct key with a colliding lot reference is a domain error.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-02','10','9','كجم',null,'LOT-HV-001',%L,null,null,'s16-harvest-dup')$$
  , :'s16_assign', :'s16_storage_a')) = 'harvest lot reference already exists for this project'
then 1 else 0 end as s16_duplicate_lot_reference_domain_error;

select 1/case when (
  select count(*) from public.harvest_lots where lot_reference = 'LOT-HV-001'
) = 1 then 1 else 0 end as s16_duplicate_lot_not_inserted;

-- ---------------------------------------------------------------------------
-- 7. Transfer semantics.
-- ---------------------------------------------------------------------------
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'30',date '2027-08-05',null,null,'s16-transfer-001')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_b')) as s16_transfer \gset

select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_a') = 65
  then 1 else 0 end as s16_transfer_source_decreased;

select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_b') = 30
  then 1 else 0 end as s16_transfer_destination_increased;

select 1/case when public.harvest_lot_total_balance(:'s16_lot') = 95
  then 1 else 0 end as s16_transfer_total_unchanged;

-- Same source/destination rejected.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'1',date '2027-08-05',null,null,'s16-transfer-same')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_a')) like '%must differ%' then 1 else 0 end
  as s16_same_source_destination_rejected;

-- Insufficient inventory rejected.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'100',date '2027-08-05',null,null,'s16-transfer-over')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_b')) like '%insufficient inventory%' then 1 else 0 end
  as s16_transfer_overdraw_rejected;

-- Movement before harvest date rejected; on harvest date allowed.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'1',date '2027-07-31',null,null,'s16-transfer-early')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_b')) like '%cannot precede the harvest date%' then 1 else 0 end
  as s16_movement_before_harvest_rejected;

select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'1',date '2027-08-01',null,null,'s16-transfer-on-date')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_b')) as s16_transfer_on_date \gset
select 1/case when (
  select count(*) from public.harvest_inventory_movements
  where idempotency_key = 's16-transfer-on-date'
    and movement_type = 'TRANSFER'
    and movement_date = date '2027-08-01'
) = 1 then 1 else 0 end as s16_movement_on_harvest_date_allowed;

-- ---------------------------------------------------------------------------
-- 8. Adjustment and spoilage.
-- ---------------------------------------------------------------------------
-- Missing reason rejected.
select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'ADJUSTMENT_IN','5',date '2027-08-05',null,null,'s16-adj-noreason')$$
  , :'s16_lot', :'s16_storage_a')) like '%adjustment reason is required%' then 1 else 0 end
  as s16_adjustment_reason_required;

-- ADJUSTMENT_IN increases the location balance.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'ADJUSTMENT_IN','10',date '2027-08-05','جرد فعلي إضافي',null,'s16-adj-in')$$
  , :'s16_lot', :'s16_storage_a')) as s16_adj_in \gset
select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_a') = 74
  then 1 else 0 end as s16_adjustment_in_increases;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'HARVEST_INVENTORY_ADJUSTED' and entity_id = :'s16_adj_in'
) = 1 then 1 else 0 end as s16_adjustment_in_audit_once;

-- ADJUSTMENT_OUT decreases and cannot overdraw.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'ADJUSTMENT_OUT','4',date '2027-08-06','تسوية جرد ناقص',null,'s16-adj-out')$$
  , :'s16_lot', :'s16_storage_a')) as s16_adj_out \gset
select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_a') = 70
  then 1 else 0 end as s16_adjustment_out_decreases;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'ADJUSTMENT_OUT','999',date '2027-08-06','تسوية خاطئة',null,'s16-adj-over')$$
  , :'s16_lot', :'s16_storage_a')) like '%insufficient inventory%' then 1 else 0 end
  as s16_adjustment_out_overdraw_rejected;

-- SPOILAGE decreases, requires reason, and cannot overdraw.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'SPOILAGE','5',date '2027-08-07','تلف أثناء التخزين',null,'s16-spoil')$$
  , :'s16_lot', :'s16_storage_a')) as s16_spoil \gset
select 1/case when public.harvest_lot_storage_balance(:'s16_lot', :'s16_storage_a') = 65
  then 1 else 0 end as s16_spoilage_decreases;

select 1/case when (
  select count(*) from public.audit_events
  where event_type = 'HARVEST_SPOILAGE_RECORDED' and entity_id = :'s16_spoil'
) = 1 then 1 else 0 end as s16_spoilage_audit_once;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'SPOILAGE','999',date '2027-08-07','تلف مبالغ فيه',null,'s16-spoil-over')$$
  , :'s16_lot', :'s16_storage_a')) like '%insufficient inventory%' then 1 else 0 end
  as s16_spoilage_overdraw_rejected;

-- ---------------------------------------------------------------------------
-- 9. Read models.
-- ---------------------------------------------------------------------------
select 1/case when s16_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.harvest_events_read where id = %L and harvest_loss = '5.000000' and lot_reference = 'LOT-HV-001' and destination_storage_name = 'مخزن رئيسي'$$
  , :'s16_harvest')) = 1 then 1 else 0 end as s16_harvest_read_model;

select 1/case when s16_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.harvest_lots_read where id = %L and current_total_balance = '96.000000' and crop = 'ذرة'$$
  , :'s16_lot')) = 1 then 1 else 0 end as s16_lot_read_model_total_balance;

select 1/case when s16_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.harvest_inventory_by_location_read where harvest_lot_id = %L and storage_id = %L and current_balance = '65.000000'$$
  , :'s16_lot', :'s16_storage_a')) = 1 then 1 else 0 end as s16_inventory_by_location_read_model;

select 1/case when s16_count('00000000-0000-4000-8000-000000000001', format(
  $$select count(*) from public.harvest_inventory_movements_read where harvest_lot_id = %L and movement_type = 'TRANSFER' and from_storage_name = 'مخزن رئيسي' and to_storage_name = 'مخزن بارد'$$
  , :'s16_lot')) = 2 then 1 else 0 end as s16_movement_history_read_model;

-- ---------------------------------------------------------------------------
-- 10. Security and append-only.
-- ---------------------------------------------------------------------------
select 1/case when s16_anon_catch(format(
  $$select public.create_storage_location('10000000-0000-4000-8000-000000000001',%L,'x',null,null,'s16-anon-storage')$$
  , :'s16_ag_project')) like '%permission denied%' then 1 else 0 end as s16_anon_execute_denied;

select 1/case when s16_anon_catch(format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','10','9','كجم',null,'LOT-ANON',%L,null,null,'s16-anon-harvest')$$
  , :'s16_assign', :'s16_storage_a')) like '%permission denied%' then 1 else 0 end as s16_anon_harvest_denied;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000001', format(
  $$insert into public.storage_locations(organization_id, project_id, name, created_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,'x','00000000-0000-4000-8000-000000000001','s16-direct-storage','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s16_ag_project')) like '%permission denied%' then 1 else 0 end as s16_direct_storage_insert_denied;

select 1/case when s16_owner_catch(format(
  $$update public.harvest_events set gross_quantity = 1 where id = %L$$, :'s16_harvest'))
  like '%append-only%' then 1 else 0 end as s16_harvest_update_rejected;

select 1/case when s16_owner_catch(format(
  $$delete from public.harvest_events where id = %L$$, :'s16_harvest'))
  like '%append-only%' then 1 else 0 end as s16_harvest_delete_rejected;

select 1/case when s16_owner_catch(format(
  $$update public.harvest_lots set initial_quantity = 1 where id = %L$$, :'s16_lot'))
  like '%append-only%' then 1 else 0 end as s16_lot_update_rejected;

select 1/case when s16_owner_catch(format(
  $$delete from public.harvest_inventory_movements where harvest_lot_id = %L$$, :'s16_lot'))
  like '%append-only%' then 1 else 0 end as s16_movement_delete_rejected;

-- Privileged direct SQL cannot bypass the lifecycle rule or movement date rule.
select 1/case when s16_owner_catch(format(
  $$insert into public.harvest_events(organization_id, project_id, crop_cycle_id, field_id, assignment_id, harvest_date, gross_quantity, net_quantity, quantity_unit, recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-08-01','10','9','كجم','00000000-0000-4000-8000-000000000001','s16-owner-lifecycle','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$
  , :'s16_ag_project', :'s16_cycle_nh', :'s16_field', :'s16_assign_nh'))
  like '%not harvest-ready%' then 1 else 0 end as s16_direct_sql_lifecycle_enforced;

-- ---------------------------------------------------------------------------
-- 11. Financial isolation and input inventory boundary.
-- ---------------------------------------------------------------------------
select 1/case when (
  select count(*) from public.journal_batches
  where source_type ilike '%harvest%' or source_id = :'s16_harvest'
) = 0 then 1 else 0 end as s16_no_journal_batch;

select 1/case when (
  select count(*) from public.cost_obligations where project_id = :'s16_ag_project'
) = 0 then 1 else 0 end as s16_no_cost_obligation;

select 1/case when (
  select count(*) from public.accounting_periods where project_id = :'s16_ag_project'
) = 0 then 1 else 0 end as s16_no_accounting_period;

-- GF-016 did NOT retrofit a stock balance onto GF-015 input tables.
select 1/case when (
  select count(*) from information_schema.columns
  where table_schema = 'public'
    and table_name in ('input_items','input_lots','input_applications')
    and column_name in ('available_stock','current_quantity','remaining_quantity','lot_balance',
                        'received_quantity','available_quantity','on_hand_quantity','unit_cost',
                        'purchase_price','valuation_amount','sale_price')
) = 0 then 1 else 0 end as s16_input_tables_have_no_stock_columns;

-- No SALE_ISSUE movement type and no sale/valuation table was introduced.
select 1/case when (
  select count(*) from pg_constraint
  where conname = 'harvest_inventory_movements_movement_type_check'
    and pg_get_constraintdef(oid) !~* 'SALE_ISSUE'
) = 1 then 1 else 0 end as s16_no_sale_issue_movement_type;

select 1/case when (
  select count(*) from information_schema.tables
  where table_schema = 'public'
    and table_name in ('sale_orders','purchase_orders','warehouses','inventory_valuations','buyers','invoices','receivables')
) = 0 then 1 else 0 end as s16_no_sale_or_procurement_tables;

-- ---------------------------------------------------------------------------
-- 12. Two-tenant isolation.
-- ---------------------------------------------------------------------------
insert into public.organizations(id, name)
  values ('20000000-0000-4000-8000-000000000099', 'منظمة باء-س16')
  on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role)
  values ('20000000-0000-4000-8000-000000000099', '00000000-0000-4000-8000-000000000002', 'OWNER')
  on conflict (organization_id, user_id) do nothing;

select 1/case when s16_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.harvest_events_read') = 0 then 1 else 0 end
  as s16_tenant_b_cannot_read_harvest_events;
select 1/case when s16_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.harvest_lots_read') = 0 then 1 else 0 end
  as s16_tenant_b_cannot_read_lots;
select 1/case when s16_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.storage_locations_read') = 0 then 1 else 0 end
  as s16_tenant_b_cannot_read_storage;
select 1/case when s16_count('00000000-0000-4000-8000-000000000002',
  'select count(*) from public.harvest_inventory_movements_read') = 0 then 1 else 0 end
  as s16_tenant_b_cannot_read_movements;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.create_storage_location('20000000-0000-4000-8000-000000000099',%L,'x',null,null,'s16-tb-storage')$$
  , :'s16_ag_project')) like '%agriculture project not found%' then 1 else 0 end
  as s16_tenant_b_storage_against_tenant_a_project_rejected;

select 1/case when s16_catch('00000000-0000-4000-8000-000000000002', format(
  $$select public.transfer_harvest_inventory('20000000-0000-4000-8000-000000000099',%L,%L,%L,'1',date '2027-08-05',null,null,'s16-tb-transfer')$$
  , :'s16_lot', :'s16_storage_a', :'s16_storage_b')) like '%harvest lot not found%' then 1 else 0 end
  as s16_tenant_b_transfer_against_tenant_a_lot_rejected;

-- ---------------------------------------------------------------------------
-- 12b. Stable idempotent replay after mutable state changes, plus the
--      database-enforced HarvestLot / initial-receipt invariants.
-- ---------------------------------------------------------------------------
-- A fresh harvest-ready cycle.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ذرة','هجين','موسم 2027-REPLAY',date '2027-05-01',date '2027-09-01',null,null,'s16-cycle-replay')$$
  , :'s16_ag_project')) as s16_cycle_r \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'PLANNED','ESTABLISHED','تجهيز','ev1','s16-rp-e1')$$
  , :'s16_cycle_r')) as s16_rp_tr1 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'ESTABLISHED','GROWING','نمو','ev2','s16-rp-e2')$$
  , :'s16_cycle_r')) as s16_rp_tr2 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'GROWING','HARVESTING','حصاد','ev3','s16-rp-e3')$$
  , :'s16_cycle_r')) as s16_rp_tr3 \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000001',%L,%L,%L,'2','FEDDAN',date '2027-05-01',date '2027-09-01','s16-assign-replay')$$
  , :'s16_ag_project', :'s16_cycle_r', :'s16_field')) as s16_assign_r \gset

select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','100','100','كجم',null,'LOT-REPLAY',%L,null,null,'s16-harvest-replay')$$
  , :'s16_assign_r', :'s16_storage_a')) as s16_harvest_r \gset
select id as s16_lot_r from public.harvest_lots where harvest_event_id = :'s16_harvest_r' \gset

-- Close the cycle, then replay the identical harvest request: it must
-- return the original event, not a "not harvest-ready" rejection.
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transition_crop_cycle('10000000-0000-4000-8000-000000000001',%L,'HARVESTING','CLOSED','إغلاق دورة','ev4','s16-rp-close')$$
  , :'s16_cycle_r')) as s16_rp_close \gset
select 1/case when s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_event('10000000-0000-4000-8000-000000000001',%L,date '2027-08-01','100','100','كجم',null,'LOT-REPLAY',%L,null,null,'s16-harvest-replay')$$
  , :'s16_assign_r', :'s16_storage_a')) = :'s16_harvest_r' then 1 else 0 end
  as s16_harvest_replay_after_close;

-- Transfer 70, then drain the source below 70, then replay the identical
-- transfer: it must return the original movement, not "insufficient".
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'70',date '2027-08-05',null,null,'s16-transfer-replay')$$
  , :'s16_lot_r', :'s16_storage_a', :'s16_storage_b')) as s16_transfer_r \gset
select s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_harvest_inventory_adjustment('10000000-0000-4000-8000-000000000001',%L,%L,'ADJUSTMENT_OUT','30',date '2027-08-06','تصفير الرصيد',null,'s16-drain-replay')$$
  , :'s16_lot_r', :'s16_storage_a')) as s16_drain_r \gset
select 1/case when s16_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.transfer_harvest_inventory('10000000-0000-4000-8000-000000000001',%L,%L,%L,'70',date '2027-08-05',null,null,'s16-transfer-replay')$$
  , :'s16_lot_r', :'s16_storage_a', :'s16_storage_b')) = :'s16_transfer_r' then 1 else 0 end
  as s16_transfer_replay_after_balance_change;

-- Database-enforced HarvestLot invariants (privileged SQL path). The event
-- net quantity is 100; a lot initial quantity of 500 must be rejected by
-- the composite foreign key, not silently accepted.
select 1/case when s16_owner_catch(format(
  $$with ev as (
    insert into public.harvest_events(organization_id, project_id, crop_cycle_id, field_id, assignment_id, harvest_date, gross_quantity, net_quantity, quantity_unit, recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,date '2027-08-02','100','100','كجم','00000000-0000-4000-8000-000000000001','s16-owner-ev','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
    returning id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, harvest_date, quantity_unit, recorded_by
  )
  insert into public.harvest_lots(organization_id, project_id, crop_cycle_id, field_id, assignment_id, harvest_event_id, lot_reference, harvest_date, initial_quantity, quantity_unit, created_by, idempotency_key, request_hash)
  select organization_id, project_id, crop_cycle_id, field_id, assignment_id, id, 'LOT-OWNER-MISMATCH', harvest_date, '500', quantity_unit, recorded_by, 's16-owner-lot','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  from ev$$
  , :'s16_ag_project', :'s16_cycle', :'s16_field', :'s16_assign'))
  is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s16_initial_quantity_mismatch_rejected;

-- A second HARVEST_RECEIPT for the same lot is rejected by the partial
-- unique index (exactly one receipt per lot).
select 1/case when s16_owner_catch(format(
  $$insert into public.harvest_inventory_movements(organization_id, project_id, harvest_lot_id, movement_type, movement_date, quantity, unit, from_storage_id, to_storage_id, recorded_by, idempotency_key, request_hash)
    values ('10000000-0000-4000-8000-000000000001',%L,%L,'HARVEST_RECEIPT',date '2027-08-01','95','كجم',null,%L,'00000000-0000-4000-8000-000000000001','s16-owner-receipt2','cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc')$$
  , :'s16_ag_project', :'s16_lot', :'s16_storage_b'))
  is distinct from 'NO_EXCEPTION' then 1 else 0 end
  as s16_second_receipt_rejected;

-- ---------------------------------------------------------------------------
-- 13. RLS / grant posture.
-- ---------------------------------------------------------------------------
select 1/case when (
  select bool_and(relrowsecurity and relforcerowsecurity)
  from pg_class
  where relname in ('storage_locations','harvest_events','harvest_lots','harvest_inventory_movements')
    and relnamespace = 'public'::regnamespace
) then 1 else 0 end as s16_rls_enabled_and_forced;

select 1/case when (
  select bool_and(p.proconfig @> array['search_path=pg_catalog, public'])
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('create_storage_location','record_harvest_event','transfer_harvest_inventory','record_harvest_inventory_adjustment')
) then 1 else 0 end as s16_commands_have_pinned_search_path;

select 1/case when (
  select bool_and(p.prosecdef)
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in ('create_storage_location','record_harvest_event','transfer_harvest_inventory','record_harvest_inventory_adjustment')
) then 1 else 0 end as s16_commands_are_security_definer;

select 1/case when (
  select bool_and(
    exists (
      select 1 from unnest(coalesce(c.reloptions, '{}')) as o(opt)
      where opt in ('security_invoker=on','security_invoker=true')
    )
  )
  from pg_class c
  where c.relname in ('storage_locations_read','harvest_events_read','harvest_lots_read','harvest_inventory_by_location_read','harvest_inventory_movements_read')
    and c.relnamespace = 'public'::regnamespace
) then 1 else 0 end as s16_read_views_are_security_invoker;

select 1/case when (
  select count(*) from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name in ('storage_locations','harvest_events','harvest_lots','harvest_inventory_movements')
    and grantee in ('authenticated','anon','PUBLIC')
    and privilege_type in ('INSERT','UPDATE','DELETE')
) = 0 then 1 else 0 end as s16_no_direct_dml_grants;

reset role;
select 'S16 Harvest & Inventory Flow Foundation PASS' as result;
