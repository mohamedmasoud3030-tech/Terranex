-- GF-009 / S7 — pilot hardening behavioural gate.
--
-- Covers the controlled opening-import lifecycle, exact control totals,
-- rejected-row atomicity, retry idempotency, maker/checker segregation,
-- closed-period refusal, cross-tenant refusal, reconciliation checkpoints /
-- exceptions / immutable sign-off, access revocation and owner recovery,
-- UAT evidence that no machine can grant, and the acceptance report.
-- The real two-session races run separately in 24_s7_concurrency.sh.

\set s7_checker '00000000-0000-4000-8000-000000000001'
\set s7_outsider '00000000-0000-4000-8000-000000000002'
\set s7_maker '00000000-0000-4000-8000-000000000003'
\set s7_member '00000000-0000-4000-8000-000000000005'
\set s7_org_b '20000000-0000-4000-8000-000000000002'
\set s7_sum_a 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
\set s7_sum_b 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
\set s7_sum_c 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'

create or replace function s7_assert(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'S7 assertion failed: %', p_message;
  end if;
end $$;

create or replace function s7_expect_raise(p_user uuid, p_sql text, p_message_like text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlerrm like p_message_like;
end $$;

create or replace function s7_expect_raise_admin(p_sql text, p_message_like text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlerrm like p_message_like;
end $$;

create or replace function s7_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql;
  reset role;
exception when others then
  reset role;
  raise;
end $$;

-- Test-only access fixture: one plain MEMBER whose access is revoked later in
-- this suite through the production command. Test data, never a product path.
insert into auth.users(id) values (:'s7_member') on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role, status)
values ('10000000-0000-4000-8000-000000000001', :'s7_member', 'MEMBER', 'ACTIVE')
on conflict (organization_id, user_id) do update set role = 'MEMBER', status = 'ACTIVE';

select id s7_project, organization_id s7_org, reporting_currency s7_currency
from public.investment_projects where name = 'مشروع النخيل' limit 1 \gset
select start_date s7_posting_date from public.accounting_periods
where organization_id = :'s7_org' and project_id = :'s7_project' and status = 'OPEN'
order by version desc limit 1 \gset
select id s7_cash from public.project_cash_accounts
where organization_id = :'s7_org' and project_id = :'s7_project' and currency = :'s7_currency'
order by id limit 1 \gset
select id s7_supplier from public.parties
where organization_id = :'s7_org' and legal_name = 'مورد أول' limit 1 \gset
select id s7_investor from public.parties
where organization_id = :'s7_org' and legal_name = 'مستثمر أول' limit 1 \gset
select id s7_foreign_party from public.parties
where organization_id = :'s7_org_b' order by id limit 1 \gset
select s7_assert(:'s7_posting_date' <> '', 'an OPEN accounting period fixture is required');

-- ===========================================================================
-- 1. The mapping registry is a locked Real-Estate list, not a generic importer.
-- ===========================================================================
select s7_assert((select count(*) = 6 from public.s7_opening_mapping_codes),
  'the opening mapping registry must be exactly the six supported Real-Estate codes');
select s7_assert((select bool_and(exists(
    select 1 from public.semantic_accounts sa where sa.role = m.account_role))
  from public.s7_opening_mapping_codes m),
  'every mapping code must resolve to an already existing locked semantic account role');
select s7_assert(s7_expect_raise_admin(
  $$insert into public.s7_opening_mapping_codes(code,account_role,label_ar,natural_side)
    values ('OPENING_CUSTOM','BANK_CASH','مخصص','DEBIT')$$,
  '%locked by S7 policy%'), 'the mapping registry must be locked against every writer');

-- ===========================================================================
-- 2. Row-level validation: a dirty file yields per-row reasons and posts nothing.
-- ===========================================================================
select count(*) s7_batches_before from public.journal_batches \gset

select s7_run(:'s7_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','opening-dirty.csv',%L,
    array['OPENING_BANK_CASH','OPENING_UNSUPPORTED','OPENING_SUPPLIER_PAYABLE',
          'OPENING_DEVELOPMENT_WIP','OPENING_BANK_CASH','OPENING_BANK_CASH',
          'OPENING_SUPPLIER_PAYABLE','OPENING_CUSTOMER_RECEIVABLE','OPENING_BANK_CASH',
          'OPENING_SUPPLIER_PAYABLE','OPENING_BANK_CASH']::text[],
    array[null,null,null,%L,null,null,%L,%L,null,%L,null]::uuid[],
    array[%L,null,null,null,%L,%L,null,null,null,null,%L]::uuid[],
    array['100','5','0','9','abc','200','0','50','60','12','100']::text[],
    array['0','0','7','0','0','300','0','0','0','0','0']::text[],
    array['نقدية','سطر غير معروف','مورد بلا طرف','تطوير بطرف','قيمة غير صالحة','طرفان',
          'بلا مبلغ','طرف من منظمة أخرى','نقدية بلا حساب','اتجاه مخالف','نقدية']::text[],
    '100','0','s7-opening-dirty-0001')$$,
  :'s7_org', :'s7_project', :'s7_sum_b',
  :'s7_investor', :'s7_supplier', :'s7_foreign_party', :'s7_supplier',
  :'s7_cash', :'s7_cash', :'s7_cash', :'s7_cash'));
