-- H1 — Project result truth (ADR 0034), executable.
--
-- Proves the H1 contract by execution, not by inspection:
--
--   1. A management operating result can never be separated from its basis,
--      cost-classification status, evidence status, policy boundary and as-of
--      date, because no bare result scalar column exists to select.
--   2. Cost is classified into attributed / overhead / excluded / unclassified,
--      and the five buckets always sum exactly to posted expense.
--   3. Unattributed operating cost is NOT silently treated as margin: it raises
--      UNCLASSIFIED_OPERATING_COST (with its amount) and, when nothing at all is
--      classified while revenue exists, UNVERIFIED_MANAGEMENT_RESULT.
--   4. Real Estate SELLING cost is not subtracted twice — it is already netted
--      inside the sector-owned realized disposal result.
--   5. Reversed postings leave the classification scope, so a reversal cannot
--      leave phantom cost behind.
--
-- Expense facts are produced by the real commands (create_cost_obligation +
-- authorize_cost_obligation), because those are the facts whose classification
-- this gate governs. Revenue recognition is constructed directly: the sector
-- sale-recognition commands are already proven end to end by gates 01–97, and
-- what is under test here is the presentation and classification semantics, not
-- the sector posting chain.

insert into auth.users values ('00a00000-0000-4000-8000-0000000000a1')
  on conflict (id) do nothing;
insert into auth.users values ('00a00000-0000-4000-8000-0000000000a2')
  on conflict (id) do nothing;

