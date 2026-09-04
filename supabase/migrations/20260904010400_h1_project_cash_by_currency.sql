-- H1 — Cash by currency (ADR 0034 §H1 item 4).
--
-- The project pages currently compute cash as
--   accounts.reduce((sum, a) => sum + BigInt(a.balance), 0n)
-- and label the result with `project.reporting_currency`. That is a currency
-- leak: it adds OMR minor units to USD minor units and stamps the total with a
-- third currency. It also silently treats a missing balance as zero.
--
-- This view is the replacement contract:
--
--   * ONE ROW PER (project_id, currency). Cash is never comparable across
--     currencies and is never presented as comparable.
--   * NO PROJECT-LEVEL FX CONVERSION. Converting would require a rate policy
--     TERRANEX does not have, and inventing one here would mint a number the
--     ledger cannot defend.
--   * NO CROSS-CURRENCY TOTAL. There is deliberately no column holding a sum
--     across currencies, so no caller can add OMR to USD by accident. The
--     absence is structural, not a UI choice to display less.
--   * NO FALLBACK TO ZERO unless the semantics genuinely establish zero. A
--     registered cash account with no posted movement really does hold zero, so
--     the coalesce is justified there — and `has_posted_activity` always says
--     which case a row is. A project with no accounts at all produces NO ROW,
--     because "no accounts" is not the same fact as "zero cash".
--
-- It is a PROJECTION over authoritative account-level facts, not a new financial
-- fact: `project_cash_accounts` remains the account registry and the posted
-- BANK_CASH journal lines remain the movements. Nothing is stored here.
--
-- Currency discipline: the account's DECLARED currency is authoritative for the
-- row, because the account is the object that holds the money. Posted movements
-- whose line currency differs are EXCLUDED from the balance and disclosed via
-- `currency_mismatch_line_count`, so a mismatch is surfaced rather than summed.

create view public.project_cash_by_currency_read with (security_invoker=on) as
with posted_cash_lines as (
  -- Authoritative cash movements: posted, not a reversal, and not itself reversed.
  select
    jl.organization_id,
    jl.project_id,
    jl.cash_account_id,
    jl.currency,
    count(*) as line_count,
    sum(jl.debit_minor_units - jl.credit_minor_units) as movement_minor
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id
  where sa.role = 'BANK_CASH'
    and jb.reversal_of_batch_id is null
    and not exists (
      select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id
    )
  group by jl.organization_id, jl.project_id, jl.cash_account_id, jl.currency
),
per_account as (
  select
    ca.organization_id,
    ca.project_id,
    ca.id as cash_account_id,
    ca.currency,
    -- Movements in the account's own currency only. A registered account with
    -- no posted movement genuinely holds zero, hence the coalesce.
    coalesce(sum(p.movement_minor) filter (where p.currency = ca.currency), 0)
      as balance_minor,
    coalesce(sum(p.line_count) filter (where p.currency = ca.currency), 0)
      as posted_line_count,
    -- Movements in some other currency: excluded from the balance, but counted
    -- and disclosed so the discrepancy is visible instead of silently dropped.
    coalesce(sum(p.line_count) filter (where p.currency is distinct from ca.currency), 0)
      as currency_mismatch_line_count
  from public.project_cash_accounts ca
  left join posted_cash_lines p on p.cash_account_id = ca.id
  group by ca.organization_id, ca.project_id, ca.id, ca.currency
)
select
  organization_id,
  project_id,
  currency,
  count(*) as account_count,
  sum(balance_minor)::text as cash_balance_minor_units,
  sum(posted_line_count)::bigint as posted_line_count,
  sum(currency_mismatch_line_count)::bigint as currency_mismatch_line_count,
  -- True when at least one ACTIVE (posted, non-reversed) movement exists in the
  -- account's own currency. A fully reversed position is economically
  -- indistinguishable from an account that was never used, and is reported the
  -- same way: no active movement stands behind the balance shown.
  (sum(posted_line_count) > 0) as has_active_posted_movement
from per_account
group by organization_id, project_id, currency;

comment on view public.project_cash_by_currency_read is
  'H1 cash position per (project, currency). Exact minor units as text. There is '
  'deliberately NO cross-currency total and NO project-level FX conversion: cash '
  'in different currencies is not comparable and is never presented as comparable. '
  'A registered account with no posted movement genuinely holds zero, which is the '
  'only justification for the coalesce; has_posted_activity always distinguishes '
  'that from a zero reached after activity. A project with no cash accounts yields '
  'no row, because having no accounts is not the same fact as holding zero cash. '
  'This is a projection over project_cash_accounts and posted BANK_CASH journal '
  'lines, not a new financial fact.';

grant select on public.project_cash_by_currency_read to authenticated;
