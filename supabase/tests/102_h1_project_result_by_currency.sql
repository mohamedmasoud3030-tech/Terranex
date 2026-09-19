-- H1 — Project Brief Result panel: management operating result by currency.
--
-- The live defect this replaces had two parts on the same surface:
--
--   1. The project page summed `property_realized_result_read.realized_result_
--      minor_units` across every recognition row with a reduce() and stamped the
--      total with `investment_projects.reporting_currency`. That view is S4 Real
--      Estate only, so for an Agriculture or Livestock project it yields no row
--      at all and the reduce() reported a confident 0 — a fabricated zero, not
--      an absent result.
--
--   2. `project_operating_result_read`, the H1 result truth, joins every
--      currency-aware CTE with `and <cte>.currency = p.reporting_currency`.
--      Facts posted in another currency are neither aggregated nor disclosed:
--      they are silently DROPPED, and the remaining result is still labelled
--      with the project reporting currency. That is the more dangerous of the
--      two, because a dropped revenue line looks identical to no revenue.
--
-- This gate proves both on one fixture, then proves the replacement contract.

insert into auth.users values ('00c00000-0000-4000-8000-0000000000c1')
  on conflict (id) do nothing;
insert into auth.users values ('00c00000-0000-4000-8000-0000000000c2')
  on conflict (id) do nothing;

create or replace function public.h1r_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'H1 RESULT ASSERTION FAILED: %', p_message;
  end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00c00000-0000-4000-8000-0000000000c1', false);

select public.create_organization('منظمة النتيجة H1') as h1r_org \gset
select public.create_investment_project(
  :'h1r_org'::uuid, 'مشروع نتيجة متعدد العملات', 'H1-RES', 'إثبات فصل عملات النتيجة',
  'AGRICULTURE') as h1r_project \gset
-- A second project that will deliberately get no result fact at all.
select public.create_investment_project(
  :'h1r_org'::uuid, 'مشروع بلا نتيجة', 'H1-NORES', 'إثبات التمييز عن الصفر',
  'AGRICULTURE') as h1r_bare \gset

-- ---------------------------------------------------------------------------
-- No result fact yet: no rows at all, in either project.
-- ---------------------------------------------------------------------------
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid) = 0,
  'a project with no posted revenue, disposal or cost yields no row, not a zero');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_bare'::uuid) = 0,
  'a project that never posts a result fact also yields no row');

-- The reduce() the page performed over an empty result set produced 0, which is
-- exactly the fabricated zero this contract removes. Nothing here can produce it.
select public.h1r_assert(
  (select count(*) from public.property_realized_result_read
    where project_id = :'h1r_project'::uuid) = 0,
  'the legacy page source has no row for this project, so its reduce() yielded 0');

-- A supplier party is required before a cost obligation can be authorized.
set role authenticated;
select set_config('request.jwt.claim.sub', '00c00000-0000-4000-8000-0000000000c1', false);
select public.create_party(:'h1r_org'::uuid, 'مورد نتيجة H1', 'PERSON') as h1r_party \gset

-- ---------------------------------------------------------------------------
-- Post revenue and cost in TWO currencies. Journal batches hold one currency
-- each, so this is two batches. Amounts are chosen so the cross-currency sum is
-- unmistakable: 10,000.00 EGP and 5,000.000 OMR.
-- ---------------------------------------------------------------------------
reset role;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, 'AGRICULTURE_SALE_RECOGNITION',
       :'h1r_project'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid,
       'h1r-batch-egp-0001', repeat('0', 64)
returning id as h1r_egp_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       10000000, 0, 'EGP', current_date, current_date
union all
select :'h1r_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       (select id from public.semantic_accounts where role = 'AGRICULTURE_SALE_REVENUE'),
       0, 10000000, 'EGP', current_date, current_date;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, 'AGRICULTURE_SALE_RECOGNITION',
       :'h1r_project'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid,
       'h1r-batch-omr-0001', repeat('0', 64)
returning id as h1r_omr_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       5000000, 0, 'OMR', current_date, current_date
union all
select :'h1r_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       (select id from public.semantic_accounts where role = 'AGRICULTURE_SALE_REVENUE'),
       0, 5000000, 'OMR', current_date, current_date;

