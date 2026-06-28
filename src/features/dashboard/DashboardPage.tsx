import { Plus, TrendingUp, TrendingDown, Building2, Wheat, PawPrint, AlertCircle, ArrowLeft, Globe, BarChart2 } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { Badge } from '../../components/ui/Badge';
import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from '../partners/hooks';
import { computeGlobalSummary, formatEgp } from '../../core/lib/profitability';
import type { SectorId } from '../../core/types/domain';
import { useI18n } from '../../core/i18n/context';
import { Suspense, lazy } from 'react';

// Lazy load charts to enable code-splitting
const RevenueChartLazy = lazy(() => import('../../components/charts/RevenueChart').then(m => ({ default: m.RevenueChart })));
const SectorBarChartLazy = lazy(() => import('../../components/charts/SectorBarChart').then(m => ({ default: m.SectorBarChart })));

const SECTOR_META: Record<SectorId, { icon: typeof Building2; i18nKey: 'sector_real_estate_name' | 'sector_agriculture_name' | 'sector_livestock_name'; color: string; bg: string; route: string }> = {
  'real-estate': { icon: Building2, i18nKey: 'sector_real_estate_name',  color: 'text-amber-700', bg: 'bg-amber-50 border-amber-200', route: '/real-estate' },
  agriculture:   { icon: Wheat,     i18nKey: 'sector_agriculture_name',  color: 'text-green-700', bg: 'bg-green-50 border-green-200', route: '/agriculture' },
  livestock:     { icon: PawPrint,  i18nKey: 'sector_livestock_name', color: 'text-blue-700',  bg: 'bg-blue-50 border-blue-200',   route: '/livestock' },
};

