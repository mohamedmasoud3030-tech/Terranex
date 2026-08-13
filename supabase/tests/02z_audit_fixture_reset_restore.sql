-- Restore the production audit immutability control immediately after the
-- legacy S1 fixture reset. Later suites, including the dedicated audit gate,
-- run with the production trigger enabled.
alter table public.audit_events enable trigger audit_events_append_only;
