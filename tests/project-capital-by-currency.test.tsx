// @vitest-environment jsdom
import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render } from '@testing-library/react';
import {
  buildProjectCapitalView,
  presentCapitalAmount,
  parseCapitalPositions,
} from '@/features/funding/project-capital';
import { CapitalPanel } from '@/features/funding/capital-panel';

// The defect: `project_capital_position` summed commitment_terms, issued
// capital_call_lines and contributions ACROSS ALL CURRENCIES and stamped the
// total with `investment_projects.reporting_currency`. None of those three
// facts is constrained to the project currency — each is only checked against
// `^[A-Z]{3}$` — so the "committed" figure was 100,000,000 EGP + 5,000,000 OMR
// reported as 105,000,000 EGP. The structural guarantee is that no such figure
// exists to display, not merely that the UI declines to show one.
afterEach(() => cleanup());

/** Strip bidi marks so assertions can compare the digits that matter. */
const norm = (s: string) => s.replace(/[\u061c\u200e\u200f]/g, '');

const migration = readFileSync(
  'supabase/migrations/20260904010500_h1_project_capital_by_currency.sql',
  'utf8',
);
const contract = readFileSync('src/features/funding/project-capital.ts', 'utf8');
const panel = readFileSync('src/features/funding/capital-panel.tsx', 'utf8');
const projectPage = readFileSync('src/app/(app)/projects/[projectId]/page.tsx', 'utf8');

const columnBlock = (() => {
  const start = migration.indexOf('select\n  cur.organization_id,');
  const end = migration.indexOf('from currencies cur');
  if (start < 0 || end < 0) throw new Error('could not locate the projection column list');
  return migration.slice(start, end);
})();

const row = (over: Record<string, unknown> = {}) => ({
  organization_id: '00b00000-0000-4000-8000-000000000001',
  project_id: '00b00000-0000-4000-8000-000000000002',
  currency: 'EGP',
  committed_minor_units: '100000000',
  called_minor_units: '25000000',
  contributed_minor_units: '15000000',
  receivable_minor_units: '10000000',
  uncalled_minor_units: '75000000',
  call_line_count: 1,
  ...over,
});

describe('H1 capital by currency — SQL contract', () => {
  it('groups every rollforward fact by its own currency, so no row can mix them', () => {
    // commitment_terms, capital_call_lines and contributions each carry their
    // own currency; each is aggregated per currency and never combined.
    expect(migration).toMatch(/group by ct\.organization_id, av\.project_id, ct\.currency/);
    expect(migration).toMatch(/group by ccl\.organization_id, cc\.project_id, ccl\.currency/);
    expect(migration).toMatch(/group by c\.organization_id, av\.project_id, c\.currency/);
    // The final projection joins on currency, so a row cannot mix them.
    expect(migration).toMatch(/and cl\.currency = cur\.currency/);
    expect(migration).toMatch(/and p\.currency = cur\.currency/);
  });

  it('exposes no column representing a total across currencies', () => {
    expect(columnBlock).not.toMatch(/total|combined|converted|consolidat|all_currencies/i);
  });

  it('exposes no FX conversion', () => {
    expect(migration).not.toMatch(/fx_rate|exchange_rate/i);
  });

  it('emits exact minor units as text, never a rounded number', () => {
    expect(migration).toMatch(/sum\(c\.contribution_minor_units\)/);
    expect(migration).toMatch(/::text\s+as contributed_minor_units/);
  });

  it('counts only ISSUED call lines, so a cancelled call cannot inflate "called"', () => {
    expect(migration).toMatch(/where cc\.status = 'ISSUED'/);
  });

  it('records that it does not supersede the project-grain view, which close gates consume', () => {
    expect(migration).toMatch(/not superseded/i);
    expect(migration).toMatch(/PARTNER_CAPITAL_ROLLFORWARD/);
  });
});

