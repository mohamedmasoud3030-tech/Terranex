#!/usr/bin/env bash
# Terranex pilot/staging activation.
#
# Safety contract:
# - Read-only inspection always runs before any write.
# - Supabase SQL uses the Management API with SUPABASE_ACCESS_TOKEN only.
# - Unrelated or untrustworthy database state fails closed.
# - Repository migrations are applied only in canonical filename order.
# - Each migration and its migration-ledger fingerprint commit atomically.
# - The migration ledger is infrastructure bookkeeping, never a domain ledger.
# - No credential value is printed.

set -uo pipefail

REF="${SUPABASE_PROJECT_REF:-nwpyeobuxzbdnnzyfyqw}"
APPLY="${APPLY_MIGRATIONS:-false}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

LEDGER_TABLE="terranex_migration_history"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note() { echo "[activation] $*"; }
warn() { echo "::warning::$*"; }
err()  { echo "::error::$*"; }

emit() {
  local accessible="$1" classification="$2" sync="$3" rls="$4" fin="$5" sec="$6"
  local summary
  summary="$(
    printf 'PROJECT_ACCESSIBLE=%s\n' "$accessible"
    printf 'PROJECT_CLASSIFICATION=%s\n' "$classification"
    printf 'MIGRATIONS_IN_SYNC=%s\n' "$sync"
    printf 'RLS_VERIFIED=%s\n' "$rls"
    printf 'FINANCIAL_CONTROLS_VERIFIED=%s\n' "$fin"
    printf 'SECURITY_VERIFIED=%s\n' "$sec"
  )"
  printf '%s\n' "$summary"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo '## Terranex pilot/staging activation'
      echo '```'
      printf '%s\n' "$summary"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "project_accessible=$accessible"
      echo "project_classification=$classification"
      echo "migrations_in_sync=$sync"
      echo "rls_verified=$rls"
      echo "financial_controls_verified=$fin"
      echo "security_verified=$sec"
    } >> "$GITHUB_OUTPUT"
  fi
}

for bin in curl jq sha256sum perl; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "required tool not found: $bin"
    emit false UNKNOWN false false false false
    exit 2
  }
done

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  err 'SUPABASE_ACCESS_TOKEN is missing. No write performed.'
  emit false UNKNOWN false false false false
  exit 2
fi

api_headers=(-H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H 'Content-Type: application/json')

runq_file() {
  local sql_file="$1" payload
  payload="$(jq -Rs '{query: .}' < "$sql_file")"
  curl --fail-with-body -sS --retry 3 --retry-all-errors --retry-delay 1 --connect-timeout 10 --max-time 45 -X POST \
    "https://api.supabase.com/v1/projects/$REF/database/query" \
    "${api_headers[@]}" \
    --data-binary "$payload" \
    2>"$TMP/query.err"
}

runq_sql() {
  printf '%s' "$1" > "$TMP/run.sql"
  runq_file "$TMP/run.sql"
}

qbool() {
  local label="$1" sql="$2" out rc val
  out="$(runq_sql "$sql")"; rc=$?
  if [[ $rc -ne 0 ]]; then
    CHECK_VAL=false
    note "  [check] $label -> ERROR"
    return
  fi
  val="$(printf '%s' "$out" | jq -r '[.. | booleans][0] // false' 2>/dev/null)"
  [[ "$val" == true ]] && CHECK_VAL=true || CHECK_VAL=false
  note "  [check] $label -> $CHECK_VAL"
}

qstr() {
  local out
  out="$(runq_sql "$1" 2>/dev/null)" || { printf ''; return; }
  printf '%s' "$out" | jq -r '[.. | strings][0] // ""' 2>/dev/null
}

sql_array() {
  sed '/^$/d' | sed "s/.*/'&'/" | paste -sd, -
}

mapfile -t MIGRATIONS < <(find supabase/migrations -maxdepth 1 -type f -name '*.sql' | sort)
if [[ "${#MIGRATIONS[@]}" -eq 0 ]]; then
  err 'No repository migrations found.'
  emit false UNKNOWN false false false false
  exit 2
fi

