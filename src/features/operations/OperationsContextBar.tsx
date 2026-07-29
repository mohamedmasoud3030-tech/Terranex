import type { Asset, Project, SectorId } from '../../core/types/domain';
import type { OperationsContext } from './model';

interface OperationsContextBarProps {
  context: OperationsContext;
  projects: Project[];
  assets: Asset[];
  locale: 'ar' | 'en';
  onChange: (context: OperationsContext) => void;
}

const sectorLabels: Record<SectorId | 'all', { ar: string; en: string }> = {
  all: { ar: 'كل القطاعات', en: 'All sectors' },
  'real-estate': { ar: 'العقاري', en: 'Real estate' },
  agriculture: { ar: 'الزراعي', en: 'Agriculture' },
  livestock: { ar: 'الحيواني', en: 'Livestock' },
};

export function OperationsContextBar({
  context,
  projects,
  assets,
  locale,
  onChange,
}: OperationsContextBarProps) {
  const scopedProjects = context.sector === 'all'
    ? projects
    : projects.filter((project) => project.sector_id === context.sector);
  const scopedAssets = assets.filter((asset) =>
    (context.sector === 'all' || asset.sector_id === context.sector)
    && (!context.projectId || asset.project_id === context.projectId),
  );
  return (
    <div className="grid gap-3 rounded-2xl border bg-muted/20 p-3 md:grid-cols-3" aria-label={locale === 'ar' ? 'سياق العمليات' : 'Operations context'}>
      <label className="text-xs font-semibold">
        <span className="mb-1 block">{locale === 'ar' ? 'القطاع' : 'Sector'}</span>
        <select
          value={context.sector}
          onChange={(event) => onChange({ sector: event.target.value as SectorId | 'all' })}
          className="min-h-11 w-full rounded-xl border bg-card px-3"
        >
          {(Object.keys(sectorLabels) as Array<SectorId | 'all'>).map((sector) => (
            <option key={sector} value={sector}>{sectorLabels[sector][locale]}</option>
          ))}
        </select>
      </label>
      <label className="text-xs font-semibold">
        <span className="mb-1 block">{locale === 'ar' ? 'المشروع' : 'Project'}</span>
        <select
          value={context.projectId ?? ''}
          onChange={(event) => onChange({
            sector: context.sector,
            projectId: event.target.value || undefined,
          })}
          className="min-h-11 w-full rounded-xl border bg-card px-3"
        >
          <option value="">{locale === 'ar' ? 'كل المشاريع' : 'All projects'}</option>
          {scopedProjects.map((project) => (
            <option key={project.id} value={project.id}>{locale === 'ar' ? project.name_ar : project.name_en}</option>
          ))}
        </select>
      </label>
      <label className="text-xs font-semibold">
        <span className="mb-1 block">{locale === 'ar' ? 'الأصل' : 'Asset'}</span>
        <select
          value={context.assetId ?? ''}
          onChange={(event) => onChange({
            ...context,
            assetId: event.target.value || undefined,
          })}
          className="min-h-11 w-full rounded-xl border bg-card px-3"
        >
          <option value="">{locale === 'ar' ? 'كل الأصول' : 'All assets'}</option>
          {scopedAssets.map((asset) => (
            <option key={asset.id} value={asset.id}>{locale === 'ar' ? asset.name_ar : asset.name_en}</option>
          ))}
        </select>
      </label>
    </div>
  );
}
