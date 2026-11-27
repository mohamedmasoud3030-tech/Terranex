import Link from 'next/link';
import { EmptyState, PageHeader, Section } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getOwnerBankSuggestions, getOwnerCashPositions } from '@/features/owner-insights/queries';
import { OwnerBankImportForm } from '@/features/owner-insights/import-form';
import { newCommandNonce } from '@/shared/idempotency';
import { formatMinorUnits } from '@/shared/money';
import type { OwnerBankSuggestionKind } from '@/features/owner-insights/queries';

export const dynamic = 'force-dynamic';

const KIND_LABEL: Record<OwnerBankSuggestionKind, string> = {
  PAY_OBLIGATION: 'سداد التزام معروف',
  RECORD_OUTFLOW: 'مصروف يحتاج تسجيل',
  RECORD_INFLOW: 'وارد يحتاج تسجيل',
};

/** استيراد كشف البنك من Excel/CSV مع اقتراحات تلقائية لكل حركة، للمراجعة فقط. */
export default async function OwnerBankImportPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="الاستيراد متاح بعد إنشاء منظمة ومشروع وحساب نقدي."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [cashPositions, suggestions, projects] = await Promise.all([
    getOwnerCashPositions(org.id),
    getOwnerBankSuggestions(org.id),
    getProjects(org.id),
  ]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const accounts = cashPositions.map((row) => ({
    cashAccountId: row.cash_account_id,
    projectId: row.project_id,
    accountName: row.name,
    projectName: projectName.get(row.project_id) ?? '—',
    currency: row.currency,
  }));

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="استيراد كشف البنك"
        description="ارفع كشف الحساب من Excel أو CSV، راجع المعاينة، وبعد الاستيراد تشوف اقتراح تلقائي لكل حركة. مفيش قيد بيتسجل غير بمراجعة منك."
        actions={<Link className="button secondary sm" href="/owner">الملخص الأسبوعي</Link>}
      />

      <Section title="رفع كشف جديد">
        {accounts.length === 0 ? (
          <EmptyState
            title="مفيش حساب نقدي بعد"
            description="أنشئ حساب نقدي داخل مشروع الأول، وبعدها تقدر تستورد كشوف الحساب هنا."
            action={<Link className="button" href="/projects">المشاريع</Link>}
          />
        ) : (
          <OwnerBankImportForm organizationId={org.id} accounts={accounts} commandNonce={newCommandNonce()} />
        )}
      </Section>

      <Section
        title="حركات مستنية مراجعتك"
        description={suggestions.length > 0 ? `${suggestions.length} حركة غير متطابقة` : undefined}
      >
        {suggestions.length === 0 ? (
          <EmptyState title="كل الحركات متطابقة" description="مفيش حركة بنك مستوردة من غير مطابقة." />
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">حركات البنك غير المتطابقة واقتراحاتها</caption>
              <thead>
                <tr>
                  <th scope="col">التاريخ</th>
                  <th scope="col">البيان</th>
                  <th scope="col">المبلغ</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">الاقتراح</th>
                  <th scope="col">إجراء</th>
                </tr>
              </thead>
              <tbody>
                {suggestions.slice(0, 50).map((row) => (
                  <tr key={row.line_id}>
                    <td dir="ltr">{row.transaction_date}</td>
                    <td>{row.description}</td>
                    <td dir="ltr">{formatMinorUnits(row.amount_minor_units, row.currency)}</td>
                    <td>{projectName.get(row.project_id) ?? '—'}</td>
                    <td>
                      {KIND_LABEL[row.suggestion_kind]}
                      {row.suggestion_kind === 'PAY_OBLIGATION' && row.suggested_obligation_description
                        ? `: ${row.suggested_obligation_description}`
                        : ''}
                    </td>
                    <td>
                      <Link className="button secondary sm" href={`/projects/${row.project_id}/cash`}>
                        راجع في المشروع
                      </Link>
                    </td>
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
