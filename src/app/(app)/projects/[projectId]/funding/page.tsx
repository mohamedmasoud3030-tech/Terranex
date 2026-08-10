import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getOrganizations } from '@/features/organizations/queries';
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
import { formatMinorUnits } from '@/features/funding/money';
import { CapitalCallForm, ContributionForm } from './forms';

export const dynamic = 'force-dynamic';

export default async function FundingPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const orgs = await getOrganizations();
  const organizationId = orgs[0]?.id;
  if (!organizationId) notFound();

  const [activeVersion, participants, position, calls, contributions] = await Promise.all([
    getActiveVersion(projectId),
    getParticipants(projectId),
    getProjectCapitalPosition(projectId),
    getCapitalCalls(projectId),
    getContributions(projectId),
  ]);
  const lines = await getCapitalCallLines(calls.map((c) => c.id));
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const partnerPositions = activeVersion
    ? await getPartnerCapitalPositions(activeVersion.id)
    : [];

  const participantName = new Map(participants.map((p) => [p.id, p.parties.legal_name]));
  const lineByCallAndParticipant = new Map(
    lines.map((l) => [`${l.capital_call_id}:${l.participant_id}`, l]),
  );

  if (!activeVersion) {
    return (
      <section className="stack">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>
            ← العودة للمشروع
          </Link>
          <h1>التمويل</h1>
        </div>
        <section className="card stack">
          <p>لا توجد اتفاقية مفعّلة بعد. فعّل الشروط أولًا لتتمكن من طلب رأس المال واستلام المساهمات.</p>
          <Link className="button" href={`/projects/${projectId}/terms`}>
            إدارة الشروط والاتفاقية
          </Link>
        </section>
      </section>
    );
  }

  return (
    <section className="stack">
      <div className="top">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>
            ← العودة للمشروع
          </Link>
          <h1>التمويل ورأس المال</h1>
          <p className="muted">
            النسخة المفعّلة {activeVersion.version_no} · سارية من {activeVersion.effective_date}
          </p>
        </div>
      </div>

      <section className="card stack">
        <h2>الموقف الرأسمالي للمشروع</h2>
        <div className="grid">
          <Metric label="الالتزام" value={formatMinorUnits(position?.committed_minor_units ?? 0, project.reporting_currency)} />
          <Metric label="المطلوب" value={formatMinorUnits(position?.called_minor_units ?? 0, project.reporting_currency)} />
          <Metric label="المستلم" value={formatMinorUnits(position?.contributed_minor_units ?? 0, project.reporting_currency)} />
          <Metric label="المتبقي استلامه" value={formatMinorUnits(position?.receivable_minor_units ?? 0, project.reporting_currency)} />
        </div>
        <table>
          <thead>
            <tr>
              <th>المستثمر</th>
              <th>الالتزام</th>
              <th>المطلوب</th>
              <th>المستلم</th>
              <th>المتبقي</th>
            </tr>
          </thead>
          <tbody>
            {partnerPositions.map((p) => (
              <tr key={p.participant_id}>
                <td>{participantName.get(p.participant_id) ?? '—'}</td>
                <td>{formatMinorUnits(p.commitment_minor_units, p.currency)}</td>
                <td>{formatMinorUnits(p.called_minor_units, p.currency)}</td>
                <td>{formatMinorUnits(p.contributed_minor_units, p.currency)}</td>
                <td>{formatMinorUnits(p.receivable_minor_units, p.currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="muted">
          هذه الأرقام مشتقة من السجلات المعتمدة ولا يمكن تعديلها يدويًا.
        </p>
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
        />
      </section>

      <section className="card stack">
        <h2>طلبات رأس المال</h2>
        {calls.length === 0 ? (
          <p className="muted">لا توجد طلبات بعد.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>المرجع</th>
                <th>تاريخ الاستحقاق</th>
                <th>الحالة</th>
                <th>البنود</th>
              </tr>
            </thead>
            <tbody>
              {calls.map((call) => (
                <tr key={call.id}>
                  <td>{call.reference || '—'}</td>
                  <td>{call.due_date}</td>
                  <td>
                    <span className="status">{call.status === 'ISSUED' ? 'مُصدر' : 'ملغى'}</span>
                  </td>
                  <td>
                    <ul>
                      {lines
                        .filter((l) => l.capital_call_id === call.id)
                        .map((l) => (
                          <li key={l.id}>
                            {participantName.get(l.participant_id) ?? '—'}:{' '}
                            {formatMinorUnits(l.amount_minor_units, l.currency)}
                          </li>
                        ))}
                    </ul>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
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
        />
      </section>

      <section className="card stack">
        <h2>سجل المساهمات</h2>
        {contributions.length === 0 ? (
          <p className="muted">لا توجد مساهمات بعد.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>التاريخ</th>
                <th>المستثمر</th>
                <th>الطلب</th>
                <th>المبلغ</th>
                <th>النسخة الحاكمة</th>
              </tr>
            </thead>
            <tbody>
              {contributions.map((c) => {
                const line = lineByCallAndParticipant.get(`${c.capital_call_id}:${c.participant_id}`);
                const call = calls.find((cc) => cc.id === c.capital_call_id);
                return (
                  <tr key={c.id}>
                    <td>{c.occurred_on}</td>
                    <td>{participantName.get(c.participant_id) ?? '—'}</td>
                    <td>{call?.reference || c.capital_call_id.slice(0, 8)}</td>
                    <td>{formatMinorUnits(c.contribution_minor_units, c.currency)}</td>
                    <td>
                      <code>{c.agreement_version_id.slice(0, 8)}</code>
                      {line ? '' : ''}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
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
