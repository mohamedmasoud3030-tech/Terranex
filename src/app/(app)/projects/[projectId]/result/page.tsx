import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import {
  getProjectRealizedResult,
  getProjectLatestValuation,
  getSaleRecognitions,
} from '@/features/real-estate/queries';
import { formatMinorUnits } from '@/features/funding/money';

export const dynamic = 'force-dynamic';

export default async function ResultPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();

  const [result, latestValuation, recognitions] = await Promise.all([
    getProjectRealizedResult(projectId),
    getProjectLatestValuation(projectId),
    getSaleRecognitions(projectId),
  ]);

  const hasSales = recognitions.length > 0;

  return (
    <section className="stack">
      <div>
        <Link className="muted" href={`/projects/${projectId}`}>
          ← المشروع
        </Link>
        <h1>النتيجة المحققة</h1>
        <p className="muted">تقرير الإيرادات والتكاليف والنتيجة المحققة للمشروع</p>
      </div>

      {!hasSales ? (
        <section className="card">
          <p className="muted">لا توجد مبيعات معترف بها بعد. النتيجة المحققة تظهر بعد الاعتراف بالبيع.</p>
        </section>
      ) : (
        <>
          <section className="card stack">
            <h2>الملخص المالي</h2>
            {result ? (
              <div className="grid">
                <div>
                  <p className="muted">الإيراد المعترف به</p>
                  <strong>{formatMinorUnits(result.recognized_revenue_minor_units, result.currency)}</strong>
                </div>
                <div>
                  <p className="muted">التكلفة المرحلة للبيع</p>
                  <strong>{formatMinorUnits(result.derecognized_carrying_cost_minor_units, result.currency)}</strong>
                </div>
                <div>
                  <p className="muted">تكاليف البيع</p>
                  <strong>{formatMinorUnits(result.selling_costs_minor_units, result.currency)}</strong>
                </div>
                <div>
                  <p className="muted">النتيجة المحققة</p>
                  <strong style={{ fontSize: '1.25rem', color: BigInt(result.realized_result_minor_units) >= 0n ? 'var(--brand)' : 'var(--danger)' }}>
                    {formatMinorUnits(result.realized_result_minor_units, result.currency)}
                  </strong>
                </div>
              </div>
            ) : (
              <p className="muted">لا توجد بيانات مالية.</p>
            )}
          </section>

          <section className="card stack">
            <h2>التحصيل والذمم</h2>
            {result ? (
              <div className="grid">
                <div>
                  <p className="muted">المحصل نقدًا</p>
                  <strong>{formatMinorUnits(result.collected_cash_minor_units, result.currency)}</strong>
                </div>
                <div>
                  <p className="muted">المتبقي للتحصيل</p>
                  <strong>{formatMinorUnits(result.outstanding_receivable_minor_units, result.currency)}</strong>
                </div>
              </div>
            ) : (
              <p className="muted">لا توجد بيانات.</p>
            )}
          </section>

          {latestValuation && (
            <section className="card stack">
              <h2>التقييم الإداري (منفصل عن النتيجة المحققة)</h2>
              <p className="muted">
                التقييم الإداري هو تقدير للقيمة السوقية ولا يمثل ربحًا محققًا. يظهر هنا للفصل الصريح بين القيمة التقديرية والنتيجة المحققة.
              </p>
              <div className="grid">
                <div>
                  <p className="muted">تاريخ التقييم</p>
                  <strong>{latestValuation.effective_date}</strong>
                </div>
                <div>
                  <p className="muted">القيمة التقديرية</p>
                  <strong>{formatMinorUnits(latestValuation.valuation_minor_units, latestValuation.currency)}</strong>
                </div>
                <div>
                  <p className="muted">المصدر</p>
                  <strong>{latestValuation.valuer_source}</strong>
                </div>
                <div>
                  <p className="muted">الطريقة</p>
                  <strong>{latestValuation.method}</strong>
                </div>
              </div>
            </section>
          )}

          <section className="card stack">
            <h2>تفاصيل المبيعات المعترف بها</h2>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>التاريخ</th>
                    <th>الإيراد</th>
                    <th>التكلفة المرحلة</th>
                    <th>تكاليف البيع</th>
                    <th>النتيجة</th>
                  </tr>
                </thead>
                <tbody>
                  {recognitions.map((rec) => (
                    <tr key={rec.id}>
                      <td>{rec.control_transfer_date}</td>
                      <td>{formatMinorUnits(rec.recognized_revenue_minor_units, rec.currency)}</td>
                      <td>{formatMinorUnits(rec.derecognized_carrying_cost_minor_units, rec.currency)}</td>
                      <td>{formatMinorUnits(rec.selling_costs_minor_units, rec.currency)}</td>
                      <td>
                        <strong style={{ color: BigInt(rec.realized_result_minor_units) >= 0n ? 'var(--brand)' : 'var(--danger)' }}>
                          {formatMinorUnits(rec.realized_result_minor_units, rec.currency)}
                        </strong>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}

      <section className="card">
        <h2>ملاحظات مهمة</h2>
        <ul className="muted">
          <li>النتيجة المحققة = الإيراد المعترف به − التكلفة المرحلة − تكاليف البيع</li>
          <li>التقييم الإداري لا يدخل في حساب النتيجة المحققة</li>
          <li>الأرقام المعروضة مشتقة من قيود محاسبية متوازنة ومسجلة</li>
          <li>هذا التقرير للأغراض الإدارية ولا يمثل امتثالًا تلقائيًا لمعايير المحاسبة الدولية</li>
        </ul>
      </section>
    </section>
  );
}
