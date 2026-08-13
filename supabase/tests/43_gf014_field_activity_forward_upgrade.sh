#!/usr/bin/env bash
# GF-014 / Field Activity forward-upgrade verification.
#
# Apply every migration except GF-014, seed surviving Real Estate and
# GF-013 Agriculture rows, then apply GF-014 and prove those rows are
# unchanged while the new field_activities primitives exist.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${TERRANEX_TEST_DB:-terranex_test}"
UPGRADE_DB="${SOURCE_DB}_gf014_upgrade"
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

for file in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$file")" in
    20260813001100*.sql) continue ;;
  esac
  psql_db "$UPGRADE_DB" < "$file"
done

psql_cmd "$UPGRADE_DB" "insert into auth.users(id) values ('00000000-0000-4000-8000-000000000099') on conflict do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.organizations(id,name) values ('10000000-0000-4000-8000-000000000099','منظمة ترقية') on conflict (id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "insert into public.memberships(organization_id,user_id,role) values ('10000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099','OWNER') on conflict (organization_id,user_id) do nothing;" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000099','مشروع ترقية عقاري','GF014-UPGRADE-RE','REAL_ESTATE','row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.investment_projects(id, organization_id, name, internal_reference, sector, description)
  values ('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000099','مشروع ترقية زراعي','GF014-UPGRADE-AG','AGRICULTURE','GF-013 row that must survive')
  on conflict (id) do nothing;
" >/dev/null
psql_cmd "$UPGRADE_DB" "
  insert into public.farms(id, organization_id, project_id, name, internal_reference, timezone, created_by, idempotency_key, request_hash)
  values (
    '30000000-0000-4000-8000-000000000011',
    '10000000-0000-4000-8000-000000000099',
    '30000000-0000-4000-8000-000000000002',
    'مزرعة الترقية','UPG-FARM','Africa/Cairo',
    '00000000-0000-4000-8000-000000000099','upgrade-farm-001',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  ) on conflict do nothing;
" >/dev/null

BEFORE=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.field_activities') is null
    and to_regprocedure('public.create_field_activity(uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text,text,text)') is null
    and to_regclass('public.farms') is not null
    and to_regclass('public.crop_cycles') is not null
    and to_regclass('public.property_assets') is not null
    and (select count(*) from public.investment_projects where id = '30000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE') = 1
    and (select count(*) from public.farms where id = '30000000-0000-4000-8000-000000000011') = 1
  )::text
")
if [[ "$BEFORE" != "true" ]]; then
  echo "ERROR: pre-GF-014 boundary fixture is not genuine (BEFORE=$BEFORE)" >&2
  exit 1
fi

psql_db "$UPGRADE_DB" < "$ROOT/supabase/migrations/20260813001100_agriculture_field_activity.sql"

AFTER=$(psql_cmd "$UPGRADE_DB" "
  select (
    to_regclass('public.field_activities') is not null
    and to_regclass('public.field_activities_read') is not null
    and to_regprocedure('public.create_field_activity(uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text,text,text)') is not null
    and (select count(*) from public.investment_projects where id = '30000000-0000-4000-8000-000000000001' and sector = 'REAL_ESTATE' and name = 'مشروع ترقية عقاري') = 1
    and (select count(*) from public.investment_projects where id = '30000000-0000-4000-8000-000000000002' and sector = 'AGRICULTURE') = 1
    and (select count(*) from public.farms where id = '30000000-0000-4000-8000-000000000011' and name = 'مزرعة الترقية') = 1
  )::text
")
if [[ "$AFTER" != "true" ]]; then
  echo "ERROR: GF-014 forward-upgrade did not preserve prior rows or add primitives (AFTER=$AFTER)" >&2
  exit 1
fi

echo "GF-014 forward-upgrade: field_activities present; Real Estate and GF-013 Agriculture rows preserved."
