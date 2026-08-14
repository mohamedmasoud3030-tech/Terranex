#!/usr/bin/env bash
# GF-016 / Harvest & Inventory forward-upgrade verification.
#
# Construct a database at the REAL pre-GF-016 boundary: every merged
# migration except the GF-016 family. Seed surviving rows from Real
# Estate, GF-013 Agriculture (farm, field, crop cycle, assignment),
# GF-014 Field Activity, and GF-015 Input Item/Lot/Application, assert
# the boundary is genuine, then apply GF-016 and prove:
#
#   * every previously seeded row survives unchanged;
#   * the new GF-016 primitives become available;
#   * the additive composite key GF-016 places on the already-merged
#     GF-013 assignment table does not disturb its existing rows;
#   * the new Harvest/Inventory workflow works immediately after upgrade.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_gf016_upgrade"
GF016_MIGRATION="$ROOT/supabase/migrations/20260814001300_agriculture_harvest_inventory.sql"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

psql_db() {
  local db="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$db"
  else
    psql -v ON_ERROR_STOP=1 -q -d "$db"
  fi
}
psql_cmd() {
  local db="$1" sql="$2"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$db" -c "$sql"
  else
    psql -v ON_ERROR_STOP=1 -Atq -d "$db" -c "$sql"
  fi
}
cleanup() {
  psql_cmd postgres "select pg_terminate_backend(pid) from pg_stat_activity where datname='$UPGRADE_DB' and pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  psql_cmd postgres "drop database if exists \"$UPGRADE_DB\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

if [[ ! -f "$GF016_MIGRATION" ]]; then
  echo "ERROR: GF-016 migration not found at $GF016_MIGRATION" >&2
  exit 1
fi

psql_cmd postgres "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB"

# Pre-GF-016 boundary: every migration except the GF-016 family. Every
# prerequisite (S0..S7, governance, GF-013, GF-014, GF-015) is applied in
# its canonical lexical order. The skip list is the exact GF-016 date
# prefix only — never a broad wildcard that could exclude a prerequisite.
applied=0
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260814001300*.sql|20260814001400*.sql|20260814001500*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
  applied=$((applied + 1))
done
if (( applied < 42 )); then
  echo "ERROR: pre-GF-016 boundary applied only $applied migrations; the skip list is too broad" >&2
  exit 1
fi

# Surviving fixture: Real Estate + GF-013 Agriculture + GF-014 activity +
# GF-015 input item/lot/application.
psql_cmd "$UPGRADE_DB" "insert into auth.users(id) values ('00000000-0000-4000-8000-000000000099') on conflict do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000099','منظمة ترقية') on conflict (id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099','OWNER') on conflict (organization_id,user_id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000099','مشروع ترقية عقاري','GF016-UPGRADE-RE','REAL_ESTATE','Real Estate row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('50000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000099','مشروع ترقية زراعي','GF016-UPGRADE-AG','AGRICULTURE','GF-013 row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.farms(id, organization_id, project_id, name, internal_reference, timezone, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','مزرعة الترقية','UPG16-FARM','Africa/Cairo','00000000-0000-4000-8000-000000000099','gf016-upgrade-farm','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.fields(id, organization_id, project_id, farm_id, identifier, area_quantity, area_unit, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000012','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000011','حقل الترقية','9','FEDDAN','00000000-0000-4000-8000-000000000099','gf016-upgrade-field','cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.crop_cycles(id, organization_id, project_id, crop, season_reference, planned_start_date, planned_end_date, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000013','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','قمح','موسم الترقية',date '2027-11-01',date '2028-05-01','00000000-0000-4000-8000-000000000099','gf016-upgrade-cycle','dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.crop_cycle_field_assignments(id, organization_id, project_id, crop_cycle_id, field_id, assigned_area_quantity, assigned_area_unit, planned_start_date, planned_end_date, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000014','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000013','50000000-0000-4000-8000-000000000012','5','FEDDAN',date '2027-11-01',date '2028-05-01','00000000-0000-4000-8000-000000000099','gf016-upgrade-assign','eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.field_activities(id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_date, activity_type, notes, recorded_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000015','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000013','50000000-0000-4000-8000-000000000012','50000000-0000-4000-8000-000000000014',date '2027-11-15','FERTILIZE','GF-014 row that must survive','00000000-0000-4000-8000-000000000099','gf016-upgrade-activity','ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.input_items(id, organization_id, project_id, category, name, application_unit, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000016','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','FERTILIZER','يوريا ترقية','كجم','00000000-0000-4000-8000-000000000099','gf016-upgrade-item','1111111111111111111111111111111111111111111111111111111111111111')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.input_lots(id, organization_id, project_id, input_item_id, lot_reference, unit, created_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000017','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000016','LOT-UPG-16','كجم','00000000-0000-4000-8000-000000000099','gf016-upgrade-lot','2222222222222222222222222222222222222222222222222222222222222222')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.input_applications(id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, field_activity_id, input_item_id, input_lot_id, input_category, activity_type, application_date, quantity, unit, applied_area_quantity, applied_area_unit, recorded_by, idempotency_key, request_hash)
  values ('50000000-0000-4000-8000-000000000018','10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000013','50000000-0000-4000-8000-000000000012','50000000-0000-4000-8000-000000000014','50000000-0000-4000-8000-000000000015','50000000-0000-4000-8000-000000000016','50000000-0000-4000-8000-000000000017','FERTILIZER','FERTILIZE',date '2027-11-15','10','كجم','1','FEDDAN','00000000-0000-4000-8000-000000000099','gf016-upgrade-application','3333333333333333333333333333333333333333333333333333333333333333')
  on conflict do nothing;
" >/dev/null

BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.storage_locations') is null
    and to_regclass('public.harvest_events') is null
    and to_regclass('public.harvest_lots') is null
    and to_regclass('public.harvest_inventory_movements') is null
    and to_regprocedure('public.create_storage_location(uuid,uuid,text,text,text,text)') is null
    and to_regprocedure('public.record_harvest_event(uuid,uuid,date,numeric,numeric,text,text,text,uuid,text,text,text)') is null
    and to_regclass('public.property_assets') is not null
    and to_regclass('public.farms') is not null
    and to_regclass('public.input_items') is not null
    and to_regclass('public.input_applications') is not null
    and (select count(*) from public.investment_projects where id = '50000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE') = 1
    and (select count(*) from public.farms where id = '50000000-0000-4000-8000-000000000011') = 1
    and (select count(*) from public.input_applications where id = '50000000-0000-4000-8000-000000000018') = 1
  )::text
