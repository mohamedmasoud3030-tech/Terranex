import { AlertTriangle, Boxes, ClipboardList, FolderKanban } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import type { ReturnType } from './types';

interface OperationsOverviewProps {
  overview: ReturnType;
  locale: 'ar' | 'en';
  assetName: (id: string) => string;
  onInspectEvent: (id: string) => void;
}

export function OperationsOverview({
  overview,
  locale,
  assetName,
  onInspectEvent,
}: OperationsOverviewProps) {
  const metrics = [
    { icon: FolderKanban, ar: 'المشاريع', en: 'Projects', value: overview.projectCount },
    { icon: Boxes, ar: 'الأصول', en: 'Assets', value: overview.assetCount },
    { icon: ClipboardList, ar: 'الأحداث', en: 'Events', value: overview.eventCount },
    { icon: AlertTriangle, ar: 'تحتاج متابعة', en: 'Needs attention', value: overview.assetsNeedingAttention.length },
  ];
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
        {metrics.map(({ icon: Icon, ar, en, value }) => (
          <Card key={en}>
            <CardContent className="p-4">
              <Icon className="h-5 w-5 text-primary" />
              <p className="mt-3 text-xs text-muted-foreground">{locale === 'ar' ? ar : en}</p>
              <p className="text-2xl font-extrabold">{value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader>
          <h2 className="font-bold">{locale === 'ar' ? 'قائمة المتابعة الحقيقية' : 'Live attention queue'}</h2>
        </CardHeader>
        <CardContent>
          {!overview.recentEvents.length && !overview.recentAdjustments.length && !overview.assetsNeedingAttention.length ? (
            <EmptyState
              title={locale === 'ar' ? 'لا توجد عناصر متابعة' : 'No attention items'}
              description={locale === 'ar' ? 'ستظهر الأحداث والتصحيحات والأصول غير النشطة هنا.' : 'Events, adjustments, and inactive assets will appear here.'}
              icon={ClipboardList}
            />
          ) : (
            <div className="space-y-3">
              {overview.recentEvents.map((event) => (
                <button
                  key={event.id}
                  type="button"
                  onClick={() => onInspectEvent(event.id)}
                  className="min-h-11 w-full rounded-2xl border p-3 text-start hover:bg-muted"
                >
                  <span className="font-semibold">{assetName(event.asset_id)}</span>
                  <span className="block text-xs text-muted-foreground">{event.type} · {event.event_date}</span>
                </button>
              ))}
              {overview.recentAdjustments.map((adjustment) => (
                <div key={adjustment.id} className="rounded-2xl border p-3">
                  <p className="font-semibold">{assetName(adjustment.asset_id)}</p>
                  <p className="text-xs text-muted-foreground">
                    {locale === 'ar' ? 'تصحيح رصيد' : 'Stock adjustment'} · {adjustment.quantity_before} → {adjustment.quantity_after}
                  </p>
                </div>
              ))}
              {overview.assetsNeedingAttention.map((asset) => (
                <div key={asset.id} className="rounded-2xl border border-warning/30 bg-warning/5 p-3">
                  <p className="font-semibold">{locale === 'ar' ? asset.name_ar : asset.name_en}</p>
                  <p className="text-xs text-muted-foreground">{locale === 'ar' ? 'لا يوجد نشاط مسجل أو الرصيد الحي صفر.' : 'No recorded activity or live balance is zero.'}</p>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
