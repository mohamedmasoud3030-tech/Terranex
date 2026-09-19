-- H1 — Project Brief Capital panel: capital by currency.
--
-- The previous project-grain view (`project_capital_position`) summed
-- commitment_terms, capital_call_lines and contributions across ALL currencies
-- and stamped the total with `investment_projects.reporting_currency`. None of
-- those three facts is constrained to the project currency; each is only checked
-- against `^[A-Z]{3}$`. This gate proves the replacement keeps the currencies
-- apart and keeps "no capital structure" distinct from "nothing received".

insert into auth.users values ('00b00000-0000-4000-8000-0000000000b1')
  on conflict (id) do nothing;
insert into auth.users values ('00b00000-0000-4000-8000-0000000000b2')
  on conflict (id) do nothing;

create or replace function public.h1c_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'H1 CAPITAL ASSERTION FAILED: %', p_message;
  end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00b00000-0000-4000-8000-0000000000b1', false);

select public.create_organization('منظمة رأس المال H1') as h1c_org \gset
select public.create_investment_project(
  :'h1c_org'::uuid, 'مشروع رأس مال H1', 'H1-CAP', 'إثبات فصل عملات رأس المال',
  'AGRICULTURE') as h1c_project \gset
-- A second project that will deliberately get no capital structure at all.
select public.create_investment_project(
  :'h1c_org'::uuid, 'مشروع بلا هيكل رأس مال', 'H1-NOCAP', 'إثبات التمييز عن الصفر',
  'LIVESTOCK') as h1c_bare \gset

-- ---------------------------------------------------------------------------
-- No capital structure yet: no rows at all, in either project.
-- ---------------------------------------------------------------------------
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid) = 0,
  'a project with no commitment, call or contribution yields no row, not a zero');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read
    where project_id = :'h1c_bare'::uuid) = 0,
  'a project that never receives a capital structure also yields no row');

-- The previous view collapsed that state into an indistinguishable zero.
select public.h1c_assert(
  (select contributed_minor_units from public.project_capital_position_read
    where project_id = :'h1c_project'::uuid) = '0',
  'the legacy project-grain view reports 0 for the same state, which is why it cannot be used');

-- ---------------------------------------------------------------------------
-- Build a capital structure with the real commands. Note what they prove:
-- `create_agreement_draft` writes commitment_terms using the project reporting
-- currency, so a commitment in another currency is NOT reachable through the
-- command. That is the same command-layer gap found for cash accounts, and it is
-- why the OMR commitment below is inserted directly: the read model must still
-- be correct for imported or backfilled rows.
-- ---------------------------------------------------------------------------
select public.create_party(:'h1c_org'::uuid, 'مستثمر H1', 'PERSON') as h1c_party \gset
select public.add_project_participant(:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_party'::uuid);
select id as h1c_participant from public.project_participants
 where party_id = :'h1c_party'::uuid \gset

-- Participants freeze once the agreement is activated, so both are added first.
select public.create_party(:'h1c_org'::uuid, 'مستثمر H1 ثانٍ', 'PERSON') as h1c_party_2 \gset
select public.add_project_participant(:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_party_2'::uuid);
select id as h1c_participant_omr from public.project_participants
 where party_id = :'h1c_party_2'::uuid \gset

select public.create_agreement_draft(
  :'h1c_org'::uuid, :'h1c_project'::uuid, current_date,
  array[:'h1c_participant'::uuid]::uuid[],
  array[100000000::bigint]::bigint[],
  'h1c-agreement-draft-0001') as h1c_version \gset

select public.activate_agreement_version(:'h1c_org'::uuid, :'h1c_version'::uuid);
select id as h1c_agreement from public.agreement_versions
 where id = :'h1c_version'::uuid and status = 'ACTIVE' \gset

select public.h1c_assert(
  (select count(*) from public.commitment_terms
    where agreement_version_id = :'h1c_agreement'::uuid) = 1,
  'the command layer creates exactly one commitment term, in the project currency');
select public.h1c_assert(
  (select currency from public.commitment_terms
    where agreement_version_id = :'h1c_agreement'::uuid) = 'EGP',
  'the command layer denominates the commitment in the project reporting currency');

-- A second commitment in OMR, inserted directly: not command-reachable, but the
-- read model must not silently fold it into the EGP total. Commitment terms are
-- unique per (agreement version, participant), so it needs its own participant.
reset role;

insert into public.commitment_terms(organization_id, agreement_version_id, participant_id, commitment_minor_units, currency)
values (:'h1c_org'::uuid, :'h1c_agreement'::uuid, :'h1c_participant_omr'::uuid, 5000000, 'OMR');

-- ---------------------------------------------------------------------------
-- Commitments only: two currency rows, still nothing called or received.
-- ---------------------------------------------------------------------------
select * from public.project_capital_by_currency_read where project_id = :'h1c_project'::uuid;

select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid) = 2,
  'commitments in EGP and OMR produce two rows, not one summed row');
