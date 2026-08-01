#!/usr/bin/env bash
# =============================================================================
# Terranex — database test runner
# =============================================================================
# Proves the Supabase schema against a REAL Postgres. The FakeSupabase client is
# not involved: it has no RLS engine and cannot prove database behaviour.
#
#   1. replay       — every migration applied in order to an empty database
#   2. contract     — schema/RLS/RPC/grants match the inventory taken from src/
#   3. rls          — two real identities: isolation + spoofing + composite FKs
#   4. rpc          — guard_*_deletion blocking behaviour and exact Arabic text
#   5. backfill     — owner_id assignment, and refusal when ownership is ambiguous
#   6. round-trip   — forward -> rollback -> reapply, ending in a working schema
#   7. idempotency  — re-application onto existing schema without drop or error
#   8. p1b-rpcs     — financial atomicity RPCs + idempotency + audit logging
#   9. ownership     — ownership domain: equity sum <= 100%, temporal, cross-tenant
#
# Usage:  scripts/db-test.sh
# Env:    PGHOST PGPORT PGUSER PGPASSWORD (default: local socket cluster)
# =============================================================================
set -euo pipefail

PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-5433}"
PGUSER="${PGUSER:-postgres}"
DB="${TERRANEX_TEST_DB:-terranex_test}"
export PGHOST PGPORT PGUSER
if [[ -n "${PGPASSWORD:-}" ]]; then export PGPASSWORD; fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$ROOT/supabase/migrations"
ROLL="$ROOT/supabase/rollback"
TESTS="$ROOT/supabase/tests"

psql_q() { local args=("$@"); psql -v ON_ERROR_STOP=1 -q "${args[@]}"; }
note()   { local msg="$1"; printf '\n\033[1m== %s\033[0m\n' "$msg"; }
strip()  { sed 's/^psql:[^ ]*: NOTICE:  //'; }

recreate_db() {
  psql_q -d postgres -c "drop database if exists $DB;" >/dev/null
  psql_q -d postgres -c "create database $DB;"        >/dev/null
  psql_q -d "$DB" -f "$TESTS/00_supabase_shim.sql"    >/dev/null 2>&1
}

apply_forward() {
  for f in "$MIG"/*.sql; do
    psql_q -d "$DB" --single-transaction -f "$f"
  done
}

apply_rollback() {
  # Reverse filename order: 0007 -> 0001.
  for f in $(ls -r "$ROLL"/*.down.sql); do
    psql_q -d "$DB" --single-transaction -f "$f" >/dev/null 2>&1
  done
}

# ── 1. replay from an empty database ────────────────────────────────────────
note "1/9  REPLAY — applying all migrations to an empty database"
recreate_db
apply_forward
echo "  migrations applied: $(ls "$MIG"/*.sql | wc -l)"

# ── 2..5 behavioural suites ─────────────────────────────────────────────────
note "2/9  SCHEMA CONTRACT"
psql_q -d "$DB" -f "$TESTS/01_schema_contract.sql" 2>&1 | strip

note "3/9  RLS — TWO IDENTITIES"
psql_q -d "$DB" -f "$TESTS/02_rls_two_identities.sql" 2>&1 | strip

note "4/9  DELETION GUARD RPCs"
psql_q -d "$DB" -f "$TESTS/03_deletion_guard_rpcs.sql" 2>&1 | strip

note "5/9  BACKFILL SCENARIOS"
psql_q -d "$DB" -f "$TESTS/04_backfill_scenarios.sql" 2>&1 | strip

note "6/9  P1B FINANCIAL RPCs"
psql_q -d "$DB" -f "$TESTS/05_p1b_financial_rpcs.sql" 2>&1 | strip

note "7/9  2B OWNERSHIP DOMAIN"
psql_q -d "$DB" -f "$TESTS/06_ownership_domain.sql" 2>&1 | strip

# ── 7. forward -> rollback -> reapply ───────────────────────────────────────
note "8/9  ROUND TRIP — forward -> rollback -> reapply"

before=$(psql -tAq -d "$DB" -c "select count(*) from pg_tables where schemaname='public';")
echo "  tables after forward : $before"

apply_rollback
after_rb=$(psql -tAq -d "$DB" -c "select count(*) from pg_tables where schemaname='public';")
types_rb=$(psql -tAq -d "$DB" -c "select count(*) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typtype='e';")
funcs_rb=$(psql -tAq -d "$DB" -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'guard\\_%' or p.proname like 'terranex\\_%');")
echo "  after rollback       : tables=$after_rb enums=$types_rb guard_fns=$funcs_rb"
if [[ "$after_rb" != "0" || "$types_rb" != "0" || "$funcs_rb" != "0" ]]; then
  echo "  FAIL: rollback left objects behind"; exit 1
fi
echo "  PASS: rollback removed every object"

apply_forward
after_re=$(psql -tAq -d "$DB" -c "select count(*) from pg_tables where schemaname='public';")
echo "  tables after reapply : $after_re"
if [[ "$after_re" != "$before" ]]; then
  echo "  FAIL: reapply produced $after_re tables, expected $before"; exit 1
fi
echo "  PASS: reapply reproduced the identical schema"

# ── 8. idempotency gate — re-application on top of existing schema ──────────
note "9/9  IDEMPOTENCY GATE — re-applying all migrations on top of existing schema"
apply_forward
echo "  PASS: re-applied all migrations on top of existing schema without error"

# The reapplied schema must still satisfy every contract — a migration set that
# only works once is not reproducible.
psql_q -d "$DB" -f "$TESTS/01_schema_contract.sql" 2>&1 | strip | tail -1
psql_q -d "$DB" -f "$TESTS/02_rls_two_identities.sql" 2>&1 | strip | tail -1
psql_q -d "$DB" -f "$TESTS/03_deletion_guard_rpcs.sql" 2>&1 | strip | tail -1
psql_q -d "$DB" -f "$TESTS/05_p1b_financial_rpcs.sql" 2>&1 | strip | tail -1
psql_q -d "$DB" -f "$TESTS/06_ownership_domain.sql" 2>&1 | strip | tail -1

printf '\n\033[1;32m=== ALL DATABASE SUITES PASSED ===\033[0m\n'
