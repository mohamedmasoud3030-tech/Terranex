#!/usr/bin/env bash
set -euo pipefail

# GF-024 / Livestock commercial concurrency.
#
# Real multi-session races prove:
#   1. two approved sales against the same as-of Cohort quantity cannot both
#      recognize (oversell);
#   2. two collections against the same recognized receivable cannot both
#      exceed the ceiling;
#   3. two identical purchase submissions produce exactly one PURCHASE_IN;
#   4. a concurrent purchase and sale serialize so the derived quantity is
#      never negative and never double-counted.
#
# Every guard is a database guard (per-Cohort advisory lock + deferred
# non-negative backstop + recognition-row lock), not a disabled UI button.

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
AUTH="set request.jwt.claim.sub='$OWNER'; set role authenticated;"

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF020-LS-A' limit 1")"
HERD="$(psql_value "select id from public.livestock_herds where organization_id='$ORG' and project_id='$PROJECT' and internal_reference='HERD-A' limit 1")"
SITE="$(psql_value "select id from public.livestock_sites where organization_id='$ORG' and project_id='$PROJECT' and internal_reference='SITE-A' limit 1")"
if [[ -z "$PROJECT" || -z "$HERD" || -z "$SITE" ]]; then
  echo 'ERROR: GF-024 concurrency prerequisites missing.' >&2
  exit 1
fi

BUYER="$(psql_value "select id from public.parties where organization_id='$ORG' and legal_name='مشتري مواشي GF024' limit 1")"
CASH="$(psql_value "select id from public.project_cash_accounts where organization_id='$ORG' and project_id='$PROJECT' and name='حساب تحصيل مواشي GF024' limit 1")"
if [[ -z "$BUYER" ]]; then
  psql_sql "$AUTH select public.create_party('$ORG','مشتري مواشي GF024','ORGANIZATION');" >/dev/null
  BUYER="$(psql_value "select id from public.parties where organization_id='$ORG' and legal_name='مشتري مواشي GF024' limit 1")"
fi
if [[ -z "$CASH" ]]; then
  psql_sql "$AUTH select public.create_project_cash_account('$ORG','$PROJECT','حساب تحصيل مواشي GF024','EGP');" >/dev/null
  CASH="$(psql_value "select id from public.project_cash_accounts where organization_id='$ORG' and project_id='$PROJECT' and name='حساب تحصيل مواشي GF024' limit 1")"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

provision_cohort() {
  local reference="$1" headcount="$2" key="$3" id
  id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
  if [[ -z "$id" ]]; then
    psql_sql "$AUTH select public.create_livestock_cohort('$ORG','$PROJECT','$HERD','$SITE','$reference','PURCHASED',date '2026-08-01',$headcount,null,null,null,null,null,null,null,'$key');" >/dev/null
    id="$(psql_value "select id from public.livestock_cohorts where organization_id='$ORG' and project_id='$PROJECT' and cohort_reference='$reference' limit 1")"
    psql_sql "$AUTH select public.transition_livestock_cohort('$ORG','$PROJECT','$id','PLANNED','ACTIVE','تفعيل سباق GF024',null,'$key-act');" >/dev/null
  fi
  if [[ -z "$id" ]]; then echo "ERROR: could not provision cohort $reference" >&2; exit 1; fi
  printf '%s' "$id"
}

quantity_of() { psql_value "select current_quantity from public.livestock_cohort_quantity_rollforward where cohort_id='$1'"; }

# ---------------------------------------------------------------------------
# Race 1 — two approved sales against one Cohort: exactly one recognizes.
# ---------------------------------------------------------------------------
RACE_COHORT="$(provision_cohort 'دفعة سباق البيع GF024' 100 'gf24-race-sale')"
[[ "$(quantity_of "$RACE_COHORT")" == '100' ]] || {
  echo "ERROR: sale race cohort did not start at 100 (got $(quantity_of "$RACE_COHORT"))." >&2
  exit 1
}

psql_sql "$AUTH
select public.create_livestock_sale('$ORG','$PROJECT','$BUYER','GF024-RACE-A',null,current_date,'EGP',null,'دليل سباق',array['$RACE_COHORT'::uuid],array[70]::integer[],array[8000]::bigint[],'gf24-race-sale-a');
select public.create_livestock_sale('$ORG','$PROJECT','$BUYER','GF024-RACE-B',null,current_date,'EGP',null,'دليل سباق',array['$RACE_COHORT'::uuid],array[60]::integer[],array[8000]::bigint[],'gf24-race-sale-b');" >/dev/null
SALE_A="$(psql_value "select id from public.livestock_sales where sale_reference='GF024-RACE-A'")"
SALE_B="$(psql_value "select id from public.livestock_sales where sale_reference='GF024-RACE-B'")"
psql_sql "$AUTH
select public.approve_livestock_sale('$ORG','$SALE_A','gf24-race-approve-a');
select public.approve_livestock_sale('$ORG','$SALE_B','gf24-race-approve-b');" >/dev/null

