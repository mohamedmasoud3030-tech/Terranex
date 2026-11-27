import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid } from '@/shared/ui';
import { BarList } from '@/shared/ui/insight';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import {
  getOwnerBankSuggestions,
  getOwnerCashPositions,
  getOwnerOverdueObligations,
  getOwnerWeeklyCash,
} from '@/features/owner-insights/queries';
import { buildWeeklySummary, weekOverWeekDelta } from '@/features/owner-insights/weekly';
import { formatMinorUnits } from '@/shared/money';

export const dynamic = 'force-dynamic';

/** الملخص الأسبوعي للمالك: الفلوس اللي دخلت وخرجت، وإيه اللي محتاج قرار. قراءة فقط. */
export default async function OwnerSummaryPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="الملخص الأسبوعي يظهر بعد إنشاء منظمة ومشروع."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const today = new Date().toISOString().slice(0, 10);
  const [weeklyCash, overdue, suggestions, cashPositions, projects] = await Promise.all([
    getOwnerWeeklyCash(org.id),
    getOwnerOverdueObligations(org.id),
    getOwnerBankSuggestions(org.id),
    getOwnerCashPositions(org.id),
    getProjects(org.id),
  ]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const summary = buildWeeklySummary(weeklyCash, today);

  const overdueByCurrency = new Map<string, bigint>();
  for (const row of overdue) {
    overdueByCurrency.set(row.currency, (overdueByCurrency.get(row.currency) ?? 0n) + BigInt(row.outstanding_minor_units));
  }

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="الملخص الأسبوعي للمالك"
        description="الفلوس اللي دخلت واللي خرجت الأسبوع ده، وإيه اللي محتاج قرارك. الأرقام من دفتر القيود مباشرة، وكل عملة تُعرض منفصلة."
        actions={
          <>
            <Link className="button secondary sm" href="/owner/ask">اسأل أرقامك</Link>
            <Link className="button secondary sm" href="/owner/bank-import">استيراد كشف بنك</Link>
          </>
        }
      />

      <StatGrid label="حركة الأسبوع">
        {summary.current.length === 0 ? (
          <Stat label="الأسبوع ده" value="مفيش حركة لسه" hint="أول قيد هيتسجل هيظهر هنا" />
        ) : (
          summary.current.map((t) => {
            const prev = summary.previous.find((p) => p.currency === t.currency);
            const delta = prev ? weekOverWeekDelta(t.inMinor, prev.inMinor) : null;
            return (
              <Stat
                key={t.currency}
                label={`الوارد (${t.currency})`}
                value={formatMinorUnits(t.inMinor.toString(), t.currency)}
                hint={
                  delta === null
                    ? 'مفيش مقارنة بالأسبوع اللي فات'
                    : `${delta >= 0 ? 'أعلى' : 'أقل'} من الأسبوع اللي فات بحوالي ${Math.abs(Math.round(delta))}٪`
                }
                tone="positive"
              />
            );
          })
        )}
        {summary.current.map((t) => (
          <Stat
            key={`out-${t.currency}`}
            label={`المنصرف (${t.currency})`}
            value={formatMinorUnits(t.outMinor.toString(), t.currency)}
            tone="negative"
          />
        ))}
        {summary.current.map((t) => (
          <Stat
            key={`net-${t.currency}`}
            label={`الصافي (${t.currency})`}
            value={formatMinorUnits(t.netMinor.toString(), t.currency)}
            tone={t.netMinor >= 0n ? 'positive' : 'negative'}
          />
        ))}
      </StatGrid>

      <Section title="محتاج قرارك" description="حاجات مفتوحة متسجلة في الدفاتر ومستنياك">
        {overdue.length === 0 && suggestions.length === 0 ? (
          <EmptyState title="مفيش حاجة متأخرة" description="كل الالتزامات في معادها وكل حركات البنك متطابقة." />
        ) : (
          <StatGrid label="بنود تحتاج قرار">
            {overdue.length > 0 ? (
              <Stat
                label="التزامات متأخرة"
                value={overdue.length}
                hint={[...overdueByCurrency.entries()]
                  .map(([currency, total]) => formatMinorUnits(total.toString(), currency))
                  .join(' · ')}
                tone="negative"
              />
            ) : null}
            {suggestions.length > 0 ? (
              <Stat
                label="حركات بنك مستنية مراجعة"
                value={suggestions.length}
                hint={`${suggestions.filter((s) => s.suggestion_kind === 'PAY_OBLIGATION').length} منها شكلها سداد التزام معروف`}
                href="/owner/bank-import"
                tone="neutral"
              />
            ) : null}
          </StatGrid>
        )}
        {overdue.length > 0 ? (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">الالتزامات المتأخرة</caption>
              <thead>
                <tr>
                  <th scope="col">الالتزام</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">المتبقي</th>
                  <th scope="col">التأخير</th>
                </tr>
              </thead>
              <tbody>
                {overdue.slice(0, 10).map((row) => (
                  <tr key={row.obligation_id}>
                    <td>{row.description}</td>
                    <td>{projectName.get(row.project_id) ?? '—'}</td>
                    <td dir="ltr">{formatMinorUnits(row.outstanding_minor_units, row.currency)}</td>
                    <td>{row.days_overdue} يوم</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </Section>

      <Section title="آخر ٨ أسابيع" description="صافي الحركة الأسبوعية لكل عملة">
        {summary.recentWeeks.length === 0 ? (
          <EmptyState title="مفيش حركة بعد" description="الأسابيع هتظهر هنا أول ما القيود تتسجل." />
        ) : (
          <BarList
            items={summary.recentWeeks.map((t) => ({
              key: `${t.weekStart}-${t.currency}`,
              label: `أسبوع ${t.weekStart} (${t.currency})`,
              value: Number(t.inMinor + t.outMinor) / 100,
              display: `${t.netMinor >= 0n ? '+' : '−'}${formatMinorUnits((t.netMinor < 0n ? -t.netMinor : t.netMinor).toString(), t.currency)}`,
              tone: t.netMinor >= 0n ? 'cash' : 'exp',
            }))}
          />
        )}
      </Section>

      <Section title="أرصدة الحسابات النقدية">
        {cashPositions.length === 0 ? (
          <EmptyState title="مفيش حسابات نقدية" description="الأرصدة تظهر بعد إنشاء حساب نقدي في مشروع." />
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">أرصدة الحسابات النقدية</caption>
              <thead>
                <tr>
                  <th scope="col">الحساب</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">الرصيد</th>
                  <th scope="col">آخر قيد</th>
                </tr>
              </thead>
              <tbody>
                {cashPositions.map((row) => (
                  <tr key={row.cash_account_id}>
                    <td>{row.name}</td>
                    <td>{projectName.get(row.project_id) ?? '—'}</td>
                    <td dir="ltr">{formatMinorUnits(row.balance_minor_units, row.currency)}</td>
                    <td dir="ltr">{row.last_posting_date ? row.last_posting_date.slice(0, 10) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>
    </section>
  );
}
