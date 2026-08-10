import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getOrganizations } from '@/features/organizations/queries';
import {
  getActiveVersion,
  getCommitments,
  getParticipants,
  getParties,
  getVersions,
} from '@/features/funding/queries';
import { formatMinorUnits } from '@/features/funding/money';
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
  const orgs = await getOrganizations();
  const organizationId = orgs[0]?.id;
  if (!organizationId) notFound();

  const [parties, participants, activeVersion, versions] = await Promise.all([
    getParties(organizationId),
    getParticipants(projectId),
    getActiveVersion(projectId),
    getVersions(projectId),
  ]);
  const commitments = activeVersion ? await getCommitments(activeVersion.id) : [];
  const participantName = new Map(participants.map((p) => [p.id, p.parties.legal_name]));

  return (
    <section className="stack">
      <div className="top">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>
            ← العودة للمشروع
          </Link>
          <h1>الشروط والاتفاقية</h1>
          <p className="muted">{project.name}</p>
        </div>
      </div>

      <section className="card stack">
        <h2>الأطراف والمشاركون</h2>
        {parties.length === 0 ? (
          <p className="muted">لا توجد أطراف بعد. أضف الطرف المستثمر الأول.</p>
        ) : (
          <ul>
            {parties.map((party) => (
              <li key={party.id}>
                {party.legal_name}{' '}
                <span className="muted">
                  ({party.party_type === 'PERSON' ? 'فرد' : 'منظمة'})
                </span>
              </li>
            ))}
          </ul>
        )}
        <details className="stack">
          <summary>إضافة طرف</summary>
          <CreatePartyForm organizationId={organizationId} />
        </details>
        {parties.length > 0 && participants.length === 0 && (
          <details className="stack" open>
            <summary>إضافة مشارك في المشروع</summary>
            <AddParticipantForm
              organizationId={organizationId}
              projectId={projectId}
              parties={parties}
            />
          </details>
        )}
        {participants.length > 0 && (
          <>
            <h3>مشاركو المشروع</h3>
            <ul>
              {participants.map((p) => (
                <li key={p.id}>
                  {p.parties.legal_name} <span className="muted">— مستثمر</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>

      {activeVersion ? (
        <section className="card stack">
          <h2>الاتفاقية المفعّلة</h2>
          <p>
            <span className="status">نسخة {activeVersion.version_no} · مفعّلة</span>
          </p>
          <p className="muted">
            سارية من {activeVersion.effective_date}. بصمة الشروط:{' '}
            <code>{activeVersion.terms_hash.slice(0, 16)}…</code>
          </p>
          <table>
            <thead>
              <tr>
                <th>المشارك</th>
                <th>الالتزام</th>
              </tr>
            </thead>
            <tbody>
              {commitments.map((c) => (
                <tr key={c.id}>
                  <td>{participantName.get(c.participant_id) ?? '—'}</td>
                  <td>{formatMinorUnits(c.commitment_minor_units, c.currency)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="muted">
            النسخة المفعّلة غير قابلة للتعديل. أي تغيير يتطلب نسخة جديدة وتفعيلًا لاحقًا.
          </p>
        </section>
      ) : (
        <section className="card stack">
          <h2>مسودة الاتفاقية</h2>
          {participants.length === 0 ? (
            <p className="muted">أضف مشاركًا واحدًا على الأقل قبل إنشاء مسودة الاتفاقية.</p>
          ) : (
            <AgreementDraftForm
              organizationId={organizationId}
              projectId={projectId}
              participants={participants}
              currency={project.reporting_currency}
            />
          )}
          {versions.length > 0 && (
            <div>
              <h3>المسودات السابقة</h3>
              <ul>
                {versions
                  .filter((v) => v.status === 'DRAFT')
                  .map((v) => (
                    <li key={v.id}>
                      نسخة {v.version_no} — {v.effective_date}{' '}
                      <ActivateVersionButton organizationId={organizationId} versionId={v.id} />
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