declare -A REPO_SHA
REPO_VERSIONS_LIST=()
for m in "${MIGRATIONS[@]}"; do
  v="$(basename "$m" .sql)"
  REPO_VERSIONS_LIST+=("$v")
  REPO_SHA["$v"]="$(sha256sum "$m" | awk '{print $1}')"
done
REPO_VERSIONS="$(printf '%s\n' "${REPO_VERSIONS_LIST[@]}" | paste -sd, -)"

CANONICAL_TABLES="$(grep -rhoiE 'create table( if not exists)?[[:space:]]+public\.[a-z0-9_]+' supabase/migrations/*.sql \
  | sed -E 's/.*public\.//I' | tr 'A-Z' 'a-z' | sort -u)"
CANONICAL_COUNT="$(printf '%s\n' "$CANONICAL_TABLES" | sed '/^$/d' | wc -l | tr -d ' ')"
CANONICAL_ARR="$(printf '%s\n' "$CANONICAL_TABLES" | sql_array)"

RLS_REQUIRED_TABLES="$(perl -0777 -ne 'while (/alter\s+table\s+public\.([a-z0-9_]+)\s+force\s+row\s+level\s+security/ig) { print lc($1), "\n"; }' supabase/migrations/*.sql | sort -u)"
RLS_REQUIRED_COUNT="$(printf '%s\n' "$RLS_REQUIRED_TABLES" | sed '/^$/d' | wc -l | tr -d ' ')"
RLS_REQUIRED_ARR="$(printf '%s\n' "$RLS_REQUIRED_TABLES" | sql_array)"

if [[ "$CANONICAL_COUNT" -le 0 || "$RLS_REQUIRED_COUNT" -le 0 ]]; then
  err 'Could not derive canonical schema/RLS contract from repository migrations.'
  emit false UNKNOWN false false false false
  exit 2
fi
note "Canonical tables=$CANONICAL_COUNT required-force-RLS tables=$RLS_REQUIRED_COUNT migrations=${#MIGRATIONS[@]}"

# 1. Project accessibility and safe metadata.
note "Verifying access to project ref: $REF"
PROJECT_JSON="$(curl --fail-with-body -sS --retry 3 --retry-all-errors --retry-delay 1 --connect-timeout 10 --max-time 45 \
  "https://api.supabase.com/v1/projects/$REF" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" 2>"$TMP/project.err")"
if [[ $? -ne 0 || -z "$PROJECT_JSON" ]]; then
  err 'Supabase project is inaccessible with the configured token. No write performed.'
  emit false UNKNOWN false false false false
  exit 1
fi
note "  name=$(printf '%s' "$PROJECT_JSON" | jq -r '.name // ""')"
note "  region=$(printf '%s' "$PROJECT_JSON" | jq -r '.region // ""') status=$(printf '%s' "$PROJECT_JSON" | jq -r '.status // ""')"
note "  db_version=$(printf '%s' "$PROJECT_JSON" | jq -r '.database.version // ""')"

refresh_classification() {
  qbool present_is_zero "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR])) = 0);"
  PRESENT_ZERO="$CHECK_VAL"

  qbool present_is_all "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR])) = $CANONICAL_COUNT);"
  PRESENT_ALL="$CHECK_VAL"

  qbool has_unrelated "select to_jsonb(exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname <> all(array[$CANONICAL_ARR]) and c.relname <> '$LEDGER_TABLE'));"
  HAS_UNRELATED="$CHECK_VAL"
  if [[ "$HAS_UNRELATED" == true ]]; then
    warn "unrelated public tables present: $(qstr "select coalesce(string_agg(c.relname, ', ' order by c.relname), '') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname <> all(array[$CANONICAL_ARR]) and c.relname <> '$LEDGER_TABLE';")"
  fi

  qbool anchor_s6_evaluate_gate "select to_jsonb(to_regprocedure('public.s6_evaluate_gate(uuid,uuid,uuid,text)') is not null);"
  ANCHOR1="$CHECK_VAL"
  qbool anchor_close_serialization "select to_jsonb((select count(*) from pg_trigger t where t.tgname in ('a_s6_close_serialization_batch_lock','a_s6_close_serialization_line_lock') and not t.tgisinternal) = 2);"
  ANCHOR2="$CHECK_VAL"
  qbool anchor_audit_append_only "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='audit_events_append_only' and not t.tgisinternal));"
  ANCHOR3="$CHECK_VAL"

  if [[ "$HAS_UNRELATED" == true ]]; then
    CLASSIFICATION=UNRELATED
  elif [[ "$PRESENT_ZERO" == true ]]; then
    CLASSIFICATION=EMPTY
  elif [[ "$PRESENT_ALL" == true && "$ANCHOR1" == true && "$ANCHOR2" == true && "$ANCHOR3" == true ]]; then
    CLASSIFICATION=TERRANEX
  else
    CLASSIFICATION=PARTIAL_TERRANEX
  fi
  note "Classification: $CLASSIFICATION"
}