")
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-GF-016 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

psql_db "$UPGRADE_DB" < "$GF016_MIGRATION"

AFTER=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.storage_locations') is not null
    and to_regclass('public.harvest_events') is not null
    and to_regclass('public.harvest_lots') is not null
    and to_regclass('public.harvest_inventory_movements') is not null
    and to_regclass('public.storage_locations_read') is not null
    and to_regclass('public.harvest_events_read') is not null
    and to_regclass('public.harvest_lots_read') is not null
    and to_regclass('public.harvest_inventory_by_location_read') is not null
    and to_regclass('public.harvest_inventory_movements_read') is not null
    and to_regprocedure('public.create_storage_location(uuid,uuid,text,text,text,text)') is not null
    and to_regprocedure('public.record_harvest_event(uuid,uuid,date,numeric,numeric,text,text,text,uuid,text,text,text)') is not null
    and to_regprocedure('public.transfer_harvest_inventory(uuid,uuid,uuid,uuid,numeric,date,text,text,text)') is not null
    and to_regprocedure('public.record_harvest_inventory_adjustment(uuid,uuid,uuid,text,numeric,date,text,text,text)') is not null
    -- Every previously seeded row survives unchanged.
    and (select count(*) from public.investment_projects where id = '50000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE' and name = 'مشروع ترقية عقاري') = 1
    and (select count(*) from public.investment_projects where id = '50000000-0000-4000-8000-000000000002' and sector = 'AGRICULTURE') = 1
    and (select count(*) from public.farms where id = '50000000-0000-4000-8000-000000000011' and name = 'مزرعة الترقية') = 1
    and (select count(*) from public.fields where id = '50000000-0000-4000-8000-000000000012' and area_quantity = 9 and area_unit = 'FEDDAN') = 1
    and (select count(*) from public.crop_cycles where id = '50000000-0000-4000-8000-000000000013' and crop = 'قمح') = 1
    and (select count(*) from public.crop_cycle_field_assignments where id = '50000000-0000-4000-8000-000000000014' and assigned_area_quantity = 5) = 1
    and (select count(*) from public.field_activities where id = '50000000-0000-4000-8000-000000000015' and activity_type = 'FERTILIZE') = 1
    and (select count(*) from public.input_items where id = '50000000-0000-4000-8000-000000000016' and category = 'FERTILIZER') = 1
    and (select count(*) from public.input_lots where id = '50000000-0000-4000-8000-000000000017' and lot_reference = 'LOT-UPG-16') = 1
    and (select count(*) from public.input_applications where id = '50000000-0000-4000-8000-000000000018' and input_category = 'FERTILIZER') = 1
    -- The additive composite key exists on the already-merged table.
    and exists (select 1 from pg_constraint where conname = 'crop_cycle_field_assignments_harvest_scope_key')
    -- Forced RLS on every new table.
    and (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
         where relnamespace = 'public'::regnamespace
           and relname in ('storage_locations','harvest_events','harvest_lots','harvest_inventory_movements'))
    -- No fake inventory / costing column was introduced on input tables.
    and (select count(*) from information_schema.columns
         where table_schema = 'public'
           and table_name in ('input_items','input_lots','input_applications')
           and column_name in ('available_stock','current_quantity','remaining_quantity','lot_balance',
                               'received_quantity','available_quantity','on_hand_quantity',
                               'unit_cost','purchase_price','valuation_amount','sale_price')) = 0
    -- No sale / procurement subsystem was scaffolded.
    and to_regclass('public.sale_orders') is null
    and to_regclass('public.purchase_orders') is null
    and to_regclass('public.buyers') is null
    and to_regclass('public.invoices') is null
  )::text