-- Costs: 3,000.00 EGP and 1,000.000 OMR, each against its own obligation.
insert into public.cost_obligations(
  organization_id, project_id, party_id, description, amount_minor_units, currency,
  transaction_date, cost_treatment, status, prepared_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, p.id, 'تكلفة تشغيل EGP', 3000000, 'EGP',
       current_date, 'EXPENSE', 'AUTHORIZED',
       '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-obl-egp-0001', repeat('0', 64)
from public.parties p where p.id = :'h1r_party'::uuid
returning id as h1r_egp_obl \gset

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, 'COST_OBLIGATION',
       :'h1r_egp_obl'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid,
       'h1r-batch-egp-cost-0001', repeat('0', 64)
returning id as h1r_egp_cost_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, obligation_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_egp_cost_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       :'h1r_egp_obl'::uuid,
       (select id from public.semantic_accounts where role = 'PROJECT_EXPENSE'),
       3000000, 0, 'EGP', current_date, current_date
union all
select :'h1r_egp_cost_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       :'h1r_egp_obl'::uuid,
       (select id from public.semantic_accounts where role = 'SUPPLIER_PAYABLE'),
       0, 3000000, 'EGP', current_date, current_date;

insert into public.cost_obligations(
  organization_id, project_id, party_id, description, amount_minor_units, currency,
  transaction_date, cost_treatment, status, prepared_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, p.id, 'تكلفة تشغيل OMR', 1000000, 'OMR',
       current_date, 'EXPENSE', 'AUTHORIZED',
       '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-obl-omr-0001', repeat('0', 64)
from public.parties p where p.id = :'h1r_party'::uuid
returning id as h1r_omr_obl \gset

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_project'::uuid, 'COST_OBLIGATION',
       :'h1r_omr_obl'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid,
       'h1r-batch-omr-cost-0001', repeat('0', 64)
returning id as h1r_omr_cost_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, obligation_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_omr_cost_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       :'h1r_omr_obl'::uuid,
       (select id from public.semantic_accounts where role = 'PROJECT_EXPENSE'),
       1000000, 0, 'OMR', current_date, current_date
union all
select :'h1r_omr_cost_batch'::uuid, :'h1r_org'::uuid, :'h1r_project'::uuid,
       :'h1r_omr_obl'::uuid,
       (select id from public.semantic_accounts where role = 'SUPPLIER_PAYABLE'),
       0, 1000000, 'OMR', current_date, current_date;

-- ---------------------------------------------------------------------------
-- NEGATIVE CONTROL 1 — the H1 project-grain view silently drops the OMR line.
-- ---------------------------------------------------------------------------
select * from public.project_operating_result_read where project_id = :'h1r_project'::uuid;

select public.h1r_assert(
  (select sale_revenue_minor_units from public.project_operating_result_read
    where project_id = :'h1r_project'::uuid) = '10000000',
  'the project-grain view reports only the EGP revenue (10000000)');
select public.h1r_assert(
  (select count(*) from public.project_operating_result_read
    where project_id = :'h1r_project'::uuid
      and sale_revenue_minor_units::bigint = 15000000) = 0,
  'the project-grain view never reports 15000000, the cross-currency sum');
-- The 5,000.000 OMR revenue is not aggregated and not disclosed anywhere.
select public.h1r_assert(
  (select count(*) from public.project_operating_result_read r
    where r.project_id = :'h1r_project'::uuid
      and r.sale_revenue_minor_units::bigint = 5000000) = 0,
  'the OMR revenue is absent from the project-grain view, not merely relabelled');
select public.h1r_assert(
  (select currency from public.project_operating_result_read
    where project_id = :'h1r_project'::uuid) = 'EGP',
  'the project-grain view stamps the surviving EGP-only result with the reporting currency');

-- ---------------------------------------------------------------------------
-- The replacement: one qualified row per currency.
-- ---------------------------------------------------------------------------
select * from public.project_result_by_currency_read where project_id = :'h1r_project'::uuid;

select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid) = 2,
  'revenue and cost posted in EGP and OMR produce two rows, not one');