select public.h1c_assert(
  (select committed_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '100000000',
  'the EGP commitment is reported exactly, in the EGP row');
select public.h1c_assert(
  (select committed_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'OMR') = '5000000',
  'the OMR commitment is reported exactly, in its own OMR row');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.project_id = :'h1c_project'::uuid
      and r.committed_minor_units::bigint = 105000000) = 0,
  'no row ever holds the cross-currency sum of the EGP and OMR commitments');

-- Nothing called yet, and `call_line_count` says so rather than an inferred zero.
select public.h1c_assert(
  (select called_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '0',
  'with no issued call, called is an established zero');
select public.h1c_assert(
  (select call_line_count from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = 0,
  'call_line_count distinguishes "nothing called yet" from "called and unpaid"');
select public.h1c_assert(
  (select contributed_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '0',
  'with no contribution recorded, contributed is an established zero');
select public.h1c_assert(
  (select receivable_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '0',
  'receivable is called minus contributed, both zero');

-- ---------------------------------------------------------------------------
-- Issue calls and record contributions, each in its own currency. A
-- contribution must reference a capital call, so each currency needs its own
-- issued call.
insert into public.capital_calls(organization_id, project_id, agreement_version_id, status, due_date, idempotency_key, request_hash)
values (:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_agreement'::uuid, 'ISSUED',
        current_date, 'h1c-call-0001', repeat('0', 64))
returning id as h1c_call \gset

insert into public.capital_call_lines(organization_id, capital_call_id, participant_id, amount_minor_units, currency)
values (:'h1c_org'::uuid, :'h1c_call'::uuid, :'h1c_participant'::uuid, 25000000, 'EGP');

insert into public.capital_calls(organization_id, project_id, agreement_version_id, status, due_date, idempotency_key, request_hash)
values (:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_agreement'::uuid, 'ISSUED',
        current_date, 'h1c-call-omr-0001', repeat('0', 64))
returning id as h1c_call_omr \gset

insert into public.capital_call_lines(organization_id, capital_call_id, participant_id, amount_minor_units, currency)
values (:'h1c_org'::uuid, :'h1c_call_omr'::uuid, :'h1c_participant_omr'::uuid, 1000000, 'OMR');

-- A CANCELLED call must not contribute to `called`.
insert into public.capital_calls(organization_id, project_id, agreement_version_id, status, due_date, idempotency_key, request_hash)
values (:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_agreement'::uuid, 'CANCELLED',
        current_date, 'h1c-call-cancelled-0001', repeat('0', 64))
returning id as h1c_cancelled_call \gset

insert into public.capital_call_lines(organization_id, capital_call_id, participant_id, amount_minor_units, currency)
values (:'h1c_org'::uuid, :'h1c_cancelled_call'::uuid, :'h1c_participant'::uuid, 777000, 'EGP');

-- Contributions received: 150,000.00 EGP and 250.000 OMR (three decimals).
insert into public.contributions(organization_id, project_id, agreement_version_id, capital_call_id, participant_id, contribution_minor_units, currency, occurred_on, recorded_by, idempotency_key)
values (:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_agreement'::uuid, :'h1c_call'::uuid,
        :'h1c_participant'::uuid, 15000000, 'EGP', current_date,
        '00b00000-0000-4000-8000-0000000000b1'::uuid, 'h1c-cont-egp-0001');
insert into public.contributions(organization_id, project_id, agreement_version_id, capital_call_id, participant_id, contribution_minor_units, currency, occurred_on, recorded_by, idempotency_key)
values (:'h1c_org'::uuid, :'h1c_project'::uuid, :'h1c_agreement'::uuid, :'h1c_call_omr'::uuid,
        :'h1c_participant_omr'::uuid, 250000, 'OMR', current_date,
        '00b00000-0000-4000-8000-0000000000b1'::uuid, 'h1c-cont-omr-0001');

select * from public.project_capital_by_currency_read where project_id = :'h1c_project'::uuid;

select public.h1c_assert(
  (select called_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '25000000',
  'the EGP call is reported exactly, in the EGP row');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.project_id = :'h1c_project'::uuid
      and r.called_minor_units::bigint = 26000000) = 0,
  'no row ever holds the cross-currency sum of the EGP and OMR calls');
select public.h1c_assert(
  (select call_line_count from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = 1,
  'a CANCELLED call does not contribute to called or to call_line_count');
select public.h1c_assert(
  (select contributed_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'EGP') = '15000000',
  'the EGP contribution is reported exactly, in the EGP row');
select public.h1c_assert(
  (select contributed_minor_units from public.project_capital_by_currency_read
    where project_id = :'h1c_project'::uuid and currency = 'OMR') = '250000',
  'the OMR contribution is reported exactly, in the OMR row');

-- Exact arithmetic identities, asserted per currency row.
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.receivable_minor_units::bigint
       <> r.called_minor_units::bigint - r.contributed_minor_units::bigint) = 0,
  'receivable equals called minus contributed, in every row');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.uncalled_minor_units::bigint
       <> r.committed_minor_units::bigint - r.called_minor_units::bigint) = 0,
  'uncalled equals committed minus called, in every row');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.contributed_minor_units::bigint > r.called_minor_units::bigint) = 0,
  'the rollforward invariant contributed <= called holds in every currency row');
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read r
    where r.receivable_minor_units::bigint < 0
       or r.uncalled_minor_units::bigint < 0) = 0,
  'no currency row reports a negative receivable or a negative uncalled commitment');

