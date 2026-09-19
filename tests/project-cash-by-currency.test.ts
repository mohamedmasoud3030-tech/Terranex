import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// The defect: the project page summed every cash account balance into one number
// and stamped it with the project reporting currency, adding OMR minor units to
// USD minor units. The structural guarantee is that no such figure exists to
// display — not merely that the UI declines to show one.
const migration = readFileSync(
  'supabase/migrations/20260904010400_h1_project_cash_by_currency.sql',
  'utf8',
);
const queries = readFileSync('src/features/finance/queries.ts', 'utf8');
const projectPage = readFileSync('src/app/(app)/projects/[projectId]/page.tsx', 'utf8');

const columnBlock = (() => {
  const start = migration.indexOf('select\n  organization_id,');
  const end = migration.indexOf('from per_account');
  if (start < 0 || end < 0) throw new Error('could not locate the projection column list');
  if (start < 0 || end < 0) throw new Error('could not locate the projection column list');
  return migration.slice(start, end);
})();

describe('H1 cash by currency — one row per currency, structurally', () => {
  it('groups by currency so no row can mix currencies', () => {
    expect(migration).toMatch(/group by organization_id, project_id, currency;/);
  });

  it('exposes no column representing a total across currencies', () => {
    expect(columnBlock).not.toMatch(/total|combined|converted|consolidat|all_currencies/i);
  });

  it('exposes no FX conversion', () => {
    expect(columnBlock).not.toMatch(/fx|rate/i);
    expect(migration).not.toMatch(/fx_rate|exchange_rate/i);
  });

  it('emits exact minor units as text, never a rounded number', () => {
    expect(columnBlock).toMatch(/cash_balance_minor_units/);
    expect(migration).toMatch(/sum\(balance_minor\)::text as cash_balance_minor_units/);
  });

  it('discloses movements whose currency differs from their account instead of summing them', () => {
    expect(migration).toContain('currency_mismatch_line_count');
    // mismatched movements are excluded from the balance, not silently added
    expect(migration).toMatch(/filter \(where p\.currency = ca\.currency\)/);
    expect(migration).toMatch(/filter \(where p\.currency is distinct from ca\.currency\)/);
  });

  it('reports an exact zero only for an account that genuinely holds zero, and labels why', () => {
    expect(migration).toContain('has_active_posted_movement');
    expect(migration).toMatch(/A registered account with no posted movement genuinely holds zero/);
  });

  it('yields no row for a project with no accounts, rather than an invented zero', () => {
    // No left join to projects and no coalesce at project level: rows exist only
    // where an account exists.
    expect(migration).toMatch(/from public\.project_cash_accounts ca/);
    expect(migration).not.toMatch(/from public\.investment_projects/);
  });

  it('is a projection over existing account-level facts, not a new financial fact', () => {
    expect(migration).toMatch(/create view/);
    expect(migration).not.toMatch(/create table/);
    expect(migration).toMatch(/This is a projection over/);
  });
});

describe('H1 cash by currency — the TypeScript layer cannot sum currencies', () => {
  it('types one row per currency with no combined field', () => {
    expect(queries).toContain('export type ProjectCashByCurrency');
    const block = queries.slice(queries.indexOf('export type ProjectCashByCurrency'));
    const body = block.slice(0, block.indexOf('};'));
    expect(body).toContain('currency: string;');
    expect(body).toContain('cash_balance_minor_units: string;');
    expect(body).not.toMatch(/total|combined|converted|consolidated/i);
  });

  it('exposes a query that filters by project and orders by currency', () => {
    expect(queries).toContain('getProjectCashByCurrency');
    expect(queries).toMatch(/from\('project_cash_by_currency_read'\)/);
  });
});

describe('H1 cash by currency — the project page no longer sums accounts', () => {
  it('does not reduce cash account balances into one number', () => {
    expect(projectPage).not.toContain('totalCash');
    expect(projectPage).not.toMatch(/cashAccounts\.reduce/);
    expect(projectPage).not.toMatch(/reduce\(\(sum, account\)/);
  });

  it('renders one labelled position per currency', () => {
    expect(projectPage).toContain('getProjectCashByCurrency');
    expect(projectPage).toMatch(/cashByCurrency\.map/);
    expect(projectPage).toMatch(/key=\{cash\.currency\}/);
    expect(projectPage).toMatch(/formatMinorUnits\(cash\.cash_balance_minor_units, cash\.currency\)/);
  });

  it('does not stamp a foreign currency onto a cash position', () => {
    // The old code formatted a summed balance with project.reporting_currency.
    expect(projectPage).not.toMatch(/formatMinorUnits\(totalCash, currency\)/);
  });

  it('says so explicitly rather than showing an invented zero when there are no accounts', () => {
    expect(projectPage).toContain('لا توجد حسابات نقدية مسجلة');
    expect(projectPage).toContain('لا نعرض صفرًا مفترضًا');
  });
});