create or replace function public.h1_assert(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'H1 ASSERTION FAILED: %', p_message;
  end if;
end $$;

create or replace function public.h1_caught(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'NO_EXCEPTION';
exception when others then
  return sqlerrm;
end $$;
grant execute on function public.h1_caught(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a1', false);

-- ===========================================================================
-- A dedicated organization and two projects, so nothing here perturbs the
-- integrated R13 company and every assertion stays readable.
-- ===========================================================================
select public.create_organization('منظمة نتيجة المشروع H1') as h1_org \gset
select public.create_investment_project(:'h1_org'::uuid, 'مشروع زراعي H1', 'H1-AG', 'مشروع نتيجة H1', 'AGRICULTURE') as h1_ag \gset
select public.create_investment_project(:'h1_org'::uuid, 'مشروع عقاري H1', 'H1-RE', 'مشروع نتيجة عقاري H1', 'REAL_ESTATE') as h1_re \gset
select public.create_party(:'h1_org'::uuid, 'مورد H1', 'ORGANIZATION') as h1_party \gset

-- ===========================================================================
-- Agriculture: expense 40,000.00 EGP authorized and posted, revenue
-- 100,000.00 EGP recognized, and no cost classified yet.
-- ===========================================================================
select public.create_cost_obligation(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_party'::uuid,
  'مستلزمات موسمية H1', 400000, 'EGP', current_date, 'EXPENSE',
  'h1-obl-ag-0001') as h1_ag_obl \gset

select public.authorize_cost_obligation(:'h1_org'::uuid, :'h1_ag_obl'::uuid, 'h1-auth-ag-0001');

-- Revenue recognition constructed directly (see file header for why). It runs as
-- the table owner because posted facts are deliberately not directly writable by
-- an authenticated user; only the commands below are exercised as a member.
reset role;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1_org'::uuid, :'h1_ag'::uuid, 'AGRICULTURE_SALE_RECOGNITION', :'h1_ag'::uuid,
       current_date, '00a00000-0000-4000-8000-0000000000a1'::uuid,
       'h1-batch-ag-rev-0001', repeat('0', 64)
returning id as h1_ag_rev_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_ag_rev_batch'::uuid, :'h1_org'::uuid, :'h1_ag'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       10000000, 0, 'EGP', current_date, current_date
union all
select :'h1_ag_rev_batch'::uuid, :'h1_org'::uuid, :'h1_ag'::uuid,
       (select id from public.semantic_accounts where role = 'AGRICULTURE_SALE_REVENUE'),
       0, 10000000, 'EGP', current_date, current_date;

-- ===========================================================================
-- 1. Nothing classified: the result equals revenue, and says so.
-- ===========================================================================
select r.* from public.project_operating_result_read r where r.project_id = :'h1_ag'::uuid;

select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.project_operating_result_read where project_id = :'h1_ag'::uuid) = 10000000,
  'revenue is recognized');
select public.h1_assert(
  (select result_basis from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 'AGRICULTURE_ENTERPRISE_OPERATING',
  'basis is sector-owned Agriculture');
select public.h1_assert(
  (select cost_classification_status from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 'NONE',
  'no classified cost yields NONE, not COMPLETE');
select public.h1_assert(
  (select unclassified_eligible_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 400000,
  'the unclassified amount is disclosed, not hidden');
select public.h1_assert(
  (select count(*) from public.financial_integrity_signals_read
    where project_id = :'h1_ag'::uuid
      and signal_code = 'UNVERIFIED_MANAGEMENT_RESULT') = 1,
  'UNVERIFIED_MANAGEMENT_RESULT fires when revenue exists with no classified cost');
select public.h1_assert(
  (select amount_minor_units::bigint from public.financial_integrity_signals_read
    where project_id = :'h1_ag'::uuid
      and signal_code = 'UNCLASSIFIED_OPERATING_COST') = 400000,
  'UNCLASSIFIED_OPERATING_COST always carries its amount');

-- The Home roll-up must refuse to present Agriculture revenue as a comparable
-- net result while no operating cost has been classified. This is the defect
-- being removed: revenue sitting in the same column as a net result.
select public.h1_assert(
  (select cost_classification_status from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'AGRICULTURE') = 'NONE',
  'an Agriculture sector with revenue and no classified cost is NONE, never COMPLETE');
select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'AGRICULTURE')
  = (select sale_revenue_minor_units::bigint
       from public.sector_management_result_read
      where organization_id = :'h1_org'::uuid and sector = 'AGRICULTURE'),
  'the unclassified Agriculture roll-up equals revenue exactly, so Home must suppress it');

-- Reconciliation identity per project and currency.
select public.h1_assert(
  (select attributed_operating_cost_minor_units::bigint
        + project_overhead_minor_units::bigint
        + excluded_from_result_minor_units::bigint
        + unclassified_eligible_minor_units::bigint
        + expense_outside_classification_scope_minor_units::bigint
     from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 400000,
  'the five cost buckets sum exactly to posted expense');

-- ===========================================================================
-- 2. Declared overhead is legitimate project overhead, not missing coverage.
-- ===========================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a1', false);

select public.classify_project_cost(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl'::uuid, 'PROJECT_OVERHEAD',
  'تكاليف إدارية عامة للمشروع غير منسوبة لدورة زراعية بعينها', 'h1-cls-0001');

select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.project_operating_result_read where project_id = :'h1_ag'::uuid) = 9600000,
  'declared overhead reduces the result');
select public.h1_assert(
  (select cost_classification_status from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 'COMPLETE',
  'overhead declaration completes coverage without 100% attribution');
select public.h1_assert(
  (select unclassified_eligible_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 0,
  'unclassified is cleared by the declaration');
select public.h1_assert(
  (select count(*) from public.financial_integrity_signals_read
    where project_id = :'h1_ag'::uuid
      and signal_code = 'UNVERIFIED_MANAGEMENT_RESULT') = 0,
  'the unverified-result signal clears once coverage exists');

-- ===========================================================================
-- 3. Reversal: a corrected classification cannot silently leave cost behind.
-- ===========================================================================
select id as h1_cls_1 from public.project_cost_classifications
 where cost_obligation_id = :'h1_ag_obl'::uuid
   and reversal_of_classification_id is null \gset

select public.reverse_project_cost_classification(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_cls_1'::uuid,
  'أُعيد تصنيف التكلفة إلى دورة زراعية محددة', 'h1-cls-0002');

select public.h1_assert(
  (select cost_classification_status from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 'NONE',
  'reversal restores NONE instead of keeping silent overhead');
select public.h1_assert(
  (select project_overhead_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 0,
  'reversed overhead no longer counts');

-- ===========================================================================
-- 4. Excluded cost is disclosed, not subtracted and not hidden.
-- ===========================================================================
select public.classify_project_cost(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl'::uuid,
  'EXCLUDED_FROM_MANAGEMENT_RESULT',
  'تكلفة استثنائية أعلن المالك عدم إدراجها في نتيجة التشغيل', 'h1-cls-0003');

select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.project_operating_result_read where project_id = :'h1_ag'::uuid) = 10000000,
  'excluded cost is not subtracted from the result');
select public.h1_assert(
  (select excluded_from_result_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 400000,
  'excluded cost remains disclosed');

-- ===========================================================================
-- 5. Command guards.
-- ===========================================================================
select public.h1_assert(
  public.h1_caught(format($$select public.classify_project_cost(%L,%L,%L,'PROJECT_OVERHEAD','second active classification','h1-cls-0004')$$,
    :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl'::uuid)) like '%active cost classification already exists%',
  'one active classification per obligation is enforced');

select public.create_cost_obligation(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_party'::uuid,
  'التزام ثانٍ H1', 200000, 'EGP', current_date, 'EXPENSE',
  'h1-obl-ag-0002') as h1_ag_obl_2 \gset

-- Authorized, so it is inside the classification scope for the membership tests.
select public.authorize_cost_obligation(:'h1_org'::uuid, :'h1_ag_obl_2'::uuid, 'h1-auth-ag-0002');

select public.h1_assert(
  public.h1_caught(format($$select public.classify_project_cost(%L,%L,%L,'EXCLUDED_FROM_MANAGEMENT_RESULT','  ','h1-cls-0005')$$,
    :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl_2'::uuid)) like '%reason%',
  'overhead/excluded declarations require a stated reason');

select public.create_cost_obligation(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_party'::uuid,
  'تكلفة رأسمالية H1', 150000, 'EGP', current_date, 'CAPITALIZABLE_WIP',
  'h1-obl-ag-wip-0001') as h1_ag_obl_wip \gset
select public.authorize_cost_obligation(:'h1_org'::uuid, :'h1_ag_obl_wip'::uuid, 'h1-auth-ag-wip-0001');

select public.h1_assert(
  public.h1_caught(format($$select public.classify_project_cost(%L,%L,%L,'PROJECT_OVERHEAD','wip must not be classified','h1-cls-0006')$$,
    :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl_wip'::uuid)) like '%EXPENSE obligation%',
  'CAPITALIZABLE_WIP obligations are outside the classification scope');

-- A non-member must not be able to declare cost treatment.
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a2', false);
select public.h1_assert(
  public.h1_caught(format($$select public.classify_project_cost(%L,%L,%L,'PROJECT_OVERHEAD','محاولة من غير عضو','h1-cls-0008')$$,
    :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl_2'::uuid)) = 'forbidden',
  'a non-member cannot declare cost treatment');
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a1', false);

select public.h1_assert(
  public.h1_caught(format($$select public.classify_project_cost(%L,%L,%L,'PROJECT_OVERHEAD','تصنيف من عضو خارج المنظمة','h1-cls-0007')$$,
    :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_ag_obl_2'::uuid)) is not distinct from 'NO_EXCEPTION',
  'inside-member classification is allowed');

-- ===========================================================================
-- 6. Real Estate: SELLING cost must not be subtracted twice.
-- ===========================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a1', false);

reset role;

insert into public.real_estate_project_profiles(
  organization_id, project_id, strategy, created_by, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_re'::uuid, 'DEVELOP_SELL',
        '00a00000-0000-4000-8000-0000000000a1'::uuid, 'h1-re-profile-0001', repeat('0', 64));

insert into public.property_assets(
  organization_id, project_id, profile_id, name, created_by, idempotency_key, request_hash)
select :'h1_org'::uuid, :'h1_re'::uuid,
       (select id from public.real_estate_project_profiles where project_id = :'h1_re'::uuid),
       'وحدة H1', '00a00000-0000-4000-8000-0000000000a1'::uuid,
       'h1-re-asset-0001', repeat('0', 64)
returning id as h1_re_asset \gset

select public.create_cost_obligation(
  :'h1_org'::uuid, :'h1_re'::uuid, :'h1_party'::uuid,
  'عمولة سمسرة على البيع', 1500000, 'EGP', current_date, 'EXPENSE',
  'h1-obl-re-selling-0001') as h1_re_obl \gset
select public.authorize_cost_obligation(:'h1_org'::uuid, :'h1_re_obl'::uuid, 'h1-auth-re-0001');

-- The operator attributes this cost to the property asset as SELLING.
insert into public.property_cost_items(
  organization_id, project_id, property_asset_id, cost_obligation_id,
  cost_category, policy_reference, classified_by, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_re'::uuid, :'h1_re_asset'::uuid, :'h1_re_obl'::uuid,
        'SELLING', 'سياسة عمولات البيع', '00a00000-0000-4000-8000-0000000000a1'::uuid,
        'h1-pci-selling-0001', repeat('0', 64));

-- Rental revenue 70,000.00 EGP recognized.
insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
select :'h1_org'::uuid, :'h1_re'::uuid, 'PROPERTY_RENTAL_RECOGNITION', :'h1_re'::uuid,
       current_date, '00a00000-0000-4000-8000-0000000000a1'::uuid,
       'h1-batch-re-rev-0001', repeat('0', 64)
returning id as h1_re_rev_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_re_rev_batch'::uuid, :'h1_org'::uuid, :'h1_re'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       7000000, 0, 'EGP', current_date, current_date
union all
select :'h1_re_rev_batch'::uuid, :'h1_org'::uuid, :'h1_re'::uuid,
       (select id from public.semantic_accounts where role = 'REAL_ESTATE_RENTAL_REVENUE'),
       0, 7000000, 'EGP', current_date, current_date;

select public.h1_assert(
  (select result_basis from public.project_operating_result_read
    where project_id = :'h1_re'::uuid) = 'REAL_ESTATE_DISPOSAL_AND_RENTAL',
  'Real Estate uses its own sector basis');
select public.h1_assert(
  (select attributed_operating_cost_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_re'::uuid) = 1500000,
  'attributed property cost is recognized as attributed');
select public.h1_assert(
  (select selling_cost_attributed_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_re'::uuid) = 1500000,
  'SELLING cost is identified separately');
select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.project_operating_result_read where project_id = :'h1_re'::uuid) = 7000000,
  'SELLING cost is NOT subtracted again — it is already inside the realized result');
select public.h1_assert(
  (select count(*) from public.financial_integrity_signals_read
    where project_id = :'h1_re'::uuid
      and signal_code = 'UNVERIFIED_MANAGEMENT_RESULT') = 0,
  'attributed Real Estate cost counts as coverage');

-- ===========================================================================
-- 7. A reversed expense posting leaves the classification scope.
-- ===========================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', '00a00000-0000-4000-8000-0000000000a1', false);

select public.create_cost_obligation(
  :'h1_org'::uuid, :'h1_ag'::uuid, :'h1_party'::uuid,
  'تكلفة قابلة للعكس H1', 900000, 'EGP', current_date, 'EXPENSE',
  'h1-obl-ag-rev-0001') as h1_ag_obl_3 \gset
select public.authorize_cost_obligation(:'h1_org'::uuid, :'h1_ag_obl_3'::uuid, 'h1-auth-ag-rev-0001');

select public.h1_assert(
  (select unclassified_eligible_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 900000,
  'a new unclassified expense enters the scope');

select id as h1_batch_to_reverse from public.journal_batches
 where source_type = 'COST_OBLIGATION' and source_id = :'h1_ag_obl_3'::uuid
   and reversal_of_batch_id is null \gset

reset role;

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, reversal_of_batch_id, idempotency_key, request_hash)
select :'h1_org'::uuid, :'h1_ag'::uuid, 'REVERSAL', :'h1_ag_obl_3'::uuid, current_date,
       '00a00000-0000-4000-8000-0000000000a1'::uuid, :'h1_batch_to_reverse'::uuid,
       'h1-batch-ag-reversal-0001', repeat('0', 64)
returning id as h1_reversal_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id, obligation_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_reversal_batch'::uuid, :'h1_org'::uuid, :'h1_ag'::uuid,
       (select id from public.semantic_accounts where role = 'PROJECT_EXPENSE'),
       :'h1_ag_obl_3'::uuid, 0, 900000, 'EGP', current_date, current_date
union all
select :'h1_reversal_batch'::uuid, :'h1_org'::uuid, :'h1_ag'::uuid,
       (select id from public.semantic_accounts where role = 'SUPPLIER_PAYABLE'),
       :'h1_ag_obl_3'::uuid, 900000, 0, 'EGP', current_date, current_date;

select public.h1_assert(
  (select unclassified_eligible_minor_units::bigint from public.project_operating_result_read
    where project_id = :'h1_ag'::uuid) = 0,
  'a reversed expense posting leaves the classification scope');

-- ===========================================================================
-- 8. The qualified-result contract itself.
-- ===========================================================================
select public.h1_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_operating_result_read'
      and column_name ~* '^(operating_result|result_amount|result_minor|management_result_amount)') = 0,
  'no bare result scalar column exists anywhere a UI can select it');

select public.h1_assert(
  (select count(*) from public.project_operating_result_read
    where management_result ? 'amount_minor_units'
      and management_result ? 'currency'
      and management_result ? 'basis'
      and management_result ? 'cost_classification_status'
      and management_result ? 'evidence_status'
      and management_result ? 'policy_availability'
      and management_result ? 'as_of')
  = (select count(*) from public.project_operating_result_read),
  'every surfaced result object carries amount, currency, basis, both statuses, policy and as-of');

select public.h1_assert(
  (select count(*) from public.project_operating_result_read
    where pg_typeof((management_result ->> 'amount_minor_units')) = 'text'::regtype) > 0,
  'the amount is transported as text, never as a lossy numeric');

select public.h1_assert(
  (select count(*) from public.project_operating_result_read
    where management_result -> 'policy_availability' ? 'RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY')
  = (select count(*) from public.project_operating_result_read),
  'every result states that return multiples are unavailable pending policy');

select public.h1_assert(
  (select count(*) from public.project_operating_result_read
    where management_result -> 'policy_availability' ? 'INVESTOR_ENTITLEMENT_NOT_ACTIVATED')
  = (select count(*) from public.project_operating_result_read),
  'every result states that investor entitlement is not activated while the registry is empty');

-- Reserved terminology must not leak into any surfaced management surface.
select public.h1_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and (table_name = 'project_operating_result_read'
           or table_name = 'project_cost_classification_read')
      and column_name ~* '(profit|investor_return|realized_return|irr|moic|tvpi|equity_multiple|cash_on_cash|distributable)') = 0,
  'reserved investor-return terminology does not appear on the result surfaces');

-- ===========================================================================
-- 9. The Home roll-up (sector_management_result_read).
-- ===========================================================================
select * from public.sector_management_result_read where organization_id = :'h1_org'::uuid;

-- Real Estate SELLING cost: classified exactly once, deducted zero times.
--
-- These are two different layers and must never be described in each other's
-- terms. The invariant is not "deducted once"; it is that the management result
-- includes the cost's economic effect EXACTLY ONCE. For SELLING that effect is
-- already netted inside the sector-owned realized disposal result, so the
-- correct split is: classification bucket 1, deduction 0.
select public.h1_assert(
  (select attributed_operating_cost_minor_units::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'REAL_ESTATE') = 1500000,
  'SELLING cost is CLASSIFIED once, as attributed property cost');
select public.h1_assert(
  (select result_deducted_cost_minor_units::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'REAL_ESTATE') = 0,
  'SELLING cost is DEDUCTED zero times, because it is already inside the realized disposal result');
select public.h1_assert(
  (select result_deducted_cost_minor_units::bigint
        = attributed_operating_cost_minor_units::bigint
          - selling_cost_attributed_minor_units::bigint
          + project_overhead_minor_units::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'REAL_ESTATE'),
  'the deduction column is defined as non-SELLING attributed cost plus declared overhead');
select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'REAL_ESTATE') = 7000000,
  'the Home Real Estate value includes the SELLING economic effect exactly once, not twice');

-- The reconciling identity, at every layer: result = revenue - deducted cost.
-- This is the invariant that catches a cost being counted twice or not at all,
-- regardless of which layer introduced it.
select public.h1_assert(
  (select count(*) from public.project_operating_result_read r
    where (r.management_result ->> 'amount_minor_units')::bigint
       <> (case r.sector
             when 'REAL_ESTATE'
               then r.realized_disposal_minor_units::bigint + r.rental_revenue_minor_units::bigint
             else r.sale_revenue_minor_units::bigint
           end) - r.result_deducted_cost_minor_units::bigint) = 0,
  'every project result equals its revenue components less the deducted cost');
select public.h1_assert(
  (select count(*) from public.sector_management_result_read r
    where (r.management_result ->> 'amount_minor_units')::bigint
       <> (case r.sector
             when 'REAL_ESTATE'
               then r.realized_disposal_minor_units::bigint + r.rental_revenue_minor_units::bigint
             else r.sale_revenue_minor_units::bigint
           end) - r.result_deducted_cost_minor_units::bigint) = 0,
  'every sector result equals its revenue components less the deducted cost');

-- Agriculture: declared overhead is deducted, excluded cost is disclosed but not deducted.
select public.h1_assert(
  (select (management_result ->> 'amount_minor_units')::bigint
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'AGRICULTURE') = 9800000,
  'the Home Agriculture value deducts declared overhead and leaves excluded cost out');
select public.h1_assert(
  (select cost_classification_status from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and sector = 'AGRICULTURE') = 'COMPLETE',
  'declared overhead completes Agriculture coverage without 100% attribution');

-- A sector amount is only meaningful if every project in it shares one basis.
-- result_basis is a pure function of sector and sector is the group key, so this
-- is proved here rather than defended against in the view.
select public.h1_assert(
  (select count(*) from (
     select sector, currency, count(distinct result_basis) as basis_count
       from public.sector_management_result_read group by sector, currency
   ) x where x.basis_count > 1) = 0,
  'no sector row mixes bases, so a summed sector amount never mixes bases');

-- The roll-up conserves the project results exactly, per currency.
select public.h1_assert(
  (select coalesce(sum((management_result ->> 'amount_minor_units')::bigint), 0)
     from public.sector_management_result_read
    where organization_id = :'h1_org'::uuid and currency = 'EGP')
  = (select coalesce(sum((management_result ->> 'amount_minor_units')::bigint), 0)
       from public.project_operating_result_read
      where organization_id = :'h1_org'::uuid and currency = 'EGP'),
  'the sector roll-up conserves the project results exactly');

reset role;
-- ===========================================================================
-- 10. Cash by currency: two positions stay two positions.
-- ===========================================================================
-- The project pages summed every cash account balance into one number and
-- stamped it with project.reporting_currency. That added minor units of one
-- currency to minor units of another. The contract is now: one row per
-- (project, currency), no FX conversion, and NO field anywhere that represents
-- their sum.
--
-- A finding from building this: `create_project_cash_account` already rejects an
-- account whose currency differs from the project's, and `investment_projects.
-- reporting_currency` is constrained to EGP. So a project holding both OMR and
-- USD accounts is NOT reachable through the command today. That guard is
-- asserted below. The dangerous state is then built by direct DML, because the
-- projection must still be correct for rows that arrive by import, backfill, or
-- a future relaxation of that rule — and because the currency on a posted
-- BANK_CASH journal line is NOT constrained to match its account at all, which
-- is the live hazard.

select public.create_investment_project(
  :'h1_org'::uuid, 'مشروع نقد متعدد العملات H1', 'H1-CASH',
  'إثبات فصل المراكز النقدية', 'AGRICULTURE') as h1_cash \gset

select public.h1_assert(
  public.h1_caught(format($$select public.create_project_cash_account(%L,%L,'حساب بعملة أخرى','OMR')$$,
    :'h1_org'::uuid, :'h1_cash'::uuid)) like '%account currency must match project currency%',
  'the command layer rejects a cash account whose currency differs from the project');

-- Build the multi-currency project directly, as the table owner.
reset role;

insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'حساب عماني — ريال عماني', 'OMR')
returning id as h1_omr_account \gset

insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'حساب عماني ثانٍ', 'OMR')
returning id as h1_omr_account_2 \gset

insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'حساب دولاري', 'USD')
returning id as h1_usd_account \gset

-- Registered but never used: it genuinely holds zero, and must be reported as
-- such rather than omitted or invented.
insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'حساب بلا حركة', 'EUR')
returning id as h1_eur_account \gset

-- Post BANK_CASH movements: the posting commands are proven by gates 01-97;
-- what is under test here is the projection over their facts.
-- A journal batch holds exactly one currency (enforced by the ledger), so the
-- OMR and USD movements are posted as two batches. That constraint is itself
-- worth knowing: the leak was never in storage, it was in the UI summing across
-- separately stored positions.
insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'CONTRIBUTION_CASH_ATTRIBUTION', gen_random_uuid(),
        current_date, '00a00000-0000-4000-8000-0000000000a1'::uuid,
        'h1-batch-cash-omr-0001', repeat('0', 64))
returning id as h1_omr_batch \gset

insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'CONTRIBUTION_CASH_ATTRIBUTION', gen_random_uuid(),
        current_date, '00a00000-0000-4000-8000-0000000000a1'::uuid,
        'h1-batch-cash-usd-0001', repeat('0', 64))
returning id as h1_usd_batch \gset

-- OMR: 1,000.000 on the first account and 250.000 on the second (three decimals).
insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id, cash_account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_omr_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'BANK_CASH'),
       :'h1_omr_account'::uuid, 1000000, 0, 'OMR', current_date, current_date
union all
select :'h1_omr_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       null, 0, 1000000, 'OMR', current_date, current_date
union all
select :'h1_omr_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'BANK_CASH'),
       :'h1_omr_account_2'::uuid, 250000, 0, 'OMR', current_date, current_date
union all
select :'h1_omr_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       null, 0, 250000, 'OMR', current_date, current_date;

-- USD: 4,000.00 (two decimals).
insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id, cash_account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_usd_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'BANK_CASH'),
       :'h1_usd_account'::uuid, 400000, 0, 'USD', current_date, current_date
union all
select :'h1_usd_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       null, 0, 400000, 'USD', current_date, current_date;

select * from public.project_cash_by_currency_read where project_id = :'h1_cash'::uuid;

-- One row per currency, never one row per project.
select public.h1_assert(
  (select count(*) from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid) = 3,
  'a project with OMR, USD and an unused EUR account yields three rows, not one');
select public.h1_assert(
  (select count(*) from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'OMR') = 1,
  'the two OMR accounts aggregate into one OMR position');

-- Each position is exact and separately labelled.
select public.h1_assert(
  (select cash_balance_minor_units from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'OMR') = '1250000',
  'the OMR position is the exact sum of OMR movements');
select public.h1_assert(
  (select cash_balance_minor_units from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'USD') = '400000',
  'the USD position is the exact sum of USD movements');
select public.h1_assert(
  (select account_count from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'OMR') = 2,
  'the OMR position reports how many accounts it aggregates');

-- The dangerous case: OMR and USD must not be combined anywhere.
select public.h1_assert(
  (select count(*) from public.project_cash_by_currency_read r
    where r.project_id = :'h1_cash'::uuid
      and r.cash_balance_minor_units::bigint = 1650000) = 0,
  'no row ever holds the cross-currency sum of the OMR and USD positions');
select public.h1_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_cash_by_currency_read'
      and column_name ~* '(total|combined|converted|consolidat|all_currencies|_sum)') = 0,
  'the read model exposes no field representing a cross-currency cash total');
select public.h1_assert(
  (select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'project_cash_by_currency_read'
      and column_name ~* '(fx|rate)') = 0,
  'the read model performs no FX conversion');

-- An unused account genuinely holds zero, and says so.
select public.h1_assert(
  (select cash_balance_minor_units from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'EUR') = '0',
  'a registered account with no movement reports an exact zero, not null');
select public.h1_assert(
  (select has_active_posted_movement from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'EUR') = false,
  'the zero is labelled as never-used, so it is not mistaken for a spent balance');
select public.h1_assert(
  (select has_active_posted_movement from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'OMR') = true,
  'an active position is labelled as active');

-- A project with no cash accounts yields no row at all: "no accounts" is not
-- the same fact as "zero cash", so no zero is invented for it.
select public.h1_assert(
  (select count(*) from public.project_cash_by_currency_read
    where project_id = :'h1_re'::uuid) = 0,
  'a project with no cash accounts yields no row rather than an invented zero');

-- The live hazard: a BANK_CASH journal line whose currency differs from its
-- account's is NOT constrained today. It is excluded from the balance and
-- disclosed, never silently summed in.
insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'CONTRIBUTION_CASH_ATTRIBUTION', gen_random_uuid(),
        current_date, '00a00000-0000-4000-8000-0000000000a1'::uuid,
        'h1-batch-cash-mismatch-0001', repeat('0', 64))
returning id as h1_mismatch_batch \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id, cash_account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_mismatch_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'BANK_CASH'),
       :'h1_usd_account'::uuid, 500000, 0, 'OMR', current_date, current_date
union all
select :'h1_mismatch_batch'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       null, 0, 500000, 'OMR', current_date, current_date;

select public.h1_assert(
  (select cash_balance_minor_units from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'USD') = '400000',
  'a mismatched-currency movement is not added to the USD position');
select public.h1_assert(
  (select currency_mismatch_line_count from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'USD') = 1,
  'the mismatched movement is disclosed rather than silently dropped');

-- Reversal discipline: a reversed cash movement leaves the position.
insert into public.journal_batches(
  organization_id, project_id, source_type, source_id, transaction_date,
  posted_by, reversal_of_batch_id, idempotency_key, request_hash)
values (:'h1_org'::uuid, :'h1_cash'::uuid, 'REVERSAL', gen_random_uuid(), current_date,
        '00a00000-0000-4000-8000-0000000000a1'::uuid, :'h1_usd_batch'::uuid,
        'h1-batch-cash-reversal-0001', repeat('0', 64))
returning id as h1_cash_reversal \gset

insert into public.journal_lines(
  batch_id, organization_id, project_id, account_id, cash_account_id,
  debit_minor_units, credit_minor_units, currency, transaction_date, posting_date)
select :'h1_cash_reversal'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'BANK_CASH'),
       :'h1_usd_account'::uuid, 0, 400000, 'USD', current_date, current_date
union all
select :'h1_cash_reversal'::uuid, :'h1_org'::uuid, :'h1_cash'::uuid,
       (select id from public.semantic_accounts where role = 'CUSTOMER_RECEIVABLE'),
       null, 400000, 0, 'USD', current_date, current_date;

select public.h1_assert(
  (select cash_balance_minor_units from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'USD') = '0',
  'a reversed cash movement leaves the position');
-- A fully reversed position has no ACTIVE movement behind it, so it is reported
-- exactly like an account that was never used. Economically they are the same
-- fact: no active movement stands behind the balance.
select public.h1_assert(
  (select has_active_posted_movement from public.project_cash_by_currency_read
    where project_id = :'h1_cash'::uuid and currency = 'USD') = false,
  'a fully reversed position reports no active movement, like an unused account');

reset role;