verify_controls() {
  qbool rls_required_enabled_and_forced "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$RLS_REQUIRED_ARR]) and c.relrowsecurity and c.relforcerowsecurity) = $RLS_REQUIRED_COUNT);"
  RLS_TABLES_OK="$CHECK_VAL"
  qbool rls_core_predicate "select to_jsonb(to_regprocedure('public.is_active_member(uuid)') is not null);"
  RLS_PREDICATE="$CHECK_VAL"
  RLS_OK=false
  [[ "$RLS_TABLES_OK" == true && "$RLS_PREDICATE" == true ]] && RLS_OK=true

  qbool secdef_search_path_boundary "select to_jsonb((select count(*) from pg_proc p where p.prosecdef and p.pronamespace='public'::regnamespace and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) pc where pc like 'search_path=pg_catalog,public'))) = 0);"
  SECDEF_OK="$CHECK_VAL"

  qbool s6_evaluate_gate_authorization "select to_jsonb(to_regprocedure('public.s6_evaluate_gate(uuid,uuid,uuid,text)') is not null and not has_function_privilege('anon','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE') and not has_function_privilege('public','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE') and has_function_privilege('authenticated','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE'));"
  GATE_AUTH_OK="$CHECK_VAL"

  qbool period_close_posting_serialization "select to_jsonb((select count(*) from pg_trigger t where t.tgname in ('a_s6_close_serialization_batch_lock','a_s6_close_serialization_line_lock') and not t.tgisinternal) = 2);"
  CLOSE_SERIAL_OK="$CHECK_VAL"
  qbool audit_events_append_only "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='audit_events_append_only' and not t.tgisinternal));"
  AUDIT_OK="$CHECK_VAL"
  qbool journal_balanced_guard "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='journal_lines_balance_guard' and not t.tgisinternal));"
  JOURNAL_OK="$CHECK_VAL"

  qbool s7_opening_import_controls "select to_jsonb(to_regclass('public.s7_opening_imports') is not null and to_regclass('public.s7_opening_mapping_codes') is not null and exists (select 1 from pg_trigger t where t.tgname='s7_opening_mapping_codes_locked' and not t.tgisinternal));"
  S7_IMPORT_OK="$CHECK_VAL"
  if [[ "$S7_IMPORT_OK" == true ]]; then
    qbool s7_mapping_codes_registry_locked_six "select to_jsonb((select count(*) from public.s7_opening_mapping_codes) = 6);"
    S7_IMPORT_OK="$CHECK_VAL"
  fi

  qbool s7_reconciliation_controls "select to_jsonb(to_regclass('public.s7_reconciliation_checkpoints') is not null and exists (select 1 from pg_constraint c where c.conrelid='public.s7_reconciliation_checkpoints'::regclass and pg_get_constraintdef(c.oid) like '%PROJECT_CASH%' and pg_get_constraintdef(c.oid) like '%INVESTOR_STATEMENT_TOTAL%'));"
  RECON_OK="$CHECK_VAL"

  FINANCIAL_OK=false
  [[ "$GATE_AUTH_OK" == true && "$CLOSE_SERIAL_OK" == true && "$AUDIT_OK" == true && "$JOURNAL_OK" == true && "$S7_IMPORT_OK" == true && "$RECON_OK" == true ]] && FINANCIAL_OK=true
}

LEDGER_EXISTS=false
LEDGER_SCHEMA_OK=false
LEDGER_PREFIX_OK=false
LEDGER_FULL_SYNC=false
LEDGER_COUNT=0
LEDGER_ROWS=()

