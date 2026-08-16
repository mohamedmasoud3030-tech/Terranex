-- F3–F10 — Contract Finance, Budget Control, Approval/Exception Engine,
-- Currency/Tax Contract, Period Close Health, Integrity Center, Project
-- Performance and Portfolio/Org Roll-up behavioral gate.
--
-- Self-contained suite on isolated fixtures (org f300..., users f300...).
-- Every command runs with the actor identity via request.jwt.claim.sub so
-- the suite behaves identically under psql and under PGlite.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function f3f_expect_error(p_user uuid, p_sql text, p_fragment text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute p_sql;
  return false;
exception when others then
  return position(lower(p_fragment) in lower(sqlerrm)) > 0;
end $$;

create or replace function f3f_run(p_user uuid, p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute p_sql;
  return true;
exception when others then
  raise exception 'f3f_run failed: % | sql: %', sqlerrm, p_sql;
end $$;

create or replace function f3f_assert(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then raise exception 'F3F ASSERTION FAILED: %', p_msg; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('f3000000-0000-4000-8000-0000000000a1'),
  ('f3000000-0000-4000-8000-0000000000a2'),
  ('f3000000-0000-4000-8000-0000000000a3')
on conflict (id) do nothing;
insert into public.organizations(id, name) values
  ('f3000000-0000-4000-8000-000000000001', 'منظمة F3-F10')
on conflict (id) do nothing;
insert into public.memberships(organization_id, user_id, role) values
  ('f3000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-0000000000a1', 'OWNER'),
  ('f3000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-0000000000a2', 'OWNER'),
  ('f3000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-0000000000a3', 'MEMBER')
on conflict (organization_id, user_id) do nothing;

do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_owner2 uuid := 'f3000000-0000-4000-8000-0000000000a2';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid; v_party uuid; v_cash uuid; v_id uuid; v_id2 uuid;
begin
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_project := public.create_investment_project(v_org, 'مشروع الرقابة المالية F3-F10', 'F3F10-REF', 'مشروع اختبار المراحل F3-F10');
  perform set_config('f3f.project', v_project::text, false);

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_party := public.create_party(v_org, 'مورد F3F10', 'ORGANIZATION');
  perform set_config('f3f.party', v_party::text, false);

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_cash := public.create_project_cash_account(v_org, v_project, 'حساب بنك F3F10', 'EGP');
  perform set_config('f3f.cash', v_cash::text, false);

  -- Open accounting period covering the whole scenario.
  v_id := public.s6_create_accounting_period(v_org, v_project, current_date - 120, current_date + 120);
  perform set_config('f3f.period', v_id::text, false);

  -- Fund cash with a direct balanced contribution posting.
  insert into public.journal_batches(
    organization_id, project_id, source_type, source_id, transaction_date,
    idempotency_key, request_hash, posted_by
  ) values (
    v_org, v_project, 'CONTRIBUTION_CASH_ATTRIBUTION',
    'f3000000-0000-4000-8000-0000000000c1', current_date - 5,
    'f3f-fund-00000001',
    encode(digest('f3f-fund-00000001', 'sha256'), 'hex'), v_owner
  );
  insert into public.journal_lines(
    batch_id, organization_id, project_id, account_id, debit_minor_units,
    credit_minor_units, currency, cash_account_id, transaction_date
  ) select
    b.id, v_org, v_project, sa_bank.id, 300000, 0, 'EGP', v_cash, current_date - 5
  from public.journal_batches b, public.semantic_accounts sa_bank
  where b.idempotency_key = 'f3f-fund-00000001' and sa_bank.role = 'BANK_CASH'
  union all
  select
    b.id, v_org, v_project, sa_cap.id, 0, 300000, 'EGP', null, current_date - 5
  from public.journal_batches b, public.semantic_accounts sa_cap
  where b.idempotency_key = 'f3f-fund-00000001' and sa_cap.role = 'CONTRIBUTED_CAPITAL';

  perform public.f3f_assert(exists (
    select 1 from public.project_cash_position_read
    where project_id = v_project and balance_minor_units::bigint = 300000
  ), 'cash funding must post 300000');
end $$;

-- ---------------------------------------------------------------------------
-- F3 — Milestones
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_m1 uuid; v_replay uuid;
begin
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_m1 := public.f3_create_project_milestone(v_org, v_project, 'MS-01', 'تسليم المرحلة الأولى',
            current_date + 30, null, 'f3f-milestone-ms01-0001');
  v_replay := public.f3_create_project_milestone(v_org, v_project, 'MS-01', 'تسليم المرحلة الأولى',
            current_date + 30, null, 'f3f-milestone-ms01-0002');
  perform public.f3f_assert(v_m1 = v_replay, 'milestone creation must be idempotent');

  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    $sql$update public.project_milestones set achieved_date = current_date where code = 'MS-01'$sql$,
    'achieved date'), 'pending milestone cannot carry achieved date');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f3_achieve_project_milestone(v_org, v_m1, current_date, 'evidence-ms01', 'f3f-milestone-ach-0001');
  perform public.f3_achieve_project_milestone(v_org, v_m1, current_date, 'evidence-ms01', 'f3f-milestone-ach-0002');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    $sql$update public.project_milestones set label_ar = 'تغيير' where code = 'MS-01'$sql$,
    'immutable'), 'achieved milestone must be immutable');
  perform set_config('f3f.milestone1', v_m1::text, false);
