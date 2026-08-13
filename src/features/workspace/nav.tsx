import Link from 'next/link';

/**
 * The coherent business-facing project workspace navigation.
 *
 * Real Estate projects keep their nine business sections exactly as GF-010
 * shipped them. Agriculture projects use a single, truthful entry that
 * leads to the Agriculture sector workspace at /projects/[id]/agriculture.
 * Internal implementation labels are never exposed here; each section
 * links to the canonical operator page for that business concern.
 *
 * The Agriculture entry is intentional: per ADR 0012 / GF-013 the first
 * bounded agriculture foundation only ships Farm → Field → CropCycle;
 * later bounded agriculture batches will add more sections when the
 * corresponding workflow is implemented and tested. Scaffolding a full
 * multi-section agriculture workspace before the underlying commands
 * exist would fabricate KPIs and would not be honest with the operator.
 */

export type WorkspaceSector = 'REAL_ESTATE' | 'AGRICULTURE';

export type WorkspaceSection =
  | 'overview'
  | 'capital'
  | 'property'
  | 'costs-cash'
  | 'revenue'
  | 'close'
  | 'statements'
  | 'opening'
  | 'controls'
  | 'agriculture';

type SectionDef = {
  id: WorkspaceSection;
  label: string;
  description: string;
  href: (projectId: string) => string;
};

const REAL_ESTATE_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'overview', label: 'نظرة عامة', description: 'الوضع المالي والتشغيلي للمشروع من المصادر الرسمية', href: (p) => `/projects/${p}/overview` },
  { id: 'capital', label: 'رأس المال', description: 'الالتزامات، طلبات رأس المال، المساهمات والموقف الرأسمالي', href: (p) => `/projects/${p}/funding` },
  { id: 'property', label: 'الأصول العقارية', description: 'الأصول، السيطرة، التطوير، دورة حياة العقار', href: (p) => `/projects/${p}/operations` },
  { id: 'costs-cash', label: 'التكاليف والنقدية', description: 'الالتزامات، المدفوعات، النقدية ومطابقة البنك', href: (p) => `/projects/${p}/costs` },
  { id: 'revenue', label: 'الإيراد والبيع', description: 'التصرف، اعتراف البيع، التحصيل والنتيجة المحققة', href: (p) => `/projects/${p}/revenue` },
  { id: 'close', label: 'الإغلاق والتوزيع', description: 'الفترات، بوابات الإغلاق، التخصيص والتوزيعات', href: (p) => `/projects/${p}/close` },
  { id: 'statements', label: 'كشوف الشركاء', description: 'رأس المال الافتتاحي، المساهمات، التخصيصات، التوزيعات', href: (p) => `/projects/${p}/statements` },
  { id: 'opening', label: 'الاستيراد والمطابقة', description: 'الأرصدة الافتتاحية، مجاميع الرقابة، مطابقة المصدر', href: (p) => `/projects/${p}/pilot` },
  { id: 'controls', label: 'الرقابة والجاهزية', description: 'الرقابة الداخلية، الوصول، والجاهزية للبيانات الحقيقية', href: (p) => `/projects/${p}/controls` },
];

const AGRICULTURE_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'agriculture', label: 'المزرعة والمحاصيل', description: 'المزارع، الحقول، دورات المحصول، ودورة حياة الدورة', href: (p) => `/projects/${p}/agriculture` },
];

export const REAL_ESTATE_SECTION_IDS = REAL_ESTATE_SECTIONS.map((s) => s.id);
export const AGRICULTURE_SECTION_IDS = AGRICULTURE_SECTIONS.map((s) => s.id);

export function sectionsFor(sector: WorkspaceSector): ReadonlyArray<SectionDef> {
  return sector === 'AGRICULTURE' ? AGRICULTURE_SECTIONS : REAL_ESTATE_SECTIONS;
}

export function sectionHref(section: WorkspaceSection, projectId: string): string {
  const def = [...REAL_ESTATE_SECTIONS, ...AGRICULTURE_SECTIONS].find((s) => s.id === section);
  return def ? def.href(projectId) : `/projects/${projectId}`;
}

export function sectorLandingHref(sector: WorkspaceSector, projectId: string): string {
  if (sector === 'AGRICULTURE') return `/projects/${projectId}/agriculture`;
  return `/projects/${projectId}/operations`;
}

export function WorkspaceNav({
  projectId,
  active,
  sector,
}: {
  projectId: string;
  active: WorkspaceSection;
  sector: WorkspaceSector;
}) {
  const sections = sectionsFor(sector);
  return (
    <nav className="workspace-nav" aria-label="مساحة عمل المشروع">
      {sections.map((section) => {
        const current = section.id === active;
        return (
          <Link
            key={section.id}
            href={section.href(projectId)}
            aria-current={current ? 'page' : undefined}
            className={current ? 'workspace-nav-item current' : 'workspace-nav-item'}
          >
            <strong>{section.label}</strong>
            <span>{section.description}</span>
          </Link>
        );
      })}
    </nav>
  );
}
