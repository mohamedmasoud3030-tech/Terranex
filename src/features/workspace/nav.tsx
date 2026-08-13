import Link from 'next/link';

/**
 * The coherent business-facing project workspace navigation.
 *
 * These nine sections are the operator's mental model for one Real Estate
 * project. Internal implementation labels are never exposed here; each section
 * links to the canonical operator page for that business concern. The detailed
 * workhorse pages (terms, funding, operations, costs, cash, close, investors,
 * pilot) remain the execution surface behind these business labels.
 */

export type WorkspaceSection =
  | 'overview'
  | 'capital'
  | 'property'
  | 'costs-cash'
  | 'revenue'
  | 'close'
  | 'statements'
  | 'opening'
  | 'controls';

export const WORKSPACE_SECTIONS: Array<{
  id: WorkspaceSection;
  label: string;
  description: string;
  href: (projectId: string) => string;
}> = [
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

export function WorkspaceNav({
  projectId,
  active,
}: {
  projectId: string;
  active: WorkspaceSection;
}) {
  return (
    <nav className="workspace-nav" aria-label="مساحة عمل المشروع">
      {WORKSPACE_SECTIONS.map((section) => {
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