select id s7_dirty from public.s7_opening_imports
where organization_id = :'s7_org' and idempotency_key = 's7-opening-dirty-0001' \gset

select s7_assert((select count(*) = :'s7_batches_before'::bigint from public.journal_batches),
  'staging an opening import must never post a journal batch');
select s7_assert((select submitted_row_count = 11 and accepted_row_count = 1 and rejected_row_count = 10
  from public.s7_opening_imports where id = :'s7_dirty'),
  'each invalid row must be rejected individually while the valid row stays accepted');
select s7_assert((select array_agg(reject_reason order by row_number) = array[
    'UNKNOWN_MAPPING_CODE','PARTY_REQUIRED','PARTY_NOT_ALLOWED','INVALID_AMOUNT',
    'BOTH_SIDES_SET','NO_AMOUNT','PARTY_NOT_IN_ORGANIZATION','CASH_ACCOUNT_REQUIRED',
    'SIDE_CONTRADICTS_MAPPING','DUPLICATE_ROW_IN_FILE']
  from public.s7_opening_import_rows where import_id = :'s7_dirty' and status = 'REJECTED'),
  'every rejected row must carry its own explicit machine-readable reason');
select s7_assert((select count(*) = 1 from public.s7_opening_import_rows
  where import_id = :'s7_dirty' and status = 'REJECTED' and reject_reason = 'PARTY_NOT_IN_ORGANIZATION'),
  'a cross-organization counterparty reference must be rejected, never imported');

select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','opening-dirty.csv',%L,
    array['OPENING_BANK_CASH']::text[],null,array[%L]::uuid[],array['999']::text[],
    array['0']::text[],array['محاولة إعادة بمحتوى مختلف']::text[],
    '999','999','s7-opening-dirty-0001')$$,
  :'s7_org', :'s7_project', :'s7_sum_b', :'s7_cash'),
  '%idempotency key payload mismatch%'),
  'a retry that changes the economics must be refused, never silently re-staged');

select s7_run(:'s7_maker', format(
  $$select public.s7_validate_opening_import(%L,%L,'s7-validate-dirty-01')$$,
  :'s7_org', :'s7_dirty'));
select s7_assert((select status = 'REJECTED' and jsonb_array_length(rejection_summary) = 10
  from public.s7_opening_imports where id = :'s7_dirty'),
  'an import holding rejected rows must be REJECTED as a whole, never partially applied');
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_review_opening_import(%L,%L,null,'s7-review-dirty-001')$$,
  :'s7_org', :'s7_dirty'), '%only a VALIDATED opening import%'),
  'a rejected import must never reach the approval queue');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.s7_opening_import_rows set debit_minor_units=1 where import_id=%L$$,
  :'s7_dirty'), '%frozen once the import leaves DRAFT%'),
  'imported rows must freeze once the import leaves DRAFT');

-- ===========================================================================
-- 3. Control totals must reconcile exactly, to the minor unit.
-- ===========================================================================
select s7_run(:'s7_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','opening-mismatch.csv',%L,
    array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['400000','0']::text[], array['0','400000']::text[],
    array['نقدية افتتاحية','رأس مال افتتاحي']::text[],
    '400001','400000','s7-opening-mismatch-1')$$,
  :'s7_org', :'s7_project', :'s7_sum_c', :'s7_investor', :'s7_cash'));
select id s7_mismatch from public.s7_opening_imports
where organization_id = :'s7_org' and idempotency_key = 's7-opening-mismatch-1' \gset
select s7_run(:'s7_maker', format(
  $$select public.s7_validate_opening_import(%L,%L,'s7-validate-mismatch')$$,
  :'s7_org', :'s7_mismatch'));
select s7_assert((select status = 'REJECTED'
  and debit_variance_minor_units = -1 and credit_variance_minor_units = 0
  and computed_debit_total_minor_units = 400000
  from public.s7_opening_imports where id = :'s7_mismatch'),
  'a one minor unit control-total variance must reject the import with an exact variance');

