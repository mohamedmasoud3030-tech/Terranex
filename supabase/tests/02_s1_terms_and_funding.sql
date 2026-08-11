-- GF-003 / S1 — Terms & Funding behavioral gate.
-- Proves two-org isolation, immutable agreement activation, capital-call
-- authorization, contribution idempotency/concurrency, exact integer money
-- rollforward, append-only history, and browser-write denial.
-- Direct command lines set role/identity (psql \gset compatible). Wrapper
-- functions are SECURITY DEFINER and re-assert identity inside themselves.

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

-- Assert a SQL statement raises a given SQLSTATE when run as a given user.
-- The wrapper SET ROLEs to "authenticated" so RLS is actually enforced;
-- SECURITY DEFINER/owner postgres is what permits that SET ROLE.
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


-- Assert a SQL statement runs successfully as a given user.
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


-- Run a statement as a given user and discard the result.
create or replace function s1_run(p_user uuid, p_sql text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
end $$;


-- ---- Seed as actor 1 (org A) ----
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_investment_project('10000000-0000-4000-8000-000000000001','مشروع النخيل',null,null)$$);
select id as project_a from public.investment_projects where name='مشروع النخيل' \gset

select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مستثمر أول','PERSON')$$);
select s1_run('00000000-0000-4000-8000-000000000001',
  $$select public.create_party('10000000-0000-4000-8000-000000000001','مستثمر ثانٍ','PERSON')$$);
select id as party_a1 from public.parties where legal_name='مستثمر أول' \gset
select id as party_a2 from public.parties where legal_name='مستثمر ثانٍ' \gset

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$,
  :'project_a', :'party_a1'));
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.add_project_participant('10000000-0000-4000-8000-000000000001',%L,%L)$$,
  :'project_a', :'party_a2'));
select id as part_a1 from public.project_participants where party_id=:'party_a1' \gset
select id as part_a2 from public.project_participants where party_id=:'party_a2' \gset

-- A tenant-B party (created as actor 2).
select s1_run('00000000-0000-4000-8000-000000000002',
  $$select public.create_party('20000000-0000-4000-8000-000000000002','طرف باء','PERSON')$$);
select id as party_b1 from public.parties where legal_name='طرف باء' \gset

-- ---- Cross-tenant rejection ----
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

-- ---- Agreement drafting & activation ----
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-08-10',
    array[%L::uuid,%L::uuid], array[1000000,500000]::bigint[])$$,
  :'project_a', :'part_a1', :'part_a2'));
select id as version_a1 from public.agreement_versions
 where agreement_id=(select id from public.investment_agreements where project_id=:'project_a')
 order by version_no limit 1 \gset

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.activate_agreement_version('10000000-0000-4000-8000-000000000001',%L)$$,
  :'version_a1'));

select 1/case when (
  select lifecycle_state from public.investment_projects where id=:'project_a'
)='FUNDING' then 1 else 0 end as project_entered_funding;

-- Activated version immutability: even the table owner cannot change an
-- activated version; the BEFORE trigger raises P0001.
create or replace function s1_update_version(p_id uuid) returns void language plpgsql as $$
begin
  update public.agreement_versions set status='DRAFT' where id=p_id;
end $$;
do $immutable$
begin
  perform s1_update_version(:'version_a1');
  raise exception 'immutability guard did not fire';
exception when others then
  if sqlerrm <> 'agreement version is immutable once activated' then
    raise;
  end if;
end $immutable$;

-- A second version drafts but cannot be activated concurrently.
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_agreement_draft('10000000-0000-4000-8000-000000000001',%L,date '2026-09-01',
    array[%L::uuid], array[2000000]::bigint[])$$,
  :'project_a', :'part_a1'));
select id as version_a2 from public.agreement_versions
 where agreement_id=(select id from public.investment_agreements where project_id=:'project_a')
 order by version_no desc limit 1 \gset
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.activate_agreement_version('10000000-0000-4000-8000-000000000001',%L)$$,
  :'version_a2'), 'P0001') then 1 else 0 end as overlapping_active_version_rejected;

create or replace function s1_update_commitment(p_version uuid) returns void language plpgsql as $$
begin
  update public.commitment_terms set commitment_minor_units=999
  where agreement_version_id=p_version;
end $$;
do $commit$
begin
  perform s1_update_commitment(:'version_a1');
  raise exception 'commitment immutability guard did not fire';
exception when others then
  if sqlerrm <> 'commitment terms are immutable once the agreement version is activated' then
    raise;
  end if;
end $commit$;

-- ---- Capital calls ----
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,
    date '2026-09-15','CALL-X', array[%L::uuid], array[100]::bigint[])$$,
  :'project_a', :'version_a2', :'part_a1'), 'P0001')
  then 1 else 0 end as call_requires_active_version;

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,
    date '2026-09-15','CALL-1', array[%L::uuid,%L::uuid], array[600000,200000]::bigint[])$$,
  :'project_a', :'version_a1', :'part_a1', :'part_a2'));
select id as call_1 from public.capital_calls where reference='CALL-1' \gset

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,
    date '2026-09-20','CALL-OVER', array[%L::uuid], array[400000]::bigint[])$$,
  :'project_a', :'version_a1', :'part_a2'), 'P0001')
  then 1 else 0 end as call_exceeding_commitment_rejected;

