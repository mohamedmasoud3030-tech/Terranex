import {
  AppShell,
  DataTableShell,
  EmptyState,
  ErrorState,
  KpiCard,
  LoadingSkeleton,
  PageHeader,
  PeriodFilter,
  RecordDetailDrawer,
  SectorCard,
} from './components/ui';
import { dashboardKpis, obligations, sectors } from './data/fixtures';

export function App() {
  return (
    <AppShell>
      <PageHeader
        title="أين تقف الشركة ماليًا وتشغيليًا الآن؟"
        description="واجهة تأسيسية تربط الأصول والمشاريع والقطاعات والالتزامات والمستندات في لوحة عربية RTL قابلة للتطوير. الأرقام الحالية بيانات تجريبية معزولة وليست حسابات إنتاجية."
      />

      <section aria-labelledby="period-filter" className="mb-6 rounded-3xl border border-border bg-card p-4">
        <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <h2 id="period-filter" className="text-lg font-bold">نطاق العرض</h2>
            <p className="mt-1 text-sm text-muted-foreground">كل رقم مالي يجب أن يظهر معه الفترة والعملة ومصدر السجل.</p>
          </div>
          <PeriodFilter />
        </div>
      </section>

      <section aria-labelledby="kpis" className="mb-6">
        <h2 id="kpis" className="sr-only">المؤشرات المالية</h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {dashboardKpis.map((kpi) => <KpiCard kpi={kpi} key={kpi.id} />)}
        </div>
      </section>

      <section aria-labelledby="sectors" className="mb-6">
        <div className="mb-4 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <div>
            <h2 id="sectors" className="text-xl font-bold">القطاعات الاستثمارية</h2>
            <p className="mt-1 text-sm text-muted-foreground">بطاقات قطاعية أولية قابلة للتحويل لاحقًا إلى صفحات كاملة.</p>
          </div>
        </div>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {sectors.map((sector) => <SectorCard sector={sector} key={sector.id} />)}
        </div>
      </section>

      <div className="mb-6 grid gap-6 xl:grid-cols-[2fr_1fr]">
        <DataTableShell obligations={obligations} />
        <RecordDetailDrawer />
      </div>

      <section className="grid gap-6 lg:grid-cols-2">
        <LoadingSkeleton />
        <ErrorState />
        <EmptyState
          title="لا توجد مستندات مرتبطة بعد"
          description="هذه حالة فارغة جاهزة للاستخدام عند بناء صفحة المستندات والقرارات. لا يجب أن تظهر صفحة تشغيلية بدون حالة فارغة واضحة."
        />
      </section>
    </AppShell>
  );
}
