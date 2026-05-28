import { useState } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { KpiCard } from '../../components/domain/KpiCard';
import { EmptyState } from '../../components/ui/States';
import { Button } from '../../components/ui/Button';
import { FinancialRecordDialog } from '../finance/FinancialRecordDialog';
import { FinancialRecordsTable } from '../finance/FinancialRecordsTable';
import { calculateFinancialSummary } from '../finance/calculations';
import { useFinancialRecords } from '../finance/hooks';
import { SECTOR_LABELS_AR, type FinancialRecord, type FinancialRecordInput } from '../finance/types';
import type { KpiCardVM } from '../../core/types/ui';

const sectorDescriptions: Record<keyof typeof SECTOR_LABELS_AR, string> = {
  real_estate: 'أراضي وأصول وتطوير ومبيعات عقارية.',
  agriculture: 'مزارع ومحاصيل ومواسم ومدخلات وإنتاج.',
  livestock: 'قطعان وأعلاف وعلاج وتحصينات ومبيعات.',
  general: 'حركة مالية عامة غير مرتبطة بقطاع محدد.',
};

export function DashboardPage() {
  const { records, createRecord, updateRecord, deleteRecord, resetRecords } = useFinancialRecords();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingRecord, setEditingRecord] = useState<FinancialRecord | null>(null);
  const summary = calculateFinancialSummary(records);
  const hasRecords = records.length > 0;

  function openCreateDialog() {
    setEditingRecord(null);
    setIsDialogOpen(true);
  }

  function handleSubmit(input: FinancialRecordInput) {
    if (editingRecord) {
      updateRecord(editingRecord.id, input);
    } else {
      createRecord(input);
    }
    setIsDialogOpen(false);
    setEditingRecord(null);
  }

  function handleEdit(record: FinancialRecord) {
    setEditingRecord(record);
    setIsDialogOpen(true);
  }

  function handleDelete(id: string) {
    if (window.confirm('هل تريد حذف هذا السجل المالي؟')) {
      deleteRecord(id);
    }
  }

  function handleReset() {
    if (window.confirm('سيتم حذف كل السجلات المالية المحلية من هذا المتصفح. هل أنت متأكد؟')) {
      resetRecords();
    }
  }

  const kpis: KpiCardVM[] = [
    {
      id: 'income-total',
      title_ar: 'إجمالي الإيرادات',
      title_en: 'Total income',
      value: summary.totalIncome,
      currency: 'EGP',
      period_ar: 'كل السجلات المحلية',
      period_en: 'All local records',
      trend_ar: hasRecords ? 'محسوب من سجلات الإيراد فقط' : 'لا توجد إيرادات مسجلة بعد',
      trend_en: hasRecords ? 'Calculated from income records only' : 'No income records yet',
      status: 'positive',
      source_ar: 'السجلات التي أدخلها المستخدم',
      source_en: 'User-entered records',
    },
    {
      id: 'expense-total',
      title_ar: 'إجمالي المصروفات',
      title_en: 'Total expenses',
      value: summary.totalExpenses,
      currency: 'EGP',
      period_ar: 'كل السجلات المحلية',
      period_en: 'All local records',
      trend_ar: hasRecords ? 'محسوب من سجلات المصروفات فقط' : 'لا توجد مصروفات مسجلة بعد',
      trend_en: hasRecords ? 'Calculated from expense records only' : 'No expense records yet',
      status: 'warning',
      source_ar: 'السجلات التي أدخلها المستخدم',
      source_en: 'User-entered records',
    },
    {
      id: 'net-profit',
      title_ar: 'صافي الربح / الخسارة',
      title_en: 'Net profit / loss',
      value: summary.netProfit,
      currency: 'EGP',
      period_ar: 'إيرادات ناقص مصروفات',
      period_en: 'Income minus expenses',
      trend_ar: hasRecords ? 'حساب أولي غير نهائي من السجلات المحلية' : 'يظهر بعد إضافة الإيرادات والمصروفات',
      trend_en: hasRecords ? 'Preliminary local calculation' : 'Shown after adding income and expenses',
      status: summary.netProfit < 0 ? 'negative' : 'neutral',
      source_ar: 'السجلات التي أدخلها المستخدم',
      source_en: 'User-entered records',
    },
    {
      id: 'open-obligations',
      title_ar: 'الذمم المفتوحة',
      title_en: 'Open obligations',
      value: summary.openReceivables - summary.openPayables,
      currency: 'EGP',
      period_ar: 'مدينة ناقص دائنة',
      period_en: 'Receivable minus payable',
      trend_ar: `مدينة: ${summary.openReceivables.toLocaleString('ar-EG')} ج.م، دائنة: ${summary.openPayables.toLocaleString('ar-EG')} ج.م`,
      trend_en: 'Receivables and payables summary',
      status: 'info',
      source_ar: 'سجلات الذمم المحلية',
      source_en: 'Local obligation records',
    },
  ];

  const sectorCards = Object.entries(SECTOR_LABELS_AR).map(([sector, label]) => ({
    name_ar: label,
    description_ar: sectorDescriptions[sector as keyof typeof SECTOR_LABELS_AR],
    description_en: sector,
    metric_label_ar: 'سجلات مالية محلية',
    metric_value: summary.bySector[sector as keyof typeof SECTOR_LABELS_AR].toLocaleString('ar-EG'),
  }));

  return (
    <>
      <PageHeader
        title="لوحة القيادة"
        description="تبدأ Terranex فارغة. كل رقم هنا محسوب فقط من السجلات التي تضيفها محليًا في هذا المتصفح."
        action={{ label: 'إضافة سجل جديد', onClick: openCreateDialog }}
      >
        {hasRecords && <Button type="button" variant="danger" onClick={handleReset}>مسح بيانات المتصفح</Button>}
      </PageHeader>

      <section aria-labelledby="kpi-section" className="mb-6">
        <h2 id="kpi-section" className="sr-only">مؤشرات مالية محلية</h2>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {kpis.map((kpi) => <KpiCard kpi={kpi} key={kpi.id} />)}
        </div>
      </section>

      {!hasRecords && (
        <section className="mb-6">
          <EmptyState
            title="لا توجد بيانات بعد"
            description="ابدأ بإضافة أول سجل مالي لتظهر الأرقام هنا"
            action={{ label: 'إضافة سجل جديد', onClick: openCreateDialog }}
          />
        </section>
      )}

      <section aria-labelledby="sectors-section" className="mb-6 rounded-3xl border border-border bg-card p-4 shadow-sm">
        <h2 id="sectors-section" className="text-xl font-bold">القطاعات الاستثمارية</h2>
        <p className="mt-1 text-sm text-muted-foreground">هذه العدادات تبدأ من صفر وتزيد فقط عند إضافة سجلات مالية محلية.</p>
        <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {sectorCards.map((sector) => (
            <div key={sector.description_en} className="rounded-2xl border border-border bg-background p-4">
              <p className="text-lg font-bold">{sector.name_ar}</p>
              <p className="mt-2 min-h-12 text-sm leading-7 text-muted-foreground">{sector.description_ar}</p>
              <div className="mt-4 rounded-2xl bg-muted p-3">
                <p className="text-xs text-muted-foreground">{sector.metric_label_ar}</p>
                <p className="mt-1 text-2xl font-bold">{sector.metric_value}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section aria-labelledby="records-section" className="rounded-3xl border border-border bg-card p-4 shadow-sm">
        <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <h2 id="records-section" className="text-xl font-bold">السجلات المالية المحلية</h2>
            <p className="mt-1 text-sm text-muted-foreground">لا تظهر أي صفوف إلا بعد إدخالها يدويًا من الواجهة.</p>
          </div>
          {hasRecords && <Button type="button" onClick={openCreateDialog}>إضافة سجل جديد</Button>}
        </div>

        {hasRecords ? (
          <FinancialRecordsTable records={records} onEdit={handleEdit} onDelete={handleDelete} />
        ) : (
          <EmptyState title="لا توجد بيانات بعد" description="ابدأ بإضافة أول سجل مالي لتظهر الأرقام هنا" />
        )}
      </section>

      <FinancialRecordDialog
        open={isDialogOpen}
        record={editingRecord}
        onSubmit={handleSubmit}
        onClose={() => {
          setIsDialogOpen(false);
          setEditingRecord(null);
        }}
      />
    </>
  );
}