select public.h1r_assert(
  (select currency from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid order by currency limit 1) = 'EGP',
  'the EGP row is labelled EGP, from the facts rather than the project');
select public.h1r_assert(
  (select sale_revenue_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'OMR') = '5000000',
  'the OMR revenue is reported in its own row, where the project-grain view dropped it');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where r.project_id = :'h1r_project'::uuid
      and r.sale_revenue_minor_units::bigint = 15000000) = 0,
  'no row ever holds the cross-currency revenue sum 15000000');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where r.project_id = :'h1r_project'::uuid
      and (r.management_result ->> 'amount_minor_units')::bigint = 11000000) = 0,
  'no row ever holds the cross-currency result sum 11000000 (7000000 EGP + 4000000 OMR)');

-- ---------------------------------------------------------------------------
-- Classification vs deduction, and the "exactly once" invariant.
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00c00000-0000-4000-8000-0000000000c1', false);

-- Before classification the whole eligible cost is UNCLASSIFIED, so coverage is
-- NONE and the result must be suppressed rather than presented as if it were a
-- margin. This is the ADR 0034 guard against a 100%-margin artifact.
select public.h1r_assert(
  (select cost_classification_status from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = 'NONE',
  'an entirely unclassified eligible cost is NONE, so the result is suppressed');
select public.h1r_assert(
  (select unclassified_eligible_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = '3000000',
  'the unclassified amount is disclosed separately from the deducted amount');
select public.h1r_assert(
  (select result_deducted_cost_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = '0',
  'an unclassified cost is not deducted: classification is not deduction');

select public.classify_project_cost(
  :'h1r_org'::uuid, :'h1r_project'::uuid, :'h1r_egp_obl'::uuid, 'PROJECT_OVERHEAD',
  'تكاليف إدارية عامة للمشروع EGP', 'h1r-cls-egp-0001');
select public.classify_project_cost(
  :'h1r_org'::uuid, :'h1r_project'::uuid, :'h1r_omr_obl'::uuid, 'PROJECT_OVERHEAD',
  'تكاليف إدارية عامة للمشروع OMR', 'h1r-cls-omr-0001');

select public.h1r_assert(
  (select cost_classification_status from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = 'COMPLETE',
  'declared overhead completes coverage without requiring 100% attribution');
select public.h1r_assert(
  (select attributed_operating_cost_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = '0',
  'overhead is a separate bucket from attributed cost: classification is not deduction');

-- The reconciling identity, asserted in every row of every project.
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where (r.management_result ->> 'amount_minor_units')::bigint
       <> r.result_revenue_minor_units::bigint - r.result_deducted_cost_minor_units::bigint) = 0,
  'result = result revenue - result deducted cost, in every row');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where r.result_deducted_cost_minor_units::bigint
       <> r.attributed_operating_cost_minor_units::bigint
        - case when r.sector = 'REAL_ESTATE'
               then r.selling_cost_attributed_minor_units::bigint else 0 end
        + r.project_overhead_minor_units::bigint) = 0,
  'deduction = attributed (less RE selling, already netted in disposal) + overhead');

-- Revenue and deduction are each counted once: the EGP row is 10000000 - 3000000.
select public.h1r_assert(
  (select (management_result ->> 'amount_minor_units') from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'EGP') = '7000000',
  'the EGP result is 10000000 revenue less 3000000 overhead');
select public.h1r_assert(
  (select (management_result ->> 'amount_minor_units') from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'OMR') = '4000000',
  'the OMR result is 5000000 revenue less 1000000 overhead');

-- ---------------------------------------------------------------------------
-- Reversal semantics: an original effect and its reversal never both count.
-- ---------------------------------------------------------------------------
reset role;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash, reversal_of_batch_id)
select :'h1r_org'::uuid, :'h1r_project'::uuid, 'AGRICULTURE_SALE_RECOGNITION',
       :'h1r_omr_batch'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid,
       'h1r-batch-omr-reversal-0001', repeat('0', 64), :'h1r_omr_batch'::uuid;

