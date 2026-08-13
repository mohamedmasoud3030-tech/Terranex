-- Audit-trail hardening: audit_events is authoritative historical evidence.
-- Existing rows may never be rewritten or deleted; corrections append new facts.

create or replace function public.s7_guard_audit_events_append_only() returns trigger
language plpgsql
set search_path=pg_catalog,public
as $$
begin
  raise exception 'audit events are append-only';
end $$;

revoke all on function public.s7_guard_audit_events_append_only()
  from public, anon, authenticated;

drop trigger if exists audit_events_append_only on public.audit_events;
create trigger audit_events_append_only
before update or delete on public.audit_events
for each row execute function public.s7_guard_audit_events_append_only();
