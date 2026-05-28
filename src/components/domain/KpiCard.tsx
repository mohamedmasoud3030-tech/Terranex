import { ArrowUpLeft } from 'lucide-react';
import { Card, CardContent } from '../ui/Card';
import { Badge } from '../ui/Badge';
import { MoneyValue } from '../ui/MoneyValue';
import { useI18n } from '../../core/i18n';
import type { KpiCardVM } from '../../core/types/ui';

interface KpiCardProps {
  kpi: KpiCardVM;
}

export function KpiCard({ kpi }: KpiCardProps) {
  const { locale } = useI18n();

  const title = locale === 'ar' ? kpi.title_ar : kpi.title_en;
  const period = locale === 'ar' ? kpi.period_ar : kpi.period_en;
  const trend = locale === 'ar' ? kpi.trend_ar : kpi.trend_en;
  const source = locale === 'ar' ? kpi.source_ar : kpi.source_en;

  return (
    <Card>
      <CardContent>
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm text-muted-foreground">{title}</p>
            <div className="mt-3">
              <MoneyValue amount={kpi.value} currency={kpi.currency} size="xl" />
            </div>
          </div>
          <Badge tone={kpi.status}>{period}</Badge>
        </div>
        <p className="mt-4 text-sm text-muted-foreground">{trend}</p>
        {kpi.drill_route ? (
          <a
            className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-primary underline-offset-4 hover:underline"
            href={kpi.drill_route}
          >
            <ArrowUpLeft className="h-4 w-4" aria-hidden="true" />
            {source}
          </a>
        ) : (
          <p className="mt-4 text-xs text-muted-foreground">{source}</p>
        )}
      </CardContent>
    </Card>
  );
}