select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'OMR') = 1,
  'reversing the OMR revenue batch removes the OMR revenue row, it does not negate it');
select public.h1r_assert(
  (select coalesce(sale_revenue_minor_units::bigint, 0) from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'OMR') = 0,
  'a reversed recognition contributes zero revenue, not double the effect');
-- The result after reversal is revenue 0 less the surviving 1000000 OMR
-- overhead: a genuine negative operating result, not a double subtraction.
select public.h1r_assert(
  (select (management_result ->> 'amount_minor_units') from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid and currency = 'OMR') = '-1000000',
  'the reversal removes revenue exactly once; the surviving overhead remains deducted once');

-- ---------------------------------------------------------------------------
-- NEGATIVE CONTROL 2 — the expression the live page actually evaluated.
--
--   results.reduce((sum, r) => sum + BigInt(r.realized_result_minor_units), 0n)
--   rendered with formatMinorUnits(realizedResult, project.reporting_currency)
--
-- `property_realized_result_read` is the S4 Real Estate disposal view. For an
-- Agriculture project it has no rows, so the reduce() yielded 0 and the page
-- printed a confident 0.00 EGP as "النتيجة المحققة".
-- ---------------------------------------------------------------------------
select public.h1r_assert(
  (select coalesce(sum(realized_result_minor_units::bigint), 0)
     from public.property_realized_result_read
    where project_id = :'h1r_project'::uuid) = 0,
  'the live page expression yields 0 for this project, which has a real result');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid) = 2,
  'the contract reports two real currency results where the page reported one zero');
select public.h1r_assert(
  (select coalesce(sum((management_result ->> 'amount_minor_units')::bigint), 0)
     from public.project_result_by_currency_read
    where project_id = :'h1r_project'::uuid) <> 0,
  'the project result is non-zero, so the page zero was fabricated, not measured');

-- ---------------------------------------------------------------------------
-- NEGATIVE CONTROL 3 — the cross-currency sum itself.
--
-- `property_dispositions.currency` and `property_sale_recognitions.currency`
-- are each constrained only by `^[A-Z]{3}$`, so two disposals of the same
-- project may be denominated in different currencies. The live page summed
-- `realized_result_minor_units` over every recognition row and labelled the
-- total with `project.reporting_currency`.
--
-- Amounts: EGP result 3,000.00 (3000000) and OMR result 1,000.000 (1000000).
-- The defective sum is 4000000 presented as EGP — a number no ledger supports.
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00c00000-0000-4000-8000-0000000000c1', false);

select public.create_investment_project(
  :'h1r_org'::uuid, 'مشروع عقاري متعدد عملات التخارج', 'H1-RE2', 'إثبات جمع التخارجات',
  'REAL_ESTATE') as h1r_re \gset

reset role;

insert into public.real_estate_project_profiles(
  organization_id, project_id, strategy, created_by, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, 'DEVELOP_SELL',
        '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-profile-0001', repeat('0', 64))
returning id as h1r_profile \gset

insert into public.property_assets(
  organization_id, project_id, profile_id, name, created_by, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_profile'::uuid, 'أصل عقاري H1',
        '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-asset-0001', repeat('0', 64))
returning id as h1r_asset \gset

-- A property asset may carry only one disposition, so the OMR disposal needs
-- its own asset within the same project.
insert into public.property_assets(
  organization_id, project_id, profile_id, name, created_by, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_profile'::uuid, 'أصل عقاري H1 ب',
        '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-asset-0002', repeat('0', 64))
returning id as h1r_asset_omr \gset

-- EGP disposal: proceeds 8,000.00, carrying 5,000.00 => result 3,000.00 EGP.
insert into public.property_dispositions(
  organization_id, project_id, property_asset_id, buyer_party_id,
  agreement_reference, agreement_evidence_reference, agreed_proceeds_minor_units,
  currency, agreement_date, status, prepared_by, approved_by, approved_at,
  approval_idempotency_key, approval_request_hash, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_asset'::uuid, :'h1r_party'::uuid,
        'H1-RE2/EGP', 'H1-RE2/EGP/evidence', 8000000, 'EGP', current_date, 'APPROVED',
        '00c00000-0000-4000-8000-0000000000c1'::uuid,
        '00c00000-0000-4000-8000-0000000000c1'::uuid, now(),
        'h1r-disp-egp-approve-0001', repeat('0', 64),
        'h1r-disp-egp-0001', repeat('0', 64))
