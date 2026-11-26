import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid, StatusBadge } from '@/shared/ui';
import { BarList } from '@/shared/ui/insight';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getOrganizationStatementLines } from '@/features/finance/queries';
import { formatDate } from '@/features/procurement/labels';
import { formatMinorUnits } from '@/shared/money';
import { presentRollup, totalsByCurrency } from '@/shared/money/by-currency';

export const dynamic = 'force-dynamic';

const LIMIT = 300;

/** حركات البنك: أسطر كشوف الحساب المستوردة عبر المشاريع وحالة مطابقتها. قراءة فقط. */
export default async function TransactionsPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="الحركات تظهر بعد استيراد كشوف الحساب."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [lines, projects] = await Promise.all([
    getOrganizationStatementLines(org.id, LIMIT),
    getProjects(org.id),
  ]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const matched = lines.filter((l) => l.is_reconciled).length;
  const inflow = totalsByCurrency(lines.filter((l) => BigInt(l.amount_minor_units) > 0n), (l) => l.currency, (l) => l.amount_minor_units);
  const outflow = totalsByCurrency(lines.filter((l) => BigInt(l.amount_minor_units) < 0n), (l) => l.currency, (l) => l.amount_minor_units);
  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="حركات البنك"
        description="أسطر كشوف الحساب المستوردة عبر المشاريع وحالة مطابقتها مع الدفعات. قراءة فقط، والاستيراد والمطابقة من صفحة التكاليف والنقدية في المشروع."
      />
      <StatGrid label="ملخص الحركات">
        <Stat label="عدد الأسطر" value={lines.length} hint={`${matched} مطابَق`} />
        {inflow.totals.map((t) => (
          <Stat key={`i-${t.currency}`} label={`الوارد (${t.currency})`} value={presentRollup(t)} tone="positive" />
        ))}
        {outflow.totals.map((t) => (
          <Stat key={`o-${t.currency}`} label={`الصادر (${t.currency})`} value={presentRollup(t)} tone="negative" />
        ))}
      </StatGrid>
      {lines.length === 0 ? (
        <EmptyState title="لا توجد حركات بنكية بعد" description="تظهر هنا بعد استيراد كشف حساب من داخل المشروع." action={<Link className="button" href="/projects">فتح المشاريع</Link>} />
      ) : (
        <Section title="الحركات" description={lines.length >= LIMIT ? `أحدث ${LIMIT} سطرًا فقط.` : `${lines.length} سطر.`}>
          <BarList
            caption="المطابقة مع الدفعات (عدد الأسطر)"
            items={[
              { key: 'm', label: 'مطابَق', value: matched, tone: 'cash' },
              { key: 'u', label: 'غير مطابَق', value: lines.length - matched, tone: 'exp' },
            ]}
          />
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">حركات البنك: التاريخ والبيان والمشروع والمبلغ والمطابقة</caption>
              <thead>
                <tr>
                  <th scope="col">التاريخ</th>
                  <th scope="col">البيان</th>
                  <th scope="col">المشروع</th>
                  <th scope="col" className="num">المبلغ</th>
                  <th scope="col">المطابقة</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((l) => (
                  <tr key={l.line_id}>
                    <td data-label="التاريخ">{formatDate(l.transaction_date)}</td>
                    <td data-label="البيان">{l.description}{l.provider_reference ? <><br /><small className="muted">{l.provider_reference}</small></> : null}</td>
                    <td data-label="المشروع"><Link href={`/projects/${l.project_id}/cash`}>{projectName.get(l.project_id) ?? 'مشروع'}</Link></td>
                    <td data-label="المبلغ" className="num">{formatMinorUnits(l.amount_minor_units, l.currency)}</td>
                    <td data-label="المطابقة"><StatusBadge tone={l.is_reconciled ? 'success' : 'warning'}>{l.is_reconciled ? 'مطابَق' : 'غير مطابَق'}</StatusBadge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      )}
    </section>
  );
}
