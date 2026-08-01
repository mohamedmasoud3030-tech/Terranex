import { useEffect, useMemo, useState } from 'react';
import { BarChart3, Boxes, Download, FileText, Gauge, Landmark, LayoutDashboard, Users } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { EmptyState } from '../../components/ui/States';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { downloadBlob } from '../../core/lib/download';
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

const workspaceIds = ['executive', 'profitability', 'ownership', 'distributions', 'sectors', 'aging', 'statement', 'assets'] as const;
type Evidence = { projectId: string } | null;
const reportSectors: Array<SectorId | 'all'> = ['all', 'real-estate', 'agriculture', 'livestock'];

function readReportContext(): ReportContext {
  if (typeof window === 'undefined') return { sector: 'all', displayCurrency: 'EGP' };
  const search = new URL(window.location.href).searchParams;
  const sector = search.get('sector');
  return {
    dateFrom: search.get('from') || undefined,
    dateTo: search.get('to') || undefined,
    sector: reportSectors.includes(sector as SectorId | 'all') ? sector as SectorId | 'all' : 'all',
    projectId: search.get('project') || undefined,
    assetId: search.get('asset') || undefined,
    partnerId: search.get('partner') || undefined,
    displayCurrency: 'EGP',
  };
}

export function IntelligenceHub({ onFinanceDrillDown }: { onFinanceDrillDown?: (context: ReportContext) => void }) {
  const { locale } = useI18n();
  const { records, loading } = useIntelligenceData();
  const [workspace, setWorkspace] = useWorkspaceUrlState(workspaceIds, 'executive', { parameter: 'workspace' });
  const [context, setContext] = useState<ReportContext>(readReportContext);
  const [evidence, setEvidence] = useState<Evidence>(null);
  const [pdfLoading, setPdfLoading] = useState(false);
  const asOf = context.dateTo ?? new Date().toISOString().slice(0, 10);
  const report = useMemo(() => buildIntelligenceReport(records, context, asOf), [asOf, context, records]);
  const contextError = validateReportContext(context);
  const reconciliation = reconcileIntelligenceReport(report);
  const evidenceProject = evidence ? records.projects.find((item) => item.id === evidence.projectId) : undefined;
  const evidenceTransactions = evidence ? report.filtered.transactions.filter((item) => item.project_id === evidence.projectId) : [];
  const evidenceDocuments = evidence ? report.filtered.documents.filter((item) => item.project_id === evidence.projectId) : [];

  function commitContext(next: ReportContext) {
    const url = new URL(window.location.href);
    for (const key of ['from', 'to', 'sector', 'project', 'asset', 'partner']) url.searchParams.delete(key);
    const values = {
      from: next.dateFrom,
      to: next.dateTo,
      sector: next.sector === 'all' ? undefined : next.sector,
      project: next.projectId,
      asset: next.assetId,
      partner: next.partnerId,
    };
    for (const [key, value] of Object.entries(values)) if (value) url.searchParams.set(key, value);
    window.history.replaceState(window.history.state, '', url);
    setContext(next);
  }

  useEffect(() => {
    const sync = () => setContext(readReportContext());
    window.addEventListener('popstate', sync);
    return () => window.removeEventListener('popstate', sync);
  }, []);

  const workspaces = [
    { id: 'executive', label: locale === 'ar' ? 'الأداء التنفيذي' : 'Executive', icon: LayoutDashboard },
    { id: 'profitability', label: locale === 'ar' ? 'ربحية المشاريع' : 'Profitability', icon: Landmark },
    { id: 'ownership', label: locale === 'ar' ? 'تقرير الملكية' : 'Ownership report', icon: Users },
    { id: 'distributions', label: locale === 'ar' ? 'تقرير التوزيعات' : 'Distribution report', icon: FileText },
    { id: 'sectors', label: locale === 'ar' ? 'أداء القطاعات' : 'Sectors', icon: BarChart3 },
    { id: 'aging', label: locale === 'ar' ? 'أعمار الذمم' : 'Aging', icon: Gauge },
    { id: 'statement', label: locale === 'ar' ? 'كشف الطرف' : 'Partner statement', icon: Users },
    { id: 'assets', label: locale === 'ar' ? 'مركز الأصول' : 'Asset position', icon: Boxes },
  ];

  function exportCsv() {
    const blob = new Blob([`\uFEFF${buildFilteredReportCsv(report)}`], { type: 'text/csv;charset=utf-8' });
    downloadBlob(blob, `Terranex-Intelligence-${asOf}.csv`);
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
        summaries={<><ReportFilters context={context} locale={locale} projects={records.projects} assets={records.assets} partners={records.partners} onChange={commitContext} />{contextError && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{locale === 'ar' ? 'يجب أن يكون تاريخ البداية قبل تاريخ النهاية أو مساويًا له.' : contextError}</p>}</>}
      >
        {workspace === 'executive' && <ExecutiveView report={report} locale={locale} reconciliation={reconciliation} />}
        {workspace === 'profitability' && <ProjectsView report={report} locale={locale} onEvidence={(projectId) => setEvidence({ projectId })} />}
        {workspace === 'ownership' && <OwnershipReportView report={report} locale={locale} />}
        {workspace === 'distributions' && <DistributionReportView report={report} locale={locale} />}
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
function ProjectsView({ report, locale, onEvidence }: { report: Report; locale: 'ar' | 'en'; onEvidence: (id: string) => void }) {
  return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'ربحية المشاريع' : 'Project profitability'}</h2><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'قاعدة الملكية: كل معاملة حسب نسب تاريخها.' : 'Ownership rule: every transaction uses same-day ownership.'}</p></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th className="p-2 text-start">Project</th><th className="p-2 text-end">Income</th><th className="p-2 text-end">Expense</th><th className="p-2 text-end">Profit</th><th className="p-2 text-end">Distributed</th><th className="p-2 text-end">Undistributed</th></tr></thead><tbody>{report.projects.map((item) => <tr key={item.project_id} className="border-t"><td className="p-2"><button className="min-h-11 font-semibold" onClick={() => onEvidence(item.project_id)}>{locale === 'ar' ? item.project_name_ar : item.project_name_en}</button></td><td className="p-2 text-end">{formatEgp(item.total_income_egp)}</td><td className="p-2 text-end">{formatEgp(item.total_expense_egp)}</td><td className="p-2 text-end font-bold">{formatEgp(item.gross_profit_egp)}</td><td className="p-2 text-end">{formatEgp(item.distributed_profit_egp)}</td><td className="p-2 text-end">{formatEgp(item.undistributed_profit_egp)}</td></tr>)}</tbody></table></div></CardContent></Card>;
}

