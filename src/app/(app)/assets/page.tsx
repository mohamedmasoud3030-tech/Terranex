import Link from 'next/link';
import { PageHeader } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import {
  getRegisteredAssets,
  getSectorPerformance,
  type RegisteredAsset,
  type SectorPerformance,
} from '@/features/assets/queries';
import {
  ASSET_CLASSIFICATION_LABEL,
  ASSET_KIND_LABEL,
  ASSET_STATE_LABEL,
  FX_STATUS_LABEL,
  SECTOR_LABEL,
  isAbsence,
  statusLabel,
} from '@/features/assets/labels';
import { formatMinorUnits } from '@/shared/money';
import { sectorLandingHref } from '@/features/workspace/nav';

export const dynamic = 'force-dynamic';

/**
 * R8 — سجل الأصول عبر القطاعات وأداء القطاعات.
 *
 * This page reads two projections and writes nothing. Its single design
 * rule: never render a number the database did not assert. Where a status
 * says the fact does not exist, the cell shows the reason in Arabic — an
 * operator must be able to tell "cost not entered yet" apart from "this
 * kind of asset has no acquisition cost" apart from "worth zero".
 */

/** Renders an exact amount, or the reason there is none. Never a bare dash
 * and never a zero standing in for missing data. */
function Figure({
  minorUnits,
  currency,
  status,
}: Readonly<{
  minorUnits: string | null;
  currency: string | null;
  status: string;
}>) {
  if (minorUnits === null || currency === null || isAbsence(status)) {
    return <span className="muted">{statusLabel(status)}</span>;
  }
  return (
    <>
      <strong>{formatMinorUnits(minorUnits, currency)}</strong>
      <br />
      <small className="muted">{statusLabel(status)}</small>
    </>
  );
}

function AssetRow({ asset }: Readonly<{ asset: RegisteredAsset }>) {
  const classification = asset.asset_classification
    ? ASSET_CLASSIFICATION_LABEL[asset.asset_classification] ?? asset.asset_classification
    : null;

  return (
    <tr>
      <td>
        <strong>{asset.asset_name}</strong>
        <br />
        <small className="muted">
          {asset.asset_reference || 'بدون مرجع'} · {ASSET_KIND_LABEL[asset.asset_kind] ?? asset.asset_kind}
        </small>
      </td>
      <td>
        <Link href={sectorLandingHref(asset.project_sector, asset.project_id)}>
          {asset.project_name}
        </Link>
        <br />
        <small className="muted">
          {SECTOR_LABEL[asset.project_sector] ?? asset.project_sector}
          {asset.portfolio_name ? ` · ${asset.portfolio_name}` : ' · بدون محفظة'}
        </small>
      </td>
      <td>
        {asset.operational_state ? (
          <span className="status">
            {ASSET_STATE_LABEL[asset.operational_state] ?? asset.operational_state}
          </span>
        ) : (
          <span className="muted">{statusLabel(asset.operational_state_basis)}</span>
        )}
        {classification ? (
          <>
            <br />
            <small className="muted">{classification}</small>
          </>
        ) : null}
      </td>
      <td>
        <Figure
          minorUnits={asset.acquisition_cost_minor_units}
          currency={asset.acquisition_cost_currency}
          status={asset.acquisition_cost_status}
        />
      </td>
      <td>
        <Figure
          minorUnits={asset.latest_approved_valuation_minor_units}
          currency={asset.latest_approved_valuation_currency}
          status={asset.latest_approved_valuation_status}
        />
        {asset.latest_approved_valuation_date ? (
          <>
            <br />
            <small className="muted">
              بتاريخ {new Date(asset.latest_approved_valuation_date).toLocaleDateString('ar-EG')}
            </small>
          </>
        ) : null}
      </td>
      <td>
        <Figure
          minorUnits={asset.realized_result_minor_units}
          currency={asset.realized_result_currency}
          status={asset.realized_result_status}
        />
      </td>
    </tr>
  );
}

