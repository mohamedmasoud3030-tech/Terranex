import { AlertTriangle, Building2, FolderKanban, Link2Off, PackageOpen, Users } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { MetricCard } from '../../components/ui/MetricCard';
import type { Asset, Partner, Project, ProjectPartner } from '../../core/types/domain';
import { buildPortfolioOverview } from './model';

interface PortfolioOverviewProps {
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  locale: 'ar' | 'en';
  onOpenEntity: (entity: 'project' | 'asset' | 'partner', id: string) => void;
}

export function PortfolioOverview({
  projects,
  assets,
  partners,
  projectPartners,
  locale,
  onOpenEntity,
}: PortfolioOverviewProps) {
  const overview = buildPortfolioOverview(projects, assets, partners, projectPartners);
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const reason: Record<(typeof overview.attention)[number]['reason'], string> = {
    'on-hold': label('مشروع متوقف مؤقتًا', 'Project on hold'),
    planning: label('مشروع في التخطيط', 'Project in planning'),
    'missing-project': label('أصل يشير إلى مشروع غير موجود', 'Asset references a missing project'),
    'unlinked-equity-partner': label('شريك ملكية غير مربوط بمشروع', 'Equity partner is not linked to a project'),
  };

  return (
    <div className="space-y-5">
      <div className="grid gap-3 min-[360px]:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label={label('المشاريع', 'Projects')}
          value={overview.projectCount}
          hint={`${overview.activeProjectCount} ${label('نشط', 'active')}`}
          icon={FolderKanban}
          tone="primary"
        />
        <MetricCard label={label('الأصول النشطة', 'Active assets')} value={overview.activeAssetCount} icon={PackageOpen} />
        <MetricCard label={label('الشركاء والأطراف', 'Partners & parties')} value={overview.partnerCount} icon={Users} />
        <MetricCard
          label={label('نواقص العلاقات', 'Relationship gaps')}
          value={overview.missingRelationCount}
          icon={Link2Off}
          tone={overview.missingRelationCount > 0 ? 'warning' : 'positive'}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_1.25fr]">
        <Card>
          <CardHeader>
            <h3 className="font-extrabold">{label('توزيع المشاريع حسب القطاع', 'Projects by sector')}</h3>
          </CardHeader>
          <CardContent className="space-y-3">
            {[
              ['real-estate', label('العقاري', 'Real estate')],
              ['agriculture', label('الزراعي', 'Agriculture')],
              ['livestock', label('الحيواني', 'Livestock')],
            ].map(([sector, text]) => (
              <div key={sector} className="flex min-h-11 items-center justify-between rounded-xl border px-3">
                <span className="flex items-center gap-2 text-sm font-semibold">
                  <Building2 className="h-4 w-4 text-primary" />
                  {text}
                </span>
                <strong>{overview.projectBySector[sector as keyof typeof overview.projectBySector]}</strong>
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <h3 className="flex items-center gap-2 font-extrabold">
              <AlertTriangle className="h-5 w-5 text-warning" />
              {label('طابور المتابعة', 'Attention queue')}
            </h3>
          </CardHeader>
          <CardContent>
            {overview.attention.length === 0 ? (
              <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">
                {label('لا توجد حالات تحتاج متابعة من القواعد الحالية.', 'No records need attention under the current rules.')}
              </p>
            ) : (
              <div className="divide-y divide-border">
                {overview.attention.slice(0, 10).map((item) => (
                  <button
                    key={`${item.entity}-${item.id}`}
                    type="button"
                    onClick={() => onOpenEntity(item.entity, item.id)}
                    className="flex min-h-11 w-full items-center justify-between gap-3 py-3 text-start hover:text-primary"
                  >
                    <span className="min-w-0">
                      <span className="block truncate text-sm font-bold">{item.label}</span>
                      <span className="block text-xs text-muted-foreground">{reason[item.reason]}</span>
                    </span>
                    <span className="shrink-0 text-xs font-semibold text-primary">{label('فتح', 'Open')}</span>
                  </button>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