ledger_refresh() {
  qbool ledger_exists "select to_jsonb(to_regclass('public.$LEDGER_TABLE') is not null);"
  LEDGER_EXISTS="$CHECK_VAL"
  LEDGER_SCHEMA_OK=false
  LEDGER_PREFIX_OK=false
  LEDGER_FULL_SYNC=false
  LEDGER_COUNT=0
  LEDGER_ROWS=()
  [[ "$LEDGER_EXISTS" == true ]] || return

  qbool ledger_schema "select to_jsonb((select count(*) from information_schema.columns where table_schema='public' and table_name='$LEDGER_TABLE' and column_name in ('version','sha256','applied_at')) = 3 and not exists (select 1 from information_schema.columns where table_schema='public' and table_name='$LEDGER_TABLE' and column_name in ('version','sha256') and is_nullable='YES'));"
  LEDGER_SCHEMA_OK="$CHECK_VAL"
  [[ "$LEDGER_SCHEMA_OK" == true ]] || return

  local out i row v sha expected_v
  out="$(runq_sql "select version, sha256 from public.$LEDGER_TABLE order by version;")" || return
  mapfile -t LEDGER_ROWS < <(printf '%s' "$out" | jq -r '.[] | [.version,.sha256] | @tsv')
  LEDGER_COUNT="${#LEDGER_ROWS[@]}"
  LEDGER_PREFIX_OK=true
  if [[ "$LEDGER_COUNT" -gt "${#MIGRATIONS[@]}" ]]; then
    LEDGER_PREFIX_OK=false
  else
    for ((i=0; i<LEDGER_COUNT; i++)); do
      row="${LEDGER_ROWS[$i]}"
      IFS=$'\t' read -r v sha <<< "$row"
      expected_v="${REPO_VERSIONS_LIST[$i]}"
      if [[ "$v" != "$expected_v" || "$sha" != "${REPO_SHA[$expected_v]}" ]]; then
        LEDGER_PREFIX_OK=false
        break
      fi
    done
  fi
  if [[ "$LEDGER_PREFIX_OK" == true && "$LEDGER_COUNT" -eq "${#MIGRATIONS[@]}" ]]; then
    LEDGER_FULL_SYNC=true
  fi
  note "Ledger: rows=$LEDGER_COUNT schema_ok=$LEDGER_SCHEMA_OK prefix_ok=$LEDGER_PREFIX_OK full_sync=$LEDGER_FULL_SYNC"
}

create_ledger() {
  local sql
  sql="begin;
  create table if not exists public.$LEDGER_TABLE (
    version text primary key,
    sha256 text not null,
    applied_at timestamptz not null default now()
  );
  alter table public.$LEDGER_TABLE enable row level security;
  alter table public.$LEDGER_TABLE force row level security;
  revoke all on table public.$LEDGER_TABLE from public, anon, authenticated;
  commit;"
  runq_sql "$sql" >/dev/null
}