function OwnershipReportView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) {
  const asOf = report.projects[0]?.as_of_date ?? report.context.dateTo ?? new Date().toISOString().slice(0, 10);
  const projectNames = new Map(report.filtered.projects.map((project) => [project.id, locale === 'ar' ? project.name_ar : project.name_en || project.name_ar]));
  const partnerNames = new Map(report.filtered.partners.map((partner) => [partner.id, locale === 'ar' ? partner.name_ar : partner.name_en ?? partner.name_ar]));
  return <div className="space-y-4"><Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'تقرير ملكية المشاريع' : 'Project ownership report'}</h2><p className="text-sm text-muted-foreground">{locale === 'ar' ? `تاريخ التقرير: ${asOf}` : `As-of date: ${asOf}`}</p></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th className="p-2 text-start">Project</th><th className="p-2 text-start">Partner</th><th className="p-2 text-end">Current %</th><th className="p-2 text-start">Effective from</th><th className="p-2 text-start">Effective to</th></tr></thead><tbody>{report.filtered.projectPartners.map((row) => <tr key={row.id} className="border-t"><td className="p-2">{projectNames.get(row.project_id) ?? row.project_id}</td><td className="p-2">{partnerNames.get(row.partner_id) ?? row.partner_id}</td><td className="p-2 text-end font-bold">{row.equity_pct}%</td><td className="p-2">{row.effective_from}</td><td className="p-2">{row.effective_to ?? (locale === 'ar' ? 'نشط' : 'active')}</td></tr>)}</tbody></table></div></CardContent></Card><Card><CardHeader><h3 className="font-bold">{locale === 'ar' ? 'خط زمني لتغييرات الملكية' : 'Ownership change timeline'}</h3></CardHeader><CardContent><div className="space-y-2">{report.filtered.equityChangeEvents.slice().sort((a,b) => b.effective_date.localeCompare(a.effective_date)).map((event) => <div key={event.id} className="rounded-xl border p-3 text-xs"><strong>{event.effective_date} · {event.change_type}</strong><p>{projectNames.get(event.project_id) ?? event.project_id} · {partnerNames.get(event.partner_id) ?? event.partner_id} · {event.previous_pct}% → {event.new_pct}%</p><p className="text-muted-foreground">{event.reason ?? event.notes ?? '—'}</p></div>)}</div></CardContent></Card></div>;
}

