#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf020_upgrade"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}" PGUSER
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

if [[ -n "$CONTAINER" ]]; then
  psql_postgres() { docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d postgres "$@"; }
  psql_db() { local db="$1"; shift; docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$db" "$@"; }
else
  psql_postgres() { psql -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
  psql_db() { local db="$1"; shift; psql -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
fi

psql_postgres -c "drop database if exists \"$UPGRADE_DB\";" >/dev/null
psql_postgres -c "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB" >/dev/null

# Complete merged boundary through GF-019; exclude the GF-020 family and every
# later Livestock slice that builds on it, so the fixture stays genuinely
# pre-GF-020 as new Livestock stages are added.
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ ! "$base" < 20260814001700_ ]] && continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == 00_* ]] && continue
  [[ "$base" =~ ^([0-9]+) ]] && (( 10#${BASH_REMATCH[1]} < 58 )) || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_cohorts') is null")" == t ]] || {
  echo 'ERROR: fixture is not genuinely pre-GF-020' >&2
  exit 1
}

fingerprint_sql="select md5(jsonb_build_object(
  'projects',(select jsonb_agg(to_jsonb(x) order by id) from investment_projects x),
  'property',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from property_assets x),
  'land',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agricultural_land_assets x),
  'farms',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from farms x),
  'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from crop_cycles x),
  'harvest',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from harvest_lots x),
  'sales',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agriculture_sales x),
  'results',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from crop_cycle_closeouts x),
  'journals',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_batches x),
  'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from project_payments x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001700_livestock_foundation.sql" >/dev/null
psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001710_livestock_placement_lifecycle_hardening.sql" >/dev/null
AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || {
  echo 'ERROR: GF-020 changed prior-sector or Finance rows' >&2
  exit 1
}

ORG='10000000-0000-4000-8000-000000000001'
OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select create_investment_project('$ORG','ترقية ثروة حيوانية','GF020-UP',null,'LIVESTOCK');" | tail -1)"
SITE="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select create_livestock_site('$ORG','$PROJECT','مزرعة التسمين','UP-S','FARM',null,null,'gf20-up-site');" | tail -1)"
HERD="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select create_livestock_herd('$ORG','$PROJECT','قطيع أبقار التسمين','UP-H','CATTLE','MEAT',null,'gf20-up-herd');" | tail -1)"
COHORT="$(psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة أغسطس 2026','PURCHASED','2026-08-01',60,'MALE',null,null,null,null,null,null,'gf20-up-cohort');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "set request.jwt.claim.sub='$OWNER'; set role authenticated; select transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','بدء التشغيل',null,'gf20-up-active');" >/dev/null
CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select lifecycle_state='ACTIVE' and opening_headcount=60 and species='CATTLE'
     and initial_site_id='$SITE' from livestock_cohorts_read where id='$COHORT')
  and (select count(*)=1 from livestock_cohort_initial_placements where cohort_id='$COHORT')
  and not exists (select 1 from information_schema.columns where table_schema='public'
    and table_name='livestock_herds' and column_name='site_id')
)::text")"
[[ "$CHECK" == true ]] || {
  echo "ERROR: GF-020 post-upgrade workflow failed ($CHECK)" >&2
  exit 1
}
echo 'GF-020 forward-upgrade PASS: complete GF-019 boundary preserved; corrected Livestock workflow exercised.'
