-- Close the default PUBLIC EXECUTE grant on the disposal/confidence-aware
-- livestock command overloads.
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. The GF-022 review
-- hardening migration (20260814002000) created the new
-- record_livestock_mortality/record_livestock_weight_event overloads and
-- granted them to authenticated, but never revoked the implicit PUBLIC grant,
-- so their ACL still carries "=X" and the Supabase anon role can invoke them.
-- The functions themselves reject anonymous callers ("authentication
-- required") and enforce active membership, so no tenant data was exposed —
-- but Terranex's default-deny contract requires the grant surface itself to
-- exclude public/anon, exactly as 20260813000300_pilot_security_advisor_
-- hardening.sql closed the same gap on s5_configure_allocation_rules.
--
-- Forward-only; recovery is re-granting EXECUTE to authenticated (already
-- restated below). Verified by supabase/tests/88_security_definer_public_
-- execute.sql, which proves no SECURITY DEFINER function in the exposed
-- public schema remains executable by PUBLIC or anon.

revoke all on function
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text,text)
from public, anon;

grant execute on function
  public.record_livestock_mortality(uuid,uuid,uuid,integer,timestamptz,text,text,text,text,text,text),
  public.record_livestock_weight_event(uuid,uuid,uuid,timestamptz,text,numeric,text,integer,integer,text,text,text,text)
to authenticated;
