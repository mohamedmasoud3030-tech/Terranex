#!/usr/bin/env bash
set -euo pipefail

# GF-022 forward upgrade.
#
# Proves that applying the GF-022 migration to a database already carrying the
# complete GF-021 boundary:
#   1. changes no prior-sector, Finance, GF-020, or GF-021 row;
#   2. is genuinely ADDITIVE on the GF-021 quantity architecture — the ledger
#      table is extended, never rebuilt, and pre-existing Cohorts keep their
#      derived quantities;
#   3. enables births, mortality, split and merge with exact conservation.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf022_upgrade"
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

# Complete merged boundary through GF-021; exclude the GF-022 family only.
PREREQ=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ ! "$base" < 20260814001900_ ]] && continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
  PREREQ=$((PREREQ + 1))
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == 00_* ]] && continue
  [[ "$base" < 65_ ]] || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done

[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_quantity_operations') is null")" == t ]] || {
  echo 'ERROR: fixture is not genuinely pre-GF-022' >&2
  exit 1
}
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_quantity_events') is not null")" == t ]] || {
  echo 'ERROR: fixture does not carry the GF-021 quantity architecture' >&2
  exit 1
}
[[ "$(psql_db "$UPGRADE_DB" -Atc "select count(*)=0 from livestock_quantity_event_types")" == t ]] || {
  echo 'ERROR: the GF-021 boundary should register no quantity event class' >&2
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
  'ls_cohorts',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohorts x),
  'ls_placements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_initial_placements x),
  'ls_history',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_state_history x),
  'ls_movements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_movements x),
  -- The hardening migration adds confidence_level. Fingerprint the old
  -- columns explicitly so an additive quality field is not a row mutation.
  'ls_weights',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'organization_id',x.organization_id,'project_id',x.project_id,
    'cohort_id',x.cohort_id,'effective_at',x.effective_at,'method',x.method,
    'weight_value',x.weight_value,'weight_unit',x.weight_unit,
    'measured_animal_count',x.measured_animal_count,'sample_size',x.sample_size,
    'evidence_reference',x.evidence_reference,'notes',x.notes,
    'recorded_by',x.recorded_by,'recorded_at',x.recorded_at,
    'idempotency_key',x.idempotency_key,'request_hash',x.request_hash
  ) order by x.id),'[]') from livestock_weight_events x),
  'ls_quantity',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_quantity_events x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"

# Derived quantities observed on the GF-021 boundary, to prove they survive.
QUANTITIES_BEFORE="$(psql_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text, ',' order by cohort_id::text), ''))
  from livestock_cohort_quantity_rollforward")"

# Apply the complete GF-022 family in order: biological events followed by
# review hardening.
for migration in \
  "$ROOT"/supabase/migrations/20260814001900_*.sql \
  "$ROOT"/supabase/migrations/20260814002000_*.sql; do
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
done

AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || {
  echo 'ERROR: GF-022 changed prior-sector, Finance, GF-020 or GF-021 rows' >&2
  exit 1
}
QUANTITIES_AFTER="$(psql_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text, ',' order by cohort_id::text), ''))
  from livestock_cohort_quantity_rollforward")"
[[ "$QUANTITIES_BEFORE" == "$QUANTITIES_AFTER" ]] || {
  echo 'ERROR: GF-022 changed a pre-existing derived quantity' >&2
  exit 1
}

# The upgrade is additive: the GF-021 ledger table was extended, not replaced.
ADDITIVE="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select count(*)=6 from livestock_quantity_event_types)
  and (select count(*)>0 from information_schema.columns
       where table_schema='public' and table_name='livestock_quantity_events'
         and column_name='operation_id')
)::text")"
[[ "$ADDITIVE" == true ]] || {
  echo "ERROR: GF-022 did not extend the GF-021 ledger additively ($ADDITIVE)" >&2
  exit 1
}

ORG='10000000-0000-4000-8000-000000000001'
OWNER='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$OWNER'; set role authenticated;"

PROJECT="$(psql_db "$UPGRADE_DB" -Atc "select id from investment_projects where internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_herds where internal_reference='HERD-A' and project_id='$PROJECT' limit 1")"
SITE="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_sites where internal_reference='SITE-A' and project_id='$PROJECT' limit 1")"

# A Cohort created before GF-022 still reports current = opening, then accepts
# the new biological events.
COHORT="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة ترقية 022','PURCHASED',date '2026-09-01',80,null,null,null,null,null,null,null,'gf22-up-cohort');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل ترقية',null,'gf22-up-activate');" >/dev/null
psql_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_birth('$ORG','$PROJECT','$COHORT',10,now(),null,null,'gf22-up-birth');" >/dev/null
psql_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_mortality('$ORG','$PROJECT','$COHORT',5,now(),'DISEASE',null,null,null,'gf22-up-mortality');" >/dev/null
SPLIT_OP="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select split_livestock_cohort('$ORG','$PROJECT','$COHORT',25,now(),'ناتج ترقية التقسيم','$HERD','$SITE',null,null,'تقسيم ترقية',null,null,'gf22-up-split');" | tail -1)"
SPLIT_DEST="$(psql_db "$UPGRADE_DB" -Atc "select destination_cohort_id from livestock_cohort_lineage where operation_id='$SPLIT_OP'")"
MERGE_OP="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select merge_livestock_cohorts('$ORG','$PROJECT',array['$COHORT','$SPLIT_DEST']::uuid[],array[20,25]::integer[],now(),'ناتج ترقية الدمج','$HERD','$SITE',null,null,'دمج ترقية',null,null,'gf22-up-merge');" | tail -1)"
MERGE_DEST="$(psql_db "$UPGRADE_DB" -Atc "select distinct destination_cohort_id from livestock_cohort_lineage where operation_id='$MERGE_OP'")"

# 80 opening + 10 births - 5 mortality - 25 split_out - 20 merge_out = 40.
CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select opening_headcount=80 and births=10 and mortality=5 and split_out=25
      and merge_out=20 and current_quantity=40
     from livestock_cohort_quantity_rollforward where cohort_id='$COHORT')
  and (select current_quantity=0 and merge_out=25 and split_in=25
     from livestock_cohort_quantity_rollforward where cohort_id='$SPLIT_DEST')
  and (select opening_headcount=0 and merge_in=45 and current_quantity=45
     from livestock_cohort_quantity_rollforward where cohort_id='$MERGE_DEST')
  and (select bool_and(current_quantity =
        opening_headcount + births + split_in + merge_in
        - mortality - split_out - merge_out)
     from livestock_cohort_quantity_rollforward)
  and (select count(*)=0 from livestock_cohort_quantity_rollforward where current_quantity < 0)
)::text")"
[[ "$CHECK" == true ]] || {
  echo "ERROR: GF-022 post-upgrade workflow failed ($CHECK)" >&2
  exit 1
}

echo "GF-022 forward-upgrade PASS: $PREREQ prerequisite migrations; exact GF-021 boundary and derived quantities preserved; births, mortality, split and merge exercised with exact conservation."
