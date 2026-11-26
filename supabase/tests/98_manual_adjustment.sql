-- Manual adjustment entry: security, balance, role restriction, idempotency, reversal.

create or replace function ma_run(p_user uuid,p_sql text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
exception when others then reset role; raise;
end $$;

create or replace function ma_expect_raise(p_user uuid,p_sql text) returns boolean language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',p_user::text,true);
  perform set_config('role','authenticated',false);
  execute p_sql;
  reset role;
  return false;
exception when others then reset role; return true;
end $$;

do $$
begin
  if has_function_privilege('anon','public.post_manual_adjustment(uuid,uuid,date,text,text,text,jsonb,text)','execute') then
    raise exception 'MA ASSERTION FAILED: anon can execute post_manual_adjustment';
  end if;
  if has_table_privilege('authenticated','public.manual_adjustments','insert') then
    raise exception 'MA ASSERTION FAILED: authenticated can insert manual_adjustments directly';
  end if;
end $$;

insert into auth.users(id) values
  ('ea000000-0000-4000-8000-0000000000a1'),
  ('ea000000-0000-4000-8000-0000000000a2'),
  ('ea000000-0000-4000-8000-0000000000a3') on conflict(id) do nothing;
insert into public.organizations(id,name) values
  ('ea000000-0000-4000-8000-000000000001','منظمة القيود اليدوية'),
  ('ea000000-0000-4000-8000-000000000002','منظمة معزولة') on conflict(id) do nothing;
insert into public.memberships(organization_id,user_id,role,status) values
  ('ea000000-0000-4000-8000-000000000001','ea000000-0000-4000-8000-0000000000a1','OWNER','ACTIVE'),
  ('ea000000-0000-4000-8000-000000000001','ea000000-0000-4000-8000-0000000000a2','MEMBER','ACTIVE'),
  ('ea000000-0000-4000-8000-000000000002','ea000000-0000-4000-8000-0000000000a3','OWNER','ACTIVE')
on conflict(organization_id,user_id) do update set role=excluded.role,status=excluded.status;

select ma_run('ea000000-0000-4000-8000-0000000000a1',
  $$select public.create_investment_project('ea000000-0000-4000-8000-000000000001','مشروع قيود يدوية','MA-001','اختبار','REAL_ESTATE')$$);
select id as ma_project from public.investment_projects
 where organization_id='ea000000-0000-4000-8000-000000000001' and name='مشروع قيود يدوية' \gset

-- Owner posts a balanced reclassification.
select ma_run('ea000000-0000-4000-8000-0000000000a1', format(
  $$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','إعادة تصنيف مصروف إلى أعمال تحت التطوير','MA-EVID-1',
    '[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":150000},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":150000}]'::jsonb,
    'ma-key-000001')$$, :'ma_project'));
select id as ma_id, journal_batch_id as ma_batch from public.manual_adjustments where idempotency_key='ma-key-000001' \gset

do $$
declare n int; d bigint; c bigint;
begin
  select count(*), sum(debit_minor_units), sum(credit_minor_units) into n, d, c
    from public.journal_lines where batch_id = (select journal_batch_id from public.manual_adjustments where idempotency_key='ma-key-000001');
  if n <> 2 or d <> 150000 or c <> 150000 then raise exception 'MA ASSERTION FAILED: lines not posted balanced (% % %)', n, d, c; end if;
  if (select source_type from public.journal_batches where id=(select journal_batch_id from public.manual_adjustments where idempotency_key='ma-key-000001')) <> 'MANUAL_ADJUSTMENT' then
    raise exception 'MA ASSERTION FAILED: wrong source type';
  end if;
  if not exists (select 1 from public.audit_events where event_type='MANUAL_ADJUSTMENT_POSTED') then
    raise exception 'MA ASSERTION FAILED: no audit event';
  end if;
end $$;

-- Idempotent replay returns the same id and posts nothing new.
select ma_run('ea000000-0000-4000-8000-0000000000a1', format(
  $$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','إعادة تصنيف مصروف إلى أعمال تحت التطوير','MA-EVID-1',
    '[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":150000},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":150000}]'::jsonb,
    'ma-key-000001')$$, :'ma_project'));
do $$ begin
  if (select count(*) from public.manual_adjustments where idempotency_key='ma-key-000001') <> 1 then
    raise exception 'MA ASSERTION FAILED: replay duplicated the entry';
  end if;
end $$;

-- Rejections: member, other tenant, unbalanced, forbidden role, payload mismatch, bad currency.
do $$
declare p uuid := (select id from public.investment_projects where name='مشروع قيود يدوية');
begin
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a2', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','قيد عضو غير مالك','MA-EVID-2','[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":100},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":100}]'::jsonb,'ma-key-000002')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: member could post'; end if;
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a3', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','قيد من منظمة أخرى','MA-EVID-3','[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":100},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":100}]'::jsonb,'ma-key-000003')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: other tenant could post'; end if;
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a1', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','قيد غير متوازن','MA-EVID-4','[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":100},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":90}]'::jsonb,'ma-key-000004')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: unbalanced entry accepted'; end if;
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a1', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','قيد على النقدية','MA-EVID-5','[{"account_role":"BANK_CASH","side":"DEBIT","amount_minor_units":100},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":100}]'::jsonb,'ma-key-000005')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: cash role accepted by hand'; end if;
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a1', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'EGP','نفس المفتاح بحمولة مختلفة','MA-EVID-1','[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":999},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":999}]'::jsonb,'ma-key-000001')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: payload mismatch accepted'; end if;
  if not ma_expect_raise('ea000000-0000-4000-8000-0000000000a1', format($q$select public.post_manual_adjustment('ea000000-0000-4000-8000-000000000001',%L,current_date,'USD','عملة مختلفة','MA-EVID-6','[{"account_role":"DEVELOPMENT_WIP","side":"DEBIT","amount_minor_units":100},{"account_role":"PROJECT_EXPENSE","side":"CREDIT","amount_minor_units":100}]'::jsonb,'ma-key-000006')$q$, p)) then
    raise exception 'MA ASSERTION FAILED: foreign currency accepted'; end if;
end $$;

-- The existing reversal command reverses it; ledger nets to zero.
select ma_run('ea000000-0000-4000-8000-0000000000a1', format(
  $$select public.reverse_journal_batch('ea000000-0000-4000-8000-000000000001',%L,'تصحيح قيد يدوي','ma-reverse-0001')$$, :'ma_batch'));
do $$
declare d bigint; c bigint;
begin
  select sum(debit_minor_units), sum(credit_minor_units) into d, c from public.journal_lines
   where batch_id in (select id from public.journal_batches where id = (select journal_batch_id from public.manual_adjustments where idempotency_key='ma-key-000001') or reversal_of_batch_id = (select journal_batch_id from public.manual_adjustments where idempotency_key='ma-key-000001'));
  if d <> c or d <> 300000 then raise exception 'MA ASSERTION FAILED: reversal did not mirror the entry (% %)', d, c; end if;
end $$;
