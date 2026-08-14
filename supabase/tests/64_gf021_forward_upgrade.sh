#!/usr/bin/env bash
set -euo pipefail

# GF-021 forward upgrade.
#
# Proves that applying the GF-021 migration to a database already carrying the
# complete merged GF-020 boundary:
#   1. changes no prior-sector, Finance, or GF-020 Livestock row;
#   2. leaves the immutable GF-020 opening placement and opening headcount
#      exactly as they were;
#   3. enables the new movement / placement / quantity / weight workflow;
#   4. reports current quantity as the opening headcount, because GF-021
#      registers no quantity event class.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf021_upgrade"
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

# Complete merged boundary through GF-020; exclude the GF-021 family and every
# later Livestock slice that builds on it, so the fixture stays genuinely
# pre-GF-021 as new Livestock stages are added.
PREREQ=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ ! "$base" < 20260814001800_ ]] && continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
  PREREQ=$((PREREQ + 1))
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == 00_* ]] && continue
  [[ "$base" < 62_ ]] || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done

[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_cohort_movements') is null")" == t ]] || {
  echo 'ERROR: fixture is not genuinely pre-GF-021' >&2
  exit 1
}
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_cohorts') is not null")" == t ]] || {
  echo 'ERROR: fixture does not carry the GF-020 boundary' >&2
  exit 1
}

fingerprint_sql="select md5(jsonb_build_object(
  'projects',(select jsonb_agg(to_jsonb(x) order by id) from investment_projects x),
  'property',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from property_assets x),
  'land',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agricultural_land_assets x),
  'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from crop_cycles x),
  'sales',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agriculture_sales x),
  'journals',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_batches x),
  'lines',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_lines x),
  'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from project_payments x),
  'ls_sites',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_sites x),
  'ls_herds',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_herds x),
  'ls_cohorts',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohorts x),
  'ls_placements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_initial_placements x),
  'ls_history',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_state_history x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260814001800_livestock_movement_quantity_weight.sql" >/dev/null
AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || {
  echo 'ERROR: GF-021 changed prior-sector, Finance, or GF-020 Livestock rows' >&2
  exit 1
}

ORG='10000000-0000-4000-8000-000000000001'
OWNER='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$OWNER'; set role authenticated;"

PROJECT="$(psql_db "$UPGRADE_DB" -Atc "select id from investment_projects where internal_reference='GF020-LS-A' limit 1")"
HERD_A="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_herds where internal_reference='HERD-A' limit 1")"
SITE_A="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_sites where internal_reference='SITE-A' limit 1")"
if [[ -z "$PROJECT" || -z "$HERD_A" || -z "$SITE_A" ]]; then
  echo 'ERROR: the GF-020 fixture hierarchy is missing from the upgrade database.' >&2
  exit 1
fi

# A pre-existing GF-020 Cohort keeps its opening facts and now resolves a
# derived OPENING placement without any data backfill.
LEGACY="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_cohorts where cohort_reference='دفعة أغسطس 2026' limit 1")"
LEGACY_CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select placement_source='OPENING' and current_site_id='$SITE_A'
     from livestock_cohort_current_placement where cohort_id='$LEGACY')
  and (select opening_headcount=60 and current_quantity=60
     from livestock_cohort_quantity_rollforward where cohort_id='$LEGACY')
)::text")"
[[ "$LEGACY_CHECK" == true ]] || {
  echo "ERROR: a pre-existing GF-020 Cohort did not upgrade cleanly ($LEGACY_CHECK)" >&2
  exit 1
}

# The new workflow runs end to end on the upgraded database.
SITE_U="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_site('$ORG','$PROJECT','موقع ترقية','SITE-UP21','BARN',null,null,'gf21-up-site');" | tail -1)"
HERD_U="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_herd('$ORG','$PROJECT','قطيع ترقية','HERD-UP21','CATTLE','MIXED',null,'gf21-up-herd');" | tail -1)"
COHORT_U="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_cohort('$ORG','$PROJECT','$HERD_A','$SITE_A','دفعة ترقية 021','PURCHASED',date '2026-08-20',30,null,null,null,null,null,null,null,'gf21-up-cohort');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select transition_livestock_cohort('$ORG','$PROJECT','$COHORT_U','PLANNED','ACTIVE','تفعيل ترقية',null,'gf21-up-activate');" >/dev/null
psql_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_movement('$ORG','$PROJECT','$COHORT_U','$SITE_A','$HERD_A','$SITE_U','$HERD_U',now(),'نقل بعد الترقية',null,null,'gf21-up-move');" >/dev/null
psql_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_weight_event('$ORG','$PROJECT','$COHORT_U',now(),'SAMPLED_AVERAGE',215.500,'KG',null,6,'كشف عينة ترقية',null,'gf21-up-weight');" >/dev/null

CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select placement_source='MOVEMENT' and current_site_id='$SITE_U' and current_herd_id='$HERD_U'
     from livestock_cohort_current_placement where cohort_id='$COHORT_U')
  and (select site_id='$SITE_A' from livestock_cohort_initial_placements where cohort_id='$COHORT_U')
  and (select opening_headcount=30 and current_quantity=30
     from livestock_cohort_quantity_rollforward where cohort_id='$COHORT_U')
  and (select count(*)=1 from livestock_weight_events where cohort_id='$COHORT_U' and sample_size=6)
  and (select count(*)=0 from livestock_quantity_event_types)
  and (select count(*)=0 from livestock_quantity_events)
)::text")"
[[ "$CHECK" == true ]] || {
  echo "ERROR: GF-021 post-upgrade workflow failed ($CHECK)" >&2
  exit 1
}

echo "GF-021 forward-upgrade PASS: $PREREQ prerequisite migrations; exact GF-020 boundary preserved; movement, derived placement, quantity foundation and weight exercised."
