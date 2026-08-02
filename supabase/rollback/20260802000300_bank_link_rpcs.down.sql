-- Rollback: drop link_financial_movement RPC
drop function if exists link_financial_movement(text, text, uuid, uuid, text, numeric, text, numeric, date, text, uuid, uuid);

-- Leave bank_account_id columns in place (they are nullable and harmless;
-- removing them could lose data if migration was applied).
