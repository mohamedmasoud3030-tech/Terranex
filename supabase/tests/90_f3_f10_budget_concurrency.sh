#!/usr/bin/env bash
set -euo pipefail

# F4 real two-session proof: competing obligation authorizations cannot
# consume more than the budget ceiling of one treatment line. Each of the
# two obligations fits alone; both together exceed the ceiling, so exactly
# one authorization must succeed even when both transactions start at the
# same time. The per-budget-line advisory lock serializes check+post.

DB="${TERRANEX_TEST_DB:-terranex_test}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql() { if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$1" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$DB"; else printf '%s\n' "$1" | psql -v ON_ERROR_STOP=1 -q -d "$DB"; fi; }
psql_value() { if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$DB" -c "$1"; else psql -v ON_ERROR_STOP=1 -Atq -d "$DB" -c "$1"; fi; }
run_session() { psql_sql "$1" >"$2" 2>&1; }

ORG='90000000-0000-4000-8000-000000000001'
OWNER='90000000-0000-4000-8000-000000000001'
OWNER2='90000000-0000-4000-8000-000000000002'
MEMBER='90000000-0000-4000-8000-000000000003'

psql_sql "
insert into auth.users(id) values ('$OWNER'),('$OWNER2'),('$MEMBER') on conflict do nothing;
insert into public.organizations(id,name) values ('$ORG','منظمة سباق السقف') on conflict do nothing;
insert into public.memberships(organization_id,user_id,role) values
  ('$ORG','$OWNER','OWNER'),('$ORG','$OWNER2','OWNER'),('$ORG','$MEMBER','MEMBER')
  on conflict (organization_id,user_id) do nothing;
set request.jwt.claim.sub='$OWNER';
select public.create_investment_project('$ORG','مشروع سباق السقف','BUD-RACE','مشروع اختبار سباق السقف');
select public.create_party('$ORG','مورد سباق السقف','ORGANIZATION');
select public.create_project_cash_account('$ORG',
  (select id from public.investment_projects where organization_id='$ORG' and internal_reference='BUD-RACE'),
  'حساب سباق السقف','EGP');
select public.s6_create_accounting_period('$ORG',
  (select id from public.investment_projects where organization_id='$ORG' and internal_reference='BUD-RACE'),
  current_date - 30, current_date + 30);
"

PROJECT="$(psql_value "select id from public.investment_projects where organization_id='$ORG' and internal_reference='BUD-RACE'")"
PARTY="$(psql_value "select id from public.parties where organization_id='$ORG' and legal_name='مورد سباق السقف'")"

psql_sql "set request.jwt.claim.sub='$MEMBER'; set role authenticated;
select public.create_cost_obligation('$ORG','$PROJECT','$PARTY','التزام سباق أ',60000,'EGP',current_date,'EXPENSE','s90-obligation-A');
select public.create_cost_obligation('$ORG','$PROJECT','$PARTY','التزام سباق ب',60000,'EGP',current_date,'EXPENSE','s90-obligation-B');
select public.f4_create_project_budget('$ORG','$PROJECT',current_date - 30,current_date + 30,'ORIGINAL','EGP','موازنة سباق السقف',null,
  '[{\"cost_treatment\":\"EXPENSE\",\"amount_minor_units\":100000}]'::jsonb,'s90-budget-create');"
BUDGET="$(psql_value "select id from public.project_budgets where idempotency_key='s90-budget-create'")"
OBL_A="$(psql_value "select id from public.cost_obligations where idempotency_key='s90-obligation-A'")"
OBL_B="$(psql_value "select id from public.cost_obligations where idempotency_key='s90-obligation-B'")"

psql_sql "set request.jwt.claim.sub='$OWNER'; set role authenticated;
select public.f4_approve_project_budget('$ORG','$BUDGET','s90-budget-approve');"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
AUTH_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.authorize_cost_obligation('$ORG','$OBL_A','s90-auth-A');"
AUTH_B="set request.jwt.claim.sub='$OWNER2'; set role authenticated; select public.authorize_cost_obligation('$ORG','$OBL_B','s90-auth-B');"
set +e
run_session "$AUTH_A" "$tmpdir/a.log" & a=$!
run_session "$AUTH_B" "$tmpdir/b.log" & b=$!
wait "$a"; sa=$?; wait "$b"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: competing authorizations expected exactly one success; A=$sa B=$sb" >&2
  cat "$tmpdir/a.log" "$tmpdir/b.log" >&2 || true
  exit 1
fi
AUTHORIZED="$(psql_value "select count(*) from public.cost_obligations where id in ('$OBL_A','$OBL_B') and status='AUTHORIZED'")"
[[ "$AUTHORIZED" == '1' ]] || { echo "ERROR: authorized race count $AUTHORIZED" >&2; exit 1; }

COMMITTED="$(psql_value "select sum(amount_minor_units) from public.cost_obligations where organization_id='$ORG' and status='AUTHORIZED' and cost_treatment='EXPENSE'")"
[[ "$COMMITTED" == '60000' ]] || { echo "ERROR: committed $COMMITTED exceeds expectation" >&2; exit 1; }

echo 'F4 budget ceiling concurrency PASS'
