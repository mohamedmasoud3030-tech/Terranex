#!/usr/bin/env bash
set -euo pipefail

# GF-007 / S6 — two-session close and correction concurrency.

DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

psql_sql() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then
    printf '%s\n' "$sql" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"
  else
    printf '%s\n' "$sql" | psql -v ON_ERROR_STOP=1 -q -d "$DB"
  fi
}
psql_value() {
  local sql="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$sql"
  else
    psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$sql"
  fi
}
run_session() {
  local sql="$1" log="$2"
  if psql_sql "$sql" >"$log" 2>&1; then return 0; fi
  return 1
}

ORG='10000000-0000-4000-8000-000000000001'
OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="مشروع النخيل"

PROJECT_ID="$(psql_value "select id from public.investment_projects where name='$PROJECT' limit 1")"
if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: project fixture not found: $PROJECT" >&2
  exit 1
fi

# 16_s6_period_close.sql normally leaves the project with a current OPEN
# superseding period. Reuse that authoritative row. Only reopen a CLOSED period
# when this concurrency suite is run against a fixture that has no OPEN period.
# Never create a second OPEN period for the same project/currency.
PERIOD_ID="$(psql_value "select id from public.accounting_periods where project_id='$PROJECT_ID' and status='OPEN' order by version desc limit 1")"
if [[ -z "$PERIOD_ID" ]]; then
  CLOSED_PERIOD_ID="$(psql_value "select id from public.accounting_periods where project_id='$PROJECT_ID' and status='CLOSED' order by version desc limit 1")"
  if [[ -z "$CLOSED_PERIOD_ID" ]]; then
    echo "ERROR: no OPEN or CLOSED accounting period found for $PROJECT; ensure 16_s6_period_close.sql ran first" >&2
    exit 1
  fi
  psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
  select public.s6_reopen_period('$ORG','$PROJECT_ID','$CLOSED_PERIOD_ID',
    'reopen for s6 concurrency test', 'reopen-concurrency-evidence');"
  PERIOD_ID="$(psql_value "select id from public.accounting_periods where project_id='$PROJECT_ID' and status='OPEN' order by version desc limit 1")"
fi
if [[ -z "$PERIOD_ID" ]]; then
  echo "ERROR: could not derive an OPEN period for $PROJECT" >&2
  exit 1
fi

# Two concurrent prepare_close_run calls. Exactly one must succeed because only
# one PREPARED close run may exist for a period.
SQL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.s6_prepare_close_run('$ORG','$PROJECT_ID','$PERIOD_ID','concurrent close A');"
SQL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.s6_prepare_close_run('$ORG','$PROJECT_ID','$PERIOD_ID','concurrent close B');"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

set +e
run_session "$SQL_A" "$tmpdir/close-a.log" & pid_a=$!
run_session "$SQL_B" "$tmpdir/close-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: close race expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/close-a.log" "$tmpdir/close-b.log" >&2
  exit 1
fi

PREPARED_COUNT="$(psql_value "select count(*) from public.close_runs where period_id='$PERIOD_ID' and status='PREPARED'")"
if [[ "$PREPARED_COUNT" != '1' ]]; then
  echo "ERROR: close race left $PREPARED_COUNT PREPARED runs (expected 1)" >&2
  exit 1
fi

RUN_ID="$(psql_value "select id from public.close_runs where period_id='$PERIOD_ID' and status='PREPARED' limit 1")"

# Two concurrent approve calls using the same idempotency key. The command
# must serialize the side effect; a retry may either replay successfully or be
# rejected after observing the already-approved run, but there must be exactly
# one approved run and one immutable snapshot.
APPROVE_A="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.s6_approve_close_run('$ORG','$RUN_ID','s6-conc-approve-key');"
APPROVE_B="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.s6_approve_close_run('$ORG','$RUN_ID','s6-conc-approve-key');"
set +e
run_session "$APPROVE_A" "$tmpdir/approve-a.log" & pid_a=$!
run_session "$APPROVE_B" "$tmpdir/approve-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if [[ "$status_a" -ne 0 && "$status_b" -ne 0 ]]; then
  echo "ERROR: approve race expected at least one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/approve-a.log" "$tmpdir/approve-b.log" >&2
  exit 1
fi

APPROVED_COUNT="$(psql_value "select count(*) from public.close_runs where period_id='$PERIOD_ID' and status='APPROVED'")"
if [[ "$APPROVED_COUNT" != '1' ]]; then
  echo "ERROR: approve race left $APPROVED_COUNT APPROVED runs (expected 1)" >&2
  exit 1
fi

SNAPSHOT_COUNT="$(psql_value "select count(*) from public.close_run_snapshots where period_id='$PERIOD_ID'")"
if [[ "$SNAPSHOT_COUNT" != '1' ]]; then
  echo "ERROR: approve race left $SNAPSHOT_COUNT snapshots (expected 1)" >&2
  exit 1
fi

# Once the period is CLOSED, a direct insert must fail. The assertion also
# verifies no partial row survives the rejected writer.
POSTING_SQL="insert into public.journal_batches(organization_id, project_id, source_type, source_id,
  transaction_date, idempotency_key, request_hash, posted_by)
values ('$ORG', '$PROJECT_ID', 'COST_OBLIGATION', gen_random_uuid(),
  current_date, 's6-conc-locked-' || substr(md5(random()::text), 1, 8),
  repeat('a', 64), '$OWNER');"
set +e
psql_sql "$POSTING_SQL" >"$tmpdir/locked-posting.log" 2>&1
status_post=$?
set -e
if [[ "$status_post" -eq 0 ]]; then
  echo "ERROR: posting into a CLOSED period unexpectedly succeeded" >&2
  cat "$tmpdir/locked-posting.log" >&2
  exit 1
fi

LOCKED_KEYS="$(psql_value "select count(*) from public.journal_batches where idempotency_key like 's6-conc-locked-%'")"
if [[ "$LOCKED_KEYS" != '0' ]]; then
  echo "ERROR: closed-period posting left rows: $LOCKED_KEYS" >&2
  exit 1
fi

echo 'S6 close and correction two-session concurrency PASS'