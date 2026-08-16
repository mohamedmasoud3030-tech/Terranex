import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import {
  getActiveVersion,
  getCommitments,
  getParticipants,
  getParties,
  getVersions,
} from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';
import { newCommandNonce } from '@/shared/idempotency';
import {
  ActivateVersionButton,
  AgreementDraftForm,
  AddParticipantForm,
  CreatePartyForm,
} from './forms';

export const dynamic = 'force-dynamic';

export default async function TermsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;

  const [parties, participants, activeVersion, versions] = await Promise.all([
    getParties(organizationId),
    getParticipants(projectId),
    getActiveVersion(projectId),
    getVersions(projectId),
  ]);
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const participantName = new Map(participants.map((participant) => [participant.id, participant.parties.legal_name]));
  const participantPartyIds = new Set(participants.map((participant) => participant.party_id));
  const eligibleParties = parties.filter((party) => !participantPartyIds.has(party.id));
  const draftVersions = versions.filter((version) => version.status === 'DRAFT');
  const agreementCommandNonce = newCommandNonce();

  return (
    <section className="stack">
      <div className="top">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← العودة للمشروع</Link>
          <h1>الشروط والاتفاقية</h1>
          <p className="muted">{project.name}</p>
        </div>
      </div>

      <section className="card stack">
        <h2>الأطراف والمشاركون</h2>
        {participants.length === 0 ? (
          <p className="muted">لم يُضف مستثمرون للمشروع بعد.</p>
        ) : (
          <ul>
            {participants.map((participant) => (
              <li key={participant.id}>
                {participant.parties.legal_name} <span className="muted">— مستثمر</span>
              </li>
            ))}
          </ul>
        )}
        {!activeVersion && (
          <>
            <details className="stack">
              <summary>إضافة طرف جديد</summary>
              <CreatePartyForm organizationId={organizationId} projectId={projectId} />
            </details>
            {eligibleParties.length > 0 && (
              <details className="stack" open={participants.length === 0}>
                <summary>إضافة طرف كمستثمر في المشروع</summary>
                <AddParticipantForm organizationId={organizationId} projectId={projectId} parties={eligibleParties} />
              </details>
            )}
          </>
        )}
      </section>

      {activeVersion ? (
        <section className="card stack">
          <h2>الاتفاقية الحاكمة</h2>
          <p><span className="status">نسخة {activeVersion.version_no} · مفعّلة</span></p>
          <p className="muted">
            سارية من {activeVersion.effective_date}. بصمة الشروط:{' '}
            <code>{activeVersion.terms_hash.slice(0, 16)}…</code>
          </p>
          <div className="table-wrap">
            <table>
              <thead><tr><th>المشارك</th><th>الالتزام</th></tr></thead>
              <tbody>
                {commitments.map((commitment) => (
                  <tr key={commitment.id}>
                    <td>{participantName.get(commitment.participant_id) ?? '—'}</td>
                    <td>{formatMinorUnits(commitment.commitment_minor_units, commitment.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            هذه النسخة وشروط الالتزام غير قابلة للتعديل. مسار تعديل الاتفاقية وترحيل أثر التمويل مؤجل لمرحلة مستقلة؛ النسخة الحالية تظل الحاكمة.
          </p>
        </section>
      ) : (
        <section className="card stack">
          <h2>مسودة الاتفاقية</h2>
          {participants.length === 0 ? (
            <p className="muted">أضف مستثمرًا واحدًا على الأقل قبل إنشاء مسودة الاتفاقية.</p>
          ) : (
            <AgreementDraftForm
              organizationId={organizationId}
              projectId={projectId}
              participants={participants}
              currency={project.reporting_currency}
              serverNonce={agreementCommandNonce}
            />
          )}
          {draftVersions.length > 0 && (
            <div className="stack">
              <h3>المسودات المحفوظة</h3>
              <ul>
                {draftVersions.map((version) => (
                  <li key={version.id}>
                    نسخة {version.version_no} — {version.effective_date}{' '}
                    <ActivateVersionButton
                      organizationId={organizationId}
                      projectId={projectId}
                      versionId={version.id}
                    />
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}
    </section>
  );
}
