-- R2 project governance behavioral/security gate.

create or replace function r2gov_run_uuid(p_user uuid,p_sql text)
returns uuid language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end $$;

create or replace function r2gov_expect_raise(p_user uuid,p_sql text,p_sqlstate text default 'P0001')
returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then
  reset role;
  return sqlstate=p_sqlstate;
end $$;

create or replace function r2gov_count_as(p_user uuid,p_sql text)
returns bigint language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end $$;

-- Security contract: browser roles read projections but cannot write tables;
-- SECDEF commands are authenticated-only.
do $$
declare proc_row record;
begin
  if has_table_privilege('authenticated','public.project_risk_items','insert')
     or has_table_privilege('authenticated','public.project_risk_resolutions','insert')
     or has_table_privilege('authenticated','public.project_decision_records','insert') then
    raise exception 'R2 GOV ASSERTION FAILED: authenticated can bypass governance commands';
  end if;
  if has_table_privilege('anon','public.project_risk_items_read','select')
     or has_table_privilege('anon','public.portfolio_project_risks_read','select')
     or has_table_privilege('anon','public.portfolio_project_decisions_read','select') then
    raise exception 'R2 GOV ASSERTION FAILED: anon can read governance projections';
  end if;
  for proc_row in
    select proc.oid,proc.proname
    from pg_proc proc join pg_namespace n on n.oid=proc.pronamespace
    where n.nspname='public' and proc.prosecdef
      and proc.proname in ('record_project_risk','resolve_project_risk','record_project_decision')
  loop
    if has_function_privilege('public',proc_row.oid,'execute')
       or has_function_privilege('anon',proc_row.oid,'execute') then
      raise exception 'R2 GOV ASSERTION FAILED: % executable by PUBLIC/anon',proc_row.proname;
    end if;
    if not has_function_privilege('authenticated',proc_row.oid,'execute') then
      raise exception 'R2 GOV ASSERTION FAILED: % not executable by authenticated',proc_row.proname;
    end if;
  end loop;
end $$;

insert into auth.users(id) values
  ('e6000000-0000-4000-8000-0000000000a1'),
  ('e6000000-0000-4000-8000-0000000000a2'),
  ('e6000000-0000-4000-8000-0000000000a3')
on conflict(id) do nothing;
insert into public.organizations(id,name) values
  ('e6000000-0000-4000-8000-000000000001','منظمة R2 للحوكمة'),
  ('e6000000-0000-4000-8000-000000000002','منظمة R2 معزولة')
on conflict(id) do nothing;
insert into public.memberships(organization_id,user_id,role,status) values
  ('e6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-0000000000a1','OWNER','ACTIVE'),
  ('e6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-0000000000a2','MEMBER','ACTIVE'),
  ('e6000000-0000-4000-8000-000000000002','e6000000-0000-4000-8000-0000000000a3','OWNER','ACTIVE')
on conflict(organization_id,user_id) do update set role=excluded.role,status=excluded.status;

select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('e6000000-0000-4000-8000-000000000001','مشروع R2 للحوكمة','R2-GOV-001','اختبار قرارات ومخاطر','REAL_ESTATE')$$) as r2gov_project \gset
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_portfolio('e6000000-0000-4000-8000-000000000001','محفظة R2','اختبار roll-up للمخاطر والقرارات','e6000000-0000-4000-8000-0000000000a1','r2gov-portfolio-001')$$) as r2gov_portfolio \gset
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',format(
  $$select public.transition_investment_portfolio('e6000000-0000-4000-8000-000000000001',%L,'DRAFT','ACTIVE','جاهزة للاختبار','r2gov-portfolio-active')$$,:'r2gov_portfolio'));
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',format(
  $$select public.assign_project_to_portfolio('e6000000-0000-4000-8000-000000000001',%L,%L,'r2gov-assign-001')$$,:'r2gov_portfolio',:'r2gov_project'));

-- Active MEMBER can surface an operational risk; its owner must be an active
-- member in the same organization. Recording a risk has no financial effect.
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_project_risk('e6000000-0000-4000-8000-000000000001',%L,'تأخر توريد','قد يتأخر توريد مادة أساسية','HIGH','e6000000-0000-4000-8000-0000000000a2',current_date+7,'R2-RISK-SOURCE','r2gov-risk-001')$$,:'r2gov_project')) as r2gov_risk \gset

select 1/case when (
  select status='OPEN' and severity='HIGH' and owner_user_id='e6000000-0000-4000-8000-0000000000a2'
  from public.project_risk_items_read where risk_item_id=:'r2gov_risk'
) then 1 else 0 end as r2gov_risk_open;
select 1/case when exists(
  select 1 from public.portfolio_project_risks_read
  where portfolio_id=:'r2gov_portfolio' and project_id=:'r2gov_project' and risk_item_id=:'r2gov_risk'
) then 1 else 0 end as r2gov_risk_rolls_to_current_portfolio;

