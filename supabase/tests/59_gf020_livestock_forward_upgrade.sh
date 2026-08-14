#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; DB="${TERRANEX_TEST_DB:-terranex_test}"; UP="${DB}_gf020_upgrade"; PGUSER="${PGUSER:-postgres}"; export PGPASSWORD="${PGPASSWORD:-postgres}" PGUSER; C="${TERRANEX_DB_CONTAINER:-}"
if [[ -n "$C" ]];then pp(){ docker exec -i "$C" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d postgres "$@";};pd(){ local d="$1";shift;docker exec -i "$C" psql -q -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$d" "$@";};else pp(){ psql -q -v ON_ERROR_STOP=1 -d postgres "$@";};pd(){ local d="$1";shift;psql -q -v ON_ERROR_STOP=1 -d "$d" "$@";};fi
pp -c "drop database if exists \"$UP\";" >/dev/null;pp -c "create database \"$UP\";" >/dev/null
sed 's/create role authenticated nologin; create role anon nologin;//' "$ROOT/supabase/tests/00_supabase_shim.sql"|pd "$UP" >/dev/null
for m in "$ROOT"/supabase/migrations/*.sql;do [[ "$(basename "$m")" == 20260814001700_* ]]&&continue;pd "$UP"<"$m">/dev/null;done
for t in "$ROOT"/supabase/tests/*.sql;do b="$(basename "$t")";[[ "$b" == 00_* ]]&&continue;[[ "$b" < 58_ ]]||continue;pd "$UP"<"$t">/dev/null;done
[[ "$(pd "$UP" -Atc "select to_regclass('public.livestock_cohorts') is null")" == t ]]||{ echo 'not a pre-GF-020 boundary' >&2;exit 1;}
# Exact row fingerprints prove representative Real Estate, complete Agriculture GF-013..019 and Finance truth survive.
FP="select md5(jsonb_build_object('projects',(select jsonb_agg(to_jsonb(x) order by id) from investment_projects x),'property',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from property_assets x),'land',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agricultural_land_assets x),'farms',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from farms x),'cycles',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from crop_cycles x),'harvest',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from harvest_lots x),'sales',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from agriculture_sales x),'results',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from crop_cycle_closeouts x),'journals',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from journal_batches x))::text);"
BEFORE="$(pd "$UP" -Atc "$FP")";pd "$UP"<"$ROOT/supabase/migrations/20260814001700_livestock_foundation.sql">/dev/null;AFTER="$(pd "$UP" -Atc "$FP")";[[ "$BEFORE" == "$AFTER" ]]||{ echo 'GF-020 changed prior-sector or Finance rows' >&2;exit 1;}
O=10000000-0000-4000-8000-000000000001;U=00000000-0000-4000-8000-000000000001
P="$(pd "$UP" -Atc "set request.jwt.claim.sub='$U';set role authenticated;select create_investment_project('$O','ترقية ثروة حيوانية','GF020-UP',null,'LIVESTOCK');"|tail -1)"
S="$(pd "$UP" -Atc "set request.jwt.claim.sub='$U';set role authenticated;select create_livestock_site('$O','$P','مزرعة التسمين','UP-S','FARM',null,null,'gf20-up-site');"|tail -1)"
H="$(pd "$UP" -Atc "set request.jwt.claim.sub='$U';set role authenticated;select create_livestock_herd('$O','$P','$S','قطيع أبقار التسمين','UP-H','CATTLE','MEAT',null,'gf20-up-herd');"|tail -1)"
K="$(pd "$UP" -Atc "set request.jwt.claim.sub='$U';set role authenticated;select create_livestock_cohort('$O','$P','$H','دفعة أغسطس 2026','PURCHASED','2026-08-01',60,'MALE',null,null,null,null,null,null,'gf20-up-cohort');"|tail -1)"
pd "$UP" -Atc "set request.jwt.claim.sub='$U';set role authenticated;select transition_livestock_cohort('$O','$P','$K','PLANNED','ACTIVE','بدء التشغيل',null,'gf20-up-active');" >/dev/null
[[ "$(pd "$UP" -Atc "select lifecycle_state='ACTIVE' and opening_headcount=60 and species='CATTLE' from livestock_cohorts_read where id='$K'")" == t ]]||{ echo 'post-upgrade workflow failed' >&2;exit 1;}
echo 'GF-020 forward-upgrade PASS: complete GF-019 boundary preserved; Livestock workflow exercised.'
