-- Roll back the Egypt-first Odoo payments/banking bridge extension.

drop trigger if exists trg_purchase_payments_odoo_outbox on purchase_invoice_payments;
drop trigger if exists trg_invoice_payments_odoo_outbox on invoice_payments;
drop trigger if exists trg_bank_accounts_odoo_outbox on bank_accounts;

drop function if exists terranex_enqueue_odoo_purchase_payment();
drop function if exists terranex_enqueue_odoo_sales_payment();
drop function if exists terranex_enqueue_odoo_bank_account();

-- New vocabulary rows must be removed before restoring the narrower checks.
delete from odoo_entity_mappings
 where entity_type in ('bank_account','sales_payment','purchase_payment');
delete from odoo_sync_outbox
 where entity_type in ('bank_account','sales_payment','purchase_payment');

alter table odoo_sync_outbox drop constraint if exists odoo_sync_outbox_entity_type_check;
alter table odoo_sync_outbox add constraint odoo_sync_outbox_entity_type_check
  check (entity_type in ('partner','project','sales_invoice','purchase_invoice'));

alter table odoo_entity_mappings drop constraint if exists odoo_entity_mappings_entity_type_check;
alter table odoo_entity_mappings add constraint odoo_entity_mappings_entity_type_check
  check (entity_type in ('partner','project','sales_invoice','purchase_invoice'));

create or replace function terranex_odoo_entity_owner(
  p_entity_type text,
  p_entity_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  case p_entity_type
    when 'partner' then
      select owner_id into v_owner from partners where id = p_entity_id;
    when 'project' then
      select owner_id into v_owner from projects where id = p_entity_id;
    when 'sales_invoice' then
      select owner_id into v_owner from sales_invoices where id = p_entity_id;
    when 'purchase_invoice' then
      select owner_id into v_owner from purchase_invoices where id = p_entity_id;
    else
      raise exception 'نوع كيان Odoo غير مدعوم: %', p_entity_type;
  end case;
  if v_owner is null then
    raise exception 'الكيان المطلوب للمزامنة غير موجود';
  end if;
  return v_owner;
end;
$$;

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
  if p_entity_type not in ('partner','project','sales_invoice','purchase_invoice') then
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

create or replace function complete_odoo_sync(
  p_event_id uuid,
  p_odoo_model text,
  p_odoo_record_id integer,
  p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event odoo_sync_outbox%rowtype;
begin
  select * into v_event from odoo_sync_outbox where id = p_event_id for update;
  if not found then raise exception 'حدث المزامنة غير موجود'; end if;

  update odoo_sync_outbox
     set status = 'synced',
         odoo_model = p_odoo_model,
         odoo_record_id = p_odoo_record_id,
         synced_at = now(),
         locked_at = null,
         locked_by = null,
         last_error = null,
         updated_at = now()
   where id = p_event_id;

  insert into odoo_entity_mappings (
    owner_id, entity_type, entity_id, odoo_model, odoo_record_id, metadata, last_synced_at
  ) values (
    v_event.owner_id, v_event.entity_type, v_event.entity_id,
    p_odoo_model, p_odoo_record_id, coalesce(p_metadata, '{}'::jsonb), now()
  )
  on conflict (owner_id, entity_type, entity_id) do update set
    odoo_model = excluded.odoo_model,
    odoo_record_id = excluded.odoo_record_id,
    metadata = excluded.metadata,
    last_synced_at = now(),
    updated_at = now();

  case v_event.entity_type
    when 'partner' then update partners set odoo_res_id = p_odoo_record_id where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'project' then update projects set odoo_res_id = p_odoo_record_id where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'sales_invoice' then update sales_invoices set odoo_res_id = p_odoo_record_id where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'purchase_invoice' then update purchase_invoices set odoo_res_id = p_odoo_record_id where id = v_event.entity_id and owner_id = v_event.owner_id;
    else null;
  end case;
end;
$$;

revoke all on function terranex_odoo_entity_owner(text, uuid) from public, anon, authenticated;
revoke all on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function complete_odoo_sync(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function terranex_odoo_entity_owner(text, uuid) to service_role;
grant execute on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) to service_role;
grant execute on function complete_odoo_sync(uuid, text, integer, jsonb) to service_role;
