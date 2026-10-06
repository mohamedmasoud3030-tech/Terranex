import { describe, expect, it } from 'vitest';
import { fixtures } from '../scripts/ui-preview/fixtures.mjs';

/**
 * The offline preview harness must be able to render the contracts the product
 * actually has.
 *
 * When the H1 tranche (ADR 0034) replaced the project-grain read models with
 * per-currency ones, this harness was not updated. `mock-supabase.mjs` answers
 * an unknown table with `[]`, so every H1 consumer — the project brief's
 * Capital and Result panels, the project position summary, and the Home sector
 * table — quietly rendered its empty state. The interface looked complete while
 * the domain contract was never exercised in a browser, and no test noticed.
 *
 * These assertions make that specific blind spot impossible to reintroduce.
 */

type Fixture = Record<string, unknown[]>;

const populated = fixtures.populated as Fixture;

/** The H1 read models every qualified/currency-aware surface reads. */
const H1_READ_MODELS = [
  'project_cash_by_currency_read',
  'project_capital_by_currency_read',
  'project_result_by_currency_read',
  'sector_management_result_read',
];

/**
 * The money-bearing surfaces recovered in this round. Each of these rendered an
 * empty state in the harness because its read model had no fixture at all — the
 * mock answers an unknown table with `[]`, so a missing fixture is
 * indistinguishable from a legitimate "nothing recorded yet".
 */
const RECOVERED_MONEY_READ_MODELS = [
  // One row per (asset, parcel, phase, category, currency): the fixture carries
  // EGP and OMR rows for the same category on purpose, because that is the shape
  // that produced the cross-currency total on `/operations`.
  'property_cost_control_read',
  'property_cost_drilldown_read',
  // One row per project, reporting-currency slice only.
  'project_financial_position_read',
  'approval_exception_registry_read',
];

describe('UI preview fixtures cover the H1 read models', () => {
  it.each(H1_READ_MODELS)('%s is present and non-empty', (table) => {
    expect(populated[table], `${table} missing from fixtures.populated`).toBeTruthy();
    expect((populated[table] ?? []).length).toBeGreaterThan(0);
  });

  it('exposes at least two currencies on the project cash contract', () => {
    // The whole point of the per-currency contracts is a project that holds
    // more than one currency. A single-currency fixture cannot demonstrate the
    // safety property, so it would pass even if the page summed everything.
    const rows = (populated.project_cash_by_currency_read ?? []) as { project_id: string; currency: string }[];
    const byProject = new Map<string, Set<string>>();
    for (const row of rows) {
      const set = byProject.get(row.project_id) ?? new Set<string>();
      set.add(row.currency);
      byProject.set(row.project_id, set);
    }
    const multi = [...byProject.values()].filter((set) => set.size > 1);
    expect(multi.length).toBeGreaterThan(0);
  });

  it('pairs currencies that differ in scale so a wrong sum would be visible', () => {
    // EGP has 2 decimals, OMR has 3. A combined figure would be wrong in its
    // digit string as well as its currency, which is what the historical
    // defect produced.
    const rows = (populated.project_cash_by_currency_read ?? []) as { project_id: string; currency: string }[];
    const currencies = new Set(rows.map((r) => r.currency));
    expect(currencies.has('EGP')).toBe(true);
    expect(currencies.has('OMR')).toBe(true);
  });

  it('carries an unclassified cost so the disclosure path renders', () => {
    const rows = (populated.sector_management_result_read ?? []) as {
      unclassified_eligible_minor_units?: string;
    }[];
    const hasUnclassified = rows.some(
      (row) => row.unclassified_eligible_minor_units && /^[1-9]/.test(row.unclassified_eligible_minor_units),
    );
    expect(hasUnclassified).toBe(true);
  });

  it('every qualified result carries its full ADR 0034 qualification', () => {
    const rows = [
      ...((populated.sector_management_result_read ?? []) as { management_result?: Record<string, unknown> }[]),
      ...((populated.project_result_by_currency_read ?? []) as { management_result?: Record<string, unknown> }[]),
    ];
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) {
      const r = row.management_result;
      expect(r, 'management_result must be an object, never a bare scalar').toBeTypeOf('object');
      for (const field of [
        'amount_minor_units',
        'currency',
        'basis',
        'cost_classification_status',
        'evidence_status',
        'policy_availability',
        'as_of',
      ]) {
        expect(r, `management_result.${field} missing`).toHaveProperty(field);
      }
      // Money is exact integer text, never a float.
      expect(String(r?.amount_minor_units)).toMatch(/^-?\d+$/);
      expect(String(r?.currency)).toMatch(/^[A-Z]{3}$/);
    }
  });

  it('does not reintroduce a bare result scalar anywhere in the fixtures', () => {
    // ADR 0034 §2.1: no shared read model intended for the management UI
    // exposes `operating_result_minor_units`. A fixture that added one would
    // advertise a contract the database deliberately does not have.
    for (const [table, rows] of Object.entries(populated)) {
      for (const row of rows as Record<string, unknown>[]) {
        expect(
          Object.keys(row ?? {}),
          `${table} must not expose a bare result scalar`,
        ).not.toContain('operating_result_minor_units');
      }
    }
  });
});

describe('UI preview fixtures cover the recovered money surfaces', () => {
  it.each(RECOVERED_MONEY_READ_MODELS)('%s is present and non-empty', (table) => {
    expect(populated[table], `${table} missing from fixtures.populated`).toBeTruthy();
    expect((populated[table] ?? []).length).toBeGreaterThan(0);
  });

  it('keeps the cost control fixture multi-currency in one category', () => {
    // The cross-currency total is only reachable when one category holds rows in
    // two currencies. A single-currency fixture would pass even if the page
    // summed everything, so the fixture must keep both rows.
    const rows = (populated.property_cost_control_read ?? []) as {
      property_asset_id: string;
      cost_category: string;
      currency: string;
    }[];
    const groups = new Map<string, Set<string>>();
    for (const row of rows) {
      const key = `${row.property_asset_id}/${row.cost_category}`;
      groups.set(key, (groups.get(key) ?? new Set()).add(row.currency));
    }
    const multi = [...groups.values()].filter((currencies) => currencies.size > 1);
    expect(multi.length).toBeGreaterThan(0);
  });

  it('keeps the cost control fixture split so the two currencies cannot be added', () => {
    const rows = (populated.property_cost_control_read ?? []) as { currency: string; budget_minor_units: string }[];
    const byCurrency = new Map<string, bigint>();
    for (const row of rows) {
      byCurrency.set(row.currency, (byCurrency.get(row.currency) ?? 0n) + BigInt(row.budget_minor_units));
    }
    expect([...byCurrency.keys()].sort()).toEqual(['EGP', 'OMR']);
    // The historical defect surfaced as one number equal to a cross-currency
    // sum. No single currency's budget may equal the naive combined total.
    let combined = 0n;
    for (const value of byCurrency.values()) combined += value;
    for (const value of byCurrency.values()) {
      expect(value).not.toBe(combined);
    }
  });

  it('keeps the project position fixture single-currency, matching the view', () => {
    // `project_financial_position_read` joins each CTE on
    // `currency = reporting_currency` and is driven by the project primary key,
    // so a second currency on this fixture would misrepresent the contract.
    const rows = (populated.project_financial_position_read ?? []) as { project_id: string; currency: string }[];
    const perProject = new Map<string, Set<string>>();
    for (const row of rows) {
      perProject.set(row.project_id, (perProject.get(row.project_id) ?? new Set()).add(row.currency));
    }
    for (const currencies of perProject.values()) {
      expect(currencies.size).toBe(1);
    }
  });
});
