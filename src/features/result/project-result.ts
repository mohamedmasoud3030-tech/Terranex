// Project result contract — the TypeScript half of the Result panel.
//
// The live defect: the project page summed `property_realized_result_read
// .realized_result_minor_units` across every recognition row and stamped the
// total with `investment_projects.reporting_currency`. That view is S4 Real
// Estate only, so an Agriculture project — which has no rows in it at all —
// reported a confident 0.00 as its result.
//
// The replacement is per currency, because there is no FX contract anywhere in
// this repository. A project whose revenue and cost are posted in two
// currencies has two results, not one combined figure.
//
// This file adds NO new result semantics. The qualified object, its basis,
// coverage and policy vocabulary, and the rule that an amount may only be
// displayed through `presentQualifiedResult` are all inherited from
// `qualified-result.ts`. What is added here is the currency partition and the
// states that go with it: no result fact, a real zero, and a currency the
// formatter cannot render.

import { MONEY_CURRENCIES } from '@/shared/money';
import type { ProjectResultByCurrencyRow } from './queries';
import {
  parseQualifiedResult,
  presentQualifiedResult,
  toQualifiedResultView,
  type QualifiedResultPresentation,
  type QualifiedResultView,
} from './qualified-result';

/**
 * A well-formed ISO-4217 code the money module cannot render is a real result
 * that cannot be printed. `currencyDecimals` throws on it, so the contract
 * absorbs that: the row is kept and disclosed rather than crashing the brief.
 */
export function isSupportedCurrency(currency: string): boolean {
  return Object.prototype.hasOwnProperty.call(MONEY_CURRENCIES, currency);
}

/** One currency's qualified management operating result. */
export type ProjectResultPosition = {
  /** The currency of the posted facts, never assumed to be the reporting one. */
  readonly currency: string;
  /** The qualified result. There is no amount here outside `presentation`. */
  readonly result: QualifiedResultView;
  /** How the result may be displayed. `SUPPRESSED` carries no amount at all. */
  readonly presentation: QualifiedResultPresentation;
  /** False when the currency cannot be rendered exactly. Disclosed, not dropped. */
  readonly presentable: boolean;

  // Reconciliation figures, exact integer text, all in this row's currency.
  /** The revenue term: disposal + rental for Real Estate, else sale revenue. */
  readonly resultRevenueMinorUnits: string;
  /** DEDUCTION: what the arithmetic actually subtracts. */
  readonly resultDeductedCostMinorUnits: string;
  /** CLASSIFICATION: cost attributed to an operating unit. Not the deduction. */
  readonly attributedOperatingCostMinorUnits: string;
  /** Attributed cost that is SELLING: classified once, deducted zero times. */
  readonly sellingCostAttributedMinorUnits: string;
  readonly projectOverheadMinorUnits: string;
  readonly unclassifiedEligibleMinorUnits: string;
};

/**
 * The Result panel's answer for one project.
 *
 * `hasResultFact` is false only when the project has no result row at all.
 * That is NOT the same as a row whose amount is zero, and callers must branch
 * on it before rendering any figure.
 */
export type ProjectResultView = {
  readonly hasResultFact: boolean;
  readonly positions: readonly ProjectResultPosition[];
  /** Rows rejected by the qualified-result contract. Never non-zero normally. */
  readonly unparseableRowCount: number;
  /** Rows in a currency that cannot be rendered exactly. Disclosed, not dropped. */
  readonly unsupportedCurrencyCount: number;
  readonly isMultiCurrency: boolean;
};

/**
 * Build the view from raw rows.
 *
 * No arithmetic happens here: the amount, the deduction and the classification
 * buckets all come from the read model. This function only partitions by
 * currency and decides what may be displayed.
 */
export function buildProjectResultView(rows: readonly unknown[]): ProjectResultView {
  const positions: ProjectResultPosition[] = [];
  let unparseableRowCount = 0;

  for (const raw of rows) {
    const row = raw as ProjectResultByCurrencyRow;
    let result: QualifiedResultView;
    try {
      result = toQualifiedResultView(
        parseQualifiedResult(row.management_result),
        row.unclassified_eligible_minor_units ?? null,
      );
    } catch {
      // A result whose shape is not the one ADR 0034 defines is an error, not a
      // default: drop it and report it rather than rendering a bare number.
      unparseableRowCount += 1;
      continue;
    }

    // `presentQualifiedResult` formats the amount, and formatting throws on a
    // currency the money module does not support. An unrenderable currency is
    // therefore decided BEFORE presentation is attempted: the row is kept, the
    // amount is withheld, and the fact is disclosed rather than crashing.
    const presentable = isSupportedCurrency(result.currency);
    const presentation: QualifiedResultPresentation = presentable
      ? presentQualifiedResult(result)
      : {
          kind: 'SUPPRESSED',
          reasonAr: `المبلغ بعملة ${result.currency} لا يمكن عرضه بدقة`,
          captionAr: `${result.basisLabelAr} · ${result.costClassificationLabelAr}`,
        };

    positions.push({
      currency: result.currency,
      result,
      presentation,
      presentable,
      resultRevenueMinorUnits: row.result_revenue_minor_units,
      resultDeductedCostMinorUnits: row.result_deducted_cost_minor_units,
      attributedOperatingCostMinorUnits: row.attributed_operating_cost_minor_units,
      sellingCostAttributedMinorUnits: row.selling_cost_attributed_minor_units,
      projectOverheadMinorUnits: row.project_overhead_minor_units,
      unclassifiedEligibleMinorUnits: row.unclassified_eligible_minor_units,
    });
  }

  positions.sort((a, b) => a.currency.localeCompare(b.currency));

  return {
    hasResultFact: positions.length > 0,
    positions,
    unparseableRowCount,
    unsupportedCurrencyCount: positions.filter((p) => !p.presentable).length,
    isMultiCurrency: positions.length > 1,
  };
}
