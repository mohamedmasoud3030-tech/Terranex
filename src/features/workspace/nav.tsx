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
