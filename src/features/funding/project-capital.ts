// Project capital contract — the TypeScript half of the Capital panel.
//
// The project-grain view this replaces summed commitment_terms,
// capital_call_lines and contributions ACROSS ALL CURRENCIES and stamped the
// total with `investment_projects.reporting_currency`. None of those three
// facts is constrained to the project currency; each is only checked against
// `^[A-Z]{3}$`.
//
// So there is no such thing as "the" committed amount for a project. There is a
// committed amount IN a currency. The discipline from `qualified-result.ts` is
// reproduced here:
//
//   * A row is only ever addressable together with its currency — the money
//     fields are NOT exposed as plain strings on the parsed view.
//   * The only way to obtain displayable money text is
//     `presentCapitalAmount()`, which returns the amount and its currency
//     together, or refuses to return an amount at all.
//   * There is deliberately NO function here that totals across currencies, and
//     no field that could hold such a total. Adding one is a decision, not a
//     refactor: it requires a policy-defined conversion rate (BD-005).
//
// "No row" and "zero" are different answers and stay different: an empty
// result means the project has no capital structure, not that it has zero
// committed. Callers branch on `hasCapitalStructure`, never on a zero-valued
// fallback that they manufactured themselves.

import { z } from 'zod';
import { MONEY_CURRENCIES, formatMinorUnits } from '@/shared/money';

/** Money is transported as decimal text so no integer is ever rounded in transit. */
const exactIntegerText = z.string().regex(/^-?\d+$/, 'money must be exact integer text');

const currencyCode = z.string().regex(/^[A-Z]{3}$/, 'currency must be an ISO-4217 code');

/**
 * The database accepts any well-formed ISO-4217 code; the money module renders
 * only a known set and throws on the rest. A row in an unrenderable currency is
 * still a real commitment, so it is kept and disclosed rather than dropped —
 * and it must not take the panel down with it.
 */
export function isSupportedCurrency(currency: string): boolean {
  return Object.prototype.hasOwnProperty.call(MONEY_CURRENCIES, currency);
}

export const capitalPositionSchema = z.object({
  organization_id: z.string().uuid(),
  project_id: z.string().uuid(),
  currency: currencyCode,
  committed_minor_units: exactIntegerText,
  called_minor_units: exactIntegerText,
  contributed_minor_units: exactIntegerText,
  receivable_minor_units: exactIntegerText,
  uncalled_minor_units: exactIntegerText,
  call_line_count: z.number().int().nonnegative(),
});

export type CapitalPosition = z.infer<typeof capitalPositionSchema>;

/**
 * A single money figure that can never be separated from its currency.
 *
 * The amount is not a public field: it is only reachable through
 * `presentCapitalAmount()`, which renders amount and currency as one string.
 */
export type CapitalAmount = {
  readonly __brand: 'CapitalAmount';
  readonly minorUnits: string;
  readonly currency: string;
};

function capitalAmount(minorUnits: string, currency: string): CapitalAmount {
  return { __brand: 'CapitalAmount', minorUnits, currency };
}

/**
 * The only way to turn a capital figure into displayable text.
 *
 * It accepts a `CapitalAmount`, so it is impossible to format a figure whose
 * currency was not carried along with it. `formatMinorUnits` renders the
 * currency as part of the string and returns '—' for anything not exactly
 * representable, so an unrepresentable amount is visibly absent rather than
 * rounded into a plausible number.
 */
export function presentCapitalAmount(amount: CapitalAmount): string {
  // `currencyDecimals` throws on an unknown code; a capital row is not a
  // licence to crash the brief, so an unrenderable currency renders as an
  // absence and is disclosed by `unsupportedCurrencyCount`.
  if (!isSupportedCurrency(amount.currency)) return '—';
  return formatMinorUnits(amount.minorUnits, amount.currency);
}

/**
 * One currency's capital position. Field accessors return `CapitalAmount`, and
 * there is no accessor that could combine two rows.
 */
export type CapitalPositionView = {
  readonly currency: string;
  readonly committed: CapitalAmount;
  readonly called: CapitalAmount;
  readonly contributed: CapitalAmount;
  readonly receivable: CapitalAmount;
  readonly uncalled: CapitalAmount;
  /** ISSUED call lines only; a CANCELLED call contributes neither. */
  readonly callLineCount: number;
  /**
   * False when the currency is well-formed but the money module cannot render
   * it exactly. The commitment is real; only its presentation is blocked.
   */
  readonly presentable: boolean;
  /**
   * True when a call has been issued in this currency. Distinguishes
   * "committed but never called" from "called and nothing received", both of
   * which report a contributed amount of zero.
   */
  readonly hasIssuedCall: boolean;
};

/**
 * Parse database rows into per-currency views.
 *
 * Fails closed on a malformed row: an unparseable row is dropped and reported
 * rather than silently becoming a zero. Callers must surface
 * `unparseableRowCount` — dropping it is how a currency disappears unnoticed.
 */
export function parseCapitalPositions(
  rows: readonly unknown[],
): { positions: CapitalPositionView[]; unparseableRowCount: number } {
  const positions: CapitalPositionView[] = [];
  let unparseableRowCount = 0;

  for (const row of rows) {
    const parsed = capitalPositionSchema.safeParse(row);
    if (!parsed.success) {
      unparseableRowCount += 1;
      continue;
    }
    const p = parsed.data;
    positions.push({
      currency: p.currency,
      committed: capitalAmount(p.committed_minor_units, p.currency),
      called: capitalAmount(p.called_minor_units, p.currency),
      contributed: capitalAmount(p.contributed_minor_units, p.currency),
      receivable: capitalAmount(p.receivable_minor_units, p.currency),
      uncalled: capitalAmount(p.uncalled_minor_units, p.currency),
      callLineCount: p.call_line_count,
      hasIssuedCall: p.call_line_count > 0,
      presentable: isSupportedCurrency(p.currency),
    });
  }

  // Stable, currency-alphabetical order: the panel order must not depend on
  // whatever order the database happened to return.
  positions.sort((a, b) => a.currency.localeCompare(b.currency));
  return { positions, unparseableRowCount };
}

/**
 * The Capital panel's answer for one project.
 *
 * `hasCapitalStructure` is false only when the project has no capital row at
 * all. That is NOT the same as having a row whose contributed amount is zero,
 * and callers must branch on it before rendering any figure.
 */
export type ProjectCapitalView = {
  readonly hasCapitalStructure: boolean;
  readonly positions: readonly CapitalPositionView[];
  /** Rows the parser rejected. Never zero in a healthy deployment. */
  readonly unparseableRowCount: number;
  /** Rows in a currency that cannot be rendered exactly. Disclosed, not dropped. */
  readonly unsupportedCurrencyCount: number;
  /** True when the project holds capital in more than one currency. */
  readonly isMultiCurrency: boolean;
};

export function buildProjectCapitalView(rows: readonly unknown[]): ProjectCapitalView {
  const { positions, unparseableRowCount } = parseCapitalPositions(rows);
  return {
    hasCapitalStructure: positions.length > 0,
    positions,
    unparseableRowCount,
    unsupportedCurrencyCount: positions.filter((p) => !p.presentable).length,
    isMultiCurrency: positions.length > 1,
  };
}
