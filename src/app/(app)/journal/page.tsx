import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getOrganizationLedger } from '@/features/finance/queries';
import { JournalTrace } from '@/features/finance/journal-trace';
import { presentRollup, totalsByCurrency } from '@/shared/money/by-currency';

export const dynamic = 'force-dynamic';

const LIMIT = 300;

/** دفتر القيود: آخر القيود المرحَّلة عبر المنظمة، قراءة فقط. لا يوجد إدخال يدوي للقيود. */
export default async function JournalPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="القيود تظهر بعد إنشاء منظمة وترحيل حركات مالية."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const lines = await getOrganizationLedger(org.id, LIMIT);
  const batches = new Set(lines.map((l) => l.batch_id)).size;
  const debit = totalsByCurrency(lines, (l) => l.currency, (l) => l.debit_minor_units);
  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="دفتر القيود"
        description="آخر القيود المرحَّلة عبر كل المشاريع، قراءة فقط. تُنشأ القيود تلقائيًا من اعتماد الالتزامات والدفعات والمساهمات، ولا يوجد إدخال يدوي."
      />
      <StatGrid label="ملخص القيود">
        <Stat label="عدد القيود" value={batches} hint={`${lines.length} سطر`} />
        {debit.totals.map((t) => (
          <Stat key={t.currency} label={`إجمالي المدين (${t.currency})`} value={presentRollup(t)} hint={`${t.rowCount} سطر`} />
        ))}
      </StatGrid>
      <Section
        title="القيود"
        description={lines.length >= LIMIT ? `أحدث ${LIMIT} سطرًا فقط.` : `${lines.length} سطر.`}
      >
        <JournalTrace lines={lines} />
      </Section>
    </section>
  );
}
