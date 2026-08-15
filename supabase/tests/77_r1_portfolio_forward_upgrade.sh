#!/usr/bin/env bash
# R1 — Portfolio Foundation forward-upgrade verification.
#
# Replays every merged migration EXCEPT the R1 family, asserts the
# boundary is genuine (no portfolio primitive exists yet), seeds one
# Real Estate, one Agriculture (with a Farm), and one Livestock project,
# then applies the R1 migration and asserts:
#
#   * every pre-R1 project and sector object survives byte-for-byte on
#     the identity columns that matter (id, name, sector, lifecycle);
#   * no project silently acquires a parent portfolio (economically and
#     operationally neutral backfill = none);
#   * every R1 primitive exists;
#   * the R1 workflow operates against the upgraded database.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_r1_upgrade"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
export PGPASSWORD
CONTAINER="${TERRANEX_DB_CONTAINER:-}"

psql_db() {
  local db="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -q -U "$PGUSER" -d "$db"
  else
    psql -v ON_ERROR_STOP=1 -q -d "$db"
  fi
}
psql_cmd() {
  local db="$1" sql="$2"
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -Atq -U "$PGUSER" -d "$db" -c "$sql"
  else
    psql -v ON_ERROR_STOP=1 -Atq -d "$db" -c "$sql"
  fi
}
cleanup() {
  psql_cmd postgres "select pg_terminate_backend(pid) from pg_stat_activity where datname='$UPGRADE_DB' and pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  psql_cmd postgres "drop database if exists \"$UPGRADE_DB\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
psql_cmd postgres "create database \"$UPGRADE_DB\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' \
  "$ROOT/supabase/tests/00_supabase_shim.sql" | psql_db "$UPGRADE_DB"

# Pre-R1 boundary: every migration except the R1 family.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260815030000*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

# Fixture organization, owner, and sector projects created through the
# canonical server-authoritative commands.
psql_cmd "$UPGRADE_DB" "insert into auth.users(id) values ('00000000-0000-4000-8000-000000000098') on conflict do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000098','منظمة ترقية ر1') on conflict (id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000098','00000000-0000-4000-8000-000000000098','OWNER') on conflict (organization_id,user_id) do nothing;" >/dev/null

psql_db "$UPGRADE_DB" <<'SQL' >/dev/null
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000098', false);
set role authenticated;
select public.create_investment_project('10000000-0000-4000-8000-000000000098','برج الترقية العقاري','R1-UPG-RE',null,'REAL_ESTATE') as upg_re \gset
select public.create_investment_project('10000000-0000-4000-8000-000000000098','مزرعة الترقية','R1-UPG-AG',null,'AGRICULTURE') as upg_ag \gset
select public.create_investment_project('10000000-0000-4000-8000-000000000098','حظيرة الترقية','R1-UPG-LS',null,'LIVESTOCK') as upg_ls \gset
select public.create_farm('10000000-0000-4000-8000-000000000098', :'upg_ag', 'مزرعة ما قبل الترقية', 'R1-UPG-FARM', null, null, 'Africa/Cairo', null, 'r1-upg-farm-001') as upg_farm \gset
reset role;
SQL

BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.investment_portfolios') is null
    and to_regclass('public.investment_portfolio_state_history') is null
    and to_regclass('public.portfolio_project_assignments') is null
    and to_regprocedure('public.create_investment_portfolio(uuid,text,text,uuid,text)') is null
    and to_regprocedure('public.assign_project_to_portfolio(uuid,uuid,uuid,text)') is null
    and to_regclass('public.investment_projects') is not null
    and to_regclass('public.farms') is not null
    and to_regclass('public.audit_events') is not null
  )::text
")
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-R1 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

FINGERPRINT_BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select string_agg(id::text || ':' || name || ':' || sector || ':' || lifecycle_state, '|' order by internal_reference)
  from public.investment_projects
  where internal_reference in ('R1-UPG-RE','R1-UPG-AG','R1-UPG-LS')
")
FARM_BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select id::text || ':' || name || ':' || timezone from public.farms
  where internal_reference = 'R1-UPG-FARM'
