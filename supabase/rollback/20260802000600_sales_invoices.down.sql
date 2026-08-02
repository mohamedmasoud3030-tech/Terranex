drop function if exists pay_sales_invoice(text, uuid, numeric, uuid, date, text);
drop function if exists issue_sales_invoice(text, uuid);
drop table if exists sales_invoice_lines cascade;
drop table if exists sales_invoices cascade;