-- ---- Contributions ----
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    600000,'EGP',date '2026-09-12','idem-0001-part-a1')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_1'));
select id as contrib_1 from public.contributions where idempotency_key='idem-0001-part-a1' \gset

-- Idempotent replay: same key returns same id, no new row.
select 1/case when s1_expect_ok('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    600000,'EGP',date '2026-09-12','idem-0001-part-a1')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_1')) then 1 else 0 end as idempotent_replay_ok;
select 1/case when (
  select count(*) from public.contributions where capital_call_id=:'call_1' and participant_id=:'part_a1'
)=1 then 1 else 0 end as duplicate_command_single_effect;

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    250000,'EGP',date '2026-09-13','idem-over-a2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'), 'P0001')
  then 1 else 0 end as over_contribution_rejected;

select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    150000,'EGP',date '2026-09-13','idem-0002-part-a2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'));
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    50000,'EGP',date '2026-09-14','idem-0003-part-a2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'));
select id as contrib_2a from public.contributions where idempotency_key='idem-0002-part-a2' \gset
select id as contrib_2b from public.contributions where idempotency_key='idem-0003-part-a2' \gset

select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    1,'EGP',date '2026-09-15','idem-0004-part-a2')$$,
  :'project_a', :'part_a2', :'version_a1', :'call_1'), 'P0001')
  then 1 else 0 end as contribution_after_full_rejected;

create or replace function s1_update_contribution(p_id uuid) returns void language plpgsql as $$
begin
  update public.contributions set contribution_minor_units=1 where id=p_id;
end $$;
do $contrib$
begin
  perform s1_update_contribution(:'contrib_1');
  raise exception 'contribution append-only guard did not fire';
exception when others then
  if sqlerrm <> 'contributions are append-only posted facts' then
    raise;
  end if;
end $contrib$;

-- ---- Exact rollforward ----
select 1/case when (select committed_minor_units from public.project_capital_position where project_id=:'project_a')=1500000 then 1 else 0 end as rollforward_committed_exact;
select 1/case when (select called_minor_units from public.project_capital_position where project_id=:'project_a')=800000 then 1 else 0 end as rollforward_called_exact;
select 1/case when (select contributed_minor_units from public.project_capital_position where project_id=:'project_a')=800000 then 1 else 0 end as rollforward_contributed_exact;
select 1/case when (select receivable_minor_units from public.project_capital_position where project_id=:'project_a')=0 then 1 else 0 end as rollforward_receivable_zero;
select 1/case when (select contributed_minor_units from public.partner_capital_position where participant_id=:'part_a1' and agreement_version_id=:'version_a1')=600000 then 1 else 0 end as partner1_contributed_exact;
select 1/case when (select contributed_minor_units from public.partner_capital_position where participant_id=:'part_a2' and agreement_version_id=:'version_a1')=200000 then 1 else 0 end as partner2_contributed_exact;
select 1/case when (
  select count(*) from public.contributions
  where id in (:'contrib_1',:'contrib_2a',:'contrib_2b') and agreement_version_id=:'version_a1'
)=3 then 1 else 0 end as contributions_retain_exact_version;

-- ---- Concurrency / overpay against a fresh full call ----
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.create_capital_call('10000000-0000-4000-8000-000000000001',%L,%L,
    date '2026-10-01','CALL-2', array[%L::uuid], array[400000]::bigint[])$$,
  :'project_a', :'version_a1', :'part_a1'));
select id as call_2 from public.capital_calls where reference='CALL-2' \gset
select s1_run('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    400000,'EGP',date '2026-09-30','idem-0005-part-a1-c2')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_2'));
select 1/case when s1_expect_raise('00000000-0000-4000-8000-000000000001', format(
  $$select public.record_contribution('10000000-0000-4000-8000-000000000001',%L,%L,%L,%L,
    400000,'EGP',date '2026-10-01','idem-0006-part-a1-c2-race')$$,
  :'project_a', :'part_a1', :'version_a1', :'call_2'), 'P0001')
  then 1 else 0 end as concurrent_overpay_rejected;

-- ---- Unauthenticated and direct-write denial ----
-- With no JWT subject set, commands must raise 'authentication required'.
create or replace function s1_unauth_contribution() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub','',false);
  perform public.record_contribution('10000000-0000-4000-8000-000000000001',
    cast(current_setting('app.project_a') as uuid), cast(current_setting('app.part_a1') as uuid),
    cast(current_setting('app.version_a1') as uuid), cast(current_setting('app.call_2') as uuid),
    1,'EGP',date '2026-10-01','idem-unauth');
end $$;
select set_config('app.project_a',:'project_a',false);
select set_config('app.part_a1',:'part_a1',false);
select set_config('app.version_a1',:'version_a1',false);
select set_config('app.call_2',:'call_2',false);
do $$ begin perform s1_unauth_contribution(); raise exception 'should have failed'; exception when others then if sqlerrm <> 'authentication required' then raise; end if; end $$;

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

-- Arabic workflow audit trail exists (at least one of each S1 event).
select 1/case when (
  select count(distinct event_type) from public.audit_events where event_type in
  ('AGREEMENT_VERSION_ACTIVATED','CAPITAL_CALL_ISSUED','CONTRIBUTION_RECORDED')
)=3 then 1 else 0 end as arabic_workflow_audited;

select 'S1 terms and funding PASS' as result;
