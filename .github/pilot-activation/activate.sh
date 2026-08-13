#!/usr/bin/env bash
#
# Terranex pilot/staging activation — read-only inspection first, optional
# migration application gated behind APPLY_MIGRATIONS=true.
#
# Safety contract:
#   * Never prints SUPABASE_ACCESS_TOKEN, database passwords, service-role
#     keys, or publishable-key values. Only names/states are logged.
#   * Read-only inspection ALWAYS runs first and classifies the project.
#   * Fails closed (no write) when unrelated application data is detected,
#     when the migration history cannot be trusted, or when apply is not
#     explicitly requested.
#   * Applies only missing repository migrations, in canonical (filename)
#     order, via the Supabase Management API query path (access token only).
#   * Never edits already-applied migrations and never reconstructs schema.
#
# Produces a SAFE summary (exactly six lines, no secrets) on stdout and in
# the GitHub step summary.

set -uo pipefail

REF="${SUPABASE_PROJECT_REF:-nwpyeobuxzbdnnzyfyqw}"
APPLY="${APPLY_MIGRATIONS:-false}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

LEDGER_TABLE="terranex_migration_history"

note() { echo "[activation] $*"; }
warn() { echo "::warning::$*"; }
err()  { echo "::error::$*"; }

# ---------------------------------------------------------------------------
# SAFE summary emitter — exactly six lines, no credentials.
# ---------------------------------------------------------------------------
emit() {
  local accessible="$1" classification="$2" sync="$3" rls="$4" fin="$5" sec="$6"
  SUMMARY="$(
    printf 'PROJECT_ACCESSIBLE=%s\n' "$accessible"
    printf 'PROJECT_CLASSIFICATION=%s\n' "$classification"
    printf 'MIGRATIONS_IN_SYNC=%s\n' "$sync"
    printf 'RLS_VERIFIED=%s\n' "$rls"
    printf 'FINANCIAL_CONTROLS_VERIFIED=%s\n' "$fin"
    printf 'SECURITY_VERIFIED=%s\n' "$sec"
  )"
  printf '%s\n' "$SUMMARY"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## Terranex pilot/staging activation"
      echo '```'
      printf '%s\n' "$SUMMARY"
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