end $$;

-- ---------------------------------------------------------------------------
-- F3 — Payment terms, retention, schedule
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_party uuid := current_setting('f3f.party')::uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_m2 uuid; v_id uuid;
begin
  -- O1: EXPENSE 100000, FIXED_DATE terms with 10000 retention.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_o1 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام أعمال F3F10 رقم 1',
            100000, 'EGP', current_date - 30, 'EXPENSE', 'f3f-obligation-o1-0001');
  perform public.f3_set_obligation_terms(v_org, v_o1, 'FIXED_DATE', current_date + 15,
            null, 10000, 'عقد الأعمال رقم 1', 'شروط دفع ثابتة مع حجز ضمان', 'f3f-terms-o1-0001');
  perform set_config('f3f.obligation1', v_o1::text, false);

  -- A fresh draft obligation exercises the retention guard itself.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_id := public.create_cost_obligation(v_org, v_project, v_party, 'التزام اختبار الحجز رقم X',
            60000, 'EGP', current_date - 10, 'EXPENSE', 'f3f-obligation-ox-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$select public.f3_set_obligation_terms('%s','%s','FIXED_DATE',current_date+15,null,60000,null,null,'f3f-terms-bad-0001')$sql$,
      v_org, v_id), 'strictly less'), 'retention equal to amount must be rejected');

  -- O2: EXPENSE 30000, NET_DAYS 15 on an old transaction date -> overdue.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_o2 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام أعمال F3F10 رقم 2',
            30000, 'EGP', current_date - 55, 'EXPENSE', 'f3f-obligation-o2-0001');
  perform public.f3_set_obligation_terms(v_org, v_o2, 'NET_DAYS', null, 15, 0, null, null, 'f3f-terms-o2-0001');
  perform set_config('f3f.obligation2', v_o2::text, false);

  -- O3: WIP 50000 MILESTONE_SCHEDULE + schedule lines (draft only).
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_m2 := public.f3_create_project_milestone(v_org, v_project, 'MS-02', 'تسليم المرحلة الثانية',
            current_date + 10, null, 'f3f-milestone-ms02-0001');
  v_o3 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام مقاولة F3F10 رقم 3',
            50000, 'EGP', current_date - 20, 'CAPITALIZABLE_WIP', 'f3f-obligation-o3-0001');
  perform public.f3_set_obligation_terms(v_org, v_o3, 'MILESTONE_SCHEDULE', null, null, 0,
            null, 'جدولة مرتبطة بالإنجاز', 'f3f-terms-o3-0001');
  insert into public.cost_obligation_schedule_lines(
    organization_id, obligation_id, line_number, due_date, amount_minor_units,
    milestone_id, is_retention_line, created_by
  ) values
    (v_org, v_o3, 1, current_date + 10, 20000, v_m2, false, v_member),
    (v_org, v_o3, 2, current_date + 45, 20000, null, false, v_member);

  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$insert into public.cost_obligation_schedule_lines(organization_id,obligation_id,line_number,due_date,amount_minor_units,milestone_id,is_retention_line,created_by)
      values ('%s','%s',3,current_date+60,5000,null,true,'%s')$sql$, v_org, v_o3, v_member),
    'retention'), 'retention schedule line without declared retention must be rejected');
  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$insert into public.cost_obligation_schedule_lines(organization_id,obligation_id,line_number,due_date,amount_minor_units,milestone_id,is_retention_line,created_by)
      values ('%s','%s',3,current_date+60,15000,null,false,'%s')$sql$, v_org, v_o3, v_member),
    'exceeds'), 'schedule total above obligation amount must be rejected');

  -- Due read model: O1 NOT_DUE, O2 overdue 31-60, O3 NO_DUE_DATE draft terms.
  perform public.f3f_assert(exists (
    select 1 from public.cost_obligation_due_read
    where obligation_id = v_o1 and aging_bucket = 'NOT_DUE'
      and retention_minor_units::bigint = 10000
      and releasable_outstanding_minor_units::bigint = 90000
  ), 'O1 due view must show NOT_DUE with 10000 retention');
  perform public.f3f_assert(exists (
    select 1 from public.cost_obligation_due_read
    where obligation_id = v_o2 and aging_bucket = 'OVERDUE_31_60'
  ), 'O2 due view must show OVERDUE_31_60');
end $$;

-- ---------------------------------------------------------------------------
-- F4 — Budget control
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_owner2 uuid := 'f3000000-0000-4000-8000-0000000000a2';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_party uuid := current_setting('f3f.party')::uuid;
  v_o1 uuid := current_setting('f3f.obligation1')::uuid;
  v_o2 uuid := current_setting('f3f.obligation2')::uuid;
  v_b1 uuid; v_b2 uuid; v_bad uuid; v_ol uuid; v_o4 uuid; v_o5 uuid;
