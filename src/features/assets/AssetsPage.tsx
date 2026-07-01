import { PackageOpen, Trash2 } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { DetailRows } from '../../components/ui/DetailRows';
import { MetricCard } from '../../components/ui/MetricCard';
import { EmptyState } from '../../components/ui/States';
import { Button } from '../../components/ui/Button';
import { confirmSafeDeletion, guardAssetDeletion } from '../../core/lib/deletionGuards';
import { useProjects } from '../projects/hooks';
import { useAssets } from './hooks';
import { formatEgp } from '../../core/lib/profitability';
import { StockAdjustmentPanel } from './StockAdjustmentPanel';
import type { AssetStatus, AssetType } from '../../core/types/domain';

const TYPE_LABELS: Record<AssetType, string> = {
  land: 'أرض',
  building: 'مبنى',
  farm: 'مزرعة',
  equipment: 'معدات',
  herd: 'قطيع',
  animal_group: 'مجموعة حيوانات',
  crop: 'محصول',
  other: 'أصل آخر',
};

const STATUS_LABELS: Record<AssetStatus, string> = {
  owned: 'مملوك',
  leased: 'مؤجر',
  sold: 'مباع',
  disposed: 'مستبعد',
};

// Assets that track live quantity via events + adjustments
const QUANTITY_TYPES: AssetType[] = ['herd', 'animal_group', 'crop'];
const QUANTITY_SECTORS = ['agriculture', 'livestock'];

function shouldShowAdjPanel(asset: import('../../core/types/domain').Asset): boolean {
  return QUANTITY_TYPES.includes(asset.type) && QUANTITY_SECTORS.includes(asset.sector_id);
}

export function AssetsPage() {
  const { assets, deleteAsset } = useAssets();
  const { projects } = useProjects();
  const projectNames = new Map(projects.map((project) => [project.id, project.name_ar]));
  const totalAcquisition = assets.reduce((sum, asset) => sum + asset.acquisition_cost_egp, 0);
  const totalCurrentValue = assets.reduce((sum, asset) => sum + (asset.current_value_egp ?? asset.acquisition_cost_egp), 0);

  async function handleDeleteAsset(assetId: string) {
    const guard = await guardAssetDeletion(assetId);
    if (!guard.canDelete) {
      window.alert(guard.message_ar);
      return;
    }
    if (!confirmSafeDeletion(guard.message_ar)) return;
    deleteAsset(assetId);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="الأصول"
        description="عرض كل الأصول المملوكة أو المشغلة عبر المشاريع والقطاعات."
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <MetricCard label="عدد الأصول" value={assets.length} />
        <MetricCard label="تكلفة الاقتناء" value={formatEgp(totalAcquisition, true)} unit="EGP" />
        <MetricCard label="القيمة الحالية" value={formatEgp(totalCurrentValue, true)} unit="EGP" tone="primary" />
      </div>

      {assets.length === 0 ? (
        <EmptyState title="لا توجد أصول بعد" description="ستظهر هنا الأصول المسجلة داخل المشاريع." icon={PackageOpen} />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {assets.map((asset) => (
            <Card key={asset.id}>
              <CardContent className="p-5">
                <div className="mb-4 flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-foreground">{asset.name_ar}</p>
                    {asset.name_en && <p className="text-xs text-muted-foreground" dir="ltr">{asset.name_en}</p>}
                  </div>
                  <Badge tone={asset.status === 'owned' ? 'positive' : asset.status === 'sold' ? 'warning' : 'neutral'}>
                    {STATUS_LABELS[asset.status]}
                  </Badge>
                </div>

                <DetailRows
                  items={[
                    { id: 'type', label: 'النوع', value: TYPE_LABELS[asset.type] },
                    { id: 'project', label: 'المشروع', value: projectNames.get(asset.project_id) ?? 'مشروع غير معروف' },
                    { id: 'acquisition-cost', label: 'تكلفة الاقتناء', value: `${formatEgp(asset.acquisition_cost_egp, true)} EGP`, valueClassName: 'font-bold' },
                    { id: 'current-value', label: 'القيمة الحالية', value: `${formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp, true)} EGP`, valueClassName: 'font-bold text-primary' },
                    ...(asset.quantity != null ? [{ id: 'qty', label: 'الكمية الأساسية', value: `${asset.quantity} ${asset.unit ?? ''}` }] : []),
                  ]}
                />

                {/* Stock adjustments panel — only for quantity-bearing assets */}
                {shouldShowAdjPanel(asset) && (
                  <StockAdjustmentPanel asset={asset} />
                )}

                <Button variant="danger" size="sm" className="mt-4 w-full" onClick={() => handleDeleteAsset(asset.id)}>
                  <Trash2 className="h-4 w-4" /> حذف الأصل
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
