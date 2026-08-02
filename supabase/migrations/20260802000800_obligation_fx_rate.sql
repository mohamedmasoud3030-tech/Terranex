-- Migration: fx_rate column on obligations
-- Aligns obligations with transactions: store per-row FX rate so amounts in
-- foreign currencies convert to base currency properly (previously only
-- amount_egp was stored without remembering the rate used).
-- Date: 2026-08-02

alter table obligations add column if not exists fx_rate numeric(18,8) not null default 1
  check (fx_rate > 0);

-- Populate fx_rate for existing rows: for EGP rows keep 1, for foreign currency
-- rows infer as amount_egp / amount (best-effort backfill).
update obligations set fx_rate = case when amount > 0 then amount_egp / amount else 1 end
  where coalesce(fx_rate, 0) <= 0 or (currency <> 'EGP' and abs(fx_rate - 1) < 0.000001 and amount_egp <> amount);
