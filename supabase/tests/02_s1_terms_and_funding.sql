-- GF-003 / S1 — Terms & Funding behavioral gate.
-- Real concurrent-session checks run separately in 03_s1_concurrency.sh.

delete from public.audit_events;
delete from public.contributions;
delete from public.capital_call_lines;
delete from public.capital_calls;
delete from public.commitment_terms;
delete from public.agreement_versions;
delete from public.investment_agreements;
delete from public.project_participants;
delete from public.parties;
delete from public.investment_projects;
delete from public.memberships;
delete from public.organizations;
delete from auth.users;

insert into auth.users values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002');
insert into public.organizations(id,name) values
  ('10000000-0000-4000-8000-000000000001','منظمة ألف'),
  ('20000000-0000-4000-8000-000000000002','منظمة باء');
insert into public.memberships(organization_id,user_id,role) values
  ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','OWNER'),
  ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','OWNER');

create or replace function s1_expect_raise(p_user uuid, p_sql text, p_sqlstate text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate = p_sqlstate;
end $$;

create or replace function s1_expect_ok(p_user uuid, p_sql text)
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return true;
exception when others then
  reset role;
  raise notice 's1_expect_ok failed: %', sqlerrm;
  return false;
end $$;

create or replace function s1_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
end $$;

-- Executes as the database owner so trigger-level immutability/scope guards are
-- tested independently of authenticated privilege denial.
create or replace function s1_owner_expect_raise(p_sql text, p_sqlstate text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate = p_sqlstate;
end $$;

-- Projects and parties.
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع النخيل',null,null)$$);
select id as project_a from public.investment_projects where name='مشروع النخيل' \gset
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع ثانٍ',null,null)$$);
select id as project_a2 from public.investment_projects where name='مشروع ثانٍ' \gset

select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مستثمر أول','PERSON')$$);
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مستثمر ثانٍ','PERSON')$$);
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مستثمر مشروع ثانٍ','PERSON')$$);
select id as party_a1 from public.parties where legal_name='مستثمر أول' \gset
select id as party_a2 from public.parties where legal_name='مستثمر ثانٍ' \gset
select id as party_a3 from public.parties where legal_name='مستثمر مشروع ثانٍ' \gset

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$, :'project_a', :'party_a1'));
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$, :'project_a', :'party_a2'));
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$, :'project_a2', :'party_a3'));
select id as part_a1 from public.project_participants where party_id=:'party_a1' \gset
select id as part_a2 from public.project_participants where party_id=:'party_a2' \gset
select id as part_a3 from public.project_participants where party_id=:'party_a3' \gset

select s1_run('00000000-0000-4000-8000-000000000002',
  $$select public.create_party('20000000-0000-4000-8000-000000000002','طرف باء','PERSON')$$);
select id as party_b1 from public.parties where legal_name='طرف باء' \gset

-- Tenant and project scope.
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000002', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$,
  :'project_a', :'party_b1'), 'P0001') then 1 else 0 end as cross_tenant_participant_rejected;

create or replace function s1_cross_tenant_read(p_user uuid, p_project uuid) returns boolean
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  return not exists (select 1 from public.investment_projects where id=p_project);
end $$;
select 1/case when s1_cross_tenant_read('00000000-0000-4000-8000-000000000002',:'project_a')
  then 1 else 0 end as cross_tenant_project_read_denied;

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-08-10',array[%L::uuid],array[100]::bigint[],'agreement-cross-project')$$,
  :'project_a', :'part_a3'), 'P0001') then 1 else 0 end as cross_project_commitment_rejected;

-- Draft idempotency and payload binding.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-08-10',array[%L::uuid,%L::uuid],array[1000000,500000]::bigint[],'agreement-main-0001')$$,
  :'project_a', :'part_a1', :'part_a2'));
select id as version_a1 from public.agreement_versions where idempotency_key='agreement-main-0001' \gset

select 1/case when s1_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-08-10',array[%L::uuid,%L::uuid],array[1000000,500000]::bigint[],'agreement-main-0001')$$,
  :'project_a', :'part_a1', :'part_a2')) then 1 else 0 end as agreement_retry_same_payload_ok;
select 1/case when (select count(*) from public.agreement_versions where idempotency_key='agreement-main-0001')=1 then 1 else 0 end as agreement_retry_single_effect;
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-08-10',array[%L::uuid,%L::uuid],array[999999,500000]::bigint[],'agreement-main-0001')$$,
  :'project_a', :'part_a1', :'part_a2'), 'P0001') then 1 else 0 end as agreement_retry_payload_mismatch_rejected;

-- Activation is idempotent, then the S1 governing boundary freezes participants and versions.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.activate_agreement_version('10000000-0000-4000-8000-000000000001',%L)$$, :'version_a1'));
select 1/case when s1_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.activate_agreement_version('10000000-0000-4000-8000-000000000001',%L)$$, :'version_a1')) then 1 else 0 end as activation_retry_ok;
select 1/case when (select lifecycle_state from public.investment_projects where id=:'project_a')='FUNDING' then 1 else 0 end as project_entered_funding;

