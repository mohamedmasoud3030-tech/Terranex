-- GF-004 / S2 independent-review regression coverage.
-- Runs after 04_s2_cost_and_cash.sql, which leaves s2_obl_expense with its
-- authorization posting reversed and all downstream payments reversed.

select id as s2_regression_obligation
from public.cost_obligations
where idempotency_key='s2-obl-exp-0001' \gset

select id as s2_regression_account
from public.project_cash_accounts
where name='حساب بنك المشروع'
limit 1 \gset

-- The immutable obligation row still says AUTHORIZED after reversal; payment
-- eligibility must therefore come from the active journal relationship.
select 1/case when (
  select status='AUTHORIZED'
  from public.cost_obligations
  where id=:'s2_regression_obligation'
) then 1 else 0 end as s2_reversed_obligation_row_remains_authorized;

select 1/case when exists (
  select 1
  from public.journal_batches original
  join public.journal_batches reversal
    on reversal.reversal_of_batch_id=original.id
  where original.source_type='COST_OBLIGATION'
    and original.source_id=:'s2_regression_obligation'
) then 1 else 0 end as s2_obligation_authorization_is_reversed;

select 1/case when s2_expect_raise(
  '00000000-0000-4000-8000-000000000001',
  format(
    $$select public.pay_cost_obligation(
      '10000000-0000-4000-8000-000000000001',
      %L,
      %L,
      1,
      date '2026-09-10',
      's2-pay-after-reversed-auth'
    )$$,
    :'s2_regression_obligation',
    :'s2_regression_account'
  ),
  'P0001'
) then 1 else 0 end as s2_payment_after_reversed_obligation_rejected;

select 'S2 integrity regression SQL PASS' as result;
