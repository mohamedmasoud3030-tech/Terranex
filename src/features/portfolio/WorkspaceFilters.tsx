import type {
  AssetStatus,
  AssetType,
  PartnerCategory,
  Project,
  ProjectStatus,
  SectorId,
} from '../../core/types/domain';

const inputClass = 'min-h-11 rounded-xl border bg-card px-3 text-sm';

export function ProjectsFilters({
  query,
  sector,
  status,
  locale,
  onQuery,
  onSector,
  onStatus,
}: {
  query: string;
  sector: SectorId | 'all';
  status: ProjectStatus | 'all';
  locale: 'ar' | 'en';
  onQuery: (value: string) => void;
  onSector: (value: SectorId | 'all') => void;
  onStatus: (value: ProjectStatus | 'all') => void;
}) {
  return (
    <div className="grid gap-2 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-3">
      <input type="search" value={query} onChange={(event) => onQuery(event.target.value)} placeholder={locale === 'ar' ? 'ابحث عن مشروع…' : 'Search projects…'} aria-label={locale === 'ar' ? 'بحث المشاريع' : 'Search projects'} className={inputClass} />
      <select value={sector} onChange={(event) => onSector(event.target.value as SectorId | 'all')} aria-label={locale === 'ar' ? 'تصفية القطاع' : 'Sector filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل القطاعات' : 'All sectors'}</option>
        <option value="real-estate">{locale === 'ar' ? 'عقاري' : 'Real estate'}</option>
        <option value="agriculture">{locale === 'ar' ? 'زراعي' : 'Agriculture'}</option>
        <option value="livestock">{locale === 'ar' ? 'حيواني' : 'Livestock'}</option>
      </select>
      <select value={status} onChange={(event) => onStatus(event.target.value as ProjectStatus | 'all')} aria-label={locale === 'ar' ? 'تصفية حالة المشروع' : 'Project status filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل الحالات' : 'All statuses'}</option>
        {(['planning', 'active', 'on_hold', 'completed', 'cancelled'] as ProjectStatus[]).map((value) => <option key={value} value={value}>{value}</option>)}
      </select>
    </div>
  );
}

export function AssetsFilters({
  query,
  projectId,
  sector,
  type,
  status,
  projects,
  locale,
  onQuery,
  onProject,
  onSector,
  onType,
  onStatus,
}: {
  query: string;
  projectId: string | 'all';
  sector: SectorId | 'all';
  type: AssetType | 'all';
  status: AssetStatus | 'all';
  projects: Project[];
  locale: 'ar' | 'en';
  onQuery: (value: string) => void;
  onProject: (value: string | 'all') => void;
  onSector: (value: SectorId | 'all') => void;
  onType: (value: AssetType | 'all') => void;
  onStatus: (value: AssetStatus | 'all') => void;
}) {
  return (
    <div className="grid gap-2 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2 xl:grid-cols-5">
      <input type="search" value={query} onChange={(event) => onQuery(event.target.value)} placeholder={locale === 'ar' ? 'ابحث عن أصل…' : 'Search assets…'} aria-label={locale === 'ar' ? 'بحث الأصول' : 'Search assets'} className={inputClass} />
      <select value={projectId} onChange={(event) => onProject(event.target.value)} aria-label={locale === 'ar' ? 'تصفية المشروع' : 'Project filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل المشاريع' : 'All projects'}</option>
        {projects.map((project) => <option key={project.id} value={project.id}>{locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}</option>)}
      </select>
      <select value={sector} onChange={(event) => onSector(event.target.value as SectorId | 'all')} aria-label={locale === 'ar' ? 'تصفية القطاع' : 'Sector filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل القطاعات' : 'All sectors'}</option>
        <option value="real-estate">real-estate</option><option value="agriculture">agriculture</option><option value="livestock">livestock</option>
      </select>
      <select value={type} onChange={(event) => onType(event.target.value as AssetType | 'all')} aria-label={locale === 'ar' ? 'تصفية نوع الأصل' : 'Asset type filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل الأنواع' : 'All types'}</option>
        {(['land', 'building', 'farm', 'equipment', 'herd', 'animal_group', 'crop', 'other'] as AssetType[]).map((value) => <option key={value} value={value}>{value}</option>)}
      </select>
      <select value={status} onChange={(event) => onStatus(event.target.value as AssetStatus | 'all')} aria-label={locale === 'ar' ? 'تصفية حالة الأصل' : 'Asset status filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'كل الحالات' : 'All statuses'}</option>
        {(['owned', 'leased', 'sold', 'disposed'] as AssetStatus[]).map((value) => <option key={value} value={value}>{value}</option>)}
      </select>
    </div>
  );
}

export function PartnersFilters({
  query,
  category,
  locale,
  onQuery,
  onCategory,
}: {
  query: string;
  category: PartnerCategory | 'all';
  locale: 'ar' | 'en';
  onQuery: (value: string) => void;
  onCategory: (value: PartnerCategory | 'all') => void;
}) {
  return (
    <div className="grid gap-2 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2">
      <input type="search" value={query} onChange={(event) => onQuery(event.target.value)} placeholder={locale === 'ar' ? 'ابحث عن شريك أو طرف…' : 'Search partners…'} aria-label={locale === 'ar' ? 'بحث الشركاء' : 'Search partners'} className={inputClass} />
      <select value={category} onChange={(event) => onCategory(event.target.value as PartnerCategory | 'all')} aria-label={locale === 'ar' ? 'تصفية نوع الشريك' : 'Partner category filter'} className={inputClass}>
        <option value="all">{locale === 'ar' ? 'الكل' : 'All categories'}</option>
        <option value="equity_partner">{locale === 'ar' ? 'شريك ملكية' : 'Equity partner'}</option>
        <option value="counterparty">{locale === 'ar' ? 'طرف تعامل' : 'Counterparty'}</option>
      </select>
    </div>
  );
}
