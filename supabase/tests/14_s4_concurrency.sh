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
OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where name='مشروع النخيل' limit 1")"
BUYER="$(psql_value "select id from public.parties where legal_name='مشتري الأصل العقاري' limit 1")"
SUPPLIER="$(psql_value "select id from public.parties where legal_name='مورد أول' limit 1")"
CASH="$(psql_value "select id from public.project_cash_accounts where name='حساب بنك المشروع' limit 1")"

# Prepare a complete, authoritative sale fixture through the public commands.
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.create_property_asset('$ORG','$PROJECT','أصل سباق الاعتراف','S4-RACE','s4-race-sale-asset');"
ASSET="$(psql_value "select id from public.property_assets where idempotency_key='s4-race-sale-asset'")"

psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.transition_property_asset('$ORG','$ASSET','CANDIDATE','DUE_DILIGENCE','بدء الفحص',null,'s4-race-dd');
select public.record_property_acquisition('$ORG','$ASSET','$SUPPLIER','S4-RACE-ACQ',1000,0,'EGP',current_date-3,null,'عقد سباق الاستحواذ','s4-race-acquisition');
select public.record_property_control('$ORG','$ASSET',null,'ACQUISITION_CHECK','فحص سباق','PASSED',current_date-3,null,'ناجح','$OWNER','S4-RACE-DD',null,'s4-race-dd-control');
select public.transition_property_asset('$ORG','$ASSET','DUE_DILIGENCE','ACQUIRING','اجتياز الفحص','S4-RACE-DD','s4-race-acquiring');
select public.record_property_control('$ORG','$ASSET',null,'TITLE','سند سباق','PASSED',current_date-2,null,'ساري','$OWNER','S4-RACE-TITLE',null,'s4-race-title');
select public.record_property_control('$ORG','$ASSET',null,'POSSESSION','حيازة سباق','PASSED',current_date-2,null,'سارية','$OWNER','S4-RACE-POS',null,'s4-race-possession');
select public.transition_property_asset('$ORG','$ASSET','ACQUIRING','HELD','السيطرة مكتملة','S4-RACE-TITLE-POS','s4-race-held');
select public.create_cost_obligation('$ORG','$PROJECT','$SUPPLIER','تكلفة دفترية لسباق الاعتراف',1000,'EGP',current_date-1,'CAPITALIZABLE_WIP','s4-race-wip-obligation');"
OBLIGATION="$(psql_value "select id from public.cost_obligations where idempotency_key='s4-race-wip-obligation'")"
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.classify_property_cost('$ORG','$OBLIGATION','$ASSET',null,null,'ACQUISITION','سياسة WIP لسباق الاعتراف','s4-race-wip-classify');
select public.authorize_cost_obligation('$ORG','$OBLIGATION','s4-race-wip-authorize');
select public.create_cost_obligation('$ORG','$PROJECT','$SUPPLIER','WIP متزامن مع انتقال السيطرة',200,'EGP',current_date,'CAPITALIZABLE_WIP','s4-race-late-wip');"
LATE_WIP="$(psql_value "select id from public.cost_obligations where idempotency_key='s4-race-late-wip'")"
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.classify_property_cost('$ORG','$LATE_WIP','$ASSET',null,null,'OTHER','سياسة WIP متزامن','s4-race-late-wip-class');
select public.create_property_disposition('$ORG','$PROJECT','$ASSET','$BUYER','S4-RACE-DISP','اتفاق سباق الاعتراف',1000,'EGP',current_date-1,current_date,'s4-race-disposition');"
DISPOSITION="$(psql_value "select id from public.property_dispositions where idempotency_key='s4-race-disposition'")"
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.approve_property_disposition('$ORG','$DISPOSITION','s4-race-disposition-approve');
select public.transition_property_asset('$ORG','$ASSET','HELD','EXITING','بدء تخارج سباق الاعتراف','S4-RACE-DISP','s4-race-exiting');"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Control transfer and a final WIP authorization share the disposition-row
# serialization boundary. The late cost either commits before transfer and is
# included, or loses after transfer and rolls back; it can never enter after the
# recognition snapshot.
TRANSFER_SQL="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.confirm_property_control_transfer('$ORG','$DISPOSITION',current_date,'محضر انتقال سباق الاعتراف','s4-race-transfer');"
LATE_WIP_SQL="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.authorize_cost_obligation('$ORG','$LATE_WIP','s4-race-late-wip-authorize');"
set +e
run_session "$TRANSFER_SQL" "$tmpdir/transfer.log" & pid_transfer=$!
run_session "$LATE_WIP_SQL" "$tmpdir/late-wip.log" & pid_wip=$!
wait "$pid_transfer"; status_transfer=$?
wait "$pid_wip"; status_wip=$?
set -e
if [[ "$status_transfer" -ne 0 ]]; then
  echo "ERROR: control transfer lost its carrying-freeze race; transfer=$status_transfer wip=$status_wip" >&2
  cat "$tmpdir/transfer.log" "$tmpdir/late-wip.log" >&2
  exit 1
