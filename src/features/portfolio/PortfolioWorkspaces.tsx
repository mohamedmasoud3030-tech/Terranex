import { Building2, FolderKanban, PackageOpen, PawPrint, UserRound, Users, Wheat } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
import { Card, CardContent } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/States';
import { computeProjectProfitability, formatEgp } from '../../core/lib/profitability';
import { queryObligationAging } from '../finance/obligationQueries';
import type {
  Asset,
  AssetStatus,
  AssetType,
  Obligation,
  Partner,
  PartnerCategory,
  Project,
  ProjectPartner,
  ProjectStatus,
  SectorId,
  Transaction,
} from '../../core/types/domain';
import { filterAssets, filterPartners, filterProjects } from './model';
import { AssetsFilters, PartnersFilters, ProjectsFilters } from './WorkspaceFilters';

const SECTOR_ICON = {
  'real-estate': Building2,
  agriculture: Wheat,
  livestock: PawPrint,
};

export function ProjectsWorkspace({
  projects,
  transactions,
  obligations,
  projectPartners,
  partners,
  locale,
  query,
  sector,
  status,
  onQuery,
  onSector,
  onStatus,
  onInspect,
  onOpenWorkspace,
}: {
  projects: Project[];
  transactions: Transaction[];
  obligations: Obligation[];
  projectPartners: ProjectPartner[];
  partners: Partner[];
  locale: 'ar' | 'en';
  query: string;
  sector: SectorId | 'all';
  status: ProjectStatus | 'all';
  onQuery: (value: string) => void;
  onSector: (value: SectorId | 'all') => void;
  onStatus: (value: ProjectStatus | 'all') => void;
  onInspect: (project: Project) => void;
  onOpenWorkspace: (project: Project) => void;
}) {
  const filtered = filterProjects(projects, { query, sector, status });
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;

  return (
    <div className="space-y-4">
      <ProjectsFilters {...{ query, sector, status, locale, onQuery, onSector, onStatus }} />
      {filtered.length === 0 ? (
        <EmptyState title={label('لا توجد مشاريع مطابقة', 'No matching projects')} description={label('غيّر عوامل التصفية أو أنشئ مشروعًا جديدًا.', 'Adjust filters or create a new project.')} icon={FolderKanban} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((project) => {
            const Icon = SECTOR_ICON[project.sector_id];
            const profitability = computeProjectProfitability(
              project,
              transactions.filter((transaction) => transaction.project_id === project.id),
              obligations.filter((obligation) => obligation.project_id === project.id),
              projectPartners.filter((link) => link.project_id === project.id),
              partners,
            );
            return (
              <Card key={project.id} className="flex h-full flex-col">
                <CardContent className="flex h-full flex-col">
                  <div className="flex items-start justify-between gap-3">
                    <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
                      <Icon className="h-5 w-5" />
                    </span>
                    <Badge tone={project.status === 'active' ? 'positive' : project.status === 'on_hold' ? 'warning' : 'neutral'}>{project.status}</Badge>
                  </div>
                  <h3 className="mt-4 font-extrabold">{locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}</h3>
                  <p className="mt-1 text-xs text-muted-foreground">{project.sector_id} · {project.start_date}</p>
                  <div className="mt-4 rounded-xl border bg-muted/30 p-3">
                    <p className="text-xs text-muted-foreground">{label('إجمالي الربح', 'Gross profit')}</p>
                    <p className={`mt-1 font-extrabold ${profitability.gross_profit_egp >= 0 ? 'text-success' : 'text-danger'}`}>
                      {formatEgp(profitability.gross_profit_egp, true)} EGP
                    </p>
                  </div>
                  <div className="mt-auto grid grid-cols-2 gap-2 pt-4">
                    <button type="button" onClick={() => onInspect(project)} className="min-h-11 rounded-xl border text-sm font-semibold hover:bg-muted">
                      {label('عرض سريع', 'Quick view')}
                    </button>
                    <button type="button" onClick={() => onOpenWorkspace(project)} className="min-h-11 rounded-xl bg-primary px-3 text-sm font-semibold text-primary-foreground">
                      {label('مساحة المشروع', 'Project workspace')}
                    </button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function AssetsWorkspace({
  assets,
  projects,
  locale,
  query,
  projectId,
  sector,
  type,
  status,
  onQuery,
  onProject,
  onSector,
  onType,
  onStatus,
  onInspect,
}: {
  assets: Asset[];
  projects: Project[];
  locale: 'ar' | 'en';
  query: string;
  projectId: string | 'all';
  sector: SectorId | 'all';
  type: AssetType | 'all';
  status: AssetStatus | 'all';
  onQuery: (value: string) => void;
  onProject: (value: string | 'all') => void;
  onSector: (value: SectorId | 'all') => void;
  onType: (value: AssetType | 'all') => void;
  onStatus: (value: AssetStatus | 'all') => void;
  onInspect: (asset: Asset) => void;
}) {
  const filtered = filterAssets(assets, { query, projectId, sector, type, status });
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  return (
    <div className="space-y-4">
      <AssetsFilters {...{ query, projectId, sector, type, status, projects, locale, onQuery, onProject, onSector, onType, onStatus }} />
      {filtered.length === 0 ? (
        <EmptyState title={label('لا توجد أصول مطابقة', 'No matching assets')} description={label('غيّر عوامل التصفية أو أنشئ أصلًا داخل مشروع.', 'Adjust filters or create an asset inside a project.')} icon={PackageOpen} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((asset) => {
            const project = projectById.get(asset.project_id);
            return (
              <button key={asset.id} type="button" onClick={() => onInspect(asset)} className="min-h-11 rounded-2xl text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary">
                <Card className="h-full hover:border-primary/40">
                  <CardContent>
                    <div className="flex items-start justify-between gap-3">
                      <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary"><PackageOpen className="h-5 w-5" /></span>
                      <Badge tone={asset.status === 'owned' ? 'positive' : asset.status === 'sold' ? 'warning' : 'neutral'}>{asset.status}</Badge>
                    </div>
                    <h3 className="mt-4 font-extrabold">{locale === 'ar' ? asset.name_ar : asset.name_en || asset.name_ar}</h3>
                    <p className="mt-1 text-xs text-muted-foreground">{project ? (locale === 'ar' ? project.name_ar : project.name_en || project.name_ar) : label('مشروع غير موجود', 'Missing project')}</p>
                    <p className="mt-3 font-bold text-primary">{formatEgp(asset.current_value_egp ?? asset.acquisition_cost_egp, true)} EGP</p>
                    {asset.quantity != null && <p className="mt-1 text-xs text-muted-foreground">{asset.quantity} {asset.unit ?? ''}</p>}
                  </CardContent>
                </Card>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function PartnersWorkspace({
  partners,
  obligations,
  projectPartners,
  locale,
  query,
  category,
  onQuery,
  onCategory,
  onInspect,
  onOpenWorkspace,
}: {
  partners: Partner[];
  obligations: Obligation[];
  projectPartners: ProjectPartner[];
  locale: 'ar' | 'en';
  query: string;
  category: PartnerCategory | 'all';
  onQuery: (value: string) => void;
  onCategory: (value: PartnerCategory | 'all') => void;
  onInspect: (partner: Partner) => void;
  onOpenWorkspace: (partner: Partner) => void;
}) {
  const filtered = filterPartners(partners, { query, category });
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  return (
    <div className="space-y-4">
      <PartnersFilters {...{ query, category, locale, onQuery, onCategory }} />
      {filtered.length === 0 ? (
        <EmptyState title={label('لا توجد نتائج', 'No matching partners')} description={label('غيّر البحث أو أضف شريكًا أو طرف تعامل.', 'Adjust search or add a partner or counterparty.')} icon={Users} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {filtered.map((partner) => {
            const exposure = queryObligationAging(obligations, {
              as_of: new Date().toISOString().slice(0, 10),
              partner_id: partner.id,
            }).totals;
            const receivable = exposure.receivable_egp;
            const payable = exposure.payable_egp;
            const linkedProjects = projectPartners.filter((link) => link.partner_id === partner.id).length;
            const Icon = partner.category === 'equity_partner' ? Users : UserRound;
            return (
              <Card key={partner.id} className="h-full hover:border-primary/40">
                  <CardContent>
                    <div className="flex items-start justify-between gap-3">
                      <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary"><Icon className="h-5 w-5" /></span>
                      <Badge tone={partner.category === 'equity_partner' ? 'info' : 'neutral'}>
                        {partner.category === 'equity_partner' ? label('ملكية', 'Equity') : label('طرف تعامل', 'Counterparty')}
                      </Badge>
                    </div>
                    <h3 className="mt-4 font-extrabold">{locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar}</h3>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {partner.category === 'equity_partner'
                        ? `${linkedProjects} ${label('مشروع مرتبط', 'linked projects')}`
                        : partner.counterparty_role}
                    </p>
                    <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                      <span className="rounded-xl bg-success/10 p-2 text-success">{label('لنا', 'Receivable')} {formatEgp(receivable, true)}</span>
                      <span className="rounded-xl bg-danger/10 p-2 text-danger">{label('علينا', 'Payable')} {formatEgp(payable, true)}</span>
                    </div>
                    <div className="mt-4 grid grid-cols-2 gap-2">
                      <button type="button" onClick={() => onInspect(partner)} className="min-h-11 rounded-xl border text-sm font-semibold hover:bg-muted">
                        {label('عرض سريع', 'Quick view')}
                      </button>
                      <button type="button" onClick={() => onOpenWorkspace(partner)} className="min-h-11 rounded-xl bg-primary px-3 text-sm font-semibold text-primary-foreground">
                        {label('مساحة الشريك', 'Partner workspace')}
                      </button>
                    </div>
                  </CardContent>
                </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
