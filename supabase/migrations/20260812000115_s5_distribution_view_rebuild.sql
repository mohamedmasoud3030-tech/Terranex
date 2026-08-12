-- GF-008 / S5 — the following hardening migration adds an explicit reversal
-- state to the distribution read model. PostgreSQL cannot insert a view column
-- before an existing column via CREATE OR REPLACE VIEW, so rebuild this derived
-- read model intentionally. No stored financial fact is changed or removed.

drop view if exists public.s5_distributions_read;
