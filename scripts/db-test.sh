#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD PGUSER

container_name=""
cleanup() {
  if [[ -n "$container_name" ]]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if command -v psql >/dev/null 2>&1; then
  : "${PGHOST:=127.0.0.1}"
  : "${PGPORT:=5432}"
  export PGHOST PGPORT
  psql_exec() { psql -q -v ON_ERROR_STOP=1 "$@"; }
  psql_stdin() { local db="$1"; psql -q -v ON_ERROR_STOP=1 -d "$db"; }
elif command -v docker >/dev/null 2>&1; then
  container_name="terranex-db-test-$RANDOM-$$"
  docker run -d --rm \
    --name "$container_name" \
    -e POSTGRES_USER="$PGUSER" \
    -e POSTGRES_PASSWORD="$PGPASSWORD" \
    -e POSTGRES_DB=postgres \
    postgres:16-alpine >/dev/null

  for _ in $(seq 1 60); do
    if docker exec "$container_name" pg_isready -U "$PGUSER" -d postgres >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  docker exec "$container_name" pg_isready -U "$PGUSER" -d postgres >/dev/null

  psql_exec() { docker exec -i "$container_name" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" "$@"; }
  psql_stdin() { local db="$1"; docker exec -i "$container_name" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$db"; }
else
  echo "ERROR: Database verification cannot run: neither 'psql' nor 'docker' is available." >&2
  echo "Install PostgreSQL client or Docker. Database tests are a required gate and must not be skipped." >&2
  exit 2
fi

run_file() {
  local db="$1"
  local file="$2"
  local output
  echo "==> $file"
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$(basename "$file")" == *s3* ]]; then echo "::notice::S3_GATE_START $(basename "$file")"; fi
  if ! output="$(psql_stdin "$db" < "$file" 2>&1)"; then
    printf '%s\n' "$output" >&2
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      local detail
      detail="$(printf '%s' "$output" | tail -20 | tr '\n' ' ' | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g')"
      echo "::error file=${file#"$ROOT/"}::${detail}"
    fi
    return 1
  fi
  [[ -n "$output" ]] && printf '%s\n' "$output"
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$(basename "$file")" == *s3* ]]; then echo "::notice::S3_GATE_PASS $(basename "$file")"; fi
}

psql_exec -d postgres -c "drop database if exists \"$DB\";"
psql_exec -d postgres -c "create database \"$DB\";"

run_file "$DB" "$ROOT/supabase/tests/00_supabase_shim.sql"

shopt -s nullglob
migrations=("$ROOT"/supabase/migrations/*.sql)
if (( ${#migrations[@]} == 0 )); then
  echo "ERROR: no migrations found." >&2
  exit 3
fi
for file in "${migrations[@]}"; do
  run_file "$DB" "$file"
done

sql_tests=("$ROOT"/supabase/tests/*.sql)
for file in "${sql_tests[@]}"; do
  [[ "$(basename "$file")" == "00_supabase_shim.sql" ]] && continue
  run_file "$DB" "$file"
done

shell_tests=("$ROOT"/supabase/tests/*.sh)
for file in "${shell_tests[@]}"; do
  echo "==> $file"
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$(basename "$file")" == *s3* ]]; then echo "::notice::S3_GATE_START $(basename "$file")"; fi
  output=""
  if ! output="$(TERRANEX_TEST_DB="$DB" TERRANEX_DB_CONTAINER="$container_name" bash "$file" 2>&1)"; then
    printf '%s\n' "$output" >&2
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      detail="$(printf '%s' "$output" | tail -20 | tr '\n' ' ' | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g')"
      echo "::error file=${file#"$ROOT/"}::${detail}"
    fi
    exit 1
  fi
  [[ -n "$output" ]] && printf '%s\n' "$output"
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$(basename "$file")" == *s3* ]]; then echo "::notice::S3_GATE_PASS $(basename "$file")"; fi
done

echo "Database migration replay and all SQL/concurrency verification suites passed."
