import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { formatMinorUnits } from '@/shared/money';
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
      <div className="top">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← العودة للمشروع</Link>
          <h1>النقدية والبنك</h1>
          <p className="muted">{project.name} · {project.reporting_currency}</p>
        </div>
        <Link className="button secondary" href={`/projects/${projectId}/costs`}>التكاليف والالتزامات</Link>
      </div>

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
            <table>
              <thead>
                <tr><th>الحساب</th><th>الرصيد الدفتري</th><th>آخر ترحيل</th></tr>
              </thead>
              <tbody>
                {accounts.map((account) => (
                  <tr key={account.cash_account_id}>
                    <td>{account.name}</td>
                    <td>{formatMinorUnits(account.balance_minor_units, account.currency)}</td>
                    <td>{account.last_posting_date ? new Date(account.last_posting_date).toLocaleString('ar-EG') : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <details className="stack">
          <summary>إنشاء حساب نقدي</summary>
          <CashAccountForm organizationId={organizationId} projectId={projectId} currency={project.reporting_currency} />
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
            <table>
              <thead>
                <tr><th>التاريخ</th><th>الالتزام</th><th>الحساب</th><th>المبلغ</th><th>الحالة</th><th>الإجراءات</th></tr>
              </thead>
              <tbody>
                {payments.map((payment) => (
                  <tr key={payment.payment_id}>
                    <td>{payment.payment_date}</td>
                    <td>{obligationDescription.get(payment.obligation_id) ?? '—'}</td>
                    <td>{accountName.get(payment.cash_account_id) ?? '—'}</td>
                    <td>{formatMinorUnits(payment.amount_minor_units, payment.currency)}</td>
                    <td>
                      <span className="status">
                        {payment.is_reversed ? 'معكوسة' : payment.is_reconciled ? 'مطابقة' : 'غير مطابقة'}
                      </span>
                    </td>
                    <td>
                      {!payment.is_reversed && isOwner && (
                        <ReversePaymentForm organizationId={organizationId} projectId={projectId} payment={payment} />
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
          <BankImportForm organizationId={organizationId} projectId={projectId} cashAccounts={accounts} />
        )}
      </section>

      <section className="card stack">
        <h2>حركات كشف الحساب والمطابقة</h2>
        {lines.length === 0 ? (
          <p className="muted">لا توجد حركات بنكية مستوردة بعد. استيراد كشف الحساب لا ينشئ أي قيد محاسبي.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>التاريخ</th><th>المرجع</th><th>الوصف</th><th>المبلغ</th>
                  <th>الحساب</th><th>الحالة</th><th>الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => (
                  <tr key={line.line_id}>
                    <td>{line.transaction_date}</td>
                    <td>{line.provider_reference ?? '—'}</td>
                    <td>{line.description}</td>
                    <td>{formatMinorUnits(line.amount_minor_units, line.currency)}</td>
                    <td>{accountName.get(line.cash_account_id) ?? '—'}</td>
                    <td>
                      <span className="status">{line.is_reconciled ? 'مطابقة' : 'غير مطابقة'}</span>
                    </td>
                    <td>
                      {!line.is_reconciled && isOwner && (
                        <ReconcileForm
                          organizationId={organizationId}
                          projectId={projectId}
                          line={line}
                          payments={payments}
                          accountName={accountName.get(line.cash_account_id) ?? ''}
                        />
                      )}
                      {line.is_reconciled && line.match_id && isOwner && (
                        <VoidMatchForm organizationId={organizationId} projectId={projectId} matchId={line.match_id} />
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
            <table>
              <thead>
                <tr><th>الحدث</th><th>الوقت</th><th>التفاصيل</th></tr>
              </thead>
              <tbody>
                {audit.map((event) => (
                  <tr key={event.id}>
                    <td>{event.event_type}</td>
                    <td>{new Date(event.created_at).toLocaleString('ar-EG')}</td>
                    <td><code>{JSON.stringify(event.payload)}</code></td>
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
