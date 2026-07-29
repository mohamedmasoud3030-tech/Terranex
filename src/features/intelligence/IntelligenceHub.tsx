import { useMemo, useState } from 'react';
import { BarChart3, Boxes, Download, FileText, Gauge, Landmark, LayoutDashboard, Users } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { EmptyState } from '../../components/ui/States';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { formatEgp } from '../../core/lib/profitability';
import { useI18n } from '../../core/i18n/context';
import type { Asset, Partner, Project, SectorId } from '../../core/types/domain';
import {
  buildFilteredReportCsv,
  buildIntelligenceReport,
  reconcileIntelligenceReport,
  validateReportContext,
  type ReportContext,
} from './reportModel';
import { useIntelligenceData } from './useIntelligenceData';

const workspaceIds = ['executive', 'projects', 'sectors', 'aging', 'statement', 'assets'] as const;
type Evidence = { projectId: string } | null;

export function IntelligenceHub({ onFinanceDrillDown }: { onFinanceDrillDown?: (context: ReportContext) => void }) {
  const { locale } = useI18n();
  const { records, loading } = useIntelligenceData();
  const [workspace, setWorkspace] = useWorkspaceUrlState(workspaceIds, 'executive', { parameter: 'intelligence_view' });
  const [context, setContext] = useState<ReportContext>({ sector: 'all', displayCurrency: 'EGP' });
  const [evidence, setEvidence] = useState<Evidence>(null);
  const [pdfLoading, setPdfLoading] = useState(false);
  const asOf = context.dateTo ?? new Date().toISOString().slice(0, 10);
  const report = useMemo(() => buildIntelligenceReport(records, context, asOf), [asOf, context, records]);
  const contextError = validateReportContext(context);
  const reconciliation = reconcileIntelligenceReport(report);
  const evidenceProject = evidence ? records.projects.find((item) => item.id === evidence.projectId) : undefined;
  const evidenceTransactions = evidence ? report.filtered.transactions.filter((item) => item.project_id === evidence.projectId) : [];
  const evidenceDocuments = evidence ? report.filtered.documents.filter((item) => item.project_id === evidence.projectId) : [];

  const workspaces = [
    { id: 'executive', label: locale === 'ar' ? 'الأداء التنفيذي' : 'Executive', icon: LayoutDashboard },
    { id: 'projects', label: locale === 'ar' ? 'ربحية المشاريع' : 'Projects', icon: Landmark },
    { id: 'sectors', label: locale === 'ar' ? 'أداء القطاعات' : 'Sectors', icon: BarChart3 },
    { id: 'aging', label: locale === 'ar' ? 'أعمار الذمم' : 'Aging', icon: Gauge },
    { id: 'statement', label: locale === 'ar' ? 'كشف الطرف' : 'Partner statement', icon: Users },
    { id: 'assets', label: locale === 'ar' ? 'مركز الأصول' : 'Asset position', icon: Boxes },
  ];

  function exportCsv() {
    const blob = new Blob([`\uFEFF${buildFilteredReportCsv(report)}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `Terranex-Intelligence-${asOf}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async function exportPdf() {
    setPdfLoading(true);
    try {
      const [{ pdf }, { GlobalProfitabilityPdfDocument, downloadGlobalPdf }] = await Promise.all([
        import('@react-pdf/renderer'),
        import('../reports/GlobalProfitabilityPdf'),
      ]);
      const blob = await pdf(
        <GlobalProfitabilityPdfDocument
          global={report.executive}
          projectProfits={report.projects}
          projectNames={new Map(report.filtered.projects.map((item) => [item.id, locale === 'ar' ? item.name_ar : item.name_en]))}
          transactions={report.filtered.transactions}
          obligations={report.filtered.obligations}
          generatedAt={new Date().toISOString()}
          generatedBy={`Terranex Intelligence · ${locale.toUpperCase()}`}
        />,
      ).toBlob();
      await downloadGlobalPdf(blob, `Terranex-Intelligence-${asOf}.pdf`);
    } finally {
      setPdfLoading(false);
    }
  }

  return (
    <>
      <WorkspaceShell
        title={locale === 'ar' ? 'مركز الذكاء' : 'Intelligence Hub'}
        description={locale === 'ar' ? 'سياق تقارير واحد يربط الأداء والربحية والذمم والأطراف والأصول بالدليل.' : 'One report context connecting performance, profitability, aging, partners, assets, and evidence.'}
        workspaces={workspaces}
        activeWorkspace={workspace}
        onWorkspaceChange={setWorkspace}
        switcherLabel={locale === 'ar' ? 'تقارير الذكاء' : 'Intelligence reports'}
        loadingLabel={locale === 'ar' ? 'جار بناء التقارير' : 'Building reports'}
        state={loading ? 'loading' : 'ready'}
        actions={<><Button variant="secondary" disabled={Boolean(contextError)} onClick={exportCsv}><Download className="h-4 w-4" />CSV</Button><Button variant="secondary" disabled={pdfLoading || Boolean(contextError)} onClick={() => void exportPdf()}><FileText className="h-4 w-4" />PDF</Button></>}
        summaries={<><ReportFilters context={context} locale={locale} projects={records.projects} assets={records.assets} partners={records.partners} onChange={setContext} />{contextError && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{locale === 'ar' ? 'يجب أن يكون تاريخ البداية قبل تاريخ النهاية أو مساويًا له.' : contextError}</p>}</>}
      >
        {workspace === 'executive' && <ExecutiveView report={report} locale={locale} reconciliation={reconciliation} />}
        {workspace === 'projects' && <ProjectsView report={report} locale={locale} onEvidence={(projectId) => setEvidence({ projectId })} />}
        {workspace === 'sectors' && <SectorsView report={report} locale={locale} />}
        {workspace === 'aging' && <AgingView report={report} locale={locale} onDrillDown={() => onFinanceDrillDown?.(context)} />}
        {workspace === 'statement' && <StatementView report={report} locale={locale} />}
        {workspace === 'assets' && <AssetsView report={report} locale={locale} />}
      </WorkspaceShell>
      <EntityInspectorDrawer
        open={Boolean(evidence)}
        onOpenChange={(open) => { if (!open) setEvidence(null); }}
        title={evidenceProject ? (locale === 'ar' ? evidenceProject.name_ar : evidenceProject.name_en) : ''}
        description={locale === 'ar' ? 'دليل الرقم المعروض' : 'Evidence behind the displayed number'}
        closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'}
        relationshipsLabel={locale === 'ar' ? 'مصادر البيانات' : 'Data sources'}
        activityLabel={locale === 'ar' ? 'الحركات' : 'Movements'}
        summary={<p className="text-sm">{evidenceTransactions.length} {locale === 'ar' ? 'معاملة' : 'transactions'} · {evidenceDocuments.length} {locale === 'ar' ? 'مستند' : 'documents'}</p>}
        relationships={<div className="space-y-2">{evidenceDocuments.map((item) => <p key={item.id} className="rounded-xl border p-2 text-sm">{item.title_ar}</p>)}</div>}
        activity={<div className="space-y-2">{evidenceTransactions.map((item) => <p key={item.id} className="rounded-xl border p-2 text-sm">{item.transaction_date} · {item.category} · {formatEgp(item.amount_egp)} EGP</p>)}</div>}
      />
    </>
  );
}

function ReportFilters({ context, locale, projects, assets, partners, onChange }: { context: ReportContext; locale: 'ar' | 'en'; projects: Project[]; assets: Asset[]; partners: Partner[]; onChange: (context: ReportContext) => void }) {
  const visibleProjectIds = new Set(projects.filter((item) => !context.sector || context.sector === 'all' || item.sector_id === context.sector).map((item) => item.id));
  return <div className="grid gap-3 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2 xl:grid-cols-6"><input aria-label={locale === 'ar' ? 'من تاريخ' : 'From date'} type="date" value={context.dateFrom ?? ''} onChange={(event) => onChange({ ...context, dateFrom: event.target.value || undefined })} className="min-h-11 rounded-xl border bg-card px-3" /><input aria-label={locale === 'ar' ? 'إلى تاريخ' : 'To date'} type="date" value={context.dateTo ?? ''} onChange={(event) => onChange({ ...context, dateTo: event.target.value || undefined })} className="min-h-11 rounded-xl border bg-card px-3" /><select aria-label={locale === 'ar' ? 'القطاع' : 'Sector'} value={context.sector ?? 'all'} onChange={(event) => onChange({ ...context, sector: event.target.value as SectorId | 'all', projectId: undefined, assetId: undefined })} className="min-h-11 rounded-xl border bg-card px-3"><option value="all">All sectors</option><option value="real-estate">Real estate</option><option value="agriculture">Agriculture</option><option value="livestock">Livestock</option></select><select aria-label={locale === 'ar' ? 'المشروع' : 'Project'} value={context.projectId ?? ''} onChange={(event) => onChange({ ...context, projectId: event.target.value || undefined, assetId: undefined })} className="min-h-11 rounded-xl border bg-card px-3"><option value="">All projects</option>{projects.filter((item) => visibleProjectIds.has(item.id)).map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en}</option>)}</select><select aria-label={locale === 'ar' ? 'الأصل' : 'Asset'} value={context.assetId ?? ''} onChange={(event) => onChange({ ...context, assetId: event.target.value || undefined })} className="min-h-11 rounded-xl border bg-card px-3"><option value="">All assets</option>{assets.filter((item) => visibleProjectIds.has(item.project_id) && (!context.projectId || item.project_id === context.projectId)).map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en}</option>)}</select><select aria-label={locale === 'ar' ? 'الطرف' : 'Partner'} value={context.partnerId ?? ''} onChange={(event) => onChange({ ...context, partnerId: event.target.value || undefined })} className="min-h-11 rounded-xl border bg-card px-3"><option value="">All partners</option>{partners.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en ?? item.name_ar}</option>)}</select></div>;
}

