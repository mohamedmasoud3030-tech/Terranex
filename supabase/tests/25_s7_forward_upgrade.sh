#!/usr/bin/env bash
set -euo pipefail

# GF-009 / S7 — forward-upgrade verification from the exact merged S5/S6
# boundary. Replay every migration up to and including the merged S5 family,
# assert the boundary is genuine, then apply only the S7 family and assert
# that every prior primitive survived and every S7 primitive exists.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_s7_upgrade"
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

# Exact merged S5/S6 boundary: every migration except the S7 family.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    202608120002*.sql|20260813*.sql|20260814*.sql|20260815*.sql|20260816*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

BEFORE="$(psql_cmd "$UPGRADE_DB" "select (
  to_regclass('public.s5_allocation_runs') is not null
  and to_regclass('public.s5_distributions') is not null
  and to_regclass('public.close_run_snapshots') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regclass('public.s7_opening_imports') is null
  and to_regclass('public.s7_reconciliation_checkpoints') is null
  and to_regprocedure('public.s5_approve_allocation(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.s6_approve_close_run(uuid,uuid,text)') is not null
)::text")"
if [[ "$BEFORE" != 'true' ]]; then
  echo 'ERROR: S7 forward-upgrade fixture is not the merged S5/S6 boundary.' >&2
  exit 1
fi

# The pre-S7 boundary must not already accept the S7 journal source.
SOURCE_BEFORE="$(psql_cmd "$UPGRADE_DB" "select pg_get_constraintdef(oid) like '%S7_OPENING_IMPORT%'
  from pg_constraint where conname='journal_batches_source_type_check'")"
if [[ "$SOURCE_BEFORE" != 'f' ]]; then
  echo 'ERROR: the pre-S7 boundary unexpectedly already knows the S7 journal source.' >&2
  exit 1
fi

s7_migrations=("$ROOT"/supabase/migrations/202608120002*.sql)
if [[ ! -e "${s7_migrations[0]}" ]]; then
  echo 'ERROR: no S7 migration family found.' >&2
  exit 1
fi
for file in "${s7_migrations[@]}"; do
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER="$(psql_cmd "$UPGRADE_DB" "select (
  to_regclass('public.s7_opening_mapping_codes') is not null
  and to_regclass('public.s7_opening_imports') is not null
  and to_regclass('public.s7_opening_import_rows') is not null
  and to_regclass('public.s7_reconciliation_checkpoints') is not null
  and to_regclass('public.s7_reconciliation_exceptions') is not null
  and to_regclass('public.s7_uat_tasks') is not null
  and to_regclass('public.s7_pilot_rehearsals') is not null
  and to_regprocedure('public.s7_stage_opening_import(uuid,uuid,text,text,text,text[],uuid[],uuid[],text[],text[],text[],text,text,text)') is not null
  and to_regprocedure('public.s7_validate_opening_import(uuid,uuid,text)') is not null
  and to_regprocedure('public.s7_review_opening_import(uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s7_approve_opening_import(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.s7_reject_opening_import(uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s7_record_reconciliation_checkpoint(uuid,uuid,text,date,bigint,text,text,uuid,text,text)') is not null
  and to_regprocedure('public.s7_resolve_reconciliation_exception(uuid,uuid,text,text,text)') is not null
  and to_regprocedure('public.s7_sign_off_reconciliation_checkpoint(uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s7_set_membership_status(uuid,uuid,text,text,text)') is not null
  and to_regprocedure('public.s7_register_uat_task(uuid,uuid,text,text,text,text)') is not null
  and to_regprocedure('public.s7_accept_uat_task(uuid,uuid,text,text)') is not null
  and to_regprocedure('public.s7_record_pilot_rehearsal(uuid,uuid,text,text,text,jsonb,text)') is not null
  -- Every earlier slice must survive untouched.
  and to_regclass('public.s5_allocation_runs') is not null
  and to_regclass('public.s5_distributions') is not null
  and to_regclass('public.close_run_snapshots') is not null
  and to_regclass('public.property_sale_recognitions') is not null
  and to_regprocedure('public.s5_approve_allocation(uuid,uuid,date,text)') is not null
  and to_regprocedure('public.s5_pay_distribution(uuid,uuid,uuid,bigint,date,text,text)') is not null
  and to_regprocedure('public.s6_approve_close_run(uuid,uuid,text)') is not null
  and to_regprocedure('public.recognize_property_sale(uuid,uuid,date,text)') is not null
)::text")"
if [[ "$AFTER" != 'true' ]]; then
  echo 'ERROR: S7 forward upgrade did not preserve S0-S6 or add every S7 primitive.' >&2
  exit 1
fi

# The S7 journal source is additive: every earlier source must still be legal.
SOURCE_AFTER="$(psql_cmd "$UPGRADE_DB" "select (
  pg_get_constraintdef(oid) like '%S7_OPENING_IMPORT%'
  and pg_get_constraintdef(oid) like '%S5_ALLOCATION%'
  and pg_get_constraintdef(oid) like '%S5_DISTRIBUTION_APPROVAL%'
  and pg_get_constraintdef(oid) like '%S5_DISTRIBUTION_PAYMENT%'
  and pg_get_constraintdef(oid) like '%PROPERTY_SALE_RECOGNITION%'
  and pg_get_constraintdef(oid) like '%PROPERTY_SALE_COLLECTION%'
  and pg_get_constraintdef(oid) like '%CONTRIBUTION_CASH_ATTRIBUTION%'
  and pg_get_constraintdef(oid) like '%COST_OBLIGATION%'
  and pg_get_constraintdef(oid) like '%PAYMENT%'
  and pg_get_constraintdef(oid) like '%REVERSAL%'
)::text from pg_constraint where conname='journal_batches_source_type_check'")"
if [[ "$SOURCE_AFTER" != 'true' ]]; then
  echo 'ERROR: the S7 journal source extension is not strictly additive.' >&2
  exit 1
fi

# S7 adds no semantic account role: the locked registry must be unchanged.
ROLE_COUNT="$(psql_cmd "$UPGRADE_DB" "select count(*) from public.semantic_accounts")"
if [[ "$ROLE_COUNT" != '11' ]]; then
  echo "ERROR: S7 changed the locked semantic account registry (roles=$ROLE_COUNT, expected 11)." >&2
  exit 1
fi

# Default-deny RLS must be forced on every new tenant table.
RLS_OK="$(psql_cmd "$UPGRADE_DB" "select bool_and(relrowsecurity and relforcerowsecurity)::text
  from pg_class where relname in (
    's7_opening_imports','s7_opening_import_rows','s7_reconciliation_checkpoints',
    's7_reconciliation_exceptions','s7_uat_tasks','s7_pilot_rehearsals')")"
if [[ "$RLS_OK" != 'true' ]]; then
  echo 'ERROR: an S7 tenant table is missing forced default-deny RLS.' >&2
  exit 1
fi

# Every S7 SECURITY DEFINER function must pin a safe search_path.
UNSAFE="$(psql_cmd "$UPGRADE_DB" "select count(*) from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
  where p.proname like 's7\\_%' and p.prosecdef
    and not coalesce(
      replace(array_to_string(p.proconfig,','), ' ', '') like '%search_path=pg_catalog,public%',
      false)")"
if [[ "$UNSAFE" != '0' ]]; then
  echo "ERROR: $UNSAFE S7 SECURITY DEFINER function(s) do not pin a safe search_path." >&2
  exit 1
fi

echo 'S7 forward upgrade from merged S5/S6 PASS'
