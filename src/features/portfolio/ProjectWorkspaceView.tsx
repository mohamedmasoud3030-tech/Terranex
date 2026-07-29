import {
  BarChart3,
  FilePlus2,
  FileText,
  Layers3,
  Pencil,
  Plus,
  ReceiptText,
  Trash2,
  Users,
} from 'lucide-react';
import type { KeyboardEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import { formatEgp, computeProjectProfitability } from '../../core/lib/profitability';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  Transaction,
} from '../../core/types/domain';
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
  locale: 'ar' | 'en';
  embedded?: boolean;
  onEditProject?: () => void;
  onDeleteProject?: () => void;
  onAddAsset?: () => void;
  onLinkPartner?: () => void;
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
  locale,
  embedded = false,
  onEditProject,
  onDeleteProject,
  onAddAsset,
  onLinkPartner,
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
  const profitability = computeProjectProfitability(
    project,
    projectTransactions,
    projectObligations,
    links,
    partners,
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
        <SnapshotCard label={label('شركاء الملكية', 'Equity partners')} value={links.length} icon={Users} />
        <SnapshotCard label={label('إجمالي الربح', 'Gross profit')} value={`${formatEgp(profitability.gross_profit_egp, true)} EGP`} icon={BarChart3} />
        <SnapshotCard label={label('التعرض النقدي', 'Cash exposure')} value={`${formatEgp(profitability.cash_exposure_egp, true)} EGP`} icon={ReceiptText} />
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
          description={label('العلاقات الفعلية ونسب الملكية من سجل ProjectPartner.', 'Actual ownership relationships from ProjectPartner records.')}
          action={onLinkPartner ? { label: label('ربط شريك', 'Link partner'), onClick: onLinkPartner } : undefined}
        />
        {links.length === 0 ? (
          <EmptyState title={label('لا توجد علاقات ملكية', 'No equity relationships')} description={label('اربط شريك ملكية بالمشروع مع الحفاظ على حد 100%.', 'Link an equity partner while preserving the 100% boundary.')} />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {links.map((link) => {
              const partner = partnerById.get(link.partner_id);
              return (
                <div
                  key={link.id}
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
                        <p className="font-bold">{partner ? (locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar) : label('شريك غير موجود', 'Missing partner')}</p>
                        <strong className="text-primary">{link.equity_pct}%</strong>
                      </div>
                      <p className="mt-2 text-xs text-muted-foreground">{label('ساري من', 'Effective from')} {link.effective_from}</p>
                    </CardContent>
                  </Card>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <section id={`project-${project.id}-finance`}>
        <SectionHeader title={label('الملخص المالي', 'Finance snapshot')} description={label('قراءة من محرك الربحية الحالي دون معادلات مكررة.', 'Read from the existing profitability engine without duplicate formulas.')} />
        <div className="grid gap-3 min-[360px]:grid-cols-2 lg:grid-cols-4">
          <SnapshotCard label={label('الإيرادات', 'Income')} value={`${formatEgp(profitability.total_income_egp, true)} EGP`} icon={ReceiptText} />
          <SnapshotCard label={label('المصروفات', 'Expenses')} value={`${formatEgp(profitability.total_expense_egp, true)} EGP`} icon={ReceiptText} />
          <SnapshotCard label={label('ذمم مدينة', 'Receivables')} value={`${formatEgp(profitability.open_receivables_egp, true)} EGP`} icon={ReceiptText} />
          <SnapshotCard label={label('ذمم دائنة', 'Payables')} value={`${formatEgp(profitability.open_payables_egp, true)} EGP`} icon={ReceiptText} />
        </div>
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
