import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getParties } from '@/features/funding/queries';
import {
  getPropertyAssets,
  getDispositions,
  getSaleRecognitions,
  getSaleReceivables,
  getCollections,
  getCashAccounts,
} from '@/features/real-estate/queries';
import { formatMinorUnits } from '@/features/funding/money';
import {
  DispositionForm,
  ApproveDispositionForm,
  RecognizeSaleForm,
  CollectionForm,
} from './forms';

export const dynamic = 'force-dynamic';

const STATUS_LABEL: Record<string, string> = {
  DRAFT: 'مسودة',
  APPROVED: 'معتمد',
  CONTROL_TRANSFERRED: 'تم نقل السيطرة',
  SETTLED: 'مُسوّى',
  CANCELLED: 'ملغى',
};

export default async function DispositionPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();

  const [assets, parties, dispositions, recognitions, receivables, cashAccounts] = await Promise.all([
    getPropertyAssets(projectId),
    getParties(project.organization_id),
    getDispositions(projectId),
    getSaleRecognitions(projectId),
    getSaleReceivables(projectId),
    getCashAccounts(project.organization_id, project.reporting_currency),
  ]);

  const availableAssets = assets.filter((a) => a.lifecycle_state !== 'DISPOSED');

  return (
    <section className="stack">
      <div>
        <Link className="muted" href={`/projects/${projectId}`}>
          ← المشروع
        </Link>
        <h1>التصرف والمبيعات</h1>
        <p className="muted">إدارة بيع العقارات والتحصيل</p>
      </div>

      <section className="card stack">
        <h2>إنشاء تصرف جديد</h2>
        {availableAssets.length === 0 ? (
          <p className="muted">لا توجد أصول متاحة للبيع. أضف عقارًا أولًا.</p>
        ) : (
          <DispositionForm
            organizationId={project.organization_id}
            projectId={projectId}
            assets={availableAssets}
            parties={parties}
            currency={project.reporting_currency}
          />
        )}
      </section>

      {dispositions.length === 0 ? (
        <section className="card">
          <p className="muted">لا توجد تصرفات مسجلة بعد.</p>
        </section>
      ) : (
        dispositions.map((disp) => (
          <DispositionDetail
            key={disp.id}
            disposition={disp}
            recognitions={recognitions}
            receivables={receivables}
            projectId={projectId}
            organizationId={project.organization_id}
            currency={project.reporting_currency}
            cashAccounts={cashAccounts}
          />
        ))
      )}
    </section>
  );
}

async function DispositionDetail({
  disposition,
  recognitions,
  receivables,
  projectId,
  organizationId,
  currency,
  cashAccounts,
}: {
  disposition: Awaited<ReturnType<typeof getDispositions>>[number];
  recognitions: Awaited<ReturnType<typeof getSaleRecognitions>>;
  receivables: Awaited<ReturnType<typeof getSaleReceivables>>;
  projectId: string;
  organizationId: string;
  currency: string;
  cashAccounts: Awaited<ReturnType<typeof getCashAccounts>>;
}) {
  const recognition = recognitions.find((r) => r.disposition_id === disposition.id);
  const receivable = receivables.find((r) => r.sale_recognition_id === recognition?.id);
  const collections = receivable ? await getCollections(receivable.id) : [];
  const totalCollected = collections.reduce(
    (sum, c) => sum + BigInt(c.collection_minor_units),
    0n,
  );
  const outstanding = receivable
    ? BigInt(receivable.receivable_minor_units) - totalCollected
    : 0n;

  return (
    <section className="card stack">
      <div>
        <span className="status">{STATUS_LABEL[disposition.status] ?? disposition.status}</span>
        <h2>تصرف {disposition.id.slice(0, 8)}</h2>
        <p className="muted">
          تاريخ الاتفاق: {disposition.agreement_date}
          {disposition.control_transfer_date && ` · نقل السيطرة: ${disposition.control_transfer_date}`}
        </p>
      </div>

      <div className="grid">
        <div>
          <p className="muted">الإيراد المتفق عليه</p>
          <strong>{formatMinorUnits(disposition.agreed_proceeds_minor_units, currency)}</strong>
        </div>
        <div>
          <p className="muted">تكاليف البيع</p>
          <strong>{formatMinorUnits(disposition.selling_costs_minor_units, currency)}</strong>
        </div>
        {disposition.contract_reference && (
          <div>
            <p className="muted">مرجع العقد</p>
            <strong>{disposition.contract_reference}</strong>
          </div>
        )}
      </div>

      {disposition.status === 'DRAFT' && (
        <ApproveDispositionForm
          organizationId={organizationId}
          projectId={projectId}
          dispositionId={disposition.id}
        />
      )}

      {disposition.status === 'APPROVED' && (
        <RecognizeSaleForm
          organizationId={organizationId}
          projectId={projectId}
          dispositionId={disposition.id}
        />
      )}

      {recognition && (
        <div className="stack">
          <h3>الاعتراف بالبيع</h3>
          <div className="grid">
            <div>
              <p className="muted">الإيراد المعترف به</p>
              <strong>{formatMinorUnits(recognition.recognized_revenue_minor_units, currency)}</strong>
            </div>
            <div>
              <p className="muted">التكلفة المرحلة</p>
              <strong>{formatMinorUnits(recognition.derecognized_carrying_cost_minor_units, currency)}</strong>
            </div>
            <div>
              <p className="muted">النتيجة المحققة</p>
              <strong>{formatMinorUnits(recognition.realized_result_minor_units, currency)}</strong>
            </div>
          </div>
        </div>
      )}

      {receivable && (
        <div className="stack">
          <h3>التحصيل</h3>
          <div className="grid">
            <div>
              <p className="muted">المستحق</p>
              <strong>{formatMinorUnits(receivable.receivable_minor_units, currency)}</strong>
            </div>
            <div>
              <p className="muted">المحصل</p>
              <strong>{formatMinorUnits(totalCollected.toString(), currency)}</strong>
            </div>
            <div>
              <p className="muted">المتبقي</p>
              <strong>{formatMinorUnits(outstanding.toString(), currency)}</strong>
            </div>
          </div>

          {outstanding > 0n && cashAccounts.length > 0 && (
            <details>
              <summary>تسجيل تحصيل</summary>
              <CollectionForm
                organizationId={organizationId}
                projectId={projectId}
                saleReceivableId={receivable.id}
                currency={currency}
                cashAccounts={cashAccounts}
                maxAmount={outstanding}
              />
            </details>
          )}

          {collections.length > 0 && (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>التاريخ</th>
                    <th>المبلغ</th>
                  </tr>
                </thead>
                <tbody>
                  {collections.map((c) => (
                    <tr key={c.id}>
                      <td>{c.collected_on}</td>
                      <td>{formatMinorUnits(c.collection_minor_units, currency)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </section>
  );
}
