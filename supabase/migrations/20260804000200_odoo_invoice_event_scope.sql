-- Restrict invoice outbox events to accounting-document lifecycle changes.
-- Payment synchronization is a separate slice and must not be reported as
-- synced merely because the invoice header amount_paid/status changed.

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
  v_old_status text;
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

  if v_entity_type in ('sales_invoice','purchase_invoice') then
    v_status := to_jsonb(new)->>'status';
    v_old_status := case when tg_op = 'UPDATE' then to_jsonb(old)->>'status' else null end;

    if tg_op = 'INSERT' then
      if v_status = 'draft' then return new; end if;
      v_operation := case when v_status = 'void' then 'void' else 'upsert' end;
    elsif v_status = 'void' and v_old_status is distinct from 'void' then
      v_operation := 'void';
    elsif v_old_status = 'draft'
      and ((v_entity_type = 'sales_invoice' and v_status = 'issued')
        or (v_entity_type = 'purchase_invoice' and v_status = 'received')) then
      v_operation := 'upsert';
    else
      -- partial/paid changes belong to the payment bridge, not invoice sync.
      return new;
    end if;
  end if;

  perform terranex_queue_odoo_event(
    new.owner_id,
    v_entity_type,
    new.id,
    v_operation,
    jsonb_build_object(
      'source_table', tg_table_name,
      'source_status', to_jsonb(new)->>'status',
      'source_updated_at', coalesce(to_jsonb(new)->>'updated_at', to_jsonb(new)->>'created_at')
    )
  );
  return new;
end;
$$;
revoke all on function terranex_enqueue_odoo_row() from public, anon, authenticated;
