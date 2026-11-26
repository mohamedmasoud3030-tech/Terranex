import Link from 'next/link';
import { SECTOR_LABEL } from '@/features/agriculture/labels';
import { formatMinorUnits } from '@/shared/money';
import { SectorChip } from '@/shared/ui';
import { SECTOR_THEME_CLASS } from '@/shared/ui/sector';
import type { SectorPerformance } from './queries';

/**
 * One card per sector and currency. Bars compare figures of the SAME card
 * only, so they never mix currencies: cash, recognized revenue and posted
 * expense are all in the card's own currency. A bar for a figure that is
 * zero is drawn empty, never hidden, so the absence is visible.
 */
function toBig(value: string): bigint {
  try {
    return BigInt(value);
  } catch {
    return BigInt(0);
  }
}

function pct(value: bigint, max: bigint): number {
  if (max <= BigInt(0) || value <= BigInt(0)) return 0;
  return Math.max(2, Number((value * BigInt(1000)) / max) / 10);
}

export function SectorCards({ rows }: { rows: SectorPerformance[] }) {
  if (rows.length === 0) return null;
  return (
    <div className="sector-cards" role="list" aria-label="بطاقات القطاعات">
      {rows.map((row) => {
        const bars = [
          { key: 'cash', label: 'النقدية', value: toBig(row.cash_balance_minor_units), tone: 'cash' },
          { key: 'rev', label: 'الإيراد المعترف به', value: toBig(row.revenue_recognized_minor_units), tone: 'rev' },
          { key: 'exp', label: 'المصروف المرحّل', value: toBig(row.expense_posted_minor_units), tone: 'exp' },
        ];
        const max = bars.reduce((m, b) => (b.value > m ? b.value : m), BigInt(0));
        return (
          <article
            className={`sector-card ${SECTOR_THEME_CLASS[row.sector]}`}
            key={`${row.sector}-${row.currency}`}
            role="listitem"
          >
            <header className="sector-card-head">
              <SectorChip sector={row.sector} label={SECTOR_LABEL[row.sector] ?? row.sector} />
              <span className="muted">{row.currency}</span>
            </header>
            <dl className="sector-card-counts">
              <div>
                <dt>المشاريع</dt>
                <dd>{row.project_count}</dd>
              </div>
              <div>
                <dt>الأصول</dt>
                <dd>{row.asset_count}</dd>
              </div>
            </dl>
            <ul className="sector-bars">
              {bars.map((bar) => (
                <li key={bar.key}>
                  <div className="sector-bar-label">
                    <span>{bar.label}</span>
                    <strong>{formatMinorUnits(bar.value.toString(), row.currency)}</strong>
                  </div>
                  <div className="sector-bar-track" aria-hidden="true">
                    <span className={`sector-bar-fill ${bar.tone}`} style={{ width: `${pct(bar.value, max)}%` }} />
                  </div>
                </li>
              ))}
            </ul>
            <Link className="button secondary sm" href="/assets">تفاصيل القطاع</Link>
          </article>
        );
      })}
    </div>
  );
}