-- True replay is one effect; same key/different payload is rejected.
select 1/case when r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_project_risk('e6000000-0000-4000-8000-000000000001',%L,'تأخر توريد','قد يتأخر توريد مادة أساسية','HIGH','e6000000-0000-4000-8000-0000000000a2',current_date+7,'R2-RISK-SOURCE','r2gov-risk-001')$$,:'r2gov_project'))=:'r2gov_risk'
  then 1 else 0 end as r2gov_risk_replay;
select 1/case when r2gov_expect_raise('e6000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_project_risk('e6000000-0000-4000-8000-000000000001',%L,'تأخر توريد','محتوى مختلف','HIGH','e6000000-0000-4000-8000-0000000000a2',current_date+7,'R2-RISK-SOURCE','r2gov-risk-001')$$,:'r2gov_project'))
  then 1 else 0 end as r2gov_risk_payload_mismatch_rejected;

-- Cross-tenant projection and commands are denied.
select 1/case when r2gov_count_as('e6000000-0000-4000-8000-0000000000a3',format(
  $$select count(*) from public.project_risk_items_read where risk_item_id=%L$$,:'r2gov_risk'))=0
  then 1 else 0 end as r2gov_cross_tenant_risk_hidden;
select 1/case when r2gov_expect_raise('e6000000-0000-4000-8000-0000000000a3',format(
  $$select public.resolve_project_risk('e6000000-0000-4000-8000-000000000001',%L,'محاولة عدائية',null,'r2gov-hostile-resolve')$$,:'r2gov_risk'))
  then 1 else 0 end as r2gov_cross_tenant_resolve_denied;

-- Resolution is an OWNER-controlled append-only fact, not a rewrite.
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',format(
  $$select public.resolve_project_risk('e6000000-0000-4000-8000-000000000001',%L,'تم تثبيت موعد التوريد واعتماد البديل','R2-RISK-RESOLUTION','r2gov-resolve-001')$$,:'r2gov_risk')) as r2gov_resolution \gset
select 1/case when (
  select status='RESOLVED' and resolution_id=:'r2gov_resolution'
  from public.project_risk_items_read where risk_item_id=:'r2gov_risk'
) then 1 else 0 end as r2gov_risk_resolved;
select 1/case when r2gov_expect_raise('e6000000-0000-4000-8000-0000000000a1',format(
  $$select public.resolve_project_risk('e6000000-0000-4000-8000-000000000001',%L,'حل آخر',null,'r2gov-resolve-002')$$,:'r2gov_risk'))
  then 1 else 0 end as r2gov_second_resolution_rejected;

-- Material decision record is OWNER-only and immutable. It records evidence;
-- it creates no funding, entitlement, posting or cross-project effect.
select 1/case when r2gov_expect_raise('e6000000-0000-4000-8000-0000000000a2',format(
  $$select public.record_project_decision('e6000000-0000-4000-8000-000000000001',%L,'قرار اختبار','اعتماد الخطة البديلة','لتقليل خطر التأخير',current_date,'R2-DECISION-EVIDENCE','r2gov-decision-member')$$,:'r2gov_project'))
  then 1 else 0 end as r2gov_decision_owner_only;
select r2gov_run_uuid('e6000000-0000-4000-8000-0000000000a1',format(
  $$select public.record_project_decision('e6000000-0000-4000-8000-000000000001',%L,'قرار اختبار','اعتماد الخطة البديلة','لتقليل خطر التأخير',current_date,'R2-DECISION-EVIDENCE','r2gov-decision-001')$$,:'r2gov_project')) as r2gov_decision \gset
select 1/case when exists(
  select 1 from public.portfolio_project_decisions_read
  where portfolio_id=:'r2gov_portfolio' and project_id=:'r2gov_project' and decision_record_id=:'r2gov_decision'
) then 1 else 0 end as r2gov_decision_rolls_to_current_portfolio;
select 1/case when r2gov_count_as('e6000000-0000-4000-8000-0000000000a3',format(
  $$select count(*) from public.portfolio_project_decisions_read where decision_record_id=%L$$,:'r2gov_decision'))=0
  then 1 else 0 end as r2gov_cross_tenant_decision_hidden;

-- Browser direct DML remains unavailable.
do $$
begin
  perform set_config('request.jwt.claim.sub','e6000000-0000-4000-8000-0000000000a2',true);
  execute 'set role authenticated';
  begin
    insert into public.project_decision_records(
      organization_id,project_id,title,decision_text,decision_date,evidence_reference,
      recorded_by,idempotency_key,request_hash
    ) values(
      'e6000000-0000-4000-8000-000000000001',gen_random_uuid(),'غير مسموح','كتابة مباشرة',current_date,
      'BAD-EVIDENCE','e6000000-0000-4000-8000-0000000000a2','r2gov-direct',repeat('a',64));
    raise exception 'direct governance DML unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'R2 project governance records PASS' as result;
