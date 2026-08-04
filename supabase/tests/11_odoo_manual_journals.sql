-- Odoo manual journal bridge: explicit posted vouchers only, reversal as a
-- separate posted voucher, tenant isolation, idempotency and stable mappings.
\set ON_ERROR_STOP on

begin;
set local role postgres;

truncate table
  odoo_entity_mappings, odoo_sync_outbox,
  journal_operations, journal_entry_lines, journal_entries,
  bank_transactions, bank_accounts, owner_sequences cascade;

delete from auth.users where id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb93'
);
insert into auth.users(id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93', 'alice-journal@terranex.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb93', 'bob-journal@terranex.test');

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93';

do $$
declare
  v_entry uuid;
  v_reversal uuid;
  v_draft uuid;
  v_count integer;
begin
  v_entry := create_journal_entry_atomic(
    '20000000-0000-4000-8000-000000000093',
    '2026-08-04',
    'إثبات مصروف تأسيس',
    'Formation expense',
    'EGP', 1, 'سند يدوي مصري',
    jsonb_build_array(
      jsonb_build_object(
        'account_code','610001','description_ar','مصروف تأسيس','debit',1000,'credit',0
      ),
      jsonb_build_object(
        'account_code','210001','description_ar','دائنون','debit',0,'credit',1000
      )
    )
  );

  select count(*) into v_count
    from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'journal_entry' and entity_id = v_entry;
  if v_count <> 0 then raise exception 'FAIL draft voucher entered Odoo outbox'; end if;

  perform post_journal_entry('20000000-0000-4000-8000-000000000094', v_entry);
  select count(*) into v_count
    from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'journal_entry'
     and entity_id = v_entry and status = 'pending';
  if v_count <> 1 then raise exception 'FAIL posted voucher event count=%', v_count; end if;

  -- Exact replay is idempotent and does not duplicate the event.
  perform post_journal_entry('20000000-0000-4000-8000-000000000094', v_entry);
  select count(*) into v_count
    from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'journal_entry' and entity_id = v_entry;
  if v_count <> 1 then raise exception 'FAIL replay duplicated posted voucher event'; end if;

  v_reversal := void_journal_entry(
    '20000000-0000-4000-8000-000000000095',
    v_entry,
    'تصحيح القيد'
  );
  if v_reversal = v_entry then raise exception 'FAIL posted voucher did not create a reversal'; end if;
  if (select status from journal_entries where id = v_entry) <> 'reversed' then
    raise exception 'FAIL original voucher was not marked reversed';
  end if;
  if (select status from journal_entries where id = v_reversal) <> 'posted' then
    raise exception 'FAIL reversal voucher was not posted';
  end if;
  if (select reversal_of_entry_id from journal_entries where id = v_reversal) <> v_entry then
    raise exception 'FAIL reversal does not reference original';
  end if;

  select count(*) into v_count
    from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'journal_entry'
     and entity_id in (v_entry, v_reversal) and status = 'pending';
  if v_count <> 2 then raise exception 'FAIL original/reversal outbox count=%', v_count; end if;

  if (select available_at from odoo_sync_outbox
       where owner_id = auth.uid() and entity_type = 'journal_entry' and entity_id = v_reversal)
       <> 'infinity'::timestamptz then
    raise exception 'FAIL reversal was not held until original mapping';
  end if;

  -- Voiding a draft is not an accounting event.
  v_draft := create_journal_entry_atomic(
    '20000000-0000-4000-8000-000000000096',
    '2026-08-04', 'مسودة ملغاة', null, 'EGP', 1, null,
    jsonb_build_array(
      jsonb_build_object('account_code','610001','debit',50,'credit',0),
      jsonb_build_object('account_code','210001','debit',0,'credit',50)
    )
  );
  perform void_journal_entry(
    '20000000-0000-4000-8000-000000000097',
    v_draft,
    'لم يتم الاعتماد'
  );
  select count(*) into v_count
    from odoo_sync_outbox
   where owner_id = auth.uid() and entity_type = 'journal_entry' and entity_id = v_draft;
  if v_count <> 0 then raise exception 'FAIL void draft produced Odoo accounting event'; end if;
end $$;

-- Bob cannot observe Alice's vouchers or outbox events.
set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb93';
do $$
declare v_count integer;
begin
  select count(*) into v_count from journal_entries;
  if v_count <> 0 then raise exception 'FAIL Bob sees Alice journal vouchers'; end if;
  select count(*) into v_count from odoo_sync_outbox where entity_type = 'journal_entry';
  if v_count <> 0 then raise exception 'FAIL Bob sees Alice Odoo journal events'; end if;
end $$;

-- Worker completion records Odoo ids without mutating immutable voucher lines.
set local role postgres;
do $$
declare
  v_entry uuid;
  v_reversal uuid;
  v_original_event uuid;
  v_reversal_event uuid;
  v_line_count integer;
  v_count integer;
begin
  select id, reversed_by_entry_id into v_entry, v_reversal
    from journal_entries
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and status = 'reversed'
   limit 1;

  select count(*) into v_line_count
    from journal_entry_lines
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and entry_id in (v_entry, v_reversal);

  select id into v_original_event from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and entity_type = 'journal_entry' and entity_id = v_entry;
  select id into v_reversal_event from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and entity_type = 'journal_entry' and entity_id = v_reversal;

  if (select available_at from odoo_sync_outbox where id = v_reversal_event)
       <> 'infinity'::timestamptz then
    raise exception 'FAIL reversal was available before original completion';
  end if;

  perform complete_odoo_sync(v_original_event, 'account.move', 9301, '{"test":true}'::jsonb);

  if (select available_at from odoo_sync_outbox where id = v_reversal_event)
       = 'infinity'::timestamptz then
    raise exception 'FAIL original mapping did not release reversal';
  end if;

  perform complete_odoo_sync(v_reversal_event, 'account.move', 9302, '{"test":true}'::jsonb);

  if (select count(*) from journal_entry_lines
       where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
         and entry_id in (v_entry, v_reversal)) <> v_line_count then
    raise exception 'FAIL Odoo completion mutated immutable journal lines';
  end if;

  select count(*) into v_count from odoo_entity_mappings
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and entity_type = 'journal_entry'
     and ((entity_id = v_entry and odoo_record_id = 9301)
       or (entity_id = v_reversal and odoo_record_id = 9302));
  if v_count <> 2 then raise exception 'FAIL stable journal mappings count=%', v_count; end if;

  select count(*) into v_count from odoo_sync_outbox
   where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa93'
     and entity_type = 'journal_entry' and status = 'synced';
  if v_count <> 2 then raise exception 'FAIL journal events not completed'; end if;
end $$;

rollback;
\echo '=== ODOO MANUAL JOURNALS SUITE: ALL CHECKS PASSED ==='
