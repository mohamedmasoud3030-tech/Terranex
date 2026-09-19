-- H1 — Capital by currency: the Project Brief Capital panel contract.
--
-- BUSINESS QUESTION
--   What has been committed to this project, what has been called, what has
--   actually been received, and what remains receivable — in which currency.
--
-- WHY A NEW VIEW IS REQUIRED (the four-part proof)
--   1. Concrete missing contract. `project_capital_position` sums commitment
--      terms, call lines and contributions across ALL currencies and stamps the
--      total with `investment_projects.reporting_currency`. None of the three
--      underlying facts is constrained to that currency: `commitment_terms.
--      currency`, `capital_call_lines.currency` and `contributions.currency` are
--      each only checked against `^[A-Z]{3}$`. The view therefore performs the
--      same cross-currency aggregation just removed from project cash.
--   2. The existing contract cannot answer correctly. It exposes four amounts
--      and one assumed currency, with no way to detect that OMR commitments were
--      added to EGP contributions.
--   3. It cannot be solved at the query boundary. Detecting the mismatch would
--      require the UI to select from `commitment_terms` / `capital_call_lines` /
--      `contributions` and re-derive financial truth in React, which the
--      architecture forbids.
--   4. This is the smallest semantic expansion that fixes it: regroup the same
--      authoritative facts by their OWN currency, and change nothing else.
--
-- BASIS (unchanged from the existing authoritative rollforward)
--   committed   stored fact     sum of commitment_terms for the ACTIVE agreement
--   called      derived fact    sum of capital_call_lines on ISSUED calls
--   contributed stored fact     sum of contributions recorded
--   receivable  derived fact    called - contributed
--   uncalled    derived fact    committed - called
-- Every component is summed only over facts denominated in the row's currency,
-- so no row ever mixes currencies.
--
-- CURRENCY SEMANTICS
--   One row per (project, currency). There is deliberately no field holding a
--   total across currencies and no FX conversion, so no caller can add OMR to
--   EGP by accident. Unlike cash, no `currency_mismatch` counter is needed: the
--   grain itself is the protection, because each fact lands in the row for its
--   own currency rather than being excluded from one.
--
-- ZERO / NO-DATA SEMANTICS
--   A project with no capital structure yields NO ROW — not a row of zeroes.
--   "No commitment has been recorded" is a different fact from "a commitment was
--   recorded and nothing has been received", and the row's presence carries that
--   distinction. The previous view collapsed both into 0.
--
--   `call_line_count` distinguishes "nothing called yet" (0) from "called and
--   not paid" (contributed < called), which are different management facts.
--
-- This is a projection over existing authoritative facts, not a new financial
-- fact. Nothing is stored here.
--
-- NOT SUPERSEDED: `project_capital_position` / `project_capital_position_read`
-- remain authoritative for the S6 close gate's rollforward invariant
-- (contributed <= called <= committed, no negative receivable) — specifically
-- the S6 `PARTNER_CAPITAL_ROLLFORWARD` gate in 20260811000600. That gate
-- consumes the project-grain view; changing its grain would alter close
-- semantics, which is a separate decision with a wider blast radius. The
-- cross-currency assumption there remains a known defect recorded for a
-- follow-up, in the same way as the BANK_CASH line-currency mismatch.

create view public.project_capital_by_currency_read with (security_invoker=on) as
with active_agreement as (
  select id, organization_id, project_id
  from public.agreement_versions
  where status = 'ACTIVE'
),
commitments as (
  select ct.organization_id, av.project_id, ct.currency,
         sum(ct.commitment_minor_units) as committed_minor
  from public.commitment_terms ct
  join active_agreement av
    on av.id = ct.agreement_version_id
   and av.organization_id = ct.organization_id
  group by ct.organization_id, av.project_id, ct.currency
),
called as (
  select ccl.organization_id, cc.project_id, ccl.currency,
         sum(ccl.amount_minor_units) as called_minor,
         count(*) as call_line_count
  from public.capital_call_lines ccl
  join public.capital_calls cc on cc.id = ccl.capital_call_id
  join active_agreement av
    on av.id = cc.agreement_version_id
   and av.organization_id = ccl.organization_id
  where cc.status = 'ISSUED'
  group by ccl.organization_id, cc.project_id, ccl.currency
),
paid as (
  select c.organization_id, av.project_id, c.currency,
         sum(c.contribution_minor_units) as contributed_minor
  from public.contributions c
  join active_agreement av
    on av.id = c.agreement_version_id
   and av.organization_id = c.organization_id
  group by c.organization_id, av.project_id, c.currency
),
currencies as (
  select organization_id, project_id, currency from commitments
  union
  select organization_id, project_id, currency from called
  union
  select organization_id, project_id, currency from paid
)
select
  cur.organization_id,
  cur.project_id,
  cur.currency,
  coalesce(cm.committed_minor, 0)::text as committed_minor_units,
  coalesce(cl.called_minor, 0)::text as called_minor_units,
  coalesce(p.contributed_minor, 0)::text as contributed_minor_units,
  (coalesce(cl.called_minor, 0) - coalesce(p.contributed_minor, 0))::text
    as receivable_minor_units,
  (coalesce(cm.committed_minor, 0) - coalesce(cl.called_minor, 0))::text
    as uncalled_minor_units,
  coalesce(cl.call_line_count, 0)::bigint as call_line_count
from currencies cur
left join commitments cm
  on cm.organization_id = cur.organization_id
 and cm.project_id = cur.project_id
 and cm.currency = cur.currency
left join called cl
  on cl.organization_id = cur.organization_id
 and cl.project_id = cur.project_id
 and cl.currency = cur.currency
left join paid p
  on p.organization_id = cur.organization_id
 and p.project_id = cur.project_id
 and p.currency = cur.currency;

comment on view public.project_capital_by_currency_read is
  'H1 capital position per (project, currency) for the Project Brief Capital '
  'panel. Regroups the authoritative rollforward facts (commitment_terms, ISSUED '
  'capital_call_lines, contributions) by each fact''s OWN currency, because none '
  'of them is constrained to the project reporting currency and the previous '
  'project-grain view summed across currencies. One row per (project, currency); '
  'no cross-currency total and no FX conversion. A project with no capital '
  'structure yields no row, which is a different fact from a recorded structure '
  'with nothing received. call_line_count distinguishes "nothing called yet" '
  'from "called and unpaid". Projection only; nothing is stored.';

grant select on public.project_capital_by_currency_read to authenticated;
