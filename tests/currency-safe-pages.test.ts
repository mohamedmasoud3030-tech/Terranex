import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/**
 * The project surfaces that hold money are locked to the currency-safe roll-up.
 *
 * `tests/money-by-currency.test.ts` proves the primitive refuses to combine
 * currencies. This file proves the pages actually use it — a correct helper
 * that a page bypasses is not a guarantee. Each assertion below fails if a page
 * goes back to reducing `*_minor_units` itself or stamps a figure with the
 * project's `reporting_currency`.
 *
 * The surfaces covered are the ones that previously did exactly that:
 * `/overview` (the project position summary), `/revenue`, `/costs`, `/cash`
 * and `/budget`.
 */

function page(path: string): string {
  return readFileSync(path, 'utf8');
}

/**
 * Pages that total ordinary money rows, so they must go through
 * `totalsByCurrency` / `presentRollup`.
 */
const SAFE_PAGES = [
  'src/app/(app)/projects/[projectId]/overview/page.tsx',
  'src/app/(app)/projects/[projectId]/revenue/page.tsx',
  'src/app/(app)/projects/[projectId]/costs/page.tsx',
  'src/app/(app)/projects/[projectId]/cash/page.tsx',
  'src/app/(app)/projects/[projectId]/budget/page.tsx',
];

/**
 * Pages whose figures come from a dedicated domain contract rather than the
 * generic roll-up. They are held to that contract instead — the capital
 * contract is stricter, and asserting the generic helper on it would test the
 * wrong thing.
 */
const CAPITAL_CONTRACT_PAGES = [
  'src/app/(app)/projects/[projectId]/funding/page.tsx',
];

/**
 * `/operations` builds four per-currency cost figures from one row set. It also
 * goes through `totalsByCurrency`, but its render shape is deliberately
 * different from `SAFE_PAGES`: the metric name and the currency are printed
 * together per tile, so there is no single `total` binding to assert on.
 */
const PER_CURRENCY_METRIC_PAGES = [
  'src/app/(app)/projects/[projectId]/operations/page.tsx',
];

/**
 * `/integrity` renders money per row and never totals it, so it has no roll-up
 * to route through. Only the negative half of the contract applies: no
 * arithmetic over money columns, no figure labelled with the project reporting
 * currency, no manufactured zero.
 */
const PER_ROW_MONEY_PAGES = [
  'src/app/(app)/projects/[projectId]/integrity/page.tsx',
];

