import Link from 'next/link';
import { EmptyState, PageHeader, Section, Stat, StatGrid, StatusBadge } from '@/shared/ui';
import { BarList } from '@/shared/ui/insight';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import { getOrganizationSupplierInvoices } from '@/features/procurement/queries';
import { formatDate, formatPaymentState } from '@/features/procurement/labels';
import { formatMinorUnits } from '@/shared/money';
import { presentRollup, totalsByCurrency } from '@/shared/money/by-currency';

export const dynamic = 'force-dynamic';

/**
 * فواتير الموردين عبر كل مشاريع المنظمة. قراءة فقط: الإدخال والاعتماد
 * يتمّان من صفحة المشتريات داخل كل مشروع. لا توجد فواتير عملاء في النظام الحالي.
 */
export default async function InvoicesPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="الفواتير تظهر بعد إنشاء المنظمة وتسجيل فواتير الموردين."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const [invoices, projects] = await Promise.all([
    getOrganizationSupplierInvoices(org.id),
    getProjects(org.id),
  ]);
  const projectName = new Map(projects.map((p) => [p.id, p.name]));
  const total = totalsByCurrency(invoices, (i) => i.currency, (i) => i.invoice_total_minor_units);
  const paid = totalsByCurrency(invoices, (i) => i.currency, (i) => i.paid_minor_units);
  const open = totalsByCurrency(invoices, (i) => i.currency, (i) => i.outstanding_minor_units);
  const submitted = invoices.filter((i) => i.status === 'SUBMITTED').length;

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="فواتير الموردين"
        description="كل فواتير الموردين عبر المشاريع، قراءة فقط. التسجيل والاعتماد من صفحة المشتريات في المشروع. لا توجد فواتير عملاء في النظام."
      />
      <StatGrid label="ملخص الفواتير">
        <Stat label="عدد الفواتير" value={invoices.length} hint={`${submitted} بانتظار الاعتماد`} />
        {total.totals.map((t) => (
          <Stat key={`t-${t.currency}`} label={`إجمالي الفواتير (${t.currency})`} value={presentRollup(t)} hint={`${t.rowCount} فاتورة`} />
        ))}
        {open.totals.map((t) => (
          <Stat key={`o-${t.currency}`} label={`المتبقي للدفع (${t.currency})`} value={presentRollup(t)} tone={t.minorUnits > 0n ? 'negative' : 'neutral'} />
        ))}
        {paid.totals.map((t) => (
          <Stat key={`p-${t.currency}`} label={`المدفوع (${t.currency})`} value={presentRollup(t)} />
        ))}
      </StatGrid>

      {invoices.length === 0 ? (
        <EmptyState
          title="لا توجد فواتير موردين بعد"
          description="تُسجَّل الفاتورة من صفحة المشتريات داخل المشروع بعد استلام البضاعة."
          action={<Link className="button" href="/projects">فتح المشاريع</Link>}
        />
      ) : (
        <Section title="الفواتير" description={`${invoices.length} فاتورة، الأحدث أولًا.`}>
          {total.totals.length === 1 ? (
            <BarList
              caption={`حالة السداد (${total.totals[0].currency})`}
              items={(['UNPAID', 'PARTIALLY_PAID', 'FULLY_PAID'] as const).map((state) => ({
                key: state,
                label: formatPaymentState(state),
                value: invoices.filter((i) => i.payment_state === state).length,
                tone: state === 'FULLY_PAID' ? ('cash' as const) : ('exp' as const),
              }))}
            />
          ) : null}
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">فواتير الموردين: المرجع والمورد والمشروع والتاريخ والمبلغ والمتبقي والحالة</caption>
              <thead>
                <tr>
                  <th scope="col">الفاتورة</th>
                  <th scope="col">المورد</th>
                  <th scope="col">المشروع</th>
                  <th scope="col">التاريخ</th>
                  <th scope="col" className="num">المبلغ</th>
                  <th scope="col" className="num">المتبقي</th>
                  <th scope="col">الحالة</th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((i) => (
                  <tr key={i.id}>
                    <td data-label="الفاتورة"><strong>{i.invoice_reference}</strong><br /><small className="muted">أمر الشراء {i.purchase_order_reference}</small></td>
                    <td data-label="المورد">{i.supplier_name}</td>
                    <td data-label="المشروع"><Link href={`/projects/${i.project_id}/procurement`}>{projectName.get(i.project_id) ?? 'مشروع'}</Link></td>
                    <td data-label="التاريخ">{formatDate(i.invoice_date)}</td>
                    <td data-label="المبلغ" className="num">{formatMinorUnits(i.invoice_total_minor_units, i.currency)}</td>
                    <td data-label="المتبقي" className="num">{formatMinorUnits(i.outstanding_minor_units, i.currency)}</td>
                    <td data-label="الحالة">
                      <StatusBadge tone={i.status === 'APPROVED' ? 'success' : 'warning'}>{i.status === 'APPROVED' ? 'معتمدة' : 'بانتظار الاعتماد'}</StatusBadge>{' '}
                      <small className="muted">{formatPaymentState(i.payment_state)}</small>
                    </td>
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
