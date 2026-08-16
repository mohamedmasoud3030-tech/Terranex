-- R8 — Cross-Sector Asset & Performance Layer behavioral gate.
--
-- Proves the register is a faithful, honest, read-only projection:
--   * it is a view, not a table, and no sector root gained an FK to it;
--   * it conserves assets exactly (no asset invented, none dropped);
--   * it never reports a guessed cost/valuation/result — absent facts
--     surface as explicit *_status text, never as a misleading zero;
--   * sector performance conserves projects, never mixes currencies, and
--     refuses to emit a partial converted total;
--   * tenancy is inherited from the underlying RLS, so a non-member sees
--     nothing and a member sees only their own organization;
--   * both views are readable by authenticated and closed to anon/public.
--
-- Self-contained fixtures on org r800..., users r800....

create or replace function r8_assert(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then raise exception 'R8 ASSERTION FAILED: %', p_msg; end if;
end $$;

create or replace function r8_run(p_user uuid, p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute p_sql;
  return true;
exception when others then
  raise exception 'r8_run failed: % | sql: %', sqlerrm, p_sql;
end $$;

-- Counts a query as a real `authenticated` caller. The role switch is
-- essential: RLS is bypassed for the owning superuser, so a tenancy claim
-- proven only as postgres would prove nothing at all.
create or replace function r8_count_as(p_user uuid, p_sql text)
returns bigint language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v;
  perform set_config('role', 'none', false);
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Structural contract — the register must not become a universal asset table
-- ---------------------------------------------------------------------------
do $$
declare v_offender text;
begin
  perform public.r8_assert(
    (select c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'cross_sector_asset_register_read') = 'v',
    'the cross-sector asset register must be a view, never a base table');

  perform public.r8_assert(
    (select c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'sector_performance_read') = 'v',
    'sector performance must be a view, never a base table');

  -- The canonical rule (03_DOMAIN_MODEL.md:175) is that sector tables connect
  -- through investment_project_id and their own roots. Nothing anywhere may
  -- reference a unified asset relation, so no such base table may exist.
  select string_agg(c.relname, ', ')
    into v_offender
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relname in ('assets', 'asset_registry', 'cross_sector_assets', 'asset_activities');
  if v_offender is not null then
    raise exception 'a universal asset base table is not authorized, found: %', v_offender;
  end if;

  -- Both views must be security_invoker so RLS on the sector roots applies to
  -- the caller; a definer-style view would silently bypass tenancy.
  perform public.r8_assert(
    (select 'security_invoker=on' = any(c.reloptions) from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'cross_sector_asset_register_read'),
    'register must be security_invoker=on');
  perform public.r8_assert(
    (select 'security_invoker=on' = any(c.reloptions) from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'sector_performance_read'),
    'sector performance must be security_invoker=on');

  -- Read-only surface: authenticated may select and nothing more, anon nothing.
  foreach v_offender in array array['cross_sector_asset_register_read', 'sector_performance_read'] loop
    perform public.r8_assert(
      has_table_privilege('authenticated', 'public.' || v_offender, 'select'),
      v_offender || ' must be selectable by authenticated');
    perform public.r8_assert(
      not has_table_privilege('authenticated', 'public.' || v_offender, 'insert')
      and not has_table_privilege('authenticated', 'public.' || v_offender, 'update')
      and not has_table_privilege('authenticated', 'public.' || v_offender, 'delete'),
      v_offender || ' must never be writable');
    perform public.r8_assert(
      not has_table_privilege('anon', 'public.' || v_offender, 'select'),
      v_offender || ' must not be readable by anon');
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures — one organization holding all three sectors
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('e8000000-0000-4000-8000-0000000000a1'),
  ('e8000000-0000-4000-8000-0000000000a2')
on conflict (id) do nothing;

insert into public.organizations(id, name) values
  ('e8000000-0000-4000-8000-000000000001', 'منظمة R8'),
  ('e8000000-0000-4000-8000-000000000002', 'منظمة R8 الأخرى')
on conflict (id) do nothing;

-- a1 belongs to org 1 only; a2 belongs to org 2 only. Neither may see the
-- other's assets through the register.
insert into public.memberships(organization_id, user_id, role) values
  ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-0000000000a1', 'OWNER'),
  ('e8000000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-0000000000a2', 'OWNER')
on conflict (organization_id, user_id) do nothing;

do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_re uuid; v_ag uuid; v_lv uuid;
  v_profile uuid; v_asset uuid; v_land uuid; v_farm uuid; v_site uuid;
  v_party uuid;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  v_re := public.create_investment_project(
            v_org, 'مشروع عقاري R8', 'R8-RE', 'عقاري', 'REAL_ESTATE');
  v_ag := public.create_investment_project(
            v_org, 'مشروع زراعي R8', 'R8-AG', 'زراعي', 'AGRICULTURE');
  v_lv := public.create_investment_project(
            v_org, 'مشروع ثروة حيوانية R8', 'R8-LV', 'حيواني', 'LIVESTOCK');
  perform set_config('r8.re', v_re::text, false);
  perform set_config('r8.ag', v_ag::text, false);
  perform set_config('r8.lv', v_lv::text, false);

  -- Real Estate: a property asset with no acquisition and no valuation yet.
  v_profile := public.create_real_estate_profile(
                 v_org, v_re, 'DEVELOP_SELL', 'مصر', 'e8-profile-000001');
  v_asset := public.create_property_asset(
               v_org, v_re, 'أصل عقاري R8', 'R8-ASSET-1', 'e8-asset-000001');
  perform set_config('r8.asset', v_asset::text, false);

  -- Agriculture: one land asset contributed in kind (so it carries no agreed
  -- consideration at all) and one farm.
  v_party := public.create_party(v_org, 'مالك أرض R8', 'PERSON');
  v_land := public.create_agricultural_land_asset(
              v_org, v_ag, 'أرض زراعية R8', 'R8-LAND-1', 'سجل 12/أ',
              10.5, 'FEDDAN', 'شمال الطريق', 'CONTRIBUTED_IN_KIND',
              current_date - 30, null, v_party, 'AGR-R8-LAND-1', 'DOC-R8-LAND-1',
              null, null, null, 'e8-land-000001');
  v_farm := public.create_farm(
              v_org, v_ag, 'مزرعة R8', 'R8-FARM-1', 'الدلتا',
              'حيازة مباشرة', 'Africa/Cairo', null, 'e8-farm-000001');

  -- Livestock: one site.
  v_site := public.create_livestock_site(
              v_org, v_lv, 'موقع R8', 'R8-SITE-1', 'BARN', 'حظيرة رئيسية',
              null, 'e8-site-000001');
  perform public.r8_assert(v_land is not null and v_farm is not null and v_site is not null,
    'sector fixtures must all be created');
end $$;

-- ---------------------------------------------------------------------------
-- Conservation — every sector-owned asset appears exactly once, and the
-- register invents nothing.
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_expected bigint;
  v_actual bigint;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  select
    (select count(*) from public.property_assets where organization_id = v_org)
  + (select count(*) from public.agricultural_land_assets where organization_id = v_org)
  + (select count(*) from public.farms where organization_id = v_org)
  + (select count(*) from public.livestock_sites where organization_id = v_org)
    into v_expected;

  select count(*) into v_actual
  from public.cross_sector_asset_register_read where organization_id = v_org;

  perform public.r8_assert(v_actual = v_expected,
    format('register must conserve assets exactly: expected %s, got %s', v_expected, v_actual));

  -- No duplicate identity: (asset_kind, asset_id) is unique.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where organization_id = v_org
    group by asset_kind, asset_id having count(*) > 1
  ), 'register must not duplicate an asset');

  -- Each of the four kinds is represented for this organization.
  perform public.r8_assert(
    (select count(distinct asset_kind) from public.cross_sector_asset_register_read
      where organization_id = v_org) = 4,
    'register must surface all four sector-owned asset kinds');

  -- Every registered asset carries its project and sector context.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where organization_id = v_org
      and (project_id is null or project_sector is null or project_currency is null)
  ), 'every register row must carry project and sector context');
