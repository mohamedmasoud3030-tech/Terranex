#!/usr/bin/env bash
# S4 concurrency tests: sale recognition and collection serialization.
# Requires a running PostgreSQL 16 with all migrations applied.
set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
PGDATABASE="${PGDATABASE:-terranex_test}"

run_sql() {
  PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -t -A -c "$1"
}

run_session() {
  local sql="$1"
  local session_name="$2"
  PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -c "$sql" 2>&1 | tee "/tmp/${session_name}.log" &
  echo $!
}

assert_one_success() {
  local pid_a="$1"
  local pid_b="$2"
  local name="$3"
  wait "$pid_a" 2>/dev/null && local exit_a=0 || local exit_a=$?
  wait "$pid_b" 2>/dev/null && local exit_b=0 || local exit_b=$?
  local successes=$(( (exit_a == 0 ? 1 : 0) + (exit_b == 0 ? 1 : 0) ))
  if [ "$successes" -ne 1 ]; then
    echo "FAIL: $name expected exactly one success, got $successes (A=$exit_a, B=$exit_b)"
    cat "/tmp/conc_sale_a.log" 2>/dev/null || true
    cat "/tmp/conc_sale_b.log" 2>/dev/null || true
    exit 1
  fi
  echo "PASS: $name (one succeeded, one failed as expected)"
}

# Setup test data.
run_sql "
do \$\$
declare
  v_user uuid := 'c0000000-0000-4000-8000-000000000001';
  v_org uuid; v_project uuid; v_asset uuid; v_buyer uuid; v_disp uuid;
begin
  insert into auth.users(id, email) values (v_user, 'conc@test.com') on conflict do nothing;
  insert into public.organizations(name) values ('منظمة اختبار التزامن') returning id into v_org;
  insert into public.memberships(organization_id, user_id, role) values (v_org, v_user, 'OWNER');
  insert into public.investment_projects(organization_id, name, sector) values (v_org, 'مشروع التزامن', 'REAL_ESTATE') returning id into v_project;
  insert into public.parties(organization_id, legal_name, party_type) values (v_org, 'مشتري التزامن', 'PERSON') returning id into v_buyer;

  perform public.create_property_asset(v_org, v_project, 'أرض التزامن', 'DEVELOP_SELL', 'القاهرة', 'CLEAR', '2026-01-01', 500000000, 'EGP', 'conc-asset-001');
  select id into v_asset from public.property_assets where idempotency_key = 'conc-asset-001' and organization_id = v_org;

  perform public.record_property_cost_item(v_org, v_project, v_asset, null, 'تطوير', true, 100000000, 'EGP', 'تطوير', '2026-02-01', null, 'conc-cost-001');

  perform public.create_disposition(v_org, v_project, v_asset, v_buyer, 2000000000, 'EGP', '2026-06-01', 50000000, 'عقد-تزامن', null, 'conc-disp-001');
  select id into v_disp from public.dispositions where idempotency_key = 'conc-disp-001' and organization_id = v_org;
  perform public.approve_disposition(v_org, v_disp);

  perform set_config('test.conc_org', v_org::text, false);
  perform set_config('test.conc_project', v_project::text, false);
  perform set_config('test.conc_disp', v_disp::text, false);
end \$\$;
"

CONC_ORG=$(run_sql "select current_setting('test.conc_org')")
CONC_PROJECT=$(run_sql "select current_setting('test.conc_project')")
CONC_DISP=$(run_sql "select current_setting('test.conc_disp')")

echo "=== Concurrent sale recognition test ==="
echo "Testing that two concurrent recognize_sale calls on the same disposition produce exactly one sale recognition."

SQL_CONC_SALE_A="select public.recognize_sale('${CONC_ORG}'::uuid, '${CONC_PROJECT}'::uuid, '${CONC_DISP}'::uuid, '2026-07-01', 'conc-sale-001');"
SQL_CONC_SALE_B="select public.recognize_sale('${CONC_ORG}'::uuid, '${CONC_PROJECT}'::uuid, '${CONC_DISP}'::uuid, '2026-07-01', 'conc-sale-001');"

pid_a=$(run_session "$SQL_CONC_SALE_A" "conc_sale_a")
pid_b=$(run_session "$SQL_CONC_SALE_B" "conc_sale_b")
assert_one_success "$pid_a" "$pid_b" "concurrent sale recognition"

# Verify only one sale recognition exists.
count=$(run_sql "select count(*) from public.sale_recognitions where organization_id = '${CONC_ORG}'::uuid and disposition_id = '${CONC_DISP}'::uuid;")
if [ "$count" -ne "1" ]; then
  echo "FAIL: expected 1 sale recognition, got $count"
  exit 1
fi
echo "PASS: exactly one sale recognition exists"

# Setup for collection concurrency test.
run_sql "
do \$\$
declare
  v_org uuid := '${CONC_ORG}'::uuid;
  v_sale uuid; v_receivable uuid; v_cash uuid;
begin
  select id into v_sale from public.sale_recognitions where disposition_id = '${CONC_DISP}'::uuid and organization_id = v_org;
  select id into v_receivable from public.sale_receivables where sale_recognition_id = v_sale;
  select id into v_cash from public.financial_accounts where organization_id = v_org and semantic_role = 'cash' and currency = 'EGP';
  if v_cash is null then
    select public.ensure_financial_account(v_org, 'cash', 'النقدية', 'EGP') into v_cash;
  end if;
  perform set_config('test.conc_receivable', v_receivable::text, false);
  perform set_config('test.conc_cash', v_cash::text, false);
end \$\$;
"

CONC_RECEIVABLE=$(run_sql "select current_setting('test.conc_receivable')")
CONC_CASH=$(run_sql "select current_setting('test.conc_cash')")

echo ""
echo "=== Concurrent collection test ==="
echo "Testing that two concurrent collections cannot exceed the receivable."

SQL_CONC_COLL_A="select public.record_collection('${CONC_ORG}'::uuid, '${CONC_PROJECT}'::uuid, '${CONC_RECEIVABLE}'::uuid, 1500000000::bigint, 'EGP', '2026-08-01', '${CONC_CASH}'::uuid, 'conc-coll-001');"
SQL_CONC_COLL_B="select public.record_collection('${CONC_ORG}'::uuid, '${CONC_PROJECT}'::uuid, '${CONC_RECEIVABLE}'::uuid, 1500000000::bigint, 'EGP', '2026-08-01', '${CONC_CASH}'::uuid, 'conc-coll-002');"

pid_a=$(run_session "$SQL_CONC_COLL_A" "conc_coll_a")
pid_b=$(run_session "$SQL_CONC_COLL_B" "conc_coll_b")
assert_one_success "$pid_a" "$pid_b" "concurrent collection (one must fail: total would exceed receivable)"

# Verify total collections do not exceed receivable.
total=$(run_sql "select coalesce(sum(collection_minor_units), 0) from public.collections where sale_receivable_id = '${CONC_RECEIVABLE}'::uuid;")
receivable=$(run_sql "select receivable_minor_units from public.sale_receivables where id = '${CONC_RECEIVABLE}'::uuid;")
if [ "$total" -gt "$receivable" ]; then
  echo "FAIL: total collections ($total) exceed receivable ($receivable)"
  exit 1
fi
echo "PASS: total collections ($total) <= receivable ($receivable)"

echo ""
echo "All S4 concurrency tests passed."