apply_missing_migrations() {
  local i m v sha n
  for ((i=LEDGER_COUNT; i<${#MIGRATIONS[@]}; i++)); do
    m="${MIGRATIONS[$i]}"
    v="${REPO_VERSIONS_LIST[$i]}"
    sha="${REPO_SHA[$v]}"
    n="$(basename "$m")"
    note "  applying $n"
    {
      echo 'begin;'
      cat "$m"
      printf "\ninsert into public.%s(version,sha256) values ('%s','%s');\n" "$LEDGER_TABLE" "$v" "$sha"
      echo 'commit;'
    } > "$TMP/apply.sql"
    if ! runq_file "$TMP/apply.sql" >/dev/null; then
      err "Migration $n failed; transaction rolled back, including its ledger record."
      return 1
    fi
  done
  return 0
}

refresh_classification
verify_controls
ledger_refresh
MIGRATIONS_IN_SYNC="$LEDGER_FULL_SYNC"
APPLY_FAILED=false

if [[ "$APPLY" == true ]]; then
  if [[ "$CLASSIFICATION" == UNRELATED ]]; then
    err 'FAIL CLOSED: unrelated application data detected. No migration applied.'
    APPLY_FAILED=true
  elif [[ "$LEDGER_EXISTS" == true && "$LEDGER_SCHEMA_OK" != true ]]; then
    err 'FAIL CLOSED: migration ledger schema is incompatible. No migration applied.'
    APPLY_FAILED=true
  elif [[ "$CLASSIFICATION" == TERRANEX ]]; then
    if [[ "$LEDGER_FULL_SYNC" == true ]]; then
      note 'Schema and migration ledger already synchronized; no write required.'
    else
      err 'FAIL CLOSED: complete Terranex schema with an incomplete or mismatched ledger requires explicit reconciliation; no migration replay attempted.'
      APPLY_FAILED=true
    fi
  elif [[ "$CLASSIFICATION" == EMPTY ]]; then
    if [[ "$LEDGER_EXISTS" == false ]]; then
      note 'Creating canonical deployment ledger.'
      if ! create_ledger; then
        err 'Could not create deployment ledger.'
        APPLY_FAILED=true
      fi
      ledger_refresh
    fi
    if [[ "$APPLY_FAILED" == false && "$LEDGER_PREFIX_OK" == true && "$LEDGER_COUNT" -eq 0 ]]; then
      note 'Applying all canonical migrations atomically with ledger fingerprints.'
      apply_missing_migrations || APPLY_FAILED=true
    elif [[ "$APPLY_FAILED" == false ]]; then
      err 'FAIL CLOSED: EMPTY classification has a non-empty or untrusted ledger.'
      APPLY_FAILED=true
    fi
  elif [[ "$CLASSIFICATION" == PARTIAL_TERRANEX ]]; then
    if [[ "$LEDGER_EXISTS" != true || "$LEDGER_SCHEMA_OK" != true || "$LEDGER_PREFIX_OK" != true ]]; then
      err 'FAIL CLOSED: partial schema does not have a trusted checksum-verified migration prefix.'
      APPLY_FAILED=true
    else
      note 'Applying only migrations after the checksum-verified ledger prefix.'
      apply_missing_migrations || APPLY_FAILED=true
    fi
  fi
else
  note 'Inspection-only mode (APPLY_MIGRATIONS=false). No write performed.'
fi

if [[ "$APPLY" == true && "$APPLY_FAILED" == false ]]; then
  ledger_refresh
  refresh_classification
  verify_controls
fi
MIGRATIONS_IN_SYNC="$LEDGER_FULL_SYNC"

# Security advisors are read through the same Management API used for SQL.
ADVISORS_RC=1
note 'Running Supabase security advisors through Management API ...'
if curl --fail-with-body -sS --retry 3 --retry-all-errors --retry-delay 1 --connect-timeout 10 --max-time 45 \
  "https://api.supabase.com/v1/projects/$REF/advisors/security" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -o "$TMP/advisors.json"; then
  ADVISOR_ERROR_COUNT="$(jq '[.lints[]? | select((((.level // .severity // "") | ascii_downcase)) == "error")] | length' "$TMP/advisors.json" 2>/dev/null || echo -1)"
  if [[ "$ADVISOR_ERROR_COUNT" == 0 ]]; then
    ADVISORS_RC=0
    note '  security advisors: no error-level findings'
  else
    warn "security advisors report $ADVISOR_ERROR_COUNT error-level finding(s)"
  fi
else
  warn 'security advisor Management API request failed'
fi

SECURITY_OK=false
[[ "$RLS_OK" == true && "$SECDEF_OK" == true && "$GATE_AUTH_OK" == true && "$AUDIT_OK" == true && "$ADVISORS_RC" -eq 0 ]] && SECURITY_OK=true

note "rls_ok=$RLS_OK financial_ok=$FINANCIAL_OK security_ok=$SECURITY_OK migrations_in_sync=$MIGRATIONS_IN_SYNC"
emit true "$CLASSIFICATION" "$MIGRATIONS_IN_SYNC" "$RLS_OK" "$FINANCIAL_OK" "$SECURITY_OK"

if [[ "$CLASSIFICATION" == UNRELATED || "$APPLY_FAILED" == true ]]; then
  exit 1
fi
exit 0
