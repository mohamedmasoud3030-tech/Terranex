-- Secure Odoo bridge: Egypt defaults, transactional enqueue, tenant isolation,
-- claim/complete mapping and browser write denial.
\set ON_ERROR_STOP on

begin;
set local role postgres;

truncate table odoo_entity_mappings, odoo_sync_outbox, partners, projects cascade;
delete from auth.users where id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa91',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb91'
);
insert into auth.users(id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa91', 'alice-odoo@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb91', 'bob-odoo@terranex.test');

-- Egypt-first database defaults are authoritative for new companies.
do $$
declare v_country text; v_currency text;
begin
  select column_default into v_country from information_schema.columns
   where table_schema='public' and table_name='company_settings' and column_name='country';
  select column_default into v_currency from information_schema.columns
   where table_schema='public' and table_name='company_settings' and column_name='base_currency';
  if v_country not like '%EG%' or v_currency not like '%EGP%' then
    raise exception 'FAIL Egypt defaults: country=% currency=%', v_country, v_currency;
  end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa91';

insert into partners(id, name_ar, category, counterparty_role)
values ('11111111-1111-4111-8111-111111111191', 'عميل أليس', 'counterparty', 'client');

-- The partner write and outbox enqueue are in the same transaction.
do $$
declare v_event uuid; v_event_again uuid; v_count integer;
begin
  select id into v_event from odoo_sync_outbox
   where owner_id=auth.uid() and entity_type='partner'
     and entity_id='11111111-1111-4111-8111-111111111191' and status='pending';
  if v_event is null then raise exception 'FAIL partner trigger did not enqueue'; end if;

  v_event_again := enqueue_odoo_sync(
    'partner', '11111111-1111-4111-8111-111111111191', 'upsert');
  select count(*) into v_count from odoo_sync_outbox
   where owner_id=auth.uid() and entity_type='partner'
     and entity_id='11111111-1111-4111-8111-111111111191' and status='pending';
  if v_event_again <> v_event or v_count <> 1 then
    raise exception 'FAIL pending event coalescing: first=% second=% count=%', v_event, v_event_again, v_count;
  end if;

  begin
    insert into odoo_sync_outbox(owner_id, entity_type, entity_id)
    values (auth.uid(), 'partner', gen_random_uuid());
    raise exception 'FAIL authenticated direct outbox insert accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

-- A second tenant sees no queue/mapping rows and cannot enqueue Alice's entity.
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb91';
do $$
declare v_count integer;
begin
  select count(*) into v_count from odoo_sync_outbox;
  if v_count <> 0 then raise exception 'FAIL Bob sees Alice outbox rows'; end if;
  select count(*) into v_count from odoo_entity_mappings;
  if v_count <> 0 then raise exception 'FAIL Bob sees Alice mappings'; end if;
  begin
    perform enqueue_odoo_sync('partner', '11111111-1111-4111-8111-111111111191', 'upsert');
    raise exception 'FAIL Bob enqueued Alice partner';
  exception when others then
    if SQLERRM like 'FAIL%' then raise; end if;
  end;
end $$;

-- Simulate the Edge Function service worker.
set local role postgres;
do $$
declare v_event odoo_sync_outbox%rowtype; v_count integer;
begin
  select * into v_event from claim_odoo_sync_batch(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa91', 10, 'sql-test-worker') limit 1;
  if v_event.id is null or v_event.status <> 'processing' or v_event.attempt_count <> 1 then
    raise exception 'FAIL worker claim: %', row_to_json(v_event);
  end if;

  perform complete_odoo_sync(v_event.id, 'res.partner', 9091, jsonb_build_object('test', true));
  if (select status from odoo_sync_outbox where id=v_event.id) <> 'synced' then
    raise exception 'FAIL worker completion status';
  end if;
  select count(*) into v_count from odoo_entity_mappings
   where owner_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa91'
     and entity_type='partner' and entity_id=v_event.entity_id
     and odoo_model='res.partner' and odoo_record_id=9091;
  if v_count <> 1 then raise exception 'FAIL stable Odoo mapping'; end if;
  if (select odoo_res_id from partners where id=v_event.entity_id) <> 9091 then
    raise exception 'FAIL source odoo_res_id update';
  end if;
  if exists (select 1 from odoo_sync_outbox where status='pending' and entity_id=v_event.entity_id) then
    raise exception 'FAIL mapping-only source update requeued event';
  end if;
end $$;

rollback;
\echo '=== ODOO EGYPT BRIDGE SUITE: ALL CHECKS PASSED ==='
