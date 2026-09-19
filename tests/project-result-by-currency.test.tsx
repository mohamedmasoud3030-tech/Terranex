// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render } from '@testing-library/react';
import { buildProjectResultView } from '@/features/result/project-result';
import { ResultPanel } from '@/features/result/result-panel';

// The defect: the project page summed `property_realized_result_read
// .realized_result_minor_units` across every recognition row and stamped the
// total with `investment_projects.reporting_currency`. That view is S4 Real
// Estate only, so an Agriculture project — with no rows in it at all — reported
// a confident 0.00 result. Where rows did exist in two currencies, the same
// expression added their minor units together.
//
// There is no FX contract anywhere in the repository, so the correct answer is
// one qualified result per currency, never a combined figure.
const migration = readFileSync(
  'supabase/migrations/20260904010600_h1_project_result_by_currency.sql',
  'utf8',
);
const contract = readFileSync('src/features/result/project-result.ts', 'utf8');
const panel = readFileSync('src/features/result/result-panel.tsx', 'utf8');
const projectPage = readFileSync('src/app/(app)/projects/[projectId]/page.tsx', 'utf8');

/** Strip bidi marks so assertions can compare the digits that matter. */
const norm = (s: string) => s.replace(/[؜‎‏]/g, '');

afterEach(() => cleanup());

const row = (over: Record<string, unknown> = {}) => ({
  project_id: '00d00000-0000-4000-8000-000000000002',
  organization_id: '00d00000-0000-4000-8000-000000000001',
  sector: 'AGRICULTURE',
  currency: 'EGP',
  result_basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
  cost_classification_status: 'COMPLETE',
  evidence_status: 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT',
  management_result: {
    amount_minor_units: '9700000',
    currency: 'EGP',
    basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
    cost_classification_status: 'COMPLETE',
    evidence_status: 'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT',
    policy_availability: ['COGS_NOT_RECOGNIZED'],
    as_of: '2026-09-04',
  },
  sale_revenue_minor_units: '10000000',
  rental_revenue_minor_units: '0',
  cogs_derecognized_minor_units: '0',
  realized_disposal_minor_units: '0',
  selling_costs_minor_units: '0',
  attributed_operating_cost_minor_units: '0',
  selling_cost_attributed_minor_units: '0',
  project_overhead_minor_units: '300000',
  excluded_from_result_minor_units: '0',
  unclassified_eligible_minor_units: '0',
  expense_outside_classification_scope_minor_units: '0',
  result_revenue_minor_units: '10000000',
  result_deducted_cost_minor_units: '300000',
  evidence_evidenced_count: 0,
  evidence_subject_count: 0,
  as_of: '2026-09-04',
  ...over,
});

/** Build a row whose qualified object matches its currency. */
const rowIn = (currency: string, amount: string, revenue: string, deducted: string) => {
  const base = row({
    currency,
    result_revenue_minor_units: revenue,
    result_deducted_cost_minor_units: deducted,
  });
  return {
    ...base,
    management_result: { ...(base.management_result as object), currency, amount_minor_units: amount },
  };
};

