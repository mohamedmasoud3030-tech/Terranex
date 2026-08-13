-- A period's `version` belongs to that accounting-window lineage (including a
-- controlled reopen), not to the entire project/currency lifetime. The original
-- unique index on (org, project, currency, version) therefore prevented a
-- perfectly valid August v1 after July v1 had closed.
--
-- Keep the authoritative invariants that matter:
--   * at most one OPEN period per project/currency (existing partial index),
--   * no overlapping authoritative date ranges (existing trigger),
--   * immutable CLOSED history (existing trigger),
--   * unique version for a given period start within a scope.

drop index if exists public.accounting_periods_authoritative_unique;

create unique index accounting_periods_scope_start_version_unique
  on public.accounting_periods(
    organization_id,
    project_id,
    reporting_currency,
    start_date,
    version
  );
