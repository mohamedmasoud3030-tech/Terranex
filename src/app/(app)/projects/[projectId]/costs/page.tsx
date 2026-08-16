import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getParties } from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';
import {
  getAuditEvents,
  getCashAccountPositions,
  getCurrentMembership,
  getLedgerForObligation,
  getObligationPositions,
  getPaymentProposals,
} from '@/features/finance/queries';
import {
  getObligationAging,
  getObligationDue,
  getProjectMilestones,
} from '@/features/control/queries';
import { JournalTrace } from '@/features/finance/journal-trace';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import {
  AchieveMilestoneButton,
  ApprovePaymentProposalButton,
  AuthorizeObligationButton,
  DeleteDraftButton,
  MilestoneForm,
  ObligationForm,
  ObligationTermsForm,
  OpenDisputeForm,
  PaymentForm,
  ResolveDisputeForm,
  RetentionReleaseForm,
  ReverseBatchForm,
} from './forms';

export const dynamic = 'force-dynamic';

const TREATMENT_LABEL: Record<string, string> = {
  EXPENSE: 'مصروف',
  CAPITALIZABLE_WIP: 'أعمال تحت التطوير',
};

const AGING_LABEL: Record<string, string> = {
  NO_TERMS: 'بدون شروط',
  SETTLED: 'مسدد',
  NO_DUE_DATE: 'بدون تاريخ استحقاق',
  OVERDUE_1_30: 'متأخر 1–30 يومًا',
  OVERDUE_31_60: 'متأخر 31–60 يومًا',
  OVERDUE_61_90: 'متأخر 61–90 يومًا',
  OVERDUE_90_PLUS: 'متأخر أكثر من 90 يومًا',
  DUE_TODAY: 'مستحق اليوم',
  NOT_DUE: 'غير مستحق',
};

function stateLabel(obligation: {
  status: string;
  is_posted: boolean;
  is_reversed: boolean;
  paid_minor_units: string;
  amount_minor_units: string;
}): { label: string; tone: 'draft' | 'open' | 'paid' | 'reversed' } {
  if (obligation.is_reversed) return { label: 'معكوس', tone: 'reversed' };
  if (obligation.status === 'DRAFT') return { label: 'مسودة', tone: 'draft' };
  if (obligation.paid_minor_units === obligation.amount_minor_units) return { label: 'مسدد بالكامل', tone: 'paid' };
  return { label: 'معتمد', tone: 'open' };
}

