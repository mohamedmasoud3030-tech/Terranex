-- =============================================================================
-- ROLLBACK 0005 — guard_*_deletion RPCs
-- =============================================================================
-- FULLY REVERSIBLE. Functions hold no state.
--
-- OPERATIONAL WARNING: with these dropped, deletionGuards.ts receives PGRST202
-- ("function not found") and falls back to FAILSAFE — every guarded delete in
-- the app is blocked with "تعذر التحقق من الروابط التشغيلية". That is the
-- fail-closed behaviour working as designed, but the app is degraded until the
-- functions are restored.
-- =============================================================================

drop function if exists public.guard_transaction_deletion(uuid);
drop function if exists public.guard_document_deletion(uuid);
drop function if exists public.guard_asset_deletion(uuid);
drop function if exists public.guard_partner_deletion(uuid);
drop function if exists public.guard_project_deletion(uuid);
drop function if exists public.terranex_guard_result(text[], text);
drop function if exists public.terranex_block_if(bigint, text);
