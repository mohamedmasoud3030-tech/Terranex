import { ArrowDownLeft, ArrowUpRight, FileText } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { useDocuments } from '../documents/hooks';
import { useProjects } from '../projects/hooks';
import { usePartners } from '../partners/hooks';
import { useTransactions } from './hooks';
import { formatEgp } from '../../core/lib/profitability';

const CATEGORY_LABELS: Record<string, string> = {
  acquisition: 'اقتناء',
  sale: 'بيع',
  development_cost: 'تطوير',
  maintenance: 'صيانة',
  salary: 'رواتب',
  tax: 'ضرائب',
  legal_fee: 'رسوم قانونية',
  transport: 'نقل',
  utility: 'مرافق',
  seed_input: 'بذور',
  fertilizer: 'أسمدة',
  harvest_revenue: 'حصاد',
  irrigation: 'ري',
  feed: 'أعلاف',
  veterinary: 'بيطرة',
  vaccination: 'تحصينات',
  livestock_purchase: 'شراء مواشٍ',
  livestock_sale: 'بيع مواشٍ',
  loan_disbursement: 'قرض',
  loan_repayment: 'سداد قرض',
  interest: 'فوائد',
  dividend: 'أرباح موزعة',
  other: 'أخرى',
};

export function TransactionsPage() {
  const { transactions, totalIncomeEgp, totalExpenseEgp, netProfitEgp } = useTransactions();
  const { documents } = useDocuments();
  const { projects } = useProjects();
  const { partners } = usePartners();

  const projectNames = new Map(projects.map((project) => [project.id, project.name_ar]));
  const partnerNames = new Map(partners.map((partner) => [partner.id, partner.name_ar]));
  const documentTitles = new Map(documents.map((document) => [document.id, document.title_ar]));

  return (
    <div className="space-y-6">
      <PageHeader
        title="المعاملات"
        description="سجل موحد لكل الإيرادات والمصروفات المرتبطة بالمشاريع والأصول والأطراف والمستندات الداعمة."
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">إجمالي الإيرادات</p>
            <p className="mt-2 text-2xl font-bold text-success">{formatEgp(totalIncomeEgp, true)} EGP</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">إجمالي المصروفات</p>
            <p className="mt-2 text-2xl font-bold text-danger">{formatEgp(totalExpenseEgp, true)} EGP</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent>
            <p className="text-sm text-muted-foreground">الصافي</p>
            <p className={`mt-2 text-2xl font-bold ${netProfitEgp >= 0 ? 'text-success' : 'text-danger'}`}>
              {formatEgp(netProfitEgp, true)} EGP
            </p>
          </CardContent>
        </Card>
      </div>

      {transactions.length === 0 ? (
        <EmptyState title="لا توجد معاملات بعد" description="ستظهر هنا المعاملات المسجلة من صفحات المشاريع والتشغيل." />
      ) : (
        <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
          <div className="divide-y divide-border">
            {transactions.map((transaction) => {
              const isIncome = transaction.direction === 'income';
              const Icon = isIncome ? ArrowUpRight : ArrowDownLeft;

              return (
                <div key={transaction.id} className="grid gap-3 p-4 md:grid-cols-[1fr_auto] md:items-center">
                  <div className="flex items-start gap-3">
                    <div className={`mt-1 flex h-9 w-9 items-center justify-center rounded-xl ${isIncome ? 'bg-success/10 text-success' : 'bg-danger/10 text-danger'}`}>
                      <Icon className="h-4 w-4" />
                    </div>
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-semibold">{transaction.description || CATEGORY_LABELS[transaction.category] || transaction.category}</p>
                        <Badge tone={isIncome ? 'positive' : 'negative'}>{isIncome ? 'إيراد' : 'مصروف'}</Badge>
                      </div>
                      <p className="mt-1 text-sm text-muted-foreground">
                        {projectNames.get(transaction.project_id) ?? 'مشروع غير معروف'}
                        {transaction.partner_id ? ` · ${partnerNames.get(transaction.partner_id) ?? 'طرف غير معروف'}` : ''}
                      </p>
                      {transaction.document_id && (
                        <p className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground">
                          <FileText className="h-3.5 w-3.5" />
                          {documentTitles.get(transaction.document_id) ?? 'مستند غير معروف'}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="text-start md:text-end">
                    <p className={`text-lg font-bold ${isIncome ? 'text-success' : 'text-danger'}`}>
                      {isIncome ? '+' : '−'}{formatEgp(transaction.amount_egp, true)} EGP
                    </p>
                    <p className="text-xs text-muted-foreground" dir="ltr">{transaction.transaction_date}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
