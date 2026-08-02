drop function if exists pay_purchase_invoice(text, uuid, numeric, uuid, date, text);
drop function if exists receive_purchase_invoice(text, uuid);
drop table if exists purchase_invoice_lines cascade;
drop table if exists purchase_invoices cascade;
