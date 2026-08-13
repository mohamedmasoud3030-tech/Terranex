#!/usr/bin/env bash
set -euo pipefail

# GF-007 / S6 — forward-upgrade verification: replay S0..S4 against a
# separate database, then apply the S6 migration family. All S0..S4
# objects and procedures must be preserved and all S6 primitives must be
# present.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_s6_upgrade"
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

# Replay S0..S4 only; the S6 family and every later stage are excluded.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    202608110006*.sql|20260812*.sql|20260813*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

BEFORE="$(psql_cmd "$UPGRADE_DB" "select (to_regclass('public.journal_batches') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regclass('public.property_sale_collections') is not null
  and to_regclass('public.accounting_periods') is null
  and to_regclass('public.close_runs') is null
  and to_regclass('public.close_run_snapshots') is null
  and to_regprocedure('public.recognize_property_sale(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.collect_property_sale_receivable(uuid,uuid,uuid,bigint,date,text,text)') is not null)::text")"
if [[ "$BEFORE" != 'true' ]]; then
  echo "ERROR: pre-S6 forward-upgrade fixture is not the merged S0..S4 schema." >&2
  exit 1
fi

# Apply the S6 migration family.
s6_migrations=("$ROOT"/supabase/migrations/202608110006*.sql)
if [[ ! -e "${s6_migrations[0]}" ]]; then
  echo "ERROR: no S6 migrations found for forward-upgrade verification." >&2
  exit 1
fi
for file in "${s6_migrations[@]}"; do
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER="$(psql_cmd "$UPGRADE_DB" "select (to_regclass('public.accounting_periods') is not null
  and to_regclass('public.close_runs') is not null
  and to_regclass('public.close_run_gates') is not null
  and to_regclass('public.close_run_exceptions') is not null
  and to_regclass('public.close_run_snapshots') is not null
  and to_regclass('public.correction_requests') is not null
  and to_regprocedure('public.s6_create_accounting_period(uuid,uuid,date,date)') is not null
  and to_regprocedure('public.s6_prepare_close_run(uuid,uuid,uuid,text)') is not null
  and to_regprocedure('public.s6_approve_close_run(uuid,uuid,text)') is not null
  and to_regprocedure('public.s6_reopen_period(uuid,uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s6_request_correction(uuid,uuid,uuid,uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s6_approve_correction(uuid,uuid,text)') is not null
  and to_regprocedure('public.s6_execute_correction(uuid,uuid,date,text)') is not null
  -- S0..S4 still present and unchanged
  and to_regclass('public.journal_batches') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regclass('public.property_sale_collections') is not null
  and to_regprocedure('public.recognize_property_sale(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.collect_property_sale_receivable(uuid,uuid,uuid,bigint,date,text,text)') is not null)::text")"
if [[ "$AFTER" != 'true' ]]; then
  echo "ERROR: S6 forward upgrade did not preserve S0..S4 or did not add all S6 primitives." >&2
  exit 1
fi

echo "S6 forward upgrade from merged S4 PASS"
