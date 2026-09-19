// Qualified result contract — the TypeScript half of ADR 0034 §2.
//
// The SQL contract deliberately exposes NO bare result scalar: the amount exists
// only inside the `management_result` jsonb object, together with its currency,
// basis, cost-classification status, evidence status, policy-availability list
// and as-of date. Selecting the result therefore selects its qualification.
//
// That discipline is worthless if a page can reach into
// `row.management_result.amount_minor_units` and drop it into an unlabelled KPI.
// So it is reproduced here:
//
//   * The parsed view exposes NO plain amount field to render from.
//   * The only way to obtain displayable amount text is
//     `presentQualifiedResult()`, which returns the amount and its mandatory
//     Arabic caption together, or refuses to return an amount at all.
//   * A result with no cost coverage is SUPPRESSED, not rounded into a number.
//
// Money is never converted or summed here: cross-project aggregation is a
// database responsibility and lives in `sector_management_result_read`.

import { z } from 'zod';
import { formatMinorUnits } from '@/shared/money';

// ---------------------------------------------------------------------------
// Contract enums — mirrored from the SQL view. Unknown values fail closed.
// ---------------------------------------------------------------------------

export const COST_CLASSIFICATION_STATUS = [
  'COMPLETE',
  'PARTIAL',
  'NONE',
  'NOT_APPLICABLE_NO_OPERATING_COST',
] as const;

export const EVIDENCE_STATUS = [
  'COMPLETE',
  'PARTIAL',
  'INCOMPLETE',
  'NOT_APPLICABLE_NO_EVIDENCE_CONTRACT',
] as const;

export const RESULT_BASIS = [
  'REAL_ESTATE_DISPOSAL_AND_RENTAL',
  'AGRICULTURE_ENTERPRISE_OPERATING',
  'LIVESTOCK_ENTERPRISE_OPERATING',
] as const;

export type CostClassificationStatus = (typeof COST_CLASSIFICATION_STATUS)[number];
export type EvidenceStatus = (typeof EVIDENCE_STATUS)[number];
export type ResultBasis = (typeof RESULT_BASIS)[number];

/** Money is transported as decimal text so no integer is ever rounded in transit. */
const exactIntegerText = z.string().regex(/^-?\d+$/, 'money must be exact integer text');

export const qualifiedResultSchema = z.object({
  amount_minor_units: exactIntegerText,
  currency: z.string().regex(/^[A-Z]{3}$/),
  basis: z.string().min(1),
  cost_classification_status: z.enum(COST_CLASSIFICATION_STATUS),
  evidence_status: z.enum(EVIDENCE_STATUS),
  policy_availability: z.array(z.string()),
  as_of: z.string().min(1),
});

export type QualifiedResult = z.infer<typeof qualifiedResultSchema>;

// ---------------------------------------------------------------------------
// Reserved terminology (ADR 0034 §2.2).
//
// These words name policy-defined investor concepts that TERRANEX deliberately
// does not compute. A management operating result must never borrow their
// authority, so the surface vocabulary is checked against them.
// ---------------------------------------------------------------------------

export const RESERVED_TERMS = [
  'profit',
  'ربح',
  'أرباح',
  'return',
  'investor return',
  'realized investment return',
  'عائد',
  'IRR',
  'MOIC',
  'TVPI',
  'equity multiple',
  'cash-on-cash',
  'distributable cash',
] as const;

