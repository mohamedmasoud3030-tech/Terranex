drop function if exists set_bank_transaction_reviewed(uuid, uuid, boolean, text);
drop function if exists void_journal_entry(uuid, uuid, text);
drop function if exists post_journal_entry(uuid, uuid);
drop function if exists create_journal_entry_atomic(uuid, date, text, text, text, numeric, text, jsonb);
drop function if exists pay_purchase_invoice(uuid, uuid, numeric, uuid, date, text);
drop function if exists receive_purchase_invoice_with_stock(uuid, uuid, date);
drop function if exists create_purchase_invoice_atomic(uuid, text, uuid, uuid, uuid, date, date, text, numeric, numeric, text, jsonb);

drop trigger if exists trg_journal_lines_immutable on journal_entry_lines;
drop trigger if exists trg_journal_operations_immutable on journal_operations;
drop trigger if exists trg_purchase_operations_immutable on purchase_invoice_operations;
drop trigger if exists trg_purchase_payments_immutable on purchase_invoice_payments;
drop function if exists trg_financial_audit_immutable();

drop table if exists bank_transaction_review_operations cascade;
drop table if exists journal_operations cascade;
drop table if exists purchase_invoice_payments cascade;
drop table if exists purchase_invoice_operations cascade;
drop index if exists inventory_purchase_receipt_line_idx;

alter table bank_transactions drop constraint if exists bank_transactions_reference_type_check;
alter table bank_transactions add constraint bank_transactions_reference_type_check
  check (reference_type in (
    'transaction','settlement','distribution_payment','transfer','manual','opening_balance','invoice_payment'
  ));
alter table bank_transactions drop column if exists review_note;
alter table bank_transactions drop column if exists reviewed_at;
alter table bank_transactions drop column if exists reviewed_by;

alter table journal_entries drop constraint if exists journal_entries_status_check;
alter table journal_entries add constraint journal_entries_status_check
  check (status in ('draft','posted','void'));
alter table journal_entries drop column if exists reversal_reason;
alter table journal_entries drop column if exists reversed_by_entry_id;
alter table journal_entries drop column if exists reversal_of_entry_id;

