#!/usr/bin/env bash
set -euo pipefail

# Forward upgrade from the exact merged GF-022 boundary. Prior rows and the
# authoritative quantity ledger are fingerprinted before GF-023 is applied.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf023_upgrade"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}" PGUSER
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
if [[ -n "$CONTAINER" ]]; then
  pg_root() { docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d postgres "$@"; }
  pg_db() { local db="$1"; shift; docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$db" "$@"; }
else
  pg_root() { psql -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
  pg_db() { local db="$1"; shift; psql -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
fi
pg_root -c "drop database if exists \"$UPGRADE_DB\";" >/dev/null
pg_root -c "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' "$ROOT/supabase/tests/00_supabase_shim.sql" | pg_db "$UPGRADE_DB" >/dev/null
PREREQ=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ "$base" < 20260815010000_ ]] || continue
  pg_db "$UPGRADE_DB" < "$migration" >/dev/null
  PREREQ=$((PREREQ+1))
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == 00_* ]] && continue
  [[ "$base" < 71_ ]] || continue
  pg_db "$UPGRADE_DB" < "$test_file" >/dev/null
done
[[ "$(pg_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_feed_issues') is null")" == t ]] || { echo 'ERROR: fixture is not pre-GF-023'; exit 1; }
[[ "$(pg_db "$UPGRADE_DB" -Atc "select count(*)=6 from livestock_quantity_event_types")" == t ]] || { echo 'ERROR: GF-022 quantity boundary absent'; exit 1; }

fingerprint="select md5(jsonb_build_object(
 'projects',(select jsonb_agg(to_jsonb(x) order by id) from investment_projects x),
 'journals',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_batches x),
 'lines',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_lines x),
 'cohorts',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohorts x),
 'placements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_initial_placements x),
 'movements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_movements x),
 'weights',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_weight_events x),
 'quantity',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_quantity_events x),
 'operations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_quantity_operations x),
 'lineage',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_lineage x)
)::text);"
BEFORE="$(pg_db "$UPGRADE_DB" -Atc "$fingerprint")"
ROLL_BEFORE="$(pg_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text,',' order by cohort_id::text),'')) from livestock_cohort_quantity_rollforward")"
pg_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260815010000_livestock_operations_completion.sql" >/dev/null
AFTER="$(pg_db "$UPGRADE_DB" -Atc "$fingerprint")"
ROLL_AFTER="$(pg_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text,',' order by cohort_id::text),'')) from livestock_cohort_quantity_rollforward")"
[[ "$BEFORE" == "$AFTER" && "$ROLL_BEFORE" == "$ROLL_AFTER" ]] || { echo 'ERROR: GF-023 changed GF-022 or prior rows/quantity'; exit 1; }

ORG='10000000-0000-4000-8000-000000000001'; ACTOR='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$ACTOR'; set role authenticated;"
PROJECT="$(pg_db "$UPGRADE_DB" -Atc "select id from investment_projects where internal_reference='GF020-LS-A' limit 1")"
HERD="$(pg_db "$UPGRADE_DB" -Atc "select id from livestock_herds where project_id='$PROJECT' and internal_reference='HERD-A' limit 1")"
SITE="$(pg_db "$UPGRADE_DB" -Atc "select id from livestock_sites where project_id='$PROJECT' and internal_reference='SITE-A' limit 1")"
COHORT="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة ترقية 023','BORN',current_date-1,12,'MIXED',null,null,null,null,'دليل',null,'gf23-up-cohort');" | tail -1)"
pg_db "$UPGRADE_DB" -Atc "$AUTH select transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل ترقية 023',null,'gf23-up-active');" >/dev/null
PRODUCT="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_medicine_product('$ORG','$PROJECT','UP-MED','دواء ترقية','MEDICINE',null,3,null,'gf23-up-med');" | tail -1)"
ANIMAL="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select identify_livestock_animal('$ORG','$PROJECT','$COHORT','EAR_TAG','UP-023-1','FEMALE',null,null,current_date::timestamptz,'دليل',null,'gf23-up-animal');" | tail -1)"
HEALTH="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_health_event('$ORG','$PROJECT','$COHORT','$ANIMAL','TREATMENT',null,null,'$PRODUCT',5,'ML','ORAL',current_date::timestamptz,'طبيب','دليل',null,'gf23-up-health');" | tail -1)"
REPRO="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_reproduction_event('$ORG','$PROJECT','$COHORT','$ANIMAL','BIRTH_OUTCOME',1,null,null,null,2,0,'GF022_BIRTH',null,'$ANIMAL',null,current_date::timestamptz,'مشرف','دليل',null,'gf23-up-repro');" | tail -1)"
FEED="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_feed_item('$ORG','$PROJECT','UP-FEED','علف ترقية','ROUGHAGE','KG',null,'gf23-up-feed');" | tail -1)"
ISSUE="$(pg_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_feed_issue('$ORG','$PROJECT','$COHORT','$FEED',20,'KG',current_date::timestamptz,null,null,'عامل','دليل',null,'gf23-up-issue');" | tail -1)"
CHECK="$(pg_db "$UPGRADE_DB" -Atc "select (
 (select withdrawal_period_days=3 from livestock_health_events where id='$HEALTH')
 and (select birth_quantity_event_id is not null from livestock_reproduction_events where id='$REPRO')
 and (select births=2 and current_quantity=14 from livestock_cohort_quantity_rollforward where cohort_id='$COHORT')
 and (select identification_quantity_effect=0 from livestock_animals_read where id='$ANIMAL')
 and (select quantity::numeric=20 from livestock_feed_issues_read where id='$ISSUE')
 and (select count(*)=6 from livestock_quantity_event_types)
)::text")"
[[ "$CHECK" == true ]] || { echo "ERROR: GF-023 post-upgrade workflow failed ($CHECK)"; exit 1; }
echo "GF-023 forward-upgrade PASS: $PREREQ prerequisite migrations; GF-022 fingerprints and quantities preserved; health, identity, linked birth and feed exercised."