export function containsReservedTerm(text: string): string | null {
  const haystack = text.toLowerCase();
  // Longest first, so the most specific term is reported: 'investor return'
  // should not be reported merely as 'return'.
  const bySpecificity = [...RESERVED_TERMS].sort((a, b) => b.length - a.length);
  for (const term of bySpecificity) {
    if (haystack.includes(term.toLowerCase())) return term;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Arabic surface vocabulary — one place, so Home and Project Brief cannot drift.
// ---------------------------------------------------------------------------

export const RESULT_TERM_AR = 'نتيجة التشغيل الإدارية';

export const BASIS_LABEL_AR: Record<string, string> = {
  REAL_ESTATE_DISPOSAL_AND_RENTAL: 'أساس عقاري: نتيجة التصرفات المحققة + الإيجار',
  AGRICULTURE_ENTERPRISE_OPERATING: 'أساس زراعي: إيراد البيع − تكلفة الدورات المُصنَّفة',
  LIVESTOCK_ENTERPRISE_OPERATING: 'أساس ماشية: إيراد البيع − تكلفة القطعان المُصنَّفة',
};

export const COST_CLASSIFICATION_LABEL_AR: Record<CostClassificationStatus, string> = {
  COMPLETE: 'تكلفة مُصنَّفة بالكامل',
  PARTIAL: 'تصنيف تكلفة جزئي',
  NONE: 'لا توجد تكلفة مُصنَّفة',
  NOT_APPLICABLE_NO_OPERATING_COST: 'لا توجد تكلفة تشغيل',
};

export const EVIDENCE_LABEL_AR: Record<EvidenceStatus, string> = {
  COMPLETE: 'مستند بالكامل',
  PARTIAL: 'مستند جزئيًا',
  INCOMPLETE: 'غير مستند',
  NOT_APPLICABLE_NO_EVIDENCE_CONTRACT: 'لا يوجد عقد إسناد لهذا السطح',
};

export const POLICY_LABEL_AR: Record<string, string> = {
  COGS_NOT_RECOGNIZED: 'تكلفة المبيعات غير معترف بها محاسبيًا لهذا القطاع',
  HARVEST_INVENTORY_VALUE_NOT_RECOGNIZED: 'قيمة مخزون الحصاد غير معترف بها',
  BIOLOGICAL_ASSET_VALUE_NOT_RECOGNIZED: 'قيمة الأصول الحيوية غير معترف بها',
  UNREALIZED_VALUATION_NOT_INCLUDED_IN_MANAGEMENT_RESULT:
    'التقييم غير المحقق غير داخل في نتيجة التشغيل',
  RETURN_MULTIPLES_UNAVAILABLE_PENDING_POLICY: 'مضاعفات العائد غير متاحة قبل اعتماد السياسة',
  INVESTOR_ENTITLEMENT_NOT_ACTIVATED: 'سياسة المستثمرين غير مُفعَّلة لهذه المنظمة',
};

// ---------------------------------------------------------------------------
// The parsed view.
//
// NOTE: there is intentionally no `amount` field here. `amountMinorUnits` is
// kept only so tests and aggregation can assert exactness; UI code must go
// through `presentQualifiedResult`.
// ---------------------------------------------------------------------------

export type QualifiedResultView = {
  /** Exact integer minor units as text. Not for direct rendering. */
  readonly amountMinorUnits: string;
  readonly currency: string;
  readonly basis: string;
  readonly basisLabelAr: string;
  readonly costClassificationStatus: CostClassificationStatus;
  readonly costClassificationLabelAr: string;
  readonly evidenceStatus: EvidenceStatus;
  readonly evidenceLabelAr: string;
  readonly policyAvailability: readonly string[];
  readonly policyNotesAr: readonly string[];
  readonly asOf: string;
  /** Eligible operating cost not yet classified, as exact text. Null when the
   *  row does not disclose it. Always rendered with the result, never behind it. */
  readonly unclassifiedMinorUnits: string | null;
};

/** Parses the `management_result` jsonb object. Fails closed: a result whose
 *  shape is not the one ADR 0034 defines is an error, not a default. */
export function parseQualifiedResult(raw: unknown): QualifiedResult {
  const parsed = qualifiedResultSchema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(
      `management_result does not satisfy the qualified-result contract: ${parsed.error.message}`,
    );
  }
  return parsed.data;
}

export function toQualifiedResultView(
  result: QualifiedResult,
  unclassifiedMinorUnits: string | null = null,
): QualifiedResultView {
  return {
    amountMinorUnits: result.amount_minor_units,
    currency: result.currency,
    basis: result.basis,
    basisLabelAr: BASIS_LABEL_AR[result.basis] ?? result.basis,
    costClassificationStatus: result.cost_classification_status,
    costClassificationLabelAr: COST_CLASSIFICATION_LABEL_AR[result.cost_classification_status],
    evidenceStatus: result.evidence_status,
    evidenceLabelAr: EVIDENCE_LABEL_AR[result.evidence_status],
    policyAvailability: result.policy_availability,
    policyNotesAr: result.policy_availability.map(
      (code) => POLICY_LABEL_AR[code] ?? code,
    ),
    asOf: result.as_of,
    unclassifiedMinorUnits,
  };
}

/** Convenience for pages holding a raw row from `project_operating_result_read`
 *  or `sector_management_result_read`. */
export function qualifiedResultViewFromRow(
  row: { management_result: unknown; unclassified_eligible_minor_units?: string | null },
): QualifiedResultView {
  return toQualifiedResultView(
    parseQualifiedResult(row.management_result),
    row.unclassified_eligible_minor_units ?? null,
  );
}

// ---------------------------------------------------------------------------
// Presentation — the only sanctioned way to obtain displayable amount text.
// ---------------------------------------------------------------------------

export type MoneyFormatter = (minorUnits: string, currency: string) => string;

export type QualifiedResultPresentation =
  | {
      readonly kind: 'PRESENTABLE';
      /** Formatted amount, always accompanied by `captionAr`. */
      readonly amountText: string;
      /** Mandatory caption: basis + coverage status. Render it with the amount. */
      readonly captionAr: string;
      /** `caution` means the amount is shown but the gap must be unmissable. */
      readonly tone: 'ok' | 'caution';
    }
  | {
      readonly kind: 'SUPPRESSED';
      /** No amount is returned. Show revenue/cost decomposition instead. */
      readonly reasonAr: string;
      readonly captionAr: string;
    };

/**
 * Coverage gate.
 *
 * `NONE` is suppressed: with no classified operating cost at all, the result is
 * arithmetically identical to revenue, and presenting it as a result would
 * restate the exact defect ADR 0034 exists to remove — an Agriculture or
 * Livestock project appearing to earn 100% margin.
 *
 * `PARTIAL` is presentable but must be flagged, because declaring genuine
 * overhead is legitimate and must not freeze a project at PARTIAL forever.
 */
export function isResultComparable(view: QualifiedResultView): boolean {
  return (
    view.costClassificationStatus === 'COMPLETE' ||
    view.costClassificationStatus === 'NOT_APPLICABLE_NO_OPERATING_COST'
  );
}

export function presentQualifiedResult(
  view: QualifiedResultView,
  formatMoney: MoneyFormatter = formatMinorUnits,
): QualifiedResultPresentation {
  const captionAr = `${view.basisLabelAr} · ${view.costClassificationLabelAr}`;

  if (view.costClassificationStatus === 'NONE') {
    const size =
      view.unclassifiedMinorUnits === null
        ? ''
        : ` (${formatMoney(view.unclassifiedMinorUnits, view.currency)} تكلفة مؤهلة غير مُصنَّفة)`;
    return {
      kind: 'SUPPRESSED',
      captionAr,
      reasonAr:
        `لا نعرض ${RESULT_TERM_AR} قبل تصنيف أي تكلفة تشغيل؛ ` +
        `الرقم سيكون مساويًا للإيراد وسيُقرأ كهامش ربح.${size}`,
    };
  }

  return {
    kind: 'PRESENTABLE',
    amountText: formatMoney(view.amountMinorUnits, view.currency),
    captionAr,
    tone: view.costClassificationStatus === 'COMPLETE' ? 'ok' : 'caution',
  };
}

/** The unclassified-cost caveat, when there is one. Callers render this next to
 *  the result so incompleteness is never presented as margin. */
export function unclassifiedCaveatAr(
  view: QualifiedResultView,
  formatMoney: MoneyFormatter = formatMinorUnits,
): string | null {
  if (!view.unclassifiedMinorUnits) return null;
  if (!/^[1-9]/.test(view.unclassifiedMinorUnits)) return null;
  return (
    `تكلفة تشغيل مؤهلة لم تُصنَّف بعد: ` +
    `${formatMoney(view.unclassifiedMinorUnits, view.currency)} — ` +
    `هذه التكلفة ليست مخصومة من النتيجة وقد تكون أعلى مما يظهر.`
  );
}
