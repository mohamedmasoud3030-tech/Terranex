import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import {
  getActiveVersion,
  getCapitalCallLines,
  getCapitalCalls,
  getCommitments,
  getContributions,
  getParticipants,
  getPartnerCapitalPositions,
  getProjectCapitalPosition,
} from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';
import { newCommandNonce } from '@/shared/idempotency';
import { WorkspaceChrome } from '@/features/workspace/chrome';
import { EmptyState, SectionTabs } from '@/shared/ui';
import { CapitalCallForm, ContributionForm } from './forms';

export const dynamic = 'force-dynamic';

export default async function FundingPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [activeVersion, participants, position, calls, contributions] = await Promise.all([
    getActiveVersion(projectId),
    getParticipants(projectId),
    getProjectCapitalPosition(projectId),
    getCapitalCalls(projectId),
    getContributions(projectId),
  ]);
  const lines = await getCapitalCallLines(calls.map((call) => call.id));
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const partnerPositions = activeVersion ? await getPartnerCapitalPositions(activeVersion.id) : [];
  const participantName = new Map(participants.map((participant) => [participant.id, participant.parties.legal_name]));
  const capitalCallCommandNonce = newCommandNonce();
  const contributionCommandNonce = newCommandNonce();

  if (!activeVersion) {
    return (
      <section className="stack">
        <WorkspaceChrome
          projectId={projectId}
          active="capital"
          title="رأس المال"
          subtitle={project.name}
          internalReference={project.internal_reference}
        />
        <SectionTabs
          label="رأس المال"
          items={[
            { href: `/projects/${projectId}/funding`, label: 'التمويل ورأس المال', current: true },
            { href: `/projects/${projectId}/terms`, label: 'الشروط والاتفاقية' },
          ]}
        />
        <EmptyState
          title="لا توجد اتفاقية مفعّلة بعد"
          description="فعّل الشروط أولًا لتتمكن من طلب رأس المال واستلام المساهمات."
          action={<Link className="button" href={`/projects/${projectId}/terms`}>إدارة الشروط والاتفاقية</Link>}
        />
      </section>
    );
  }

  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="capital"
        title="التمويل ورأس المال"
        subtitle={`${project.name} · النسخة الحاكمة ${activeVersion.version_no} · سارية من ${activeVersion.effective_date}`}
        internalReference={project.internal_reference}
      />
      <SectionTabs
        label="رأس المال"
        items={[
          { href: `/projects/${projectId}/funding`, label: 'التمويل ورأس المال', current: true },
          { href: `/projects/${projectId}/terms`, label: 'الشروط والاتفاقية' },
        ]}
      />

      <section className="card stack">
        <h2>الموقف الرأسمالي للمشروع</h2>
        <div className="grid">
          <Metric label="الالتزام" value={formatMinorUnits(position?.committed_minor_units ?? '0', project.reporting_currency)} />
          <Metric label="المطلوب" value={formatMinorUnits(position?.called_minor_units ?? '0', project.reporting_currency)} />
          <Metric label="المستلم" value={formatMinorUnits(position?.contributed_minor_units ?? '0', project.reporting_currency)} />
          <Metric label="المتبقي استلامه" value={formatMinorUnits(position?.receivable_minor_units ?? '0', project.reporting_currency)} />
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>المستثمر</th><th>الالتزام</th><th>المطلوب</th><th>المستلم</th><th>المتبقي</th></tr></thead>
            <tbody>
              {partnerPositions.map((partner) => (
                <tr key={partner.participant_id}>
                  <td>{participantName.get(partner.participant_id) ?? '—'}</td>
                  <td>{formatMinorUnits(partner.commitment_minor_units, partner.currency)}</td>
                  <td>{formatMinorUnits(partner.called_minor_units, partner.currency)}</td>
                  <td>{formatMinorUnits(partner.contributed_minor_units, partner.currency)}</td>
                  <td>{formatMinorUnits(partner.receivable_minor_units, partner.currency)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="muted">هذه الأرقام مشتقة من السجلات المعتمدة ولا يمكن تعديلها يدويًا.</p>
      </section>

      <section className="card stack">
        <h2>إصدار طلب رأس مال</h2>
        <CapitalCallForm
          organizationId={organizationId}
          projectId={projectId}
          versionId={activeVersion.id}
          currency={project.reporting_currency}
          participants={participants}
          commitments={commitments}
          serverNonce={capitalCallCommandNonce}
        />
      </section>

      <section className="card stack">
        <h2>طلبات رأس المال</h2>
        {calls.length === 0 ? (
          <p className="muted">لا توجد طلبات بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>المرجع</th><th>تاريخ الاستحقاق</th><th>الحالة</th><th>البنود</th></tr></thead>
              <tbody>
                {calls.map((call) => (
                  <tr key={call.id}>
                    <td>{call.reference || '—'}</td>
                    <td>{call.due_date}</td>
                    <td><span className="status">{call.status === 'ISSUED' ? 'مُصدر' : 'ملغى'}</span></td>
                    <td>
                      <ul>
                        {lines.filter((line) => line.capital_call_id === call.id).map((line) => (
                          <li key={line.id}>
                            {participantName.get(line.participant_id) ?? '—'}: {formatMinorUnits(line.amount_minor_units, line.currency)}
                          </li>
                        ))}
                      </ul>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="card stack">
        <h2>تسجيل مساهمة</h2>
        <ContributionForm
          organizationId={organizationId}
          projectId={projectId}
          versionId={activeVersion.id}
          currency={project.reporting_currency}
          calls={calls}
          lines={lines}
          participants={participants}
          serverNonce={contributionCommandNonce}
        />
      </section>

      <section className="card stack">
        <h2>سجل المساهمات</h2>
        {contributions.length === 0 ? (
          <p className="muted">لا توجد مساهمات بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>التاريخ</th><th>المستثمر</th><th>الطلب</th><th>المبلغ</th><th>النسخة الحاكمة</th></tr></thead>
              <tbody>
                {contributions.map((contribution) => {
                  const call = calls.find((item) => item.id === contribution.capital_call_id);
                  return (
                    <tr key={contribution.id}>
                      <td>{contribution.occurred_on}</td>
                      <td>{participantName.get(contribution.participant_id) ?? '—'}</td>
                      <td>{call?.reference || contribution.capital_call_id.slice(0, 8)}</td>
                      <td>{formatMinorUnits(contribution.contribution_minor_units, contribution.currency)}</td>
                      <td>النسخة الحاكمة {activeVersion.version_no}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <p className="muted">تحتفظ كل مساهمة بالنسخة التي حكمتها وقت التسجيل.</p>
      </section>
    </section>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="muted">{label}</p>
      <strong style={{ fontSize: '1.4rem' }}>{value}</strong>
    </div>
  );
}
