#!/usr/bin/env bash
set -euo pipefail
DB="${TERRANEX_TEST_DB:-terranex_test}"; PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}" PGUSER
CONTAINER="${TERRANEX_DB_CONTAINER:-}"
psql_sql(){ local sql="$1"; if [[ -n "$CONTAINER" ]]; then printf '%s\n' "$sql" | docker exec -i "$CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB"; else printf '%s\n' "$sql" | psql -q -v ON_ERROR_STOP=1 -d "$DB"; fi; }
psql_value(){ local sql="$1"; if [[ -n "$CONTAINER" ]]; then docker exec -i "$CONTAINER" psql -Atq -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$DB" -c "$sql"; else psql -Atq -v ON_ERROR_STOP=1 -d "$DB" -c "$sql"; fi; }
run_session(){ psql_sql "$1" >"$2" 2>&1; }
ORG='10000000-0000-4000-8000-000000000001'; OWNER='00000000-0000-4000-8000-000000000001'
PROJECT="$(psql_value "select id from public.investment_projects where internal_reference='GF013-AG-A'")"
SOURCE="$(psql_value "select jl.id from public.journal_lines jl join public.journal_batches jb on jb.id=jl.batch_id join public.cost_obligations o on o.id=jb.source_id join public.semantic_accounts sa on sa.id=jl.account_id where o.idempotency_key='s19-cost-obligation' and sa.role='PROJECT_EXPENSE'")"
CYCLE_A="$(psql_value "select id from public.crop_cycles where season_reference='موسم 2027-HV'")"
CYCLE_B="$(psql_value "select id from public.crop_cycles where season_reference='موسم 2027-REPLAY'")"
# The functional suite explicitly reversed its 60,000 attribution, restoring
# all 100,000 source units. Two independent 70,000 requests cannot both win.
SQL_A="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.attribute_crop_cycle_cost('$ORG','$PROJECT','$CYCLE_A',null,'$SOURCE',70000,'OTHER','سياسة سباق التكلفة','دليل سباق أ','s19-race-cost-a');"
SQL_B="set request.jwt.claim.sub='$OWNER'; set role authenticated; select public.attribute_crop_cycle_cost('$ORG','$PROJECT','$CYCLE_B',null,'$SOURCE',70000,'OTHER','سياسة سباق التكلفة','دليل سباق ب','s19-race-cost-b');"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
set +e
run_session "$SQL_A" "$tmp/a.log" & pa=$!
run_session "$SQL_B" "$tmp/b.log" & pb=$!
wait "$pa"; sa=$?; wait "$pb"; sb=$?
set -e
if ! { [[ "$sa" -eq 0 && "$sb" -ne 0 ]] || [[ "$sa" -ne 0 && "$sb" -eq 0 ]]; }; then
  echo "ERROR: concurrent cost attribution expected exactly one success; A=$sa B=$sb" >&2
  cat "$tmp"/*.log >&2; exit 1
fi
ACTIVE="$(psql_value "select coalesce(sum(a.attributed_amount_minor_units),0) from public.crop_cycle_cost_attributions a where a.source_journal_line_id='$SOURCE' and a.reversal_of_attribution_id is null and not exists(select 1 from public.crop_cycle_cost_attributions r where r.reversal_of_attribution_id=a.id)")"
COUNT="$(psql_value "select count(*) from public.crop_cycle_cost_attributions where idempotency_key in ('s19-race-cost-a','s19-race-cost-b')")"
if [[ "$ACTIVE" != 70000 || "$COUNT" != 1 ]]; then
  echo "ERROR: cost ceiling race left active=$ACTIVE rows=$COUNT" >&2; exit 1
fi
echo 'GF-019 real two-session cost attribution ceiling concurrency PASS'
