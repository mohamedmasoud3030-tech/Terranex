import Link from 'next/link';

/**
 * The coherent business-facing project workspace navigation.
 * Sector operations keep their own authoritative roots. Shared project
 * concerns are linked once for every sector. Investor-economics controls are
 * intentionally not navigation targets while BD-003/004/006/008 remain OPEN.
 */

export type WorkspaceSector = 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';

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
  | 'budget'
  | 'integrity'
  | 'governance'
  | 'agriculture'
  | 'land-assets'
  | 'field-activities'
  | 'field-inputs'
  | 'harvest-inventory'
  | 'agriculture-sales'
  | 'agriculture-results'
  | 'livestock'
  | 'livestock-operations'
  | 'procurement';

type SectionDef = {
  id: WorkspaceSection;
  label: string;
  description: string;
  href: (projectId: string) => string;
};

const REAL_ESTATE_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'overview', label: 'نظرة عامة', description: 'الوضع المالي والتشغيلي للمشروع من المصادر الرسمية', href: (p) => `/projects/${p}/overview` },
  { id: 'capital', label: 'رأس المال', description: 'وقائع الالتزامات والمساهمات المسجلة دون استنتاج ملكية أو حصة ربح', href: (p) => `/projects/${p}/funding` },
  { id: 'property', label: 'الأصول العقارية', description: 'الأصول، السيطرة، التطوير، دورة حياة العقار', href: (p) => `/projects/${p}/operations` },
  { id: 'costs-cash', label: 'التكاليف والنقدية', description: 'الالتزامات، المدفوعات، النقدية ومطابقة البنك', href: (p) => `/projects/${p}/costs` },
  { id: 'revenue', label: 'الإيراد والبيع', description: 'التصرف، اعتراف البيع، التحصيل والنتيجة المحققة', href: (p) => `/projects/${p}/revenue` },
  { id: 'close', label: 'الإغلاق المالي', description: 'الفترات، بوابات الإغلاق، اللقطات والتصحيحات', href: (p) => `/projects/${p}/close` },
  { id: 'statements', label: 'شفافية المشاركين', description: 'هوية المشاركين والنسخة الاتفاقية؛ الاستحقاقات محجوبة حتى R14', href: (p) => `/projects/${p}/investors` },
  { id: 'opening', label: 'الاستيراد والمطابقة', description: 'الأرصدة الافتتاحية، مجاميع الرقابة، مطابقة المصدر', href: (p) => `/projects/${p}/pilot` },
  { id: 'controls', label: 'الرقابة والجاهزية', description: 'الرقابة الداخلية، الوصول، والجاهزية للبيانات الحقيقية', href: (p) => `/projects/${p}/controls` },
];

const LIVESTOCK_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'livestock', label: 'المواقع والقطعان', description: 'مواقع التشغيل، القطعان الإدارية، والدفعات القابلة للعد', href: (p) => `/projects/${p}/livestock` },
  { id: 'livestock-operations', label: 'العمليات الحيوانية', description: 'الصحة والتكاثر والهوية والتغذية وقياسات التشغيل', href: (p) => `/projects/${p}/livestock/operations` },
];

const PROCUREMENT_SECTION: SectionDef = {
  id: 'procurement',
  label: 'المشتريات',
  description: 'الموردون المشتركون، طلبات الشراء وأوامر الشراء',
  href: (p) => `/projects/${p}/procurement`,
};

const FINANCE_CONTROL_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'budget', label: 'الموازنة', description: 'نسخ الموازنة، بنود السقوف، الاستهلاك والمراجعات', href: (p) => `/projects/${p}/budget` },
  { id: 'integrity', label: 'مركز النزاهة', description: 'إشارات الرقابة المالية، الاستثناءات وسياسات الاعتماد', href: (p) => `/projects/${p}/integrity` },
];

const GOVERNANCE_SECTION: SectionDef = {
  id: 'governance',
  label: 'المخاطر والقرارات',
  description: 'مخاطر المشروع وسجل القرارات الموثق دون تغيير الحقائق المالية',
  href: (p) => `/projects/${p}/governance`,
};

