// Capital — the first of the seven Project Brief panels (ADR 0034 §6).
//
// Renders `ProjectCapitalView` and nothing else. Two rules are enforced by the
// shape of this component rather than by convention:
//
//   1. No cross-currency total exists to render. There is no project-level
//      "committed" figure, because a commitment is denominated in the currency
//      of the commitment — which is not constrained to be the project reporting
//      currency. Each row is labelled with its own currency and stands alone.
//
//   2. "No capital structure" is rendered as an absence, never as a zero. A
//      project that has never raised capital has no row at all; printing 0.000
//      would claim a fact no ledger supports.

import type { CapitalAmount, ProjectCapitalView, CapitalPositionView } from './project-capital';
import { presentCapitalAmount } from './project-capital';

const COLUMN_LABEL = {
  currency: 'العملة',
  committed: 'الملتزم به',
  called: 'المستدعى',
  contributed: 'المساهم به',
  receivable: 'المستحق',
  uncalled: 'غير المستدعى',
} as const;

/**
 * One currency's row. The currency is the row header, so every figure in the
 * row is read against it; each cell also carries `data-currency` so a figure
 * can never be lifted out of the row and rendered on its own.
 */
function CapitalRow({ position }: { position: CapitalPositionView }) {
  const cell = (amount: CapitalAmount, testId: string) => (
    <td data-testid={testId} data-currency={position.currency}>
      {presentCapitalAmount(amount)}
    </td>
  );

  return (
    <tr data-currency={position.currency}>
      <th scope="row">{position.currency}</th>
      {cell(position.committed, `capital-committed-${position.currency}`)}
      {cell(position.called, `capital-called-${position.currency}`)}
      {cell(position.contributed, `capital-contributed-${position.currency}`)}
      {cell(position.receivable, `capital-receivable-${position.currency}`)}
      {cell(position.uncalled, `capital-uncalled-${position.currency}`)}
      <td>{position.hasIssuedCall ? `${position.callLineCount} استدعاء` : 'لم يُستدعَ'}</td>
    </tr>
  );
}

export function CapitalPanel({ view }: { view: ProjectCapitalView }) {
  return (
    <section className="card stack" aria-labelledby="capital-panel-heading">
      <div className="topline">
        <h2 id="capital-panel-heading">رأس المال</h2>
      </div>

      {view.unparseableRowCount > 0 && (
        <p className="error" role="alert">
          تم تجاهل {view.unparseableRowCount} صفًّا رأسماليًا غير مطابق للعقد؛ راجع قراءة رأس المال
          قبل اعتماد أي رقم أدناه.
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

      {!view.hasCapitalStructure ? (
        <p className="muted" data-testid="capital-empty">
          لا يوجد هيكل رأس مال مسجل لهذا المشروع: لا التزام ولا استدعاء ولا مساهمة. لا نعرض أصفارًا
          مفترضة.
        </p>
      ) : (
        <>
          <div className="table-wrap">
            <table>
              <caption className="muted">
                موقف رأس المال لكل عملة. كل عملة تُقرأ وحدها.
              </caption>
              <thead>
                <tr>
                  <th scope="col">{COLUMN_LABEL.currency}</th>
                  <th scope="col">{COLUMN_LABEL.committed}</th>
                  <th scope="col">{COLUMN_LABEL.called}</th>
                  <th scope="col">{COLUMN_LABEL.contributed}</th>
                  <th scope="col">{COLUMN_LABEL.receivable}</th>
                  <th scope="col">{COLUMN_LABEL.uncalled}</th>
                  <th scope="col">الاستدعاءات</th>
                </tr>
              </thead>
              <tbody>
                {view.positions.map((position) => (
                  <CapitalRow key={position.currency} position={position} />
                ))}
              </tbody>
            </table>
          </div>

          {view.isMultiCurrency && (
            <p className="muted" data-testid="capital-multi-currency-note">
              {view.positions.length} عملات. لا يوجد إجمالي بين العملات: ضمّ المبالغ بعملات مختلفة
              يحتاج سعر تحويل معتمد بسياسة، ولا يُختلق هنا.
            </p>
          )}
        </>
      )}
    </section>
  );
}
