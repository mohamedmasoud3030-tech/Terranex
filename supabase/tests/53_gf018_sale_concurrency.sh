#!/usr/bin/env bash
set -euo pipefail
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"; export PGPASSWORD="${PGPASSWORD:-postgres}"
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql(){ local sql="$1"; if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$sql" | docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB"; else printf '%s\n' "$sql" | psql -q -v ON_ERROR_STOP=1 -d "$DB"; fi; }
psql_value(){ local sql="$1"; if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -Atq -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB" -c "$sql"; else psql -Atq -v ON_ERROR_STOP=1 -d "$DB" -c "$sql"; fi; }
run_session(){ psql_sql "$1" >"$2" 2>&1; }

ORG='10000000-0000-4000-8000-000000000001'; OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where internal_reference='GF013-AG-A'")"
ASSIGN="$(psql_value "select id from public.crop_cycle_field_assignments where idempotency_key='s18-assignment'")"
STORE="$(psql_value "select id from public.storage_locations where idempotency_key='s18-storage-create'")"
BUYER="$(psql_value "select id from public.parties where legal_name='مشتري محاصيل GF018'")"
CASH="$(psql_value "select id from public.project_cash_accounts where name='حساب تحصيل زراعي GF018'")"

psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.record_harvest_event('$ORG','$ASSIGN',current_date,102,100,'كجم','أولى','GF018-RACE-LOT','$STORE','حصاد سباق','EV-RACE','s18-race-harvest');"
LOT="$(psql_value "select id from public.harvest_lots where lot_reference='GF018-RACE-LOT'")"
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.create_agriculture_sale('$ORG','$PROJECT','$BUYER','GF018-RACE-A',null,current_date,'EGP',null,null,array['$LOT'::uuid],array['$STORE'::uuid],array[70::numeric],array[1000::bigint],'s18-race-sale-a');
select public.create_agriculture_sale('$ORG','$PROJECT','$BUYER','GF018-RACE-B',null,current_date,'EGP',null,null,array['$LOT'::uuid],array['$STORE'::uuid],array[60::numeric],array[1000::bigint],'s18-race-sale-b');"
SALE_A="$(psql_value "select id from public.agriculture_sales where sale_reference='GF018-RACE-A'")"
SALE_B="$(psql_value "select id from public.agriculture_sales where sale_reference='GF018-RACE-B'")"
psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.approve_agriculture_sale('$ORG','$SALE_A','s18-race-approve-a');
select public.approve_agriculture_sale('$ORG','$SALE_B','s18-race-approve-b');"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
SQL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.recognize_agriculture_sale('$ORG','$SALE_A',current_date,'تسليم سباق أ','s18-race-recognize-a');"
SQL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.recognize_agriculture_sale('$ORG','$SALE_B',current_date,'تسليم سباق ب','s18-race-recognize-b');"
set +e
run_session "$SQL_A" "$tmp/a.log" & pa=$!
run_session "$SQL_B" "$tmp/b.log" & pb=$!
wait "$pa"; sa=$?; wait "$pb"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: concurrent oversell expected exactly one success; A=$sa B=$sb" >&2; cat "$tmp"/*.log >&2; exit 1
fi
REC_COUNT="$(psql_value "select count(*) from public.agriculture_sale_recognitions where sale_id in ('$SALE_A','$SALE_B')")"
ISSUE_QTY="$(psql_value "select coalesce(sum(quantity),0) from public.harvest_inventory_movements where movement_type='SALE_ISSUE' and harvest_lot_id='$LOT'")"
BALANCE="$(psql_value "select public.harvest_lot_storage_balance('$LOT','$STORE')")"
if [[ "$REC_COUNT" != 1 ]] || { [[ "$ISSUE_QTY" != "70.000000" && "$ISSUE_QTY" != "60.000000" ]]; } || { [[ "$BALANCE" != "30.000000" && "$BALANCE" != "40.000000" ]]; }; then
  echo "ERROR: oversell race left recognitions=$REC_COUNT issue=$ISSUE_QTY balance=$BALANCE" >&2; exit 1
fi

RECOGNITION="$(psql_value "select id from public.agriculture_sale_recognitions where sale_id in ('$SALE_A','$SALE_B')")"
TOTAL="$(psql_value "select recognized_revenue_minor_units from public.agriculture_sale_recognitions where id='$RECOGNITION'")"
AMOUNT=$(( TOTAL * 7 / 10 ))
COL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.collect_agriculture_sale_receivable('$ORG','$RECOGNITION','$CASH',$AMOUNT,current_date,'تحصيل سباق أ','s18-race-collection-a');"
COL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.collect_agriculture_sale_receivable('$ORG','$RECOGNITION','$CASH',$AMOUNT,current_date,'تحصيل سباق ب','s18-race-collection-b');"
set +e
run_session "$COL_A" "$tmp/ca.log" & pa=$!
run_session "$COL_B" "$tmp/cb.log" & pb=$!
wait "$pa"; ca=$?; wait "$pb"; cb=$?
set -e
if ! { [[ "$ca" -eq 0 && "$cb" -ne 0 ]] || [[ "$ca" -ne 0 && "$cb" -eq 0 ]]; }; then
  echo "ERROR: collection ceiling race expected exactly one success; A=$ca B=$cb" >&2; cat "$tmp"/c*.log >&2; exit 1
fi
COLLECTED="$(psql_value "select coalesce(sum(amount_minor_units),0) from public.agriculture_sale_collections where recognition_id='$RECOGNITION'")"
OUTSTANDING="$(psql_value "select outstanding_receivable_minor_units from public.agriculture_sales_read where recognition_id='$RECOGNITION'")"
if [[ "$COLLECTED" != "$AMOUNT" || "$OUTSTANDING" != "$((TOTAL-AMOUNT))" ]]; then
  echo "ERROR: collection race left collected=$COLLECTED outstanding=$OUTSTANDING total=$TOTAL" >&2; exit 1
fi

echo 'GF-018 two-session oversell and collection concurrency PASS'
