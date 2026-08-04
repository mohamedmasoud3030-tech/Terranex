-- Roll back the Egypt-first Odoo manual journal bridge.

drop trigger if exists trg_odoo_mapping_release_journal_reversals on odoo_entity_mappings;
drop function if exists terranex_release_odoo_journal_reversals();
drop trigger if exists trg_journal_entries_odoo_outbox on journal_entries;
drop function if exists terranex_enqueue_odoo_manual_journal();

delete from odoo_entity_mappings where entity_type = 'journal_entry';
delete from odoo_sync_outbox where entity_type = 'journal_entry';

alter table odoo_sync_outbox drop constraint if exists odoo_sync_outbox_entity_type_check;
alter table odoo_sync_outbox add constraint odoo_sync_outbox_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice',
    'bank_account','sales_payment','purchase_payment'
  ));

alter table odoo_entity_mappings drop constraint if exists odoo_entity_mappings_entity_type_check;
alter table odoo_entity_mappings add constraint odoo_entity_mappings_entity_type_check
  check (entity_type in (
    'partner','project','sales_invoice','purchase_invoice',
    'bank_account','sales_payment','purchase_payment'
  ));

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
    'bank_account','sales_payment','purchase_payment'
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