-- Migration: odoo_res_id columns on partners / projects / transactions
-- Phase: Odoo 18 two-way cross-reference (Terranex stores Odoo's record IDs so
-- subsequent syncs update instead of creating duplicates).
-- Date: 2026-08-02

alter table partners   add column if not exists odoo_res_id integer unique;
alter table projects   add column if not exists odoo_res_id integer unique;
alter table transactions add column if not exists odoo_res_id integer unique;
