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
      />
      <nav className="context-nav" aria-label="تنقل الإيراد">
        <a href="#dispositions">التصرفات</a>
        <a href="#result">النتيجة المحققة</a>
        <a href="#collections">التحصيل</a>
        <a href="#bank">المطابقة البنكية</a>
      </nav>

      <section className="card stack">
        <h2>ملخص الإيراد</h2>
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
      </section>

      {project.sector === 'REAL_ESTATE' ? <section id="rentals" className="stack scroll-target">
        <div className="section-heading"><div><h2>إيراد الإيجار</h2><p className="muted">اعتراف ← ذمة مدينة ← تحصيل ← مطابقة بنكية، مع بقاء كل مرحلة واقعة مستقلة.</p></div></div>
        {membership.role === 'OWNER' ? <details className="card" open={rentals.length === 0}><summary>الاعتراف بإيراد إيجار</summary><RentalRecognitionForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} currency={currency} assets={assets} parties={parties}/></details> : <p className="muted">أوامر الإيجار المالية متاحة لمالك المنظمة وفق سلطة قاعدة البيانات.</p>}
        <section className="card stack">
          {rentals.length === 0 ? <p className="empty">لا توجد اعترافات إيجار مرحلة.</p> : <div className="table-wrap"><table><thead><tr><th>العقد / الفترة</th><th>الأصل / المستأجر</th><th>المعترف</th><th>المحصل</th><th>الذمة المتبقية</th><th>الحالة / الإجراء</th></tr></thead><tbody>{rentals.map(r=><tr key={r.recognition_id}><td>{r.contract_reference}<br/><small>{d(r.rental_period_start)} — {d(r.rental_period_end)}</small></td><td>{assetName.get(r.property_asset_id)??r.property_asset_id}<br/><small>{partyName.get(r.tenant_party_id)??r.tenant_party_id}</small></td><td>{formatMinorUnits(r.recognized_amount_minor_units,r.currency)}</td><td>{formatMinorUnits(r.collected_minor_units,r.currency)}</td><td>{formatMinorUnits(r.outstanding_receivable_minor_units,r.currency)}</td><td>{r.is_reversed?<span className="status">معكوس</span>:BigInt(r.outstanding_receivable_minor_units)===0n?<span className="status">محصل بالكامل</span>:membership.role==='OWNER'?<details><summary>تحصيل</summary><RentalCollectionForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} recognition={r} cashAccounts={cashAccounts}/></details>:<span className="muted">مستحق</span>}</td></tr>)}</tbody></table></div>}
        </section>
        <section className="card stack"><h3>تحصيلات الإيجار والمطابقة</h3>{rentalCollections.length===0?<p className="muted">لا توجد تحصيلات إيجار.</p>:<div className="table-wrap"><table><thead><tr><th>التاريخ</th><th>المبلغ</th><th>الحساب</th><th>الدليل</th><th>المطابقة</th></tr></thead><tbody>{rentalCollections.map(c=><tr key={c.collection_id}><td>{d(c.collection_date)}</td><td>{formatMinorUnits(c.amount_minor_units,c.currency)}</td><td>{cashName.get(c.cash_account_id)??c.cash_account_id}</td><td>{c.evidence_reference}</td><td>{c.is_reversed?<span className="status">معكوس</span>:membership.role==='OWNER'?<RentalReconciliationForm organizationId={organizationId} projectId={projectId} commandNonce={newCommandNonce()} collection={c} statementLines={unreconciledLines}/>:c.is_reconciled?<span className="status">مطابق بنكيًا</span>:<span className="muted">غير مطابق</span>}</td></tr>)}</tbody></table></div>}</section>
      </section> : null}

      <section id="dispositions" className="card stack scroll-target">
        <h2>التصرفات</h2>
        {dispositions.length === 0 ? (
          <p className="muted">لا توجد اتفاقيات تصرف مسجّلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>اتفاقية التصرف</th><th>المشتري</th><th>الحالة</th><th>المتحصّل المتفق عليه</th><th>تاريخ الاتفاق</th></tr></thead>
              <tbody>
                {dispositions.map((disposition) => (
                  <tr key={disposition.disposition_id}>
                    <td>{disposition.agreement_reference}</td>
                    <td>{partyName.get(disposition.buyer_party_id) || 'مشتري'}</td>
                    <td><span className="status">{DISPOSITION_STATUS[disposition.status] ?? disposition.status}</span></td>
                    <td>{formatMinorUnits(disposition.agreed_proceeds_minor_units, disposition.currency)}</td>
                    <td>{d(disposition.agreement_date)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">تسجيل تصرف جديد، اعتماد، انتقال سيطرة واعتراف البيع من <Link href={`/projects/${projectId}/operations`}>الأصول العقارية</Link>.</p>
      </section>

      <section id="result" className="card stack scroll-target">
        <h2>النتيجة المحققة</h2>
        {results.length === 0 ? (
          <p className="empty">لا توجد نتيجة محققة بعد. تظهر فقط بعد قيد اعتراف متوازن.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>الأصل</th><th>التاريخ</th><th>الإيراد</th><th>التكلفة الملغاة</th><th>تكاليف البيع</th><th>النتيجة المحققة</th></tr></thead>
              <tbody>
                {results.map((result) => (
                  <tr key={result.recognition_id}>
                    <td>{assetName.get(result.property_asset_id) || 'أصل عقاري'}</td>
                    <td>{d(result.recognition_date)}</td>
                    <td>{formatMinorUnits(result.recognized_revenue_minor_units, result.currency)}</td>
                    <td>{formatMinorUnits(result.carrying_cost_derecognized_minor_units, result.currency)}</td>
                    <td>{formatMinorUnits(result.selling_costs_minor_units, result.currency)}</td>
                    <td><strong>{formatMinorUnits(result.realized_result_minor_units, result.currency)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="collections" className="card stack scroll-target">
        <h2>سجل التحصيل</h2>
        {collections.length === 0 ? (
          <p className="muted">لا توجد تحصيلات مسجّلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>التاريخ</th><th>المبلغ</th><th>الحساب النقدي</th><th>الدليل</th><th>المطابقة</th></tr></thead>
              <tbody>
                {collections.map((collection) => (
                  <tr key={collection.collection_id}>
                    <td>{d(collection.collection_date)}</td>
                    <td>{formatMinorUnits(collection.amount_minor_units, collection.currency)}</td>
                    <td>{collection.cash_account_id}</td>
                    <td>{collection.evidence_reference}</td>
                    <td>{collection.is_reconciled ? <span className="status">مطابق بنكيًا</span> : <span className="muted">غير مطابق</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section id="bank" className="card stack scroll-target">
        <h2>المطابقة البنكية للتحصيلات</h2>
        {unreconciledLines.length === 0 ? (
          <p className="muted">لا توجد سطور بنكية موجبة غير مطابقة.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>التاريخ</th><th>الوصف</th><th>المبلغ</th><th>مرجع المزود</th></tr></thead>
              <tbody>
                {unreconciledLines.map((line) => (
                  <tr key={line.line_id}>
                    <td>{d(line.transaction_date)}</td>
                    <td>{line.description}</td>
                    <td>{formatMinorUnits(line.amount_minor_units, line.currency)}</td>
                    <td>{line.provider_reference}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">مطابقة التحصيلات وسطور البنك تتم من <Link href={`/projects/${projectId}/operations`}>الأصول العقارية</Link> و<Link href={`/projects/${projectId}/cash`}>النقدية والبنك</Link>.</p>
      </section>
    </section>
  );
}
