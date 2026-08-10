#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:=/tmp}"; : "${PGPORT:=5433}"; : "${PGUSER:=postgres}"; export PGHOST PGPORT PGUSER
DB="${TERRANEX_TEST_DB:=terranex_s0_test}"; root="$(cd "$(dirname "$0")/.." && pwd)"
psql -v ON_ERROR_STOP=1 -d postgres -c "drop database if exists $DB"; psql -v ON_ERROR_STOP=1 -d postgres -c "create database $DB"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$root/supabase/tests/00_supabase_shim.sql"
for f in "$root"/supabase/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -d "$DB" -f "$f"; done
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$root/supabase/tests/01_s0_isolation.sql"
echo 'Migration replay and S0 isolation tests passed.'
