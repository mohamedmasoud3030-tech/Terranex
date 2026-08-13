-- Pilot runtime hardening after live Supabase advisor verification.
-- Forward-only: secure the non-tenant S7 mapping registry, close the accidental
-- anonymous EXECUTE grant on the evidence-backed S5 command, and pin mutable
-- search_path on S1 trigger guards.

-- The S7 opening mapping registry is shared immutable reference data. It is
-- readable by signed-in users through the security-invoker read view, never
-- writable by client roles, and must still be protected by RLS because public
-- is an exposed PostgREST schema.
alter table public.s7_opening_mapping_codes enable row level security;
alter table public.s7_opening_mapping_codes force row level security;

drop policy if exists s7_opening_mapping_codes_authenticated_read
  on public.s7_opening_mapping_codes;
create policy s7_opening_mapping_codes_authenticated_read
  on public.s7_opening_mapping_codes
  for select
  to authenticated
  using (true);

revoke all on public.s7_opening_mapping_codes from public, anon, authenticated;
grant select on public.s7_opening_mapping_codes to authenticated;

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. The 9-argument S5
-- allocation-basis wrapper was created after the older overload's revoke, so
-- explicitly close its anonymous/public surface while retaining the intended
-- signed-in command entry point. The function itself still enforces active
-- membership and OWNER authorization.
revoke all on function public.s5_configure_allocation_rules(
  uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text
) from public, anon, authenticated;
grant execute on function public.s5_configure_allocation_rules(
  uuid,uuid,uuid,text,uuid[],bigint[],bigint,text,text
) to authenticated;

-- Trigger guards do not need caller-controlled schema resolution.
alter function public.s1_guard_agreement_version_immutable()
  set search_path = pg_catalog, public;
alter function public.s1_guard_append_only()
  set search_path = pg_catalog, public;
alter function public.s1_guard_commitment_terms_immutable()
  set search_path = pg_catalog, public;
