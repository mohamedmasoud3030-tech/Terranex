-- GF-008 / S5 — maker/checker segregation of duties.
-- Canonical operating model: the maker and approver must be different users
-- for allocation and distribution approvals. Enforce the invariant directly
-- on persisted facts so RPC, privileged, and future write paths cannot bypass it.

alter table public.s5_allocation_runs
  add constraint s5_allocation_run_maker_checker_check
  check (approved_by is null or approved_by <> prepared_by);

alter table public.s5_distributions
  add constraint s5_distribution_maker_checker_check
  check (approved_by is null or approved_by <> prepared_by);
