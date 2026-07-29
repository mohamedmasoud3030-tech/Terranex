import { Boxes, ClipboardList } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import type { Asset, OperationalEvent, StockAdjustment } from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';
import type { OperationsContext } from './model';

interface AssetBalancesWorkspaceProps {
  assets: Asset[];
  events: OperationalEvent[];
  adjustments: StockAdjustment[];
  context: OperationsContext;
  locale: 'ar' | 'en';
  onAdjust: (asset: Asset) => void;
}

export function AssetBalancesWorkspace({
  assets,
  events,
  adjustments,
  context,
  locale,
  onAdjust,
}: AssetBalancesWorkspaceProps) {
  const scoped = assets.filter((asset) =>
    asset.sector_id !== 'real-estate'
    && (context.sector === 'all' || asset.sector_id === context.sector)
    && (!context.projectId || asset.project_id === context.projectId)
    && (!context.assetId || asset.id === context.assetId),
  );
  return (
    <Card>
      <CardHeader>
        <h2 className="font-bold">{locale === 'ar' ? 'الأرصدة والتصحيحات' : 'Balances and adjustments'}</h2>
        <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'التصحيح إجراء استثنائي محفوظ في سجل مستقل، وليس حدثًا يوميًا.' : 'An adjustment is a guarded exception in its own audit trail, not a daily event.'}</p>
      </CardHeader>
      <CardContent>
        {!scoped.length ? (
          <EmptyState
            title={locale === 'ar' ? 'لا توجد أصول كمية' : 'No quantity-bearing assets'}
            description={locale === 'ar' ? 'الأرصدة الحية متاحة للأصول الزراعية والحيوانية الموجودة فقط.' : 'Live balances are available only for existing agriculture and livestock assets.'}
            icon={Boxes}
          />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {scoped.map((asset) => {
              const assetEvents = events.filter((event) => event.asset_id === asset.id);
              const assetAdjustments = adjustments.filter((adjustment) => adjustment.asset_id === asset.id);
              const balance = computeAssetLiveQuantity(asset.quantity ?? 0, assetEvents, assetAdjustments);
              const latestAdjustment = [...assetAdjustments].sort((a, b) => b.adjustment_date.localeCompare(a.adjustment_date))[0];
              return (
                <article key={asset.id} className="rounded-2xl border p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h3 className="font-bold">{locale === 'ar' ? asset.name_ar : asset.name_en}</h3>
                      <p className="text-xs text-muted-foreground">{asset.type}</p>
                    </div>
                    <Badge tone={balance.quantity > 0 ? 'positive' : 'warning'}>
                      {balance.quantity} {asset.unit ?? ''}
                    </Badge>
                  </div>
                  <dl className="mt-4 grid grid-cols-2 gap-3 text-xs">
                    <div>
                      <dt className="text-muted-foreground">{locale === 'ar' ? 'الأحداث' : 'Events'}</dt>
                      <dd className="font-bold">{assetEvents.length}</dd>
                    </div>
                    <div>
                      <dt className="text-muted-foreground">{locale === 'ar' ? 'التصحيحات' : 'Adjustments'}</dt>
                      <dd className="font-bold">{assetAdjustments.length}</dd>
                    </div>
                  </dl>
                  {latestAdjustment && (
                    <p className="mt-3 text-xs text-muted-foreground">
                      {locale === 'ar' ? 'آخر تصحيح' : 'Last adjustment'}: {latestAdjustment.adjustment_date} · {latestAdjustment.quantity_before} → {latestAdjustment.quantity_after}
                    </p>
                  )}
                  <Button type="button" variant="secondary" className="mt-4 min-h-11 w-full" onClick={() => onAdjust(asset)}>
                    <ClipboardList className="h-4 w-4" />
                    {locale === 'ar' ? 'تصحيح محكوم' : 'Guarded adjustment'}
                  </Button>
                </article>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
