import { PackageOpen } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useProjects } from '../projects/hooks';
import { useAssets } from './hooks';
import { formatEgp } from '../../core/lib/profitability';
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

export function AssetsPage() {
  const { assets } = useAssets();
  const { projects } = useProjects();
  const projectNames = new Map(projects.map((project) => [project.id, project.name_ar]));
  const totalAcquisition = assets.reduce((sum, asset) => sum + asset.acquisition_cost_egp, 0);
  const totalCurrentValue = assets.reduce((sum, asset) => sum + (asset.current_value_egp ?? asset.acquisition_cost_egp), 0);

  return (
    <div className="space-y-6">
      <PageHeader
        title="الأصول"
        description="عرض كل الأصول المملوكة أو المشغلة عبر المشاريع والقطاعات."
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">عدد الأصول</p>
            <p className="mt-2 text-2xl font-bold">{assets.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">تكلفة الاقتناء</p>
            <p className="mt-2 text-2xl font-bold">{formatEgp(totalAcquisition, true)} EGP</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">القيمة الحالية</p>
            <p className="mt-2 text-2xl font-bold text-primary">{formatEgp(totalCurrentValue, true)} EGP</p>
          </CardContent>
        </Card>
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

                <div className="space-y-2 text-sm">
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">النوع</span>
                    <span className="font-medium">{TYPE_LABELS[asset.type]}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">المشروع</span>
                    <span className="font-medium">{projectNames.get(asset.project_id) ?? 'مشروع غير معروف'}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">تكلفة الاقتناء</span>
                    <span className="font-bold">{formatEgp(asset.acquisition_cost_egp, true)} EGP</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">القيمة الحالية</span>
                    <span className="font-bold text-primary">{formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp, true)} EGP</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