const AGRICULTURE_SECTIONS: ReadonlyArray<SectionDef> = [
  { id: 'agriculture', label: 'المزرعة والمحاصيل', description: 'المزارع، الحقول، دورات المحصول، ودورة حياة الدورة', href: (p) => `/projects/${p}/agriculture` },
  { id: 'land-assets', label: 'الأراضي والأصول', description: 'أصل الأرض، أساس السيطرة، العقد، والطرف المقابل وربط المزرعة', href: (p) => `/projects/${p}/agriculture#land-assets` },
  { id: 'field-activities', label: 'أنشطة الحقل', description: 'تسجيل ما حدث في الحقل على تخصيص دورة قائم', href: (p) => `/projects/${p}/agriculture#activities` },
  { id: 'field-inputs', label: 'المدخلات والتطبيقات', description: 'المدخلات وتشغيلاتها وتطبيقها الفعلي على نشاط حقل قائم', href: (p) => `/projects/${p}/agriculture#inputs` },
  { id: 'harvest-inventory', label: 'الحصاد والمخزون', description: 'أحداث الحصاد، تشغيلات المحصول، مواقع التخزين، وحركات المخزون', href: (p) => `/projects/${p}/agriculture#harvest` },
  { id: 'agriculture-sales', label: 'المبيعات والتحصيل', description: 'المشتري، صرف البيع، الإيراد، الذمم والتحصيلات', href: (p) => `/projects/${p}/agriculture#sales` },
  { id: 'agriculture-results', label: 'النتائج والإغلاق', description: 'نتيجة الدورة، تكلفة التشغيل، المراكز المفتوحة والإغلاق الآمن', href: (p) => `/projects/${p}/agriculture#results-closeout` },
];

export const REAL_ESTATE_SECTION_IDS = [
  ...REAL_ESTATE_SECTIONS.map((s) => s.id),
  PROCUREMENT_SECTION.id,
  ...FINANCE_CONTROL_SECTIONS.map((s) => s.id),
  GOVERNANCE_SECTION.id,
];
export const AGRICULTURE_SECTION_IDS = [
  ...AGRICULTURE_SECTIONS.map((s) => s.id),
  PROCUREMENT_SECTION.id,
  ...FINANCE_CONTROL_SECTIONS.map((s) => s.id),
  GOVERNANCE_SECTION.id,
];
export const LIVESTOCK_SECTION_IDS = [
  ...LIVESTOCK_SECTIONS.map((s) => s.id),
  PROCUREMENT_SECTION.id,
  ...FINANCE_CONTROL_SECTIONS.map((s) => s.id),
  GOVERNANCE_SECTION.id,
];

/**
 * Explicit group membership per sector.
 *
 * Membership is declared, never derived by exclusion: `sectionsFor` returns
 * the sector's finance sections *inside* its own list, so "everything not
 * claimed by another group" would put all of them in the sector group and
 * duplicate them elsewhere. Each id below appears in exactly one group.
 *
 * Grouping is a presentation of `sectionsFor()`. `sectionGroupsFor` asserts
 * that invariant at runtime and returns the canonical section objects, so a
 * group can never change a label, an href, or which sections a sector may
 * reach. Guarded by tests/workspace-nav-grouping.test.ts.
 */
type GroupSpec = { id: string; label: string; members: ReadonlyArray<WorkspaceSection> };

const GROUP_SPECS: ReadonlyArray<GroupSpec> = [
  {
    id: 'overview',
    label: 'نظرة عامة',
    members: ['overview'],
  },
  {
    id: 'sector',
    label: 'التشغيل',
    members: [
      'property',
      'agriculture',
      'land-assets',
      'field-activities',
      'field-inputs',
      'harvest-inventory',
      'agriculture-sales',
      'agriculture-results',
      'livestock',
      'livestock-operations',
    ],
  },
  {
    id: 'money',
    label: 'المال',
    members: ['capital', 'costs-cash', 'revenue', 'close'],
  },
  {
    id: 'transparency',
    label: 'الشفافية والاستيراد',
    members: ['statements', 'opening'],
  },
  {
    id: 'control',
    label: 'الرقابة والحوكمة',
    members: ['controls', 'procurement', 'budget', 'integrity', 'governance'],
  },
];

const GROUP_LABEL_OVERRIDE: Record<WorkspaceSector, Record<string, string>> = {
  REAL_ESTATE: { overview: 'نظرة عامة', sector: 'الأصول العقارية' },
  AGRICULTURE: { sector: 'مساحة الزراعة' },
  LIVESTOCK: { sector: 'مساحة الثروة الحيوانية' },
};

export type WorkspaceSectionGroup = {
  id: string;
  label: string;
  sections: ReadonlyArray<SectionDef>;
};

