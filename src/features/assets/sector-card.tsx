import { SectorChip } from '@/shared/ui';
import { formatMinorUnits } from '@/shared/money';
import type { SectorPerformance } from './queries';
import { FX_STATUS_LABEL, SECTOR_LABEL } from './labels';

/** One sector-and-currency performance card. Shared by /assets and /reports. */
export function SectorCard({ row }: Readonly<{ row: SectorPerformance }>) {
  const money = (value: string | null) =>
    value === null ? null : formatMinorUnits(value, row.currency);
  const converted = row.converted_realized_result_minor_units;

  return (
    <section className="panel">
      <h3 className="badge-row">
        <SectorChip sector={row.sector} label={SECTOR_LABEL[row.sector] ?? row.sector} />
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