")
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: GF-016 forward-upgrade did not preserve prior rows or add primitives (AFTER=$AFTER)" >&2
  exit 1
fi

# The new Harvest/Inventory workflow is immediately usable on the upgraded
# database: create a fresh harvest-ready cycle, a storage location, and
# record a harvest without any data repair.
psql_cmd "$UPGRADE_DB" "
  select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',false);
  set role authenticated;
  select public.create_crop_cycle(
    '10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002',
    'ذرة','هجين','موسم ترقية حصاد',date '2028-11-01',date '2029-05-01',null,null,'gf016-upgrade-cycle-new');
" >/dev/null
NEW_CYCLE=$(psql_cmd "$UPGRADE_DB" "select id from public.crop_cycles where season_reference='موسم ترقية حصاد' limit 1")
psql_cmd "$UPGRADE_DB" "
  select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',false);
  set role authenticated;
  select public.transition_crop_cycle('10000000-0000-4000-8000-000000000099','$NEW_CYCLE','PLANNED','ESTABLISHED','تجهيز','ev1','gf016-upgrade-e1');
  select public.transition_crop_cycle('10000000-0000-4000-8000-000000000099','$NEW_CYCLE','ESTABLISHED','GROWING','نمو','ev2','gf016-upgrade-e2');
  select public.transition_crop_cycle('10000000-0000-4000-8000-000000000099','$NEW_CYCLE','GROWING','HARVESTING','حصاد','ev3','gf016-upgrade-e3');
  select public.assign_crop_cycle_to_field('10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','$NEW_CYCLE','50000000-0000-4000-8000-000000000012','4','FEDDAN',date '2028-11-01',date '2029-05-01','gf016-upgrade-assign-new');
  select public.create_storage_location('10000000-0000-4000-8000-000000000099','50000000-0000-4000-8000-000000000002','مخزن الترقية','UPG16-STORE',null,'gf016-upgrade-storage');
" >/dev/null
NEW_ASSIGN=$(psql_cmd "$UPGRADE_DB" "select id from public.crop_cycle_field_assignments where idempotency_key='gf016-upgrade-assign-new' limit 1")
NEW_STORAGE=$(psql_cmd "$UPGRADE_DB" "select id from public.storage_locations where idempotency_key='gf016-upgrade-storage' limit 1")
psql_cmd "$UPGRADE_DB" "
  select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',false);
  set role authenticated;
  select public.record_harvest_event('10000000-0000-4000-8000-000000000099','$NEW_ASSIGN',date '2029-04-01','80','78','كجم','درجة أولى','LOT-UPG-16-HV','$NEW_STORAGE',null,null,'gf016-upgrade-harvest');
" >/dev/null

USABLE=$(psql_cmd "$UPGRADE_DB" "
  select (
    (select count(*) from public.harvest_events where idempotency_key = 'gf016-upgrade-harvest') = 1
    and (select count(*) from public.harvest_lots where lot_reference = 'LOT-UPG-16-HV') = 1
    and (select count(*) from public.harvest_inventory_movements where harvest_lot_id = (select id from public.harvest_lots where lot_reference = 'LOT-UPG-16-HV') and movement_type = 'HARVEST_RECEIPT') = 1
    and (select public.harvest_lot_total_balance((select id from public.harvest_lots where lot_reference = 'LOT-UPG-16-HV'))) = 78
    and (select count(*) from public.audit_events where event_type = 'HARVEST_EVENT_RECORDED') = 1
  )::text
")
if [[ "$USABLE" != "true" ]]; then
  echo "ERROR: GF-016 primitives are not usable on the upgraded database (USABLE=$USABLE)" >&2
  exit 1
fi

echo "GF-016 forward-upgrade: harvest/storage/inventory present and usable; Real Estate, GF-013, GF-014 and GF-015 rows preserved unchanged ($applied prerequisite migrations applied)."
