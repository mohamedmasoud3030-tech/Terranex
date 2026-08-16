#!/usr/bin/env bash
# GF-013 / Agriculture forward-upgrade verification.
#
# Replay every merged migration up to and including the S6/S7/Gov/Sector
# boundary (everything before the GF-013 family), assert the boundary is
# genuine, then apply only the GF-013 family and assert that every prior
# Real Estate primitive survived and every new Agriculture primitive
# exists. Existing Real Estate rows in the fixture prove no regression
# to the established path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_gf013_upgrade"
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

# Pre-GF-013 boundary: every migration except the GF-013 family.
for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260813000900*.sql|20260813001000*.sql|20260813001010*.sql|20260813001100*.sql|20260814*.sql|20260815*.sql|20260816*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

# Seed a real Real Estate project + the permanent synthetic showcase so
# the post-upgrade invariant "the Real Estate showcase row still
# exists" can be checked.
psql_cmd "$UPGRADE_DB" "insert into auth.users(id) values ('00000000-0000-4000-8000-000000000099') on conflict do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000099','منظمة ترقية') on conflict (id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099','OWNER') on conflict (organization_id,user_id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000099','مشروع ترقية عقاري','GF013-UPGRADE-RE','REAL_ESTATE','row that must survive the upgrade')
  on conflict (id) do nothing;
" >/dev/null

BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.farms') is null
    and to_regclass('public.fields') is null
    and to_regclass('public.crop_cycles') is null
    and to_regclass('public.crop_cycle_field_assignments') is null
    and to_regclass('public.crop_cycle_state_history') is null
    and to_regclass('public.agriculture_project_profiles') is null
    and to_regprocedure('public.create_agriculture_profile(uuid,uuid,text,text)') is null
    and to_regprocedure('public.assign_crop_cycle_to_field(uuid,uuid,uuid,uuid,numeric,text,date,date,text)') is null
    and to_regprocedure('public.transition_crop_cycle(uuid,uuid,text,text,text,text,text)') is null
    and to_regprocedure('public.create_investment_project(uuid,text,text,text,text)') is null
    and to_regclass('public.property_assets') is not null
    and to_regclass('public.cost_obligations') is not null
    and to_regclass('public.close_runs') is not null
  )::text
")
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-GF-013 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

gf013_migrations=(
  "$ROOT/supabase/migrations/20260813000900_sector_aware_project.sql"
  "$ROOT/supabase/migrations/20260813001000_agriculture_foundation.sql"
  "$ROOT/supabase/migrations/20260813001010_agriculture_field_area_invariant.sql"
)
for file in "${gf013_migrations[@]}"; do
  if [[ ! -e "$file" ]]; then
    echo "ERROR: missing GF-013 migration $file" >&2
    exit 1
  fi
  psql_db "$UPGRADE_DB" < "$file"
done

AFTER=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.agriculture_project_profiles') is not null
    and to_regclass('public.farms') is not null
    and to_regclass('public.fields') is not null
    and to_regclass('public.crop_cycles') is not null
    and to_regclass('public.crop_cycle_field_assignments') is not null
    and to_regclass('public.crop_cycle_state_history') is not null
    and to_regprocedure('public.create_agriculture_profile(uuid,uuid,text,text)') is not null
    and to_regprocedure('public.create_farm(uuid,uuid,text,text,text,text,text,text,text)') is not null
    and to_regprocedure('public.create_field(uuid,uuid,uuid,text,numeric,text,text,text,text)') is not null
    and to_regprocedure('public.create_crop_cycle(uuid,uuid,text,text,text,date,date,numeric,text,text)') is not null
    and to_regprocedure('public.assign_crop_cycle_to_field(uuid,uuid,uuid,uuid,numeric,text,date,date,text)') is not null
    and to_regprocedure('public.transition_crop_cycle(uuid,uuid,text,text,text,text,text)') is not null
    and to_regprocedure('public.create_investment_project(uuid,text,text,text,text)') is not null
    and to_regprocedure('public.create_investment_project(uuid,text,text,text)') is not null
  )::text
")
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: GF-013 forward-upgrade did not produce all expected primitives (AFTER=$AFTER)" >&2
  exit 1
fi

# Real Estate row must survive the upgrade untouched.
SURVIVED=$(psql_cmd "$UPGRADE_DB" "
  select (count(*) = 1 and bool_and(sector = 'REAL_ESTATE'))::text
  from public.investment_projects
  where id = '30000000-0000-4000-8000-000000000001'::uuid
")
if [[ "$SURVIVED" != "true" ]]; then
  echo "ERROR: pre-existing Real Estate row did not survive the GF-013 forward upgrade (SURVIVED=$SURVIVED)" >&2
  exit 1
fi

# Sector vocabulary must have grown to include AGRICULTURE.
SECTOR_CHECK=$(psql_cmd "$UPGRADE_DB" "
  select pg_get_constraintdef(oid) like '%AGRICULTURE%'
  from pg_constraint
  where conname = 'investment_projects_sector_check'
")
if [[ "$SECTOR_CHECK" != "t" ]]; then
  echo "ERROR: investment_projects_sector_check did not accept AGRICULTURE after upgrade" >&2
  exit 1
fi

echo "GF-013 forward-upgrade: all primitives present, Real Estate row preserved, sector vocabulary expanded."