returning id as h1r_disp_egp \gset

-- OMR disposal of the same project: result 1,000.000 OMR.
insert into public.property_dispositions(
  organization_id, project_id, property_asset_id, buyer_party_id,
  agreement_reference, agreement_evidence_reference, agreed_proceeds_minor_units,
  currency, agreement_date, status, prepared_by, approved_by, approved_at,
  approval_idempotency_key, approval_request_hash, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_asset_omr'::uuid, :'h1r_party'::uuid,
        'H1-RE2/OMR', 'H1-RE2/OMR/evidence', 2000000, 'OMR', current_date, 'APPROVED',
        '00c00000-0000-4000-8000-0000000000c1'::uuid,
        '00c00000-0000-4000-8000-0000000000c1'::uuid, now(),
        'h1r-disp-omr-approve-0001', repeat('0', 64),
        'h1r-disp-omr-0001', repeat('0', 64))
returning id as h1r_disp_omr \gset

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_re'::uuid, 'PROPERTY_SALE_RECOGNITION',
       :'h1r_disp_egp'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-re-batch-egp-0001', repeat('0', 64)
returning id as h1r_re_egp_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_re_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       8000000, 0, 'EGP', current_date, current_date
union all
select :'h1r_re_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'REAL_ESTATE_SALE_REVENUE'),
       0, 8000000, 'EGP', current_date, current_date
union all
select :'h1r_re_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'REAL_ESTATE_COST_OF_SALE'),
       5000000, 0, 'EGP', current_date, current_date
union all
select :'h1r_re_egp_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'DEVELOPMENT_WIP'),
       0, 5000000, 'EGP', current_date, current_date;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1r_org'::uuid, :'h1r_re'::uuid, 'PROPERTY_SALE_RECOGNITION',
       :'h1r_disp_omr'::uuid, current_date,
       '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-re-batch-omr-0001', repeat('0', 64)
returning id as h1r_re_omr_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1r_re_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       2000000, 0, 'OMR', current_date, current_date
union all
select :'h1r_re_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'REAL_ESTATE_SALE_REVENUE'),
       0, 2000000, 'OMR', current_date, current_date
union all
select :'h1r_re_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'REAL_ESTATE_COST_OF_SALE'),
       1000000, 0, 'OMR', current_date, current_date
union all
select :'h1r_re_omr_batch'::uuid, :'h1r_org'::uuid, :'h1r_re'::uuid,
       (select id from public.semantic_accounts where role = 'DEVELOPMENT_WIP'),
       0, 1000000, 'OMR', current_date, current_date;

insert into public.property_sale_recognitions(
  organization_id, project_id, property_asset_id, disposition_id,
  recognized_proceeds_minor_units, carrying_cost_minor_units, currency,
  recognition_date, journal_batch_id, recognized_by, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_asset'::uuid, :'h1r_disp_egp'::uuid,
        8000000, 5000000, 'EGP', current_date, :'h1r_re_egp_batch'::uuid,
        '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-rec-egp-0001', repeat('0', 64));

insert into public.property_sale_recognitions(
  organization_id, project_id, property_asset_id, disposition_id,
  recognized_proceeds_minor_units, carrying_cost_minor_units, currency,
  recognition_date, journal_batch_id, recognized_by, idempotency_key, request_hash)
values (:'h1r_org'::uuid, :'h1r_re'::uuid, :'h1r_asset_omr'::uuid, :'h1r_disp_omr'::uuid,
        2000000, 1000000, 'OMR', current_date, :'h1r_re_omr_batch'::uuid,
        '00c00000-0000-4000-8000-0000000000c1'::uuid, 'h1r-rec-omr-0001', repeat('0', 64));

select project_id, currency, realized_result_minor_units
  from public.property_realized_result_read where project_id = :'h1r_re'::uuid;

