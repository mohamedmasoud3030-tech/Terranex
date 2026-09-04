// Result — the second of the seven Project Brief panels (ADR 0034 §6).
//
// Renders `ProjectResultView` and nothing else. Three rules are enforced by the
// shape of this component rather than by convention:
//
//   1. No cross-currency total exists to render. There is no FX contract in this
//      repository, so a project whose facts are posted in two currencies has two
//      results. The panel renders one qualified position per currency and never
//      combines them.
//
//   2. No naked amount. The amount is only ever produced by
//      `presentQualifiedResult`, which returns it together with a mandatory
//      caption naming the basis and the cost-coverage status, or withholds the
//      amount entirely and returns a reason instead.
//
//   3. "No result fact" is rendered as an absence, never as a zero. The previous
//      implementation reduced an empty Real Estate disposal view and printed a
//      confident 0.00 for projects that could not possibly have one.
//
// The panel performs no arithmetic. Revenue, deduction and the classification
// buckets all come from the read model; this component only labels and formats.

import { formatMinorUnits } from '@/shared/money';
import type { ProjectResultPosition, ProjectResultView } from './project-result';

const LABEL = {
  heading: 'نتيجة التشغيل الإدارية',
  resultRevenue: 'إيراد النتيجة',
  deducted: 'التكلفة المخصومة من النتيجة',
  attributed: 'التكلفة المنسوبة (تصنيف)',
  sellingAttributed: 'منها تكلفة بيع مخصومة صفر مرة',
  overhead: 'تكلفة عامة للمشروع',
  unclassified: 'تكلفة مؤهلة غير مُصنَّفة',
  currencyNote: 'كل عملة تُقرأ وحدها',
} as const;

/**
 * Formats a figure with the row's own currency, never with the project
 * reporting currency. Returns an em dash when the currency cannot be rendered,
 * so an unrepresentable amount is visibly absent rather than rounded.
 */
function useMoney(position: ProjectResultPosition) {
  return (minorUnits: string) =>
    position.presentable ? formatMinorUnits(minorUnits, position.currency) : '—';
}

function ResultPosition({ position }: { position: ProjectResultPosition }) {
  const { presentation, result } = position;
  const money = useMoney(position);

  return (
    <article className="stack" data-testid={`result-position-${position.currency}`}>
      <div className="topline">
        <h3>{position.currency}</h3>
        <span className="muted">{result.basisLabelAr}</span>
      </div>

      {presentation.kind === 'PRESENTABLE' ? (
        <div className="stack" data-testid={`result-presentable-${position.currency}`}>
          <strong
            data-testid={`result-amount-${position.currency}`}
            data-currency={position.currency}
            className={presentation.tone === 'caution' ? 'error' : undefined}
          >
            {presentation.amountText}
          </strong>
          <small className="muted">{presentation.captionAr}</small>
        </div>
      ) : (
        <div className="stack" data-testid={`result-suppressed-${position.currency}`}>
          <strong>—</strong>
          <small className="muted">{presentation.reasonAr}</small>
          <small className="muted">{presentation.captionAr}</small>
        </div>
      )}

      <dl className="facts">
        <div>
          <dt>{LABEL.resultRevenue}</dt>
          <dd data-testid={`result-revenue-${position.currency}`}>
            {money(position.resultRevenueMinorUnits)}
          </dd>
        </div>
        <div>
          <dt>{LABEL.deducted}</dt>
          <dd data-testid={`result-deducted-${position.currency}`}>
            {money(position.resultDeductedCostMinorUnits)}
          </dd>
        </div>
        <div>
          <dt>{LABEL.attributed}</dt>
          <dd data-testid={`result-attributed-${position.currency}`}>
            {money(position.attributedOperatingCostMinorUnits)}
          </dd>
        </div>
        <div>
          <dt>{LABEL.sellingAttributed}</dt>
          <dd data-testid={`result-selling-${position.currency}`}>
            {money(position.sellingCostAttributedMinorUnits)}
          </dd>
        </div>
        <div>
          <dt>{LABEL.overhead}</dt>
          <dd data-testid={`result-overhead-${position.currency}`}>
            {money(position.projectOverheadMinorUnits)}
          </dd>
        </div>
        <div>
          <dt>{LABEL.unclassified}</dt>
          <dd data-testid={`result-unclassified-${position.currency}`}>
            {money(position.unclassifiedEligibleMinorUnits)}
          </dd>
        </div>
      </dl>
    </article>
  );
}

export function ResultPanel({ view }: { view: ProjectResultView }) {
  return (
    <section className="card stack" aria-labelledby="result-panel-heading">
      <div className="topline">
        <h2 id="result-panel-heading">{LABEL.heading}</h2>
      </div>

      {view.unparseableRowCount > 0 && (
        <p className="error" role="alert">
          تم تجاهل {view.unparseableRowCount} صفًّا للنتيجة غير مطابق لعقد النتيجة المؤهَّلة؛ راجع
          قراءة النتيجة قبل اعتماد أي رقم أدناه.
        </p>
      )}

      {view.unsupportedCurrencyCount > 0 && (
        <p className="error" role="alert">
          {view.unsupportedCurrencyCount === 1
            ? 'عملة واحدة غير مدعومة في العرض'
            : `${view.unsupportedCurrencyCount} عملات غير مدعومة في العرض`}
          ؛ تُقرأ كغياب (—) ولا تُحذف ولا تُصفر.
        </p>
      )}

      {!view.hasResultFact ? (
        <p className="muted" data-testid="result-empty">
          لا توجد نتيجة تشغيل مسجلة لهذا المشروع: لا إيراد محقق ولا تكلفة تشغيلية مقابِلة. لا نعرض
          صفرًا مفترضًا.
        </p>
      ) : (
        <>
          {view.positions.map((position) => (
            <ResultPosition key={position.currency} position={position} />
          ))}

          {view.isMultiCurrency && (
            <p className="muted" data-testid="result-multi-currency-note">
              {view.positions.length} عملات. لا يوجد إجمالي بين العملات: ضمّ المبالغ بعملات مختلفة
              يحتاج سعر تحويل معتمد بسياسة، ولا يُختلق هنا.
            </p>
          )}
        </>
      )}
    </section>
  );
}
