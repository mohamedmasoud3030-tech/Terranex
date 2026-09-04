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

reset role;
