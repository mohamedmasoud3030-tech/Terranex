import { ArrowUpLeft } from 'lucide-react';
import { Card, CardContent } from '../ui/Card';
import { Badge } from '../ui/Badge';
import { useI18n } from '../../core/i18n';
import type { SectorCardVM } from '../../core/types/ui';
import type { StatusTone } from '../../core/types/ui';

const statusTone: Record<SectorCardVM['status'], StatusTone> = {
  active: 'positive',
  review: 'warning',
  stable: 'neutral',
  inactive: 'negative',
};

const statusKeyMap: Record<SectorCardVM['status'], 'sector_status_active' | 'sector_status_review' | 'sector_status_stable' | 'sector_status_inactive'> = {
  active: 'sector_status_active',
  review: 'sector_status_review',
  stable: 'sector_status_stable',
  inactive: 'sector_status_inactive',
};

interface SectorCardProps {
  sector: SectorCardVM;
}

export function SectorCard({ sector }: SectorCardProps) {
  const { locale, t } = useI18n();

  const name = locale === 'ar' ? sector.name_ar : sector.name_en;
  const description = locale === 'ar' ? sector.description_ar : sector.description_en;
  const metricLabel = locale === 'ar' ? sector.metric_label_ar : sector.metric_label_en;

  return (
    <Card>
      <CardContent>
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="text-lg font-bold">{name}</h3>
            <p className="mt-2 min-h-14 text-sm leading-7 text-muted-foreground">{description}</p>
          </div>
          <Badge tone={statusTone[sector.status]}>{t(statusKeyMap[sector.status])}</Badge>
        </div>
        <div className="mt-5 rounded-2xl bg-muted p-4">
          <p className="text-xs text-muted-foreground">{metricLabel}</p>
          <p className="mt-1 text-2xl font-bold">{sector.metric_value}</p>
        </div>
        <a
          className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-primary underline-offset-4 hover:underline"
          href={sector.href}
        >
          {t('sector_open_record')}
          <ArrowUpLeft className="h-4 w-4" aria-hidden="true" />
        </a>
      </CardContent>
    </Card>
  );
}
