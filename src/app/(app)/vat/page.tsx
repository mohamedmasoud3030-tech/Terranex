import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getTaxRegistry } from '@/features/control/queries';
import { TaxRegistryTable } from '@/features/control/tax-registry-table';
import { PlainIntro } from '@/features/plain-language/plain-intro';

export const dynamic = 'force-dynamic';

/**
 * الضريبة: سجل المعالجات الضريبية للمنظمة، قراءة فقط.
 * النظام لا يحسب إقرار ضريبة القيمة المضافة ولا يملك أسعارًا أو مبالغ ضريبية، لذلك لا نعرض أي رقم ضريبي.
 */
export default async function VatPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="سجل الضرائب يظهر بعد إنشاء المنظمة."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const rows = await getTaxRegistry(org.id);
  const active = rows.filter((r) => r.status === 'ACTIVE').length;
  return (
    <section className="stack-lg">
      <PlainIntro page="vat" />
      <PageHeader
        eyebrow={org.name}
        title="الضريبة"
        description="سجل المعالجات الضريبية المعتمدة. لا يحسب النظام إقرار ضريبة القيمة المضافة بعد، ولذلك لا تظهر هنا أي مبالغ ضريبية. التعديل من صفحة سلامة البيانات داخل المشروع (للمالك)."
      />
      <StatGrid label="ملخص الضرائب">
        <Stat label="معالجات مسجلة" value={rows.length} />
        <Stat label="سارية" value={active} />
      </StatGrid>
      <Section title="المعالجات الضريبية">
        <TaxRegistryTable rows={rows} />
      </Section>
    </section>
  );
}