")

r1_migrations=(
  "$ROOT/supabase/migrations/20260815030000_r1_portfolio_foundation.sql"
)
for file in "${r1_migrations[@]}"; do
  if [[ ! -e "$file" ]]; then
    echo "ERROR: missing R1 migration $file" >&2
    exit 1
  fi
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.investment_portfolios') is not null
    and to_regclass('public.investment_portfolio_state_history') is not null
    and to_regclass('public.portfolio_project_assignments') is not null
    and to_regprocedure('public.create_investment_portfolio(uuid,text,text,uuid,text)') is not null
    and to_regprocedure('public.update_investment_portfolio_metadata(uuid,uuid,text,text,uuid,text)') is not null
    and to_regprocedure('public.transition_investment_portfolio(uuid,uuid,text,text,text,text)') is not null
    and to_regprocedure('public.assign_project_to_portfolio(uuid,uuid,uuid,text)') is not null
    and to_regprocedure('public.remove_project_from_portfolio(uuid,uuid,uuid,text,text)') is not null
    and to_regprocedure('public.move_project_to_portfolio(uuid,uuid,uuid,text,text)') is not null
  )::text
")
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: R1 forward-upgrade did not produce all expected primitives (AFTER=$AFTER)" >&2
  exit 1
fi

# Every pre-R1 project and sector object survives untouched.
FINGERPRINT_AFTER=$(psql_cmd "$UPGRADE_DB" "
  select string_agg(id::text || ':' || name || ':' || sector || ':' || lifecycle_state, '|' order by internal_reference)
  from public.investment_projects
  where internal_reference in ('R1-UPG-RE','R1-UPG-AG','R1-UPG-LS')
")
if [[ "$FINGERPRINT_BEFORE" != "$FINGERPRINT_AFTER" ]]; then
  echo "ERROR: pre-R1 project fingerprints changed by the upgrade" >&2
  echo "  before: $FINGERPRINT_BEFORE" >&2
  echo "  after:  $FINGERPRINT_AFTER" >&2
  exit 1
fi

FARM_AFTER=$(psql_cmd "$UPGRADE_DB" "
  select id::text || ':' || name || ':' || timezone from public.farms
  where internal_reference = 'R1-UPG-FARM'
")
if [[ "$FARM_BEFORE" != "$FARM_AFTER" ]]; then
  echo "ERROR: pre-R1 Agriculture Farm changed by the upgrade" >&2
  exit 1
fi

# Economically neutral backfill: no project silently gains a parent.
ASSIGNED=$(psql_cmd "$UPGRADE_DB" "select count(*) from public.portfolio_project_assignments")
if [[ "$ASSIGNED" != "0" ]]; then
  echo "ERROR: R1 upgrade fabricated portfolio memberships (count=$ASSIGNED)" >&2
  exit 1
fi

# The R1 workflow operates against the upgraded database.
psql_db "$UPGRADE_DB" <<'SQL'
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000098', false);
set role authenticated;
select public.create_investment_portfolio('10000000-0000-4000-8000-000000000098','محفظة ما بعد الترقية','غرض إداري',null,'r1-upg-pf-001') as upg_pf \gset
select public.transition_investment_portfolio('10000000-0000-4000-8000-000000000098', :'upg_pf', 'DRAFT', 'ACTIVE', 'تنشيط بعد الترقية', 'r1-upg-act-001') as upg_act \gset
select public.assign_project_to_portfolio('10000000-0000-4000-8000-000000000098', :'upg_pf',
  (select id from public.investment_projects where internal_reference='R1-UPG-RE'), 'r1-upg-assign-001') as upg_assign \gset
select 1/case when (
  select count(*) from public.portfolio_project_assignments
   where portfolio_id = :'upg_pf' and removed_at is null
) = 1 then 1 else 0 end as r1_upgraded_workflow_membership;
reset role;
SQL

echo "R1 forward-upgrade PASS: pre-R1 Real Estate/Agriculture/Livestock projects and Farm preserved exactly; no fabricated memberships; all R1 primitives created; R1 workflow verified on the upgraded database."
