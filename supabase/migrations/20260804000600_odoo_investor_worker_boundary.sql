-- Route investor accounting events to a dedicated Edge Function while keeping
-- the original worker responsible for operational Odoo entities.

create or replace function claim_odoo_sync_batch(
  p_owner_id uuid,
  p_limit integer default 20,
  p_worker_id text default 'edge-function'
) returns setof odoo_sync_outbox
language plpgsql security definer set search_path=public as $$
begin
  return query
  with picked as (
    select id from odoo_sync_outbox
     where owner_id=p_owner_id
       and entity_type not in ('distribution','partner_ledger_entry')
       and status in ('pending','failed') and available_at<=now()
     order by created_at for update skip locked
     limit greatest(1,least(coalesce(p_limit,20),100))
  )
  update odoo_sync_outbox o set status='processing',attempt_count=o.attempt_count+1,
    locked_at=now(),locked_by=coalesce(p_worker_id,'edge-function'),updated_at=now()
  from picked where o.id=picked.id returning o.*;
end; $$;

create or replace function claim_odoo_investor_sync_batch(
  p_owner_id uuid,
  p_limit integer default 20,
  p_worker_id text default 'odoo-investor-sync'
) returns setof odoo_sync_outbox
language plpgsql security definer set search_path=public as $$
begin
  return query
  with picked as (
    select id from odoo_sync_outbox
     where owner_id=p_owner_id
       and entity_type in ('distribution','partner_ledger_entry')
       and status in ('pending','failed') and available_at<=now()
     order by created_at for update skip locked
     limit greatest(1,least(coalesce(p_limit,20),100))
  )
  update odoo_sync_outbox o set status='processing',attempt_count=o.attempt_count+1,
    locked_at=now(),locked_by=coalesce(p_worker_id,'odoo-investor-sync'),updated_at=now()
  from picked where o.id=picked.id returning o.*;
end; $$;

revoke all on function claim_odoo_sync_batch(uuid,integer,text) from public,anon,authenticated;
revoke all on function claim_odoo_investor_sync_batch(uuid,integer,text) from public,anon,authenticated;
grant execute on function claim_odoo_sync_batch(uuid,integer,text) to service_role;
grant execute on function claim_odoo_investor_sync_batch(uuid,integer,text) to service_role;