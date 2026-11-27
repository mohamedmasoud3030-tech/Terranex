-- Owner insights gate (invention stream E): the three org-level read views
-- exist, are reversal-aware, stay consistent with their source read models,
-- and deny non-members through the underlying RLS.

-- 1. Weekly cash totals equal a reversal-aware aggregation of BANK_CASH
--    journal lines for the same organization.
select 1/case when (
  select coalesce(sum(in_minor_units::bigint), 0)
  from public.owner_weekly_cash_read
  where organization_id = '10000000-0000-4000-8000-000000000001'
) = (
  select coalesce(sum(jl.debit_minor_units), 0)
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
  where jl.organization_id = '10000000-0000-4000-8000-000000000001'
    and jb.reversal_of_batch_id is null
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
) then 1 else 0 end as owner_weekly_in_matches_ledger;

select 1/case when (
  select coalesce(sum(out_minor_units::bigint), 0)
  from public.owner_weekly_cash_read
  where organization_id = '10000000-0000-4000-8000-000000000001'
) = (
  select coalesce(sum(jl.credit_minor_units), 0)
  from public.journal_lines jl
  join public.journal_batches jb on jb.id = jl.batch_id
  join public.semantic_accounts sa on sa.id = jl.account_id and sa.role = 'BANK_CASH'
  where jl.organization_id = '10000000-0000-4000-8000-000000000001'
    and jb.reversal_of_batch_id is null
    and not exists (select 1 from public.journal_batches rb where rb.reversal_of_batch_id = jb.id)
) then 1 else 0 end as owner_weekly_out_matches_ledger;

-- 2. Overdue view only surfaces authorized, unreversed, outstanding,
--    past-due obligations, with days_overdue consistent with the due date.
select 1/case when not exists (
  select 1
  from public.owner_overdue_obligations_read v
  where not exists (
    select 1
    from public.cost_obligation_position_read op
    where op.obligation_id = v.obligation_id
      and op.status = 'AUTHORIZED'
      and not op.is_reversed
      and op.outstanding_minor_units::bigint > 0
      and op.transaction_date < current_date
      and op.outstanding_minor_units = v.outstanding_minor_units
      and v.days_overdue = current_date - v.due_date
  )
) then 1 else 0 end as owner_overdue_consistent_with_position;

-- 3. Suggestions never reference reconciled lines, kinds stay in the locked
--    set, and a PAY_OBLIGATION suggestion always matches the line amount to
--    the obligation outstanding in the same currency.
select 1/case when not exists (
  select 1
  from public.owner_bank_line_suggestions_read s
  join public.bank_statement_line_status_read l on l.line_id = s.line_id
  where l.is_reconciled
) then 1 else 0 end as owner_suggestions_skip_reconciled;

select 1/case when not exists (
  select 1 from public.owner_bank_line_suggestions_read
  where suggestion_kind not in ('PAY_OBLIGATION', 'RECORD_OUTFLOW', 'RECORD_INFLOW')
) then 1 else 0 end as owner_suggestion_kind_set_locked;

select 1/case when not exists (
  select 1
  from public.owner_bank_line_suggestions_read s
  join public.cost_obligation_position_read op on op.obligation_id = s.suggested_obligation_id
  where s.suggestion_kind = 'PAY_OBLIGATION'
    and (op.outstanding_minor_units::bigint <> -s.amount_minor_units::bigint
         or op.currency <> s.currency)
) then 1 else 0 end as owner_suggestion_amount_exact;

-- 4. Tenant isolation: a non-member sees no rows through any of the views.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000099',
  $$select 1 from public.owner_weekly_cash_read limit 1$$) then 1 else 0 end as owner_weekly_readable_by_authenticated;

select s2_run('00000000-0000-4000-8000-000000000099',
  $$create temp table _nonmember_probe as
    select (select count(*) from public.owner_weekly_cash_read) as weekly,
           (select count(*) from public.owner_overdue_obligations_read) as overdue,
           (select count(*) from public.owner_bank_line_suggestions_read) as suggestions$$);

select 1/case when (
  select weekly + overdue + suggestions from _nonmember_probe
) = 0 then 1 else 0 end as owner_views_deny_nonmember;

drop table _nonmember_probe;

select 'Owner insights SQL PASS' as result;