function DistributionReportView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) {
  const projectNames = new Map(report.filtered.projects.map((project) => [project.id, locale === 'ar' ? project.name_ar : project.name_en || project.name_ar]));
  const partnerNames = new Map(report.filtered.partners.map((partner) => [partner.id, locale === 'ar' ? partner.name_ar : partner.name_en ?? partner.name_ar]));
  return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'تقرير التوزيعات' : 'Distribution report'}</h2><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'يعرض إجمالي التوزيع والتخصيصات المجمدة والمراكز المدفوعة وغير المدفوعة.' : 'Shows distribution totals, frozen allocations, and paid/unpaid positions.'}</p></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th className="p-2 text-start">Project</th><th className="p-2 text-start">Distribution date</th><th className="p-2 text-start">Ownership as of</th><th className="p-2 text-start">Partner</th><th className="p-2 text-end">Frozen %</th><th className="p-2 text-end">Allocated EGP</th><th className="p-2 text-start">Status</th></tr></thead><tbody>{report.filtered.distributionAllocations.map((allocation) => { const distribution = report.filtered.distributions.find((item) => item.id === allocation.distribution_id); return <tr key={allocation.id} className="border-t"><td className="p-2">{distribution ? projectNames.get(distribution.project_id) ?? distribution.project_id : '—'}</td><td className="p-2">{distribution?.distribution_date ?? '—'}</td><td className="p-2">{distribution?.ownership_as_of_date ?? '—'}</td><td className="p-2">{partnerNames.get(allocation.partner_id) ?? allocation.partner_id}</td><td className="p-2 text-end">{allocation.equity_pct_snapshot}%</td><td className="p-2 text-end font-bold">{formatEgp(allocation.allocated_amount_egp)}</td><td className="p-2">{allocation.status}</td></tr>; })}</tbody></table></div></CardContent></Card>;
}

