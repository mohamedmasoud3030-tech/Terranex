import { useEffect, useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { ArrowRight, BarChart3, CalendarDays, Edit3, FileText, Layers, Plus, ShieldAlert, Trash2, TrendingDown, TrendingUp, Users } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { EmptyState } from '../../components/ui/States';
import { confirmSafeDeletion, guardProjectDeletion } from '../../core/lib/deletionGuards';
import { computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { useAssets } from '../assets/hooks';
import { useDocuments } from '../documents/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from '../partners/hooks';
import { projectPartnersStore } from '../partners/storage';
import { useTransactions } from '../transactions/hooks';
import { TransactionForm } from '../transactions/TransactionForm';
import type { TransactionInput } from '../transactions/storage';
import { transactionsStore } from '../transactions/storage';
import { useProject, useProjects } from './hooks';
import { ProjectForm } from './ProjectForm';
import type { ProjectInput } from './storage';

const CATEGORY_LABELS: Record<string, string> = {
  acquisition: 'اقتناء', sale: 'بيع', development_cost: 'تطوير', maintenance: 'صيانة', salary: 'رواتب', tax: 'ضرائب', legal_fee: 'رسوم قانونية', transport: 'نقل', utility: 'مرافق', seed_input: 'بذور', fertilizer: 'أسمدة', harvest_revenue: 'حصاد', irrigation: 'ري', feed: 'أعلاف', veterinary: 'بيطرة', vaccination: 'تحصينات', livestock_purchase: 'شراء مواشٍ', livestock_sale: 'بيع مواشٍ', loan_disbursement: 'قرض', loan_repayment: 'سداد قرض', interest: 'فوائد', dividend: 'أرباح موزعة', other: 'أخرى',
};

const SECTOR_LABELS = { 'real-estate': 'العقاري', agriculture: 'الزراعي', livestock: 'الحيواني' } as const;
type Tab = 'overview' | 'transactions' | 'obligations' | 'partners' | 'assets' | 'documents' | 'activity';

export function ProjectDetailPage({ projectId }: { projectId: string }) {
  const router = useRouter();
  const project = useProject(projectId);
  const { updateProject, deleteProject } = useProjects();
  const { transactions } = useTransactions(projectId);
  const { obligations } = useObligations(projectId);
  const { assets } = useAssets(projectId);
  const { documents } = useDocuments(projectId);
  const { partners } = usePartners();
  const [projectPartners, setProjectPartners] = useState(() => projectPartnersStore.getByProject(projectId));
  const [tab, setTab] = useState<Tab>('overview');
  const [showTxForm, setShowTxForm] = useState(false);
  const [editing, setEditing] = useState(false);
  const [deleteMessage, setDeleteMessage] = useState<string | null>(null);

  useEffect(() => projectPartnersStore.subscribe((all) => setProjectPartners(all.filter((pp) => pp.project_id === projectId))), [projectId]);

  if (!project) {
    return (
      <div className="mx-auto flex max-w-md flex-col items-center justify-center gap-4 py-24 text-center">
        <ShieldAlert className="h-10 w-10 text-muted-foreground" />
        <div>
          <h1 className="text-lg font-bold">المشروع غير موجود</h1>
          <p className="mt-1 text-sm text-muted-foreground">قد يكون المشروع حُذف أو أن الرابط غير صالح.</p>
        </div>
        <Button onClick={() => router.navigate({ to: '/projects' } as any)} variant="secondary">
          <ArrowRight className="h-4 w-4" /> العودة للمشاريع
        </Button>
      </div>
    );
  }

  const profitability = computeProjectProfitability(project, transactions, obligations, projectPartners, partners);
  const isProfit = profitability.gross_profit_egp >= 0;
  const partnerName = new Map(partners.map((partner) => [partner.id, partner.name_ar]));

  function handleAddTransaction(input: TransactionInput) {
    transactionsStore.create(input);
    setShowTxForm(false);
  }

  function handleUpdateProject(input: ProjectInput) {
    updateProject(projectId, input);
    setEditing(false);
  }

  function handleDeleteProject() {
    const guard = guardProjectDeletion(projectId);
    if (!guard.canDelete) {
      setDeleteMessage(guard.message_ar);
      return;
    }
    if (!confirmSafeDeletion(guard.message_ar)) return;
    deleteProject(projectId);
    router.navigate({ to: '/projects' } as any);
  }

  const kpis = [
    { label: 'إجمالي الإيرادات', value: profitability.total_income_egp, color: 'text-success', icon: TrendingUp },
    { label: 'إجمالي المصروفات', value: profitability.total_expense_egp, color: 'text-danger', icon: TrendingDown },
    { label: 'إجمالي الربح', value: profitability.gross_profit_egp, color: isProfit ? 'text-success' : 'text-danger', icon: BarChart3 },
    { label: 'التعرض النقدي', value: profitability.cash_exposure_egp, color: profitability.cash_exposure_egp >= 0 ? 'text-success' : 'text-danger', icon: FileText },
  ];

  const tabs: { id: Tab; label: string; count?: number }[] = [
    { id: 'overview', label: 'نظرة عامة' },
    { id: 'transactions', label: 'المعاملات', count: transactions.length },
    { id: 'obligations', label: 'الالتزامات', count: obligations.length },
    { id: 'partners', label: 'الشركاء', count: projectPartners.length },
    { id: 'assets', label: 'الأصول', count: assets.length },
    { id: 'documents', label: 'المستندات', count: documents.length },
    { id: 'activity', label: 'النشاط' },
  ];

  const activity = [
    ...transactions.map((item) => ({ id: item.id, date: item.transaction_date, label: item.description || CATEGORY_LABELS[item.category] || item.category, meta: item.direction === 'income' ? 'إيراد' : 'مصروف' })),
    ...obligations.map((item) => ({ id: item.id, date: item.due_date ?? item.created_at.slice(0, 10), label: partnerName.get(item.partner_id) ?? 'طرف غير معروف', meta: item.direction === 'receivable' ? 'ذمة مدينة' : 'ذمة دائنة' })),
    ...documents.map((item) => ({ id: item.id, date: item.issue_date ?? item.created_at.slice(0, 10), label: item.title_ar, meta: 'مستند' })),
    ...assets.map((item) => ({ id: item.id, date: item.acquisition_date, label: item.name_ar, meta: 'أصل' })),
  ].sort((a, b) => b.date.localeCompare(a.date));

  return (
    <div className="space-y-6 overflow-hidden">
      <div>
        <button onClick={() => router.navigate({ to: '/projects' } as any)} className="mb-3 flex items-center gap-1 text-sm text-muted-foreground transition hover:text-foreground">
          <ArrowRight className="h-4 w-4" /> المشاريع
        </button>
        <Card>
          <CardContent className="p-4 sm:p-5">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0">
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  <Badge tone={project.status === 'active' ? 'positive' : 'neutral'}>{project.status}</Badge>
                  <Badge tone="info">{SECTOR_LABELS[project.sector_id]}</Badge>
                  <Badge>{project.base_currency} — ج.م للتقارير</Badge>
                </div>
                <h1 className="break-words text-2xl font-bold text-foreground">{project.name_ar}</h1>
                {project.name_en && <p className="mt-1 text-sm text-muted-foreground" dir="ltr">{project.name_en}</p>}
                <div className="mt-3 flex flex-wrap gap-3 text-xs text-muted-foreground">
                  <span className="inline-flex items-center gap-1"><CalendarDays className="h-3.5 w-3.5" /> بدأ: {project.start_date}</span>
                  {project.end_date && <span>ينتهي: {project.end_date}</span>}
                  <span>آخر تحديث: {project.updated_at.slice(0, 10)}</span>
                </div>
              </div>
              <div className="flex shrink-0 flex-wrap gap-2">
                <Button variant="secondary" size="sm" onClick={() => setEditing(true)}><Edit3 className="h-4 w-4" /> تعديل</Button>
                <Button variant="danger" size="sm" onClick={handleDeleteProject}><Trash2 className="h-4 w-4" /> حذف</Button>
              </div>
            </div>
            {deleteMessage && <p className="mt-4 rounded-xl border border-danger/30 bg-danger/10 px-3 py-2 text-sm text-danger">{deleteMessage}</p>}
          </CardContent>
        </Card>
      </div>

      {editing && (
        <Card>
          <CardContent>
            <h2 className="mb-4 font-semibold">تعديل بيانات المشروع</h2>
            <ProjectForm initial={project} onSubmit={handleUpdateProject} onCancel={() => setEditing(false)} />
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-3 min-[320px]:grid-cols-2 lg:grid-cols-4">
        {kpis.map((kpi) => {
          const Icon = kpi.icon;
          return (
            <Card key={kpi.label}>
              <CardContent className="p-3 sm:p-4">
                <div className="mb-2 flex items-center justify-between gap-2">
                  <span className="text-xs text-muted-foreground">{kpi.label}</span>
                  <Icon className={`h-4 w-4 ${kpi.color}`} />
                </div>
                <p className={`break-words text-lg font-bold sm:text-xl ${kpi.color}`}>{formatEgp(kpi.value, true)} <span className="text-xs font-normal text-muted-foreground">EGP</span></p>
              </CardContent>
            </Card>
          );
        })}
      </div>

      <div className="overflow-x-auto border-b border-border pb-px">
        <div className="flex min-w-max gap-1">
          {tabs.map((item) => (
            <button key={item.id} onClick={() => setTab(item.id)} className={`flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-3 text-sm font-medium transition sm:px-4 ${tab === item.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
              {item.label}
              {item.count !== undefined && <span className={`rounded-full px-1.5 py-0.5 text-xs ${tab === item.id ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}`}>{item.count}</span>}
            </button>
          ))}
        </div>
      </div>

      {tab === 'overview' && (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader><h3 className="font-semibold">تعريفات الربحية</h3></CardHeader>
            <CardContent className="space-y-3">
              <FormulaRow label="إجمالي الإيرادات" value={profitability.total_income_egp} tone="text-success" />
              <FormulaRow label="إجمالي المصروفات" value={profitability.total_expense_egp} tone="text-danger" negative />
              <FormulaRow label="إجمالي الربح" value={profitability.gross_profit_egp} tone={isProfit ? 'text-success' : 'text-danger'} strong />
              <FormulaRow label="ذمم مدينة مفتوحة" value={profitability.open_receivables_egp} tone="text-success" />
              <FormulaRow label="ذمم دائنة مفتوحة" value={profitability.open_payables_egp} tone="text-danger" />
              <FormulaRow label="التعرض النقدي" value={profitability.cash_exposure_egp} tone={profitability.cash_exposure_egp >= 0 ? 'text-success' : 'text-danger'} strong />
              <p className="text-xs leading-6 text-muted-foreground">إجمالي الربح المحاسبي لا يطرح الذمم المدينة. التعرض النقدي = الذمم المدينة المفتوحة − الذمم الدائنة المفتوحة.</p>
            </CardContent>
          </Card>
          <Card>
            <CardHeader><h3 className="font-semibold">عن المشروع</h3></CardHeader>
            <CardContent>
              <p className="text-sm leading-7 text-muted-foreground">{project.description_ar || 'لا يوجد وصف عربي مسجل لهذا المشروع بعد.'}</p>
            </CardContent>
          </Card>
        </div>
      )}

      {tab === 'transactions' && <TransactionsTab projectId={projectId} transactions={transactions} showTxForm={showTxForm} setShowTxForm={setShowTxForm} onAdd={handleAddTransaction} />}
      {tab === 'obligations' && <ObligationsTab obligations={obligations} partnerName={partnerName} />}
      {tab === 'partners' && <PartnersTab projectPartners={projectPartners} partnerName={partnerName} profitability={profitability.gross_profit_egp} />}
      {tab === 'assets' && <AssetsTab assets={assets} />}
      {tab === 'documents' && <DocumentsTab documents={documents} />}
      {tab === 'activity' && <ActivityTab activity={activity} />}
    </div>
  );
}

function FormulaRow({ label, value, tone, negative, strong }: { label: string; value: number; tone: string; negative?: boolean; strong?: boolean }) {
  return <div className={`flex flex-col gap-1 rounded-xl border border-border px-3 py-2.5 min-[360px]:flex-row min-[360px]:items-center min-[360px]:justify-between ${strong ? 'bg-muted/40' : ''}`}><span className="text-sm text-muted-foreground">{label}</span><span className={`text-sm font-bold ${tone}`}>{negative ? '− ' : ''}{formatEgp(Math.abs(value))} EGP</span></div>;
}

function TransactionsTab({ projectId, transactions, showTxForm, setShowTxForm, onAdd }: { projectId: string; transactions: ReturnType<typeof useTransactions>['transactions']; showTxForm: boolean; setShowTxForm: (show: boolean) => void; onAdd: (input: TransactionInput) => void }) {
  return <div className="space-y-4"><div className="flex flex-col gap-2 min-[360px]:flex-row min-[360px]:items-center min-[360px]:justify-between"><h3 className="font-semibold">سجل المعاملات</h3><Button size="sm" onClick={() => setShowTxForm(true)}><Plus className="h-4 w-4" /> معاملة جديدة</Button></div>{showTxForm && <Card><CardContent><TransactionForm projectId={projectId} onSubmit={onAdd} onCancel={() => setShowTxForm(false)} /></CardContent></Card>}{transactions.length === 0 ? <EmptyState title="لا توجد معاملات بعد" description="كل مؤشرات الربحية ستظل صفراً حتى تُسجل معاملات فعلية." /> : <Card><div className="divide-y divide-border">{transactions.map((tx) => <div key={tx.id} className="flex flex-col gap-2 px-4 py-3 min-[360px]:flex-row min-[360px]:items-center min-[360px]:justify-between"><div className="min-w-0"><p className="truncate text-sm font-medium">{tx.description || CATEGORY_LABELS[tx.category] || tx.category}</p><p className="text-xs text-muted-foreground">{tx.transaction_date}</p></div><p className={`text-sm font-bold ${tx.direction === 'income' ? 'text-success' : 'text-danger'}`}>{tx.direction === 'income' ? '+' : '−'}{formatEgp(tx.amount_egp)} EGP</p></div>)}</div></Card>}</div>;
}

function ObligationsTab({ obligations, partnerName }: { obligations: ReturnType<typeof useObligations>['obligations']; partnerName: Map<string, string> }) {
  if (obligations.length === 0) return <EmptyState title="لا توجد التزامات" description="لا توجد ذمم مدينة أو دائنة مرتبطة بهذا المشروع." />;
  return <Card><div className="divide-y divide-border">{obligations.map((obligation) => { const remaining = Math.max(0, obligation.amount_egp - obligation.amount_settled_egp); return <div key={obligation.id} className="flex flex-col gap-2 px-4 py-3 min-[360px]:flex-row min-[360px]:items-center min-[360px]:justify-between"><div><p className="text-sm font-medium">{partnerName.get(obligation.partner_id) ?? 'طرف غير معروف'}</p><p className="text-xs text-muted-foreground">{obligation.due_date ?? 'بدون تاريخ استحقاق'} · {obligation.status}</p></div><div className="text-start min-[360px]:text-end"><Badge tone={obligation.direction === 'receivable' ? 'positive' : 'negative'}>{obligation.direction === 'receivable' ? 'مدينة لنا' : 'دائنة علينا'}</Badge><p className="mt-1 text-sm font-bold">{formatEgp(remaining)} EGP</p></div></div>; })}</div></Card>;
}

function PartnersTab({ projectPartners, partnerName, profitability }: { projectPartners: ReturnType<typeof projectPartnersStore.getByProject>; partnerName: Map<string, string>; profitability: number }) {
  if (projectPartners.length === 0) return <EmptyState title="لا يوجد شركاء" description="لم يتم ربط شركاء ملكية بهذا المشروع بعد." icon={Users} />;
  return <div className="grid gap-3 sm:grid-cols-2">{projectPartners.map((pp) => <Card key={pp.id}><CardContent><p className="font-semibold">{partnerName.get(pp.partner_id) ?? 'شريك غير معروف'}</p><p className="mt-1 text-sm text-muted-foreground">نسبة الملكية: {pp.equity_pct}%</p><p className="mt-3 text-sm font-bold text-primary">حصة الربح: {formatEgp((profitability * pp.equity_pct) / 100)} EGP</p></CardContent></Card>)}</div>;
}

function AssetsTab({ assets }: { assets: ReturnType<typeof useAssets>['assets'] }) {
  if (assets.length === 0) return <EmptyState title="لا توجد أصول" description="لا توجد أصول مسجلة على هذا المشروع." icon={Layers} />;
  return <div className="grid gap-3 sm:grid-cols-2">{assets.map((asset) => <Card key={asset.id}><CardContent><p className="font-medium">{asset.name_ar}</p><p className="mt-1 text-xs text-muted-foreground">{asset.type} · {asset.status}</p><p className="mt-2 text-sm font-bold text-primary">{formatEgp(asset.acquisition_cost_egp)} EGP</p></CardContent></Card>)}</div>;
}

function DocumentsTab({ documents }: { documents: ReturnType<typeof useDocuments>['documents'] }) {
  if (documents.length === 0) return <EmptyState title="لا توجد مستندات" description="لا توجد مستندات مرتبطة بهذا المشروع." icon={FileText} />;
  return <Card><div className="divide-y divide-border">{documents.map((doc) => <div key={doc.id} className="flex items-center gap-3 px-4 py-3"><FileText className="h-5 w-5 shrink-0 text-muted-foreground" /><div className="min-w-0"><p className="truncate text-sm font-medium">{doc.title_ar}</p><p className="text-xs text-muted-foreground">{doc.type} · {doc.issue_date ?? 'بدون تاريخ'}</p></div></div>)}</div></Card>;
}

function ActivityTab({ activity }: { activity: { id: string; date: string; label: string; meta: string }[] }) {
  if (activity.length === 0) return <EmptyState title="لا يوجد نشاط" description="سيظهر هنا تسلسل زمني من المعاملات والالتزامات والأصول والمستندات." />;
  return <Card><div className="divide-y divide-border">{activity.map((item) => <div key={`${item.meta}-${item.id}`} className="flex items-start gap-3 px-4 py-3"><div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" /><div className="min-w-0"><p className="truncate text-sm font-medium">{item.label}</p><p className="text-xs text-muted-foreground">{item.date} · {item.meta}</p></div></div>)}</div></Card>;
}