export function DashboardPage() {
  const router = useRouter();
  const { t, locale, setLocale } = useI18n();
  const { projects } = useProjects();
  const { transactions } = useTransactions();
  const { obligations, open: openObls } = useObligations();
  const { partners } = usePartners();

  const global = computeGlobalSummary(projects, transactions, obligations);
  const isProfit = global.gross_profit_egp >= 0;

  const today = new Date().toISOString().slice(0, 10);
  const overdue = openObls.filter((o) => o.due_date && o.due_date < today);
  const dueSoon = openObls.filter((o) => o.due_date && o.due_date >= today && o.due_date <= new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10));
  const priorityIds = new Set([...overdue, ...dueSoon].map((obligation) => obligation.id));
  const prioritizedOpenObls = [...overdue, ...dueSoon, ...openObls.filter((obligation) => !priorityIds.has(obligation.id))];

  function toggleLocale() {
    setLocale(locale === 'ar' ? 'en' : 'ar');
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={t('dashboard_title')}
        description={t('dashboard_description')}
      >
        <div className="flex gap-2">
          <button
            onClick={toggleLocale}
            className="flex items-center gap-2 rounded-xl border border-border bg-card px-3 py-2 text-xs hover:bg-muted transition"
            title={locale === 'ar' ? 'Switch to English' : 'التبديل للعربية'}
          >
            <Globe className="h-3.5 w-3.5" />
            {locale === 'ar' ? 'EN' : 'عربي'}
          </button>
          <Button onClick={() => router.navigate({ to: '/projects' } as any)}>
            <Plus className="h-4 w-4" /> {t('project_new')}
          </Button>
        </div>
      </PageHeader>

      {overdue.length > 0 && (
        <div className="flex items-start gap-3 rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3">
          <AlertCircle className="h-5 w-5 text-danger flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-danger">
              {overdue.length} {locale === 'ar' ? 'التزام متأخر عن الاستحقاق' : 'overdue obligations'}
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {locale === 'ar' ? 'تأكد من مراجعة صفحة الذمم والالتزامات' : 'Check obligations page'}
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {[
          { key: 'kpi_total_revenue', value: global.total_income_egp, color: 'text-success', Icon: TrendingUp },
          { key: 'kpi_total_expenses', value: global.total_expense_egp, color: 'text-danger', Icon: TrendingDown },
          { key: 'kpi_net_profit', value: global.gross_profit_egp, color: isProfit ? 'text-success' : 'text-danger', Icon: isProfit ? TrendingUp : TrendingDown },
          { key: 'kpi_open_receivables', value: global.open_receivables_egp, color: 'text-warning', Icon: AlertCircle },
        ].map((kpi) => (
          <Card key={kpi.key}>
            <CardContent className="p-4">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs text-muted-foreground">{t(kpi.key as any)}</span>
                <kpi.Icon className={`h-4 w-4 ${kpi.color}`} />
              </div>
              <p className={`text-xl font-bold ${kpi.color}`}>{formatEgp(kpi.value, true)}</p>
              <p className="text-xs text-muted-foreground">EGP • {t('dashboard_period_label')}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Charts — Recharts MVP — ADR-007 */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div className="flex items-center gap-2">
              <BarChart2 className="h-4 w-4 text-primary" />
              <h3 className="font-semibold">{locale==='ar' ? 'الإيرادات مقابل المصروفات — 12 شهر' : 'Revenue vs Expense — 12m'}</h3>
            </div>
          </CardHeader>
          <CardContent>
            <Suspense fallback={<div className="h-[280px] flex items-center justify-center text-sm text-muted-foreground">{t('state_loading')}</div>}>
              <RevenueChartLazy transactions={transactions} />
            </Suspense>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <h3 className="font-semibold text-sm">{t('profitability_by_sector')}</h3>
          </CardHeader>
          <CardContent>
            <Suspense fallback={<div className="h-[220px] flex items-center justify-center text-sm text-muted-foreground">{t('state_loading')}</div>}>
              <SectorBarChartLazy data={(Object.keys(SECTOR_META) as SectorId[]).map(sId => ({
                sector_id: sId,
                label_ar: t(SECTOR_META[sId].i18nKey),
                profit_egp: global.by_sector[sId].gross_profit_egp,
                income_egp: global.by_sector[sId].total_income_egp,
                expense_egp: global.by_sector[sId].total_expense_egp,
              }))} />
            </Suspense>
          </CardContent>
        </Card>
      </div>

      <div>
        <h3 className="mb-3 font-semibold">{t('profitability_by_sector')}</h3>
        <div className="grid gap-4 sm:grid-cols-3">
          {(Object.keys(SECTOR_META) as SectorId[]).map((sId) => {
            const meta = SECTOR_META[sId];
            const s = global.by_sector[sId];
            const Icon = meta.icon;
            const positive = s.gross_profit_egp >= 0;
            const sectorProjects = projects.filter((p) => p.sector_id === sId);

            return (
              <button
                key={sId}
                onClick={() => router.navigate({ to: meta.route } as any)}
                className="group text-start rounded-2xl border border-border bg-card p-5 shadow-sm hover:border-primary/30 hover:shadow-md transition cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                <div className="mb-4 flex items-center justify-between">
                  <div className={`flex h-10 w-10 items-center justify-center rounded-xl border ${meta.bg}`}>
                    <Icon className={`h-5 w-5 ${meta.color}`} />
                  </div>
                  <ArrowLeft className="h-4 w-4 text-muted-foreground transition group-hover:text-primary rtl:rotate-180" />
                </div>
                <p className="mb-1 font-semibold">{t(meta.i18nKey)}</p>
                <p className="text-xs text-muted-foreground mb-3">{sectorProjects.length} {locale === 'ar' ? 'مشروع' : 'projects'}</p>

                <div className="space-y-1.5">
                  <div className="flex justify-between text-xs">
                    <span className="text-muted-foreground">{t('profit_income')}</span>
                    <span className="font-medium text-success">{formatEgp(s.total_income_egp, true)} EGP</span>
                  </div>
                  <div className="flex justify-between text-xs">
                    <span className="text-muted-foreground">{t('profit_expense')}</span>
                    <span className="font-medium text-danger">{formatEgp(s.total_expense_egp, true)} EGP</span>
                  </div>
                  <div className={`flex justify-between rounded-lg px-2 py-1.5 text-xs font-bold mt-1 ${positive ? 'bg-success/10 text-success' : 'bg-danger/10 text-danger'}`}>
                    <span>{t('profit_gross')}</span>
                    <span>{positive ? '+' : ''}{formatEgp(s.gross_profit_egp, true)} EGP</span>
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <h3 className="font-semibold">{locale === 'ar' ? 'آخر المشاريع' : 'Recent Projects'}</h3>
              <button onClick={() => router.navigate({ to: '/projects' } as any)} className="text-xs text-primary hover:underline">{t('action_view_all')}</button>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {projects.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_empty_title')}</p>
            ) : (
              <div className="divide-y divide-border">
                {projects.slice(0, 5).map((p) => {
                  const meta = SECTOR_META[p.sector_id];
                  const Icon = meta.icon;
                  const txCount = transactions.filter(tx => tx.project_id === p.id).length;
                  return (
                    <div key={p.id} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/50 transition">
                      <div className={`flex h-8 w-8 items-center justify-center rounded-lg border ${meta.bg} flex-shrink-0`}>
                        <Icon className={`h-4 w-4 ${meta.color}`} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">{locale === 'ar' ? p.name_ar : (p.name_en || p.name_ar)}</p>
                        <p className="text-xs text-muted-foreground">{txCount} {locale === 'ar' ? 'معاملة' : 'txns'}</p>
                      </div>
                      <Badge tone={p.status === 'active' ? 'positive' : 'neutral'}>{t(`project_status_${p.status}` as any) ?? p.status}</Badge>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <h3 className="font-semibold">{t('obligations_title')}</h3>
              <button onClick={() => router.navigate({ to: '/finance/obligations' } as any)} className="text-xs text-primary hover:underline">{t('action_view_all')}</button>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {openObls.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_empty_title')}</p>
            ) : (
              <div className="divide-y divide-border">
                {prioritizedOpenObls.slice(0, 5).map((o) => {
                  const partnerName = partners.find(pr => pr.id === o.partner_id)?.name_ar ?? o.partner_id;
                  const isLate = o.due_date && o.due_date < today;
                  const remaining = o.amount_egp - o.amount_settled_egp;
                  return (
                    <div key={o.id} className="flex items-center gap-3 px-4 py-3">
                      <div className={`h-2 w-2 rounded-full flex-shrink-0 ${isLate ? 'bg-danger' : 'bg-warning'}`} />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">{partnerName}</p>
                        <p className={`text-xs ${isLate ? 'text-danger' : 'text-muted-foreground'}`}>
                          {isLate ? (locale==='ar' ? 'متأخر — ' : 'Overdue — ') : ''}{o.due_date ?? t('status_open')}
                        </p>
                      </div>
                      <span className={`text-sm font-bold flex-shrink-0 ${o.direction === 'receivable' ? 'text-success' : 'text-danger'}`}>
                        {formatEgp(remaining, true)} EGP
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 min-[420px]:grid-cols-3">
        {[
          { label_key: 'nav_projects' as const, value: projects.length, sub: `${projects.filter(pr => pr.status === 'active').length} ${t('sector_status_active')}` },
          { label_key: 'transactions_title' as const, value: transactions.length, sub: `${transactions.filter(tx => tx.direction === 'income').length} ↑ / ${transactions.filter(tx => tx.direction === 'expense').length} ↓` },
          { label_key: 'partners_title' as const, value: partners.length, sub: `${openObls.length} ${locale==='ar' ? 'التزام مفتوح' : 'open'}` },
        ].map((stat) => (
          <Card key={stat.label_key}>
            <CardContent className="p-4 text-center">
              <p className="text-3xl font-bold">{stat.value}</p>
              <p className="text-sm font-medium mt-1">{t(stat.label_key)}</p>
              <p className="text-xs text-muted-foreground mt-0.5">{stat.sub}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="text-center text-[11px] text-muted-foreground pt-2 border-t border-border">
        {t('dashboard_period_note')} • {t('profitability_desc')} • v0.2.0-p0
      </div>
    </div>
  );
}