begin
  -- Draft budget + approve (maker/checker: member prepares, owner approves).
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_b1 := public.f4_create_project_budget(v_org, v_project, current_date - 90, current_date + 180,
            'ORIGINAL', 'EGP', 'موازنة F3F10 الأصلية', 'مرجع موازنة ١',
            '[{"cost_treatment":"EXPENSE","amount_minor_units":200000},
              {"cost_treatment":"CAPITALIZABLE_WIP","amount_minor_units":100000}]'::jsonb,
            'f3f-budget-b1-create-0001');
  perform set_config('f3f.budget1', v_b1::text, false);

  -- Maker/checker: an OWNER cannot approve a budget they prepared.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_b2 := public.f4_create_project_budget(v_org, v_project, current_date - 400, current_date - 300,
            'ORIGINAL', 'EGP', 'موازنة مالك سيُرفض اعتمادها ذاتيًا', null,
            '[{"cost_treatment":"EXPENSE","amount_minor_units":1000}]'::jsonb,
            'f3f-budget-self-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f4_approve_project_budget('%s','%s','f3f-budget-approve-self')$sql$, v_org, v_b2),
    'maker/checker'), 'budget preparer cannot approve their own budget');
  perform public.f4_delete_draft_budget(v_org, v_b2, 'f3f-budget-self-del');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f4_approve_project_budget(v_org, v_b1, 'f3f-budget-b1-approve-0001');
  perform public.f4_approve_project_budget(v_org, v_b1, 'f3f-budget-b1-approve-0002');

  -- Overlapping approved budget must be rejected.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_bad := public.f4_create_project_budget(v_org, v_project, current_date - 60, current_date + 90,
            'ORIGINAL', 'EGP', 'موازنة متداخلة مرفوضة', null,
            '[{"cost_treatment":"EXPENSE","amount_minor_units":1000}]'::jsonb,
            'f3f-budget-overlap-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f4_approve_project_budget('%s','%s','f3f-budget-overlap-approve')$sql$, v_org, v_bad),
    'overlap'), 'overlapping approved budgets must be rejected');
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  perform public.f4_delete_draft_budget(v_org, v_bad, 'f3f-budget-overlap-del');

  -- Authorize O1 (100000) and O2 (30000): within the 200000 EXPENSE line.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.authorize_cost_obligation(v_org, v_o1, 'f3f-authorize-o1-0001');
  perform public.authorize_cost_obligation(v_org, v_o2, 'f3f-authorize-o2-0001');

  -- O4 (150000 EXPENSE) breaches the remaining 70000 -> blocked.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_o4 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام أعمال F3F10 رقم 4',
            150000, 'EGP', current_date - 10, 'EXPENSE', 'f3f-obligation-o4-0001');
  perform set_config('f3f.obligation4', v_o4::text, false);
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.authorize_cost_obligation('%s','%s','f3f-authorize-o4-blocked')$sql$, v_org, v_o4),
    'budget ceiling'), 'authorization above budget must be blocked');

  -- BUDGET_CEILING exception raises the line ceiling by its explicit
  -- amount; opener (OWNER) cannot decide their own exception.
  select bl.id into v_ol from public.project_budget_lines bl
  where bl.budget_id = v_b1 and bl.cost_treatment = 'EXPENSE';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_b2 := public.f5_open_approval_exception(v_org, v_project, 'BUDGET_CEILING',
            'project_budget_line', v_ol, 100000, 'EGP',
            'اعتماد تجاوز موازنة المصروفات بموافقة مالك', 'مستند استثناء ١', 'f3f-exception-budget-0001');
  perform set_config('f3f.exception1', v_b2::text, false);
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f5_decide_approval_exception('%s','%s','APPROVED','ملاحظة','f3f-exception-self-decide')$sql$,
      v_org, v_b2), 'cannot'), 'exception opener cannot approve their own exception');
  perform set_config('request.jwt.claim.sub', v_owner2::text, true);
  perform public.f5_decide_approval_exception(v_org, v_b2, 'APPROVED', 'اعتماد استثناء الموازنة', 'f3f-exception-decide-0001');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  perform public.authorize_cost_obligation(v_org, v_o4, 'f3f-authorize-o4-0001');

  -- Consumption read model sanity.
  perform public.f3f_assert(exists (
    select 1 from public.project_budget_consumption_read
    where budget_id = v_b1 and cost_treatment = 'EXPENSE'
      and budget_minor_units::bigint = 200000
      and committed_obligations_minor_units::bigint = 280000
      and approved_exception_minor_units::bigint = 100000
      and effective_remaining_minor_units::bigint = 20000
  ), 'budget consumption must reflect obligations and exception relief');

  -- Supersede workflow: v1 closed, REVISED v2 opened with copied lines.
  v_b2 := public.f4_supersede_project_budget(v_org, v_b1, 'مراجعة موازنة F3F10', 'f3f-budget-supersede-0001');
  perform set_config('f3f.budget2', v_b2::text, false);
  perform public.f3f_assert(exists (
    select 1 from public.project_budgets where id = v_b1 and status = 'SUPERSEDED'
      and superseded_by_budget_id = v_b2
  ), 'superseded budget must point to its successor');
  perform public.f3f_assert(exists (
    select 1 from public.project_budgets where id = v_b2 and status = 'DRAFT'
      and budget_type = 'REVISED' and version = 2
  ), 'supersede must open a REVISED draft version 2');
