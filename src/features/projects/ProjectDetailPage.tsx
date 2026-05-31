import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import {
  ArrowRight,
  BarChart3,
  CalendarDays,
  Edit3,
  FileText,
  Layers,
  PackageOpen,
  Plus,
  Trash2,
  TrendingDown,
  TrendingUp,
  Users,
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { guardProjectDeletion } from '../../core/domain/deletionGuards';
import { computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { operationalEventsStore, stockAdjustmentsStore } from '../events/storage';
import { projectPartnersStore } from '../partners/storage';
import { TransactionForm } from '../transactions/TransactionForm';
import { ProjectForm } from './ProjectForm';
import { projectsStore, type ProjectInput } from './storage';
import { transactionsStore, type TransactionInput } from '../transactions/storage';
import { useAssets } from '../assets/hooks';
import { useDocuments } from '../documents/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from '../partners/hooks';
import { useProject } from './hooks';
import { useTransactions } from '../transactions/hooks';

const CATEGORY_LABELS: Record<string, string> = {
  acquisition: 'اقتناء', sale: 'بيع', development_cost: 'تطوير', maintenance: 'صيانة',
  salary: 'رواتب', tax: 'ضرائب', legal_fee: 'رسوم قانونية', transport: 'نقل', utility: 'مرافق',
  seed_input: 'بذور', fertilizer: 'أسمدة', harvest_revenue: 'حصاد', irrigation: 'ري', feed: 'أعلاف',
  veterinary: 'بيطرة', vaccination: 'تحصينات', livestock_purchase: 'شراء مواشٍ', livestock_sale: 'بيع مواشٍ',
  loan_disbursement: 'قرض', loan_repayment: 'سداد قرض', interest: 'فوائد', dividend: 'أرباح موزعة', other: 'أخرى',
};

const SECTOR_LABELS = { 'real-estate': 'العقاري', agriculture: 'الزراعي', livestock: 'الحيواني' } as const;
type Tab = 'overview' | 'transactions' | 'assets' | 'obligations' | 'documents' | 'partners' | 'timeline';

export function ProjectDetailPage({ projectId }: { projectId: string }) {
  const router = useRouter();
  const project = useProject(projectId);
  const { transactions } = useTransactions(projectId);
  const { obligations } = useObligations(projectId);
  const { assets } = useAssets(projectId);
  const { documents } = useDocuments(projectId);
  const { partners } = usePartners();
  const allEvents = operationalEventsStore.getAll();
  const allAdjustments = stockAdjustmentsStore.getAll();
  const projectPartners = projectPartnersStore.getByProject(projectId);
  const projectEvents = allEvents.filter((item) => item.project_id === projectId);
  const projectAdjustments = allAdjustments.filter((item) => item.project_id === projectId);
  const [tab, setTab] = useState<Tab>('overview');
  const [showTxForm, setShowTxForm] = useState(false);
  const [showEditForm, setShowEditForm] = useState(false);
  const [deleteMessage, setDeleteMessage] = useState('');

  if (!project) {
    return (
      <div className="flex flex-col items-center justify-center gap-4 py-24 text-center">
        <EmptyState title="المشروع غير موجود" description="لم يتم العثور على مشروع بهذا المعرف، أو ربما تم حذفه من التخزين المحلي." />
        <Button onClick={() => router.navigate({ to: '/projects' } as any)} variant="secondary">
          <ArrowRight className="h-4 w-4" /> العودة للمشاريع
        </Button>
      </div>
    );
  }

  const currentProject = project;

  const profitability = computeProjectProfitability(currentProject, transactions, obligations, projectPartners, partners);
  const isProfit = profitability.gross_profit_egp >= 0;
  const linkedPartners = projectPartners.map((item) => partners.find((partner) => partner.id === item.partner_id)).filter(Boolean);
  const relationSnapshot = {
    transactions,
    assets,
    obligations,
    documents,
    projectPartners,
    operationalEvents: projectEvents,
    stockAdjustments: projectAdjustments,
  };

  const timeline = [
    ...transactions.map((item) => ({ id: item.id, date: item.transaction_date, title: item.description || CATEGORY_LABELS[item.category] || 'معاملة', type: 'معاملة', amount: item.amount_egp, tone: item.direction === 'income' ? 'text-success' : 'text-danger' })),
    ...obligations.map((item) => ({ id: item.id, date: item.due_date ?? item.created_at, title: item.notes || (item.direction === 'receivable' ? 'ذمة مدينة' : 'ذمة دائنة'), type: 'التزام', amount: item.amount_egp - item.amount_settled_egp, tone: item.direction === 'receivable' ? 'text-success' : 'text-danger' })),
    ...documents.map((item) => ({ id: item.id, date: item.issue_date ?? item.created_at, title: item.title_ar, type: 'مستند', amount: undefined, tone: 'text-muted-foreground' })),
    ...projectEvents.map((item) => ({ id: item.id, date: item.event_date, title: item.description || item.type, type: 'حدث تشغيلي', amount: item.total_cost_egp, tone: 'text-warning' })),
    ...projectAdjustments.map((item) => ({ id: item.id, date: item.adjustment_date, title: item.reason, type: 'تسوية مخزون', amount: item.value_egp_after - item.value_egp_before, tone: 'text-info' })),
  ].sort((a, b) => b.date.localeCompare(a.date));

  function handleAddTransaction(input: TransactionInput) {
    transactionsStore.create(input);
    setShowTxForm(false);
  }

  function handleUpdateProject(input: ProjectInput) {
    projectsStore.update(currentProject.id, input);
    setShowEditForm(false);
  }

  function handleDeleteProject() {
    const guard = guardProjectDeletion(currentProject.id, relationSnapshot);
    if (!guard.allowed) {
      setDeleteMessage(guard.message);
      return;
    }
    if (!window.confirm('هل أنت متأكد من حذف هذا المشروع؟ لا يمكن التراجع عن هذا الإجراء.')) return;
    projectsStore.remove(currentProject.id);
    router.navigate({ to: '/projects' } as any);
  }

  const kpis = [
    { label: 'إجمالي الإيرادات', value: profitability.total_income_egp, color: 'text-success', icon: TrendingUp },
    { label: 'إجمالي المصروفات', value: profitability.total_expense_egp, color: 'text-danger', icon: TrendingDown },
    { label: 'إجمالي الربح', value: profitability.gross_profit_egp, color: isProfit ? 'text-success' : 'text-danger', icon: BarChart3 },
    { label: 'ذمم مدينة مفتوحة', value: profitability.open_receivables_egp, color: 'text-success', icon: FileText },
    { label: 'ذمم دائنة مفتوحة', value: profitability.open_payables_egp, color: 'text-danger', icon: FileText },
    { label: 'عدد الأصول', value: assets.length, color: 'text-primary', icon: PackageOpen, isCount: true },
    { label: 'عدد المستندات', value: documents.length, color: 'text-info', icon: Layers, isCount: true },
    { label: 'عدد الشركاء', value: linkedPartners.length, color: 'text-warning', icon: Users, isCount: true },
  ];

  const tabs: { id: Tab; label: string; count?: number }[] = [
    { id: 'overview', label: 'نظرة عامة' },
    { id: 'transactions', label: 'المعاملات', count: transactions.length },
    { id: 'assets', label: 'الأصول', count: assets.length },
    { id: 'obligations', label: 'الذمم', count: obligations.length },
    { id: 'documents', label: 'المستندات', count: documents.length },
    { id: 'partners', label: 'الشركاء', count: linkedPartners.length },
    { id: 'timeline', label: 'النشاط', count: timeline.length },
  ];

  return (
    <div className="space-y-6">
      <div>
        <button onClick={() => router.navigate({ to: '/projects' } as any)} className="mb-3 flex items-center gap-1 text-sm text-muted-foreground transition hover:text-foreground">
          <ArrowRight className="h-4 w-4" /> المشاريع
        </button>
        <Card>
          <CardContent className="p-5">
            <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div className="min-w-0">
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  <Badge tone="info">{SECTOR_LABELS[currentProject.sector_id]}</Badge>
                  <Badge tone={currentProject.status === 'active' ? 'positive' : 'neutral'}>{currentProject.status}</Badge>
                  <Badge>{currentProject.base_currency}</Badge>
                </div>
                <h1 className="text-2xl font-bold text-foreground md:text-3xl">{currentProject.name_ar}</h1>
                {currentProject.name_en && <p className="mt-1 text-sm text-muted-foreground" dir="ltr">{currentProject.name_en}</p>}
                <div className="mt-3 flex flex-wrap gap-3 text-sm text-muted-foreground">
                  <span className="inline-flex items-center gap-1"><CalendarDays className="h-4 w-4" /> يبدأ: {currentProject.start_date}</span>
                  {currentProject.end_date && <span>ينتهي: {currentProject.end_date}</span>}
                </div>
                {currentProject.description_ar && <p className="mt-3 max-w-3xl text-sm leading-7 text-muted-foreground">{currentProject.description_ar}</p>}
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary" onClick={() => setShowEditForm((value) => !value)}><Edit3 className="h-4 w-4" /> تعديل</Button>
                <Button variant="danger" onClick={handleDeleteProject}><Trash2 className="h-4 w-4" /> حذف آمن</Button>
              </div>
            </div>
            {deleteMessage && <p className="mt-4 rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{deleteMessage}</p>}
          </CardContent>
        </Card>
      </div>

      {showEditForm && (
        <Card>
          <CardContent>
            <h2 className="mb-4 font-semibold">تعديل المشروع</h2>
            <ProjectForm initial={currentProject} onSubmit={handleUpdateProject} onCancel={() => setShowEditForm(false)} />
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 xl:grid-cols-8">
        {kpis.map((kpi) => {
          const Icon = kpi.icon;
          return (
            <Card key={kpi.label}>
              <CardContent className="p-3 sm:p-4">
                <div className="mb-2 flex items-center justify-between gap-2">
                  <span className="text-xs text-muted-foreground">{kpi.label}</span>
                  <Icon className={`h-4 w-4 ${kpi.color}`} />
                </div>
                <p className={`text-lg font-bold sm:text-xl ${kpi.color}`}>
                  {kpi.isCount ? kpi.value : formatEgp(kpi.value, true)}
                  {!kpi.isCount && <span className="ms-1 text-xs font-normal text-muted-foreground">EGP</span>}
                </p>
              </CardContent>
            </Card>
          );
        })}
      </div>

      <div className="overflow-x-auto border-b border-border pb-px">
        <div className="flex min-w-max gap-1">
          {tabs.map((item) => (
            <button key={item.id} onClick={() => setTab(item.id)} className={`flex items-center gap-1.5 border-b-2 px-4 py-3 text-sm font-medium transition ${tab === item.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
              {item.label}
              {item.count !== undefined && <span className={`rounded-full px-1.5 py-0.5 text-xs ${tab === item.id ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}`}>{item.count}</span>}
            </button>
          ))}
        </div>
      </div>

      {tab === 'overview' && (
        <Card>
          <CardHeader><h2 className="font-semibold">تعريف الربحية</h2></CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm leading-7 text-muted-foreground">إجمالي الربح = إجمالي الإيرادات ناقص إجمالي المصروفات. الذمم المفتوحة تعرض التعرض النقدي ولا تخصم من الربح المحاسبي.</p>
            <p className="text-sm font-semibold">هامش الربح: {profitability.margin_pct.toFixed(1)}%</p>
          </CardContent>
        </Card>
      )}

      {tab === 'transactions' && (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="font-semibold">سجل المعاملات</h2>
            <Button size="sm" onClick={() => setShowTxForm(true)}><Plus className="h-4 w-4" /> معاملة جديدة</Button>
          </div>
          {showTxForm && <Card><CardContent><TransactionForm projectId={projectId} onSubmit={handleAddTransaction} onCancel={() => setShowTxForm(false)} /></CardContent></Card>}
          {transactions.length === 0 ? <EmptyState title="لا توجد معاملات بعد" description="أضف إيراداً أو مصروفاً لبدء حساب الربحية." /> : <Card><div className="divide-y divide-border">{transactions.map((tx) => <div key={tx.id} className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm font-medium">{tx.description || CATEGORY_LABELS[tx.category] || tx.category}</p><p className="text-xs text-muted-foreground">{tx.transaction_date}</p></div><p className={`text-sm font-bold ${tx.direction === 'income' ? 'text-success' : 'text-danger'}`}>{tx.direction === 'income' ? '+' : '-'}{formatEgp(tx.amount_egp)} EGP</p></div>)}</div></Card>}
        </div>
      )}

      {tab === 'assets' && (assets.length === 0 ? <EmptyState title="لا توجد أصول" description="لم يتم ربط أصول بهذا المشروع بعد." /> : <div className="grid gap-3 sm:grid-cols-2">{assets.map((asset) => <Card key={asset.id}><CardContent><p className="font-semibold">{asset.name_ar}</p><p className="mt-1 text-xs text-muted-foreground">{asset.type} · {asset.status}</p><p className="mt-3 text-sm font-bold text-primary">{formatEgp(asset.acquisition_cost_egp)} EGP</p></CardContent></Card>)}</div>)}

      {tab === 'obligations' && (obligations.length === 0 ? <EmptyState title="لا توجد ذمم" description="لا توجد التزامات أو ذمم مرتبطة بهذا المشروع." /> : <Card><div className="divide-y divide-border">{obligations.map((item) => <div key={item.id} className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{item.direction === 'receivable' ? 'ذمة مدينة' : 'ذمة دائنة'}</p><p className="text-xs text-muted-foreground">{item.status} · {item.due_date ?? 'بدون تاريخ'}</p></div><p className={item.direction === 'receivable' ? 'text-success font-bold' : 'text-danger font-bold'}>{formatEgp(item.amount_egp - item.amount_settled_egp)} EGP</p></div>)}</div></Card>)}

      {tab === 'documents' && (documents.length === 0 ? <EmptyState title="لا توجد مستندات" description="لم يتم ربط مستندات بهذا المشروع بعد." /> : <Card><div className="divide-y divide-border">{documents.map((doc) => <div key={doc.id} className="flex items-center gap-3 px-4 py-3"><FileText className="h-5 w-5 flex-shrink-0 text-muted-foreground" /><div className="min-w-0"><p className="truncate text-sm font-medium">{doc.title_ar}</p><p className="text-xs text-muted-foreground">{doc.type} · {doc.issue_date ?? 'بدون تاريخ'}</p></div></div>)}</div></Card>)}

      {tab === 'partners' && (linkedPartners.length === 0 ? <EmptyState title="لا يوجد شركاء" description="لم يتم ربط شركاء ملكية بهذا المشروع بعد." /> : <div className="grid gap-3 sm:grid-cols-2">{projectPartners.map((item) => { const partner = partners.find((entry) => entry.id === item.partner_id); return <Card key={item.id}><CardContent><p className="font-semibold">{partner?.name_ar ?? 'شريك غير معروف'}</p><p className="mt-1 text-sm text-muted-foreground">نسبة الملكية: {item.equity_pct}%</p><p className="mt-2 text-sm font-bold text-primary">حصة الربح: {formatEgp((profitability.gross_profit_egp * item.equity_pct) / 100)} EGP</p></CardContent></Card>; })}</div>)}

      {tab === 'timeline' && (timeline.length === 0 ? <EmptyState title="لا يوجد نشاط" description="سيظهر هنا تسلسل زمني موحد للمعاملات والذمم والمستندات والأحداث." /> : <Card><div className="divide-y divide-border">{timeline.map((item) => <div key={`${item.type}-${item.id}`} className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{item.title}</p><p className="text-xs text-muted-foreground">{item.type} · {item.date}</p></div>{typeof item.amount === 'number' && <p className={`font-bold ${item.tone}`}>{formatEgp(item.amount)} EGP</p>}</div>)}</div></Card>)}
    </div>
  );
}