-- ===========================================================================
-- 4. Clean import: deterministic normalization, review, maker/checker approval,
--    and exactly one balanced canonical journal batch.
-- ===========================================================================
select s7_run(:'s7_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','opening-nakhil.csv',%L,
    array['OPENING_BANK_CASH','OPENING_SUPPLIER_PAYABLE','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L,%L]::uuid[], array[%L,null,null]::uuid[],
    array['٥٠٠٠٠٠','0','0']::text[], array['0','200000','300000']::text[],
    array['رصيد بنكي افتتاحي','=1+1','رأس مال افتتاحي']::text[],
    '500000','500000','s7-opening-clean-0001')$$,
  :'s7_org', :'s7_project', :'s7_sum_a', :'s7_supplier', :'s7_investor', :'s7_cash'));
select id s7_clean from public.s7_opening_imports
where organization_id = :'s7_org' and idempotency_key = 's7-opening-clean-0001' \gset
select s7_assert((select accepted_row_count = 3 and rejected_row_count = 0
  from public.s7_opening_imports where id = :'s7_clean'),
  'the clean opening file must be accepted in full');
select s7_assert((select debit_minor_units = '500000' from public.s7_opening_import_rows_read
  where import_id = :'s7_clean' and row_number = 1),
  'Arabic-Indic digits must normalize deterministically to exact minor units');