fi
ACTIVE_WIP="$(psql_value "select coalesce(sum(jl.debit_minor_units-jl.credit_minor_units),0) from public.property_cost_items pci join public.journal_lines jl on jl.obligation_id=pci.cost_obligation_id join public.semantic_accounts sa on sa.id=jl.account_id and sa.role='DEVELOPMENT_WIP' where pci.property_asset_id='$ASSET'")"
if [[ "$ACTIVE_WIP" != '1000' && "$ACTIVE_WIP" != '1200' ]]; then
  echo "ERROR: control-transfer/WIP race left invalid active WIP=$ACTIVE_WIP" >&2
  exit 1
fi

SQL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.recognize_property_sale('$ORG','$DISPOSITION',current_date,'s4-race-recognition-a');"
SQL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.recognize_property_sale('$ORG','$DISPOSITION',current_date,'s4-race-recognition-b');"

set +e
run_session "$SQL_A" "$tmpdir/recognition-a.log" & pid_a=$!
run_session "$SQL_B" "$tmpdir/recognition-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: recognition race expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/recognition-a.log" "$tmpdir/recognition-b.log" >&2
  exit 1
fi
REC_COUNT="$(psql_value "select count(*) from public.property_sale_recognitions where disposition_id='$DISPOSITION'")"
BATCH_COUNT="$(psql_value "select count(*) from public.journal_batches jb join public.property_sale_recognitions r on r.id=jb.source_id where r.disposition_id='$DISPOSITION' and jb.source_type='PROPERTY_SALE_RECOGNITION'")"
if [[ "$REC_COUNT" != '1' || "$BATCH_COUNT" != '1' ]]; then
  echo "ERROR: recognition race left recognitions=$REC_COUNT batches=$BATCH_COUNT" >&2
  exit 1
fi
RECOGNITION="$(psql_value "select id from public.property_sale_recognitions where disposition_id='$DISPOSITION'")"
RECOGNIZED_CARRYING="$(psql_value "select carrying_cost_minor_units from public.property_sale_recognitions where id='$RECOGNITION'")"
if [[ "$RECOGNIZED_CARRYING" != "$ACTIVE_WIP" ]]; then
  echo "ERROR: recognized carrying=$RECOGNIZED_CARRYING does not match serialized active WIP=$ACTIVE_WIP" >&2
  exit 1
fi

# Two 70% collections race against the same receivable. The recognition-row
# lock and database trigger must permit exactly one and preserve the ceiling.
COL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.collect_property_sale_receivable('$ORG','$RECOGNITION','$CASH',700,current_date,'تحصيل سباق أ','s4-race-collection-a');"
COL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.collect_property_sale_receivable('$ORG','$RECOGNITION','$CASH',700,current_date,'تحصيل سباق ب','s4-race-collection-b');"
set +e
run_session "$COL_A" "$tmpdir/collection-a.log" & pid_a=$!
run_session "$COL_B" "$tmpdir/collection-b.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: collection race expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/collection-a.log" "$tmpdir/collection-b.log" >&2
  exit 1
fi
COLLECTED="$(psql_value "select coalesce(sum(amount_minor_units),0) from public.property_sale_collections where recognition_id='$RECOGNITION'")"
COL_COUNT="$(psql_value "select count(*) from public.property_sale_collections where recognition_id='$RECOGNITION'")"
OUTSTANDING="$(psql_value "select outstanding_receivable_minor_units from public.property_realized_result_read where recognition_id='$RECOGNITION'")"
if [[ "$COLLECTED" != '700' || "$COL_COUNT" != '1' || "$OUTSTANDING" != '300' ]]; then
  echo "ERROR: collection race left count=$COL_COUNT collected=$COLLECTED outstanding=$OUTSTANDING" >&2
  exit 1
fi

echo 'S4 recognition and collection two-session concurrency PASS'