end $$;

-- ---------------------------------------------------------------------------
-- Honesty — absent facts are stated, never guessed as zero
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_asset uuid := current_setting('r8.asset')::uuid;
  r record;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  -- A property asset with no acquisition must not claim a cost of zero.
  select * into r from public.cross_sector_asset_register_read
  where asset_id = v_asset and asset_kind = 'PROPERTY_ASSET';
  perform public.r8_assert(r.acquisition_cost_status = 'NOT_RECORDED',
    'unacquired property must report NOT_RECORDED, not a zero cost');
  perform public.r8_assert(r.acquisition_cost_minor_units is null,
    'unacquired property must not emit a numeric acquisition cost');
  perform public.r8_assert(r.latest_approved_valuation_status = 'NO_APPROVED_VALUATION',
    'unvalued property must say so explicitly');
  perform public.r8_assert(r.latest_approved_valuation_minor_units is null,
    'unvalued property must not emit a numeric valuation');
  perform public.r8_assert(r.realized_result_status = 'NO_RECOGNIZED_SALE',
    'unsold property must report NO_RECOGNIZED_SALE');
  perform public.r8_assert(r.realized_result_minor_units is null,
    'unsold property must not emit a numeric realized result');

  -- A farm has no acquisition concept at all — that is different from
  -- "not entered yet", and the register must distinguish the two.
  select * into r from public.cross_sector_asset_register_read
  where organization_id = v_org and asset_kind = 'FARM' and asset_reference = 'R8-FARM-1';
  perform public.r8_assert(r.acquisition_cost_status = 'NOT_APPLICABLE_NO_ACQUISITION_FACT',
    'a farm must report the concept as not applicable, not as missing data');
  perform public.r8_assert(r.operational_state_basis = 'NOT_MODELLED_FOR_THIS_ASSET_KIND',
    'a farm has no state machine and must say so');

  -- Land contributed in kind carries no agreed consideration.
  select * into r from public.cross_sector_asset_register_read
  where organization_id = v_org and asset_kind = 'AGRICULTURAL_LAND_ASSET'
    and asset_reference = 'R8-LAND-1';
  perform public.r8_assert(r.acquisition_cost_status = 'NOT_RECORDED',
    'land with no agreed consideration must report NOT_RECORDED');
  perform public.r8_assert(r.asset_classification = 'CONTRIBUTED_IN_KIND',
    'land must carry its control basis as the sector classification');

  -- No sector outside Real Estate has an approved valuation policy yet.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where asset_kind <> 'PROPERTY_ASSET'
      and latest_approved_valuation_status
          <> 'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY'
  ), 'non-real-estate valuation must stay explicitly unavailable, never guessed');
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where asset_kind <> 'PROPERTY_ASSET'
      and (latest_approved_valuation_minor_units is not null
        or realized_result_minor_units is not null)
  ), 'non-real-estate assets must not emit valuation or result numbers');

  -- A status column is never null: the register always explains itself.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where acquisition_cost_status is null
       or latest_approved_valuation_status is null
       or realized_result_status is null
       or operational_state_basis is null
  ), 'every register row must carry a non-null explanation for each concept');

  -- The load-bearing invariant of the whole register: a status that says
  -- "there is no such fact" must never be accompanied by a number. A zero
  -- here would read to an operator as "this asset cost nothing" / "this
  -- asset is worth nothing" / "this asset made nothing", which is exactly
  -- the guessed figure the domain model forbids. Asserting the status text
  -- alone is not enough — the number must be absent too.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where acquisition_cost_status in (
            'NOT_RECORDED',
            'NOT_APPLICABLE_NO_ACQUISITION_FACT',
            'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY')
      and (acquisition_cost_minor_units is not null
        or acquisition_cost_currency is not null)
  ), 'an absent acquisition cost must carry no amount and no currency');

  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where latest_approved_valuation_status in (
            'NO_APPROVED_VALUATION',
            'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY')
      and (latest_approved_valuation_minor_units is not null
        or latest_approved_valuation_currency is not null
        or latest_approved_valuation_date is not null)
  ), 'an absent valuation must carry no amount, currency or date');

  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where realized_result_status in (
            'NO_RECOGNIZED_SALE',
            'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY')
      and (realized_result_minor_units is not null
        or realized_result_currency is not null)
  ), 'an absent realized result must carry no amount and no currency');

  -- Converse direction: a number must never appear without a status that
  -- accounts for it, so neither side can drift from the other.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where (acquisition_cost_minor_units is not null
           and acquisition_cost_status not in (
             'CONTRACTED_CONSIDERATION_AND_CLOSING_COSTS', 'AGREED_CONSIDERATION'))
       or (latest_approved_valuation_minor_units is not null
           and latest_approved_valuation_status <> 'APPROVED_VALUATION')
       or (realized_result_minor_units is not null
           and realized_result_status <> 'REALIZED_ON_RECOGNIZED_SALE')
  ), 'a reported amount must always be explained by a matching status');

  -- An amount and its currency travel together; a bare number is unreadable.
  perform public.r8_assert(not exists (
    select 1 from public.cross_sector_asset_register_read
    where (acquisition_cost_minor_units is null) <> (acquisition_cost_currency is null)
       or (latest_approved_valuation_minor_units is null)
          <> (latest_approved_valuation_currency is null)
       or (realized_result_minor_units is null) <> (realized_result_currency is null)
  ), 'every register amount must carry its own currency');