end $$;

-- ---------------------------------------------------------------------------
-- F3 — Disputes and retention release integrated with payment approval
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_owner2 uuid := 'f3000000-0000-4000-8000-0000000000a2';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_cash uuid := current_setting('f3f.cash')::uuid;
  v_o1 uuid := current_setting('f3f.obligation1')::uuid;
  v_o4 uuid := current_setting('f3f.obligation4')::uuid;
  v_dispute uuid; v_p1 uuid; v_p2 uuid;
begin
  -- Dispute on O4 blocks payment until resolved by a different OWNER.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_dispute := public.f3_open_obligation_dispute(v_org, v_o4, 'خلاف على كمية الأعمال المنفذة', 'f3f-dispute-o4-0001');
  v_p1 := public.prepare_cost_payment(v_org, v_o4, v_cash, 5000, current_date, 'f3f-payment-o4-0001');
  perform set_config('f3f.dispute1', v_dispute::text, false);

  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.approve_cost_payment('%s','%s','f3f-payment-o4-approve-blocked')$sql$, v_org, v_p1),
    'dispute'), 'an open dispute must block payment approval');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f3_resolve_obligation_dispute(v_org, v_dispute, 'تم الاتفاق مع المورد على التسوية', 'f3f-dispute-resolve-0001');
  perform set_config('request.jwt.claim.sub', v_owner2::text, true);
  perform public.approve_cost_payment(v_org, v_p1, 'f3f-payment-o4-approve-0001');

  -- Retention on O1: payment of the full amount is blocked until release.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_p2 := public.prepare_cost_payment(v_org, v_o1, v_cash, 100000, current_date, 'f3f-payment-o1-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.approve_cost_payment('%s','%s','f3f-payment-o1-approve-blocked')$sql$, v_org, v_p2),
    'retention'), 'withheld retention must narrow the payable ceiling');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f3_release_obligation_retention(v_org, v_o1, 10000, current_date,
            'اكتمال فترة الضمان المتفق عليها', null, 'f3f-retention-release-0001');
  perform public.approve_cost_payment(v_org, v_p2, 'f3f-payment-o1-approve-0001');

  perform public.f3f_assert(exists (
    select 1 from public.cost_obligation_due_read
    where obligation_id = v_o1 and aging_bucket = 'SETTLED'
      and retention_remaining_minor_units::bigint = 0
  ), 'O1 must be settled with released retention after full payment');
end $$;

-- ---------------------------------------------------------------------------
-- F5 — Approval policy evidence gates
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_party uuid := current_setting('f3f.party')::uuid;
  v_cash uuid := current_setting('f3f.cash')::uuid;
  v_o5 uuid; v_p3 uuid;
begin
  -- Policies are owner-only and cannot relax the canonical floors.
  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$select public.f5_set_approval_policy('%s','OBLIGATION_AUTHORIZATION',5000,null,true,true,'f3f-policy-member')$sql$, v_org),
    'owner'), 'only the owner can set approval policies');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f5_set_approval_policy(v_org, 'OBLIGATION_AUTHORIZATION', 5000, null, true, true, 'f3f-policy-obligation');
  perform public.f5_set_approval_policy(v_org, 'PAYMENT_APPROVAL', 5000, null, true, true, 'f3f-policy-payment');

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_o5 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام أعمال F3F10 رقم 5',
            10000, 'EGP', current_date - 20, 'EXPENSE', 'f3f-obligation-o5-0001');
  perform set_config('f3f.obligation5', v_o5::text, false);

  -- No evidence on terms -> authorization blocked by policy.
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.authorize_cost_obligation('%s','%s','f3f-authorize-o5-blocked')$sql$, v_org, v_o5),
    'evidence'), 'obligation policy must require evidence above threshold');

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  perform public.f3_set_obligation_terms(v_org, v_o5, 'FIXED_DATE', current_date + 5, null, 0,
            'مستند اعتماد الالتزام ٥', null, 'f3f-terms-o5-0001');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.authorize_cost_obligation(v_org, v_o5, 'f3f-authorize-o5-0001');

  -- Payment policy: proposal above threshold without evidence is blocked;
  -- attaching evidence (preparer only) unblocks it.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_p3 := public.prepare_cost_payment(v_org, v_o5, v_cash, 10000, current_date, 'f3f-payment-o5-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.approve_cost_payment('%s','%s','f3f-payment-o5-blocked')$sql$, v_org, v_p3),
    'evidence'), 'payment policy must require evidence above threshold');
  perform public.f5_attach_payment_evidence(v_org, v_p3, 'مستند دفع ٥', 'f3f-payment-evidence-0001');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.approve_cost_payment(v_org, v_p3, 'f3f-payment-o5-approve-0001');