# ---------------------------------------------------------------------------
# CLI helpers
# ---------------------------------------------------------------------------
for bin in supabase jq sha256sum; do
  command -v "$bin" >/dev/null 2>&1 || { err "required tool not found: $bin"; emit false UNKNOWN false false false false; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# runq_file <sqlfile> -> stdout of `supabase db query` (Management API path).
runq_file() {
  supabase db query --project-ref "$REF" --output-format json -f "$1" 2>"$TMP/q.err"
}

# runq_sql <text> -> stdout; sql written to a temp file first.
runq_sql() {
  printf '%s' "$1" > "$TMP/run.sql"
  runq_file "$TMP/run.sql"
}

# qbool <label> <sql> -> sets CHECK_VAL to "true"/"false" (grep on 'true',
# which is robust to both JSON and plain-text CLI output).
qbool() {
  local label="$1" sql="$2" out rc
  out="$(runq_sql "$sql")"; rc=$?
  if [[ $rc -ne 0 ]]; then
    CHECK_VAL=false
    note "  [check] $label -> ERROR (query failed)"
    return
  fi
  if printf '%s' "$out" | grep -q 'true'; then CHECK_VAL=true; else CHECK_VAL=false; fi
  note "  [check] $label -> $CHECK_VAL"
}

# qstr <sql> -> best-effort joined string (cosmetic logging only; never
# used for a safety decision). Empty on failure.
qstr() {
  local sql="$1" out
  out="$(runq_sql "$sql" 2>/dev/null)"
  printf '%s' "$out" | jq -r '[.. | strings][0] // ""' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Canonical Terranex tables (derived from repository migrations, not hardcoded).
# ---------------------------------------------------------------------------
CANONICAL_TABLES="$(grep -rhoiE "create table( if not exists)?[[:space:]]+public\.[a-z0-9_]+" \
  supabase/migrations/*.sql | sed -E 's/.*public\.//I' | tr 'A-Z' 'a-z' | sort -u)"
CANONICAL_COUNT="$(printf '%s\n' "$CANONICAL_TABLES" | wc -l | tr -d ' ')"
CANONICAL_ARR="$(printf '%s\n' "$CANONICAL_TABLES" | sed "s/.*/'&'/" | paste -sd, -)"
note "Canonical Terranex table count (from migrations): $CANONICAL_COUNT"
[[ "$CANONICAL_COUNT" -gt 0 ]] || { err "Could not derive canonical table list."; emit false UNKNOWN false false false false; exit 2; }

MIGRATIONS=( $(ls supabase/migrations/*.sql | sort) )
REPO_VERSIONS="$(for m in "${MIGRATIONS[@]}"; do basename "$m" .sql; done | paste -sd, -)"

# ---------------------------------------------------------------------------
# 1. Accessibility + metadata (read-only)
# ---------------------------------------------------------------------------
note "Verifying access to project ref: $REF"
LIST_JSON="$(supabase projects list --output-format json 2>"$TMP/list.err")"
if [[ $? -ne 0 ]]; then
  err "Could not list Supabase projects (token invalid or API unreachable). No write performed."
  emit false UNKNOWN false false false false
  exit 1
fi
PROJ="$(printf '%s' "$LIST_JSON" | jq -c --arg ref "$REF" '[.[] | select(.id == $ref)][0]')"
if [[ -z "$PROJ" || "$PROJ" == "null" ]]; then
  err "Project ref $REF is not accessible with the provided token. No write performed."
  emit false UNKNOWN false false false false
  exit 1
fi
note "  metadata (names/state only): name=$(printf '%s' "$PROJ" | jq -r '.name // ""')"
note "  region=$(printf '%s' "$PROJ" | jq -r '.region // ""') status=$(printf '%s' "$PROJ" | jq -r '.status // ""')"
note "  db_version=$(printf '%s' "$PROJ" | jq -r '.database.version // ""')"

# ---------------------------------------------------------------------------
# 2. Read-only classification (boolean-only decisions)
# ---------------------------------------------------------------------------
qbool "present_is_zero" "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR])) = 0);"
PRESENT_ZERO="$CHECK_VAL"

qbool "present_is_all" "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR])) = $CANONICAL_COUNT);"
PRESENT_ALL="$CHECK_VAL"

qbool "has_unrelated" "select to_jsonb(exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname <> all(array[$CANONICAL_ARR]) and c.relname <> '$LEDGER_TABLE'));"
HAS_UNRELATED="$CHECK_VAL"
if [[ "$HAS_UNRELATED" == true ]]; then
  warn "unrelated public tables present: $(qstr "select coalesce(string_agg(c.relname, ', ' order by c.relname), '') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname <> all(array[$CANONICAL_ARR]) and c.relname <> '$LEDGER_TABLE';")"
fi

qbool "rls_all_enabled_and_forced" "select to_jsonb((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR]) and c.relrowsecurity) = $CANONICAL_COUNT and (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname = any(array[$CANONICAL_ARR]) and c.relforcerowsecurity) = $CANONICAL_COUNT);"
RLS_ALL="$CHECK_VAL"

qbool "latest_anchor_s6_evaluate_gate" "select to_jsonb(to_regprocedure('public.s6_evaluate_gate(uuid,uuid,uuid,text)') is not null);"
ANCHOR1="$CHECK_VAL"
qbool "latest_anchor_close_serialization" "select to_jsonb((select count(*) from pg_trigger t where t.tgname in ('a_s6_close_serialization_batch_lock','a_s6_close_serialization_line_lock') and not t.tgisinternal) = 2);"
ANCHOR2="$CHECK_VAL"
qbool "latest_anchor_audit_append_only" "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='audit_events_append_only' and not t.tgisinternal));"
ANCHOR3="$CHECK_VAL"

if [[ "$HAS_UNRELATED" == true ]]; then
  CLASSIFICATION="UNRELATED"
elif [[ "$PRESENT_ZERO" == true ]]; then
  CLASSIFICATION="EMPTY"
elif [[ "$PRESENT_ALL" == true && "$ANCHOR1" == true && "$ANCHOR2" == true && "$ANCHOR3" == true ]]; then
  CLASSIFICATION="TERRANEX"
else
  CLASSIFICATION="PARTIAL_TERRANEX"
fi
note "Classification: $CLASSIFICATION"

# ---------------------------------------------------------------------------
# 3. Read-only verification
# ---------------------------------------------------------------------------
qbool "rls_core_predicate" "select to_jsonb(to_regprocedure('public.is_active_member(uuid)') is not null);"
RLS_PREDICATE="$CHECK_VAL"
RLS_OK=false
[[ "$RLS_ALL" == true && "$RLS_PREDICATE" == true ]] && RLS_OK=true

# Scope to Terranex's own public schema so Supabase's internal definer
# functions (other schemas) cannot produce a false negative.
qbool "secdef_search_path_boundary" "select to_jsonb(count(*) = 0 from pg_proc p where p.prosecdef and p.pronamespace = 'public'::regnamespace and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) pc where pc like 'search_path=pg_catalog,public')));"
SECDEF_OK="$CHECK_VAL"

qbool "s6_evaluate_gate_authorization" "select to_jsonb(to_regprocedure('public.s6_evaluate_gate(uuid,uuid,uuid,text)') is not null and not has_function_privilege('anon','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE') and not has_function_privilege('public','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE') and has_function_privilege('authenticated','public.s6_evaluate_gate(uuid,uuid,uuid,text)','EXECUTE'));"
GATE_AUTH_OK="$CHECK_VAL"

qbool "period_close_posting_serialization" "select to_jsonb((select count(*) from pg_trigger t where t.tgname in ('a_s6_close_serialization_batch_lock','a_s6_close_serialization_line_lock') and not t.tgisinternal) = 2);"
CLOSE_SERIAL_OK="$CHECK_VAL"

qbool "audit_events_append_only" "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='audit_events_append_only' and not t.tgisinternal));"
AUDIT_OK="$CHECK_VAL"

qbool "journal_balanced_guard" "select to_jsonb(exists (select 1 from pg_trigger t where t.tgname='journal_lines_balance_guard' and not t.tgisinternal));"
JOURNAL_OK="$CHECK_VAL"

qbool "s7_opening_import_controls" "select to_jsonb(to_regclass('public.s7_opening_imports') is not null and to_regclass('public.s7_opening_mapping_codes') is not null and exists (select 1 from pg_trigger t where t.tgname='s7_opening_mapping_codes_locked' and not t.tgisinternal));"
S7_IMPORT_OK="$CHECK_VAL"
if [[ "$S7_IMPORT_OK" == true ]]; then
  qbool "s7_mapping_codes_registry_locked_six" "select to_jsonb((select count(*) from public.s7_opening_mapping_codes) = 6);"
  S7_IMPORT_OK="$CHECK_VAL"
fi

qbool "s7_reconciliation_controls" "select to_jsonb(to_regclass('public.s7_reconciliation_checkpoints') is not null and exists (select 1 from pg_constraint c where c.conrelid = 'public.s7_reconciliation_checkpoints'::regclass and pg_get_constraintdef(c.oid) like '%PROJECT_CASH%' and pg_get_constraintdef(c.oid) like '%INVESTOR_STATEMENT_TOTAL%'));"
RECON_OK="$CHECK_VAL"

# ---------------------------------------------------------------------------
# 4. Activation ledger (deployment bookkeeping only — NOT a domain ledger).
#    It records which repository migrations this workflow applied so that
#    "apply only missing, in order" is deterministic without re-running
#    non-idempotent migrations.
# ---------------------------------------------------------------------------
qbool "ledger_exists" "select to_jsonb(to_regclass('public.$LEDGER_TABLE') is not null);"
LEDGER_EXISTS="$CHECK_VAL"

# Ledger is absent until this workflow creates it; gate direct table access
# on existence to avoid Postgres parse-time "relation does not exist".
LEDGER_EQ_REPO=false
if [[ "$LEDGER_EXISTS" == true ]]; then
  qbool "ledger_eq_repo" "select to_jsonb(coalesce((select string_agg(version, ',' order by version) from public.$LEDGER_TABLE), '') = '$REPO_VERSIONS');"
  LEDGER_EQ_REPO="$CHECK_VAL"
fi

MIGRATIONS_IN_SYNC=false
[[ "$LEDGER_EQ_REPO" == true ]] && MIGRATIONS_IN_SYNC=true

# ---------------------------------------------------------------------------
# 5. Optional apply (gated by APPLY_MIGRATIONS=true). Never on UNRELATED.
# ---------------------------------------------------------------------------
APPLY_ALLOWED=false
APPLY_MODE=""

if [[ "$APPLY" == "true" ]]; then
  if [[ "$CLASSIFICATION" == "UNRELATED" ]]; then
    err "FAIL CLOSED: unrelated application data detected; no migration applied."
  elif [[ "$CLASSIFICATION" == "EMPTY" ]]; then
    note "EMPTY project; will apply all migrations in canonical order."
    APPLY_ALLOWED=true; APPLY_MODE="apply_all"
  elif [[ "$CLASSIFICATION" == "TERRANEX" ]]; then
    if [[ "$LEDGER_EQ_REPO" == true ]]; then
      note "TERRANEX schema already complete and ledger in sync; nothing to apply."
    else
      note "TERRANEX schema complete but ledger out of sync; reconciling ledger (records only, no re-execution)."
      APPLY_ALLOWED=true; APPLY_MODE="backfill"
    fi
  elif [[ "$CLASSIFICATION" == "PARTIAL_TERRANEX" ]]; then
    if [[ "$LEDGER_EXISTS" == false ]]; then
      err "FAIL CLOSED: partial Terranex schema with no activation ledger. Cannot determine a safe migration set; manual review required (docs/runbooks/FAILED_DEPLOYMENT_OR_MIGRATION.md). No migration applied."
    elif [[ "$LEDGER_EQ_REPO" == true ]]; then
      err "FAIL CLOSED: ledger claims all migrations applied but live schema is partial — inconsistent. Manual review required. No migration applied."
    else
      # Trusted only if the applied ledger versions are a prefix of the repo list.
      qbool "ledger_is_prefix" "select to_jsonb(not exists (select 1 from (select unnest(string_to_array('$REPO_VERSIONS', ',')) as v) r where r.v not in (select version from public.$LEDGER_TABLE) and exists (select 1 from public.$LEDGER_TABLE l where l.version > r.v)) and not exists (select 1 from public.$LEDGER_TABLE l where l.version <> all (select unnest(string_to_array('$REPO_VERSIONS', ',')))));"
      if [[ "$CHECK_VAL" == true ]]; then
        note "PARTIAL_TERRANEX with trusted history prefix; applying only missing migrations."
        APPLY_ALLOWED=true; APPLY_MODE="apply_missing"
      else
        err "FAIL CLOSED: partial Terranex schema with a non-prefix migration history. Manual review required. No migration applied."
      fi
    fi
  fi
else
  note "Inspection-only mode (APPLY_MIGRATIONS=false). No write performed."
fi

if [[ "$APPLY_ALLOWED" == true ]]; then
  if [[ "$LEDGER_EXISTS" == false ]]; then
    note "Creating activation migration ledger (infrastructure, additive, non-domain)."
    runq_sql "create table if not exists public.$LEDGER_TABLE (version text primary key, name text not null, checksum text not null, applied_at timestamptz not null default now()); alter table public.$LEDGER_TABLE enable row level security; alter table public.$LEDGER_TABLE force row level security;" >/dev/null \
      || { err "Could not create activation ledger. Fail-closed."; APPLY_ALLOWED=false; }
  fi
fi

if [[ "$APPLY_ALLOWED" == true && "$APPLY_MODE" == "backfill" ]]; then
  for m in "${MIGRATIONS[@]}"; do
    v="$(basename "$m" .sql)"; n="$(basename "$m")"; cs="$(sha256sum "$m" | cut -d' ' -f1)"
    runq_sql "insert into public.$LEDGER_TABLE(version,name,checksum) values ('$v','$n','$cs') on conflict (version) do nothing;" >/dev/null
  done
  note "Ledger reconciled for complete Terranex schema."
fi

if [[ "$APPLY_ALLOWED" == true && ( "$APPLY_MODE" == "apply_all" || "$APPLY_MODE" == "apply_missing" ) ]]; then
  APPLY_FAILED=false
  for m in "${MIGRATIONS[@]}"; do
    v="$(basename "$m" .sql)"; n="$(basename "$m")"; cs="$(sha256sum "$m" | cut -d' ' -f1)"
    qbool "already_applied_$v" "select to_jsonb(exists (select 1 from public.$LEDGER_TABLE where version = '$v'));"
    if [[ "$CHECK_VAL" == true ]]; then
      note "  skip $n (already applied)"
      continue
    fi
    note "  applying $n (checksum $cs)"
    { echo "begin;"; cat "$m"; echo "commit;"; } > "$TMP/apply.sql"
    if ! runq_file "$TMP/apply.sql" >/dev/null; then
      err "Migration $n failed. Fail-closed: stopping. See docs/runbooks/FAILED_DEPLOYMENT_OR_MIGRATION.md."
      APPLY_FAILED=true
      break
    fi
    runq_sql "insert into public.$LEDGER_TABLE(version,name,checksum) values ('$v','$n','$cs') on conflict (version) do nothing;" >/dev/null
  done
  [[ "$APPLY_FAILED" == true ]] && warn "Migration application stopped early (fail-closed)."
fi

# Recompute sync truthfully after any apply/backfill.
LEDGER_EXISTS_AFTER=false
qbool "ledger_exists_after" "select to_jsonb(to_regclass('public.$LEDGER_TABLE') is not null);"
LEDGER_EXISTS_AFTER="$CHECK_VAL"
MIGRATIONS_IN_SYNC=false
if [[ "$LEDGER_EXISTS_AFTER" == true ]]; then
  qbool "ledger_eq_repo_after" "select to_jsonb(coalesce((select string_agg(version, ',' order by version) from public.$LEDGER_TABLE), '') = '$REPO_VERSIONS');"
  [[ "$CHECK_VAL" == true ]] && MIGRATIONS_IN_SYNC=true
fi

# ---------------------------------------------------------------------------
# 6. Security advisors (Management API path; supported by CLI)
# ---------------------------------------------------------------------------
note "Running Supabase security advisors ..."
ADVISORS_RC=1
if supabase db advisors --type security --project-ref "$REF" --fail-on error >"$TMP/adv.out" 2>"$TMP/adv.err"; then
  ADVISORS_RC=0
  note "  security advisors: no error-level findings"
else
  warn "  security advisors: error-level findings or advisor run failed (see run log; no secrets printed)"
fi

# ---------------------------------------------------------------------------
# 7. Compose summary flags
# ---------------------------------------------------------------------------
FINANCIAL_OK=false
[[ "$GATE_AUTH_OK" == true && "$CLOSE_SERIAL_OK" == true && "$AUDIT_OK" == true \
   && "$JOURNAL_OK" == true && "$S7_IMPORT_OK" == true && "$RECON_OK" == true ]] && FINANCIAL_OK=true

SECURITY_OK=false
[[ "$RLS_OK" == true && "$SECDEF_OK" == true && "$GATE_AUTH_OK" == true \
   && "$AUDIT_OK" == true && "$ADVISORS_RC" -eq 0 ]] && SECURITY_OK=true

note "rls_ok=$RLS_OK secdef_ok=$SECDEF_OK gate_auth_ok=$GATE_AUTH_OK audit_ok=$AUDIT_OK"
note "financial_ok=$FINANCIAL_OK security_ok=$SECURITY_OK migrations_in_sync=$MIGRATIONS_IN_SYNC"

emit true "$CLASSIFICATION" "$MIGRATIONS_IN_SYNC" "$RLS_OK" "$FINANCIAL_OK" "$SECURITY_OK"

if [[ "$CLASSIFICATION" == "UNRELATED" ]]; then
  exit 1
fi
exit 0