export function sectionGroupsFor(sector: WorkspaceSector): ReadonlyArray<WorkspaceSectionGroup> {
  const allowed = sectionsFor(sector);
  const resolve = (id: WorkspaceSection) => allowed.find((section) => section.id === id);

  return GROUP_SPECS.map((spec) => ({
    id: spec.id,
    label: GROUP_LABEL_OVERRIDE[sector][spec.id] ?? spec.label,
    sections: spec.members
      .map(resolve)
      .filter((section): section is SectionDef => Boolean(section)),
  })).filter((group) => group.sections.length > 0);
}

/** Every section must be claimed by exactly one group, for every sector. A
 * section in two groups renders twice; in none, it disappears. */
export function assertSectionGroupingIsExact(sector: WorkspaceSector): void {
  const allowed = sectionsFor(sector).map((section) => section.id);
  const grouped = sectionGroupsFor(sector).flatMap((group) =>
    group.sections.map((section) => section.id),
  );
  const missing = allowed.filter((id) => !grouped.includes(id));
  const duplicated = grouped.filter((id, index) => grouped.indexOf(id) !== index);
  const invented = grouped.filter((id) => !allowed.includes(id));
  if (missing.length || duplicated.length || invented.length) {
    throw new Error(
      `workspace nav grouping is not exact for ${sector}: ` +
        `missing=${missing.join(',') || '-'} ` +
        `duplicated=${duplicated.join(',') || '-'} ` +
        `invented=${invented.join(',') || '-'}`,
    );
  }
}

export function sectionsFor(sector: WorkspaceSector): ReadonlyArray<SectionDef> {
  const shared = [PROCUREMENT_SECTION, ...FINANCE_CONTROL_SECTIONS, GOVERNANCE_SECTION];
  if (sector === 'AGRICULTURE') return [...AGRICULTURE_SECTIONS, ...shared];
  if (sector === 'LIVESTOCK') return [...LIVESTOCK_SECTIONS, ...shared];
  return [...REAL_ESTATE_SECTIONS, ...shared];
}

export function sectionHref(section: WorkspaceSection, projectId: string): string {
  const def = [
    ...REAL_ESTATE_SECTIONS,
    ...AGRICULTURE_SECTIONS,
    ...LIVESTOCK_SECTIONS,
    PROCUREMENT_SECTION,
    ...FINANCE_CONTROL_SECTIONS,
    GOVERNANCE_SECTION,
  ].find((s) => s.id === section);
  return def ? def.href(projectId) : `/projects/${projectId}`;
}

export function sectorLandingHref(sector: WorkspaceSector, projectId: string): string {
  if (sector === 'AGRICULTURE') return `/projects/${projectId}/agriculture`;
  if (sector === 'LIVESTOCK') return `/projects/${projectId}/livestock`;
  return `/projects/${projectId}/operations`;
}

/**
 * Grouped workspace navigation. Each group is its own scrollable strip with a
 * visible name, so the operator can locate a section by concern (sector work,
 * money, transparency, control) instead of scanning one undifferentiated row.
 * Falls back to the flat strip when a section is active but ungrouped.
 */
export function WorkspaceNavGrouped({
  projectId,
  active,
  sector,
}: {
  projectId: string;
  active: WorkspaceSection;
  sector: WorkspaceSector;
}) {
  const groups = sectionGroupsFor(sector);
  return (
    <div className="workspace-nav-grouped">
      {groups.map((group) => (
        <nav key={group.id} className="workspace-nav-group" aria-label={group.label}>
          <span className="workspace-nav-group-label">{group.label}</span>
          <div className="workspace-nav tab-strip">
            {group.sections.map((section) => {
              const current = section.id === active;
              return (
                <Link
                  key={section.id}
                  href={section.href(projectId)}
                  aria-current={current ? 'page' : undefined}
                  title={section.description}
                  className={current ? 'workspace-nav-item current' : 'workspace-nav-item'}
                >
                  <strong>{section.label}</strong>
                  <span>{section.description}</span>
                </Link>
              );
            })}
          </div>
        </nav>
      ))}
    </div>
  );
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
    <nav className="workspace-nav tab-strip" aria-label="مساحة عمل المشروع">
      {sections.map((section) => {
        const current = section.id === active;
        return (
          <Link
            key={section.id}
            href={section.href(projectId)}
            aria-current={current ? 'page' : undefined}
            title={section.description}
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
