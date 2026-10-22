#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf017_upgrade"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}" PGUSER
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

if [[ -n "$CONTAINER" ]]; then
  psql_postgres(){ docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d postgres "$@"; }
  psql_db(){ local db="$1"; shift; docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$db" "$@"; }
else
  psql_postgres(){ psql -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
  psql_db(){ local db="$1"; shift; psql -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
fi

psql_postgres -c "drop database if exists \"$UPGRADE_DB\";" >/dev/null
psql_postgres -c "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB" >/dev/null

applied=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ "$base" < "20260814001400" ]] || continue
  echo "==> GF-017 prerequisite migration: $base"
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
  applied=$((applied+1))
done

# Build a genuine pre-GF-017 database using every cumulative SQL regression
# fixture available at the GF-016 boundary. Exclude post-GF-016 test fixtures.
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == "00_supabase_shim.sql" ]] && continue
  # Only include test fixtures below the GF-017 boundary (prefix < 50)
  # and explicitly exclude any R4/procurement tests which reference
  # supplier_invoices that only exist after GF-017.
  [[ "$base" =~ ^([0-9]+) ]] && (( 10#${BASH_REMATCH[1]} < 50 )) || continue
  [[ "$base" == "83_"* ]] && continue  # Skip R4 procurement integration (83_r4_*.sql)
  [[ "$base" == "85_"* ]] && continue  # Skip R4 evidence tests (85_r4_*.sql)
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done

fingerprint_sql="select md5(jsonb_build_object(
  'property_assets',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.property_assets x),
  'farms',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.farms x),
  'fields',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.fields x),
  'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.crop_cycles x),
  'assignments',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.crop_cycle_field_assignments x),
  'activities',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.field_activities x),
  'input_items',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.input_items x),
  'input_lots',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.input_lots x),
  'input_applications',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.input_applications x),
  'harvest_events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_events x),
  'harvest_lots',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_lots x),
  'movements',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_inventory_movements x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"

if [[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.agricultural_land_assets') is null")" != "t" ]]; then
  echo "ERROR: forward fixture was not genuinely pre-GF-017" >&2
  exit 1
fi

psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001400_agricultural_land_asset.sql" >/dev/null
AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || { echo "ERROR: GF-017 changed pre-existing Agriculture/Real Estate rows" >&2; exit 1; }

USABLE="$(psql_db "$UPGRADE_DB" -Atc "
  select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
  set role authenticated;
  select public.create_agricultural_land_asset(
    '10000000-0000-4000-8000-000000000001',
    (select id from public.investment_projects where internal_reference='GF013-AG-A'),
    'أرض اختبار الترقية','GF017-UPGRADE-LAND',null,2,'FEDDAN',null,
    'LEASED',date '2026-08-14',date '2027-08-13',
    (select id from public.parties where organization_id='10000000-0000-4000-8000-000000000001' order by created_at limit 1),
    'عقد ترقية','دليل ترقية موثق',null,null,null,'gf017-upgrade-land');
" | tail -1)"
[[ -n "$USABLE" ]] || { echo "ERROR: GF-017 command unusable after forward upgrade" >&2; exit 1; }

CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select count(*) from public.agricultural_land_assets where internal_reference='GF017-UPGRADE-LAND')=1
  and (select count(*) from public.farm_land_asset_links)=0
  and (select count(*) from public.audit_events where event_type='AGRICULTURAL_LAND_ASSET_RECORDED' and entity_id='$USABLE')=1
  and (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
       where relnamespace='public'::regnamespace and relname in ('agricultural_land_assets','farm_land_asset_links'))
  and to_regclass('public.property_assets') is not null
)::text")"
[[ "$CHECK" == "true" ]] || { echo "ERROR: GF-017 forward-upgrade controls failed ($CHECK)" >&2; exit 1; }

echo "GF-017 forward-upgrade PASS: $applied prerequisite migrations; GF-013→GF-016 and Real Estate fingerprints preserved."
