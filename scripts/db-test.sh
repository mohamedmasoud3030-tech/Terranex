#!/usr/bin/env bash
# Greenfield database gate: fresh migration replay + SQL test suite.
# Uses the local `psql` when available (CI); otherwise falls back to the
# Node-based runner in scripts/psql-runner.mjs for local/offline checks.
set -euo pipefail
: "${PGHOST:=127.0.0.1}"; : "${PGPORT:=5432}"; : "${PGUSER:=postgres}"; : "${PGPASSWORD:=postgres}"
export PGHOST PGPORT PGUSER PGPASSWORD
DB="${TERRANEX_TEST_DB:=terranex_greenfield_test}"
root="$(cd "$(dirname "$0")/.." && pwd)"

run_sql() {
  if command -v psql >/dev/null 2>&1; then
    psql -v ON_ERROR_STOP=1 --no-psqlrc -d "$2" -f "$1"
  else
    PGDATABASE="$2" node "$root/scripts/psql-runner.mjs" "$1"
  fi
}
run_inline() {
  if command -v psql >/dev/null 2>&1; then
    psql -v ON_ERROR_STOP=1 --no-psqlrc -d postgres -c "$1"
  else
    PGDATABASE=postgres node "$root/scripts/psql-runner.mjs" /dev/stdin <<<"$1"
  fi
}

if command -v psql >/dev/null 2>&1; then
  PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$DB' and pid <> pg_backend_pid();" >/dev/null || true
  PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 -d postgres -c "drop database if exists $DB;"
  PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 -d postgres -c "create database $DB;"
else
  PGDATABASE=postgres node "$root/scripts/psql-runner.mjs" /dev/stdin <<SQL
select pg_terminate_backend(pid) from pg_stat_activity where datname='$DB' and pid <> pg_backend_pid();
drop database if exists $DB;
drop role if exists authenticated;
drop role if exists anon;
create role authenticated nologin;
create role anon nologin;
grant authenticated to postgres;
create database $DB;
SQL
fi

export TERRANEX_TEST_DB="$DB"
run_sql "$root/supabase/tests/00_supabase_shim.sql" "$DB"
for f in "$root"/supabase/migrations/*.sql; do
  echo "applying $(basename "$f")"
  run_sql "$f" "$DB"
done
for f in "$root"/supabase/tests/[0-9]*.sql; do
  case "$(basename "$f")" in
    00_*) continue ;;
  esac
  echo "running $(basename "$f")"
  run_sql "$f" "$DB"
done
echo 'Migration replay and Greenfield database tests passed.'
