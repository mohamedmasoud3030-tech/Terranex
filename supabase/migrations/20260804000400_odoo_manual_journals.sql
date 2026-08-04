-- Terranex -> Odoo 18 manual journal bridge (Egypt-first)
-- Only explicit, persisted manual vouchers are synchronized. Derived reporting
-- projections and invoice/payment movements remain outside this event type to
-- prevent duplicate accounting.

-- ---------------------------------------------------------------------------
-- 1) Extend the stable Odoo entity vocabulary.
-- ---------------------------------------------------------------------------
alter table odoo_sync_outbox drop constraint if exists odoo_sync_outbox_entity_type_check;
alter table odoo_sync_outbox add constraint odoo_sync_outbox_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice',
    'bank_account','sales_payment','purchase_payment','journal_entry'
  ));

alter table odoo_entity_mappings drop constraint if exists odoo_entity_mappings_entity_type_check;
alter table odoo_entity_mappings add constraint odoo_entity_mappings_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice',
    'bank_account','sales_payment','purchase_payment','journal_entry'
  ));

-- ---------------------------------------------------------------------------
-- 2) Allow the server-only queue writer to accept manual vouchers.
-- ---------------------------------------------------------------------------
create or replace function terranex_queue_odoo_event(
  p_owner_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_operation text default 'upsert',
  p_payload jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_owner_id is null or p_entity_id is null then
    raise exception 'owner_id و entity_id مطلوبان للمزامنة';
  end if;
  if p_entity_type not in (
    'partner','project','sales_invoice','purchase_invoice',
    'bank_account','sales_payment','purchase_payment','journal_entry'
  ) then
    raise exception 'نوع كيان Odoo غير مدعوم: %', p_entity_type;
  end if;
  if p_operation not in ('upsert','void') then
    raise exception 'عملية Odoo غير مدعومة: %', p_operation;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_owner_id::text || ':' || p_entity_type || ':' || p_entity_id::text, 0)
  );

  update odoo_sync_outbox
     set operation = p_operation,
         payload = coalesce(p_payload, '{}'::jsonb),
         status = 'pending',
         available_at = now(),
         locked_at = null,
         locked_by = null,
         last_error = null,
         updated_at = now()
   where owner_id = p_owner_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     and status in ('pending','failed')
  returning id into v_id;

  if v_id is null then
    insert into odoo_sync_outbox (
      owner_id, entity_type, entity_id, operation, payload
    ) values (
      p_owner_id, p_entity_type, p_entity_id, p_operation,
      coalesce(p_payload, '{}'::jsonb)
    ) returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3) Queue exactly the accounting event: draft -> posted, or insertion of an
-- already-posted reversal voucher. Changing the original to `reversed` does
-- not cancel its Odoo move; the separately posted reversal offsets it.
-- ---------------------------------------------------------------------------
create or replace function terranex_enqueue_odoo_manual_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'posted' then
    if tg_op = 'INSERT' then
      perform terranex_queue_odoo_event(
        new.owner_id,
        'journal_entry',
        new.id,
        'upsert',
        jsonb_build_object(
          'source_table', 'journal_entries',
          'entry_number', new.entry_number,
          'entry_date', new.entry_date,
          'currency', new.currency,
          'reversal_of_entry_id', new.reversal_of_entry_id,
          'source_updated_at', new.updated_at
        )
      );
    elsif old.status is distinct from 'posted' then
      perform terranex_queue_odoo_event(
        new.owner_id,
        'journal_entry',
        new.id,
        'upsert',
        jsonb_build_object(
          'source_table', 'journal_entries',
          'entry_number', new.entry_number,
          'entry_date', new.entry_date,
          'currency', new.currency,
          'reversal_of_entry_id', new.reversal_of_entry_id,
          'source_updated_at', new.updated_at
        )
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function terranex_enqueue_odoo_manual_journal()
  from public, anon, authenticated;

drop trigger if exists trg_journal_entries_odoo_outbox on journal_entries;
create trigger trg_journal_entries_odoo_outbox
  after insert or update of status on journal_entries
  for each row execute function terranex_enqueue_odoo_manual_journal();

-- Historical vouchers that were posted and later reversed still need their
-- original Odoo move; the explicit posted reversal then offsets that move.
select terranex_queue_odoo_event(
  j.owner_id,
  'journal_entry',
  j.id,
  'upsert',
  jsonb_build_object(
    'backfill', true,
    'entry_number', j.entry_number,
    'status', j.status,
    'reversal_of_entry_id', j.reversal_of_entry_id
  )
)
from journal_entries j
where j.status in ('posted','reversed')
  and not exists (
    select 1
      from odoo_entity_mappings m
     where m.owner_id = j.owner_id
       and m.entity_type = 'journal_entry'
       and m.entity_id = j.id
  );