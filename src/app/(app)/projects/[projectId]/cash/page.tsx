import { WorkspaceChrome } from '@/features/workspace/chrome';
import { SectionTabs } from '@/shared/ui';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { formatMinorUnits } from '@/shared/money';
import { newCommandNonce } from '@/shared/idempotency';
import {
  getAuditEvents,
  getCashAccountPositions,
  getCurrentMembership,
  getLedgerForBatch,
  getObligationPositions,
  getPayments,
  getStatementLines,
  getUnpostedContributions,
} from '@/features/finance/queries';
import { JournalTrace } from '@/features/finance/journal-trace';
import {
  BankImportForm,
  CashAccountForm,
  ContributionAttributionForm,
  ReconcileForm,
  ReversePaymentForm,
  VoidMatchForm,
} from './forms';

export const dynamic = 'force-dynamic';

export default async function CashPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, accounts, obligations, payments, lines, contributions] = await Promise.all([
    getCurrentMembership(organizationId),
    getCashAccountPositions(projectId),
    getObligationPositions(projectId),
    getPayments(projectId),
    getStatementLines(projectId),
    getUnpostedContributions(projectId),
  ]);
  const isOwner = membership?.role === 'OWNER';
  const accountName = new Map(accounts.map((account) => [account.cash_account_id, account.name]));
  const obligationDescription = new Map(obligations.map((obligation) => [obligation.obligation_id, obligation.description]));

  const totalCash = accounts.reduce((sum, account) => sum + BigInt(account.balance_minor_units), 0n);
  const unreconciledCount = lines.filter((line) => !line.is_reconciled).length;
  const reconciledCount = lines.length - unreconciledCount;

  const paymentLedger = new Map<string, Awaited<ReturnType<typeof getLedgerForBatch>>>();
  for (const payment of payments) {
    const trace = await getLedgerForBatch(payment.batch_id);
    if (trace.length > 0) paymentLedger.set(payment.payment_id, trace);
  }
  const audit = await getAuditEvents([
    ...accounts.map((account) => account.cash_account_id),
    ...payments.map((payment) => payment.payment_id),
    ...lines.map((line) => line.import_id),
  ]);

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="costs-cash"
        title="النقدية والبنك"
        subtitle={`${project.name} · ${project.reporting_currency}`}
        internalReference={project.internal_reference}
        sector={project.sector}
        lifecycleState={project.lifecycle_state}
      />
      <SectionTabs
        label="التكاليف والنقدية"
        items={[
          { href: `/projects/${projectId}/costs`, label: 'التكاليف والالتزامات' },
          { href: `/projects/${projectId}/cash`, label: 'النقدية والبنك', current: true },
        ]}
      />

      <section className="grid">
        <div className="card">
          <p className="muted">إجمالي النقدية الدفترية</p>
          <strong>{formatMinorUnits(totalCash, project.reporting_currency)}</strong>
          <p className="muted">مشتق من القيود المرحلة فقط</p>
        </div>
        <div className="card">
          <p className="muted">حركات بنكية غير مطابقة</p>
          <strong>{unreconciledCount}</strong>
        </div>
        <div className="card">
          <p className="muted">حركات مطابقة</p>
          <strong>{reconciledCount}</strong>
        </div>
      </section>

      <section className="card stack">
        <h2>حسابات المشروع النقدية</h2>
        {accounts.length === 0 ? (
          <p className="muted">لا توجد حسابات نقدية بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الحساب · الرصيد الدفتري · آخر ترحيل</caption>
              <thead>
                <tr><th scope="col">الحساب</th><th scope="col" className="num">الرصيد الدفتري</th><th scope="col">آخر ترحيل</th></tr>
              </thead>
              <tbody>
                {accounts.map((account) => (
                  <tr key={account.cash_account_id}>
                    <td data-label="الحساب">{account.name}</td>
                    <td className="num" data-label="الرصيد الدفتري">{formatMinorUnits(account.balance_minor_units, account.currency)}</td>
                    <td data-label="آخر ترحيل">{account.last_posting_date ? new Date(account.last_posting_date).toLocaleString('ar-EG') : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <details className="stack">
          <summary>إنشاء حساب نقدي</summary>
          <CashAccountForm
            organizationId={organizationId}
            projectId={projectId}
            currency={project.reporting_currency}
            commandNonce={newCommandNonce()}
          />
        </details>
      </section>

      <section className="card stack">
        <h2>إسناد مساهمات رأس المال إلى النقدية</h2>
        {accounts.length === 0 ? (
          <p className="muted">أنشئ حسابًا نقديًا أولًا لربط المساهمات به.</p>
        ) : (
          <ContributionAttributionForm
            organizationId={organizationId}
            projectId={projectId}
            contributions={contributions}
            cashAccountId={accounts[0].cash_account_id}
            commandNonce={newCommandNonce()}
          />
        )}
        {!isOwner && <p className="muted">ترحيل الإسناد يتطلب صلاحية مالك المنظمة.</p>}
      </section>

      <section className="card stack">
        <h2>الدفعات</h2>
        {payments.length === 0 ? (
          <p className="muted">لا توجد دفعات بعد. سجّل دفعة من صفحة التكاليف أو انتظر أول دفعة.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: التاريخ · الالتزام · الحساب · المبلغ · الحالة · الإجراءات</caption>
              <thead>
                <tr><th scope="col">التاريخ</th><th scope="col" className="num">الالتزام</th><th scope="col">الحساب</th><th scope="col" className="num">المبلغ</th><th scope="col">الحالة</th><th scope="col">الإجراءات</th></tr>
              </thead>
              <tbody>
                {payments.map((payment) => (
                  <tr key={payment.payment_id}>
                    <td data-label="التاريخ">{payment.payment_date}</td>
                    <td className="num" data-label="الالتزام">{obligationDescription.get(payment.obligation_id) ?? '—'}</td>
                    <td data-label="الحساب">{accountName.get(payment.cash_account_id) ?? '—'}</td>
                    <td className="num" data-label="المبلغ">{formatMinorUnits(payment.amount_minor_units, payment.currency)}</td>
                    <td data-label="الحالة">
                      <span className="status">
                        {payment.is_reversed ? 'معكوسة' : payment.is_reconciled ? 'مطابقة' : 'غير مطابقة'}
                      </span>
                    </td>
                    <td data-label="الإجراءات">
                      {!payment.is_reversed && isOwner && (
                        <ReversePaymentForm
                          organizationId={organizationId}
                          projectId={projectId}
                          payment={payment}
                          commandNonce={newCommandNonce()}
                        />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {payments.length > 0 && (
          <details className="stack">
            <summary>الأثر المحاسبي للدفعات</summary>
            {payments.map((payment) => {
              const trace = paymentLedger.get(payment.payment_id);
              if (!trace || trace.length === 0) return null;
              return (
                <details key={payment.payment_id} className="stack">
                  <summary>{payment.payment_date} — {formatMinorUnits(payment.amount_minor_units, payment.currency)}</summary>
                  <JournalTrace lines={trace} />
                </details>
              );
            })}
          </details>
        )}
      </section>

      <section className="card stack">
        <h2>استيراد كشف الحساب البنكي</h2>
        {accounts.length === 0 ? (
          <p className="muted">أنشئ حسابًا نقديًا أولًا لاستيراد كشف حسابه.</p>
        ) : (
          <BankImportForm
            organizationId={organizationId}
            projectId={projectId}
            cashAccounts={accounts}
            commandNonce={newCommandNonce()}
          />
        )}
      </section>

      <section className="card stack">
        <h2>حركات كشف الحساب والمطابقة</h2>
        {lines.length === 0 ? (
          <p className="muted">لا توجد حركات بنكية مستوردة بعد. استيراد كشف الحساب لا ينشئ أي قيد محاسبي.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: التاريخ · المرجع · الوصف · المبلغ · الحساب · الحالة · الإجراءات</caption>
              <thead>
                <tr>
                  <th scope="col">التاريخ</th><th scope="col">المرجع</th><th scope="col">الوصف</th><th scope="col" className="num">المبلغ</th>
                  <th scope="col">الحساب</th><th scope="col">الحالة</th><th scope="col">الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => (
                  <tr key={line.line_id}>
                    <td data-label="التاريخ">{line.transaction_date}</td>
                    <td data-label="المرجع">{line.provider_reference ?? '—'}</td>
                    <td data-label="الوصف">{line.description}</td>
                    <td className="num" data-label="المبلغ">{formatMinorUnits(line.amount_minor_units, line.currency)}</td>
                    <td data-label="الحساب">{accountName.get(line.cash_account_id) ?? '—'}</td>
                    <td data-label="الحالة">
                      <span className="status">{line.is_reconciled ? 'مطابقة' : 'غير مطابقة'}</span>
                    </td>
                    <td data-label="الإجراءات">
                      {!line.is_reconciled && isOwner && (
                        <ReconcileForm
                          organizationId={organizationId}
                          projectId={projectId}
                          line={line}
                          payments={payments}
                          accountName={accountName.get(line.cash_account_id) ?? ''}
                          commandNonce={newCommandNonce()}
                        />
                      )}
                      {line.is_reconciled && line.match_id && isOwner && (
                        <VoidMatchForm
                          organizationId={organizationId}
                          projectId={projectId}
                          matchId={line.match_id}
                          commandNonce={newCommandNonce()}
                        />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">المطابقة تتم واحد-بواحد: دفعة واحدة مقابل سطر بنكي واحد بنفس الحساب والعملة والمبلغ (إشارة معاكسة).</p>
      </section>

      <section className="card stack">
        <h2>سجل التدقيق</h2>
        {audit.length === 0 ? (
          <p className="muted">لا توجد أحداث بعد.</p>
        ) : (
          <div className="table-wrap">
            <table className="table-stackable">
              <caption className="sr-only">جدول: الحدث · الوقت · التفاصيل</caption>
              <thead>
                <tr><th scope="col">الحدث</th><th scope="col">الوقت</th><th scope="col">التفاصيل</th></tr>
              </thead>
              <tbody>
                {audit.map((event) => (
                  <tr key={event.id}>
                    <td data-label="الحدث">{event.event_type}</td>
                    <td data-label="الوقت">{new Date(event.created_at).toLocaleString('ar-EG')}</td>
                    <td data-label="التفاصيل"><code>{JSON.stringify(event.payload)}</code></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </section>
  );
}
