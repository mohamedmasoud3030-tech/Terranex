-- Terranex -> Odoo 18 secure accounting bridge (Egypt-first)
-- Keeps operational/investor data in Terranex while Odoo owns the official
-- accounting ledger, Egyptian localization and ETA e-invoicing workflow.
-- Date: 2026-08-04

-- ---------------------------------------------------------------------------
-- 1) Egypt-first defaults for newly-created companies and financial records.
-- Existing tenant values are deliberately preserved.
-- ---------------------------------------------------------------------------
alter table company_settings alter column country set default 'EG';
alter table company_settings alter column base_currency set default 'EGP';
alter table company_settings add column if not exists odoo_company_id integer;
alter table company_settings add column if not exists odoo_localization text not null default 'l10n_eg';
alter table company_settings add column if not exists eta_branch_code text not null default '0';

alter table bank_accounts alter column currency set default 'EGP';
alter table sales_invoices alter column currency set default 'EGP';
alter table purchase_invoices alter column currency set default 'EGP';
alter table inventory_items alter column currency set default 'EGP';
alter table inventory_movements alter column currency set default 'EGP';
alter table journal_entries alter column currency set default 'EGP';

-- ---------------------------------------------------------------------------
-- 2) Transactional outbox and stable Terranex <-> Odoo mappings.
-- Browser code never sees an Odoo API key. Domain table triggers enqueue work
-- in the same Postgres transaction as the business write.
-- ---------------------------------------------------------------------------
create table if not exists odoo_sync_outbox (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('partner','project','sales_invoice','purchase_invoice')),
  entity_id uuid not null,
  operation text not null default 'upsert' check (operation in ('upsert','void')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','processing','synced','failed','dead_letter')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  last_error text,
  odoo_model text,
  odoo_record_id integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz,
  unique (id, owner_id)
);

create table if not exists odoo_entity_mappings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('partner','project','sales_invoice','purchase_invoice')),
  entity_id uuid not null,
  odoo_model text not null,
  odoo_record_id integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_synced_at timestamptz not null default now(),
  unique (id, owner_id),
  unique (owner_id, entity_type, entity_id),
  unique (owner_id, odoo_model, odoo_record_id)
);

create index if not exists odoo_sync_outbox_ready_idx
  on odoo_sync_outbox(owner_id, status, available_at, created_at);
create unique index if not exists odoo_sync_outbox_pending_entity_idx
  on odoo_sync_outbox(owner_id, entity_type, entity_id, operation)
  where status = 'pending';
create index if not exists odoo_entity_mappings_entity_idx
  on odoo_entity_mappings(owner_id, entity_type, entity_id);

alter table odoo_sync_outbox enable row level security;
alter table odoo_sync_outbox force row level security;
alter table odoo_entity_mappings enable row level security;
alter table odoo_entity_mappings force row level security;

drop policy if exists odoo_sync_outbox_owner_select on odoo_sync_outbox;
drop policy if exists odoo_entity_mappings_owner_select on odoo_entity_mappings;
create policy odoo_sync_outbox_owner_select on odoo_sync_outbox
  for select to authenticated using (owner_id = auth.uid());
create policy odoo_entity_mappings_owner_select on odoo_entity_mappings
  for select to authenticated using (owner_id = auth.uid());

revoke all on odoo_sync_outbox, odoo_entity_mappings from anon, authenticated;
grant select on odoo_sync_outbox, odoo_entity_mappings to authenticated;
grant select, insert, update, delete on odoo_sync_outbox, odoo_entity_mappings to service_role;

-- ---------------------------------------------------------------------------
-- 3) Owner lookup and internal queue writer.
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
      p_owner_id, p_entity_type, p_entity_id, p_operation, coalesce(p_payload, '{}'::jsonb)
    ) returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function terranex_odoo_entity_owner(text, uuid) from public, anon, authenticated;
revoke all on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function terranex_odoo_entity_owner(text, uuid) to service_role;
grant execute on function terranex_queue_odoo_event(uuid, text, uuid, text, jsonb) to service_role;

