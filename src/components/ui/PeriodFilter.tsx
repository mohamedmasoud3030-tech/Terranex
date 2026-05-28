import { useI18n } from '../../core/i18n';
import type { PeriodFilter } from '../../core/types';

interface PeriodFilterProps {
  value: PeriodFilter;
  onChange: (p: PeriodFilter) => void;
}

const OPTIONS: PeriodFilter[] = ['month', 'quarter', 'year', 'all'];

const keyMap: Record<PeriodFilter, 'period_month' | 'period_quarter' | 'period_year' | 'period_all' | 'period_custom'> = {
  month: 'period_month',
  quarter: 'period_quarter',
  year: 'period_year',
  all: 'period_all',
  custom: 'period_custom',
};

export function PeriodFilter({ value, onChange }: PeriodFilterProps) {
  const { t } = useI18n();

  return (
    <div className="flex flex-wrap gap-2" role="group" aria-label={t('dashboard_period_label')}>
      {OPTIONS.map((opt) => (
        <button
          key={opt}
          onClick={() => onChange(opt)}
          className={[
            'h-9 rounded-full border px-4 text-sm font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
            value === opt
              ? 'border-primary bg-primary text-white'
              : 'border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground',
          ].join(' ')}
          aria-pressed={value === opt}
        >
          {t(keyMap[opt])}
        </button>
      ))}
    </div>
  );
}