function SectorsView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) { const sectors = Object.entries(report.sectors); return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'أداء القطاعات' : 'Sector performance'}</h2></CardHeader><CardContent><div className="space-y-3" aria-hidden="true">{sectors.map(([id, item]) => <div key={id}><p className="text-sm font-semibold">{id}</p><div className="mt-1 h-3 rounded-full bg-muted"><div className="h-3 rounded-full bg-primary" style={{ width: `${Math.min(100, Math.abs(item.gross_profit_egp) / Math.max(1, report.executive.total_income_egp) * 100)}%` }} /></div></div>)}</div><table className="mt-5 w-full text-sm"><caption className="sr-only">Accessible sector performance data</caption><thead><tr><th>Sector</th><th>Income</th><th>Expense</th><th>Profit</th></tr></thead><tbody>{sectors.map(([id, item]) => <tr key={id} className="border-t"><td className="p-2">{id}</td><td className="p-2">{formatEgp(item.total_income_egp)}</td><td className="p-2">{formatEgp(item.total_expense_egp)}</td><td className="p-2">{formatEgp(item.gross_profit_egp)}</td></tr>)}</tbody></table></CardContent></Card>; }
function AgingView({ report, locale, onDrillDown }: { report: Report; locale: 'ar' | 'en'; onDrillDown: () => void }) { return <Card><CardHeader><div className="flex justify-between gap-3"><h2 className="font-bold">{locale === 'ar' ? 'أعمار الذمم' : 'Aging'}</h2><Button variant="secondary" onClick={onDrillDown}>{locale === 'ar' ? 'فتح المالية' : 'Open Finance'}</Button></div></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr><th>Bucket</th><th>Outstanding EGP</th></tr></thead><tbody>{['not_due','overdue_1_30','overdue_31_60','overdue_61_90','overdue_91_plus','undated'].map((bucket) => <tr key={bucket} className="border-t"><td className="p-2">{bucket}</td><td className="p-2">{formatEgp(report.aging.totals[`${bucket}_egp` as keyof typeof report.aging.totals])}</td></tr>)}</tbody></table></div></CardContent></Card>; }
function StatementView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) {
  if (!report.statement && !report.partnerLedgerSummary) return <EmptyState title={locale === 'ar' ? 'اختر طرفًا لعرض الكشف' : 'Choose a partner for a statement'} description="" icon={Users} />;
  const summary = report.partnerLedgerSummary;
  return <div className="space-y-4"><Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'كشف الطرف' : 'Partner statement'} · {formatEgp(summary?.current_balance_egp ?? report.statement?.closing_balance_egp ?? 0)} EGP</h2></CardHeader><CardContent>{summary && <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4"><Metric label={locale === 'ar' ? 'مساهمات' : 'Contributions'} value={`${formatEgp(summary.capital_contributed_egp)} EGP`} /><Metric label={locale === 'ar' ? 'سحوبات' : 'Withdrawals'} value={`${formatEgp(summary.withdrawals_egp)} EGP`} /><Metric label={locale === 'ar' ? 'استحقاقات' : 'Entitlements'} value={`${formatEgp(summary.profit_entitlements_egp)} EGP`} /><Metric label={locale === 'ar' ? 'مدفوعات' : 'Payments'} value={`${formatEgp(summary.payments_made_egp)} EGP`} /></div>}</CardContent></Card><Card><CardHeader><h3 className="font-bold">{locale === 'ar' ? 'دفتر الشريك' : 'Partner ledger'}</h3></CardHeader><CardContent><div className="space-y-2">{report.partnerLedgerRows.map((item) => <div key={item.id} className="grid gap-2 rounded-xl border p-3 text-xs sm:grid-cols-5"><span>{item.posting_date}</span><span>{item.entry_type}</span><span>{item.amount.toLocaleString()} {item.currency}</span><strong>{formatEgp(item.active_effect_egp)} EGP</strong><span>{item.reversal_of_id ?? item.related_distribution_id ?? '—'}</span></div>)}</div></CardContent></Card>{report.statement && <Card><CardHeader><h3 className="font-bold">{locale === 'ar' ? 'الذمم والتسويات' : 'Obligations and settlements'}</h3></CardHeader><CardContent><div className="space-y-2">{report.statement.entries.map((item) => <div key={item.id} className="grid grid-cols-4 gap-2 rounded-xl border p-3 text-xs"><span>{item.entry_date}</span><span>{item.entry_type}</span><span>{formatEgp(item.debit_egp)} / {formatEgp(item.credit_egp)}</span><strong>{formatEgp(item.running_balance_egp)}</strong></div>)}</div></CardContent></Card>}</div>;
}

function Metric({ label, value }: { label: string; value: string }) { return <div className="rounded-xl border p-3"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 font-bold">{value}</p></div>; }

function AssetsView({ report, locale }: { report: Report; locale: 'ar' | 'en' }) { return <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{report.assetPositions.map(({ asset, balance }) => <Card key={asset.id}><CardContent className="p-4"><h3 className="font-bold">{locale === 'ar' ? asset.name_ar : asset.name_en}</h3><p className="text-xs text-muted-foreground">{asset.type} · {asset.sector_id}</p><p className="mt-3 text-lg font-bold">{balance ? `${balance.quantity} ${asset.unit ?? ''}` : `${formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp)} EGP`}</p></CardContent></Card>)}</div>; }
