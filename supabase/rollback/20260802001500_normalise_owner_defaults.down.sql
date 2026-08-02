-- 0015 rollback: no destructive drops — the defaults/policies added here are
-- safe to leave in place. We only drop constraints/policies that this migration
-- created explicitly, but since they are idempotent/safe we keep it minimal.
drop policy if exists bank_transactions_owner_delete on bank_transactions;
drop policy if exists invoice_payments_owner_insert on invoice_payments;
drop policy if exists invoice_payments_owner_update on invoice_payments;
drop policy if exists invoice_payments_owner_delete on invoice_payments;
alter table if exists owner_sequences drop constraint if exists owner_sequences_owner_seq_key;
