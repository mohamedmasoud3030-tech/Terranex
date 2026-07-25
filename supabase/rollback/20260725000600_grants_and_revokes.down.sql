-- =============================================================================
-- ROLLBACK 0006 — privileges
-- =============================================================================
-- FULLY REVERSIBLE. Revokes what 0006 granted and drops the default-privilege
-- rules. It does NOT restore the permissive PUBLIC grants that 0006 revoked —
-- re-granting PUBLIC access to financial tables would be a security regression,
-- so the rollback stops at "no access" rather than "the old, looser state".
-- =============================================================================

alter default privileges in schema public
  revoke select, insert, update, delete on tables from authenticated;

revoke execute on function public.guard_project_deletion(uuid)     from authenticated;
revoke execute on function public.guard_partner_deletion(uuid)     from authenticated;
revoke execute on function public.guard_asset_deletion(uuid)       from authenticated;
revoke execute on function public.guard_document_deletion(uuid)    from authenticated;
revoke execute on function public.guard_transaction_deletion(uuid) from authenticated;
revoke execute on function public.terranex_block_if(bigint, text)     from authenticated;
revoke execute on function public.terranex_guard_result(text[], text) from authenticated;

revoke select, insert, update, delete on
  public.projects, public.partners, public.assets, public.documents,
  public.project_partners, public.transactions, public.obligations,
  public.settlements, public.settlement_allocations,
  public.operational_events, public.stock_adjustments
from authenticated;