-- Authenticated callers may explicitly requeue their own entity, but cannot
-- supply or spoof owner_id.
create or replace function enqueue_odoo_sync(
  p_entity_type text,
  p_entity_id uuid,
  p_operation text default 'upsert'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
  v_actual_owner uuid;
begin
  if v_owner is null then raise exception 'يجب تسجيل الدخول'; end if;
  v_actual_owner := terranex_odoo_entity_owner(p_entity_type, p_entity_id);
  if v_actual_owner <> v_owner then
    raise exception 'لا تملك صلاحية مزامنة هذا السجل';
  end if;
  return terranex_queue_odoo_event(
    v_owner,
    p_entity_type,
    p_entity_id,
    p_operation,
    jsonb_build_object('requested_by', v_owner, 'requested_at', now())
  );
end;
$$;
revoke all on function enqueue_odoo_sync(text, uuid, text) from public, anon;
grant execute on function enqueue_odoo_sync(text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Trigger-based transactional enqueue.
-- ---------------------------------------------------------------------------
create or replace function terranex_enqueue_odoo_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_type text;
  v_operation text := 'upsert';
  v_status text;
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'updated_at' - 'odoo_res_id')
         = (to_jsonb(old) - 'updated_at' - 'odoo_res_id') then
    return new;
  end if;

  v_entity_type := case tg_table_name
    when 'partners' then 'partner'
    when 'projects' then 'project'
    when 'sales_invoices' then 'sales_invoice'
    when 'purchase_invoices' then 'purchase_invoice'
    else null
  end;
  if v_entity_type is null then return new; end if;

  v_status := to_jsonb(new)->>'status';
  if v_entity_type in ('sales_invoice','purchase_invoice') and v_status = 'draft' then
    return new;
  end if;
  if v_entity_type in ('sales_invoice','purchase_invoice') and v_status = 'void' then
    v_operation := 'void';
  end if;

  perform terranex_queue_odoo_event(
    new.owner_id,
    v_entity_type,
    new.id,
    v_operation,
    jsonb_build_object(
      'source_table', tg_table_name,
      'source_status', v_status,
      'source_updated_at', coalesce(to_jsonb(new)->>'updated_at', to_jsonb(new)->>'created_at')
    )
  );
  return new;
end;
$$;
revoke all on function terranex_enqueue_odoo_row() from public, anon, authenticated;

drop trigger if exists trg_partners_odoo_outbox on partners;
create trigger trg_partners_odoo_outbox
  after insert or update on partners
  for each row execute function terranex_enqueue_odoo_row();

drop trigger if exists trg_projects_odoo_outbox on projects;
create trigger trg_projects_odoo_outbox
  after insert or update on projects
  for each row execute function terranex_enqueue_odoo_row();

drop trigger if exists trg_sales_invoices_odoo_outbox on sales_invoices;
create trigger trg_sales_invoices_odoo_outbox
  after insert or update on sales_invoices
  for each row execute function terranex_enqueue_odoo_row();

drop trigger if exists trg_purchase_invoices_odoo_outbox on purchase_invoices;
create trigger trg_purchase_invoices_odoo_outbox
  after insert or update on purchase_invoices
  for each row execute function terranex_enqueue_odoo_row();

-- Queue existing unsynced records once when this migration first lands.
select terranex_queue_odoo_event(owner_id, 'partner', id, 'upsert', jsonb_build_object('backfill', true))
  from partners where odoo_res_id is null;
select terranex_queue_odoo_event(owner_id, 'project', id, 'upsert', jsonb_build_object('backfill', true))
  from projects where odoo_res_id is null;
select terranex_queue_odoo_event(owner_id, 'sales_invoice', id,
         case when status = 'void' then 'void' else 'upsert' end,
         jsonb_build_object('backfill', true, 'source_status', status))
  from sales_invoices where odoo_res_id is null and status <> 'draft';
select terranex_queue_odoo_event(owner_id, 'purchase_invoice', id,
         case when status = 'void' then 'void' else 'upsert' end,
         jsonb_build_object('backfill', true, 'source_status', status))
  from purchase_invoices where odoo_res_id is null and status <> 'draft';

-- ---------------------------------------------------------------------------
-- 5) Server worker RPCs. Only service_role can claim/complete/fail events.
-- Edge Functions pass the authenticated owner_id, so one user cannot drain
-- another tenant's queue.
-- ---------------------------------------------------------------------------
create or replace function claim_odoo_sync_batch(
  p_owner_id uuid,
  p_limit integer default 20,
  p_worker_id text default 'edge-function'
) returns setof odoo_sync_outbox
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with picked as (
    select id
      from odoo_sync_outbox
     where owner_id = p_owner_id
       and status in ('pending','failed')
       and available_at <= now()
     order by created_at
     for update skip locked
     limit greatest(1, least(coalesce(p_limit, 20), 100))
  )
  update odoo_sync_outbox o
     set status = 'processing',
         attempt_count = o.attempt_count + 1,
         locked_at = now(),
         locked_by = coalesce(p_worker_id, 'edge-function'),
         updated_at = now()
    from picked
   where o.id = picked.id
  returning o.*;
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

create or replace function fail_odoo_sync(
  p_event_id uuid,
  p_error text,
  p_retry_seconds integer default 60
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update odoo_sync_outbox
     set status = case when attempt_count >= 10 then 'dead_letter' else 'failed' end,
         available_at = now() + make_interval(secs => greatest(5, coalesce(p_retry_seconds, 60))),
         locked_at = null,
         locked_by = null,
         last_error = left(coalesce(p_error, 'Unknown Odoo error'), 4000),
         updated_at = now()
   where id = p_event_id;
  if not found then raise exception 'حدث المزامنة غير موجود'; end if;
end;
$$;

revoke all on function claim_odoo_sync_batch(uuid, integer, text) from public, anon, authenticated;
revoke all on function complete_odoo_sync(uuid, text, integer, jsonb) from public, anon, authenticated;
revoke all on function fail_odoo_sync(uuid, text, integer) from public, anon, authenticated;
grant execute on function claim_odoo_sync_batch(uuid, integer, text) to service_role;
grant execute on function complete_odoo_sync(uuid, text, integer, jsonb) to service_role;
grant execute on function fail_odoo_sync(uuid, text, integer) to service_role;
