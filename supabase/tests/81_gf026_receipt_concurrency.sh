#!/usr/bin/env bash
set -euo pipefail

# GF-026 / R4 — Purchase receiving concurrency.
#
# A real two-session race proves the receiving serialization contract:
#
#   Race 1 (over-receipt): an APPROVED order line of 100 KG receives two
#   concurrent receipts (60 and 50). Exactly one must succeed and the
#   cumulative received quantity must never exceed 100.
#
#   Race 2 (replay): two concurrent receipts with the SAME idempotency key
#   (30 each) must both succeed with exactly one persisted receipt — the
#   second session replays the committed first one instead of duplicating.
#
# The RPC locks each order line FOR UPDATE during its over-receipt
# pre-check, so concurrent receipts serialize and re-check the committed
# received quantity under the lock (BEFORE INSERT trigger stays as the
# second defense).

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
MEMBER='00000000-0000-4000-8000-000000000003'
OWNER='00000000-0000-4000-8000-000000000001'

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF025-PROJ' limit 1")"
if [[ -z "$PROJECT" ]]; then
  echo 'ERROR: GF-026 concurrency fixture prerequisite missing (GF025-PROJ project from suite 78).' >&2
  exit 1
fi

# Idempotent fixture: a dedicated APPROVED order with one 100-unit line.
PO="$(psql_value "select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-CONC-001' limit 1")"
if [[ -z "$PO" ]]; then
  psql_sql "set request.jwt.claim.sub='$MEMBER'; set role authenticated;
    select public.create_purchase_order('$ORG','$PROJECT','PO-CONC-001',null,null,null,(current_date + 30),
      '[{\"item_description\":\"علف سباق\",\"quantity\":100,\"unit\":\"كجم\"}]','s81-conc-po-create');
    select public.submit_purchase_order('$ORG',(select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-CONC-001'),'s81-conc-po-submit');"
  psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
    select public.approve_purchase_order('$ORG',(select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-CONC-001'),'s81-conc-po-approve');"
  PO="$(psql_value "select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-CONC-001' limit 1")"
fi
if [[ -z "$PO" ]]; then
  echo 'ERROR: could not provision the GF-026 concurrency order.' >&2
  exit 1
fi

LINE="$(psql_value "select id from public.purchase_order_lines where organization_id='$ORG' and purchase_order_id='$PO' limit 1")"
if [[ -z "$LINE" ]]; then
  echo 'ERROR: could not resolve the GF-026 concurrency order line.' >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

RECEIPT_60="set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.create_purchase_receipt('$ORG','$PROJECT','$PO','سند استلام سباق 60',null,ARRAY['$LINE']::uuid[],ARRAY[60]::numeric[],'s81-conc-rec-60');"
RECEIPT_50="set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.create_purchase_receipt('$ORG','$PROJECT','$PO','سند استلام سباق 50',null,ARRAY['$LINE']::uuid[],ARRAY[50]::numeric[],'s81-conc-rec-50');"

# Race 1: concurrent over-receipt (60 + 50 > 100) — exactly one may succeed.
set +e
run_session "$RECEIPT_60" "$tmpdir/r60.log" & pid_a=$!
run_session "$RECEIPT_50" "$tmpdir/r50.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent receipts expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/r60.log" "$tmpdir/r50.log" >&2 || true
  exit 1
fi

TOTAL_1="$(psql_value "select coalesce(sum(quantity_received),0)::text from public.purchase_receipt_lines where organization_id='$ORG' and purchase_order_line_id='$LINE'")"
if [[ "$TOTAL_1" != '50.000000' && "$TOTAL_1" != '60.000000' ]]; then
  echo "ERROR: race 1 left an invalid received total: $TOTAL_1" >&2
  exit 1
fi

# Race 2: same idempotency key, concurrent — both succeed, one persisted row.
RECEIPT_X="set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.create_purchase_receipt('$ORG','$PROJECT','$PO','سند استلام سباق مكرر',null,ARRAY['$LINE']::uuid[],ARRAY[30]::numeric[],'s81-conc-rec-x');"

set +e
run_session "$RECEIPT_X" "$tmpdir/rx1.log" & pid_c=$!
run_session "$RECEIPT_X" "$tmpdir/rx2.log" & pid_d=$!
wait "$pid_c"; status_c=$?
wait "$pid_d"; status_d=$?
set -e

if [[ "$status_c" -ne 0 || "$status_d" -ne 0 ]]; then
  echo "ERROR: same-key concurrent receipts must both replay successfully; C=$status_c D=$status_d" >&2
  cat "$tmpdir/rx1.log" "$tmpdir/rx2.log" >&2 || true
  exit 1
fi

RECEIPT_ROWS="$(psql_value "select count(*) from public.purchase_receipts where organization_id='$ORG' and idempotency_key='s81-conc-rec-x'")"
if [[ "$RECEIPT_ROWS" != '1' ]]; then
  echo "ERROR: same-key race persisted $RECEIPT_ROWS receipts, expected exactly 1" >&2
  exit 1
fi

TOTAL_FINAL="$(psql_value "select coalesce(sum(quantity_received),0)::text from public.purchase_receipt_lines where organization_id='$ORG' and purchase_order_line_id='$LINE'")"
case "$TOTAL_FINAL" in
  '80.000000'|'90.000000') ;;
  *)
    echo "ERROR: final received total is $TOTAL_FINAL, expected 80 or 90 (never > 100)" >&2
    exit 1
    ;;
esac

echo 'GF-026 purchase receiving concurrency PASS'
