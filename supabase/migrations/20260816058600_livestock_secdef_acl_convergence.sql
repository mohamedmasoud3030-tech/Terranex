-- Cross-branch SECURITY DEFINER ACL convergence.
--
-- PR #146 independently closes these two pre-existing livestock ACL gaps.
-- PR #147 now carries a global SECURITY DEFINER regression gate as well, so
-- this branch must be safe when replayed directly from its current main base.
-- Repeating REVOKE/GRANT is idempotent and remains harmless if #146 lands first.

revoke all on function
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text,text)
from public, anon;

grant execute on function
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text,text)
to authenticated;