end $$;

-- ---------------------------------------------------------------------------
-- Real facts flow through — an approved valuation and a recorded acquisition
-- must actually appear, so the honesty above is not merely "always null".
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_asset uuid := current_setting('r8.asset')::uuid;
  v_val uuid;
  r record;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  v_val := public.propose_property_valuation(
             v_org, v_asset, current_date - 1, 'مثمّن معتمد', 'MARKET_COMPARABLE',
             2500000, 'EGP', 'افتراضات السوق الحالية', 'HIGH',
             'DOC-R8-VAL-1', 'e8-valuation-00001');
  perform public.approve_property_valuation(v_org, v_val, 'e8-valuation-appr-1');

  select * into r from public.cross_sector_asset_register_read
  where asset_id = v_asset and asset_kind = 'PROPERTY_ASSET';

  perform public.r8_assert(r.latest_approved_valuation_status = 'APPROVED_VALUATION',
    'an approved valuation must surface in the register');
  perform public.r8_assert(r.latest_approved_valuation_minor_units = '2500000',
    'the register must carry the exact approved valuation, unrounded');
  perform public.r8_assert(r.latest_approved_valuation_currency = 'EGP',
    'the valuation must carry its own currency');
  perform public.r8_assert(r.latest_approved_valuation_date = current_date - 1,
    'the register must carry the valuation effective date');

  -- A merely proposed valuation must never be promoted into the register.
  perform public.propose_property_valuation(
    v_org, v_asset, current_date, 'مثمّن آخر', 'INCOME_APPROACH',
    9900000, 'EGP', 'افتراضات مختلفة', 'LOW', 'DOC-R8-VAL-2', 'e8-valuation-00002');

  select * into r from public.cross_sector_asset_register_read
  where asset_id = v_asset and asset_kind = 'PROPERTY_ASSET';
  perform public.r8_assert(r.latest_approved_valuation_minor_units = '2500000',
    'a proposed (unapproved) valuation must never reach the register');
