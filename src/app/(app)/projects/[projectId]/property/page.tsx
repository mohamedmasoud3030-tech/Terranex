import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getParties } from '@/features/funding/queries';
import {
  getPropertyAssets,
  getPropertyCostItems,
  getPropertyValuations,
  getPropertyCarryingAmount,
} from '@/features/real-estate/queries';
import { formatMinorUnits } from '@/features/funding/money';
import {
  PropertyAssetForm,
  PropertyCostForm,
  PropertyValuationForm,
} from './forms';

export const dynamic = 'force-dynamic';

const STRATEGY_LABEL: Record<string, string> = {
  ACQUIRE_HOLD: 'شراء واحتفاظ',
  DEVELOP_SELL: 'تطوير وبيع',
  LAND_TRADE: 'تجارة أراضٍ',
};

const STATE_LABEL: Record<string, string> = {
  CANDIDATE: 'مرشح',
  DUE_DILIGENCE: 'فحص نافي للجهالة',
  ACQUIRING: 'قيد الاكتساب',
  HELD: 'مملوك',
  DEVELOPING: 'قيد التطوير',
  DISPOSING: 'قيد التصرف',
  DISPOSED: 'تم التصرف',
};

export default async function PropertyPage({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();

  const [assets, parties] = await Promise.all([
    getPropertyAssets(projectId),
    getParties(project.organization_id),
  ]);

  return (
    <section className="stack">
      <div>
        <Link className="muted" href={`/projects/${projectId}`}>
          ← المشروع
        </Link>
        <h1>الأصول العقارية</h1>
        <p className="muted">إدارة العقارات والتكاليف والتقييمات</p>
      </div>

      <section className="card stack">
        <h2>إضافة عقار جديد</h2>
        <PropertyAssetForm
          organizationId={project.organization_id}
          projectId={projectId}
          currency={project.reporting_currency}
        />
      </section>

      {assets.length === 0 ? (
        <section className="card">
          <p className="muted">لا توجد أصول عقارية مسجلة بعد.</p>
        </section>
      ) : (
        assets.map((asset) => (
          <AssetDetail
            key={asset.id}
            asset={asset}
            projectId={projectId}
            organizationId={project.organization_id}
            currency={project.reporting_currency}
          />
        ))
      )}
    </section>
  );
}

async function AssetDetail({
  asset,
  projectId,
  organizationId,
  currency,
}: {
  asset: Awaited<ReturnType<typeof getPropertyAssets>>[number];
  projectId: string;
  organizationId: string;
  currency: string;
}) {
  const [costItems, valuations, carryingAmount] = await Promise.all([
    getPropertyCostItems(asset.id),
    getPropertyValuations(asset.id),
    getPropertyCarryingAmount(asset.id),
  ]);

  const totalCost = costItems.reduce(
    (sum, item) => sum + (item.is_capitalizable ? BigInt(item.cost_minor_units) : 0n),
    0n,
  );

  return (
    <section className="card stack">
      <div>
        <span className="status">{STATE_LABEL[asset.lifecycle_state] ?? asset.lifecycle_state}</span>
        <h2>{asset.display_name}</h2>
        <p className="muted">
          {STRATEGY_LABEL[asset.strategy] ?? asset.strategy}
          {asset.jurisdiction ? ` · ${asset.jurisdiction}` : ''}
          {asset.acquired_on ? ` · اكتُسب في ${asset.acquired_on}` : ''}
        </p>
      </div>

      <div className="grid">
        <div>
          <p className="muted">تكلفة الاكتساب</p>
          <strong>
            {asset.acquisition_cost_minor_units
              ? formatMinorUnits(asset.acquisition_cost_minor_units, currency)
              : '—'}
          </strong>
        </div>
        <div>
          <p className="muted">التكاليف الرأسمالية</p>
          <strong>{formatMinorUnits(totalCost.toString(), currency)}</strong>
        </div>
        <div>
          <p className="muted">التكلفة الدفترية</p>
          <strong>
            {carryingAmount
              ? formatMinorUnits(carryingAmount.carrying_amount_minor_units, currency)
              : '—'}
          </strong>
        </div>
      </div>

      <details>
        <summary>إضافة تكلفة عقارية</summary>
        <PropertyCostForm
          organizationId={organizationId}
          projectId={projectId}
          propertyAssetId={asset.id}
          currency={currency}
        />
      </details>

      {costItems.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>الفئة</th>
                <th>رأسمالي</th>
                <th>المبلغ</th>
                <th>التاريخ</th>
                <th>الوصف</th>
              </tr>
            </thead>
            <tbody>
              {costItems.map((item) => (
                <tr key={item.id}>
                  <td>{item.cost_category}</td>
                  <td>{item.is_capitalizable ? 'نعم' : 'لا'}</td>
                  <td>{formatMinorUnits(item.cost_minor_units, currency)}</td>
                  <td>{item.occurred_on}</td>
                  <td>{item.description || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <details>
        <summary>إضافة تقييم إداري</summary>
        <PropertyValuationForm
          organizationId={organizationId}
          projectId={projectId}
          propertyAssetId={asset.id}
          currency={currency}
        />
      </details>

      {valuations.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>التاريخ</th>
                <th>المصدر</th>
                <th>الطريقة</th>
                <th>القيمة</th>
                <th>الثقة</th>
                <th>الحالة</th>
              </tr>
            </thead>
            <tbody>
              {valuations.map((val) => (
                <tr key={val.id}>
                  <td>{val.effective_date}</td>
                  <td>{val.valuer_source}</td>
                  <td>{val.method}</td>
                  <td>{formatMinorUnits(val.valuation_minor_units, currency)}</td>
                  <td>{val.confidence ?? '—'}</td>
                  <td>{val.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