SQL_A="$AUTH select public.recognize_livestock_sale('$ORG','$SALE_A',current_date,'تسليم سباق أ','gf24-race-recognize-a');"
SQL_B="$AUTH select public.recognize_livestock_sale('$ORG','$SALE_B',current_date,'تسليم سباق ب','gf24-race-recognize-b');"
set +e
run_session "$SQL_A" "$tmpdir/a.log" & pa=$!
run_session "$SQL_B" "$tmpdir/b.log" & pb=$!
wait "$pa"; sa=$?
wait "$pb"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: concurrent oversell expected exactly one success; A=$sa B=$sb" >&2
  cat "$tmpdir/a.log" "$tmpdir/b.log" >&2
  exit 1
fi
REC_COUNT="$(psql_value "select count(*) from public.livestock_sale_recognitions where sale_id in ('$SALE_A','$SALE_B')")"
SALE_OUT_QTY="$(psql_value "select coalesce(sum(quantity),0) from public.livestock_quantity_events where event_type='SALE_OUT' and cohort_id='$RACE_COHORT'")"
BALANCE="$(quantity_of "$RACE_COHORT")"
if [[ "$REC_COUNT" != '1' ]] || { [[ "$SALE_OUT_QTY" != '70' && "$SALE_OUT_QTY" != '60' ]]; } || { [[ "$BALANCE" != '30' && "$BALANCE" != '40' ]]; }; then
  echo "ERROR: oversell race left recognitions=$REC_COUNT sale_out=$SALE_OUT_QTY balance=$BALANCE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Race 2 — two collections of 60% against one receivable: exactly one wins.
# ---------------------------------------------------------------------------
RECOGNITION="$(psql_value "select id from public.livestock_sale_recognitions where sale_id in ('$SALE_A','$SALE_B')")"
TOTAL="$(psql_value "select recognized_revenue_minor_units from public.livestock_sale_recognitions where id='$RECOGNITION'")"
AMOUNT=$(( TOTAL * 6 / 10 ))
COL_A="$AUTH select public.collect_livestock_sale_receivable('$ORG','$RECOGNITION','$CASH',$AMOUNT,current_date,'تحصيل سباق أ','gf24-race-collection-a');"
COL_B="$AUTH select public.collect_livestock_sale_receivable('$ORG','$RECOGNITION','$CASH',$AMOUNT,current_date,'تحصيل سباق ب','gf24-race-collection-b');"
set +e
run_session "$COL_A" "$tmpdir/ca.log" & pa=$!
run_session "$COL_B" "$tmpdir/cb.log" & pb=$!
wait "$pa"; ca=$?
wait "$pb"; cb=$?
set -e
if ! { [[ "$ca" -eq 0 && "$cb" -ne 0 ]] || [[ "$ca" -ne 0 && "$cb" -eq 0 ]]; }; then
  echo "ERROR: collection ceiling race expected exactly one success; A=$ca B=$cb" >&2
  cat "$tmpdir/ca.log" "$tmpdir/cb.log" >&2
  exit 1
fi
COLLECTED="$(psql_value "select coalesce(sum(amount_minor_units),0) from public.livestock_sale_collections where recognition_id='$RECOGNITION'")"
OUTSTANDING="$(psql_value "select outstanding_receivable_minor_units from public.livestock_sales_read where recognition_id='$RECOGNITION'")"
if [[ "$COLLECTED" != "$AMOUNT" || "$OUTSTANDING" != "$((TOTAL-AMOUNT))" ]]; then
  echo "ERROR: collection race left collected=$COLLECTED outstanding=$OUTSTANDING total=$TOTAL" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Race 3 — idempotent duplicate purchase submissions write one PURCHASE_IN.
# ---------------------------------------------------------------------------
DUP_COHORT="$(provision_cohort 'دفعة سباق الشراء المكرر GF024' 20 'gf24-race-dup')"
PURCHASE_SQL="$AUTH select public.record_livestock_purchase('$ORG','$PROJECT','$BUYER','شراء سباق مكرر GF024','عقد مكرر',now(),'دليل مكرر',null,array['$DUP_COHORT'::uuid],array[5]::integer[],array[50000]::bigint[],'gf24-race-purchase-dup');"
set +e
run_session "$PURCHASE_SQL" "$tmpdir/d1.log" & pa=$!
run_session "$PURCHASE_SQL" "$tmpdir/d2.log" & pb=$!
wait "$pa"; da=$?
wait "$pb"; db=$?
set -e
if [[ "$da" -ne 0 || "$db" -ne 0 ]]; then
  echo "ERROR: idempotent duplicate purchase should succeed in both sessions (one effect)." >&2
  cat "$tmpdir/d1.log" "$tmpdir/d2.log" >&2
  exit 1