describe('H1 capital by currency — TypeScript contract', () => {
  it('offers no function or field that could total across currencies', () => {
    expect(contract).not.toMatch(/export function .*(total|sum|combined|aggregate)/i);
    expect(contract).not.toMatch(/reduce\(/);
  });

  it('exposes money only through a branded type paired with its currency', () => {
    // The amount is unreachable without the currency: there is no public
    // `amount` string on the view, and the brand prevents a bare string.
    expect(contract).toMatch(/readonly __brand: 'CapitalAmount'/);
    expect(contract).toMatch(/type CapitalPositionView = \{[\s\S]*committed: CapitalAmount/);
  });

  it('keeps "no capital structure" distinct from "zero contributed"', () => {
    const empty = buildProjectCapitalView([]);
    expect(empty.hasCapitalStructure).toBe(false);
    expect(empty.positions).toHaveLength(0);

    const settled = buildProjectCapitalView([
      row({
        contributed_minor_units: '0',
        called_minor_units: '0',
        called_line_count: undefined,
        call_line_count: 0,
      }),
    ]);
    expect(settled.hasCapitalStructure).toBe(true);
    expect(settled.positions[0]?.hasIssuedCall).toBe(false);
  });

  it('fails closed on a malformed row instead of inventing a zero', () => {
    const { positions, unparseableRowCount } = parseCapitalPositions([
      row({ currency: 'egp' }), // not ISO-4217 upper-case
      row({ committed_minor_units: '1.5' }), // not exact integer text
      row(),
    ]);
    expect(unparseableRowCount).toBe(2);
    expect(positions).toHaveLength(1);
  });

  it('renders an amount only together with its currency', () => {
    const view = buildProjectCapitalView([row()]);
    const amount = view.positions[0]!.committed;
    // The currency symbol is part of the rendered string; the branded type
    // makes it impossible to format a figure whose currency was left behind.
    expect(norm(presentCapitalAmount(amount))).toBe('١٬٠٠٠٬٠٠٠٫٠٠ ج.م');
    expect(amount.currency).toBe('EGP');
  });

  // A well-formed ISO-4217 code the money module cannot render is a real
  // commitment that cannot be printed. `currencyDecimals` throws on it, so the
  // contract must absorb that: disclose the row, render an absence, do not
  // crash the brief and do not drop the fact.
  it('keeps a row in an unrenderable currency, disclosed and not dropped', () => {
    const view = buildProjectCapitalView([row({ currency: 'XYZ' }), row()]);
    expect(view.positions.map((p) => p.currency)).toEqual(['EGP', 'XYZ']);
    expect(view.unsupportedCurrencyCount).toBe(1);
    expect(view.positions[1]!.presentable).toBe(false);
  });

  it('renders an unrenderable amount as an absence instead of throwing', () => {
    const view = buildProjectCapitalView([row({ currency: 'XYZ' })]);
    const amount = view.positions[0]!.committed;
    expect(() => presentCapitalAmount(amount)).not.toThrow();
    expect(presentCapitalAmount(amount)).toBe('—');
  });

  it('renders an unsupported-currency row as an absence in the panel, not a zero', () => {
    const { container } = render(
      <CapitalPanel view={buildProjectCapitalView([row({ currency: 'XYZ' })])} />,
    );
    const text = norm(container.textContent ?? '');
    expect(text).toContain('XYZ');
    expect(text).toContain('—');
    // The figure is not silently zeroed or dropped.
    expect(text).toMatch(/غير مدعومة/);
    expect(text).not.toMatch(/[0٠][.,٫][0٠]{2,3}/);
  });
});

describe('H1 capital by currency — the dangerous multi-currency case', () => {
  // A project holding OMR and USD positions must produce two independently
  // labelled rows, with no API or read-model field representing their sum.
  const omr = row({
    currency: 'OMR',
    committed_minor_units: '5000000',
    called_minor_units: '1000000',
    contributed_minor_units: '250000',
    receivable_minor_units: '750000',
    uncalled_minor_units: '4000000',
  });
  const usd = row({
    currency: 'USD',
    committed_minor_units: '400000',
    called_minor_units: '400000',
    contributed_minor_units: '400000',
    receivable_minor_units: '0',
    uncalled_minor_units: '0',
  });

  it('produces two independently labelled rows', () => {
    const view = buildProjectCapitalView([usd, omr]);
    expect(view.positions.map((p) => p.currency)).toEqual(['OMR', 'USD']);
    expect(view.isMultiCurrency).toBe(true);
  });

  it('has no field anywhere on the view holding their sum', () => {
    const view = buildProjectCapitalView([usd, omr]);
    const serialized = JSON.stringify(view);
    // 5,000,000 OMR + 400,000 USD = 5,400,000 — a number no ledger supports.
    expect(serialized).not.toContain('5400000');
    expect(serialized).not.toContain('540000000');
  });

  it('renders every figure with its own currency and never the combined total', () => {
    const { container } = render(
      <CapitalPanel view={buildProjectCapitalView([usd, omr])} />,
    );
    const text = norm(container.textContent ?? '');

    expect(text).toContain('OMR');
    expect(text).toContain('USD');
    // 5,000.000 OMR and 4,000.00 USD, each rendered with its own currency.
    expect(text).toContain('٥٬٠٠٠٫٠٠٠ ر.ع.');
    expect(text).toContain('٤٬٠٠٠٫٠٠ US$');
    // The cross-currency sums — 5,400,000 committed, 650,000 contributed —
    // are numbers no ledger supports and must not appear anywhere.
    expect(text).not.toContain('٥٬٤٠٠٫٠٠٠');
    expect(text).not.toContain('٦٥٠٫٠٠٠');
  });

  it('attributes every money cell to a single currency', () => {
    const { container } = render(
      <CapitalPanel view={buildProjectCapitalView([usd, omr])} />,
    );
    const cells = [...container.querySelectorAll('td[data-currency]')];
    // 5 money columns × 2 currencies, each labelled with its own currency.
    expect(cells).toHaveLength(10);
    expect(new Set(cells.map((c) => c.getAttribute('data-currency')))).toEqual(
      new Set(['OMR', 'USD']),
    );
    // No cell is attributed to the project reporting currency by assumption.
    expect(cells.every((c) => c.getAttribute('data-currency') !== 'EGP')).toBe(true);
  });

  it('labels the multi-currency state and explains the absence of a total', () => {
    const { container } = render(
      <CapitalPanel view={buildProjectCapitalView([usd, omr])} />,
    );
    const note = container.querySelector('[data-testid="capital-multi-currency-note"]');
    expect(note?.textContent).toContain('عملات');
    expect(note?.textContent).toMatch(/لا يوجد إجمالي/);
  });
});

describe('H1 capital by currency — panel rendering', () => {
  it('renders an absence, not a zero, when there is no capital structure', () => {
    const { container } = render(<CapitalPanel view={buildProjectCapitalView([])} />);
    const empty = container.querySelector('[data-testid="capital-empty"]');
    expect(empty).not.toBeNull();
    expect(empty?.textContent).toMatch(/لا نعرض أصفارًا/);
    // No fabricated zero anywhere in the panel, in either digit form.
    expect(norm(container.textContent ?? '')).not.toMatch(/[0٠][.,٫][0٠]{2,3}/);
  });

  it('distinguishes "committed but never called" from "called and unpaid"', () => {
    const { container } = render(
      <CapitalPanel view={buildProjectCapitalView([row({ call_line_count: 0 })])} />,
    );
    expect(container.textContent).toMatch(/لم يُستدعَ/);
  });

  it('surfaces rows rejected by the parser rather than dropping them silently', () => {
    const view = buildProjectCapitalView([row({ currency: 'x' }), row()]);
    expect(view.unparseableRowCount).toBe(1);
    const { container } = render(<CapitalPanel view={view} />);
    const alert = container.querySelector('[role="alert"]');
    expect(alert?.textContent).toContain('1');
  });
});

describe('H1 capital by currency — project page consumer', () => {
  it('consumes the per-currency contract, not the project-grain total', () => {
    expect(projectPage).toMatch(/getProjectCapitalByCurrency/);
    expect(projectPage).not.toMatch(/getProjectCapitalPosition/);
  });

  it('no longer manufactures a zero where the capital answer is missing', () => {
    expect(projectPage).not.toMatch(/\?\?\s*'0'/);
  });

  it('renders the Capital panel as the first panel of the brief', () => {
    expect(projectPage).toMatch(/<CapitalPanel view=\{capital\} \/>/);
    expect(projectPage).not.toMatch(/position\?\.contributed_minor_units/);
  });

  it('does not reduce capital rows across currencies', () => {
    expect(projectPage).not.toMatch(/capital(?:Rows)?\.reduce\(/);
  });
});