describe('the operations page never totals cost rows across currencies', () => {
  const operations = page(PER_CURRENCY_METRIC_PAGES[0]);

  it('totals cost columns only through totalsByCurrency', () => {
    expect(operations).toContain('totalsByCurrency');
    expect(operations).not.toMatch(/reduce\([\s\S]{0,80}_minor_units/);
    expect(operations).not.toMatch(/_minor_units\)\s*,\s*0n/);
  });

  it('never labels a cost figure with the project reporting currency', () => {
    expect(operations).not.toMatch(/formatMinorUnits\([^,]+,\s*project\.reporting_currency\)/);
    // The acquisition consideration is a contract fact in the contract's own
    // currency; a missing acquisition currency is disclosed, not backfilled.
    expect(operations).not.toMatch(/acquisition_currency\s*\?\?/);
  });

  it('prints every metric together with the currency it is stated in', () => {
    expect(operations).toMatch(/metric\.rollup\.totals\.find\(/);
    expect(operations).toMatch(/presentRollup\(/);
    expect(operations).toMatch(/metric\.label\} — \{costCurrency\}/);
  });

  it('does not manufacture a zero for a missing answer', () => {
    expect(operations).not.toMatch(/\?\?\s*'0'/);
    expect(operations).not.toMatch(/_minor_units\s*\?\?/);
  });
});

describe('the integrity page renders money per row, in that row currency', () => {
  const integrity = page(PER_ROW_MONEY_PAGES[0]);

  it('reads the project-grain position and discloses its currency scope', () => {
    // `project_financial_position_read` is a genuine singleton per project, so
    // the reader stays a singleton. What the page must not do is present that
    // single reporting-currency slice as the whole financial position.
    expect(integrity).toContain('getProjectPosition');
    expect(integrity).toMatch(/position\.currency/);
    expect(integrity).toMatch(/نطاق هذا الجدول عملة تقارير المشروع/);
    expect(integrity).toMatch(/يستبعد ما رُحّل بعملة أخرى/);
  });

  it('never falls back to the project reporting currency for a row amount', () => {
    // `signal.currency ?? project reporting currency` was the original defect,
    // and `formatMinorUnits(amount, currency)` with a page-level `currency`
    // binding was its shape. Neither may come back.
    expect(integrity).not.toMatch(/\?\?\s*reportingCurrency/);
    expect(integrity).not.toMatch(/currency\s*\?\?\s*currency/);
    expect(integrity).not.toMatch(/formatMinorUnits\([^,]+,\s*currency\)/);
    expect(integrity).not.toMatch(/row\.org_reporting_currency\s*\?\?/);
    expect(integrity).not.toMatch(/formatMinorUnits\([^,]+,\s*row\.org_reporting_currency\s*\?\?/);
    // Every amount goes through the single `moneyCell` guard, whose currency
    // parameter is named `rowCurrency` so it cannot be confused with the
    // project's reporting currency. Any new raw call site fails here.
    expect(integrity.match(/formatMinorUnits\(/g) ?? []).toHaveLength(1);
    expect(integrity).toMatch(/function moneyCell\(amount: string \| null, rowCurrency: string \| null\)/);
  });
});

describe('project money surfaces use the currency-safe roll-up', () => {
  it.each(SAFE_PAGES)('%s totals money only through totalsByCurrency', (path) => {
    const source = page(path);
    expect(source).toContain('totalsByCurrency');
    // No page-level arithmetic over money columns. `reduce` on non-money arrays
    // (counting, mapping) is not the concern; summing `*_minor_units` is.
    expect(source).not.toMatch(/reduce\([\s\S]{0,80}_minor_units/);
    expect(source).not.toMatch(/_minor_units\)\s*,\s*0n/);
  });

  it.each(SAFE_PAGES)('%s never labels a figure with the project reporting currency', (path) => {
    const source = page(path);
    // `formatMinorUnits(x, currency)` where `currency` is
    // `project.reporting_currency` is the historical defect in one line.
    expect(source).not.toMatch(/formatMinorUnits\([^,]+,\s*currency\)/);
    expect(source).not.toMatch(/formatMinorUnits\([^,]+,\s*project\.reporting_currency\)/);
  });

  it.each(SAFE_PAGES)('%s does not manufacture a zero for a missing answer', (path) => {
    const source = page(path);
    expect(source).not.toMatch(/\?\?\s*'0'/);
    expect(source).not.toMatch(/value\s*\?\?\s*0/);
  });

  it.each(SAFE_PAGES)('%s renders one line per currency, labelled with it', (path) => {
    const source = page(path);
    // Every roll-up render site is keyed and labelled by the currency.
    expect(source).toMatch(/presentRollup\(total\)/);
    expect(source).toMatch(/total\.currency/);
  });
});

/**
 * The three surfaces repaired after the first currency sweep. Each one took a
 * different route to the same lie — inventing a number where the data had none:
 * a missing variance became `0.00`, a missing sector row became `0.00`, and a
 * purchase order with no recognised commitment became "invoiced 0.00 / whole
 * order still outstanding".
 *
 * The assertion is scoped to `*_minor_units` on purpose. These pages legitimately
 * use `?? '0'` for quantities and counts (`received_quantity`, row counts) and
 * `?? null` for an absent variance; the defect is manufacturing a *money* value,
 * and only that is forbidden here.
 */
const NO_MANUFACTURED_MONEY_PAGES = [
  'src/app/(app)/page.tsx',
  'src/app/(app)/projects/[projectId]/intake/page.tsx',
  'src/app/(app)/projects/[projectId]/procurement/page.tsx',
];

describe('no surface invents a money value the data does not contain', () => {
  it.each(NO_MANUFACTURED_MONEY_PAGES)('%s never defaults money to zero', (path) => {
    const source = page(path);
    expect(source).not.toMatch(/_minor_units\s*\?\?\s*'0'/);
  });

  it.each(NO_MANUFACTURED_MONEY_PAGES)(
    '%s never substitutes one money amount for another',
    (path) => {
      // `a_minor_units ?? b_minor_units` presents b's figure as a's answer.
      // `/procurement` did this by falling back to the commercial total when no
      // commitment row existed.
      const source = page(path);
      expect(source).not.toMatch(/_minor_units\s*\?\?\s*[A-Za-z_][\w.?]*_minor_units/);
    },
  );

  it('intake keeps an absent variance absent rather than printing a zero', () => {
    const intake = page(NO_MANUFACTURED_MONEY_PAGES[1]);
    // The helper's contract: unknown stays '—', and the currency label is the
    // project's because the S7 intake contract carries no per-row currency.
    expect(intake).toMatch(/value === null \|\| value === undefined \? '—'/);
    expect(intake).toMatch(/formatMinorUnits\(value, project\.reporting_currency\)/);
    expect(intake).not.toMatch(/formatMinorUnits\(value \?\? '0'/);
  });

  it('the home sector table shows no deducted cost when the row is missing', () => {
    const home = page(NO_MANUFACTURED_MONEY_PAGES[0]);
    expect(home).toMatch(/const deducted = resultRowBySector\.get\(key\)\?\.result_deducted_cost_minor_units/);
    expect(home).toMatch(/if \(!sectorResult \|\| deducted === undefined\) return '—'/);
  });

  it('procurement only reports commitment figures for an order that has one', () => {
    const procurement = page(NO_MANUFACTURED_MONEY_PAGES[2]);
    // `project_procurement_commitments_read` emits a row only for an APPROVED
    // order with lines, so the absent case is "not committed yet" and must not
    // be rendered as a figure.
    expect(procurement).toMatch(/commitment \? formatMinorUnits\(commitment\.invoiced_minor_units/);
    expect(procurement).toMatch(/commitment \? formatMinorUnits\(commitment\.remaining_commitment_minor_units/);
    expect(procurement).not.toMatch(/commitment\?\.(invoiced|remaining_commitment)_minor_units/);
  });
});

describe('the funding page reads capital through the per-currency contract', () => {
  it.each(CAPITAL_CONTRACT_PAGES)('%s consumes the capital contract, not a raw scalar', (path) => {
    const source = page(path);
    expect(source).toContain('getProjectCapitalByCurrency');
    expect(source).toContain('buildProjectCapitalView');
    // `presentCapitalAmount` returns amount and currency together, or refuses.
    expect(source).toContain('presentCapitalAmount');
    // The project-grain reader is gone; a page reintroducing it would be able
    // to print a cross-currency total under the reporting currency again.
    expect(source).not.toMatch(/getProjectCapitalPosition/);
    expect(source).not.toMatch(/\?\?\s*'0'/);
    expect(source).not.toMatch(/formatMinorUnits\([^,]+,\s*project\.reporting_currency\)/);
  });
});

describe('the project position page no longer reads the single-currency contracts', () => {
  const overview = page('src/app/(app)/projects/[projectId]/overview/page.tsx');

  it('uses the per-currency cash and capital read models', () => {
    expect(overview).toContain('getProjectCashByCurrency');
    expect(overview).toContain('getProjectCapitalByCurrency');
    // The project-grain position view assumes one currency per project.
    expect(overview).not.toMatch(/getProjectCapitalPosition/);
    expect(overview).not.toMatch(/getCashAccountPositions/);
  });

  it('no longer reduces account or result balances into a single number', () => {
    expect(overview).not.toMatch(/totalCash/);
    expect(overview).not.toMatch(/cashAccounts\.reduce/);
    expect(overview).not.toMatch(/results\.reduce/);
    expect(overview).not.toMatch(/realized_result_minor_units\)\s*,\s*0n/);
  });

  it('keeps realized result in its own currency and stops calling it a project result', () => {
    // ADR 0034: realized result is the Real-Estate disposal result, and the
    // view must not present it as a cross-sector figure.
    expect(overview).toContain('النتيجة المحققة من التصرفات');
    expect(overview).toContain('نتيجة تصرف عقاري');
  });
});

describe('the cash page no longer calls a summed balance the project cash', () => {
  const cash = page('src/app/(app)/projects/[projectId]/cash/page.tsx');

  it('does not sum accounts into one book balance', () => {
    expect(cash).not.toMatch(/accounts\.reduce\(/);
    expect(cash).not.toMatch(/totalCash\s*=\s*accounts/);
    expect(cash).not.toMatch(/formatMinorUnits\(totalCash/);
  });
});

describe('the budget and costs pages partition their ceilings and obligations', () => {
  const budget = page('src/app/(app)/projects/[projectId]/budget/page.tsx');
  const costs = page('src/app/(app)/projects/[projectId]/costs/page.tsx');

  it('budget does not roll consumption across currencies', () => {
    expect(budget).not.toMatch(/consumption[\s\S]{0,60}\.reduce\(/);
    expect(budget).toContain('totalsByCurrency');
  });

  it('costs partitions aging and obligation totals by currency', () => {
    expect(costs).not.toMatch(/agingRows[\s\S]{0,60}\.reduce\(/);
    expect(costs).not.toMatch(/obligations\.reduce\(/);
    expect(costs).toContain('totalsByCurrency');
  });
});
