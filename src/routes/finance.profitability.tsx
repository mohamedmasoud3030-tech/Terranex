import { createRoute } from '@tanstack/react-router';
import { financeRoute } from './finance';
import { KpiCard } from '../components/domain/KpiCard';
import { EmptyState } from '../components/ui/States';
import { calculateFinancialSummary } from '../features/finance/calculations';
import { useFinancialRecords } from '../features/finance/hooks';
import type { KpiCardVM } from '../core/types/ui';

export const financeProfitabilityRoute = createRoute({
  getParentRoute: () => financeRoute,
  path: '/profitability',
  component: ProfitabilityPage,
});

function ProfitabilityPage() {
  const { records } = useFinancialRecords();
  const summary = calculateFinancialSummary(records);

  const kpis: KpiCardVM[] = [
    {
      id: 'income',
      title_ar: 'إجمالي الإيرادات',
      title_en: 'Total income',
      value: summary.totalIncome,
      currency: 'EGP',
      period_ar: 'كل السجلات المحلية',
      period_en: 'All local records',
      trend_ar: 'سجلات النوع: إيراد',
      trend_en: 'Income records',
      status: 'positive',
      source_ar: 'السجلات المالية المحلية',
      source_en: 'Local financial records',
    },
    {
      id: 'expenses',
      title_ar: 'إجمالي المصروفات',
      title_en: 'Total expenses',
      value: summary.totalExpenses,
      currency: 'EGP',
      period_ar: 'كل السجلات المحلية',
      period_en: 'All local records',
      trend_ar: 'سجلات النوع: مصروف',
      trend_en: 'Expense records',
      status: 'warning',
      source_ar: 'السجلات المالية المحلية',
      source_en: 'Local financial records',
    },
    {
      id: 'net',
      title_ar: 'صافي الربح / الخسارة',
      title_en: 'Net profit / loss',
      value: summary.netProfit,
      currency: 'EGP',
      period_ar: 'إيرادات ناقص مصروفات',
      period_en: 'Income minus expenses',
      trend_ar: 'حساب محلي أولي لا يستبدل الإقفال المحاسبي',
      trend_en: 'Preliminary local calculation',
      status: summary.netProfit < 0 ? 'negative' : 'neutral',
      source_ar: 'السجلات المالية المحلية',
      source_en: 'Local financial records',
    },
  ];

  if (records.length === 0) {
    return <EmptyState title="لا توجد بيانات بعد" description="ابدأ بإضافة أول سجل مالي لتظهر الأرقام هنا" />;
  }

  return (
    <div className="grid gap-4 md:grid-cols-3">
      {kpis.map((kpi) => <KpiCard key={kpi.id} kpi={kpi} />)}
    </div>
  );
}