export default async function CostsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [membership, parties, obligations, cashAccounts, paymentProposals, dueRows, agingRows, milestones] =
    await Promise.all([
      getCurrentMembership(organizationId),
      getParties(organizationId),
      getObligationPositions(projectId),
      getCashAccountPositions(projectId),
      getPaymentProposals(projectId),
      getObligationDue(projectId),
      getObligationAging(projectId),
      getProjectMilestones(projectId),
    ]);
  const isOwner = membership?.role === 'OWNER';
  const partyName = new Map(parties.map((party) => [party.id, party.legal_name]));
  const dueByObligation = new Map(dueRows.map((row) => [row.obligation_id, row]));

  const overdueTotal = agingRows
    .filter((row) => row.aging_bucket.startsWith('OVERDUE'))
    .reduce((sum, row) => sum + BigInt(row.overdue_outstanding_minor_units), 0n);
  const retentionHeld = agingRows.reduce(
    (sum, row) => sum + BigInt(row.retention_held_minor_units),
    0n,
  );
  const disputedCount = dueRows.filter((row) => row.is_disputed).length;

  const ledgerByObligation = new Map<string, Awaited<ReturnType<typeof getLedgerForObligation>>>();
  for (const obligation of obligations) {
    if (obligation.authorization_batch_id || obligation.status === 'DRAFT') {
      const lines = await getLedgerForObligation(obligation.obligation_id);
      if (lines.length > 0) ledgerByObligation.set(obligation.obligation_id, lines);
    }
  }
  const audit = await getAuditEvents(obligations.map((obligation) => obligation.obligation_id));

  const totalAmount = obligations.reduce((sum, o) => sum + BigInt(o.amount_minor_units), 0n);
  const totalPaid = obligations.reduce(
    (sum, o) => sum + (o.status === 'DRAFT' ? 0n : BigInt(o.paid_minor_units)),
    0n,
  );
  const outstanding = obligations.reduce(
    (sum, o) => sum + (o.status === 'DRAFT' || o.is_reversed ? 0n : BigInt(o.outstanding_minor_units)),
    0n,
  );

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="costs-cash"
        title="التكاليف والنقدية"
        subtitle={`${project.name} · ${project.reporting_currency}`}
        internalReference={project.internal_reference}
      />
      <nav className="context-nav">
        <Link href={`/projects/${projectId}/cash`}>النقدية والبنك</Link>
      </nav>

      <section className="grid">
        <div className="card">
          <p className="muted">إجمالي الالتزامات</p>
          <strong>{formatMinorUnits(totalAmount, project.reporting_currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">المسدد</p>
          <strong>{formatMinorUnits(totalPaid, project.reporting_currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">المتبقي المستحق</p>
          <strong>{formatMinorUnits(outstanding, project.reporting_currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">المتأخر عن الاستحقاق</p>
          <strong>{formatMinorUnits(overdueTotal, project.reporting_currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">حجز ضمان قائم</p>
          <strong>{formatMinorUnits(retentionHeld, project.reporting_currency)}</strong>
        </div>
        <div className="card">
          <p className="muted">التزامات متنازع عليها</p>
          <strong>{disputedCount}</strong>
        </div>
      </section>

      <section className="card stack">
        <h2>تسجيل التزام جديد</h2>
        <ObligationForm
          organizationId={organizationId}
          projectId={projectId}
          currency={project.reporting_currency}
          parties={parties}
        />
      </section>

      <section className="card stack">
        <h2>التزامات المشروع</h2>
        {obligations.length === 0 ? (
          <p className="muted">لا توجد التزامات مسجلة بعد. سجّل أول التزام ثم اعتمده وادفعه من الحساب النقدي.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>المورد</th>
                  <th>الوصف</th>
                  <th>المعالجة</th>
                  <th>المبلغ</th>
                  <th>المتبقي</th>
                  <th>الاستحقاق</th>
                  <th>الحالة</th>
                  <th>الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {obligations.map((obligation) => {
                  const state = stateLabel(obligation);
                  const due = dueByObligation.get(obligation.obligation_id);
                  return (
                    <tr key={obligation.obligation_id} id={obligation.obligation_id}>
                      <td>{partyName.get(obligation.party_id) ?? '—'}</td>
                      <td>{obligation.description}</td>
                      <td>{TREATMENT_LABEL[obligation.cost_treatment] ?? obligation.cost_treatment}</td>
                      <td>{formatMinorUnits(obligation.amount_minor_units, obligation.currency)}</td>
                      <td>{formatMinorUnits(obligation.outstanding_minor_units, obligation.currency)}</td>
                      <td>
                        <div className="stack" style={{ gap: 4 }}>
                          {due ? (
                            <>
                              <span className="status">{AGING_LABEL[due.aging_bucket] ?? due.aging_bucket}</span>
                              {due.due_date ? <small>{due.due_date}</small> : null}
                              {due.is_disputed ? <small className="error">نزاع مفتوح — الدفع محظور</small> : null}
                              {BigInt(due.retention_remaining_minor_units) > 0n ? (
                                <small>حجز ضمان قائم: {formatMinorUnits(due.retention_remaining_minor_units, due.currency)}</small>
                              ) : null}
                            </>
                          ) : (
                            <span className="muted">—</span>
                          )}
                        </div>
                      </td>
                      <td><span className="status">{state.label}</span></td>
                      <td>
                        <div className="stack" style={{ gap: 8 }}>
                          {obligation.status === 'DRAFT' && isOwner && obligation.authorization_batch_id === null && (
                            <AuthorizeObligationButton
                              organizationId={organizationId}
                              projectId={projectId}
                              obligationId={obligation.obligation_id}
                            />
                          )}
                          {obligation.status === 'DRAFT' && (
                            <DeleteDraftButton
                              organizationId={organizationId}
                              projectId={projectId}
                              obligationId={obligation.obligation_id}
                            />
                          )}
                          {obligation.status === 'DRAFT' && (
                            <details className="stack">
                              <summary>شروط الدفع والجدولة</summary>
                              <ObligationTermsForm
                                organizationId={organizationId}
                                projectId={projectId}
                                obligationId={obligation.obligation_id}
                                currency={obligation.currency}
                              />
                            </details>
                          )}
                          {obligation.status === 'AUTHORIZED' && !obligation.is_reversed && due && (
                            <>
                              {due.is_disputed ? (
                                <details className="stack">
                                  <summary>تسوية النزاع المفتوح</summary>
                                  <ResolveDisputeForm
                                    organizationId={organizationId}
                                    projectId={projectId}
                                    disputeId={due.open_dispute_id as string}
                                  />
                                </details>
                              ) : (
                                <details className="stack">
                                  <summary>فتح نزاع</summary>
                                  <OpenDisputeForm
                                    organizationId={organizationId}
                                    projectId={projectId}
                                    obligationId={obligation.obligation_id}
                                  />
                                </details>
                              )}
                              {BigInt(due.retention_remaining_minor_units) > 0n && isOwner && (
                                <details className="stack">
                                  <summary>الإفراج عن حجز الضمان</summary>
                                  <RetentionReleaseForm
                                    organizationId={organizationId}
                                    projectId={projectId}
                                    obligationId={obligation.obligation_id}
                                    currency={obligation.currency}
                                    milestones={milestones.map((m) => ({
                                      milestone_id: m.milestone_id,
                                      code: m.code,
                                      label_ar: m.label_ar,
                                      status: m.status,
                                    }))}
                                  />
                                </details>
                              )}
                            </>
                          )}
                          {obligation.status === 'AUTHORIZED' && !obligation.is_reversed
                            && obligation.outstanding_minor_units !== '0' && (
                            <details className="stack">
                              <summary>إعداد مقترح دفع</summary>
                              <PaymentForm
                                organizationId={organizationId}
                                projectId={projectId}
                                obligationId={obligation.obligation_id}
                                currency={obligation.currency}
                                outstandingMinorUnits={obligation.outstanding_minor_units}
                                cashAccounts={cashAccounts}
                              />
                            </details>
                          )}
                          {paymentProposals.filter((proposal) => proposal.obligation_id === obligation.obligation_id
                            && proposal.status === 'PROPOSED').map((proposal) => (
                            <div className="stack" key={proposal.payment_proposal_id}>
                              <span className="status">مقترح دفع بانتظار معتمد مستقل</span>
                              <small>{formatMinorUnits(proposal.amount_minor_units, proposal.currency)} · {proposal.cash_account_name} · {proposal.payment_date}</small>
                              {isOwner && membership?.user_id !== proposal.prepared_by ? (
                                <ApprovePaymentProposalButton
                                  organizationId={organizationId}
                                  projectId={projectId}
                                  paymentProposalId={proposal.payment_proposal_id}
                                />
                              ) : (
                                <small className="muted">لا يجوز للمُعدّ اعتماد مقترحه؛ يلزم مالك مختلف.</small>
                              )}
                            </div>
                          ))}
                          {obligation.is_posted && !obligation.is_reversed && isOwner && obligation.authorization_batch_id && (
                            <details className="stack">
                              <summary>عكس القيد</summary>
                              <ReverseBatchForm
                                organizationId={organizationId}
                                projectId={projectId}
                                batchId={obligation.authorization_batch_id}
                                label="عكس اعتماد الالتزام"
                              />
                            </details>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack">
        <h2>إنجازات المشروع التعاقدية</h2>
        {milestones.length === 0 ? (
          <p className="muted">لا توجد إنجازات مسجلة. تُستخدم لجدولة الدفعات وربط الإفراج عن الحجز.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>الرمز</th>
                  <th>الوصف</th>
                  <th>التاريخ المخطط</th>
                  <th>الحالة</th>
                  <th>تاريخ الإنجاز</th>
                  <th>بنود جدولة مرتبطة</th>
                  <th>الإجراء</th>
                </tr>
              </thead>
              <tbody>
                {milestones.map((milestone) => (
                  <tr key={milestone.milestone_id}>
                    <td>{milestone.code}</td>
                    <td>{milestone.label_ar}</td>
                    <td>{milestone.planned_date ?? '—'}</td>
                    <td><span className="status">{milestone.status === 'ACHIEVED' ? 'محقق' : 'قيد التنفيذ'}</span></td>
                    <td>{milestone.achieved_date ?? '—'}</td>
                    <td>{milestone.linked_schedule_lines}</td>
                    <td>
                      {milestone.status === 'PENDING' ? (
                        <AchieveMilestoneButton
                          organizationId={organizationId}
                          projectId={projectId}
                          milestoneId={milestone.milestone_id}
                        />
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <MilestoneForm organizationId={organizationId} projectId={projectId} />
      </section>

      <section className="card stack">
        <h2>الأثر المحاسبي ومصدر القيد</h2>
        {obligations.length === 0 ? (
          <p className="muted">لا توجد قيود بعد.</p>
        ) : (
          obligations.map((obligation) => {
            const lines = ledgerByObligation.get(obligation.obligation_id);
            if (!lines || lines.length === 0) {
              return (
                <details key={obligation.obligation_id} className="stack">
                  <summary>{obligation.description} — لم يُرحَّل قيد بعد</summary>
                </details>
              );
            }
            return (
              <details key={obligation.obligation_id} className="stack">
                <summary>{obligation.description}</summary>
                <JournalTrace lines={lines} />
              </details>
            );
          })
        )}
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