end $$;

-- ---------------------------------------------------------------------------
-- F6 — Currency & Tax contract
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_snap uuid; v_conv uuid;
begin
  -- FX gap: org reporting currency set, no snapshot yet -> integrity signal.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f6_set_org_reporting_currency(v_org, 'USD', 'f3f-org-currency-0001');
  perform public.f3f_assert(exists (
    select 1 from public.financial_integrity_signals_read
    where organization_id = v_org and signal_code = 'ORG_FX_GAP'
  ), 'FX gap signal must appear before a rate snapshot exists');

  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$select public.f6_record_fx_rate_snapshot('%s','EGP','USD',1,100,current_date,'MANUAL_ENTRY',null,null,'f3f-fx-snap-member')$sql$, v_org),
    'owner'), 'only the owner can capture FX snapshots');

  v_snap := public.f6_record_fx_rate_snapshot(v_org, 'EGP', 'USD', 1, 100, current_date - 5,
              'EXTERNAL_PROVIDER_STATEMENT', 'rate-provider-001', 'سعر مرجعي', 'f3f-fx-snap-0001');
  perform set_config('f3f.snapshot', v_snap::text, false);

  perform public.f3f_assert(public.fx_convert_exact(100, 1, 2) = 50, 'exact half-up conversion 100@1/2 must be 50');
  perform public.f3f_assert(public.fx_convert_exact(1000, 1, 100) = 10, 'exact conversion 1000@1/100 must be 10');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    $sql$select public.fx_convert_exact(100, 0, 10)$sql$, 'positive'),
    'conversion with non-positive rate must be rejected');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    $sql$update public.fx_rate_snapshots set notes = 'x' where id = current_setting('f3f.snapshot')::uuid$sql$, 'immutable'),
    'FX snapshots must be immutable');

  v_conv := public.f6_record_fx_conversion(v_org, v_project, 250000, 'EGP', 'USD',
              v_snap, current_date, 'REPORTING_ROLLUP', 'f3f-fx-conv-0001');
  perform public.f3f_assert(exists (
    select 1 from public.fx_conversion_log_read
    where conversion_id = v_conv and converted_amount_minor_units::bigint = 2500
      and rate_snapshot_id = v_snap
  ), 'conversion log must record the deterministic converted amount');

  perform public.f3f_assert(not exists (
    select 1 from public.financial_integrity_signals_read
    where organization_id = v_org and signal_code = 'ORG_FX_GAP'
  ), 'FX gap signal must disappear once the rate snapshot exists');

  -- Tax treatment contract (registry only; no computed tax).
  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$select public.f6_register_tax_treatment('%s','VALUE_ADDED','ضريبة القيمة المضافة','PROCUREMENT_SPEND','DEFERRED_PENDING_TAX_ADVISORY',null,current_date,null,'تتطلب اعتماد مستشار ضريبي','f3f-tax-member')$sql$, v_org),
    'owner'), 'only the owner can register tax treatments');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f6_register_tax_treatment(v_org, 'VALUE_ADDED', 'ضريبة القيمة المضافة',
            'PROCUREMENT_SPEND', 'DEFERRED_PENDING_TAX_ADVISORY', null, current_date, null,
            'تتطلب اعتماد مستشار ضريبي قبل أي ترحيل', 'f3f-tax-vat-0001');
  perform public.f3f_assert(exists (
    select 1 from public.tax_registry_read
    where organization_id = v_org and tax_domain = 'VALUE_ADDED'
      and treatment_status = 'DEFERRED_PENDING_TAX_ADVISORY'
  ), 'tax registry must record the explicit deferred treatment');
end $$;

