import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject } from '@/features/projects/queries';
import { getCurrentMembership } from '@/features/finance/queries';
import { getActiveVersion, getParticipants } from '@/features/funding/queries';
import { getPartnerCapitalStatement } from '@/features/allocation/queries';
import { formatMinorUnits } from '@/shared/money';
import { WorkspaceNav } from '@/features/workspace/nav';

export const dynamic = 'force-dynamic';

export default async function StatementsPage({ params }: { params: Promise<{ projectId: string }> }) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project) notFound();
  const organizationId = project.organization_id;
  const currency = project.reporting_currency;

  const [membership, activeVersion, participants, statements] = await Promise.all([
    getCurrentMembership(organizationId),
    getActiveVersion(projectId),
    getParticipants(projectId),
    getPartnerCapitalStatement(projectId),
  ]);

  if (!membership) {
    return (
      <section className="card">
        <h1>غير مصرح</h1>
        <p className="error">عضويتك الحالية لا تسمح بقراءة كشوف الشركاء لهذا المشروع.</p>
        <Link className="button" href={`/projects/${projectId}`}>العودة للمشروع</Link>
      </section>
    );
  }

  const participantName = new Map(
    participants.map((participant) => [participant.party_id, participant.parties.legal_name]),
  );

  return (
    <section className="stack">
      <header className="project-context card">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <h1>كشوف الشركاء</h1>
          <p className="muted">
            {project.name} · {currency}
            {activeVersion ? ` · النسخة الحاكمة ${activeVersion.version_no}` : ' · لا توجد اتفاقية مفعّلة'}
          </p>
        </div>
      </header>

      <WorkspaceNav projectId={projectId} active="statements" />

      {statements.length === 0 ? (
        <section className="card stack">
          <h2>لا توجد بيانات كشوف بعد</h2>
          <p className="muted">
            تُشتق الكشوف من وقائع مسجّلة (المساهمات، التخصيصات، التوزيعات) عبر قراءة رسمية موثوقة.
            لا تُحسب في المتصفح أبدًا.
          </p>
          <nav className="context-nav">
            <Link href={`/projects/${projectId}/funding`}>رأس المال والمساهمات</Link>
            <Link href={`/projects/${projectId}/close`}>الإغلاق والتوزيع</Link>
          </nav>
        </section>
      ) : (
        <section className="card stack">
          <h2>كشف رأس مال الشركاء</h2>
          <p className="muted">
            لكل شريك: رأس المال الافتتاحي ← المساهمات ← التخصيصات (دخل/خسارة) ← التوزيعات ← رأس المال الختامي.
            جميع الأرقام من القراءة الرسمية <code>s5_partner_capital_statement_read</code>.
          </p>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>الشريك</th>
                  <th>رأس المال الافتتاحي</th>
                  <th>المساهمات</th>
                  <th>دخل مخصص</th>
                  <th>خسارة مخصصة</th>
                  <th>توزيعات معتمدة</th>
                  <th>توزيعات مدفوعة</th>
                  <th>رأس المال الختامي</th>
                </tr>
              </thead>
              <tbody>
                {statements.map((statement) => (
                  <tr key={statement.participant_party_id}>
                    <td>{statement.legal_name || participantName.get(statement.participant_party_id) || 'شريك'}</td>
                    <td>{formatMinorUnits(statement.opening_capital_minor_units, statement.currency)}</td>
                    <td>{formatMinorUnits(statement.contributions_minor_units, statement.currency)}</td>
                    <td>{formatMinorUnits(statement.allocated_income_minor_units, statement.currency)}</td>
                    <td>{formatMinorUnits(statement.allocated_loss_minor_units, statement.currency)}</td>
                    <td>{formatMinorUnits(statement.approved_distributions_minor_units, statement.currency)}</td>
                    <td>{formatMinorUnits(statement.paid_distributions_minor_units, statement.currency)}</td>
                    <td><strong>{formatMinorUnits(statement.closing_capital_minor_units, statement.currency)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted">
            هذه قراءة إعلامية. لإصدار قرار تخصيص/توزيع جديد انتقل إلى{' '}
            <Link href={`/projects/${projectId}/close`}>الإغلاق والتوزيع</Link>.
          </p>
        </section>
      )}
    </section>
  );
}