select 1/case when s1_owner_expect_raise(format(
  $$update public.agreement_versions set status='DRAFT' where id=%L::uuid$$, :'version_a1'), 'P0001')
  then 1 else 0 end as activated_version_immutable;

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-09-01',array[%L::uuid],array[1000000]::bigint[],'agreement-amendment-deferred')$$,
  :'project_a', :'part_a1'), 'P0001') then 1 else 0 end as amendment_draft_after_activation_rejected;

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$,
  :'project_a', :'party_a3'), 'P0001') then 1 else 0 end as participant_change_after_activation_rejected;

select 1/case when s1_owner_expect_raise(format(
  $$update public.commitment_terms set commitment_minor_units=999 where agreement_version_id=%L::uuid$$,
  :'version_a1'), 'P0001') then 1 else 0 end as activated_commitments_immutable;

-- Capital-call idempotency, payload binding, and ceiling.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,date '2026-09-15','CALL-1',array[%L::uuid,%L::uuid],array[600000,200000]::bigint[],'call-main-0001')$$,
  :'project_a', :'version_a1', :'part_a1', :'part_a2'));
select id as call_1 from public.capital_calls where idempotency_key='call-main-0001' \gset

select 1/case when s1_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,date '2026-09-15','CALL-1',array[%L::uuid,%L::uuid],array[600000,200000]::bigint[],'call-main-0001')$$,
  :'project_a', :'version_a1', :'part_a1', :'part_a2')) then 1 else 0 end as capital_call_retry_same_payload_ok;
select 1/case when (select count(*) from public.capital_calls where idempotency_key='call-main-0001')=1 then 1 else 0 end as capital_call_retry_single_effect;
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,date '2026-09-15','CALL-1',array[%L::uuid],array[1]::bigint[],'call-main-0001')$$,
  :'project_a', :'version_a1', :'part_a1'), 'P0001') then 1 else 0 end as capital_call_retry_payload_mismatch_rejected;
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,date '2026-09-20','CALL-OVER',array[%L::uuid],array[400000]::bigint[],'call-over-a2')$$,
  :'project_a', :'version_a1', :'part_a2'), 'P0001') then 1 else 0 end as call_exceeding_commitment_rejected;

-- Contributions: exact key replay, mismatched replay rejection, and call ceiling.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,600000,'EGP',date '2026-09-12','contrib-main-a1')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_1'));
select id as contrib_1 from public.contributions where idempotency_key='contrib-main-a1' \gset
select 1/case when s1_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,600000,'EGP',date '2026-09-12','contrib-main-a1')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_1')) then 1 else 0 end as contribution_retry_same_payload_ok;
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,599999,'EGP',date '2026-09-12','contrib-main-a1')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_1'), 'P0001') then 1 else 0 end as contribution_retry_payload_mismatch_rejected;

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,150000,'EGP',current_date,'contrib-main-a2-1')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'));
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,50000,'EGP',date '2026-09-14','contrib-main-a2-2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'));
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,1,'EGP',date '2026-09-15','contrib-over-a2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'), 'P0001') then 1 else 0 end as contribution_after_full_rejected;

select 1/case when s1_owner_expect_raise(format(
  $$update public.contributions set contribution_minor_units=1 where id=%L::uuid$$,
  :'contrib_1'), 'P0001') then 1 else 0 end as contribution_append_only;

-- Privileged same-tenant cross-project writes are rejected by database guards too.
select 1/case when s1_owner_expect_raise(format(
  $$insert into public.commitment_terms(organization_id,agreement_version_id,participant_id,commitment_minor_units,currency) values ('10000000-0000-4000-8000-000000000001',%L::uuid,%L::uuid,1,'EGP')$$,
  :'version_a1', :'part_a3'), 'P0001') then 1 else 0 end as privileged_cross_project_commitment_rejected;

-- Exact derived rollforward and exact-text transport views.
select 1/case when (select committed_minor_units from public.project_capital_position where project_id=:'project_a')=1500000 then 1 else 0 end as rollforward_committed_exact;
select 1/case when (select called_minor_units from public.project_capital_position where project_id=:'project_a')=800000 then 1 else 0 end as rollforward_called_exact;
select 1/case when (select contributed_minor_units from public.project_capital_position where project_id=:'project_a')=800000 then 1 else 0 end as rollforward_contributed_exact;
select 1/case when (select receivable_minor_units from public.project_capital_position where project_id=:'project_a')=0 then 1 else 0 end as rollforward_receivable_zero;
select 1/case when pg_typeof((select committed_minor_units from public.project_capital_position_read where project_id=:'project_a'))='text'::regtype then 1 else 0 end as money_transport_is_text;

-- Prepare deterministic race cases for 03_s1_concurrency.sh.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,date '2026-10-01','CALL-RACE',array[%L::uuid],array[400000]::bigint[],'call-race-contribution')$$,
  :'project_a', :'version_a1', :'part_a1'));

-- Direct browser DML remains denied.
do $$
begin
  execute 'set role authenticated';
  begin
    execute 'insert into public.parties(organization_id,legal_name) values (''10000000-0000-4000-8000-000000000001'',''should fail'')';
    raise exception 'direct insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 1/case when (
  select count(distinct event_type) from public.audit_events where event_type in
  ('AGREEMENT_VERSION_ACTIVATED','CAPITAL_CALL_ISSUED','CONTRIBUTION_RECORDED')
)=3 then 1 else 0 end as s1_workflow_audited;

select 'S1 terms and funding SQL PASS' as result;
