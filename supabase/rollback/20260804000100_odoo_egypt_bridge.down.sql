-- Rollback: Egypt-first Odoo accounting bridge

drop trigger if exists trg_purchase_invoices_odoo_outbox on purchase_invoices;
drop trigger if exists trg_sales_invoices_odoo_outbox on sales_invoices;
drop trigger if exists trg_projects_odoo_outbox on projects;
drop trigger if exists trg_partners_odoo_outbox on partners;

drop function if exists fail_odoo_sync(uuid, text, integer);
drop function if exists complete_odoo_sync(uuid, text, integer, jsonb);
drop function if exists claim_odoo_sync_batch(uuid, integer, text);
drop function if exists terranex_enqueue_odoo_row();
drop function if exists enqueue_odoo_sync(text, uuid, text);
drop function if exists terranex_queue_odoo_event(uuid, text, uuid, text, jsonb);
drop function if exists terranex_odoo_entity_owner(text, uuid);

drop table if exists odoo_entity_mappings cascade;
drop table if exists odoo_sync_outbox cascade;

alter table company_settings drop column if exists eta_branch_code;
alter table company_settings drop column if exists odoo_localization;
alter table company_settings drop column if exists odoo_company_id;

alter table company_settings alter column country set default 'OM';
alter table company_settings alter column base_currency set default 'OMR';
alter table bank_accounts alter column currency set default 'OMR';
alter table sales_invoices alter column currency set default 'OMR';
alter table purchase_invoices alter column currency set default 'OMR';
alter table inventory_items alter column currency set default 'OMR';
alter table inventory_movements alter column currency set default 'OMR';
alter table journal_entries alter column currency set default 'OMR';
