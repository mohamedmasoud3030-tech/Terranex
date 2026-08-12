#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_s5_upgrade"
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

# Exact pre-S5 boundary: replay every merged S0-S6 migration, excluding only
# the S5 family under verification.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260812*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

BEFORE="$(psql_cmd "$UPGRADE_DB" "select (
  to_regclass('public.close_run_snapshots') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regclass('public.s5_allocation_runs') is null
  and to_regprocedure('public.s6_approve_close_run(uuid,uuid,text)') is not null
  and to_regprocedure('public.recognize_property_sale(uuid,uuid,date,text)') is not null
)::text")"
if [[ "$BEFORE" != 'true' ]]; then
  echo 'ERROR: S5 forward-upgrade fixture is not the merged S0-S6 boundary.' >&2
  exit 1
fi

s5_migrations=("$ROOT"/supabase/migrations/20260812*.sql)
if [[ ! -e "${s5_migrations[0]}" ]]; then
  echo 'ERROR: no S5 migration family found.' >&2
  exit 1
fi
for file in "${s5_migrations[@]}"; do
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER="$(psql_cmd "$UPGRADE_DB" "select (
  to_regclass('public.s5_allocation_rule_sets') is not null
  and to_regclass('public.s5_allocation_rules') is not null
  and to_regclass('public.s5_allocation_runs') is not null
  and to_regclass('public.s5_allocation_lines') is not null
  and to_regclass('public.s5_distributions') is not null
  and to_regclass('public.s5_distribution_payments') is not null
  and to_regprocedure('public.s5_configure_allocation_rules(uuid,uuid,uuid,text,uuid[],bigint[],bigint,text)') is not null
  and to_regprocedure('public.s5_prepare_allocation(uuid,uuid,uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s5_approve_allocation(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.s5_prepare_distribution(uuid,uuid,uuid,uuid,bigint,text,text)') is not null
  and to_regprocedure('public.s5_approve_distribution(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.s5_pay_distribution(uuid,uuid,uuid,bigint,date,text,text)') is not null
  and to_regclass('public.close_run_snapshots') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regprocedure('public.s6_approve_close_run(uuid,uuid,text)') is not null
  and to_regprocedure('public.recognize_property_sale(uuid,uuid,date,text)') is not null
)::text")"
if [[ "$AFTER" != 'true' ]]; then
  echo 'ERROR: S5 forward upgrade did not preserve S0-S6 or add every S5 primitive.' >&2
  exit 1
fi

echo 'S5 forward upgrade from merged S6 PASS'
