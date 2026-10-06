import { describe, expect, it } from 'vitest';
import {
  addSameCurrency,
  isRenderableCurrency,
  presentRollup,
  totalsByCurrency,
  type CurrencyRollup,
} from '../src/shared/money/by-currency';

/**
 * The domain guarantee under test is negative: a page must not be able to state
 * a total that adds amounts in two currencies. Every assertion below is written
 * so that it fails if someone reintroduces a scalar-summing helper.
 */

type Row = { currency: string | null | undefined; amount: string | null };

const currencyOf = (row: Row) => row.currency;
const amountOf = (row: Row) => row.amount;

describe('currency-safe roll-up — refuses invalid aggregation', () => {
  it('does not add EGP to OMR, and reports both currencies separately', () => {
    // The historical defect: 100,000,000.00 EGP + 5,000,000.000 OMR surfaced
    // as `105,000,000` under the project's reporting currency.
    const rows: Row[] = [
      { currency: 'EGP', amount: '10000000000' }, // 100,000,000.00 EGP
      { currency: 'OMR', amount: '5000000000' }, // 5,000,000.000 OMR
    ];
    const { totals, isMultiCurrency } = totalsByCurrency(rows, currencyOf, amountOf);

    expect(totals).toHaveLength(2);
    expect(isMultiCurrency).toBe(true);
    expect(totals.map((t) => t.currency)).toEqual(['EGP', 'OMR']);
    expect(totals.find((t) => t.currency === 'EGP')?.minorUnits).toBe(10_000_000_000n);
    expect(totals.find((t) => t.currency === 'OMR')?.minorUnits).toBe(5_000_000_000n);
    // No member of the result is 105000000 in any scale.
    expect(totals.map((t) => t.minorUnits.toString())).not.toContain('105000000');
  });

  it('has no return path that yields a single combined scalar', () => {
    const { totals } = totalsByCurrency(
      [
        { currency: 'EGP', amount: '1' },
        { currency: 'USD', amount: '1' },
      ],
      currencyOf,
      amountOf,
    );
    // The result is a list keyed by currency; there is no aggregate field.
    expect(Array.isArray(totals)).toBe(true);
    expect(Object.keys(totals[0])).toEqual(['currency', 'minorUnits', 'rowCount', 'presentable']);
    // Two rows of 1 never appear as a combined 2: there is no member to hold it.
    expect(totals.map((t) => t.minorUnits)).toEqual([1n, 1n]);
  });

  it('rejects adding two roll-ups in different currencies', () => {
    const egp: CurrencyRollup = { currency: 'EGP', minorUnits: 1n, rowCount: 1, presentable: true };
    const omr: CurrencyRollup = { currency: 'OMR', minorUnits: 1n, rowCount: 1, presentable: true };
    expect(() => addSameCurrency(egp, omr)).toThrow(/refusing to add EGP to OMR/);
  });

  it('adds two roll-ups in the same currency', () => {
    const a: CurrencyRollup = { currency: 'EGP', minorUnits: 100n, rowCount: 1, presentable: true };
    const b: CurrencyRollup = { currency: 'EGP', minorUnits: 250n, rowCount: 2, presentable: true };
    expect(addSameCurrency(a, b)).toEqual({
      currency: 'EGP',
      minorUnits: 350n,
      rowCount: 3,
      presentable: true,
    });
  });

  it('keeps a missing currency in its own bucket instead of adopting a real one', () => {
    const rows: Row[] = [
      { currency: 'EGP', amount: '100' },
      { currency: null, amount: '100' },
      { currency: undefined, amount: '100' },
      { currency: '', amount: '100' },
    ];
    const { totals } = totalsByCurrency(rows, currencyOf, amountOf);
    expect(totals.map((t) => t.currency)).toEqual(['', 'EGP']);
    expect(totals.find((t) => t.currency === '')?.minorUnits).toBe(300n);
    expect(totals.find((t) => t.currency === 'EGP')?.minorUnits).toBe(100n);
    expect(totals.find((t) => t.currency === '')?.presentable).toBe(false);
  });

  it('treats a malformed currency as unrenderable rather than as a known one', () => {
    const { totals } = totalsByCurrency(
      [
        { currency: 'egp', amount: '100' },
        { currency: 'US', amount: '100' },
      ],
      currencyOf,
      amountOf,
    );
    expect(totals.every((t) => !t.presentable)).toBe(true);
    expect(totals.map((t) => presentRollup(t))).toEqual(['—', '—']);
    expect(isRenderableCurrency('EGP')).toBe(true);
    expect(isRenderableCurrency('OMR')).toBe(true);
    expect(isRenderableCurrency('XYZ')).toBe(false);
  });

  it('fails closed on a non-integer amount instead of counting it as zero', () => {
    const { totals, unparseableRowCount } = totalsByCurrency(
      [
        { currency: 'EGP', amount: '100' },
        { currency: 'EGP', amount: '1.5' },
        { currency: 'EGP', amount: 'not money' },
      ],
      currencyOf,
      amountOf,
    );
    expect(unparseableRowCount).toBe(2);
    expect(totals).toHaveLength(1);
    // The surviving total is exactly the one parsable row — not 101.5, and not
    // 100 with the bad rows silently contributing zero to the row count.
    expect(totals[0].minorUnits).toBe(100n);
    expect(totals[0].rowCount).toBe(1);
  });

  it('counts a null amount as a real row of its currency', () => {
    const { totals, unparseableRowCount } = totalsByCurrency(
      [
        { currency: 'EGP', amount: '100' },
        { currency: 'EGP', amount: null },
      ],
      currencyOf,
      amountOf,
    );
    expect(unparseableRowCount).toBe(0);
    expect(totals[0]).toEqual({ currency: 'EGP', minorUnits: 100n, rowCount: 2, presentable: true });
  });

  it('renders amount and currency together, and never a bare number', () => {
    // formatMinorUnits renders the currency as its symbol, so the check is that
    // the symbol is present, that the two currencies render differently, and
    // that the scale difference (EGP 2dp, OMR 3dp) survives.
    const { totals } = totalsByCurrency(
      [
        { currency: 'OMR', amount: '5000000000' }, // 5,000,000.000 OMR
        { currency: 'EGP', amount: '10000000000' }, // 100,000,000.00 EGP
      ],
      currencyOf,
      amountOf,
    );
    const byCurrency = new Map(totals.map((t) => [t.currency, presentRollup(t)]));
    const egp = byCurrency.get('EGP') ?? '';
    const omr = byCurrency.get('OMR') ?? '';

    expect(egp).not.toBe(omr);
    // Currency identity is part of the string: neither is a bare digit run.
    expect(egp).not.toBe('١٠٠٬٠٠٠٬٠٠٠٫٠٠');
    expect(omr).not.toBe('٥٬٠٠٠٬٠٠٠٫٠٠٠');
    expect(egp.length).toBeGreaterThan('١٠٠٬٠٠٠٬٠٠٠٫٠٠'.length);
    expect(omr.length).toBeGreaterThan('٥٬٠٠٠٬٠٠٠٫٠٠٠'.length);
    // The three-decimal minor unit is not truncated to two.
    expect(omr).toMatch(/٫٠٠٠\s/);
    expect(egp).toMatch(/٫٠٠\s/);
  });

  it('is order-independent and empty-safe', () => {
    const rows: Row[] = [
      { currency: 'USD', amount: '5' },
      { currency: 'EGP', amount: '5' },
    ];
    expect(totalsByCurrency(rows, currencyOf, amountOf).totals.map((t) => t.currency)).toEqual([
      'EGP',
      'USD',
    ]);
    expect(totalsByCurrency([], currencyOf, amountOf)).toEqual({
      totals: [],
      unparseableRowCount: 0,
      isMultiCurrency: false,
    });
  });

  it('accepts bigint amounts without going through a float', () => {
    const big = 10n ** 30n;
    const { totals } = totalsByCurrency(
      [{ currency: 'EGP', amount: big }],
      (row: { currency: string; amount: bigint }) => row.currency,
      (row: { currency: string; amount: bigint }) => row.amount,
    );
    expect(totals[0].minorUnits).toBe(big);
  });
});