select s7_assert((select description = '''=1+1' from public.s7_opening_import_rows_read
  where import_id = :'s7_clean' and row_number = 2),
  'exported free text must be neutralized against CSV formula injection');

select s7_run(:'s7_maker', format(
  $$select public.s7_validate_opening_import(%L,%L,'s7-validate-clean-01')$$,
  :'s7_org', :'s7_clean'));
select s7_assert((select status = 'VALIDATED' and control_totals_match
  and debit_variance_minor_units = '0' and credit_variance_minor_units = '0'
  from public.s7_opening_imports_read where import_id = :'s7_clean'),
  'a reconciling opening file must validate with an explicit zero variance');
select s7_assert((select (mapping_summary->'OPENING_BANK_CASH'->>'debit_minor_units') = '500000'
  from public.s7_opening_imports where id = :'s7_clean'),
  'the mapping summary must report exactly how each mapping code was resolved');

select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-too-early')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'), '%ready for approval%'),
  'approval must be impossible before an explicit review step');
select s7_run(:'s7_checker', format(
  $$select public.s7_review_opening_import(%L,%L,'روجعت مقابل ميزان المراجعة الافتتاحي','s7-review-clean-01')$$,
  :'s7_org', :'s7_clean'));

select s7_assert(s7_expect_raise(:'s7_member', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-by-member')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'), '%organization owner required%'),
  'a plain member must never approve an opening import');
select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-self-000')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'), '%s7_opening_import_maker_checker_check%'),
  'the preparer must not approve their own opening import even when OWNER');
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,date '1900-01-01','s7-approve-closed-p')$$,
  :'s7_org', :'s7_clean'), '%OPEN accounting period%'),
  'an opening position must never post outside an OPEN accounting period');
select s7_assert(s7_expect_raise(:'s7_outsider', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-crosstenant')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'), '%forbidden%'),
  'another tenant must never approve this organization''s opening import');

select s7_run(:'s7_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-clean-001')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'));
select journal_batch_id s7_clean_batch from public.s7_opening_imports where id = :'s7_clean' \gset
select s7_assert((select status = 'POSTED' and approved_by = :'s7_checker'::uuid
  and prepared_by <> approved_by and char_length(snapshot_content_hash) = 64
  from public.s7_opening_imports where id = :'s7_clean'),
  'a posted opening import must freeze an immutable snapshot with a distinct checker');
select s7_assert((select count(*) = 3 and sum(debit_minor_units) = sum(credit_minor_units)
  and sum(debit_minor_units) = 500000
  from public.journal_lines where batch_id = :'s7_clean_batch'),
  'the opening import must post exactly one balanced canonical journal batch');
select s7_assert((select count(*) = 1 from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  where jl.batch_id = :'s7_clean_batch' and sa.role = 'BANK_CASH'
    and jl.cash_account_id = :'s7_cash'::uuid),
  'opening cash must carry its project cash-account dimension');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.s7_opening_imports set snapshot_content_hash=repeat('0',64) where id=%L$$,
  :'s7_clean'), '%snapshot is immutable%'),
  'an approved opening snapshot must be immutable for every writer');
select s7_assert(s7_expect_raise_admin(format(
  $$delete from public.s7_opening_imports where id=%L$$, :'s7_clean'),
  '%append-only%'), 'opening import facts must be append-only');

-- Retrying the exact approval must be a replay with one material effect.
select s7_run(:'s7_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-clean-001')$$,
  :'s7_org', :'s7_clean', :'s7_posting_date'));
select s7_assert((select count(*) = 1 from public.journal_batches
  where source_type = 'S7_OPENING_IMPORT' and source_id = :'s7_clean'),
  'an approval retry must have exactly one material effect');

-- ===========================================================================
-- 5. No destructive overwrite of an opening position.
-- ===========================================================================
select s7_run(:'s7_maker', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','opening-second.csv',%L,
    array['OPENING_BANK_CASH','OPENING_CONTRIBUTED_CAPITAL']::text[],
    array[null,%L]::uuid[], array[%L,null]::uuid[],
    array['1000','0']::text[], array['0','1000']::text[],
    array['محاولة استيراد افتتاحي ثانٍ','رأس مال']::text[],
    '1000','1000','s7-opening-second-01')$$,
  :'s7_org', :'s7_project', :'s7_sum_c', :'s7_investor', :'s7_cash'));
select id s7_second from public.s7_opening_imports
where organization_id = :'s7_org' and idempotency_key = 's7-opening-second-01' \gset
select s7_run(:'s7_maker', format(
  $$select public.s7_validate_opening_import(%L,%L,'s7-validate-second1')$$,
  :'s7_org', :'s7_second'));
select s7_run(:'s7_checker', format(
  $$select public.s7_review_opening_import(%L,%L,null,'s7-review-second-01')$$,
  :'s7_org', :'s7_second'));
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_approve_opening_import(%L,%L,%L,'s7-approve-second-01')$$,
  :'s7_org', :'s7_second', :'s7_posting_date'),
  '%already has an active posted opening import%'),
  'a second opening position must never silently overwrite the first');
select s7_run(:'s7_checker', format(
  $$select public.s7_reject_opening_import(%L,%L,'ملف افتتاحي مكرر أُلغي بقرار المشغل','s7-reject-second-1')$$,
  :'s7_org', :'s7_second'));
select s7_assert((select status = 'REJECTED' from public.s7_opening_imports where id = :'s7_second'),
  'an operator must be able to reject a superseded staged import explicitly');
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_reject_opening_import(%L,%L,'محاولة إلغاء استيراد مرحّل','s7-reject-posted-1')$$,
  :'s7_org', :'s7_clean'), '%use linked reversal%'),
  'a posted opening import must only be corrected by linked reversal');
-- Post ordinary operating activity after the opening position, then prove the
-- opening cannot be pulled out from underneath it.
select s7_run(:'s7_maker', format(
  $$select public.create_cost_obligation(%L,%L,%L,'التزام تشغيلي بعد الافتتاحي',
    4000,%L,%L,'EXPENSE','s7-post-open-obl-01')$$,
  :'s7_org', :'s7_project', :'s7_supplier', :'s7_currency', :'s7_posting_date'));
select id s7_post_open_obl from public.cost_obligations
where organization_id = :'s7_org' and idempotency_key = 's7-post-open-obl-01' \gset
select s7_run(:'s7_checker', format(
  $$select public.authorize_cost_obligation(%L,%L,'s7-post-open-auth-01')$$,
  :'s7_org', :'s7_post_open_obl'));
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.reverse_journal_batch(%L,%L,'محاولة عكس الافتتاحي تحت حركة لاحقة','s7-reverse-blocked1')$$,
  :'s7_org', :'s7_clean_batch'), '%dependent later postings%'),
  'an opening import must not be reversible underneath later operating postings');

-- Unwind the dependency in the only correct order: the later posting first.
select id s7_post_open_batch from public.journal_batches
where organization_id = :'s7_org' and source_type = 'COST_OBLIGATION'
  and source_id = :'s7_post_open_obl' \gset
select s7_run(:'s7_checker', format(
  $$select public.reverse_journal_batch(%L,%L,'إلغاء الالتزام التشغيلي التجريبي','s7-reverse-post-obl')$$,
  :'s7_org', :'s7_post_open_batch'));
select s7_assert((select exists(select 1 from public.journal_batches rb
  where rb.reversal_of_batch_id = :'s7_post_open_batch')),
  'the later operating posting must be reversible on its own');

-- ===========================================================================
-- 6. Reconciliation checkpoints. The external number is evidence only.
-- ===========================================================================
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'PROJECT_CASH', :'s7_posting_date') s7_cash_truth \gset
select s7_run(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',%L,%s,
    'كشف بنك العميل','BANK-STMT-PILOT-W1',null,null,'s7-recon-cash-match')$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_cash_truth'));
select id s7_recon_match from public.s7_reconciliation_checkpoints
where organization_id = :'s7_org' and idempotency_key = 's7-recon-cash-match' \gset
select s7_assert((select status = 'MATCHED' and is_zero_variance
  and variance_minor_units = '0' and open_exception_count = 0
  from public.s7_reconciliation_checkpoints_read where checkpoint_id = :'s7_recon_match'),
  'a zero variance must be recorded explicitly, not implied by silence');
select s7_assert((select terranex_value_minor_units::bigint = :'s7_cash_truth'::bigint
  from public.s7_reconciliation_checkpoints where id = :'s7_recon_match'),
  'the Terranex side of a checkpoint must be derived in PostgreSQL, never supplied');

select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',%L,%s,
    'كشف بنك العميل','BANK-STMT-PILOT-W2',null,null,'s7-recon-no-severity')$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_cash_truth'::bigint + 250),
  '%requires an explicit exception severity%'),
  'a non-zero variance must never be recordable without an owned exception');

select s7_run(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',%L,%s,
    'كشف بنك العميل','BANK-STMT-PILOT-W2',%L,'CRITICAL','s7-recon-cash-var01')$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_cash_truth'::bigint + 250, :'s7_checker'));
select id s7_recon_var from public.s7_reconciliation_checkpoints
where organization_id = :'s7_org' and idempotency_key = 's7-recon-cash-var01' \gset
select s7_assert((select status = 'VARIANCE' and variance_minor_units = '250'
  and open_exception_count = 1 and max_open_severity = 'CRITICAL'
  from public.s7_reconciliation_checkpoints_read where checkpoint_id = :'s7_recon_var'),
  'a non-zero variance must create a visible owned exception with an exact integer variance');
select exception_id s7_exception from public.s7_reconciliation_exceptions_read
where checkpoint_id = :'s7_recon_var' \gset
select s7_assert((select owner_user_id = :'s7_checker'::uuid and status = 'OPEN'
  from public.s7_reconciliation_exceptions where id = :'s7_exception'),
  'an exception must name its owner and start OPEN');
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_sign_off_reconciliation_checkpoint(%L,%L,'SIGNOFF-W2','s7-signoff-blocked')$$,
  :'s7_org', :'s7_recon_var'), '%unresolved exception%'),
  'a checkpoint with an unresolved exception must not be signable');

select s7_assert(s7_expect_raise(:'s7_member', format(
  $$select public.s7_resolve_reconciliation_exception(%L,%L,'محاولة إغلاق','EV-1','s7-resolve-member')$$,
  :'s7_org', :'s7_exception'), '%organization owner required%'),
  'exception resolution is an owner act');
select s7_run(:'s7_checker', format(
  $$select public.s7_resolve_reconciliation_exception(%L,%L,
    'فرق ٢٥٠ وحدة يعود لإيداع مسجل لدى العميل خارج نطاق المشروع','RECON-EV-W2-01','s7-resolve-var-01')$$,
  :'s7_org', :'s7_exception'));
select s7_assert((select status = 'RESOLVED' and resolved_by = :'s7_checker'::uuid
  from public.s7_reconciliation_exceptions where id = :'s7_exception'),
  'resolution must be a documented act with an actor and evidence');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.s7_reconciliation_exceptions set severity='LOW' where id=%L$$, :'s7_exception'),
  '%resolved reconciliation exception is immutable%'),
  'a resolved exception must be immutable');

select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_sign_off_reconciliation_checkpoint(%L,%L,'SIGNOFF-W2','s7-signoff-maker1')$$,
  :'s7_org', :'s7_recon_var'), '%s7_checkpoint_maker_checker_check%'),
  'the operator who recorded a checkpoint must not sign it off');
select s7_run(:'s7_checker', format(
  $$select public.s7_sign_off_reconciliation_checkpoint(%L,%L,'RECON-SIGNOFF-W2','s7-signoff-var-01')$$,
  :'s7_org', :'s7_recon_var'));
select s7_assert((select status = 'SIGNED_OFF' and signed_off_by = :'s7_checker'::uuid
  and sign_off_evidence_reference = 'RECON-SIGNOFF-W2'
  from public.s7_reconciliation_checkpoints where id = :'s7_recon_var'),
  'sign-off must record actor, time and source evidence');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.s7_reconciliation_checkpoints set external_value_minor_units=0 where id=%L$$,
  :'s7_recon_var'), '%immutable%'),
  'a signed-off checkpoint must be immutable');
select s7_assert(s7_expect_raise_admin(format(
  $$insert into public.s7_reconciliation_checkpoints(organization_id,project_id,checkpoint_code,
      as_of_date,reporting_currency,external_value_minor_units,terranex_value_minor_units,
      variance_minor_units,external_source_reference,external_evidence_reference,status,
      prepared_by,content_hash,idempotency_key,request_hash)
    values (%L,%L,'PROJECT_CASH',%L,'EGP',10,5,999,'src','ev','VARIANCE',%L,repeat('a',64),
      's7-bad-variance-row',repeat('a',64))$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_maker'),
  '%s7_checkpoint_variance_check%'),
  'a stored variance must always equal external minus authoritative');

-- The derivation helper is internal: an authenticated client can never call it
-- and can therefore never substitute its own "authoritative" value.
select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_authoritative_checkpoint_value(%L,%L,'PROJECT_CASH',%L)$$,
  :'s7_org', :'s7_project', :'s7_posting_date'), '%permission denied%'),
  'the authoritative checkpoint derivation must not be callable by a client role');

-- Every remaining checkpoint code must derive without error.
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'PARTNER_CAPITAL', :'s7_posting_date') s7_capital_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'INVESTOR_STATEMENT_TOTAL', :'s7_posting_date') s7_investor_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'SUPPLIER_OBLIGATION_POSITION', :'s7_posting_date') s7_supplier_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'CUSTOMER_RECEIVABLE_POSITION', :'s7_posting_date') s7_receivable_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'REALIZED_RESULT', :'s7_posting_date') s7_result_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'DISTRIBUTION_PAYABLE', :'s7_posting_date') s7_payable_truth \gset
select public.s7_authoritative_checkpoint_value(
  :'s7_org', :'s7_project', 'DISTRIBUTION_PAID', :'s7_posting_date') s7_paid_truth \gset
select s7_run(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PARTNER_CAPITAL',%L,%s,
    'كشف رأس مال العميل','CAP-STMT-W2',null,null,'s7-recon-capital-01')$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_capital_truth'));
select s7_run(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'INVESTOR_STATEMENT_TOTAL',%L,%s,
    'كشف المستثمرين','INV-STMT-W2',null,null,'s7-recon-investor-1')$$,
  :'s7_org', :'s7_project', :'s7_posting_date', :'s7_investor_truth'));
select s7_assert(
  :'s7_supplier_truth'::bigint is not null and :'s7_receivable_truth'::bigint is not null
  and :'s7_result_truth'::bigint is not null and :'s7_payable_truth'::bigint is not null
  and :'s7_paid_truth'::bigint is not null,
  'every supported checkpoint code must derive an exact integer from posted lines');
select s7_assert((select count(*) = 2 from public.s7_reconciliation_checkpoints
  where project_id = :'s7_project' and status = 'MATCHED'
    and checkpoint_code in ('PARTNER_CAPITAL','INVESTOR_STATEMENT_TOTAL')),
  'capital and investor statement checkpoints must reconcile against the posted ledger');
select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'MADE_UP_CODE',%L,0,
    'مصدر','EV-BAD-CODE',null,null,'s7-recon-badcode-1')$$,
  :'s7_org', :'s7_project', :'s7_posting_date'), '%unsupported reconciliation checkpoint%'),
  'only the supported checkpoint codes may be recorded');
select s7_assert(s7_expect_raise(:'s7_outsider', format(
  $$select public.s7_record_reconciliation_checkpoint(%L,%L,'PROJECT_CASH',%L,0,
    'مصدر','EV-OUTSIDER',null,null,'s7-recon-outsider1')$$,
  :'s7_org', :'s7_project', :'s7_posting_date'), '%forbidden%'),
  'another tenant must never record a checkpoint on this project');

-- ===========================================================================
-- 7. Access revocation and owner recovery.
-- ===========================================================================
select s7_run(:'s7_member', format(
  $$select public.s7_assert((select count(*)>0 from public.s7_opening_imports_read where project_id=%L),
    'an active member must be able to read pilot data')$$, :'s7_project'));
select s7_assert(s7_expect_raise(:'s7_member', format(
  $$select public.s7_set_membership_status(%L,%L,'INACTIVE','محاولة إلغاء ذاتية','s7-self-revoke-01')$$,
  :'s7_org', :'s7_checker'), '%organization owner required%'),
  'a plain member must never change membership status');
select s7_run(:'s7_checker', format(
  $$select public.s7_set_membership_status(%L,%L,'INACTIVE','انتهاء تكليف المستخدم في التجربة','s7-revoke-member-1')$$,
  :'s7_org', :'s7_member'));
select s7_assert((select not has_access from public.s7_membership_access_read
  where organization_id = :'s7_org' and user_id = :'s7_member'::uuid),
  'a revoked membership must lose access immediately');
select s7_run(:'s7_member', format(
  $$select public.s7_assert((select count(*)=0 from public.s7_opening_imports_read where project_id=%L),
    'a revoked session must not bypass RLS')$$, :'s7_project'));
select s7_assert(s7_expect_raise(:'s7_member', format(
  $$select public.s7_stage_opening_import(%L,%L,'S7.OPENING.V1','revoked.csv',%L,
    array['OPENING_BANK_CASH']::text[],null,array[%L]::uuid[],array['1']::text[],
    array['0']::text[],array['محاولة بعد الإلغاء']::text[],'1','1','s7-revoked-stage-1')$$,
  :'s7_org', :'s7_project', :'s7_sum_c', :'s7_cash'), '%forbidden%'),
  'a revoked member must not execute a privileged command with an existing session');
select s7_assert((select count(*) = 0 from public.s7_opening_imports
  where idempotency_key = 's7-revoked-stage-1'), 'a revoked command must leave no row behind');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.memberships set status='INACTIVE'
    where organization_id=%L and role='OWNER' and status='ACTIVE'$$, :'s7_org'),
  '%at least one active owner%'),
  'an organization must never be left without an active owner');
select s7_run(:'s7_checker', format(
  $$select public.s7_set_membership_status(%L,%L,'ACTIVE','إعادة تفعيل بعد المراجعة','s7-restore-member1')$$,
  :'s7_org', :'s7_member'));
select s7_assert((select has_access from public.s7_membership_access_read
  where organization_id = :'s7_org' and user_id = :'s7_member'::uuid),
  'an owner must be able to restore a revoked membership');

-- Revocation must not weaken any existing maker/checker control.
select id s7_run_id from public.s5_allocation_runs
where organization_id = :'s7_org' and status = 'APPROVED' order by prepared_at limit 1 \gset
select s7_assert((select prepared_by <> approved_by from public.s5_allocation_runs
  where id = :'s7_run_id'),
  'S5 allocation self-approval must remain impossible after S7 access changes');
select s7_assert((select bool_and(approved_by is null or approved_by <> prepared_by)
  from public.s5_distributions where organization_id = :'s7_org'),
  'S5 distribution self-approval must remain impossible after S7 access changes');

-- The revocation rehearsal is recorded only after every assertion above held.
-- It is a technical fact about this replay, not a customer acceptance.
select s7_run(:'s7_checker', format(
  $$select public.s7_record_pilot_rehearsal(%L,%L,'ACCESS_REVOCATION','PASS',
    'بروفة إلغاء الوصول: عضوية ملغاة تفقد القراءة والأوامر فورًا، ولا يمكن ترك المنظمة بلا مالك نشط، وفصل المهام في التخصيص والتوزيع لم يضعف',
    jsonb_build_object('source','23_s7_pilot_hardening.sql'),'s7-rehearsal-revoke1')$$,
  :'s7_org', :'s7_project'));
select s7_assert((select access_revocation_result = 'PASS'
  from public.s7_pilot_acceptance_report_read where project_id = :'s7_project'),
  'the acceptance report must read the revocation rehearsal from the recorded fact');

-- ===========================================================================
-- 8. UAT evidence: the system can never grant customer acceptance itself.
-- ===========================================================================
select s7_run(:'s7_maker', format(
  $$select public.s7_register_uat_task(%L,%L,'S7-UAT-OPENING-IMPORT',
    'استيراد الأرصدة الافتتاحية ومطابقتها',
    'يجب أن تتطابق مجاميع الرقابة تمامًا وأن تظهر القيود المرحّلة في دفتر الأستاذ','s7-uat-reg-open-01')$$,
  :'s7_org', :'s7_project'));
select id s7_uat from public.s7_uat_tasks
where organization_id = :'s7_org' and task_code = 'S7-UAT-OPENING-IMPORT' \gset
select s7_assert((select status = 'PENDING' and reviewed_by is null
  from public.s7_uat_tasks where id = :'s7_uat'),
  'a newly registered UAT task must stay PENDING');
select s7_run(:'s7_maker', format(
  $$select public.s7_register_uat_task(%L,%L,'S7-UAT-OPENING-IMPORT','عنوان آخر',
    'يجب أن تتطابق مجاميع الرقابة تمامًا وأن تظهر القيود المرحّلة في دفتر الأستاذ','s7-uat-reg-open-01')$$,
  :'s7_org', :'s7_project'));
select s7_assert((select count(*) = 1 from public.s7_uat_tasks
  where organization_id = :'s7_org' and task_code = 'S7-UAT-OPENING-IMPORT'),
  'registering the same UAT task twice must have one material effect');
select s7_assert(s7_expect_raise(:'s7_checker', format(
  $$select public.s7_accept_uat_task(%L,%L,'UAT-SIGN-01','s7-uat-accept-early')$$,
  :'s7_org', :'s7_uat'), '%only an executed UAT task%'),
  'a UAT task must not be accepted before it is executed');
select s7_run(:'s7_maker', format(
  $$select public.s7_record_uat_execution(%L,%L,'UAT-RUN-EVIDENCE-01','نُفذ على بيانات التجربة','s7-uat-exec-01')$$,
  :'s7_org', :'s7_uat'));
select s7_assert(s7_expect_raise(:'s7_maker', format(
  $$select public.s7_accept_uat_task(%L,%L,'UAT-SIGN-01','s7-uat-accept-self')$$,
  :'s7_org', :'s7_uat'), '%must not be its executor%'),
  'the executor of a UAT task must never accept it');
select s7_assert((select status = 'EXECUTED'
  from public.s7_uat_tasks where id = :'s7_uat'),
  'automated execution must never advance a UAT task past EXECUTED');

-- A second task deliberately stays PENDING: without real customer evidence the
-- human gate is not satisfied and the report must say so.
select s7_run(:'s7_maker', format(
  $$select public.s7_register_uat_task(%L,%L,'S7-UAT-INVESTOR-STATEMENT',
    'مراجعة كشف المستثمر','يجب أن يطابق كشف المستثمر القيود المرحّلة','s7-uat-reg-inv-001')$$,
  :'s7_org', :'s7_project'));

-- ===========================================================================
-- 9. Technical rehearsal records are not UAT.
-- ===========================================================================
select s7_run(:'s7_checker', format(
  $$select public.s7_record_pilot_rehearsal(%L,%L,'END_TO_END_CYCLE','PASS',
    'بروفة كاملة على بيانات اختبار: استيراد افتتاحي، مطابقة، إغلاق، تخصيص، توزيع',
    jsonb_build_object('source','automated-suite'),'s7-rehearsal-e2e-01')$$,
  :'s7_org', :'s7_project'));
select s7_assert((select result = 'PASS' from public.s7_pilot_rehearsals
  where organization_id = :'s7_org' and idempotency_key = 's7-rehearsal-e2e-01'),
  'a technical rehearsal result must be recorded as an independent fact');
select s7_assert(s7_expect_raise_admin(format(
  $$update public.s7_pilot_rehearsals set result='FAIL'
    where organization_id=%L and idempotency_key='s7-rehearsal-e2e-01'$$, :'s7_org'),
  '%append-only%'), 'a recorded rehearsal must be immutable');

-- ===========================================================================
-- 10. Acceptance report: technical truth and human truth stay separate.
-- ===========================================================================
select s7_assert((select posted_opening_imports = 1
  and opening_import_rejected_rows > 0
  and opening_control_totals_match
  and unbalanced_journal_batches = 0
  and reconciliation_checkpoints >= 4
  and reconciliation_non_zero_variances = 1
  and unresolved_exceptions = 0
  and unresolved_critical_exceptions = 0
  and end_to_end_result = 'PASS'
  from public.s7_pilot_acceptance_report_read where project_id = :'s7_project'),
  'the acceptance report must reproduce the machine-verifiable technical state exactly');
select s7_assert((select human_uat_status = 'PENDING' and uat_total_tasks = 2 and uat_accepted_tasks = 0
  from public.s7_pilot_acceptance_report_read where project_id = :'s7_project'),
  'the human UAT gate must report PENDING while no real customer acceptance exists');
select s7_assert((select backup_restore_result is null
  from public.s7_pilot_acceptance_report_read where project_id = :'s7_project'),
  'a rehearsal that has not been recorded must report as unknown, never as PASS');

-- Cross-tenant containment for every S7 read model.
select s7_run(:'s7_outsider', format(
  $$select public.s7_assert((
      (select count(*) from public.s7_opening_imports_read where project_id=%L)
      + (select count(*) from public.s7_opening_import_rows_read where project_id=%L)
      + (select count(*) from public.s7_reconciliation_checkpoints_read where project_id=%L)
      + (select count(*) from public.s7_reconciliation_exceptions_read where project_id=%L)
      + (select count(*) from public.s7_uat_tasks_read where project_id=%L)
      + (select count(*) from public.s7_pilot_rehearsals_read where project_id=%L)
    )=0,'cross-tenant S7 rows leaked')$$,
  :'s7_project', :'s7_project', :'s7_project', :'s7_project', :'s7_project', :'s7_project'));

select 'S7 pilot hardening SQL PASS' result;