end $$;

-- ---------------------------------------------------------------------------
-- Sector performance — conservation, currency discipline, FX honesty
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_projects bigint;
  v_counted bigint;
  v_assets bigint;
  v_reg bigint;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  select count(*) into v_projects from public.investment_projects where organization_id = v_org;
  select coalesce(sum(project_count), 0) into v_counted
  from public.sector_performance_read where organization_id = v_org;
  perform public.r8_assert(v_projects = v_counted,
    format('sector performance must conserve projects: %s vs %s', v_projects, v_counted));

  -- Critically: a project with no financial activity must still be counted.
  -- Driving the roll-up off the finance spine would silently drop it.
  perform public.r8_assert(v_counted >= 3,
    'all three sector projects must be counted even before any money is posted');

  select count(*) into v_reg
  from public.cross_sector_asset_register_read where organization_id = v_org;
  select coalesce(sum(asset_count), 0) into v_assets
  from public.sector_performance_read where organization_id = v_org;
  perform public.r8_assert(v_reg = v_assets,
    format('sector asset counts must reconcile to the register: %s vs %s', v_reg, v_assets));

  -- One row per (sector, currency): currencies are never mixed into one total.
  perform public.r8_assert(not exists (
    select 1 from public.sector_performance_read
    where organization_id = v_org
    group by sector, currency having count(*) > 1
  ), 'sector performance must be keyed by sector and currency');
  perform public.r8_assert(not exists (
    select 1 from public.sector_performance_read where currency is null
  ), 'a sector total without a currency is meaningless and must not exist');

  -- The organization has no reporting currency, so no converted figure may
  -- be invented — fx_status must say exactly why.
  perform public.r8_assert(not exists (
    select 1 from public.sector_performance_read
    where organization_id = v_org and fx_status <> 'NO_REPORTING_CURRENCY'
  ), 'without an organization reporting currency fx_status must be NO_REPORTING_CURRENCY');
  perform public.r8_assert(not exists (
    select 1 from public.sector_performance_read
    where organization_id = v_org
      and (converted_cash_balance_minor_units is not null
        or converted_revenue_recognized_minor_units is not null
        or converted_contributions_received_minor_units is not null
        or converted_realized_result_minor_units is not null)
  ), 'no converted figure may exist without a reporting currency');

  -- Unconverted figures are still exact and present.
  perform public.r8_assert(not exists (
    select 1 from public.sector_performance_read
    where organization_id = v_org
      and (cash_balance_minor_units is null
        or revenue_recognized_minor_units is null
        or realized_result_minor_units is null)
  ), 'native-currency totals must always be present and exact');

  perform public.r8_assert(
    (select count(distinct sector) from public.sector_performance_read
      where organization_id = v_org) = 3,
    'all three sectors must be represented');