describe('H1 result by currency — SQL contract', () => {
  it('groups every currency-bearing fact by its own currency', () => {
    // revenue, re_disposal, classification and re_selling_attributed each
    // aggregate per currency; none of them collapses currencies.
    expect(
      migration.match(/group by [a-z.]*organization_id, [a-z.]*project_id, [a-z.]*currency/g),
    ).not.toBeNull();
    expect(
      (migration.match(/group by [a-z.]*organization_id, [a-z.]*project_id, [a-z.]*currency/g) ?? [])
        .length,
    ).toBeGreaterThanOrEqual(4);
  });

  it('never filters facts to the project reporting currency', () => {
    // The defect in the project-grain view was `and <cte>.currency =
    // p.reporting_currency`, which dropped non-reporting currencies silently.
    // The header comment names that defect, so the check is scoped to the view.
    const viewBody = migration.slice(
      migration.indexOf('create view'),
      migration.indexOf('from derived d;'),
    );
    expect(viewBody).not.toMatch(/reporting_currency/);
  });

  it('joins every component on the row currency, so a row cannot mix them', () => {
    expect(migration).toMatch(/and rev\.currency = cur\.currency/);
    expect(migration).toMatch(/and rd\.currency = cur\.currency/);
    expect(migration).toMatch(/and c\.currency = cur\.currency/);
    expect(migration).toMatch(/and rs\.currency = cur\.currency/);
  });

  it('exposes no column representing a total across currencies, and no FX', () => {
    expect(migration).not.toMatch(/fx_rate|exchange_rate/i);
    const projection = migration.slice(
      migration.indexOf('select\n  d.project_id,'),
      migration.indexOf('from derived d;'),
    );
    expect(projection).not.toMatch(/total|combined|converted|consolidat|all_currencies/i);
  });

  it('keeps the amount inside the qualified object, with no bare scalar column', () => {
    const projection = migration.slice(
      migration.indexOf('select\n  d.project_id,'),
      migration.indexOf('from derived d;'),
    );
    expect(projection).toMatch(/jsonb_build_object\(\s*'amount_minor_units'/);
    expect(projection).not.toMatch(/^\s*d\.result_amount_minor,|result_amount_minor_units/m);
  });

  it('separates classification from deduction, and names them distinctly', () => {
    expect(migration).toMatch(/attributed_operating_cost_minor_units/);
    expect(migration).toMatch(/result_deducted_cost_minor_units/);
    expect(migration).not.toMatch(/classified_deducted/);
    // A SELLING cost is classified once and deducted zero times.
    expect(migration).toMatch(/already netted inside/i);
  });

  it('is reversal-aware: a reversed batch and its reversal never both count', () => {
    expect(migration).toMatch(/jb\.reversal_of_batch_id is null/);
    expect(migration).toMatch(/rb\.reversal_of_batch_id = jb\.id/);
  });

  it('records that it does not supersede the project-grain view consumed by Home', () => {
    expect(migration).toMatch(/DOES NOT SUPERSEDE/);
    expect(migration).toMatch(/sector_management_result_read/);
  });
});

describe('H1 result by currency — TypeScript contract', () => {
  it('offers no function or field that could total across currencies', () => {
    expect(contract).not.toMatch(/export function .*(total|sum|combined|aggregate)/i);
    expect(contract).not.toMatch(/reduce\(/);
    expect(contract).not.toMatch(/Number\(/);
  });

  it('derives every figure from the read model and performs no arithmetic', () => {
    expect(contract).not.toMatch(/BigInt\(/);
    expect(contract).not.toMatch(/\+\s*BigInt/);
    expect(contract).toMatch(/No arithmetic happens here/);
  });

  it('keeps "no result fact" distinct from "a result of zero"', () => {
    const empty = buildProjectResultView([]);
    expect(empty.hasResultFact).toBe(false);
    expect(empty.positions).toHaveLength(0);

    const zero = buildProjectResultView([rowIn('EGP', '0', '0', '0')]);
    expect(zero.hasResultFact).toBe(true);
    expect(zero.positions[0]?.result.amountMinorUnits).toBe('0');
  });

  it('fails closed on a malformed qualified object instead of inventing a result', () => {
    const broken = row({ management_result: { amount_minor_units: '7000000' } });
    const view = buildProjectResultView([broken, row()]);
    expect(view.unparseableRowCount).toBe(1);
    expect(view.positions).toHaveLength(1);
  });

  it('discloses a currency it cannot render instead of crashing or dropping it', () => {
    const unsupported = rowIn('XYZ', '5000000', '5000000', '0');
    const view = buildProjectResultView([unsupported, row()]);
    expect(view.positions.map((p) => p.currency)).toEqual(['EGP', 'XYZ']);
    expect(view.unsupportedCurrencyCount).toBe(1);
    // The amount is withheld rather than formatted, and no exception escapes.
    expect(view.positions[1]?.presentable).toBe(false);
    expect(view.positions[1]?.presentation.kind).toBe('SUPPRESSED');
  });

  it('binds each position to its own currency', () => {
    const view = buildProjectResultView([rowIn('USD', '400000', '400000', '0'), row()]);
    expect(view.positions.map((p) => p.currency)).toEqual(['EGP', 'USD']);
    expect(view.isMultiCurrency).toBe(true);
  });
});

describe('H1 result by currency — the dangerous multi-currency case', () => {
  // 5,000.000 OMR and 4,000.00 USD. Any combined figure is a number no ledger
  // supports: 5,400,000 in raw minor units.
  const omr = rowIn('OMR', '5000000', '5000000', '0');
  const usd = rowIn('USD', '400000', '400000', '0');

  it('produces two independently qualified positions', () => {
    const view = buildProjectResultView([usd, omr]);
    expect(view.positions.map((p) => p.currency)).toEqual(['OMR', 'USD']);
    expect(view.isMultiCurrency).toBe(true);
  });

  it('has no field anywhere on the view holding their sum', () => {
    const serialized = JSON.stringify(buildProjectResultView([usd, omr]));
    expect(serialized).not.toContain('5400000');
    expect(serialized).not.toContain('540000000');
  });

  it('renders each amount with its own currency and never the combined figure', () => {
    const { container } = render(
      <ResultPanel view={buildProjectResultView([usd, omr])} />,
    );
    const text = norm(container.textContent ?? '');

    expect(text).toContain('OMR');
    expect(text).toContain('USD');
    expect(text).toContain('٥٬٠٠٠٫٠٠٠ ر.ع.');
    expect(text).toContain('٤٬٠٠٠٫٠٠ US$');
    // The cross-currency sum must not appear in any rendering.
    expect(text).not.toContain('٥٬٤٠٠');
    expect(text).not.toContain('٩٬٠٠٠');
  });

  it('labels the multi-currency state and explains the absence of a total', () => {
    const { container } = render(
      <ResultPanel view={buildProjectResultView([usd, omr])} />,
    );
    const note = container.querySelector('[data-testid="result-multi-currency-note"]');
    expect(note?.textContent).toContain('عملات');
    expect(note?.textContent).toMatch(/لا يوجد إجمالي/);
  });

  it('attributes every result amount to a single currency', () => {
    const { container } = render(
      <ResultPanel view={buildProjectResultView([usd, omr])} />,
    );
    const amounts = [...container.querySelectorAll('[data-testid^="result-amount-"]')];
    expect(amounts).toHaveLength(2);
    expect(amounts.map((a) => a.getAttribute('data-currency'))).toEqual(['OMR', 'USD']);
    // Neither is attributed to a project reporting currency by assumption.
    expect(amounts.every((a) => a.getAttribute('data-currency') !== 'EGP')).toBe(true);
  });
});

describe('H1 result by currency — panel rendering', () => {
  it('renders an absence, not a zero, when there is no result fact', () => {
    const { container } = render(<ResultPanel view={buildProjectResultView([])} />);
    const empty = container.querySelector('[data-testid="result-empty"]');
    expect(empty).not.toBeNull();
    expect(empty?.textContent).toMatch(/لا نعرض\s+صفرًا/);
    // No fabricated zero anywhere in the panel.
    expect(norm(container.textContent ?? '')).not.toMatch(/[0٠][.,٫][0٠]{2,3}/);
  });

  it('renders a genuine zero result as a presentable zero, not as an absence', () => {
    const zero = buildProjectResultView([rowIn('EGP', '0', '0', '0')]);
    const { container } = render(<ResultPanel view={zero} />);
    expect(container.querySelector('[data-testid="result-empty"]')).toBeNull();
    const amount = container.querySelector('[data-testid="result-amount-EGP"]');
    expect(norm(amount?.textContent ?? '')).toContain('٠٫٠٠');
  });

  it('suppresses the amount when no cost is classified, and says why', () => {
    const unclassified = row({
      cost_classification_status: 'NONE',
      unclassified_eligible_minor_units: '3000000',
      result_deducted_cost_minor_units: '0',
      management_result: {
        ...(row().management_result as object),
        cost_classification_status: 'NONE',
      },
    });
    const { container } = render(
      <ResultPanel view={buildProjectResultView([unclassified])} />,
    );
    const suppressed = container.querySelector('[data-testid="result-suppressed-EGP"]');
    expect(suppressed).not.toBeNull();
    expect(suppressed?.textContent).toContain('—');
    // No amount is rendered for a suppressed result.
    expect(container.querySelector('[data-testid="result-amount-EGP"]')).toBeNull();
  });

  it('reports classification separately from deduction', () => {
    const { container } = render(<ResultPanel view={buildProjectResultView([row()])} />);
    const attributed = container.querySelector('[data-testid="result-attributed-EGP"]');
    const deducted = container.querySelector('[data-testid="result-deducted-EGP"]');
    // Attributed classification is 0 while the deduction is the 3000.00 overhead.
    expect(norm(attributed?.textContent ?? '')).toContain('٠٫٠٠');
    expect(norm(deducted?.textContent ?? '')).toContain('٣٬٠٠٠٫٠٠');
  });

  it('renders an unrenderable currency as an absence and discloses it', () => {
    const unsupported = rowIn('XYZ', '5000000', '5000000', '0');
    const { container } = render(
      <ResultPanel view={buildProjectResultView([unsupported])} />,
    );
    const text = norm(container.textContent ?? '');
    expect(text).toContain('XYZ');
    expect(text).toContain('—');
    expect(text).toMatch(/غير مدعومة/);
    // The fact is not zeroed or dropped.
    expect(text).not.toMatch(/[0٠][.,٫][0٠]{2,3}/);
  });

  it('uses the approved result term and no reserved vocabulary', () => {
    const { container } = render(<ResultPanel view={buildProjectResultView([row()])} />);
    const text = container.textContent ?? '';
    expect(text).toContain('نتيجة التشغيل الإدارية');
    for (const banned of ['ربح', 'أرباح', 'عائد']) {
      expect(text).not.toContain(banned);
    }
  });
});

describe('H1 result by currency — project page consumer', () => {
  it('no longer sums realized results across currencies', () => {
    expect(projectPage).not.toMatch(/reduce\(/);
    expect(projectPage).not.toMatch(/realized_result_minor_units/);
  });

  it('no longer reads the Real Estate disposal view as a generic project result', () => {
    expect(projectPage).not.toMatch(/getRealizedResults/);
    expect(projectPage).not.toMatch(/property_realized_result_read/);
  });

  it('consumes the per-currency qualified contract', () => {
    expect(projectPage).toMatch(/getProjectResultByCurrency/);
    expect(projectPage).toMatch(/buildProjectResultView/);
    expect(projectPage).toMatch(/<ResultPanel view=\{result\} \/>/);
  });

  it('renders the Result panel after Capital, in the brief order', () => {
    const capitalAt = projectPage.indexOf('<CapitalPanel');
    const resultAt = projectPage.indexOf('<ResultPanel');
    expect(capitalAt).toBeGreaterThan(0);
    expect(resultAt).toBeGreaterThan(capitalAt);
  });

  it('does not label a result with the project reporting currency', () => {
    // reporting_currency survives only as a project attribute in the header.
    expect(projectPage).not.toMatch(/formatMinorUnits\([^,]+,\s*currency\)/);
  });
});
