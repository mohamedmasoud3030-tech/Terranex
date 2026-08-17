-- S2 corrective gate — project cash-account creation must be replay-safe for
-- both the canonical five-argument command and the backward-compatible
-- four-argument overload used by cached/older clients.

select id as s2_idem_project
from public.investment_projects
where name = 'مشروع النخيل'
\gset

-- Canonical command: same key + same payload replays one row / one audit event.
select s2_run('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,
    'حساب اختبار idempotency','EGP','s2-cash-idem-0001'
  )$$,
  :'s2_idem_project'));

select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,
    'حساب اختبار idempotency','EGP','s2-cash-idem-0001'
  )$$,
  :'s2_idem_project')) then 1 else 0 end as s2_cash_retry_same_payload_ok;

select 1/case when (
  select count(*)
  from public.project_cash_accounts
  where organization_id = '10000000-0000-4000-8000-000000000001'
    and idempotency_key = 's2-cash-idem-0001'
) = 1 then 1 else 0 end as s2_cash_retry_single_effect;

select id as s2_idem_account
from public.project_cash_accounts
where organization_id = '10000000-0000-4000-8000-000000000001'
  and idempotency_key = 's2-cash-idem-0001'
\gset

select 1/case when (
  select count(*)
  from public.audit_events
  where organization_id = '10000000-0000-4000-8000-000000000001'
    and event_type = 'CASH_ACCOUNT_CREATED'
    and entity_type = 'project_cash_account'
    and entity_id = :'s2_idem_account'
) = 1 then 1 else 0 end as s2_cash_retry_single_audit_effect;

-- Same key + different payload must never replay the wrong account.
select 1/case when s2_expect_raise('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,
    'اسم مختلف لنفس المفتاح','EGP','s2-cash-idem-0001'
  )$$,
  :'s2_idem_project'), 'P0001') then 1 else 0 end as s2_cash_payload_mismatch_rejected;

-- Legacy overload remains callable for older clients, but is itself idempotent
-- because it derives a stable legacy key and delegates to the canonical RPC.
select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,
    'حساب عميل قديم','EGP'
  )$$,
  :'s2_idem_project')) then 1 else 0 end as s2_cash_legacy_first_ok;

select 1/case when s2_expect_ok('00000000-0000-4000-8000-000000000003', format(
  $$select public.create_project_cash_account(
    '10000000-0000-4000-8000-000000000001',%L,
    'حساب عميل قديم','EGP'
  )$$,
  :'s2_idem_project')) then 1 else 0 end as s2_cash_legacy_retry_ok;

select 1/case when (
  select count(*)
  from public.project_cash_accounts
  where organization_id = '10000000-0000-4000-8000-000000000001'
    and project_id = :'s2_idem_project'
    and name = 'حساب عميل قديم'
    and idempotency_key like 'legacy-%'
) = 1 then 1 else 0 end as s2_cash_legacy_retry_single_effect;

select 'S2 cash-account idempotency SQL PASS' as result;
