-- Terranex -> Odoo 18 payments and banking bridge (Egypt-first)
-- Extends the durable outbox created in 20260804000100 without duplicating
-- Terranex bank movements. Invoice RPCs remain the authoritative atomic write
-- boundary; their immutable payment rows enqueue Odoo work in the same tx.

-- ---------------------------------------------------------------------------
-- 1) Extend the Odoo entity vocabulary.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 2) Owner lookup and queue writer now understand bank journals and payments.
-- ---------------------------------------------------------------------------
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
    when 'bank_account' then
      select owner_id into v_owner from bank_accounts where id = p_entity_id;
    when 'sales_payment' then
      select owner_id into v_owner from invoice_payments where id = p_entity_id;
    when 'purchase_payment' then
      select owner_id into v_owner from purchase_invoice_payments where id = p_entity_id;
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

revoke all on function terranex_odoo_entity_owner(text, uuid) from public, anon, authenticated;
revoke all on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function terranex_odoo_entity_owner(text, uuid) to service_role;
grant execute on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 3) Transactional enqueue from the authoritative source rows.
-- ---------------------------------------------------------------------------
create or replace function terranex_enqueue_odoo_bank_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'updated_at' - 'odoo_res_id')
         = (to_jsonb(old) - 'updated_at' - 'odoo_res_id') then
    return new;
  end if;

  perform terranex_queue_odoo_event(
    new.owner_id,
    'bank_account',
    new.id,
    'upsert',
    jsonb_build_object(
      'source_table', 'bank_accounts',
      'account_type', new.account_type,
      'currency', new.currency,
      'is_archived', new.is_archived,
      'source_updated_at', coalesce(new.updated_at, new.created_at)
    )
  );
  return new;
end;
$$;

create or replace function terranex_enqueue_odoo_sales_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_reversed then return new; end if;
  perform terranex_queue_odoo_event(
    new.owner_id,
    'sales_payment',
    new.id,
    'upsert',
    jsonb_build_object(
      'source_table', 'invoice_payments',
      'invoice_id', new.invoice_id,
      'bank_account_id', new.bank_account_id,
      'payment_date', new.payment_date,
      'amount', new.amount,
      'currency', new.currency
    )
  );
  return new;
end;
$$;

create or replace function terranex_enqueue_odoo_purchase_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform terranex_queue_odoo_event(
    new.owner_id,
    'purchase_payment',
    new.id,
    'upsert',
    jsonb_build_object(
      'source_table', 'purchase_invoice_payments',
      'invoice_id', new.invoice_id,
      'bank_account_id', new.bank_account_id,
      'payment_date', new.payment_date,
      'amount', new.amount,
      'currency', new.currency
    )
  );
  return new;
end;
$$;

revoke all on function terranex_enqueue_odoo_bank_account() from public, anon, authenticated;
revoke all on function terranex_enqueue_odoo_sales_payment() from public, anon, authenticated;
revoke all on function terranex_enqueue_odoo_purchase_payment() from public, anon, authenticated;

drop trigger if exists trg_bank_accounts_odoo_outbox on bank_accounts;
create trigger trg_bank_accounts_odoo_outbox
  after insert or update on bank_accounts
  for each row execute function terranex_enqueue_odoo_bank_account();

drop trigger if exists trg_invoice_payments_odoo_outbox on invoice_payments;
create trigger trg_invoice_payments_odoo_outbox
  after insert on invoice_payments
  for each row execute function terranex_enqueue_odoo_sales_payment();

drop trigger if exists trg_purchase_payments_odoo_outbox on purchase_invoice_payments;
create trigger trg_purchase_payments_odoo_outbox
  after insert on purchase_invoice_payments
  for each row execute function terranex_enqueue_odoo_purchase_payment();

-- Existing rows are queued only when they do not already have a stable mapping;
-- this keeps migration replay idempotent without mutating immutable payment rows.
select terranex_queue_odoo_event(
  b.owner_id, 'bank_account', b.id, 'upsert', jsonb_build_object('backfill', true)
)
from bank_accounts b
where not exists (
  select 1 from odoo_entity_mappings m
   where m.owner_id = b.owner_id and m.entity_type = 'bank_account' and m.entity_id = b.id
);

select terranex_queue_odoo_event(
  p.owner_id, 'sales_payment', p.id, 'upsert',
  jsonb_build_object('backfill', true, 'invoice_id', p.invoice_id)
)
from invoice_payments p
where not p.is_reversed
  and not exists (
    select 1 from odoo_entity_mappings m
     where m.owner_id = p.owner_id and m.entity_type = 'sales_payment' and m.entity_id = p.id
  );

select terranex_queue_odoo_event(
  p.owner_id, 'purchase_payment', p.id, 'upsert',
  jsonb_build_object('backfill', true, 'invoice_id', p.invoice_id)
)
from purchase_invoice_payments p
where not exists (
  select 1 from odoo_entity_mappings m
   where m.owner_id = p.owner_id and m.entity_type = 'purchase_payment' and m.entity_id = p.id
);

-- ---------------------------------------------------------------------------
-- 4) Completion updates mutable source records only. Payment audit rows remain
-- immutable; their Odoo ids live in odoo_entity_mappings.
-- ---------------------------------------------------------------------------
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
    when 'partner' then
      update partners set odoo_res_id = p_odoo_record_id
       where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'project' then
      update projects set odoo_res_id = p_odoo_record_id
       where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'sales_invoice' then
      update sales_invoices set odoo_res_id = p_odoo_record_id
       where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'purchase_invoice' then
      update purchase_invoices set odoo_res_id = p_odoo_record_id
       where id = v_event.entity_id and owner_id = v_event.owner_id;
    when 'bank_account' then
      update bank_accounts set odoo_res_id = p_odoo_record_id
       where id = v_event.entity_id and owner_id = v_event.owner_id;
    else null;
  end case;
end;
$$;

revoke all on function complete_odoo_sync(uuid, text, integer, jsonb) from public, anon, authenticated;
grant execute on function complete_odoo_sync(uuid, text, integer, jsonb) to service_role;