-- The two disposals really do sit in two currencies.
select public.h1r_assert(
  (select count(distinct currency) from public.property_realized_result_read
    where project_id = :'h1r_re'::uuid) = 2,
  'two disposals of one project can be denominated in different currencies');
select public.h1r_assert(
  (select realized_result_minor_units from public.property_realized_result_read
    where project_id = :'h1r_re'::uuid and currency = 'EGP') = '3000000',
  'the EGP disposal realizes 3000000');
select public.h1r_assert(
  (select realized_result_minor_units from public.property_realized_result_read
    where project_id = :'h1r_re'::uuid and currency = 'OMR') = '1000000',
  'the OMR disposal realizes 1000000');

-- THE DEFECT: the live page expression adds them and calls the result EGP.
select public.h1r_assert(
  (select sum(realized_result_minor_units::bigint) from public.property_realized_result_read
    where project_id = :'h1r_re'::uuid) = 4000000,
  'NEGATIVE CONTROL: the page reduce() produced 4000000 = 3000000 EGP + 1000000 OMR');
select public.h1r_assert(
  (select count(*) from public.property_realized_result_read r
    where r.project_id = :'h1r_re'::uuid
      and r.realized_result_minor_units::bigint = 4000000) = 0,
  'no single realized-result fact is 4000000; the sum is an artifact of the page');
select public.h1r_assert(
  (select reporting_currency from public.investment_projects
    where id = :'h1r_re'::uuid) = 'EGP',
  'the project reporting currency is EGP, so 4000000 was presented as EGP');

-- The contract keeps the two disposal currencies apart.
select * from public.project_result_by_currency_read where project_id = :'h1r_re'::uuid;

select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where project_id = :'h1r_re'::uuid) = 2,
  'the contract reports the two disposal currencies as two rows');
select public.h1r_assert(
  (select realized_disposal_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_re'::uuid and currency = 'EGP') = '3000000',
  'the EGP row carries only the EGP disposal result');
select public.h1r_assert(
  (select realized_disposal_minor_units from public.project_result_by_currency_read
    where project_id = :'h1r_re'::uuid and currency = 'OMR') = '1000000',
  'the OMR row carries only the OMR disposal result');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where r.project_id = :'h1r_re'::uuid
      and r.realized_disposal_minor_units::bigint = 4000000) = 0,
  'no row of the contract ever holds the 4000000 cross-currency sum');
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read r
    where r.project_id = :'h1r_re'::uuid
      and (r.management_result ->> 'amount_minor_units')::bigint = 4000000) = 0,
  'the qualified result object never carries the cross-currency sum either');

-- ---------------------------------------------------------------------------
-- Structural guarantees.
-- ---------------------------------------------------------------------------
select public.h1r_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_result_by_currency_read'
      and column_name ~* '(total|combined|converted|consolidat|all_currencies|_sum)') = 0,
  'the read model exposes no field representing a cross-currency result total');
select public.h1r_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_result_by_currency_read'
      and column_name ~* '(fx|rate)') = 0,
  'the read model performs no FX conversion');
select public.h1r_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_result_by_currency_read'
      and data_type = 'jsonb') = 1,
  'the only jsonb column is the qualified result object; there is no bare amount');
select public.h1r_assert(
  (select count(*) from public.investment_projects p
    where p.organization_id = :'h1r_org'::uuid
      and not exists (select 1 from public.project_result_by_currency_read c
                      where c.project_id = p.id)) = 1,
  'only the project with no result fact is absent; the other is present');

-- The amount is unreachable without its qualification: it exists only as a key
-- inside management_result, never as a column of its own.
select public.h1r_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_result_by_currency_read'
      and column_name ~* '(result_amount|amount_minor|operating_result_minor)') = 0,
  'no column exposes a naked result amount outside the qualified object');

-- ---------------------------------------------------------------------------
-- Tenant isolation: a non-member sees nothing.
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', '00c00000-0000-4000-8000-0000000000c2', false);
select public.h1r_assert(
  (select count(*) from public.project_result_by_currency_read
    where organization_id = :'h1r_org'::uuid) = 0,
  'a non-member sees no result rows for the organization');

reset role;
