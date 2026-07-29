import { Building2, FileText, Leaf, PawPrint, ReceiptText } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
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
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';
import type { OperationsHandoff } from './contracts';
import type { OperationsContext } from './model';

interface SectorWorkspaceProps {
  context: OperationsContext;
  projects: Project[];
  assets: Asset[];
  events: OperationalEvent[];
  adjustments: StockAdjustment[];
  transactions: Transaction[];
  documents: Document[];
  obligations: Obligation[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  locale: 'ar' | 'en';
  onContextChange: (context: OperationsContext) => void;
  onHandoff?: (handoff: OperationsHandoff) => void;
}

export function SectorWorkspace(props: SectorWorkspaceProps) {
  const { context, projects, assets, locale } = props;
  const scopedProjects = projects.filter((project) =>
    (context.sector === 'all' || project.sector_id === context.sector)
    && (!context.projectId || project.id === context.projectId),
  );
  if (!scopedProjects.length) {
    return (
      <EmptyState
        title={locale === 'ar' ? 'لا توجد مشاريع في هذا السياق' : 'No projects in this context'}
        description={locale === 'ar' ? 'اختر قطاعًا آخر أو أزل فلتر المشروع.' : 'Choose another sector or clear the project filter.'}
        icon={Building2}
      />
    );
  }
  return (
    <div className="space-y-4">
      {scopedProjects.map((project) => {
        const projectAssets = assets.filter((asset) =>
          asset.project_id === project.id && (!context.assetId || asset.id === context.assetId),
        );
        return (
          <ProjectSectorCard
            key={project.id}
            {...props}
            project={project}
            assets={projectAssets}
          />
        );
      })}
    </div>
  );
}

function ProjectSectorCard({
  project,
  assets,
  events,
  adjustments,
  transactions,
  documents,
  obligations,
  partners,
  projectPartners,
  locale,
  onContextChange,
  onHandoff,
}: SectorWorkspaceProps & { project: Project; assets: Asset[] }) {
  const Icon = project.sector_id === 'real-estate' ? Building2 : project.sector_id === 'agriculture' ? Leaf : PawPrint;
  const projectTransactions = transactions.filter((transaction) => transaction.project_id === project.id);
  const projectDocuments = documents.filter((document) => document.project_id === project.id);
  const projectEvents = events.filter((event) => event.project_id === project.id);
  const profitability = computeProjectProfitability(
    project,
    projectTransactions,
    obligations.filter((obligation) => obligation.project_id === project.id),
    projectPartners.filter((link) => link.project_id === project.id),
    partners,
  );
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <Icon className="mt-1 h-5 w-5 text-primary" />
            <div>
              <h2 className="font-bold">{locale === 'ar' ? project.name_ar : project.name_en}</h2>
              <p className="text-xs text-muted-foreground">{project.sector_id}</p>
            </div>
          </div>
          <Badge tone={project.status === 'active' ? 'positive' : 'neutral'}>{project.status}</Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Metric label={locale === 'ar' ? 'الأصول' : 'Assets'} value={String(assets.length)} />
          <Metric label={locale === 'ar' ? 'المعاملات' : 'Transactions'} value={String(projectTransactions.length)} />
          <Metric label={locale === 'ar' ? 'المستندات' : 'Documents'} value={String(projectDocuments.length)} />
          <Metric label={locale === 'ar' ? 'إجمالي الربح' : 'Gross profit'} value={`${formatEgp(profitability.gross_profit_egp, true)} EGP`} />
        </div>
        {project.sector_id === 'real-estate' ? (
          <div className="rounded-2xl border bg-muted/20 p-4">
            <p className="font-semibold">{locale === 'ar' ? 'تركيب عقاري بلا أحداث مصطنعة' : 'Real-estate composition without invented events'}</p>
            <p className="mt-1 text-sm text-muted-foreground">{locale === 'ar' ? 'يعرض الأصول والمعاملات والمستندات والربحية من المصادر الحالية.' : 'Shows assets, transactions, documents, and profitability from current sources.'}</p>
          </div>
        ) : (
          <>
            {project.sector_id === 'agriculture' && (
              <p className="rounded-2xl border border-info/30 bg-info/5 p-3 text-xs text-muted-foreground">
                {locale === 'ar'
                  ? 'لا يوجد كيان موسم مستقل في النموذج الحالي؛ يعرض هذا السياق الأصول والمحاصيل والأحداث الموجودة فقط.'
                  : 'The current domain has no standalone season entity; this context shows only existing assets, crops, and events.'}
              </p>
            )}
            <div className="grid gap-3 sm:grid-cols-2">
              {assets.map((asset) => {
              const balance = computeAssetLiveQuantity(
                asset.quantity ?? 0,
                events.filter((event) => event.asset_id === asset.id),
                adjustments.filter((adjustment) => adjustment.asset_id === asset.id),
              );
                return (
                  <button
                    key={asset.id}
                    type="button"
                    onClick={() => onContextChange({ sector: asset.sector_id, projectId: project.id, assetId: asset.id })}
                    className="min-h-11 rounded-2xl border p-4 text-start hover:bg-muted"
                  >
                    <strong>{locale === 'ar' ? asset.name_ar : asset.name_en}</strong>
                    <span className="mt-1 block text-xs text-muted-foreground">{asset.type} · {balance.quantity} {asset.unit ?? ''} · {balance.eventCount} {locale === 'ar' ? 'سجل' : 'records'}</span>
                  </button>
                );
              })}
            </div>
          </>
        )}
        <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
          <span className="inline-flex items-center gap-1"><ReceiptText className="h-4 w-4" />{projectTransactions.length}</span>
          <span className="inline-flex items-center gap-1"><FileText className="h-4 w-4" />{projectDocuments.length}</span>
          {project.sector_id !== 'real-estate' && <span>{projectEvents.length} {locale === 'ar' ? 'حدث' : 'events'}</span>}
        </div>
        {onHandoff && assets[0] && (
          <div className="flex flex-wrap gap-2">
            <Button type="button" variant="secondary" onClick={() => onHandoff({
              destination: 'governance',
              intent: 'attach-document',
              projectId: project.id,
              assetId: assets[0].id,
            })}>
              <FileText className="h-4 w-4" />
              {locale === 'ar' ? 'إرفاق مستند' : 'Attach document'}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl border p-3"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 font-bold">{value}</p></div>;
}
