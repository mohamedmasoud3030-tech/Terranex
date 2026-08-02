-- Migration: Inventory items & movements (مخزون الأعلاف والأسمدة والبذور)
-- Phase: Lightweight stock ledger for ag/livestock consumables
-- Date: 2026-08-02

create table if not exists inventory_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name_ar text not null,
  name_en text,
  sku text,
  category text not null check (category in ('feed','fertilizer','seed','medicine','vaccine','supply','other'))
    default 'other',
  unit text not null default 'unit', -- kg, bag, liter, sack, head...
  project_id uuid references projects(id) on delete set null,
  reorder_level numeric(18,3) not null default 0,
  default_unit_cost numeric(18,3) not null default 0,
  currency text not null default 'OMR' references currencies(code) on delete restrict,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create table if not exists inventory_movements (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references inventory_items(id) on delete cascade,
  movement_type text not null check (movement_type in ('purchase','consume','adjustment','transfer_in','transfer_out','waste')),
  quantity numeric(18,3) not null check (quantity <> 0),
  unit_cost numeric(18,3) not null default 0,
  currency text not null default 'OMR' references currencies(code) on delete restrict,
  fx_rate_to_base numeric(18,8) not null default 1,
  total_cost_base numeric(18,3) not null default 0,
  movement_date date not null default current_date,
  reference_type text, -- 'transaction','operational_event',null
  reference_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create index inventory_items_owner_idx on inventory_items(owner_id) where is_archived = false;
create index inventory_movements_item_date_idx on inventory_movements(item_id, movement_date desc);
create index inventory_movements_owner_date_idx on inventory_movements(owner_id, movement_date desc);

drop trigger if exists trg_inventory_items_updated on inventory_items;
create trigger trg_inventory_items_updated before update on inventory_items
  for each row execute function set_timestamp();
drop trigger if exists trg_inventory_movements_updated on inventory_movements;
create trigger trg_inventory_movements_updated before update on inventory_movements
  for each row execute function set_timestamp();

alter table inventory_items enable row level security;
alter table inventory_movements enable row level security;

create policy inv_items_owner_all on inventory_items
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy inv_mvmts_owner_all on inventory_movements
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

grant select, insert, update, delete on inventory_items to authenticated;
grant select, insert, update, delete on inventory_movements to authenticated;

-- Current stock per item (view)
create or replace view inventory_stock as
select
  i.id,
  i.owner_id,
  i.name_ar,
  i.name_en,
  i.category,
  i.unit,
  i.project_id,
  i.reorder_level,
  i.default_unit_cost,
  i.currency,
  coalesce(sum(
    case m.movement_type
      when 'purchase'     then m.quantity
      when 'transfer_in'  then m.quantity
      when 'transfer_out' then -m.quantity
      when 'consume'      then -m.quantity
      when 'waste'        then -m.quantity
      when 'adjustment'   then m.quantity
      else 0
    end
  ), 0)::numeric(18,3) as quantity_on_hand
from inventory_items i
left join inventory_movements m on m.item_id = i.id
where i.is_archived = false
group by i.id, i.owner_id, i.name_ar, i.name_en, i.category, i.unit, i.project_id,
         i.reorder_level, i.default_unit_cost, i.currency;
