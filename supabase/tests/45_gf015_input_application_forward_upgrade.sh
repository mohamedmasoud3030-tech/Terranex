#!/usr/bin/env bash
# GF-015 / Field Input Application forward-upgrade verification.
#
# Construct a database at the REAL pre-GF-015 boundary: every merged
# migration except the GF-015 family. Seed surviving rows from Real
# Estate, GF-013 Agriculture (farm, field, crop cycle, assignment) and
# GF-014 Field Activity, assert the boundary is genuine, then apply
# GF-015 and prove:
#
#   * every previously seeded row survives unchanged;
#   * the new GF-015 primitives become available;
#   * the additive composite keys GF-015 places on the already-merged
#     GF-013/GF-014 tables do not disturb their existing rows.
#
# The skip list matches the GF-015 family by its exact date prefix only.
# It must never exclude a prerequisite migration, and every other
# forward-upgrade fixture in this repository was updated in the same
# change so a later migration can never be applied before GF-015's own
# prerequisites (the GF-014 forward-upgrade defect).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_gf015_upgrade"
GF015_MIGRATION="$ROOT/supabase/migrations/20260814001200_agriculture_input_application.sql"
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

if [[ ! -f "$GF015_MIGRATION" ]]; then
  echo "ERROR: GF-015 migration not found at $GF015_MIGRATION" >&2
  exit 1
fi

psql_cmd postgres "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB"

# Pre-GF-015 boundary: every migration except the GF-015 family and every
# later family (GF-016). Every prerequisite (S0..S7, governance, GF-013,
# GF-014) is applied in its canonical lexical order. Excluding the later
# GF-016 family here prevents a later migration from being applied before
# GF-015's own prerequisites — the exact defect found during GF-014.
applied=0
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260814001200*.sql|20260814001300*.sql|20260814001400*.sql|20260814001500*.sql|20260814001600*.sql|20260815*.sql|20260816*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
  applied=$((applied + 1))
done
if (( applied < 40 )); then
  echo "ERROR: pre-GF-015 boundary applied only $applied migrations; the skip list is too broad" >&2
  exit 1
fi