-- ---------------------------------------------------------------------------
-- Negative control: on this exact fixture the legacy project-grain view folds
-- both currencies into one figure stamped with the project reporting currency.
-- ---------------------------------------------------------------------------
select * from public.project_capital_position_read where project_id = :'h1c_project'::uuid;

select public.h1c_assert(
  (select committed_minor_units from public.project_capital_position_read
    where project_id = :'h1c_project'::uuid) = '105000000',
  'the legacy view reports 100000000 EGP + 5000000 OMR as one 105000000 figure');
select public.h1c_assert(
  (select called_minor_units from public.project_capital_position_read
    where project_id = :'h1c_project'::uuid) = '26000000',
  'the legacy view reports 25000000 EGP + 1000000 OMR as one 26000000 figure');

-- ---------------------------------------------------------------------------
-- Structural guarantees: no cross-currency total, no FX, no invented row.
-- ---------------------------------------------------------------------------
select public.h1c_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_capital_by_currency_read'
      and column_name ~* '(total|combined|converted|consolidat|all_currencies|_sum)') = 0,
  'the read model exposes no field representing a cross-currency capital total');
select public.h1c_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_capital_by_currency_read'
      and column_name ~* '(fx|rate)') = 0,
  'the read model performs no FX conversion');
select public.h1c_assert(
  (select count(*) from public.investment_projects p
    where p.organization_id = :'h1c_org'::uuid
      and not exists (select 1 from public.project_capital_by_currency_read c
                      where c.project_id = p.id)) = 1,
  'only the project with no capital structure is absent; the other is present');

-- ---------------------------------------------------------------------------
-- Tenant isolation: a non-member sees nothing.
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00b00000-0000-4000-8000-0000000000b2', false);
select public.h1c_assert(
  (select count(*) from public.project_capital_by_currency_read
    where organization_id = :'h1c_org'::uuid) = 0,
  'a non-member sees no capital rows for the organization');

reset role;
