#!/usr/bin/env bash
set -euo pipefail

# GF-009 / S7 — executable backup and restore rehearsal.
#
# This is a rehearsal against the verification database built by the canonical
# replay, using standard PostgreSQL tooling only. It never touches a production
# system and never uses production credentials. A real production restore is a
# separate operator procedure documented in docs/runbooks/BACKUP_AND_RESTORE.md;
# passing this suite does not mean a production restore has been performed.
#
# The rehearsal:
#   1. captures integrity fingerprints from the source database;
#   2. takes a logical backup with pg_dump;
#   3. restores it into a clean database;
#   4. re-runs every integrity query on the restored copy;
#   5. fails loudly on any mismatch.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
RESTORE_DB="${SOURCE_DB}_s7_restore"
DUMP_FILE="$(mktemp -t terranex-s7-backup-XXXXXX.dump)"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

psql_cmd() {
  local db="$1" sql="$2"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$db" -c "$sql"
  else
    psql -v ON_ERROR_STOP=1 -Atq -d "$db" -c "$sql"
  fi
}

cleanup() {
  rm -f "$DUMP_FILE"
  psql_cmd postgres "select pg_terminate_backend(pid) from pg_stat_activity where datname='$RESTORE_DB' and pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  psql_cmd postgres "drop database if exists \"$RESTORE_DB\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

# The operator runbook is part of the deliverable, not an optional extra: an
# executable rehearsal without a written production procedure is not a
# restorable system. The runbook must also refuse to imply that this rehearsal
# was a production restore.
RUNBOOK="$ROOT/docs/runbooks/BACKUP_AND_RESTORE.md"
if [[ ! -s "$RUNBOOK" ]]; then
  echo "ERROR: the operator runbook $RUNBOOK is missing; the backup/restore gate requires it." >&2
  exit 1
fi
if ! grep -q 'rehearsal' "$RUNBOOK"; then
  echo "ERROR: $RUNBOOK must state explicitly that the automated suite is a rehearsal." >&2
  exit 1
fi

SERVER_MAJOR="$(psql_cmd postgres "select current_setting('server_version_num')::int/10000")"
PG_DUMP=''
PG_RESTORE=''

# pg_dump refuses to read a server newer than itself, so resolve a client whose
# major version is at least the server's. Never silently skip the gate.
if [[ -z "$CONTAINER" ]]; then
  candidates=()
  if command -v pg_dump >/dev/null 2>&1; then candidates+=("$(command -v pg_dump)"); fi
  for candidate in /usr/lib/postgresql/*/bin/pg_dump; do
    [[ -x "$candidate" ]] && candidates+=("$candidate")
  done
  for candidate in "${candidates[@]}"; do
    client_major="$("$candidate" --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
    [[ -z "$client_major" ]] && continue
    if (( client_major >= SERVER_MAJOR )) && [[ -x "${candidate%pg_dump}pg_restore" ]]; then
      PG_DUMP="$candidate"
      PG_RESTORE="${candidate%pg_dump}pg_restore"
      break
    fi
  done
  if [[ -z "$PG_DUMP" ]]; then
    echo "ERROR: no pg_dump/pg_restore of major version >= $SERVER_MAJOR is available;" >&2
    echo 'the backup/restore rehearsal is a required gate and must not be skipped.' >&2
    exit 2
  fi
elif ! docker exec "$CONTAINER" sh -c 'command -v pg_dump >/dev/null 2>&1 && command -v pg_restore >/dev/null 2>&1'; then
  echo 'ERROR: pg_dump/pg_restore are unavailable in the database container;' >&2
  echo 'the backup/restore rehearsal is a required gate and must not be skipped.' >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Integrity queries. Every one of these must produce an identical answer on the
# restored copy. They span tenant isolation, journal balance, the financial
# rollforwards, S6 close provenance, S5 allocation/distribution, and the new S7
# import/reconciliation records.
# ---------------------------------------------------------------------------
declare -a CHECK_NAMES=(
  'tenant_scoped_projects'
  'cross_tenant_journal_leakage'
  'unbalanced_journal_batches'
  'journal_line_total'
  'cash_position_by_account'
  'obligation_outstanding_total'
  's6_close_snapshot_provenance'
  's6_period_versions'
  's5_allocation_provenance'
  's5_allocation_line_total'
  's5_distribution_settlement'
  's5_partner_capital_rollforward'
  's7_opening_import_state'
  's7_opening_row_fingerprints'
  's7_reconciliation_state'
  's7_uat_state'
  'audit_event_total'
)
declare -a CHECK_SQL=(
  "select coalesce(string_agg(organization_id::text||':'||count::text,'|' order by organization_id::text),'')
   from (select organization_id, count(*) as count from public.investment_projects group by organization_id) t"
  "select count(*) from public.journal_lines jl
     join public.journal_batches jb on jb.id=jl.batch_id
    where jl.organization_id<>jb.organization_id or jl.project_id<>jb.project_id"
  "select count(*) from (
     select batch_id from public.journal_lines group by batch_id
     having sum(debit_minor_units)<>sum(credit_minor_units) or count(*)<2) u"
  "select coalesce(sum(debit_minor_units)::text,'0')||'/'||coalesce(sum(credit_minor_units)::text,'0')
   from public.journal_lines"
  "select coalesce(string_agg(cash_account_id::text||'='||balance_minor_units,'|' order by cash_account_id::text),'')
   from public.project_cash_position_read"
  "select coalesce(string_agg(obligation_id::text||'='||outstanding_minor_units,'|' order by obligation_id::text),'')
   from public.cost_obligation_position_read"
  "select coalesce(string_agg(s.id::text||'='||s.content_hash,'|' order by s.id::text),'')
   from public.close_run_snapshots s"
  "select coalesce(string_agg(id::text||'='||status||':'||version::text,'|' order by id::text),'')
   from public.accounting_periods"
  "select coalesce(string_agg(id::text||'='||status||':'||content_hash||':'||source_amount_minor_units::text,
     '|' order by id::text),'') from public.s5_allocation_runs"
  "select coalesce(sum(allocated_minor_units)::text,'0') from public.s5_allocation_lines"
  "select coalesce(string_agg(distribution_id::text||'='||settlement_status||':'||outstanding_minor_units,
     '|' order by distribution_id::text),'') from public.s5_distributions_read"
  "select coalesce(string_agg(participant_party_id::text||'='||closing_capital_minor_units,
     '|' order by participant_party_id::text),'') from public.s5_partner_capital_statement_read"
  "select coalesce(string_agg(id::text||'='||status||':'||content_hash||':'||
     coalesce(snapshot_content_hash,'-')||':'||computed_debit_total_minor_units::text,
     '|' order by id::text),'') from public.s7_opening_imports"
  "select coalesce(string_agg(fingerprint,'|' order by fingerprint),'') from public.s7_opening_import_rows"
  "select coalesce(string_agg(id::text||'='||status||':'||variance_minor_units::text||':'||content_hash,
     '|' order by id::text),'') from public.s7_reconciliation_checkpoints"
  "select coalesce(string_agg(task_code||'='||status,'|' order by task_code),'') from public.s7_uat_tasks"
  "select count(*)::text from public.audit_events"
)

declare -a BEFORE=()
for i in "${!CHECK_NAMES[@]}"; do
  BEFORE[i]="$(psql_cmd "$SOURCE_DB" "${CHECK_SQL[i]}")"
done

SOURCE_ROWS="$(psql_cmd "$SOURCE_DB" "select count(*) from public.journal_lines")"
if [[ "$SOURCE_ROWS" == '0' ]]; then
  echo 'ERROR: the backup/restore rehearsal source database holds no financial facts.' >&2
  exit 1
fi
if [[ "${BEFORE[2]}" != '0' || "${BEFORE[1]}" != '0' ]]; then
  echo "ERROR: the source database is already inconsistent before backup: unbalanced=${BEFORE[2]} cross_tenant=${BEFORE[1]}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Back up with standard PostgreSQL tooling, then restore into a clean database.
# ---------------------------------------------------------------------------
if [[ -n "$CONTAINER" ]]; then
  docker exec "$CONTAINER" pg_dump -U "$PGUSER" -Fc -d "$SOURCE_DB" -f /tmp/terranex-s7.dump
else
  "$PG_DUMP" -Fc -d "$SOURCE_DB" -f "$DUMP_FILE"
  if [[ ! -s "$DUMP_FILE" ]]; then
    echo 'ERROR: pg_dump produced an empty backup artifact.' >&2
    exit 1
  fi
fi

psql_cmd postgres "create database \"$RESTORE_DB\";" >/dev/null
# The shim roles are cluster-global and already exist; the restore only needs
# the schema and data of the database itself.
if [[ -n "$CONTAINER" ]]; then
  docker exec "$CONTAINER" pg_restore -U "$PGUSER" -d "$RESTORE_DB" --no-owner --no-privileges /tmp/terranex-s7.dump >/dev/null 2>&1 || true
  docker exec "$CONTAINER" rm -f /tmp/terranex-s7.dump || true
else
  "$PG_RESTORE" -d "$RESTORE_DB" --no-owner --no-privileges "$DUMP_FILE" >/dev/null 2>&1 || true
fi

RESTORED_TABLES="$(psql_cmd "$RESTORE_DB" "select count(*) from information_schema.tables where table_schema='public'")"
if [[ "$RESTORED_TABLES" == '0' ]]; then
  echo 'ERROR: the restore produced an empty database.' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Re-run every integrity query on the restored copy and fail loudly on drift.
# ---------------------------------------------------------------------------
FAILURES=0
for i in "${!CHECK_NAMES[@]}"; do
  AFTER="$(psql_cmd "$RESTORE_DB" "${CHECK_SQL[i]}")"
  if [[ "$AFTER" != "${BEFORE[i]}" ]]; then
    echo "ERROR: restored database differs on '${CHECK_NAMES[i]}'" >&2
    echo "  source:   ${BEFORE[i]}" >&2
    echo "  restored: $AFTER" >&2
    FAILURES=$((FAILURES + 1))
  fi
done
if [[ "$FAILURES" -ne 0 ]]; then
  echo "ERROR: backup/restore rehearsal failed on $FAILURES integrity check(s)." >&2
  exit 1
fi

# Structural controls must survive a restore, not just data. A restored copy
# with data but without forced RLS would be a silent tenant-isolation hole.
RLS_OK="$(psql_cmd "$RESTORE_DB" "select bool_and(relrowsecurity and relforcerowsecurity)::text
  from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  where c.relname in ('organizations','memberships','investment_projects','audit_events',
    'journal_batches','journal_lines','s5_allocation_runs','s5_distributions',
    's7_opening_imports','s7_opening_import_rows','s7_reconciliation_checkpoints',
    's7_reconciliation_exceptions','s7_uat_tasks','s7_pilot_rehearsals')")"
if [[ "$RLS_OK" != 'true' ]]; then
  echo 'ERROR: forced default-deny RLS did not survive the restore.' >&2
  exit 1
fi

IMMUTABLE_OK="$(psql_cmd "$RESTORE_DB" "select count(*) from pg_trigger
  where not tgisinternal and tgname in (
    'journal_batches_immutable','journal_lines_immutable',
    's7_opening_imports_transition_guard','s7_opening_imports_no_delete',
    's7_reconciliation_checkpoints_immutable','memberships_last_active_owner_guard')")"
if [[ "$IMMUTABLE_OK" != '6' ]]; then
  echo "ERROR: only $IMMUTABLE_OK of 6 critical immutability/recovery triggers survived the restore." >&2
  exit 1
fi

# Prove the restored copy still refuses a destructive edit of a posted fact.
TAMPER_LOG="$(mktemp)"
set +e
if [[ -n "$CONTAINER" ]]; then
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$RESTORE_DB" \
    -c "update public.journal_lines set debit_minor_units=debit_minor_units+1" >"$TAMPER_LOG" 2>&1
else
  psql -v ON_ERROR_STOP=1 -Atq -d "$RESTORE_DB" \
    -c "update public.journal_lines set debit_minor_units=debit_minor_units+1" >"$TAMPER_LOG" 2>&1
fi
tamper_status=$?
set -e
if [[ "$tamper_status" -eq 0 ]] || ! grep -q 'immutable once posted' "$TAMPER_LOG"; then
  echo 'ERROR: the restored database allowed a destructive edit of a posted journal line.' >&2
  cat "$TAMPER_LOG" >&2 || true
  rm -f "$TAMPER_LOG"
  exit 1
fi
rm -f "$TAMPER_LOG"

# Record the rehearsal in the source database through the production command, so
# the acceptance report derives its BACKUP_RESTORE line from a recorded fact
# instead of an assumption. This is a rehearsal fact only; it never asserts that
# a production restore was performed.
REHEARSAL_PROJECT="$(psql_cmd "$SOURCE_DB" "select id from public.investment_projects
  where organization_id='10000000-0000-4000-8000-000000000001'
    and name='مشروع البروفة الشاملة' limit 1")"
if [[ -z "$REHEARSAL_PROJECT" ]]; then
  echo 'ERROR: the end-to-end rehearsal project is missing; run 27_s7_end_to_end_rehearsal.sql first.' >&2
  exit 1
fi
psql_cmd "$SOURCE_DB" "set request.jwt.claim.sub='00000000-0000-4000-8000-000000000001';
set role authenticated;
select public.s7_record_pilot_rehearsal(
  '10000000-0000-4000-8000-000000000001','$REHEARSAL_PROJECT','BACKUP_RESTORE','PASS',
  'بروفة نسخ احتياطي واستعادة على قاعدة تحقق نظيفة بأدوات PostgreSQL القياسية مع إعادة تشغيل ${#CHECK_NAMES[@]} استعلام سلامة ومطابقتها حرفيًا',
  jsonb_build_object('source','26_s7_backup_restore.sh','integrity_checks',${#CHECK_NAMES[@]},
    'production_restore_performed',false),
  's7-rehearsal-restore1');" >/dev/null

RECORDED="$(psql_cmd "$SOURCE_DB" "select backup_restore_result
  from public.s7_pilot_acceptance_report_read where project_id='$REHEARSAL_PROJECT'")"
if [[ "$RECORDED" != 'PASS' ]]; then
  echo "ERROR: the backup/restore rehearsal fact was not recorded (report says '${RECORDED:-null}')." >&2
  exit 1
fi

echo "S7 backup and restore rehearsal PASS (${#CHECK_NAMES[@]} integrity checks reproduced exactly)"