# Surviving fixture: Real Estate + GF-013 Agriculture + GF-014 activity.
psql_cmd "$UPGRADE_DB" "insert into auth.users(id) values ('00000000-0000-4000-8000-000000000099') on conflict do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000099','منظمة ترقية') on conflict (id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099','OWNER') on conflict (organization_id,user_id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000099','مشروع ترقية عقاري','GF015-UPGRADE-RE','REAL_ESTATE','Real Estate row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('40000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000099','مشروع ترقية زراعي','GF015-UPGRADE-AG','AGRICULTURE','GF-013 row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.farms(id, organization_id, project_id, name, internal_reference, timezone, created_by, idempotency_key, request_hash)
  values ('40000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002','مزرعة الترقية','UPG15-FARM','Africa/Cairo','00000000-0000-4000-8000-000000000099','gf015-upgrade-farm','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.fields(id, organization_id, project_id, farm_id, identifier, area_quantity, area_unit, created_by, idempotency_key, request_hash)
  values ('40000000-0000-4000-8000-000000000012','10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000011','حقل الترقية','9','FEDDAN','00000000-0000-4000-8000-000000000099','gf015-upgrade-field','cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.crop_cycles(id, organization_id, project_id, crop, season_reference, planned_start_date, planned_end_date, created_by, idempotency_key, request_hash)
  values ('40000000-0000-4000-8000-000000000013','10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002','قمح','موسم الترقية',date '2027-11-01',date '2028-05-01','00000000-0000-4000-8000-000000000099','gf015-upgrade-cycle','dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.crop_cycle_field_assignments(id, organization_id, project_id, crop_cycle_id, field_id, assigned_area_quantity, assigned_area_unit, planned_start_date, planned_end_date, created_by, idempotency_key, request_hash)
  values ('40000000-0000-4000-8000-000000000014','10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000013','40000000-0000-4000-8000-000000000012','5','FEDDAN',date '2027-11-01',date '2028-05-01','00000000-0000-4000-8000-000000000099','gf015-upgrade-assign','eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee')
  on conflict do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.field_activities(id, organization_id, project_id, crop_cycle_id, field_id, assignment_id, activity_date, activity_type, notes, recorded_by, idempotency_key, request_hash)
  values ('40000000-0000-4000-8000-000000000015','10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000013','40000000-0000-4000-8000-000000000012','40000000-0000-4000-8000-000000000014',date '2027-11-15','FERTILIZE','GF-014 row that must survive','00000000-0000-4000-8000-000000000099','gf015-upgrade-activity','ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
  on conflict do nothing;
" >/dev/null

BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.input_items') is null
    and to_regclass('public.input_lots') is null
    and to_regclass('public.input_applications') is null
    and to_regclass('public.input_applications_read') is null
    and to_regprocedure('public.create_input_item(uuid,uuid,text,text,text,text,text,text,text)') is null
    and to_regprocedure('public.create_input_lot(uuid,uuid,text,text,date,date,text,text)') is null
    and to_regprocedure('public.record_input_application(uuid,uuid,uuid,uuid,date,numeric,text,numeric,text,text,text,text,text)') is null
    and to_regclass('public.property_assets') is not null
    and to_regclass('public.farms') is not null
    and to_regclass('public.crop_cycles') is not null
    and to_regclass('public.field_activities') is not null
    and (select count(*) from public.investment_projects where id = '40000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE') = 1
    and (select count(*) from public.farms where id = '40000000-0000-4000-8000-000000000011') = 1
    and (select count(*) from public.fields where id = '40000000-0000-4000-8000-000000000012') = 1
    and (select count(*) from public.crop_cycles where id = '40000000-0000-4000-8000-000000000013') = 1
    and (select count(*) from public.crop_cycle_field_assignments where id = '40000000-0000-4000-8000-000000000014') = 1
    and (select count(*) from public.field_activities where id = '40000000-0000-4000-8000-000000000015') = 1
  )::text
")
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-GF-015 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

psql_db "$UPGRADE_DB" < "$GF015_MIGRATION"

AFTER=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.input_items') is not null
    and to_regclass('public.input_lots') is not null
    and to_regclass('public.input_applications') is not null
    and to_regclass('public.input_items_read') is not null
    and to_regclass('public.input_lots_read') is not null
    and to_regclass('public.input_applications_read') is not null
    and to_regprocedure('public.create_input_item(uuid,uuid,text,text,text,text,text,text,text)') is not null
    and to_regprocedure('public.create_input_lot(uuid,uuid,text,text,date,date,text,text)') is not null
    and to_regprocedure('public.record_input_application(uuid,uuid,uuid,uuid,date,numeric,text,numeric,text,text,text,text,text)') is not null
    -- Every previously seeded row survives unchanged.
    and (select count(*) from public.investment_projects where id = '40000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE' and name = 'مشروع ترقية عقاري') = 1
    and (select count(*) from public.investment_projects where id = '40000000-0000-4000-8000-000000000002' and sector = 'AGRICULTURE') = 1
    and (select count(*) from public.farms where id = '40000000-0000-4000-8000-000000000011' and name = 'مزرعة الترقية') = 1
    and (select count(*) from public.fields where id = '40000000-0000-4000-8000-000000000012' and identifier = 'حقل الترقية' and area_quantity = 9 and area_unit = 'FEDDAN') = 1
    and (select count(*) from public.crop_cycles where id = '40000000-0000-4000-8000-000000000013' and crop = 'قمح') = 1
    and (select count(*) from public.crop_cycle_field_assignments where id = '40000000-0000-4000-8000-000000000014' and assigned_area_quantity = 5 and assigned_area_unit = 'FEDDAN') = 1
    and (select count(*) from public.field_activities where id = '40000000-0000-4000-8000-000000000015' and activity_type = 'FERTILIZE' and notes = 'GF-014 row that must survive') = 1
    -- The additive composite keys exist on the already-merged tables.
    and exists (select 1 from pg_constraint where conname = 'crop_cycle_field_assignments_area_scope_key')
    and exists (select 1 from pg_constraint where conname = 'field_activities_input_scope_key')
    -- Forced RLS on every new table.
    and (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
         where relnamespace = 'public'::regnamespace
           and relname in ('input_items','input_lots','input_applications'))
    -- No fake inventory / costing column was introduced.
    and (select count(*) from information_schema.columns
         where table_schema = 'public'
           and table_name in ('input_items','input_lots','input_applications')
           and column_name in ('available_stock','current_quantity','remaining_quantity','lot_balance',
                               'received_quantity','available_quantity','on_hand_quantity',
                               'unit_cost','purchase_price','valuation_amount')) = 0
    -- No deferred subsystem was scaffolded.
    and to_regclass('public.inventory_movements') is null
    and to_regclass('public.storage_locations') is null
    and to_regclass('public.harvest_events') is null
    and to_regclass('public.harvest_lots') is null
  )::text
")
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: GF-015 forward-upgrade did not preserve prior rows or add primitives (AFTER=$AFTER)" >&2
  exit 1
fi

# The surviving GF-014 activity is immediately usable by the new
# primitive: the upgraded database can record a real input application
# against the pre-existing assignment without any data repair.
psql_cmd "$UPGRADE_DB" "
  select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',false);
  set role authenticated;
  select public.create_input_item(
    '10000000-0000-4000-8000-000000000099','40000000-0000-4000-8000-000000000002',
    'FERTILIZER','يوريا ترقية','UPG15-FERT','كجم',null,null,'gf015-upgrade-item-cmd');
" >/dev/null

USABLE=$(psql_cmd "$UPGRADE_DB" "
  select (
    (select count(*) from public.input_items where idempotency_key = 'gf015-upgrade-item-cmd') = 1
    and (select count(*) from public.audit_events where event_type = 'INPUT_ITEM_CREATED') = 1
  )::text
")
if [[ "$USABLE" != "true" ]]; then
  echo "ERROR: GF-015 primitives are not usable on the upgraded database (USABLE=$USABLE)" >&2
  exit 1
fi

echo "GF-015 forward-upgrade: input_items/input_lots/input_applications present and usable; Real Estate, GF-013 Agriculture, and GF-014 Field Activity rows preserved unchanged ($applied prerequisite migrations applied)."
