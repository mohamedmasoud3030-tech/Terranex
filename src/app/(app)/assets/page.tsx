import Link from 'next/link';
import { EmptyState, PageHeader, SectorChip, Section } from '@/shared/ui';
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
  SECTOR_LABEL,
  isAbsence,
  statusLabel,
} from '@/features/assets/labels';
import { formatMinorUnits } from '@/shared/money';
import { SectorCard } from '@/features/assets/sector-card';
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
          <strong>{asset.project_name}</strong>
        </Link>
        <br />
        <SectorChip
          sector={asset.project_sector}
          label={SECTOR_LABEL[asset.project_sector] ?? asset.project_sector}
        />
        <br />
        <small className="muted">{asset.portfolio_name ? asset.portfolio_name : 'بدون محفظة'}</small>
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
      <td className="num">
        <Figure
          minorUnits={asset.acquisition_cost_minor_units}
          currency={asset.acquisition_cost_currency}
          status={asset.acquisition_cost_status}
        />
      </td>
      <td className="num">
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
      <td className="num">
        <Figure
          minorUnits={asset.realized_result_minor_units}
          currency={asset.realized_result_currency}
          status={asset.realized_result_status}
        />
      </td>
    </tr>
  );
}

export default async function AssetsPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="المنظمة هي الحدود الآمنة لبيانات الاستثمار الخاصة بفريقك."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }

  const [assets, performance] = await Promise.all([
    getRegisteredAssets(org.id),
    getSectorPerformance(org.id),
  ]);

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="الأصول وأداء القطاعات"
        description="عرض موحَّد للقراءة فقط فوق أصول القطاعات. كل أصل ما زال مملوكًا ومُدارًا داخل قطاعه ومشروعه؛ هذه الصفحة لا تنشئ سجلًا موحَّدًا للأصول ولا تكتب أي بيانات."
      />

      <Section title="أداء القطاعات" description="كل قطاع بعملة مشاريعه الأصلية؛ لا تُجمع أرقام عبر عملات مختلفة.">
        {performance.length === 0 ? (
          <EmptyState
            title="لا توجد قطاعات لعرضها بعد"
            description="أنشئ مشروعًا أولًا؛ سيظهر قطاعه هنا فور تسجيله، حتى قبل تسجيل أي حركة مالية."
            action={<Link className="button" href="/intake">بدء إدخال المشروع</Link>}
          />
        ) : (
          <div className="panel-grid">
            {performance.map((row) => (
              <SectorCard key={`${row.sector}-${row.currency}`} row={row} />
            ))}
          </div>
        )}
      </Section>

      <Section title="سجل الأصول عبر القطاعات" description={`${assets.length} أصل مُسجَّل — قراءة فقط، بلا أرقام تقديرية.`}>
        {assets.length === 0 ? (
          <EmptyState
            title="لا توجد أصول مُسجَّلة بعد"
            description="تُسجَّل الأصول من داخل مساحة عمل كل قطاع: أصل عقاري، أرض زراعية، مزرعة، أو موقع ثروة حيوانية. لن نعرض هنا أرقامًا تقديرية أو بيانات تجريبية."
          />
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">
                سجل الأصول عبر القطاعات: الأصل والمشروع والقطاع والحالة وتكلفة الاقتناء وآخر تقييم معتمد والنتيجة المحققة
              </caption>
              <thead>
                <tr>
                  <th scope="col">الأصل</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">الحالة</th>
                  <th scope="col" className="num">تكلفة الاقتناء</th>
                  <th scope="col" className="num">آخر تقييم معتمد</th>
                  <th scope="col" className="num">النتيجة المحققة</th>
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
      </Section>
    </section>
  );
}
