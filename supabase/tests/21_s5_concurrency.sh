#!/usr/bin/env bash
set -euo pipefail

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
USER_ID='00000000-0000-4000-8000-000000000001'
DIST="$(psql_value "select id from public.s5_distributions where organization_id='$ORG' and idempotency_key='s5-concurrency-dist-prepare' limit 1")"
PROJECT="$(psql_value "select project_id from public.s5_distributions where id='$DIST'")"
CURRENCY="$(psql_value "select currency from public.s5_distributions where id='$DIST'")"
CASH="$(psql_value "select ca.id from public.project_cash_accounts ca where ca.organization_id='$ORG' and ca.project_id='$PROJECT' and ca.currency='$CURRENCY' and public.s5_cash_account_balance_internal(ca.organization_id,ca.project_id,ca.id,ca.currency)>0 order by ca.id limit 1")"
PAY_DATE="$(psql_value "select start_date from public.accounting_periods where organization_id='$ORG' and project_id='$PROJECT' and status='OPEN' order by version desc limit 1")"

for value in "$DIST" "$PROJECT" "$CASH" "$PAY_DATE"; do
  if [[ -z "$value" ]]; then
    echo 'ERROR: S5 concurrency fixture is incomplete.' >&2
    exit 1
  fi
done

SQL_A="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.s5_pay_distribution('$ORG','$DIST','$CASH',1,'$PAY_DATE','S5-CONCURRENCY-PAY-A','s5-concurrency-pay-key-a');"
SQL_B="set request.jwt.claim.sub='$USER_ID'; set role authenticated;
select public.s5_pay_distribution('$ORG','$DIST','$CASH',1,'$PAY_DATE','S5-CONCURRENCY-PAY-B','s5-concurrency-pay-key-b');"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
set +e
run_session "$SQL_A" "$tmpdir/pay-a.log" & pid_a=$!
run_session "$SQL_B" "$tmpdir/pay-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent distribution payment expected exactly one success; got A=$status_a B=$status_b" >&2
  cat "$tmpdir/pay-a.log" >&2 || true
  cat "$tmpdir/pay-b.log" >&2 || true
  exit 1
fi

ACTIVE_PAYMENTS="$(psql_value "select count(*) from public.s5_distribution_payments p where p.distribution_id='$DIST' and not exists(select 1 from public.journal_batches rb where rb.reversal_of_batch_id=p.journal_batch_id)")"
OUTSTANDING="$(psql_value "select outstanding_minor_units from public.s5_distributions_read where distribution_id='$DIST'")"
if [[ "$ACTIVE_PAYMENTS" != '1' || "$OUTSTANDING" != '0' ]]; then
  echo "ERROR: concurrency invariant failed: active_payments=$ACTIVE_PAYMENTS outstanding=$OUTSTANDING" >&2
  exit 1
fi

echo 'S5 distribution payment concurrency PASS'
