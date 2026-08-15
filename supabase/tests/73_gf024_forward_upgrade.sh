#!/usr/bin/env bash
set -euo pipefail

# GF-024 forward upgrade.
#
# Proves that applying the GF-024 migration to a database already carrying the
# complete GF-022 boundary:
#   1. changes no prior-sector, Finance, GF-020, GF-021, or GF-022 row;
#   2. is genuinely ADDITIVE on the quantity registry (6 classes -> 8) and the
#      semantic account registry (one new revenue role);
#   3. fabricates NO purchases or sales for pre-existing rows;
#   4. enables purchase, sale, revenue, collection, cost attribution,
#      profitability and closeout on pre-existing Cohorts.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${DB}_gf024_upgrade"
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

# Complete merged boundary through GF-022; exclude the GF-024 migration only.
PREREQ=0
for migration in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$migration")"
  [[ ! "$base" < 20260815020000_ ]] && continue
  psql_db "$UPGRADE_DB" < "$migration" >/dev/null
  PREREQ=$((PREREQ + 1))
done
for test_file in "$ROOT"/supabase/tests/*.sql; do
  base="$(basename "$test_file")"
  [[ "$base" == 00_* ]] && continue
  [[ "$base" < 71_ ]] || continue
  psql_db "$UPGRADE_DB" < "$test_file" >/dev/null
done

[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_purchases') is null")" == t ]] || {
  echo 'ERROR: fixture is not genuinely pre-GF-024' >&2
  exit 1
}
[[ "$(psql_db "$UPGRADE_DB" -Atc "select to_regclass('public.livestock_quantity_events') is not null")" == t ]] || {
  echo 'ERROR: fixture does not carry the GF-021 quantity architecture' >&2
  exit 1
}
[[ "$(psql_db "$UPGRADE_DB" -Atc "select count(*)=6 from livestock_quantity_event_types")" == t ]] || {
  echo 'ERROR: the GF-022 boundary should register exactly six quantity classes' >&2
  exit 1
}

fingerprint_sql="select md5(jsonb_build_object(
  'projects',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from investment_projects x),
  'semantic_roles',(select coalesce(jsonb_agg(jsonb_build_object('role',x.role,'label_ar',x.label_ar) order by x.role),'[]')
                    from semantic_accounts x where x.role <> 'LIVESTOCK_SALE_REVENUE'),
  'qtypes',(select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'direction',x.direction,'label_ar',x.label_ar,'requires_operation',x.requires_operation,'requires_cause',x.requires_cause,'requires_disposal',x.requires_disposal) order by x.code),'[]')
            from livestock_quantity_event_types x where x.code not in ('PURCHASE_IN','SALE_OUT')),
  'parties',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from parties x),
  'cash',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from project_cash_accounts x),
  'obligations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from cost_obligations x),
  'payments',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from project_payments x),
  'journals',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_batches x),
  'lines',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_lines x),
  'ls_cohorts',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohorts x),
  'ls_placements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_initial_placements x),
  'ls_history',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_state_history x),
  'ls_movements',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_movements x),
  'ls_weights',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_weight_events x),
  'ls_quantity',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_quantity_events x),
  'ls_operations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_quantity_operations x),
  'ls_lineage',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from livestock_cohort_lineage x)
)::text);"
BEFORE="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
QUANTITIES_BEFORE="$(psql_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text, ',' order by cohort_id::text), ''))
  from livestock_cohort_quantity_rollforward")"

# Apply GF-024.
psql_db "$UPGRADE_DB" < "$ROOT"/supabase/migrations/20260815020000_livestock_commercial_profitability_closeout.sql >/dev/null

AFTER="$(psql_db "$UPGRADE_DB" -Atc "$fingerprint_sql")"
[[ "$BEFORE" == "$AFTER" ]] || {
  echo 'ERROR: GF-024 changed prior-sector, Finance, GF-020, GF-021 or GF-022 rows' >&2
  exit 1
}
QUANTITIES_AFTER="$(psql_db "$UPGRADE_DB" -Atc "select md5(coalesce(string_agg(cohort_id::text||':'||current_quantity::text, ',' order by cohort_id::text), ''))
  from livestock_cohort_quantity_rollforward")"
[[ "$QUANTITIES_BEFORE" == "$QUANTITIES_AFTER" ]] || {
  echo 'ERROR: GF-024 changed a pre-existing derived quantity' >&2
  exit 1
}

ADDITIVE="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select count(*)=8 from livestock_quantity_event_types)
  and (select count(*)=2 from livestock_quantity_event_types where code in ('PURCHASE_IN','SALE_OUT'))
  and (select count(*)=1 from semantic_accounts where role='LIVESTOCK_SALE_REVENUE')
)::text")"
[[ "$ADDITIVE" == true ]] || {
  echo "ERROR: GF-024 did not extend the registries additively ($ADDITIVE)" >&2
  exit 1
}
NO_FABRICATED_COMMERCIAL="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select count(*)=0 from livestock_purchases)
  and (select count(*)=0 from livestock_sales)
  and (select count(*)=0 from livestock_sale_recognitions)
  and (select count(*)=0 from livestock_sale_collections)
  and (select count(*)=0 from livestock_cohort_cost_attributions)
  and (select count(*)=0 from livestock_cohort_closeouts)
)::text")"
[[ "$NO_FABRICATED_COMMERCIAL" == true ]] || {
  echo 'ERROR: the upgrade fabricated commercial facts for pre-existing rows' >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Exercise the new workflow on a Cohort created before GF-024.
# ---------------------------------------------------------------------------
ORG='10000000-0000-4000-8000-000000000001'
OWNER='00000000-0000-4000-8000-000000000001'
AUTH="set request.jwt.claim.sub='$OWNER'; set role authenticated;"

PROJECT="$(psql_db "$UPGRADE_DB" -Atc "select id from investment_projects where internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_herds where internal_reference='HERD-A' and project_id='$PROJECT' limit 1")"
SITE="$(psql_db "$UPGRADE_DB" -Atc "select id from livestock_sites where internal_reference='SITE-A' and project_id='$PROJECT' limit 1")"
BUYER="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_party('$ORG','مشتري ترقية GF024','ORGANIZATION');" | tail -1)"
SUPPLIER="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_party('$ORG','مورد ترقية GF024','ORGANIZATION');" | tail -1)"
CASH="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_project_cash_account('$ORG','$PROJECT','نقدية ترقية GF024','EGP');" | tail -1)"

COHORT="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','دفعة ترقية GF024','PURCHASED',date '2026-08-01',80,null,null,null,null,null,null,null,'gf24-up-cohort');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select transition_livestock_cohort('$ORG','$PROJECT','$COHORT','PLANNED','ACTIVE','تفعيل ترقية GF024',null,'gf24-up-activate');" >/dev/null
psql_db "$UPGRADE_DB" -Atc "$AUTH select record_livestock_purchase('$ORG','$PROJECT','$SUPPLIER','شراء ترقية GF024','عقد ترقية',timestamptz '2026-08-05 08:00+00','دليل شراء',null,array['$COHORT'::uuid],array[20]::integer[],array[50000]::bigint[],'gf24-up-purchase');" >/dev/null

SALE="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_livestock_sale('$ORG','$PROJECT','$BUYER','بيع ترقية GF024',null,current_date,'EGP',null,'دليل بيع',array['$COHORT'::uuid],array[40]::integer[],array[8000]::bigint[],'gf24-up-sale');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select approve_livestock_sale('$ORG','$SALE','gf24-up-approve');" >/dev/null
RECOG="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select recognize_livestock_sale('$ORG','$SALE',current_date,'تسليم ترقية','gf24-up-recognize');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select collect_livestock_sale_receivable('$ORG','$RECOG','$CASH',320000,current_date,'تحصيل ترقية','gf24-up-collection');" >/dev/null

OBLIGATION="$(psql_db "$UPGRADE_DB" -Atc "$AUTH select create_cost_obligation('$ORG','$PROJECT','$SUPPLIER','تكلفة ترقية GF024',100000,'EGP',current_date,'EXPENSE','gf24-up-cost');" | tail -1)"
psql_db "$UPGRADE_DB" -Atc "$AUTH select authorize_cost_obligation('$ORG','$OBLIGATION','gf24-up-cost-authorize');" >/dev/null
COST_LINE="$(psql_db "$UPGRADE_DB" -Atc "select id from journal_lines where organization_id='$ORG' and project_id='$PROJECT' and debit_minor_units=100000 order by posting_date desc limit 1")"
psql_db "$UPGRADE_DB" -Atc "$AUTH select attribute_livestock_cohort_cost('$ORG','$PROJECT','$COHORT','$COST_LINE',100000,'FEED','سياسة ترقية','مذكرة ترقية','gf24-up-attribution');" >/dev/null

# 80 opening + 20 purchase - 40 sale_out = 60 unsold; revenue 320000, cost 100000.
CHECK="$(psql_db "$UPGRADE_DB" -Atc "select (
  (select opening_headcount=80 and purchase_in=20 and sale_out=40 and current_quantity=60
     from livestock_cohort_quantity_rollforward where cohort_id='$COHORT')
  and (select recognized_revenue_minor_units='320000' and cash_collected_minor_units='320000'
       and attributed_operating_cost_minor_units='100000' and operating_result_to_date_minor_units='220000'
       and unsold_live_quantity=60 from livestock_cohort_results_read where cohort_id='$COHORT')
)::text")"
[[ "$CHECK" == true ]] || {
  echo "ERROR: GF-024 post-upgrade workflow failed ($CHECK)" >&2
  exit 1
}

psql_db "$UPGRADE_DB" -Atc "$AUTH select close_livestock_cohort('$ORG','$PROJECT','$COHORT','اكتمال ترقية GF024','مذكرة إقفال ترقية','gf24-up-close');" >/dev/null
STATE="$(psql_db "$UPGRADE_DB" -Atc "select public.livestock_current_cohort_state('$COHORT')")"
[[ "$STATE" == 'ACTIVE' ]] || {
  echo "ERROR: technical close mutated the Cohort lifecycle to $STATE" >&2
  exit 1
}

echo "GF-024 forward-upgrade PASS: $PREREQ prerequisite migrations; exact GF-022 boundary and derived quantities preserved; registries extended additively with no fabricated commercial facts; purchase, sale, revenue, collection, cost attribution, result and closeout exercised."
