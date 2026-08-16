#!/usr/bin/env bash
set -euo pipefail

# F3–F10 forward-upgrade gate: replay every migration ordered BEFORE the
# F3 family (the complete R4/P2/P3 state), then apply the F3–F10 family
# as the upgrade phase and verify the full contract-finance/budget/
# approval/currency/integrity/performance/roll-up surface exists and that
# the pre-existing Finance Core primitives survive the upgrade unchanged.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_f3f10_upgrade"
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
psql_cmd postgres "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB"

# Pre-F3 boundary: replay every migration ordered BEFORE the F3 family.
for file in "$ROOT"/supabase/migrations/*.sql; do
  base="$(basename "$file")"
  if [[ "$base" == 20260816050000*.sql || "$base" > 20260816050000_ ]]; then
    continue
  fi
  psql_db "$UPGRADE_DB" < "$file"
done

BEFORE="$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.cost_obligations') is not null
    and to_regclass('public.journal_batches') is not null
    and to_regclass('public.cost_payment_proposals') is not null
    and to_regprocedure('public.approve_cost_payment(uuid,uuid,text)') is not null
    and to_regclass('public.investment_portfolios') is not null
    and to_regclass('public.project_milestones') is null
    and to_regclass('public.cost_obligation_terms') is null
    and to_regclass('public.project_budgets') is null
    and to_regclass('public.approval_policies') is null
    and to_regclass('public.approval_exceptions') is null
    and to_regclass('public.fx_rate_snapshots') is null
    and to_regclass('public.tax_registry') is null
  )::text
")"
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-F3 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

f3f10_migrations=("$ROOT"/supabase/migrations/20260816*.sql)
if (( ${#f3f10_migrations[@]} == 0 )); then
  echo 'ERROR: no F3-F10 migrations found for forward-upgrade verification.' >&2
  exit 1
fi
for file in "${f3f10_migrations[@]}"; do
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER="$(psql_cmd "$UPGRADE_DB" "
  select (
    -- F3
    to_regclass('public.project_milestones') is not null
    and to_regclass('public.cost_obligation_terms') is not null
    and to_regclass('public.cost_obligation_schedule_lines') is not null
    and to_regclass('public.cost_obligation_disputes') is not null
    and to_regclass('public.cost_obligation_retention_releases') is not null
    and to_regclass('public.cost_obligation_due_read') is not null
    and to_regprocedure('public.f3_set_obligation_terms(uuid,uuid,text,date,integer,bigint,text,text,text)') is not null
    and to_regprocedure('public.f3_open_obligation_dispute(uuid,uuid,text,text)') is not null
    -- F4
    and to_regclass('public.project_budgets') is not null
    and to_regclass('public.project_budget_lines') is not null
    and to_regprocedure('public.f4_create_project_budget(uuid,uuid,date,date,text,text,text,text,jsonb,text)') is not null
    -- F5
    and to_regclass('public.approval_policies') is not null
    and to_regclass('public.approval_exceptions') is not null
    and to_regclass('public.approval_exception_registry_read') is not null
    -- F6
    and to_regclass('public.fx_rate_snapshots') is not null
    and to_regclass('public.fx_conversion_log') is not null
    and to_regclass('public.tax_registry') is not null
    and to_regprocedure('public.fx_convert_exact(bigint,bigint,bigint)') is not null
    -- F7/F8/F9/F10
    and to_regclass('public.period_close_health_read') is not null
    and to_regclass('public.financial_integrity_signals_read') is not null
    and to_regclass('public.project_financial_position_read') is not null
    and to_regclass('public.portfolio_financial_rollup_read') is not null
    and to_regclass('public.organization_financial_consolidation_read') is not null
    -- pre-existing primitives survive
    and to_regprocedure('public.create_cost_obligation(uuid,uuid,uuid,text,bigint,text,date,text,text)') is not null
    and to_regprocedure('public.approve_cost_payment(uuid,uuid,text)') is not null
    and to_regprocedure('public.prepare_cost_payment(uuid,uuid,uuid,bigint,date,text)') is not null
  )::text
")"
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: F3-F10 forward upgrade did not deliver the full contract-finance surface (AFTER=$AFTER)" >&2
  exit 1
fi

# The pgcrypto qualification pass must leave no unqualified digest call.
DIGEST_CHECK="$(psql_cmd "$UPGRADE_DB" "
  select count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and pg_get_functiondef(p.oid) ~ '(^|[^[:alnum:]_.])digest[[:space:]]*\\('
")"
if [[ "$DIGEST_CHECK" != "0" ]]; then
  echo "ERROR: $DIGEST_CHECK public functions still call digest unqualified after the F3-F10 upgrade" >&2
  exit 1
fi

echo 'F3-F10 forward upgrade from the pre-F3 boundary PASS'