end $$;

-- ---------------------------------------------------------------------------
-- FX honesty under a real reporting currency: a partial conversion is
-- refused outright rather than reported as a smaller-but-wrong total.
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_status text;
  v_converted text;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  update public.organizations set reporting_currency = 'USD' where id = v_org;

  -- The roll-up's currency safety rests on one structural premise: because
  -- the grouping key includes the project currency, every project inside a
  -- group resolves the same snapshot and therefore the same fx_status. If
  -- that premise ever broke, min(fx_status) would report one group's status
  -- while the totals mixed converted and unconverted projects. Assert the
  -- premise directly rather than trusting it.
  perform public.r8_assert(not exists (
    select 1
    from (
      select p.organization_id, p.sector, p.reporting_currency as currency,
             case
               when o.reporting_currency is null then 'NO_REPORTING_CURRENCY'
               when o.reporting_currency = p.reporting_currency then 'SAME_CURRENCY'
               when s.id is null then 'NO_RATE_SNAPSHOT'
               else 'CONVERTED_AT_RATE'
             end as fx_status
      from public.investment_projects p
      join public.organizations o on o.id = p.organization_id
      left join lateral (
        select s2.id from public.fx_rate_snapshots s2
        where s2.organization_id = p.organization_id
          and s2.base_currency = p.reporting_currency
          and s2.quote_currency = o.reporting_currency
          and s2.rate_date <= current_date
        order by s2.rate_date desc limit 1
      ) s on true
    ) t
    group by organization_id, sector, currency
    having count(distinct fx_status) > 1
  ), 'fx_status must be uniform within every (organization, sector, currency) group');

  -- No snapshot yet for EGP -> USD: every converted column must be NULL and
  -- fx_status must be NO_RATE_SNAPSHOT. Reporting 0 here would be a lie.
  select fx_status, converted_cash_balance_minor_units into v_status, v_converted
  from public.sector_performance_read
  where organization_id = v_org and sector = 'REAL_ESTATE';
  perform public.r8_assert(v_status = 'NO_RATE_SNAPSHOT',
    'a missing FX snapshot must be reported as NO_RATE_SNAPSHOT');
  perform public.r8_assert(v_converted is null,
    'a missing FX snapshot must yield NULL, never a guessed converted total');

  -- Restore, so this gate leaves no cross-test residue.
  update public.organizations set reporting_currency = null where id = v_org;
end $$;

-- ---------------------------------------------------------------------------
-- Tenancy — inherited from the sector roots' RLS, not re-implemented
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'e8000000-0000-4000-8000-000000000001';
  v_other uuid := 'e8000000-0000-4000-8000-000000000002';
  v_owner uuid := 'e8000000-0000-4000-8000-0000000000a1';
  v_stranger uuid := 'e8000000-0000-4000-8000-0000000000a2';
begin
  -- The owner sees their own organization's assets.
  perform public.r8_assert(public.r8_count_as(v_owner,
    format('select count(*) from public.cross_sector_asset_register_read where organization_id = %L', v_org)) > 0,
    'an active member must see their own organization assets');

  -- A member of another organization sees none of them, through either view.
  perform public.r8_assert(public.r8_count_as(v_stranger,
    format('select count(*) from public.cross_sector_asset_register_read where organization_id = %L', v_org)) = 0,
    'the register must not leak assets across organizations');
  perform public.r8_assert(public.r8_count_as(v_stranger,
    format('select count(*) from public.sector_performance_read where organization_id = %L', v_org)) = 0,
    'sector performance must not leak across organizations');

  -- And the stranger sees nothing at all, since their own org has no projects.
  perform public.r8_assert(public.r8_count_as(v_stranger,
    'select count(*) from public.cross_sector_asset_register_read') = 0,
    'a member of an empty organization must see an empty register');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.r8_assert(v_other is not null, 'fixture guard');
end $$;
