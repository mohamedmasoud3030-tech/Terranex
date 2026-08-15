#!/usr/bin/env bash
set -euo pipefail

# R4 two-session proof for immutable evidence/storage referential integrity.
#
# 1) Registration wins while DELETE has already evaluated an unregistered-object
#    RLS snapshot: DELETE must still fail at the FK boundary and the object must
#    remain present.
# 2) DELETE wins first: registration must fail closed because the locked Storage
#    object no longer exists, and no evidence metadata may be created.
DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql() { if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$1" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"; else printf '%s\n' "$1" | psql -v ON_ERROR_STOP=1 -q -d "$DB"; fi; }
psql_value() { if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$1"; else psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$1"; fi; }
run_session() { psql_sql "$1" >"$2" 2>&1; }

ORG='10000000-0000-4000-8000-000000000001'
MEMBER='00000000-0000-4000-8000-000000000003'
PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='GF025-PROJ'")"
PO="$(psql_value "select id from public.purchase_orders where organization_id='$ORG' and internal_reference='PO-R4-EVIDENCE'")"
[[ -n "$PROJECT" && -n "$PO" ]] || { echo 'ERROR: R4 evidence concurrency fixtures missing' >&2; exit 1; }

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Race A: registration acquires the Storage row first and holds the transaction
# open. DELETE begins while the version is still uncommitted, so its RLS
# predicate can observe the old "unregistered" snapshot. The FK must still make
# the DELETE lose after registration commits.
# ---------------------------------------------------------------------------
OBJ_A="$ORG/$PROJECT/86000000-0000-4000-8000-000000000001"
psql_sql "set request.jwt.claim.sub='$MEMBER'; set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence','$OBJ_A',jsonb_build_object('size',100,'mimetype','application/pdf'));
reset role;"

REGISTER_A="begin;
set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.register_procurement_evidence(
  '$ORG','$PROJECT',null,'PURCHASE_ORDER','s86 registration wins evidence',
  '$OBJ_A','s86-register-wins.pdf','application/pdf',100,repeat('e',64),
  '$PO',null,null,'s86-register-wins');
select pg_sleep(1);
commit;"
DELETE_A="select pg_sleep(0.2);
set request.jwt.claim.sub='$MEMBER'; set role authenticated;
delete from storage.objects where bucket_id='procurement-evidence' and name='$OBJ_A';"

set +e
run_session "$REGISTER_A" "$tmpdir/register-a.log" & ra=$!
run_session "$DELETE_A" "$tmpdir/delete-a.log" & da=$!
wait "$ra"; sra=$?
wait "$da"; sda=$?
set -e
if [[ "$sra" -ne 0 || "$sda" -eq 0 ]]; then
  echo "ERROR: registration-wins race expected register=success delete=failure; register=$sra delete=$sda" >&2
  cat "$tmpdir/register-a.log" "$tmpdir/delete-a.log" >&2 || true
  exit 1
fi
OBJ_A_COUNT="$(psql_value "select count(*) from storage.objects where bucket_id='procurement-evidence' and name='$OBJ_A'")"
VER_A_COUNT="$(psql_value "select count(*) from public.procurement_evidence_versions where storage_bucket='procurement-evidence' and storage_object_name='$OBJ_A'")"
LINK_A_COUNT="$(psql_value "select count(*) from public.procurement_evidence_links where organization_id='$ORG' and idempotency_key='s86-register-wins'")"
[[ "$OBJ_A_COUNT" == '1' && "$VER_A_COUNT" == '1' && "$LINK_A_COUNT" == '1' ]] || {
  echo "ERROR: registration-wins race left object/version/link counts $OBJ_A_COUNT/$VER_A_COUNT/$LINK_A_COUNT" >&2; exit 1;
}

# ---------------------------------------------------------------------------
# Race B: DELETE obtains the row first and holds its transaction open.
# Registration starts while the delete is uncommitted and must fail closed after
# the delete commits; no immutable metadata can point at a missing object.
# ---------------------------------------------------------------------------
OBJ_B="$ORG/$PROJECT/86000000-0000-4000-8000-000000000002"
psql_sql "set request.jwt.claim.sub='$MEMBER'; set role authenticated;
insert into storage.objects(id,bucket_id,name,metadata) values (
  gen_random_uuid(),'procurement-evidence','$OBJ_B',jsonb_build_object('size',100,'mimetype','application/pdf'));
reset role;"

DELETE_B="begin;
set request.jwt.claim.sub='$MEMBER'; set role authenticated;
delete from storage.objects where bucket_id='procurement-evidence' and name='$OBJ_B';
select pg_sleep(1);
commit;"
REGISTER_B="select pg_sleep(0.2);
set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.register_procurement_evidence(
  '$ORG','$PROJECT',null,'PURCHASE_ORDER','s86 delete wins evidence',
  '$OBJ_B','s86-delete-wins.pdf','application/pdf',100,repeat('f',64),
  '$PO',null,null,'s86-delete-wins');"

set +e
run_session "$DELETE_B" "$tmpdir/delete-b.log" & db=$!
run_session "$REGISTER_B" "$tmpdir/register-b.log" & rb=$!
wait "$db"; sdb=$?
wait "$rb"; srb=$?
set -e
if [[ "$sdb" -ne 0 || "$srb" -eq 0 ]]; then
  echo "ERROR: delete-wins race expected delete=success register=failure; delete=$sdb register=$srb" >&2
  cat "$tmpdir/delete-b.log" "$tmpdir/register-b.log" >&2 || true
  exit 1
fi
OBJ_B_COUNT="$(psql_value "select count(*) from storage.objects where bucket_id='procurement-evidence' and name='$OBJ_B'")"
VER_B_COUNT="$(psql_value "select count(*) from public.procurement_evidence_versions where storage_bucket='procurement-evidence' and storage_object_name='$OBJ_B'")"
LINK_B_COUNT="$(psql_value "select count(*) from public.procurement_evidence_links where organization_id='$ORG' and idempotency_key='s86-delete-wins'")"
[[ "$OBJ_B_COUNT" == '0' && "$VER_B_COUNT" == '0' && "$LINK_B_COUNT" == '0' ]] || {
  echo "ERROR: delete-wins race left object/version/link counts $OBJ_B_COUNT/$VER_B_COUNT/$LINK_B_COUNT" >&2; exit 1;
}

echo 'R4 procurement evidence registration/delete concurrency PASS'