function SectorCard({ row }: Readonly<{ row: SectorPerformance }>) {
  const money = (value: string | null) =>
    value === null ? null : formatMinorUnits(value, row.currency);
  const converted = row.converted_realized_result_minor_units;

  return (
    <section className="panel">
      <h3>
        {SECTOR_LABEL[row.sector] ?? row.sector}{' '}
        <span className="status">{row.currency}</span>
      </h3>
      <p className="muted">
        {row.project_count} مشروع · {row.asset_count} أصل مُسجَّل
      </p>

      <div className="gate">
        <span>النقدية</span>
        <strong>{money(row.cash_balance_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>الإيراد المعترف به</span>
        <strong>{money(row.revenue_recognized_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>تكلفة المبيعات</span>
        <strong>{money(row.cost_of_sale_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>النتيجة المحققة</span>
        <strong>{money(row.realized_result_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>المساهمات المستلمة</span>
        <strong>{money(row.contributions_received_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>ذمم مدينة مفتوحة</span>
        <strong>{money(row.receivable_open_minor_units)}</strong>
      </div>
      <div className="gate">
        <span>ذمم دائنة مفتوحة</span>
        <strong>{money(row.payable_open_minor_units)}</strong>
      </div>

      <p className="muted">
        تحويل العملة: {FX_STATUS_LABEL[row.fx_status] ?? row.fx_status}
        {row.fx_rate_date
          ? ` · لقطة ${new Date(row.fx_rate_date).toLocaleDateString('ar-EG')}`
          : ''}
      </p>
      {converted && row.org_reporting_currency ? (
        <div className="gate">
          <span>النتيجة المحققة بعملة التقرير</span>
          <strong>{formatMinorUnits(converted, row.org_reporting_currency)}</strong>
        </div>
      ) : (
        <p className="muted">
          لا نعرض مبلغًا محوّلًا: التحويل غير متاح لكل مشاريع هذا القطاع، وعرض مجموع
          جزئي سيكون رقمًا مضلِّلًا.
        </p>
      )}
    </section>
  );
}

export default async function AssetsPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <section className="card stack">
        <h1>لنبدأ بإنشاء منظمتك</h1>
        <p className="muted">المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك.</p>
        <Link className="button" href="/onboarding">إنشاء منظمة</Link>
      </section>
    );
  }

  const [assets, performance] = await Promise.all([
    getRegisteredAssets(org.id),
    getSectorPerformance(org.id),
  ]);

  return (
    <section className="stack">
      <PageHeader
        eyebrow={org.name}
        title="الأصول وأداء القطاعات"
        description="عرض موحَّد للقراءة فقط فوق أصول القطاعات. كل أصل ما زال مملوكًا ومُدارًا داخل قطاعه ومشروعه؛ هذه الصفحة لا تنشئ سجلًا موحَّدًا للأصول ولا تكتب أي بيانات."
      />

      <section className="stack">
        <h2>أداء القطاعات</h2>
        {performance.length === 0 ? (
          <section className="card stack empty">
            <h3>لا توجد قطاعات لعرضها بعد</h3>
            <p className="muted">
              أنشئ مشروعًا أولًا؛ سيظهر قطاعه هنا فور تسجيله، حتى قبل تسجيل أي حركة مالية.
            </p>
            <Link className="button" href="/intake">بدء إدخال المشروع</Link>
          </section>
        ) : (
          <div className="panel-grid">
            {performance.map((row) => (
              <SectorCard key={`${row.sector}-${row.currency}`} row={row} />
            ))}
          </div>
        )}
      </section>

      <section className="stack">
        <h2>سجل الأصول عبر القطاعات</h2>
        {assets.length === 0 ? (
          <section className="card stack empty">
            <h3>لا توجد أصول مُسجَّلة بعد</h3>
            <p className="muted">
              تُسجَّل الأصول من داخل مساحة عمل كل قطاع: أصل عقاري، أرض زراعية، مزرعة،
              أو موقع ثروة حيوانية. لن نعرض هنا أرقامًا تقديرية أو بيانات تجريبية.
            </p>
          </section>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="muted">
                {assets.length} أصل مُسجَّل عبر جميع القطاعات
              </caption>
              <thead>
                <tr>
                  <th scope="col">الأصل</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">الحالة</th>
                  <th scope="col">تكلفة الاقتناء</th>
                  <th scope="col">آخر تقييم معتمد</th>
                  <th scope="col">النتيجة المحققة</th>
                </tr>
              </thead>
              <tbody>
                {assets.map((asset) => (
                  <AssetRow key={`${asset.asset_kind}-${asset.asset_id}`} asset={asset} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </section>
  );
}
