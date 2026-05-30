import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { ArrowRight, Plus, TrendingUp, TrendingDown, FileText, Users, BarChart3, Layers } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { useProject } from './hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { useAssets } from '../assets/hooks';
import { useDocuments } from '../documents/hooks';
import { computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { TransactionForm } from '../transactions/TransactionForm';
import type { TransactionInput } from '../transactions/storage';
import { transactionsStore } from '../transactions/storage';

const CATEGORY_LABELS: Record<string, string> = {
  acquisition: 'اقتناء', sale: 'بيع', development_cost: 'تطوير', maintenance: 'صيانة',
  salary: 'رواتب', tax: 'ضرائب', legal_fee: 'رسوم قانونية', transport: 'نقل',
  utility: 'مرافق', seed_input: 'بذور', fertilizer: 'أسمدة', harvest_revenue: 'حصاد',
  irrigation: 'ري', feed: 'أعلاف', veterinary: 'بيطرة', vaccination: 'تحصينات',
  livestock_purchase: 'شراء مواشٍ', livestock_sale: 'بيع مواشٍ',
  loan_disbursement: 'قرض', loan_repayment: 'سداد قرض', interest: 'فوائد',
  dividend: 'أرباح موزعة', other: 'أخرى',
};

type Tab = 'overview' | 'transactions' | 'assets' | 'documents';

export function ProjectDetailPage({ projectId }: { projectId: string }) {
  const router = useRouter();
  const project = useProject(projectId);
  const { transactions } = useTransactions(projectId);
  const { obligations } = useObligations(projectId);
  const { assets } = useAssets(projectId);
  const { documents } = useDocuments(projectId);
  const [tab, setTab] = useState<Tab>('overview');
  const [showTxForm, setShowTxForm] = useState(false);

  if (!project) {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4">
        <p className="text-muted-foreground">المشروع غير موجود</p>
        <Button onClick={() => router.navigate({ to: '/projects' } as any)} tone="secondary">
          <ArrowRight className="h-4 w-4" /> العودة للمشاريع
        </Button>
      </div>
    );
  }

  const profitability = computeProjectProfitability(project, transactions, obligations, [], []);
  const isProfit = profitability.gross_profit_egp >= 0;

  function handleAddTransaction(input: TransactionInput) {
    transactionsStore.create(input);
    setShowTxForm(false);
  }

  const kpis = [
    { label: 'إجمالي الإيرادات', value: profitability.total_income_egp, color: 'text-success', icon: TrendingUp },
    { label: 'إجمالي المصروفات', value: profitability.total_expense_egp, color: 'text-danger', icon: TrendingDown },
    { label: 'إجمالي الربح', value: profitability.gross_profit_egp, color: isProfit ? 'text-success' : 'text-danger', icon: BarChart3 },
    { label: 'الالتزامات المفتوحة', value: profitability.open_obligations_egp, color: 'text-warning', icon: FileText },
  ];

  const tabs: { id: Tab; label: string; count?: number }[] = [
    { id: 'overview', label: 'نظرة عامة' },
    { id: 'transactions', label: 'المعاملات', count: transactions.length },
    { id: 'assets', label: 'الأصول', count: assets.length },
    { id: 'documents', label: 'المستندات', count: documents.length },
  ];

  return (
    <div className="space-y-6">
      {/* Breadcrumb & header */}
      <div>
        <button
          onClick={() => router.navigate({ to: '/projects' } as any)}
          className="mb-3 flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition"
        >
          <ArrowRight className="h-4 w-4" /> المشاريع
        </button>
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-foreground">{project.name_ar}</h1>
            {project.name_en && <p className="mt-1 text-sm text-muted-foreground" dir="ltr">{project.name_en}</p>}
          </div>
          <Badge tone={project.status === 'active' ? 'positive' : 'neutral'}>
            {project.status}
          </Badge>
        </div>
      </div>

      {/* KPI strip */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {kpis.map((kpi) => {
          const Icon = kpi.icon;
          return (
            <Card key={kpi.label}>
              <CardContent className="p-4">
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">{kpi.label}</span>
                  <Icon className={`h-4 w-4 ${kpi.color}`} />
                </div>
                <p className={`text-xl font-bold ${kpi.color}`}>
                  {formatEgp(kpi.value, true)}
                  <span className="ms-1 text-xs font-normal text-muted-foreground">EGP</span>
                </p>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* Tabs */}
      <div className="border-b border-border">
        <div className="flex gap-1">
          {tabs.map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex items-center gap-1.5 border-b-2 px-4 py-3 text-sm font-medium transition ${
                tab === t.id
                  ? 'border-primary text-primary'
                  : 'border-transparent text-muted-foreground hover:text-foreground'
              }`}
            >
              {t.label}
              {t.count !== undefined && (
                <span className={`rounded-full px-1.5 py-0.5 text-xs ${tab === t.id ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}`}>
                  {t.count}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Tab: Overview */}
      {tab === 'overview' && (
        <div className="space-y-4">
          <Card>
            <CardHeader><h3 className="font-semibold">محرك الربحية</h3></CardHeader>
            <CardContent>
              <div className="space-y-3">
                {[
                  { label: 'إجمالي الإيرادات', value: profitability.total_income_egp, color: 'text-success bg-success/10', sign: '+' },
                  { label: 'إجمالي المصروفات', value: -profitability.total_expense_egp, color: 'text-danger bg-danger/10', sign: '−' },
                  { label: 'إجمالي الربح', value: profitability.gross_profit_egp, color: isProfit ? 'text-success bg-success/10' : 'text-danger bg-danger/10', sign: '=' },
                ].map((row) => (
                  <div key={row.label} className="flex items-center justify-between rounded-xl px-3 py-2.5 border border-border">
                    <span className="text-sm text-muted-foreground">{row.label}</span>
                    <span className={`rounded-lg px-2.5 py-1 text-sm font-bold ${row.color}`}>
                      {row.sign} {formatEgp(Math.abs(row.value))} EGP
                    </span>
                  </div>
                ))}
              </div>
              <p className="mt-3 text-xs text-muted-foreground text-center">
                كل رقم مرتبط بمعاملة موثقة
              </p>
            </CardContent>
          </Card>

          {project.description_ar && (
            <Card>
              <CardHeader><h3 className="font-semibold">عن المشروع</h3></CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground leading-relaxed">{project.description_ar}</p>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Tab: Transactions */}
      {tab === 'transactions' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold">سجل المعاملات</h3>
            <Button size="sm" onClick={() => setShowTxForm(true)}>
              <Plus className="h-4 w-4" /> معاملة جديدة
            </Button>
          </div>

          {showTxForm && (
            <Card>
              <CardContent>
                <TransactionForm
                  projectId={projectId}
                  onSubmit={handleAddTransaction}
                  onCancel={() => setShowTxForm(false)}
                />
              </CardContent>
            </Card>
          )}

          {transactions.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">لا توجد معاملات بعد</p>
          ) : (
            <Card>
              <div className="divide-y divide-border">
                {transactions.map((tx) => (
                  <div key={tx.id} className="flex items-center gap-3 px-4 py-3">
                    <div className={`h-2 w-2 rounded-full flex-shrink-0 ${tx.direction === 'income' ? 'bg-success' : 'bg-danger'}`} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{tx.description || CATEGORY_LABELS[tx.category] || tx.category}</p>
                      <p className="text-xs text-muted-foreground">{tx.transaction_date}</p>
                    </div>
                    <div className="text-end">
                      <p className={`text-sm font-bold ${tx.direction === 'income' ? 'text-success' : 'text-danger'}`}>
                        {tx.direction === 'income' ? '+' : '−'}{formatEgp(tx.amount_egp)} EGP
                      </p>
                      <p className="text-xs text-muted-foreground">{tx.currency !== 'EGP' ? `${tx.amount} ${tx.currency}` : ''}</p>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}

      {/* Tab: Assets */}
      {tab === 'assets' && (
        <div>
          {assets.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">لا توجد أصول مسجلة بعد</p>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2">
              {assets.map((asset) => (
                <Card key={asset.id}>
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between">
                      <div>
                        <p className="font-medium">{asset.name_ar}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">{asset.type} • {asset.status}</p>
                      </div>
                      <p className="text-sm font-bold text-primary">
                        {formatEgp(asset.acquisition_cost_egp)} EGP
                      </p>
                    </div>
                    {asset.quantity && (
                      <p className="mt-2 text-xs text-muted-foreground">{asset.quantity} {asset.unit}</p>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Tab: Documents */}
      {tab === 'documents' && (
        <div>
          {documents.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">لا توجد مستندات مرتبطة بعد</p>
          ) : (
            <Card>
              <div className="divide-y divide-border">
                {documents.map((doc) => (
                  <div key={doc.id} className="flex items-center gap-3 px-4 py-3">
                    <FileText className="h-5 w-5 text-muted-foreground flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{doc.title_ar}</p>
                      <p className="text-xs text-muted-foreground">{doc.type} • {doc.issue_date ?? '—'}</p>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  );
}
