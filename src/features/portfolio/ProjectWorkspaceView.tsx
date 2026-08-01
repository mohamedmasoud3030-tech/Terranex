import {
  BarChart3,
  CalendarDays,
  FilePlus2,
  FileText,
  HandCoins,
  History,
  Layers3,
  Pencil,
  Plus,
  ReceiptText,
  Trash2,
  Users,
} from 'lucide-react';
import { useState, type KeyboardEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import { formatEgp, computeProjectProfitability } from '../../core/lib/profitability';
import type {
  Asset,
  Distribution,
  DistributionAllocation,
  Document,
  EquityChangeEvent,
  Obligation,
  OperationalEvent,
  Partner,
  PartnerLedgerEntry,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
import {
  buildOwnershipTimeline,
  getDistributionAllocations,
  getDistributionPaidAmount,
  getOwnershipRowsAsOf,
  partnerName,
  summarizeOwnership,
} from '../ownership/model';
import type { PortfolioHandoff } from './contracts';

interface ProjectWorkspaceViewProps {
  project: Project;
  assets: Asset[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  documents: Document[];
  events: OperationalEvent[];
  equityChangeEvents?: EquityChangeEvent[];
  partnerLedgerEntries?: PartnerLedgerEntry[];
  distributions?: Distribution[];
  distributionAllocations?: DistributionAllocation[];
  locale: 'ar' | 'en';
  embedded?: boolean;
  onEditProject?: () => void;
  onDeleteProject?: () => void;
  onAddAsset?: () => void;
  onLinkPartner?: () => void;
  onOwnershipChange?: () => void;
  onCreateDistribution?: () => void;
  onInspectAsset?: (asset: Asset) => void;
  onInspectPartner?: (partner: Partner) => void;
  onHandoff?: (handoff: PortfolioHandoff) => void;
}

export function ProjectWorkspaceView({
  project,
  assets,
  partners,
  projectPartners,
  transactions,
  obligations,
  documents,
  events,
  equityChangeEvents = [],
  partnerLedgerEntries = [],
  distributions = [],
  distributionAllocations = [],
  locale,
  embedded = false,
  onEditProject,
  onDeleteProject,
  onAddAsset,
  onLinkPartner,
  onOwnershipChange,
  onCreateDistribution,
  onInspectAsset,
  onInspectPartner,
  onHandoff,
}: ProjectWorkspaceViewProps) {
  const projectAssets = assets.filter((asset) => asset.project_id === project.id);
  const links = projectPartners.filter((link) => link.project_id === project.id);
  const projectTransactions = transactions.filter((transaction) => transaction.project_id === project.id);
  const projectObligations = obligations.filter((obligation) => obligation.project_id === project.id);
  const projectDocuments = documents.filter((document) => document.project_id === project.id);
  const projectEvents = events.filter((event) => event.project_id === project.id);
  const projectDistributions = distributions.filter((distribution) => distribution.project_id === project.id);
  const projectLedgerEntries = partnerLedgerEntries.filter((entry) => entry.project_id === project.id);
  const today = new Date().toISOString().slice(0, 10);
  const [ownershipAsOfDate, setOwnershipAsOfDate] = useState(today);
  const ownershipRows = getOwnershipRowsAsOf(links, project.id, ownershipAsOfDate);
  const ownershipSummary = summarizeOwnership(ownershipRows);
  const ownershipTimeline = buildOwnershipTimeline(project.id, links, equityChangeEvents);
  const profitability = computeProjectProfitability(
    project,
    projectTransactions,
    projectObligations,
    links,
    partners,
    {
      as_of_date: ownershipAsOfDate,
      distributions: projectDistributions,
      distributionAllocations,
      partnerLedgerEntries: projectLedgerEntries,
    },
  );
  const partnerById = new Map(partners.map((partner) => [partner.id, partner]));
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const activity = [
    ...projectTransactions.map((item) => ({
      id: `transaction-${item.id}`,
      date: item.transaction_date,
      label: item.description || item.category,
      kind: label('معاملة', 'Transaction'),
    })),
    ...projectDocuments.map((item) => ({
      id: `document-${item.id}`,
      date: item.issue_date ?? item.created_at.slice(0, 10),
      label: locale === 'ar' ? item.title_ar : item.title_en || item.title_ar,
      kind: label('مستند', 'Document'),
    })),
    ...projectEvents.map((item) => ({
      id: `event-${item.id}`,
      date: item.event_date,
      label: item.description || item.type,
      kind: label('حدث تشغيلي', 'Operational event'),
    })),
    ...ownershipTimeline.map((item) => ({
      id: `ownership-${item.id}`,
      date: item.effective_date,
      label: `${item.change_type}: ${item.previous_pct}% → ${item.new_pct}%`,
      kind: label('تغيير ملكية', 'Ownership change'),
    })),
    ...projectDistributions.map((item) => ({
      id: `distribution-${item.id}`,
      date: item.distribution_date,
      label: `${label('توزيع أرباح', 'Profit distribution')} · ${item.total_amount.toLocaleString()} ${item.currency}`,
      kind: label('توزيع', 'Distribution'),
    })),
  ].sort((a, b) => b.date.localeCompare(a.date));

  const handoff = (intent: PortfolioHandoff['intent']) => {
    if (!onHandoff) return;
    const target =
      intent === 'attach-document' ? 'governance'
        : intent === 'create-transaction' ? 'finance'
          : 'operations';
    onHandoff({
      target,
      workspace:
        target === 'governance' ? 'documents'
          : target === 'finance' ? 'transactions'
            : 'events',
      context: { projectId: project.id, sector: project.sector_id },
      intent,
    });
  };
  const ownershipAction = onOwnershipChange ?? onLinkPartner;

  return (
    <article className="space-y-5" aria-labelledby={`project-${project.id}-title`}>
      <Card>
        <CardContent className="p-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div className="min-w-0">
              <p className="text-xs font-semibold uppercase tracking-wide text-primary">
                {label('مساحة مشروع', 'Project workspace')} · {project.sector_id}
              </p>
              <h2 id={`project-${project.id}-title`} className={embedded ? 'mt-1 text-2xl font-extrabold' : 'mt-1 text-3xl font-extrabold'}>
                {locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}
              </h2>
              <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">
                {locale === 'ar'
                  ? project.description_ar || 'لا يوجد وصف مسجل لهذا المشروع.'
                  : project.description_en || project.description_ar || 'No project description is recorded.'}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {onEditProject && (
                <Button variant="secondary" size="sm" onClick={onEditProject}>
                  <Pencil className="h-4 w-4" /> {label('تعديل المشروع', 'Edit project')}
                </Button>
              )}
              {onDeleteProject && (
                <Button variant="danger" size="sm" onClick={onDeleteProject}>
                  <Trash2 className="h-4 w-4" /> {label('حذف المشروع', 'Delete project')}
                </Button>
              )}
              {onAddAsset && (
                <Button size="sm" onClick={onAddAsset}>
                  <Plus className="h-4 w-4" /> {label('إضافة أصل', 'Add asset')}
                </Button>
              )}
              <Button variant="secondary" size="sm" onClick={() => handoff('attach-document')}>
                <FilePlus2 className="h-4 w-4" /> {label('إضافة مستند', 'Attach document')}
              </Button>
              <Button variant="secondary" size="sm" onClick={() => handoff('create-transaction')}>
                <ReceiptText className="h-4 w-4" /> {label('قيد مالي', 'Financial entry')}
              </Button>
              {onCreateDistribution && (
                <Button variant="secondary" size="sm" onClick={onCreateDistribution}>
                  <HandCoins className="h-4 w-4" /> {label('توزيع أرباح', 'Profit distribution')}
                </Button>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      <nav
        aria-label={label('أقسام المشروع', 'Project sections')}
        className="flex gap-2 overflow-x-auto pb-1"
      >
        {[
          ['summary', label('الملخص', 'Summary')],
          ['assets', label('الأصول', 'Assets')],
          ['partners', label('الشركاء والملكية', 'Partners & equity')],
          ['finance', label('الملخص المالي', 'Finance snapshot')],
          ['documents', label('المستندات', 'Documents')],
          ['activity', label('النشاط التشغيلي', 'Operational activity')],
        ].map(([id, text]) => (
          <a key={id} href={`#project-${project.id}-${id}`} className="inline-flex min-h-11 shrink-0 items-center rounded-xl border bg-card px-4 text-sm font-semibold hover:bg-muted">
            {text}
          </a>
        ))}
      </nav>

      <section id={`project-${project.id}-summary`} className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
        <SnapshotCard label={label('الأصول', 'Assets')} value={projectAssets.length} icon={Layers3} />
        <SnapshotCard label={label('الملكية المخصصة', 'Assigned equity')} value={`${ownershipSummary.assigned_pct.toFixed(2)}%`} icon={Users} />
        <SnapshotCard label={label('إجمالي الربح', 'Gross profit')} value={`${formatEgp(profitability.gross_profit_egp, true)} EGP`} icon={BarChart3} />
        <SnapshotCard label={label('ربح غير موزع', 'Undistributed profit')} value={`${formatEgp(profitability.undistributed_profit_egp, true)} EGP`} icon={ReceiptText} />
      </section>

      <section id={`project-${project.id}-assets`}>
        <SectionHeader
          title={label('الأصول', 'Assets')}
          description={label('الأصول التابعة للمشروع مع انتقال مباشر للسجل.', 'Project assets with direct record inspection.')}
          action={onAddAsset ? { label: label('إضافة أصل', 'Add asset'), onClick: onAddAsset } : undefined}
        />
        {projectAssets.length === 0 ? (
          <EmptyState title={label('لا توجد أصول', 'No assets')} description={label('أضف أول أصل داخل سياق المشروع.', 'Add the first asset within this project context.')} />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {projectAssets.map((asset) => (
              <div
                key={asset.id}
                {...(onInspectAsset
                  ? {
                      role: 'button',
                      tabIndex: 0,
                      onClick: () => onInspectAsset(asset),
                      onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => {
                        if (event.key === 'Enter' || event.key === ' ') onInspectAsset(asset);
                      },
                    }
                  : {})}
                className="min-h-11 rounded-2xl text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
              >
                <Card className="h-full hover:border-primary/40">
                  <CardContent>
                    <p className="font-bold">{locale === 'ar' ? asset.name_ar : asset.name_en || asset.name_ar}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{asset.type} · {asset.status}</p>
                    <p className="mt-3 text-sm font-bold text-primary">{formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp, true)} EGP</p>
                  </CardContent>
                </Card>
              </div>
            ))}
          </div>
        )}
      </section>

      <section id={`project-${project.id}-partners`}>
        <SectionHeader
          title={label('الشركاء والملكية', 'Partners and equity')}
          description={label('ملكية فعالة بتاريخ محدد مع سجل تاريخي غير قابل للتحرير.', 'Effective-dated ownership plus immutable history.')}
          action={ownershipAction ? { label: label('تغيير ملكية', 'Change ownership'), onClick: ownershipAction } : undefined}
        />
        <div className="mb-3 grid gap-3 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="text-xs font-semibold">
            {label('عرض الملكية كما في', 'Ownership as of')}
            <input
              type="date"
              aria-label={label('عرض الملكية كما في', 'Ownership as of')}
              value={ownershipAsOfDate}
              onChange={(event) => setOwnershipAsOfDate(event.target.value)}
              className="mt-1 min-h-11 w-full rounded-xl border bg-card px-3"
            />
          </label>
          <MetricBox label={label('المخصص', 'Assigned')} value={`${ownershipSummary.assigned_pct.toFixed(2)}%`} />
          <MetricBox label={label('غير مخصص', 'Unassigned')} value={`${ownershipSummary.remaining_pct.toFixed(2)}%`} />
          <MetricBox label={label('الحالة', 'Status')} value={ownershipSummary.exceeds_full ? label('يتجاوز 100%', 'Over 100%') : ownershipSummary.below_full ? label('أقل من 100%', 'Below 100%') : label('مكتمل', 'Complete')} tone={ownershipSummary.exceeds_full ? 'danger' : ownershipSummary.below_full ? 'warning' : 'success'} />
        </div>
        {ownershipSummary.below_full && !ownershipSummary.exceeds_full && (
          <p role="status" className="mb-3 rounded-xl border border-warning/30 bg-warning/5 p-3 text-sm text-warning-foreground">
            {label('تنبيه: إجمالي الملكية أقل من 100%، وتبقى النسبة غير المخصصة ظاهرة للتقارير.', 'Warning: total ownership is below 100%; the unassigned percentage remains explicit in reports.')}
          </p>
        )}
        {ownershipSummary.exceeds_full && (
          <p role="alert" className="mb-3 rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">
            {label('إجمالي الملكية يتجاوز 100%. يمنع نموذج التغيير أي تعديل يزيد هذا الخلل.', 'Total ownership exceeds 100%. The change form prevents any mutation that worsens this state.')}
          </p>
        )}
        {ownershipRows.length === 0 ? (
          <EmptyState title={label('لا توجد ملكية فعالة في هذا التاريخ', 'No effective ownership on this date')} description={label('استخدم تغيير الملكية لإدخال أو إعادة إدخال شريك عبر RPC ذري.', 'Use Change ownership to enter or re-enter a partner through the atomic RPC.')} />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {ownershipRows.map((row) => {
              const partner = partnerById.get(row.partner_id);
              return (
                <div
                  key={row.project_partner_id}
                  {...(partner && onInspectPartner
                    ? {
                        role: 'button',
                        tabIndex: 0,
                        onClick: () => onInspectPartner(partner),
                        onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => {
                          if (event.key === 'Enter' || event.key === ' ') onInspectPartner(partner);
                        },
                      }
                    : {})}
                  className="min-h-11 rounded-2xl text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
                >
                  <Card className="h-full hover:border-primary/40">
                    <CardContent>
                      <div className="flex items-center justify-between gap-3">
                        <p className="font-bold">{partnerName(partner, locale)}</p>
                        <strong className="text-primary">{row.equity_pct.toFixed(2)}%</strong>
                      </div>
                      <p className="mt-2 text-xs text-muted-foreground">
                        {label('ساري من', 'Effective from')} {row.effective_from}
                        {row.effective_to ? ` · ${label('حتى', 'to')} ${row.effective_to}` : ` · ${label('نشط', 'active')}`}
                      </p>
                    </CardContent>
                  </Card>
                </div>
              );
            })}
          </div>
        )}

        <Card className="mt-4">
          <CardContent className="p-4">
            <div className="flex items-center gap-2">
              <History className="h-4 w-4 text-primary" />
              <h4 className="font-extrabold">{label('سجل الملكية التاريخي', 'Ownership history')}</h4>
            </div>
            {ownershipTimeline.length === 0 ? (
              <p className="mt-3 text-sm text-muted-foreground">{label('لا توجد تغييرات ملكية مسجلة بعد.', 'No ownership changes have been recorded yet.')}</p>
            ) : (
              <div className="mt-3 space-y-2">
                {ownershipTimeline.slice(0, 10).map((item) => (
                  <div key={item.id} className="rounded-xl border p-3 text-sm">
                    <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                      <p className="font-bold">{partnerName(partnerById.get(item.partner_id), locale)} · {item.change_type}</p>
                      <p className="text-xs text-muted-foreground"><CalendarDays className="me-1 inline h-4 w-4" />{item.effective_date}</p>
                    </div>
                    <p className="mt-1 text-xs text-muted-foreground">{item.previous_pct}% → {item.new_pct}% · {item.reason || item.notes || label('دون سبب مسجل', 'No reason recorded')}</p>
                    <p className="mt-1 text-[11px] text-muted-foreground">{label('مرجع تدقيق', 'Audit reference')}: {item.audit_reference}</p>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </section>

      <section id={`project-${project.id}-finance`}>
        <SectionHeader title={label('الملخص المالي', 'Finance snapshot')} description={label('قراءة من محرك الربحية مع قاعدة تاريخية: كل معاملة تُنسب حسب ملكية يومها، والتوزيعات لا تُحتسب كمصروفات تشغيلية.', 'Read from the profitability engine with a temporal rule: every transaction is attributed by same-day ownership, and distributions are not operational expenses.')} />
        <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
          <SnapshotCard label={label('الإيرادات', 'Income')} value={`${formatEgp(profitability.total_income_egp, true)} EGP`} icon={ReceiptText} />
          <SnapshotCard label={label('المصروفات', 'Expenses')} value={`${formatEgp(profitability.total_expense_egp, true)} EGP`} icon={ReceiptText} />
          <SnapshotCard label={label('موزع', 'Distributed')} value={`${formatEgp(profitability.distributed_profit_egp, true)} EGP`} icon={HandCoins} />
          <SnapshotCard label={label('غير مدفوع', 'Unpaid distributions')} value={`${formatEgp(profitability.unpaid_distribution_amounts_egp, true)} EGP`} icon={ReceiptText} />
        </div>
        {projectDistributions.length > 0 && (
          <Card className="mt-4">
            <CardContent className="p-4">
              <h4 className="font-extrabold">{label('توزيعات المشروع', 'Project distributions')}</h4>
              <div className="mt-3 overflow-x-auto">
                <table className="w-full text-sm">
                  <caption className="sr-only">{label('قائمة توزيعات المشروع', 'Project distribution list')}</caption>
                  <thead><tr className="border-b text-xs text-muted-foreground"><th className="p-2 text-start">{label('التاريخ', 'Date')}</th><th className="p-2 text-start">{label('ملكية كما في', 'Ownership as of')}</th><th className="p-2 text-end">{label('الإجمالي', 'Total')}</th><th className="p-2 text-end">{label('مدفوع', 'Paid')}</th><th className="p-2 text-start">{label('الحالة', 'Status')}</th></tr></thead>
                  <tbody>
                    {projectDistributions.slice(0, 8).map((distribution) => {
                      const allocationTotal = getDistributionAllocations(distribution, distributionAllocations).reduce((sum, allocation) => sum + allocation.allocated_amount_egp, 0);
                      const paid = getDistributionPaidAmount(distribution.id, projectLedgerEntries);
                      return (
                        <tr key={distribution.id} className="border-b last:border-b-0">
                          <td className="p-2">{distribution.distribution_date}</td>
                          <td className="p-2">{distribution.ownership_as_of_date}</td>
                          <td className="p-2 text-end font-semibold">{formatEgp(allocationTotal || distribution.total_amount_egp)} EGP</td>
                          <td className="p-2 text-end">{formatEgp(Math.max(0, paid))} EGP</td>
                          <td className="p-2">{distribution.status}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        )}
      </section>

      <section id={`project-${project.id}-documents`}>
        <SectionHeader title={label('المستندات', 'Documents')} description={label('الأدلة المرتبطة مباشرة بالمشروع.', 'Evidence linked directly to the project.')} />
        {projectDocuments.length === 0 ? (
          <EmptyState title={label('لا توجد مستندات', 'No documents')} description={label('يمكن إضافة المستند من نفس سياق المشروع.', 'Attach a document from the same project context.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {projectDocuments.map((document) => (
                <div key={document.id} className="flex min-h-11 items-center gap-3 px-4 py-3">
                  <FileText className="h-5 w-5 shrink-0 text-muted-foreground" />
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold">{locale === 'ar' ? document.title_ar : document.title_en || document.title_ar}</p>
                    <p className="text-xs text-muted-foreground">{document.type} · {document.issue_date ?? label('دون تاريخ إصدار', 'No issue date')}</p>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>

      <section id={`project-${project.id}-activity`}>
        <SectionHeader title={label('النشاط التشغيلي', 'Operational activity')} description={label('تسلسل موحد للمعاملات والمستندات والأحداث.', 'A unified timeline of transactions, documents, and events.')} />
        {activity.length === 0 ? (
          <EmptyState title={label('لا يوجد نشاط', 'No activity')} description={label('سيظهر النشاط الحقيقي هنا بعد تسجيله.', 'Recorded activity will appear here.')} />
        ) : (
          <Card>
            <div className="divide-y divide-border">
              {activity.slice(0, 12).map((item) => (
                <div key={item.id} className="flex min-h-11 items-start gap-3 px-4 py-3">
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary" />
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold">{item.label}</p>
                    <p className="text-xs text-muted-foreground">{item.date} · {item.kind}</p>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}
      </section>
    </article>
  );
}

function MetricBox({ label, value, tone = 'neutral' }: { label: string; value: string; tone?: 'neutral' | 'success' | 'warning' | 'danger' }) {
  const toneClass = tone === 'success'
    ? 'text-success'
    : tone === 'warning'
      ? 'text-warning-foreground'
      : tone === 'danger'
        ? 'text-danger'
        : 'text-foreground';
  return (
    <div className="rounded-xl border bg-card p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={`mt-1 font-extrabold ${toneClass}`}>{value}</p>
    </div>
  );
}

function SnapshotCard({
  label,
  value,
  icon: Icon,
}: {
  label: string;
  value: string | number;
  icon: typeof Layers3;
}) {
  return (
    <Card>
      <CardContent>
        <div className="flex items-center justify-between gap-3">
          <p className="text-xs text-muted-foreground">{label}</p>
          <Icon className="h-4 w-4 text-primary" />
        </div>
        <p className="mt-2 break-words text-xl font-extrabold">{value}</p>
      </CardContent>
    </Card>
  );
}

function SectionHeader({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: { label: string; onClick: () => void };
}) {
  return (
    <CardHeader className="mb-3 flex flex-col gap-3 px-0 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h3 className="text-lg font-extrabold">{title}</h3>
        <p className="mt-1 text-sm text-muted-foreground">{description}</p>
      </div>
      {action && (
        <Button variant="secondary" size="sm" onClick={action.onClick}>
          <Plus className="h-4 w-4" /> {action.label}
        </Button>
      )}
    </CardHeader>
  );
}