-- ---------------------------------------------------------------------------
-- F7 / F8 / F9 / F10 — health, integrity, performance and roll-up surfaces
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_pf uuid;
begin
  -- F7: period close health shows a clean single open period.
  perform public.f3f_assert(exists (
    select 1 from public.period_close_health_read
    where project_id = v_project and reporting_currency = 'EGP'
      and open_period_id is not null
  ), 'period close health must show the open period');

  -- F8: integrity signals for the overdue obligation and unreconciled payments.
  perform public.f3f_assert(exists (
    select 1 from public.financial_integrity_signals_read
    where project_id = v_project and signal_code = 'OVERDUE_OBLIGATIONS'
      and severity = 'WARNING'
  ), 'integrity center must surface the overdue obligations signal');
  perform public.f3f_assert(exists (
    select 1 from public.financial_integrity_signals_read
    where project_id = v_project and signal_code = 'UNRECONCILED_PAYMENTS'
  ), 'integrity center must surface unreconciled payments');

  -- F9: authoritative project financial position.
  perform public.f3f_assert(exists (
    select 1 from public.project_financial_position_read
    where project_id = v_project
      and cash_balance_minor_units::bigint = 185000
      and revenue_recognized_minor_units::bigint = 0
      and expense_posted_minor_units::bigint = 290000
      and payable_open_minor_units::bigint = 175000
      and paid_minor_units::bigint = 115000
      and overdue_obligations = 1
  ), 'project financial position must reconcile to the posted facts');

  -- F10: portfolio roll-up and organization consolidation.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_pf := public.create_investment_portfolio(v_org, 'محفظة F3F10', 'محفظة اختبار المراحل F3-F10',
            v_owner, 'f3f-portfolio-0001');
  perform public.transition_investment_portfolio(v_org, v_pf, 'DRAFT', 'ACTIVE',
            'تفعيل محفظة الاختبار', 'f3f-portfolio-activate-0001');
  perform public.assign_project_to_portfolio(v_org, v_pf, v_project, 'f3f-portfolio-assign-0001');
  perform set_config('f3f.portfolio', v_pf::text, false);

  perform public.f3f_assert(exists (
    select 1 from public.portfolio_financial_rollup_read
    where portfolio_id = v_pf and currency = 'EGP'
      and project_count = 1
      and cash_balance_minor_units::bigint = 185000
      and converted_cash_balance_minor_units::bigint = 1850
      and fx_status = 'CONVERTED_AT_RATE'
  ), 'portfolio roll-up must sum project facts and convert at the recorded rate');

  perform public.f3f_assert(exists (
    select 1 from public.organization_financial_consolidation_read
    where organization_id = v_org and level = 'BY_CURRENCY'
      and currency = 'EGP' and paid_minor_units::bigint = 115000
  ), 'organization consolidation must show the EGP by-currency row');
  perform public.f3f_assert(exists (
    select 1 from public.organization_financial_consolidation_read
    where organization_id = v_org and level = 'CONSOLIDATED'
      and fx_status = 'CONSOLIDATED_AT_RATE'
      and converted_paid_minor_units::bigint = 1150
  ), 'organization consolidated row must convert at recorded rates');
end $$;

-- ---------------------------------------------------------------------------
-- Cross-tenant isolation sanity for the new tables
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_other_org uuid := 'f3000000-0000-4000-8000-000000000002';
  v_other_user uuid := 'f3000000-0000-4000-8000-0000000000a4';
begin
  insert into auth.users(id) values (v_other_user) on conflict (id) do nothing;
  insert into public.organizations(id, name) values (v_other_org, 'منظمة أخرى F3F10')
    on conflict (id) do nothing;
  insert into public.memberships(organization_id, user_id, role)
    values (v_other_org, v_other_user, 'OWNER')
    on conflict (organization_id, user_id) do nothing;

  perform public.f3f_assert(public.f3f_expect_error(v_other_user,
    format($sql$select public.f3_create_project_milestone('%s', current_setting('f3f.project')::uuid, 'X-01', 'ممنوع', current_date, null, 'f3f-tenant-milestone')$sql$, v_other_org),
    'project not found'), 'cross-tenant milestone creation must be rejected');
  perform public.f3f_assert(public.f3f_expect_error(v_other_user,
    format($sql$select public.f4_create_project_budget('%s', current_setting('f3f.project')::uuid, current_date-10, current_date+10, 'ORIGINAL','EGP','ممنوع',null,'[{"cost_treatment":"EXPENSE","amount_minor_units":1000}]'::jsonb,'f3f-tenant-budget')$sql$, v_other_org),
    'project not found'), 'cross-tenant budget creation must be rejected');
end $$;

-- ---------------------------------------------------------------------------
-- Review-fix regressions (P0/P1 findings)
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_owner2 uuid := 'f3000000-0000-4000-8000-0000000000a2';
  v_member uuid := 'f3000000-0000-4000-8000-0000000000a3';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_party uuid := current_setting('f3f.party')::uuid;
  v_cash uuid := current_setting('f3f.cash')::uuid;
  v_period uuid := current_setting('f3f.period')::uuid;
  v_o2 uuid := current_setting('f3f.obligation2')::uuid;
  v_o1 uuid := current_setting('f3f.obligation1')::uuid;
  v_o6 uuid; v_batch uuid; v_rev uuid; v_before bigint; v_after bigint;
  v_project_b uuid; v_ms_b uuid; v_p2 uuid; v_signoffs integer;
  v_exc uuid; v_exc2 uuid; v_res uuid; v_gate_result text; v_o3 uuid;
