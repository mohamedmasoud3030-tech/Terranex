#!/usr/bin/env bash
set -euo pipefail

# GF-016 / Harvest inventory concurrency.
#
# A real two-session race proves that two simultaneous outbound movements
# against the same Harvest Lot at the same Storage Location cannot overdraw
# it. The lot starts with 100 KG at Storage A; one request transfers 70 KG
# and a concurrent request transfers 60 KG. Exactly one must succeed and
# the location balance must never go negative.
#
# The lot row is locked FOR UPDATE by the movement command and again by the
# BEFORE INSERT trigger, so concurrent movements against the same lot
# serialize and re-check the available balance under the lock.

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
USER='00000000-0000-4000-8000-000000000001'

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF013-AG-A' limit 1")"
FIELD="$(psql_value "select id from public.fields where organization_id='$ORG' and identifier='حقل شمال' limit 1")"
if [[ -z "$PROJECT" || -z "$FIELD" ]]; then
  echo 'ERROR: GF-016 concurrency fixture prerequisites missing (GF013-AG-A project / field).' >&2
  exit 1
fi

# Provision a dedicated harvest-ready cycle + assignment + storage locations.
CYCLE="$(psql_value "select id from public.crop_cycles where organization_id='$ORG' and season_reference='موسم 2027-CONC' limit 1")"
if [[ -z "$CYCLE" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.create_crop_cycle('$ORG','$PROJECT','ذرة','هجين','موسم 2027-CONC',date '2027-05-01',date '2027-09-01',null,null,'s16-conc-cycle');"
  CYCLE="$(psql_value "select id from public.crop_cycles where organization_id='$ORG' and season_reference='موسم 2027-CONC' limit 1")"
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.transition_crop_cycle('$ORG','$CYCLE','PLANNED','ESTABLISHED','تجهيز سباق','ev1','s16-conc-e1');
    select public.transition_crop_cycle('$ORG','$CYCLE','ESTABLISHED','GROWING','نمو سباق','ev2','s16-conc-e2');
    select public.transition_crop_cycle('$ORG','$CYCLE','GROWING','HARVESTING','حصاد سباق','ev3','s16-conc-e3');"
fi
if [[ -z "$CYCLE" ]]; then
  echo 'ERROR: could not provision the GF-016 concurrency cycle.' >&2
  exit 1
fi

ASSIGN="$(psql_value "select id from public.crop_cycle_field_assignments where organization_id='$ORG' and crop_cycle_id='$CYCLE' and field_id='$FIELD' limit 1")"
if [[ -z "$ASSIGN" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.assign_crop_cycle_to_field('$ORG','$PROJECT','$CYCLE','$FIELD','4','FEDDAN',date '2027-05-01',date '2027-09-01','s16-conc-assign');"
  ASSIGN="$(psql_value "select id from public.crop_cycle_field_assignments where organization_id='$ORG' and crop_cycle_id='$CYCLE' and field_id='$FIELD' limit 1")"
fi
if [[ -z "$ASSIGN" ]]; then
  echo 'ERROR: could not provision the GF-016 concurrency assignment.' >&2
  exit 1
fi

STORAGE_A="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق أ' limit 1")"
if [[ -z "$STORAGE_A" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.create_storage_location('$ORG','$PROJECT','مخزن سباق أ','CONC-A',null,'s16-conc-store-a');"
  STORAGE_A="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق أ' limit 1")"
fi
STORAGE_B="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق ب' limit 1")"
if [[ -z "$STORAGE_B" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.create_storage_location('$ORG','$PROJECT','مخزن سباق ب','CONC-B',null,'s16-conc-store-b');"
  STORAGE_B="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق ب' limit 1")"
fi
STORAGE_C="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق ج' limit 1")"
if [[ -z "$STORAGE_C" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.create_storage_location('$ORG','$PROJECT','مخزن سباق ج','CONC-C',null,'s16-conc-store-c');"
  STORAGE_C="$(psql_value "select id from public.storage_locations where organization_id='$ORG' and name='مخزن سباق ج' limit 1")"
fi

# A harvest of 100 KG net lands at Storage A.
LOT="$(psql_value "select id from public.harvest_lots where organization_id='$ORG' and lot_reference='LOT-CONC-001' limit 1")"
if [[ -z "$LOT" ]]; then
  psql_sql "set request.jwt.claim.sub='$USER'; set role authenticated;
    select public.record_harvest_event('$ORG','$ASSIGN',date '2027-08-01','100','100','كجم',null,'LOT-CONC-001','$STORAGE_A',null,null,'s16-conc-harvest');"
  LOT="$(psql_value "select id from public.harvest_lots where organization_id='$ORG' and lot_reference='LOT-CONC-001' limit 1")"
fi
if [[ -z "$LOT" ]]; then
  echo 'ERROR: could not provision the GF-016 concurrency lot.' >&2
  exit 1
fi

BEFORE="$(psql_value "select public.harvest_lot_storage_balance('$LOT','$STORAGE_A')::text")"
if [[ "$BEFORE" != '100.000000' ]]; then
  echo "ERROR: concurrency lot balance is $BEFORE, expected 100.000000." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

TRANSFER_70="set request.jwt.claim.sub='$USER'; set role authenticated;
select public.transfer_harvest_inventory('$ORG','$LOT','$STORAGE_A','$STORAGE_B','70',date '2027-08-10',null,null,'s16-conc-transfer-70');"
TRANSFER_60="set request.jwt.claim.sub='$USER'; set role authenticated;
select public.transfer_harvest_inventory('$ORG','$LOT','$STORAGE_A','$STORAGE_C','60',date '2027-08-10',null,null,'s16-conc-transfer-60');"

set +e
run_session "$TRANSFER_70" "$tmpdir/t70.log" & pid_a=$!
run_session "$TRANSFER_60" "$tmpdir/t60.log" & pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

# Exactly one of the two concurrent outbound movements may succeed.
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "ERROR: concurrent harvest transfers expected exactly one success; A=$status_a B=$status_b" >&2
  cat "$tmpdir/t70.log" "$tmpdir/t60.log" >&2 || true
  exit 1
fi

A_BALANCE="$(psql_value "select public.harvest_lot_storage_balance('$LOT','$STORAGE_A')::text")"
TOTAL="$(psql_value "select public.harvest_lot_total_balance('$LOT')::text")"

# After the race the source location must never be negative and the total
# lot balance must be unchanged (a transfer never creates or destroys qty).
if [[ "$A_BALANCE" != '30.000000' && "$A_BALANCE" != '40.000000' ]]; then
  echo "ERROR: concurrency left an invalid source balance: $A_BALANCE" >&2
  exit 1
fi
if [[ "$TOTAL" != '100.000000' ]]; then
  echo "ERROR: concurrency altered the total lot balance: $TOTAL" >&2
  exit 1
fi

echo 'GF-016 harvest inventory concurrency PASS'
