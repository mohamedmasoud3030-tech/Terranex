import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { getParties } from '@/features/funding/queries';
import {
  getPropertyDispositions,
  getRealizedResults,
  getRentalCollections,
  getRentalIncome,
  getSaleCollections,
  getUnreconciledPositiveStatementLines,
} from '@/features/revenue/queries';
import { formatMinorUnits } from '@/shared/money';
import { getCashAccountPositions } from '@/features/finance/queries';
import { getPropertyWorkspaces } from '@/features/real-estate/queries';
import { WorkspaceChrome, ForbiddenCard } from '@/features/workspace/chrome';
import { Section, InPageTabs } from '@/shared/ui';
import { newCommandNonce } from '@/shared/idempotency';
import { RentalCollectionForm, RentalRecognitionForm, RentalReconciliationForm } from './rental-forms';

export const dynamic = 'force-dynamic';

const DISPOSITION_STATUS: Record<string, string> = {
  DRAFT: 'مسودة اتفاق',
  APPROVED: 'اتفاق معتمد',
  CONTROL_TRANSFERRED: 'انتقلت السيطرة',
};

function d(value: string | null | undefined) {
  return value ? new Date(value).toLocaleDateString('ar-EG') : '—';
}

export default async function RevenuePage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;
  const money = (value: string | number | bigint | null | undefined) => formatMinorUnits(value ?? '0', currency);

  const [membership, dispositions, results, collections, parties, unreconciledLines, assets, cashAccounts, rentals, rentalCollections] = await Promise.all([
    getCurrentMembership(organizationId),
    getPropertyDispositions(projectId),
    getRealizedResults(projectId),
    getSaleCollections(projectId),
    getParties(organizationId),
    getUnreconciledPositiveStatementLines(projectId),
    getPropertyWorkspaces(projectId),
    getCashAccountPositions(projectId),
    getRentalIncome(projectId),
    getRentalCollections(projectId),
  ]);

  if (!membership) {
    return <ForbiddenCard projectId={projectId} message="عضويتك الحالية لا تسمح بقراءة الإيراد لهذا المشروع." />;
  }

  const partyName = new Map(parties.map((party) => [party.id, party.legal_name]));
  const assetName = new Map(assets.map((asset) => [asset.property_asset_id, asset.name]));
  const cashName = new Map(cashAccounts.map((account) => [account.cash_account_id, account.name]));
  const recognizedRevenue = results.reduce((sum, result) => sum + BigInt(result.recognized_revenue_minor_units), 0n);
  const realizedResult = results.reduce((sum, result) => sum + BigInt(result.realized_result_minor_units), 0n);
  const totalCollected = collections
    .filter((collection) => collection.journal_batch_id)
    .reduce((sum, collection) => sum + BigInt(collection.amount_minor_units), 0n);

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="revenue"
        title="الإيراد والبيع"
        subtitle={`${project.name} · ${currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
        lifecycleState={project.lifecycle_state}
      />
      <InPageTabs
        label="تنقل الإيراد"
        items={[
          { href: '#dispositions', label: 'التصرفات' },
          // The rental section only renders for real-estate projects, so its
          // tab is conditional on exactly the same test — a tab that links to
          // a section the page will not render is a dead link.
          ...(project.sector === 'REAL_ESTATE'
            ? [{ href: '#rentals', label: 'الإيجار' }]
            : []),
          { href: '#result', label: 'النتيجة المحققة' },
          { href: '#collections', label: 'التحصيل' },
          { href: '#bank', label: 'المطابقة البنكية' },
        ]}
      />

            <Section
        title="ملخص الإيراد"
      >
        <div className="overview-kpis">
          <article className="overview-kpi">
            <span>إيراد البيع المعترف به</span>
            <strong>{money(recognizedRevenue)}</strong>
            <small>عبر قيود الاعتراف المتوازنة فقط</small>
          </article>
          <article className="overview-kpi negative">
            <span>النتيجة المحققة</span>
            <strong>{money(realizedResult)}</strong>
            <small>{results.length} تصرف معترف به</small>
          </article>
          <article className="overview-kpi">
            <span>النقد المحصل من المبيعات</span>
            <strong>{money(totalCollected)}</strong>
            <small>وقائع تحصيل مرحّلة</small>
          </article>
          <article className="overview-kpi">
            <span>سطور بنكية موجبة غير مطابقة</span>
            <strong>{unreconciledLines.length}</strong>
            <small>مرشحة لمطابقة تحصيلات</small>
          </article>
        </div>
      </Section>

      {project.sector === 'REAL_ESTATE' ? <section id="rentals" className="stack scroll-target" aria-labelledby="rentals-title">
        <div className="section-heading"><div><h2 id="rentals-title">إيراد الإيجار</h2><p className="muted">اعتراف ← ذمة مدينة ← تحصيل ← مطابقة بنكية، مع بقاء كل مرحلة واقعة مستقلة.</p></div></div>
        {membership.role === 'OWNER' ? <details className="card" open={rentals.length === 0}><summary>الاعتراف بإيراد إيجار</summary><RentalRecognitionForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} currency={currency} assets={assets} parties={parties}/></details> : <p className="muted">أوامر الإيجار المالية متاحة لمالك المنظمة وفق سلطة قاعدة البيانات.</p>}
        <section className="card stack">
          {rentals.length === 0 ? <p className="empty">لا توجد اعترافات إيجار مرحلة.</p> : <div className="table-wrap"><table className="table-stackable"><caption className="sr-only">جدول: العقد / الفترة · الأصل / المستأجر · المعترف · المحصل · الذمة المتبقية · الحالة / الإجراء</caption><thead><tr><th scope="col">العقد / الفترة</th><th scope="col">الأصل / المستأجر</th><th scope="col">المعترف</th><th scope="col">المحصل</th><th scope="col" className="num">الذمة المتبقية</th><th scope="col">الحالة / الإجراء</th></tr></thead><tbody>{rentals.map(r=><tr key={r.recognition_id}><td data-label="العقد / الفترة">{r.contract_reference}<br/><small>{d(r.rental_period_start)} — {d(r.rental_period_end)}</small></td><td data-label="الأصل / المستأجر">{assetName.get(r.property_asset_id)??r.property_asset_id}<br/><small>{partyName.get(r.tenant_party_id)??r.tenant_party_id}</small></td><td data-label="المعترف">{formatMinorUnits(r.recognized_amount_minor_units,r.currency)}</td><td data-label="المحصل">{formatMinorUnits(r.collected_minor_units,r.currency)}</td><td className="num" data-label="الذمة المتبقية">{formatMinorUnits(r.outstanding_receivable_minor_units,r.currency)}</td><td data-label="الحالة / الإجراء">{r.is_reversed?<span className="status">معكوس</span>:BigInt(r.outstanding_receivable_minor_units)===0n?<span className="status">محصل بالكامل</span>:membership.role==='OWNER'?<details><summary>تحصيل</summary><RentalCollectionForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} recognition={r} cashAccounts={cashAccounts}/></details>:<span className="muted">مستحق</span>}</td></tr>)}</tbody></table></div>}
        </section>
        <Section title="تحصيلات الإيجار والمطابقة" headingLevel={3}>{rentalCollections.length===0?<p className="muted">لا توجد تحصيلات إيجار.</p>:<div className="table-wrap"><table className="table-stackable"><caption className="sr-only">جدول: التاريخ · المبلغ · الحساب · الدليل · المطابقة</caption><thead><tr><th scope="col">التاريخ</th><th scope="col" className="num">المبلغ</th><th scope="col">الحساب</th><th scope="col">الدليل</th><th scope="col">المطابقة</th></tr></thead><tbody>{rentalCollections.map(c=><tr key={c.collection_id}><td data-label="التاريخ">{d(c.collection_date)}</td><td className="num" data-label="المبلغ">{formatMinorUnits(c.amount_minor_units,c.currency)}</td><td data-label="الحساب">{cashName.get(c.cash_account_id)??c.cash_account_id}</td><td data-label="الدليل">{c.evidence_reference}</td><td data-label="المطابقة">{c.is_reversed?<span className="status">معكوس</span>:membership.role==='OWNER'?<RentalReconciliationForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} collection={c} statementLines={unreconciledLines}/>:c.is_reconciled?<span className="status">مطابق بنكيًا</span>:<span className="muted">غير مطابق</span>}</td></tr>)}</tbody></table></div>}</Section>
      </section> : null}

            <Section
        id="dispositions"
        title="التصرفات"
      >
        {dispositions.length === 0 ? (
          <p className="muted">لا توجد اتفاقيات تصرف مسجّلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: اتفاقية التصرف · المشتري · الحالة · المتحصّل المتفق عليه · تاريخ الاتفاق</caption>
              <thead><tr><th scope="col">اتفاقية التصرف</th><th scope="col">المشتري</th><th scope="col">الحالة</th><th scope="col">المتحصّل المتفق عليه</th><th scope="col">تاريخ الاتفاق</th></tr></thead>
              <tbody>
                {dispositions.map((disposition) => (
                  <tr key={disposition.disposition_id}>
                    <td data-label="اتفاقية التصرف">{disposition.agreement_reference}</td>
                    <td data-label="المشتري">{partyName.get(disposition.buyer_party_id) || 'مشتري'}</td>
                    <td data-label="الحالة"><span className="status">{DISPOSITION_STATUS[disposition.status] ?? disposition.status}</span></td>
                    <td data-label="المتحصّل المتفق عليه">{formatMinorUnits(disposition.agreed_proceeds_minor_units, disposition.currency)}</td>
                    <td data-label="تاريخ الاتفاق">{d(disposition.agreement_date)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">تسجيل تصرف جديد، اعتماد، انتقال سيطرة واعتراف البيع من <Link href={`/projects/${projectId}/operations`}>الأصول العقارية</Link>.</p>
      </Section>

            <Section
        id="result"
        title="النتيجة المحققة"
      >
        {results.length === 0 ? (
          <p className="empty">لا توجد نتيجة محققة بعد. تظهر فقط بعد قيد اعتراف متوازن.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الأصل · التاريخ · الإيراد · التكلفة الملغاة · تكاليف البيع · النتيجة المحققة</caption>
              <thead><tr><th scope="col">الأصل</th><th scope="col">التاريخ</th><th scope="col" className="num">الإيراد</th><th scope="col" className="num">التكلفة الملغاة</th><th scope="col">تكاليف البيع</th><th scope="col" className="num">النتيجة المحققة</th></tr></thead>
              <tbody>
                {results.map((result) => (
                  <tr key={result.recognition_id}>
                    <td data-label="الأصل">{assetName.get(result.property_asset_id) || 'أصل عقاري'}</td>
                    <td data-label="التاريخ">{d(result.recognition_date)}</td>
                    <td className="num" data-label="الإيراد">{formatMinorUnits(result.recognized_revenue_minor_units, result.currency)}</td>
                    <td className="num" data-label="التكلفة الملغاة">{formatMinorUnits(result.carrying_cost_derecognized_minor_units, result.currency)}</td>
                    <td data-label="تكاليف البيع">{formatMinorUnits(result.selling_costs_minor_units, result.currency)}</td>
                    <td className="num" data-label="النتيجة المحققة"><strong>{formatMinorUnits(result.realized_result_minor_units, result.currency)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

            <Section
        id="collections"
        title="سجل التحصيل"
      >
        {collections.length === 0 ? (
          <p className="muted">لا توجد تحصيلات مسجّلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: التاريخ · المبلغ · الحساب النقدي · الدليل · المطابقة</caption>
              <thead><tr><th scope="col">التاريخ</th><th scope="col" className="num">المبلغ</th><th scope="col">الحساب النقدي</th><th scope="col">الدليل</th><th scope="col">المطابقة</th></tr></thead>
              <tbody>
                {collections.map((collection) => (
                  <tr key={collection.collection_id}>
                    <td data-label="التاريخ">{d(collection.collection_date)}</td>
                    <td className="num" data-label="المبلغ">{formatMinorUnits(collection.amount_minor_units, collection.currency)}</td>
                    <td data-label="الحساب النقدي">{collection.cash_account_id}</td>
                    <td data-label="الدليل">{collection.evidence_reference}</td>
                    <td data-label="المطابقة">{collection.is_reconciled ? <span className="status">مطابق بنكيًا</span> : <span className="muted">غير مطابق</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Section>

            <Section
        id="bank"
        title="المطابقة البنكية للتحصيلات"
      >
        {unreconciledLines.length === 0 ? (
          <p className="muted">لا توجد سطور بنكية موجبة غير مطابقة.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: التاريخ · الوصف · المبلغ · مرجع المزود</caption>
              <thead><tr><th scope="col">التاريخ</th><th scope="col">الوصف</th><th scope="col" className="num">المبلغ</th><th scope="col">مرجع المزود</th></tr></thead>
              <tbody>
                {unreconciledLines.map((line) => (
                  <tr key={line.line_id}>
                    <td data-label="التاريخ">{d(line.transaction_date)}</td>
                    <td data-label="الوصف">{line.description}</td>
                    <td className="num" data-label="المبلغ">{formatMinorUnits(line.amount_minor_units, line.currency)}</td>
                    <td data-label="مرجع المزود">{line.provider_reference}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">مطابقة التحصيلات وسطور البنك تتم من <Link href={`/projects/${projectId}/operations`}>الأصول العقارية</Link> و<Link href={`/projects/${projectId}/cash`}>النقدية والبنك</Link>.</p>
      </Section>
    </section>
  );
}
