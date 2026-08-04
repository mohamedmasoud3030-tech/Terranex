-- Terranex — preserve the authenticated owner assertion contract
--
-- Production applied the anonymous-execution hardening before the invoker-RPC
-- dependency was discovered. Keep this explicit follow-up migration so the
-- repository and Supabase migration histories remain rebuildable and aligned.

revoke all on function public.terranex_assert_owner(uuid)
  from public, anon;
grant execute on function public.terranex_assert_owner(uuid)
  to authenticated, service_role;