fi
DUP_PURCHASES="$(psql_value "select count(*) from public.livestock_purchases where idempotency_key='gf24-race-purchase-dup'")"
DUP_EVENTS="$(psql_value "select count(*) from public.livestock_quantity_events where cohort_id='$DUP_COHORT' and event_type='PURCHASE_IN'")"
if [[ "$DUP_PURCHASES" != '1' || "$DUP_EVENTS" != '1' ]]; then
  echo "ERROR: duplicate purchase wrote purchases=$DUP_PURCHASES events=$DUP_EVENTS (expected 1 each)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Race 4 — purchase vs sale as-of ordering: a same-day purchase cannot
# retroactively supply a same-day sale, and the ledger never goes negative.
# ---------------------------------------------------------------------------
ORDER_COHORT="$(provision_cohort 'دفعة سباق الترتيب GF024' 10 'gf24-race-order')"
psql_sql "$AUTH select public.create_livestock_sale('$ORG','$PROJECT','$BUYER','GF024-RACE-ORDER',null,current_date,'EGP',null,'دليل ترتيب',array['$ORDER_COHORT'::uuid],array[25]::integer[],array[8000]::bigint[],'gf24-race-order-sale');" >/dev/null
ORDER_SALE="$(psql_value "select id from public.livestock_sales where sale_reference='GF024-RACE-ORDER'")"
psql_sql "$AUTH select public.approve_livestock_sale('$ORG','$ORDER_SALE','gf24-race-order-approve');" >/dev/null

ORDER_PURCHASE="$AUTH select public.record_livestock_purchase('$ORG','$PROJECT','$BUYER','شراء ترتيب GF024',null,now(),null,null,array['$ORDER_COHORT'::uuid],array[30]::integer[],null,'gf24-race-order-purchase');"
ORDER_SALE_SQL="$AUTH select public.recognize_livestock_sale('$ORG','$ORDER_SALE',current_date,'تسليم ترتيب','gf24-race-order-recognize');"
set +e
run_session "$ORDER_PURCHASE" "$tmpdir/op.log" & pa=$!
run_session "$ORDER_SALE_SQL" "$tmpdir/os.log" & pb=$!
wait "$pa"; op=$?
wait "$pb"; os=$?
set -e
# The sale asks for 25 against an opening of 10. The purchase commits at
# now(), which is strictly AFTER the control-transfer instant (the transfer
# date at UTC midnight), so the sale must fail on the as-of ceiling even
# though the purchase commits. Nothing may go negative.
if [[ "$op" -ne 0 ]]; then
  echo 'ERROR: purchase in the ordering race unexpectedly failed.' >&2; cat "$tmpdir/op.log" >&2; exit 1
fi
if [[ "$os" -eq 0 ]]; then
  echo 'ERROR: the same-day sale was supplied by a later-dated purchase.' >&2; cat "$tmpdir/os.log" >&2; exit 1
fi
if ! grep -Eq 'insufficient livestock quantity' "$tmpdir/os.log"; then
  echo 'ERROR: the losing sale did not fail on the as-of quantity ceiling.' >&2; cat "$tmpdir/os.log" >&2; exit 1
fi
FINAL_QTY="$(quantity_of "$ORDER_COHORT")"
NEG="$(psql_value "select count(*) from public.livestock_cohort_quantity_rollforward where current_quantity < 0")"
if [[ "$NEG" != '0' ]]; then
  echo "ERROR: $NEG cohorts hold a negative derived quantity after the race." >&2; exit 1
fi
if [[ "$FINAL_QTY" != '40' ]]; then
  echo "ERROR: ordering race left an invalid balance: $FINAL_QTY (expected 40)." >&2; exit 1
fi

# Global invariant after every race.
INVARIANT="$(psql_value "select bool_and(
  r.current_quantity =
    (case when c.is_operational_as_of_now then r.opening_headcount else 0 end)
    + r.quantity_increase - r.quantity_decrease)
  from public.livestock_cohort_quantity_rollforward r
  join public.livestock_cohorts_read c on c.id = r.cohort_id")"
if [[ "$INVARIANT" != 't' ]]; then
  echo 'ERROR: the quantity rollforward invariant is violated after the races.' >&2
  exit 1
fi

echo 'GF-024 real multi-session commercial concurrency PASS: oversell, collection ceiling, idempotent duplicate purchase, and purchase/sale ordering races each serialize correctly; conservation and non-negativity hold.'