type Report = ReturnType<typeof buildIntelligenceReport>;
function ExecutiveView({ report, locale, reconciliation }: { report: Report; locale: 'ar' | 'en'; reconciliation: ReturnType<typeof reconcileIntelligenceReport> }) {
  const rows = [['Income', report.executive.total_income_egp], ['Expense', report.executive.total_expense_egp], ['Gross profit', report.executive.gross_profit_egp], ['Cash exposure', report.executive.cash_exposure_egp]] as const;
  return <div className="space-y-4"><div className="grid grid-cols-2 gap-3 xl:grid-cols-4">{rows.map(([label, value]) => <Card key={label}><CardContent className="p-4"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 text-xl font-bold">{formatEgp(value)} EGP</p></CardContent></Card>)}</div><p className={`rounded-xl border p-3 text-sm ${reconciliation.income && reconciliation.expense ? 'border-success/30 bg-success/5' : 'border-danger/30 bg-danger/5'}`}>{locale === 'ar' ? 'التصالح بين الإجمالي والمشاريع والقطاعات' : 'Executive/project/sector reconciliation'}: {reconciliation.income && reconciliation.expense ? '✓' : '✕'}</p></div>;
}
function ProjectsView({ report, locale, onEvidence }: { report: Report; locale: 'ar' | 'en'; onEvidence: (id: string) => void }) { return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'ربحية المشاريع' : 'Project profitability'}</h2></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th className="p-2 text-start">Project</th><th className="p-2 text-end">Income</th><th className="p-2 text-end">Expense</th><th className="p-2 text-end">Profit</th></tr></thead><tbody>{report.projects.map((item) => <tr key={item.project_id} className="border-t"><td className="p-2"><button className="min-h-11 font-semibold" onClick={() => onEvidence(item.project_id)}>{locale === 'ar' ? item.project_name_ar : item.project_name_en}</button></td><td className="p-2 text-end">{formatEgp(item.total_income_egp)}</td><td className="p-2 text-end">{formatEgp(item.total_expense_egp)}</td><td className="p-2 text-end font-bold">{formatEgp(item.gross_profit_egp)}</td></tr>)}</tbody></table></div></CardContent></Card>; }
function SectorsView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) { const sectors = Object.entries(report.sectors); return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'أداء القطاعات' : 'Sector performance'}</h2></CardHeader><CardContent><div className="space-y-3" aria-hidden="true">{sectors.map(([id, item]) => <div key={id}><p className="text-sm font-semibold">{id}</p><div className="mt-1 h-3 rounded-full bg-muted"><div className="h-3 rounded-full bg-primary" style={{ width: `${Math.min(100, Math.abs(item.gross_profit_egp) / Math.max(1, report.executive.total_income_egp) * 100)}%` }} /></div></div>)}</div><table className="mt-5 w-full text-sm"><caption className="sr-only">Accessible sector performance data</caption><thead><tr><th>Sector</th><th>Income</th><th>Expense</th><th>Profit</th></tr></thead><tbody>{sectors.map(([id, item]) => <tr key={id} className="border-t"><td className="p-2">{id}</td><td className="p-2">{formatEgp(item.total_income_egp)}</td><td className="p-2">{formatEgp(item.total_expense_egp)}</td><td className="p-2">{formatEgp(item.gross_profit_egp)}</td></tr>)}</tbody></table></CardContent></Card>; }
function AgingView({ report, locale, onDrillDown }: { report: Report; locale: 'ar' | 'en'; onDrillDown: () => void }) { return <Card><CardHeader><div className="flex justify-between gap-3"><h2 className="font-bold">{locale === 'ar' ? 'أعمار الذمم' : 'Aging'}</h2><Button variant="secondary" onClick={onDrillDown}>{locale === 'ar' ? 'فتح المالية' : 'Open Finance'}</Button></div></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th>Bucket</th><th>Outstanding EGP</th></tr></thead><tbody>{['not_due','overdue_1_30','overdue_31_60','overdue_61_90','overdue_91_plus','undated'].map((bucket) => <tr key={bucket} className="border-t"><td className="p-2">{bucket}</td><td className="p-2">{formatEgp(report.aging.totals[`${bucket}_egp` as keyof typeof report.aging.totals])}</td></tr>)}</tbody></table></div></CardContent></Card>; }
function StatementView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) { if (!report.statement) return <EmptyState title={locale === 'ar' ? 'اختر طرفًا لعرض الكشف' : 'Choose a partner for a statement'} description="" icon={Users} />; return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'كشف الطرف' : 'Partner statement'} · {formatEgp(report.statement.closing_balance_egp)} EGP</h2></CardHeader><CardContent><div className="space-y-2">{report.statement.entries.map((item) => <div key={item.id} className="grid grid-cols-4 gap-2 rounded-xl border p-3 text-xs"><span>{item.entry_date}</span><span>{item.entry_type}</span><span>{formatEgp(item.debit_egp)} / {formatEgp(item.credit_egp)}</span><strong>{formatEgp(item.running_balance_egp)}</strong></div>)}</div></CardContent></Card>; }
function AssetsView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) { return <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{report.assetPositions.map(({ asset, balance }) => <Card key={asset.id}><CardContent className="p-4"><h3 className="font-bold">{locale === 'ar' ? asset.name_ar : asset.name_en}</h3><p className="text-xs text-muted-foreground">{asset.type} · {asset.sector_id}</p><p className="mt-3 text-lg font-bold">{balance ? `${balance.quantity} ${asset.unit ?? ''}` : `${formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp)} EGP`}</p></CardContent></Card>)}</div>; }
