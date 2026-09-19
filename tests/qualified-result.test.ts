import { describe, expect, it } from 'vitest';
import {
  BASIS_LABEL_AR,
  COST_CLASSIFICATION_LABEL_AR,
  containsReservedTerm,
  isResultComparable,
  parseQualifiedResult,
  presentQualifiedResult,
  qualifiedResultViewFromRow,
  toQualifiedResultView,
  unclassifiedCaveatAr,
  RESULT_TERM_AR,
} from '@/features/result/qualified-result';

const exact = (minorUnits: string, currency: string) => `${minorUnits} ${currency}`;

const result = (overrides: Record<string, unknown> = {}) => ({
  amount_minor_units: '500000',
  currency: 'EGP',
  basis: 'AGRICULTURE_ENTERPRISE_OPERATING',
  cost_classification_status: 'COMPLETE',
  evidence_status: 'COMPLETE',
  policy_availability: ['COGS_NOT_RECOGNIZED'],
  as_of: '2026-09-04',
  ...overrides,
});

describe('qualified result contract', () => {
  it('parses a well-formed result object', () => {
    expect(parseQualifiedResult(result())).toMatchObject({ amount_minor_units: '500000' });
  });

  it('fails closed when the amount is not exact integer text', () => {
    expect(() => parseQualifiedResult(result({ amount_minor_units: 500000 }))).toThrow(
      /qualified-result contract/,
    );
    expect(() => parseQualifiedResult(result({ amount_minor_units: '5000.00' }))).toThrow(
      /qualified-result contract/,
    );
  });

  it('fails closed when a qualification is missing', () => {
    for (const key of ['currency', 'basis', 'cost_classification_status', 'evidence_status', 'as_of']) {
      const broken: Record<string, unknown> = result();
      delete broken[key];
      expect(() => parseQualifiedResult(broken), `missing ${key}`).toThrow(
        /qualified-result contract/,
      );
    }
  });

  it('fails closed on an unknown basis or status rather than defaulting', () => {
    expect(() => parseQualifiedResult(result({ basis: '' }))).toThrow();
    expect(() => parseQualifiedResult(result({ cost_classification_status: 'FINE' }))).toThrow();
  });
});

describe('comparability gate', () => {
  const view = (status: string, unclassified: string | null = '0') =>
    toQualifiedResultView(parseQualifiedResult(result({ cost_classification_status: status })), unclassified);

  it('treats a fully classified result as comparable', () => {
    expect(isResultComparable(view('COMPLETE'))).toBe(true);
  });

  it('treats a project with no operating cost as comparable', () => {
    expect(isResultComparable(view('NOT_APPLICABLE_NO_OPERATING_COST'))).toBe(true);
  });

  it('does not treat a partially classified result as fully comparable', () => {
    expect(isResultComparable(view('PARTIAL'))).toBe(false);
  });

  it('never treats an entirely unclassified result as comparable', () => {
    expect(isResultComparable(view('NONE'))).toBe(false);
  });
});

describe('presentation never yields an unlabelled amount', () => {
  it('returns the amount together with a caption carrying basis and coverage', () => {
    const view = toQualifiedResultView(parseQualifiedResult(result()));
    const presented = presentQualifiedResult(view, exact);
    expect(presented.kind).toBe('PRESENTABLE');
    if (presented.kind !== 'PRESENTABLE') throw new Error('expected presentable');
    expect(presented.amountText).toBe('500000 EGP');
    expect(presented.captionAr).toContain(BASIS_LABEL_AR.AGRICULTURE_ENTERPRISE_OPERATING);
    expect(presented.captionAr).toContain(COST_CLASSIFICATION_LABEL_AR.COMPLETE);
    expect(presented.tone).toBe('ok');
  });

  it('suppresses the amount entirely when no cost has been classified', () => {
    const view = toQualifiedResultView(
      parseQualifiedResult(result({ cost_classification_status: 'NONE' })),
      '400000',
    );
    const presented = presentQualifiedResult(view, exact);
    expect(presented.kind).toBe('SUPPRESSED');
    if (presented.kind !== 'SUPPRESSED') throw new Error('expected suppressed');
    // The whole point: there is no amount field to render.
    expect(presented).not.toHaveProperty('amountText');
    expect(presented.reasonAr).toContain('400000 EGP');
  });

  it('flags a partially classified result as caution rather than hiding or blessing it', () => {
    const view = toQualifiedResultView(
      parseQualifiedResult(result({ cost_classification_status: 'PARTIAL' })),
      '120000',
    );
    const presented = presentQualifiedResult(view, exact);
    expect(presented.kind).toBe('PRESENTABLE');
    if (presented.kind !== 'PRESENTABLE') throw new Error('expected presentable');
    expect(presented.tone).toBe('caution');
  });

  it('states the size of the unclassified gap, not merely its existence', () => {
    const view = toQualifiedResultView(parseQualifiedResult(result()), '275000');
    expect(unclassifiedCaveatAr(view, exact)).toContain('275000 EGP');
  });

  it('stays silent about an unclassified gap of zero', () => {
    const view = toQualifiedResultView(parseQualifiedResult(result()), '0');
    expect(unclassifiedCaveatAr(view, exact)).toBeNull();
  });
});

describe('row parsing', () => {
  it('reads a project_operating_result_read row and carries the unclassified amount', () => {
    const view = qualifiedResultViewFromRow({
      management_result: result({ cost_classification_status: 'PARTIAL' }),
      unclassified_eligible_minor_units: '90000',
    });
    expect(view.unclassifiedMinorUnits).toBe('90000');
    expect(view.costClassificationStatus).toBe('PARTIAL');
    expect(view.policyNotesAr).toContain('تكلفة المبيعات غير معترف بها محاسبيًا لهذا القطاع');
  });

  it('refuses a row whose object is not the qualified contract', () => {
    expect(() => qualifiedResultViewFromRow({ management_result: { amount_minor_units: '5' } })).toThrow(
      /qualified-result contract/,
    );
  });
});

describe('reserved terminology (ADR 0034 §2.2)', () => {
  it('detects reserved investor-return vocabulary', () => {
    expect(containsReservedTerm('investor return')).toBe('investor return');
    expect(containsReservedTerm('MOIC')).toBe('MOIC');
    expect(containsReservedTerm('عائد المستثمر')).toBe('عائد');
  });

  it('uses none of it in the surface vocabulary it owns', () => {
    const surface = [
      RESULT_TERM_AR,
      ...Object.values(BASIS_LABEL_AR),
      ...Object.values(COST_CLASSIFICATION_LABEL_AR),
    ];
    for (const text of surface) {
      expect(containsReservedTerm(text), text).toBeNull();
    }
  });
});
