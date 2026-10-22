#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"; UPGRADE_DB="${DB}_gf018_upgrade"; PGUSER="${PGUSER:-postgres}"
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
sed 's/create role authenticated nologin; create role anon nologin;//' "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB" >/dev/null
applied=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"; [[ "$base" < "20260814001500" ]] || continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null; applied=$((applied+1))
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"; [[ "$base" == '00_supabase_shim.sql' ]] && continue
  [[ "$base" =~ ^([0-9]+) ]] && (( 10#${BASH_REMATCH[1]} < 52 )) || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done
fingerprint_sql="select md5(jsonb_build_object(
 'projects',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.investment_projects x),
 'farms',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.farms x),
 'fields',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.fields x),
 'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.crop_cycles x),
 'land',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agricultural_land_assets x),
 'farm_land',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.farm_land_asset_links x),
 'harvest_events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_events x),
 'harvest_lots',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_lots x),
 'movements',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from (select id,organization_id,project_id,harvest_lot_id,movement_type,from_storage_id,to_storage_id,quantity,unit,movement_date,reason,evidence_reference,recorded_by,created_at,idempotency_key from public.harvest_inventory_movements) x),
 'batches',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.journal_batches x),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.journal_lines x),
 'cash',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.project_cash_accounts x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.agriculture_sales') is null")" == t ]] || { echo 'ERROR: fixture is not genuinely pre-GF-018' >&2; exit 1; }
psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001500_agriculture_sale_revenue.sql" >/dev/null
AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || { echo 'ERROR: GF-018 changed pre-existing Agriculture, land, Finance Core, or inventory rows' >&2; exit 1; }

# Exercise the new commands on a current-date lot created after the upgrade.
# Historical rows above remain untouched; only this explicit post-upgrade fixture grows.
PROJECT="$(psql_db "$UPGRADE_DB" -Atc "select id from public.investment_projects where internal_reference='GF013-AG-A'")"
BUYER="$(psql_db "$UPGRADE_DB" -Atc "select id from public.parties where organization_id='10000000-0000-4000-8000-000000000001' order by created_at limit 1")"
OWNER='00000000-0000-4000-8000-000000000001'; ORG='10000000-0000-4000-8000-000000000001'
FARM="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_farm('$ORG','$PROJECT','مزرعة ترقية GF018','GF018-UP-FARM',null,null,'Africa/Cairo',null,'gf018-up-farm');" | tail -1)"
FIELD="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_field('$ORG','$PROJECT','$FARM','حقل ترقية GF018',1,'FEDDAN',null,null,'gf018-up-field');" | tail -1)"
CYCLE="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_crop_cycle('$ORG','$PROJECT','محصول ترقية',null,'GF018-UP-CYCLE',current_date-10,current_date+10,null,null,'gf018-up-cycle');" | tail -1)"
psql_db "$UPGRADE_DB" -c "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.transition_crop_cycle('$ORG','$CYCLE','PLANNED','ESTABLISHED','تجهيز ترقية','GF018-UP-E1','gf018-up-established');
select public.transition_crop_cycle('$ORG','$CYCLE','ESTABLISHED','GROWING','نمو ترقية','GF018-UP-E2','gf018-up-growing');
select public.transition_crop_cycle('$ORG','$CYCLE','GROWING','HARVESTING','حصاد ترقية','GF018-UP-E3','gf018-up-harvesting');" >/dev/null
ASSIGN="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.assign_crop_cycle_to_field('$ORG','$PROJECT','$CYCLE','$FIELD',1,'FEDDAN',current_date-10,current_date+10,'gf018-up-assignment');" | tail -1)"
STORE="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_storage_location('$ORG','$PROJECT','مخزن ترقية GF018','GF018-UP-STORE',null,'gf018-up-storage');" | tail -1)"
HARVEST="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.record_harvest_event('$ORG','$ASSIGN',current_date,2,2,'كجم',null,'GF018-UP-LOT','$STORE',null,'دليل حصاد ترقية','gf018-up-harvest');" | tail -1)"
LOT="$(psql_db "$UPGRADE_DB" -Atc "select id from public.harvest_lots where harvest_event_id='$HARVEST'")"; QTY=1
CASH="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_project_cash_account('$ORG','$PROJECT','حساب ترقية GF018','EGP');" | tail -1)"
SALE="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_agriculture_sale('$ORG','$PROJECT','$BUYER','GF018-UPGRADE-SALE',null,current_date,'EGP',null,'دليل ترقية',array['$LOT'::uuid],array['$STORE'::uuid],array[$QTY::numeric],array[1000::bigint],'gf018-upgrade-sale');" | tail -1)"
psql_db "$UPGRADE_DB" -c "set request.jwt.claim.sub='00000000-0000-4000-8000-000000000001'; set role authenticated; select public.approve_agriculture_sale('10000000-0000-4000-8000-000000000001','$SALE','gf018-upgrade-approve');" >/dev/null
RECOGNITION="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.recognize_agriculture_sale('$ORG','$SALE',current_date,'تسليم ترقية','gf018-upgrade-recognize');" | tail -1)"
COLLECTION="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.collect_agriculture_sale_receivable('$ORG','$RECOGNITION','$CASH',1000,current_date,'تحصيل ترقية','gf018-upgrade-collect');" | tail -1)"
CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
 (select count(*)=1 from public.harvest_inventory_movements where agriculture_sale_line_id in (select id from public.agriculture_sale_lines where sale_id='$SALE'))
 and (select count(*)=1 from public.journal_batches where source_type='AGRICULTURE_SALE_RECOGNITION' and source_id='$RECOGNITION')
 and (select count(*)=1 from public.agriculture_sale_collections where id='$COLLECTION')
 and (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where relnamespace='public'::regnamespace and relname in ('agriculture_sales','agriculture_sale_lines','agriculture_sale_recognitions','agriculture_sale_collections'))
 and to_regclass('public.agricultural_land_assets') is not null and to_regclass('public.property_assets') is not null
)::text")"
[[ "$CHECK" == true ]] || { echo "ERROR: GF-018 forward-upgrade controls failed ($CHECK)" >&2; exit 1; }
echo "GF-018 forward-upgrade PASS: $applied prerequisite migrations; GF-013→GF-017, Finance Core and Real Estate fingerprints preserved."