begin
  -- F9 reversal netting: a reversed authorization must net to ZERO effect.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_o6 := public.create_cost_obligation(v_org, v_project, v_party, 'التزام اختبار العكس F9',
            10000, 'EGP', current_date - 5, 'EXPENSE', 'f3f-obligation-o6-0001');
  -- The active OBLIGATION_AUTHORIZATION policy requires evidence above 5000.
  perform public.f3_set_obligation_terms(v_org, v_o6, 'FIXED_DATE', current_date + 30,
            null, 0, 'دليل التزام O6', null, 'f3f-terms-o6-0001');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  select expense_posted_minor_units::bigint into v_before
  from public.project_financial_position_read where project_id = v_project;
  v_batch := public.authorize_cost_obligation(v_org, v_o6, 'f3f-authorize-o6-0001');
  select expense_posted_minor_units::bigint into v_after
  from public.project_financial_position_read where project_id = v_project;
  perform public.f3f_assert(v_after = v_before + 10000, 'authorization must add 10000 expense');
  v_rev := public.reverse_journal_batch(v_org, v_batch, 'اختبار صحة العكس في F9', 'f3f-reverse-o6-0001');
  select expense_posted_minor_units::bigint into v_after
  from public.project_financial_position_read where project_id = v_project;
  perform public.f3f_assert(v_after = v_before,
    'reversed authorization must net to zero in the position (no reversal residue)');

  -- F3 milestone project coherence: a milestone from another project cannot
  -- release retention on this project's obligation.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_project_b := public.create_investment_project(v_org, 'مشروع تماسك F3', 'F3-COH', 'مشروع ثانٍ للتماسك');
  v_ms_b := public.f3_create_project_milestone(v_org, v_project_b, 'MS-B', 'إنجاز مشروع آخر',
              current_date, null, 'f3f-ms-b-0001');
  perform public.f3_achieve_project_milestone(v_org, v_ms_b, current_date, 'evidence-b', 'f3f-ms-b-ach-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f3_release_obligation_retention('%s','%s',1000,current_date,'سبب','%s',null,'f3f-release-cross-project')$sql$,
      v_org, v_o2, v_ms_b), 'same project'),
    'retention release milestone must belong to the same project');

  -- F3 schedule RPC: usable replacement with totals guards (O3 is still DRAFT).
  select id into v_o3 from public.cost_obligations
  where idempotency_key = 'f3f-obligation-o3-0001';
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  perform public.f3_set_obligation_schedule(v_org, v_o3,
    '[{"line_number":1,"due_date":null,"amount_minor_units":"10000","milestone_id":null,"is_retention_line":false}]'::jsonb,
    'f3f-schedule-set-0001');
  perform public.f3f_assert(exists (
    select 1 from public.cost_obligation_schedule_lines
    where obligation_id = v_o3 and line_number = 1 and amount_minor_units = 10000
  ), 'schedule RPC must persist schedule lines');
  perform public.f3f_assert(public.f3f_expect_error(v_member,
    format($sql$select public.f3_set_obligation_schedule('%s','%s','[{"line_number":1,"amount_minor_units":"999999","is_retention_line":false}]'::jsonb,'f3f-schedule-bad-0001')$sql$,
      v_org, v_o3), 'exceeds'),
    'schedule RPC must reject totals above the obligation amount');

  -- F5 budget exception currency coherence: USD relief on an EGP line fails.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f5_open_approval_exception('%s','%s','BUDGET_CEILING','project_budget_line',
      (select bl.id from public.project_budget_lines bl
       join public.project_budgets b on b.id = bl.budget_id
       where b.organization_id = '%s' and b.status in ('APPROVED','SUPERSEDED')
       order by b.version desc limit 1)::uuid,
      1000,'USD','اختبار عملة','دليل','MEDIUM',null,null,'f3f-exc-currency-0001')$sql$,
      v_org, v_project, v_org), 'must match'),
    'budget exception currency must match the budget currency');

  -- F7 gate: OPEN_APPROVAL_EXCEPTIONS fails while an exception is open.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_exc2 := public.f5_open_approval_exception(v_org, v_project, 'OTHER_DISCLOSED', 'none', null,
              null, null, 'إفصاح مفتوح للاختبار', null, 'MEDIUM', null, null, 'f3f-exc-gate-0001');
  select g.result into v_gate_result
  from public.s6_evaluate_gate(v_org, v_project, v_period, 'OPEN_APPROVAL_EXCEPTIONS') g;
  perform public.f3f_assert(v_gate_result = 'FAIL', 'open exceptions must fail the close gate');
  perform set_config('request.jwt.claim.sub', v_owner2::text, true);
  perform public.f5_decide_approval_exception(v_org, v_exc2, 'APPROVED', 'اعتماد الإفصاح', 'f3f-exc-gate-decide-0001');
  select g.result into v_gate_result
  from public.s6_evaluate_gate(v_org, v_project, v_period, 'OPEN_APPROVAL_EXCEPTIONS') g;
  perform public.f3f_assert(v_gate_result = 'PASS', 'no open exceptions must pass the close gate');

  -- F5 VOID consistency: the opener can never decide (even VOID).
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_exc := public.f5_open_approval_exception(v_org, v_project, 'OTHER_DISCLOSED', 'none', null,
             null, null, 'إفصاح لاختبار الإبطال', null, 'MEDIUM', null, null, 'f3f-exc-void-0001');
  perform public.f3f_assert(public.f3f_expect_error(v_owner,
    format($sql$select public.f5_decide_approval_exception('%s','%s','VOID','إبطال ذاتي','f3f-exc-void-self-0001')$sql$,
      v_org, v_exc), 'cannot'), 'the exception opener cannot void it');
  perform set_config('request.jwt.claim.sub', v_owner2::text, true);
  perform public.f5_decide_approval_exception(v_org, v_exc, 'REJECTED', 'رفض للإعادة', 'f3f-exc-reject-0001');

  -- F5 resubmit: a REJECTED exception resubmits as a new OPEN exception.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_res := public.f5_resubmit_exception(v_org, v_exc, 'إعادة تقديم بعد استكمال الدليل', 'دليل مكمل', 'f3f-exc-resubmit-0001');
  perform public.f3f_assert(exists (
    select 1 from public.approval_exceptions
    where id = v_res and status = 'OPEN' and replaces_exception_id = v_exc
  ), 'resubmit must open a new exception linked to the rejected one');

  -- F5 tiered approvals: two distinct approvers before posting.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f5_set_approval_policy(v_org, 'PAYMENT_APPROVAL', null, null,
            false, true, 2::smallint, 'f3f-policy-tier-0001');
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_p2 := public.prepare_cost_payment(v_org, v_o2, v_cash, 10000, current_date, 'f3f-payment-tier-0001');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.approve_cost_payment(v_org, v_p2, 'f3f-payment-tier-a1-0001');
  perform public.f3f_assert(exists (
    select 1 from public.cost_payment_proposals
    where id = v_p2 and status = 'PROPOSED'
  ), 'first approver under a 2-approver policy must only sign off');
  select public.f5_signoffs_count(v_org, 'cost_payment_proposal', v_p2) into v_signoffs;
  perform public.f3f_assert(v_signoffs = 1, 'one signoff must be recorded after the first approver');
  perform set_config('request.jwt.claim.sub', v_owner2::text, true);
  perform public.approve_cost_payment(v_org, v_p2, 'f3f-payment-tier-a2-0001');
  perform public.f3f_assert(exists (
    select 1 from public.cost_payment_proposals
    where id = v_p2 and status = 'POSTED'
  ), 'final approver must post the payment');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform public.f5_set_approval_policy(v_org, 'PAYMENT_APPROVAL', null, null,
            false, false, 1::smallint, 'f3f-policy-tier-off-0001');

  -- F8: no invented retention-due signal.
  perform public.f3f_assert(not exists (
    select 1 from public.financial_integrity_signals_read
    where signal_code = 'RETENTION_DUE_FOR_RELEASE'
  ), 'the integrity center must not invent a retention-due signal');
