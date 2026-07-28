import type {
  Asset,
  AssetStatus,
  AssetType,
  Partner,
  PartnerCategory,
  Project,
  ProjectPartner,
  ProjectStatus,
  SectorId,
} from '../../core/types/domain';

export interface ProjectFilters {
  query?: string;
  sector?: SectorId | 'all';
  status?: ProjectStatus | 'all';
}

export interface AssetFilters {
  query?: string;
  projectId?: string | 'all';
  sector?: SectorId | 'all';
  type?: AssetType | 'all';
  status?: AssetStatus | 'all';
}

export interface PartnerFilters {
  query?: string;
  category?: PartnerCategory | 'all';
}

function normalize(value: string) {
  return value.trim().toLocaleLowerCase();
}

export function filterProjects(projects: Project[], filters: ProjectFilters) {
  const query = normalize(filters.query ?? '');
  return projects.filter((project) => {
    if (filters.sector && filters.sector !== 'all' && project.sector_id !== filters.sector) return false;
    if (filters.status && filters.status !== 'all' && project.status !== filters.status) return false;
    if (!query) return true;
    return [project.name_ar, project.name_en, project.description_ar, project.description_en]
      .filter(Boolean)
      .some((value) => normalize(value as string).includes(query));
  });
}

export function filterAssets(assets: Asset[], filters: AssetFilters) {
  const query = normalize(filters.query ?? '');
  return assets.filter((asset) => {
    if (filters.projectId && filters.projectId !== 'all' && asset.project_id !== filters.projectId) return false;
    if (filters.sector && filters.sector !== 'all' && asset.sector_id !== filters.sector) return false;
    if (filters.type && filters.type !== 'all' && asset.type !== filters.type) return false;
    if (filters.status && filters.status !== 'all' && asset.status !== filters.status) return false;
    if (!query) return true;
    return [asset.name_ar, asset.name_en, asset.notes]
      .filter(Boolean)
      .some((value) => normalize(value as string).includes(query));
  });
}

export function filterPartners(partners: Partner[], filters: PartnerFilters) {
  const query = normalize(filters.query ?? '');
  return partners.filter((partner) => {
    if (filters.category && filters.category !== 'all' && partner.category !== filters.category) return false;
    if (!query) return true;
    return [partner.name_ar, partner.name_en, partner.phone, partner.email, partner.address]
      .filter(Boolean)
      .some((value) => normalize(value as string).includes(query));
  });
}

export function validateEquityAddition(
  links: ProjectPartner[],
  projectId: string,
  percentage: number,
) {
  const allocated = links
    .filter((link) => link.project_id === projectId && !link.effective_to)
    .reduce((total, link) => total + link.equity_pct, 0);
  const remaining = Math.max(0, 100 - allocated);
  return {
    allocated,
    remaining,
    valid: Number.isFinite(percentage) && percentage > 0 && percentage <= remaining + Number.EPSILON,
  };
}

export interface PortfolioAttentionItem {
  id: string;
  entity: 'project' | 'asset' | 'partner';
  label: string;
  reason: 'on-hold' | 'planning' | 'missing-project' | 'unlinked-equity-partner';
}

export function buildPortfolioOverview(
  projects: Project[],
  assets: Asset[],
  partners: Partner[],
  projectPartners: ProjectPartner[],
) {
  const projectIds = new Set(projects.map((project) => project.id));
  const linkedPartnerIds = new Set(projectPartners.map((link) => link.partner_id));
  const projectBySector = projects.reduce<Record<SectorId, number>>(
    (counts, project) => ({ ...counts, [project.sector_id]: counts[project.sector_id] + 1 }),
    { 'real-estate': 0, agriculture: 0, livestock: 0 },
  );
  const attention: PortfolioAttentionItem[] = [
    ...projects
      .filter((project) => project.status === 'on_hold' || project.status === 'planning')
      .map((project) => ({
        id: project.id,
        entity: 'project' as const,
        label: project.name_ar,
        reason: project.status === 'on_hold' ? 'on-hold' as const : 'planning' as const,
      })),
    ...assets
      .filter((asset) => !projectIds.has(asset.project_id))
      .map((asset) => ({
        id: asset.id,
        entity: 'asset' as const,
        label: asset.name_ar,
        reason: 'missing-project' as const,
      })),
    ...partners
      .filter((partner) => partner.category === 'equity_partner' && !linkedPartnerIds.has(partner.id))
      .map((partner) => ({
        id: partner.id,
        entity: 'partner' as const,
        label: partner.name_ar,
        reason: 'unlinked-equity-partner' as const,
      })),
  ];

  return {
    projectCount: projects.length,
    activeProjectCount: projects.filter((project) => project.status === 'active').length,
    projectBySector,
    activeAssetCount: assets.filter((asset) => asset.status === 'owned' || asset.status === 'leased').length,
    partnerCount: partners.length,
    missingRelationCount: attention.filter(
      (item) => item.reason === 'missing-project' || item.reason === 'unlinked-equity-partner',
    ).length,
    attention,
  };
}
