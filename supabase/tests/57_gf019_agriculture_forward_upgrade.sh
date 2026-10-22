#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"; UPGRADE_DB="${DB}_gf019_upgrade"; PGUSER="${PGUSER:-postgres}"
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
  base="$(basename "$migration")"
  [[ "$base" < "20260814001600" ]] || continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null; applied=$((applied+1))
done
# True merged GF-018 boundary: load every cumulative SQL fixture through 52.
# Shell suites are not seed migrations; GF-019 is excluded by its exact family.
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"; [[ "$base" == '00_supabase_shim.sql' ]] && continue
  [[ "$base" =~ ^([0-9]+) ]] && (( 10#${BASH_REMATCH[1]} < 55 )) || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.crop_cycle_cost_attributions') is null")" == t ]] || { echo 'ERROR: fixture is not genuinely pre-GF-019' >&2; exit 1; }
fingerprint_sql="select md5(jsonb_build_object(
 'land',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agricultural_land_assets x),
 'farms',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.farms x),
 'fields',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.fields x),
 'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.crop_cycles x),
 'assignments',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.crop_cycle_field_assignments x),
 'activities',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.field_activities x),
 'applications',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.input_applications x),
 'harvest_events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_events x),
 'harvest_lots',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_lots x),
 'movements',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.harvest_inventory_movements x),
 'sales',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agriculture_sales x),
 'sale_lines',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agriculture_sale_lines x),
 'recognitions',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agriculture_sale_recognitions x),
 'collections',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.agriculture_sale_collections x),
 'batches',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.journal_batches x),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.journal_lines x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001600_agriculture_profitability_closeout.sql" >/dev/null
AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || { echo 'ERROR: GF-019 changed pre-existing GF-013→GF-018 or Finance rows' >&2; exit 1; }

ORG='10000000-0000-4000-8000-000000000001'; OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_db "$UPGRADE_DB" -Atc "select id from public.investment_projects where internal_reference='GF013-AG-A'")"
CYCLE="$(psql_db "$UPGRADE_DB" -Atc "select id from public.crop_cycles where season_reference='GF018-2026'")"
FIELD="$(psql_db "$UPGRADE_DB" -Atc "select id from public.fields where identifier='حقل مبيعات'")"
SUPPLIER="$(psql_db "$UPGRADE_DB" -Atc "select id from public.parties where organization_id='$ORG' order by created_at limit 1")"
OBLIGATION="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.create_cost_obligation('$ORG','$PROJECT','$SUPPLIER','تكلفة ترقية GF019',50000,'EGP',current_date,'EXPENSE','s19-up-cost');" | tail -1)"
BATCH="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.authorize_cost_obligation('$ORG','$OBLIGATION','s19-up-authorize');" | tail -1)"
LINE="$(psql_db "$UPGRADE_DB" -Atc "select jl.id from public.journal_lines jl join public.semantic_accounts sa on sa.id=jl.account_id where jl.batch_id='$BATCH' and sa.role='PROJECT_EXPENSE'")"
ATTRIBUTION="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.attribute_crop_cycle_cost('$ORG','$PROJECT','$CYCLE','$FIELD','$LINE',50000,'LABOR','سياسة ترقية GF019','دليل ترقية GF019','s19-up-attribute');" | tail -1)"
CLOSEOUT="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.close_crop_cycle('$ORG','$PROJECT','$CYCLE','اكتمال التشغيل بعد الترقية','دليل إغلاق ترقية GF019','s19-up-close');" | tail -1)"
CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
 (select attributed_operating_cost_minor_units='50000' from public.crop_cycle_results_read where crop_cycle_id='$CYCLE')
 and (select operational_state='CLOSED' and remaining_physical_inventory::numeric>0 from public.crop_cycle_results_read where crop_cycle_id='$CYCLE')
 and (select count(*)=1 from public.crop_cycle_cost_attributions where id='$ATTRIBUTION')
 and (select count(*)=1 from public.crop_cycle_closeouts where id='$CLOSEOUT')
 and (select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where relnamespace='public'::regnamespace and relname in ('crop_cycle_cost_attributions','crop_cycle_closeouts'))
)::text")"
[[ "$CHECK" == true ]] || { echo "ERROR: GF-019 post-upgrade flow failed ($CHECK)" >&2; exit 1; }
echo "GF-019 forward-upgrade PASS: $applied prerequisite migrations; exact GF-018 boundary preserved and new result/closeout exercised."