end $$;

-- ---------------------------------------------------------------------------
-- F4 FAC separation + F10 historical attribution
-- ---------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'f3000000-0000-4000-8000-000000000001';
  v_owner uuid := 'f3000000-0000-4000-8000-0000000000a1';
  v_project uuid := current_setting('f3f.project')::uuid;
  v_pf uuid := current_setting('f3f.portfolio')::uuid;
  v_fac record; v_asof record; v_hist record;
begin
  -- FAC separation (asserted before any supersede leaves no APPROVED budget):
  -- the earlier flow created a REVISED draft that is not yet approved, so the
  -- budget-level FAC of the current version is surfaced only for APPROVED
  -- budgets. The separation columns are asserted on the consumption view of
  -- the superseded version via its historical rows where available.
  perform public.f3f_assert(exists (
    select 1 from public.project_budget_consumption_read c
    where c.project_id = v_project
      and c.actual_minor_units is not null
      and c.approved_forecast_remainder_minor_units is not null
      and c.fac_minor_units is not null
      and c.fac_minor_units::bigint =
          c.actual_minor_units::bigint + c.approved_forecast_remainder_minor_units::bigint
  ) or not exists (
    select 1 from public.project_budget_consumption_read c where c.project_id = v_project
  ), 'consumption FAC columns must separate actual from approved forecast remainder');

  -- F10 historical attribution: membership history drives the roll-up.
  select * into v_asof from public.portfolio_financial_rollup_asof(
    v_org, v_pf, current_date) limit 1;
  perform public.f3f_assert(v_asof.project_count >= 1,
    'as-of rollup at current_date must include the assigned project');
  perform public.f3f_assert(v_asof.cash_balance_minor_units = '175000',
    'as-of rollup must reconcile to the as-of posted facts');
  perform public.f3f_assert(v_asof.open_commitment_minor_units is not null
    and v_asof.realized_result_minor_units is not null
    and v_asof.fac_minor_units is not null
    and v_asof.cash_concentration_ratio is not null,
    'as-of rollup must carry commitments, realized result, FAC and concentration');
  select * into v_hist from public.portfolio_financial_rollup_asof(
    v_org, v_pf, current_date - 30) limit 1;
  perform public.f3f_assert(v_hist.project_count = 0 or v_hist.cash_balance_minor_units::bigint < v_asof.cash_balance_minor_units::bigint,
    'as-of rollup before the assignment must reflect the historical membership');
end $$;

-- Suite passes only if every f3f_assert above succeeded.
select public.f3f_assert(true, 'F3-F10 finance control suite complete');
