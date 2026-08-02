-- Rollback: drop bank_accounts + bank_transactions + company_settings + currencies
-- NOTE: this is destructive — all bank/company data is destroyed.
-- Only run this in development.

drop view if exists bank_account_balances;
drop trigger if exists trg_guard_bank_account_deletion on bank_accounts;
drop function if exists guard_bank_account_deletion();
drop table if exists bank_transactions;
drop table if exists bank_accounts;
drop trigger if exists trg_company_settings_updated on company_settings;
drop function if exists ensure_company_settings(uuid);
drop table if exists company_settings;
drop table if exists currencies cascade;
drop function if exists set_timestamp();
