-- Customer invoices: issue/collect commands, journal exactness, idempotency,
-- RLS, append-only, and revenue visibility in the widened reporting reads.

create or replace function s102_run(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_result text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  execute p_sql into v_result;
  reset role;
  return v_result;
end $$;

create or replace function s102_catch(p_user uuid, p_sql text)
returns text language plpgsql as $$
declare v_msg text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', false);
  begin
    execute p_sql into v_msg;
  exception when others then
    v_msg := sqlerrm;
    reset role;
    return v_msg;
  end;
  reset role;
  return 'NO_EXCEPTION';
end $$;

-- Fixtures: one organization with an owner and a plain member, an outsider,
-- one project (default reporting currency EGP), a customer party, one cash
-- account, and a second project for cross-project checks.
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000301'),
  ('00000000-0000-4000-8000-000000000302'),
  ('00000000-0000-4000-8000-000000000303');
insert into public.organizations(id, name) values
  ('10000000-0000-4000-8000-000000000301', 'منظمة فواتير العملاء');
insert into public.memberships(organization_id, user_id, role, status) values
  ('10000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000301', 'OWNER', 'ACTIVE'),
  ('10000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000302', 'MEMBER', 'ACTIVE');
insert into public.investment_projects(id, organization_id, name) values
  ('20000000-0000-4000-8000-000000000301', '10000000-0000-4000-8000-000000000301', 'مشروع الفواتير'),
  ('20000000-0000-4000-8000-000000000302', '10000000-0000-4000-8000-000000000301', 'مشروع آخر');
select s102_run('00000000-0000-4000-8000-000000000301', $f$
  select public.create_party('10000000-0000-4000-8000-000000000301', 'شركة العميل الأول', 'ORGANIZATION')$f$) as s102_party \gset
insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values ('10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301', 'حساب التحصيل', 'EGP')
returning id as s102_cash \gset

-- 1. Owner issues an invoice; the journal effect is posted.
select s102_run('00000000-0000-4000-8000-000000000301', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301',
    '%s', 'INV-0001', 'مقاولة شهر أكتوبر', 2500000, current_date - 2,
    'سند-101', 'ci-issue-0001')$f$, :'s102_party')) as s102_invoice \gset

select 1/case when exists (
  select 1 from public.journal_batches jb
  join public.customer_invoices i on i.journal_batch_id = jb.id
  where jb.source_type = 'CUSTOMER_INVOICE_ISSUE'
    and i.id = :'s102_invoice'::uuid
    and i.amount_minor_units = 2500000 and i.currency = 'EGP'
) then 1 end as s102_issue_posted;

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  join public.customer_invoices i on i.journal_batch_id = jl.batch_id
  where i.id = :'s102_invoice'::uuid
    and ((sa.role = 'CUSTOMER_RECEIVABLE' and jl.debit_minor_units = 2500000)
      or (sa.role = 'GENERAL_SALE_REVENUE' and jl.credit_minor_units = 2500000))
) = 2 then 1 end as s102_issue_pair_exact;

-- 2. Idempotent replay returns the same invoice; a payload mismatch fails.
select 1/case when s102_run('00000000-0000-4000-8000-000000000301', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301',
    '%s', 'INV-0001', 'مقاولة شهر أكتوبر', 2500000, current_date - 2,
    'سند-101', 'ci-issue-0001')$f$, :'s102_party')) = :'s102_invoice'
then 1 end as s102_issue_idempotent;

select 1/case when s102_catch('00000000-0000-4000-8000-000000000301', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301',
    '%s', 'INV-0001', 'مقاولة شهر أكتوبر', 999000, current_date - 2,
    'سند-101', 'ci-issue-0001')$f$, :'s102_party')) = 'idempotency key payload mismatch'
then 1 end as s102_issue_mismatch_blocked;

-- 3. The reference is unique per project, case-insensitively, but reusable in
--    another project.
select 1/case when s102_catch('00000000-0000-4000-8000-000000000301', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301',
    '%s', 'inv-0001', null, 1000, current_date, 'سند-102', 'ci-issue-0002')$f$, :'s102_party'))
  = 'customer invoice reference already exists in this project'
then 1 end as s102_duplicate_reference_blocked;

select s102_run('00000000-0000-4000-8000-000000000301', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000302',
    '%s', 'INV-0001', null, 400000, current_date - 1, 'سند-103', 'ci-issue-0003')$f$, :'s102_party'))
  is not null as s102_reference_reusable_across_projects \gset

