import { useMemo, useState } from 'react';
import { Building2, FileSearch, Search } from 'lucide-react';
import { KpiCard } from '../../components/domain/KpiCard';
import { PageHeader } from '../../components/layout/PageHeader';
import { EmptyState } from '../../components/ui/States';
import { Card, CardContent } from '../../components/ui/Card';
import { cn } from '../../core/lib/cn';
import type { AssetRowVM } from '../../core/types/ui';
import { AssetDetailDrawer } from './AssetDetailDrawer';
import { findRealEstateAsset, realEstateKpis, realEstateRows } from './fixtures';
import { RealEstateTable } from './RealEstateTable';

export function RealEstatePage() {
  const [query, setQuery] = useState('');
  const [selectedAssetId, setSelectedAssetId] = useState<string | null>(null);

  const filteredRows = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    if (!normalizedQuery) return realEstateRows;

    return realEstateRows.filter((asset) => {
      return [asset.name_ar, asset.project_name_ar, asset.location ?? '']
        .join(' ')
        .toLowerCase()
        .includes(normalizedQuery);
    });
  }, [query]);

  const selectedAsset = selectedAssetId ? findRealEstateAsset(selectedAssetId) : null;

  function handleRowClick(row: AssetRowVM) {
    setSelectedAssetId(row.id);
  }

  return (
    <>
      <PageHeader
        title="محفظة الاستثمار العقاري"
        description="إدارة الأصول العقارية على مستوى الاستثمار: الشراء، التطوير، التقييم، البيع، الربح، وحقوق الشركاء."
      />

      <section className="mb-6 rounded-3xl border border-info/30 bg-info/5 p-4" aria-labelledby="real-estate-question">
        <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wide text-info">السؤال التشغيلي الأساسي</p>
            <h2 id="real-estate-question" className="mt-2 text-xl font-bold">
              أي الأصول العقارية مربحة أو تحت التطوير أو جاهزة للبيع؟
            </h2>
            <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">
              هذه الصفحة لا تدير مستأجرين أو وحدات صغيرة. هي محفظة أصول: تكلفة شراء، CAPEX، تقييم، بيع، التزامات، مستندات، وحصص شركاء.
            </p>
          </div>
          <div className="rounded-2xl border border-info/20 bg-card px-4 py-3 text-sm font-semibold text-info">
            العملة الأساسية: EGP / ج.م
          </div>
        </div>
      </section>

      <section aria-labelledby="real-estate-kpis" className="mb-6">
        <h2 id="real-estate-kpis" className="sr-only">مؤشرات محفظة الاستثمار العقاري</h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
          {realEstateKpis.map((kpi) => (
            <KpiCard key={kpi.id} kpi={kpi} />
          ))}
        </div>
      </section>

      <Card className="mb-6">
        <CardContent>
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h2 className="text-xl font-bold">سجل الأصول العقارية</h2>
              <p className="mt-1 text-sm leading-7 text-muted-foreground">
                الجدول يعرض الأصل، المشروع، الحالة، رأس المال المستثمر، التقييم، والربح/الخسارة. اضغط على أي صف لعرض مصدر الأرقام.
              </p>
            </div>
            <label className="relative w-full max-w-md">
              <span className="sr-only">بحث في الأصول</span>
              <Search className="pointer-events-none absolute end-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
              <input
                className="w-full rounded-xl border border-border bg-background py-2 pe-10 ps-3 text-sm outline-none transition focus-visible:ring-2 focus-visible:ring-primary"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="ابحث باسم الأصل أو المشروع أو الموقع…"
              />
            </label>
          </div>

          <div className="mt-4 rounded-2xl border border-border bg-muted/30 p-3 text-sm leading-7 text-muted-foreground">
            <div className="flex items-start gap-2">
              <FileSearch className="mt-1 h-4 w-4 shrink-0 text-info" aria-hidden="true" />
              <p>
                مسار التدقيق: كل KPI يجب أن يرجع إلى صف أصل، وكل صف يرجع إلى معاملات ومستندات والتزامات وشركاء داخل التفاصيل.
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      <section className={cn('rounded-3xl border border-border bg-card p-4 shadow-sm', filteredRows.length === 0 && 'bg-transparent p-0 shadow-none')}>
        {filteredRows.length > 0 ? (
          <RealEstateTable data={filteredRows} onRowClick={handleRowClick} />
        ) : (
          <EmptyState
            title="لا توجد أصول مطابقة"
            description="غيّر كلمات البحث أو امسح الفلتر لعرض كامل المحفظة العقارية."
            icon={Building2}
            action={{ label: 'مسح البحث', onClick: () => setQuery('') }}
          />
        )}
      </section>

      <AssetDetailDrawer asset={selectedAsset} onClose={() => setSelectedAssetId(null)} />
    </>
  );
}
