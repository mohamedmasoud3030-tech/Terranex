#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_s3_upgrade"
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
# Roles are cluster-global and were already created by the canonical fresh
# replay in the primary test database. Recreate only the per-database Auth shim.
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB"

# Keep this fixture at the exact pre-S3 (merged S2) boundary. All migrations in
# the 202608110004xx family belong to GF-005/S3 and must be applied only after
# the pre-upgrade assertion, in normal lexical migration order.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    202608110004*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

BEFORE="$(psql_cmd "$UPGRADE_DB" "select (to_regclass('public.cost_obligations') is not null and to_regclass('public.journal_batches') is not null and to_regclass('public.property_assets') is null)::text")"
if [[ "$BEFORE" != 'true' ]]; then
  echo 'ERROR: forward-upgrade fixture is not the merged S2 schema.' >&2
  exit 1
fi

s3_migrations=("$ROOT"/supabase/migrations/202608110004*.sql)
if [[ ! -e "${s3_migrations[0]}" ]]; then
  echo 'ERROR: no S3 migrations found for forward-upgrade verification.' >&2
  exit 1
fi
for file in "${s3_migrations[@]}"; do
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER="$(psql_cmd "$UPGRADE_DB" "select (to_regclass('public.cost_obligations') is not null and to_regclass('public.journal_batches') is not null and to_regclass('public.property_assets') is not null and to_regclass('public.property_cost_items') is not null and to_regprocedure('public.s3_has_current_effective_control(uuid,text)') is not null)::text")"
if [[ "$AFTER" != 'true' ]]; then
  echo 'ERROR: full S3 forward upgrade did not preserve S2 and add all S3 hardening.' >&2
  exit 1
fi

echo 'S3 forward upgrade from merged S2 PASS'