-- 4. A non-owner member cannot issue; an outsider reads nothing through RLS.
select 1/case when s102_catch('00000000-0000-4000-8000-000000000302', format($f$
  select public.issue_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000301',
    '%s', 'INV-0009', null, 1000, current_date, 'سند-109', 'ci-issue-0009')$f$, :'s102_party'))
  = 'forbidden: organization owner required'
then 1 end as s102_member_cannot_issue;

select 1/case when s102_run('00000000-0000-4000-8000-000000000303', $f$
  select count(*)::text from public.customer_invoices
  where organization_id = '10000000-0000-4000-8000-000000000301'$f$) = '0'
then 1 end as s102_outsider_reads_nothing;

-- 5. Partial collection posts the cash/receivable pair and updates the view.
select s102_run('00000000-0000-4000-8000-000000000301', format($f$
  select public.collect_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '%s', '%s', 1000000, current_date,
    'إيصال-201', 'ci-collect-0001')$f$, :'s102_invoice', :'s102_cash')) as s102_collection \gset

select 1/case when exists (
  select 1 from public.customer_invoices_read
  where invoice_id = :'s102_invoice'::uuid
    and collected_minor_units = '1000000' and outstanding_minor_units = '1500000'
    and customer_name = 'شركة العميل الأول'
) then 1 end as s102_partial_collection_view;

select 1/case when (
  select count(*) from public.journal_lines jl
  join public.semantic_accounts sa on sa.id = jl.account_id
  join public.customer_invoice_collections c on c.journal_batch_id = jl.batch_id
  where c.id = :'s102_collection'::uuid
    and ((sa.role = 'BANK_CASH' and jl.debit_minor_units = 1000000 and jl.cash_account_id = :'s102_cash'::uuid)
      or (sa.role = 'CUSTOMER_RECEIVABLE' and jl.credit_minor_units = 1000000))
) = 2 then 1 end as s102_collection_pair_exact;

-- 6. Over-collection and wrong-currency / cross-project cash accounts fail.
select 1/case when s102_catch('00000000-0000-4000-8000-000000000301', format($f$
  select public.collect_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '%s', '%s', 1500001, current_date,
    'إيصال-202', 'ci-collect-0002')$f$, :'s102_invoice', :'s102_cash'))
  = 'collection exceeds outstanding receivable'
then 1 end as s102_overcollection_blocked;

insert into public.project_cash_accounts(organization_id, project_id, name, currency)
values ('10000000-0000-4000-8000-000000000301', '20000000-0000-4000-8000-000000000302', 'حساب المشروع الآخر', 'EGP')
returning id as s102_cash_other \gset

select 1/case when s102_catch('00000000-0000-4000-8000-000000000301', format($f$
  select public.collect_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '%s', '%s', 1000, current_date,
    'إيصال-203', 'ci-collect-0003')$f$, :'s102_invoice', :'s102_cash_other'))
  = 'collection cash account must belong to the same project and currency'
then 1 end as s102_cross_project_cash_blocked;

-- 7. Full settlement leaves zero outstanding.
select s102_run('00000000-0000-4000-8000-000000000301', format($f$
  select public.collect_customer_invoice(
    '10000000-0000-4000-8000-000000000301', '%s', '%s', 1500000, current_date,
    'إيصال-204', 'ci-collect-0004')$f$, :'s102_invoice', :'s102_cash')) is not null as s102_full_collection \gset

select 1/case when exists (
  select 1 from public.customer_invoices_read
  where invoice_id = :'s102_invoice'::uuid and outstanding_minor_units = '0'
) then 1 end as s102_settled_view;

-- 8. Rows are append-only.
select 1/case when s102_catch('00000000-0000-4000-8000-000000000301', format($f$
  update public.customer_invoices set amount_minor_units = 1 where id = '%s'$f$, :'s102_invoice'))
  like '%append-only%'
then 1 end as s102_append_only;

-- 9. GENERAL_SALE_REVENUE counts as recognized revenue in the reporting reads.
select 1/case when exists (
  select 1 from public.project_financial_position_read
  where project_id = '20000000-0000-4000-8000-000000000301'
    and revenue_recognized_minor_units = '2500000'
    and receivable_open_minor_units = '0'
    and cash_balance_minor_units = '2500000'
) then 1 end as s102_position_counts_revenue;

select 1/case when exists (
  select 1 from public.project_result_by_currency_read
  where project_id = '20000000-0000-4000-8000-000000000301'
    and sale_revenue_minor = 2500000
) then 1 end as s102_result_counts_revenue;

drop function s102_run(uuid, text);
drop function s102_catch(uuid, text);
