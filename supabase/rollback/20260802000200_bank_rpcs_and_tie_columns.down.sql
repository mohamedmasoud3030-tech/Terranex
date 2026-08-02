-- Rollback: drop bank RPCs and columns
drop function if exists record_bank_transfer(uuid,uuid,numeric,text,numeric,numeric,date,text,text);
drop function if exists record_bank_transaction(uuid,text,numeric,text,numeric,date,text,uuid,uuid,text);
alter table settlements  drop column if exists bank_account_id;
alter table transactions drop column if exists bank_account_id;
