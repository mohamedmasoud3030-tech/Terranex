import Link from 'next/link';
import { WorkspaceNav, type WorkspaceSection } from './nav';

export function DemoBanner({ internalReference }: { internalReference: string | null | undefined }) {
  if (!internalReference?.startsWith('DEMO')) return null;
  return (
    <div className="banner info" role="note">
      هذا المشروع ({internalReference}) بيانات توضيحية اصطناعية ثابتة. تُستخدم للمعاينة والتدريب
      والتحقق، ولا تُحتسب كدليل عميل حقيقي أو إغلاق لأي بوابة مرحلَة ثانية أو ثالثة.
    </div>
  );
}

export function WorkspaceChrome({
  projectId,
  active,
  title,
  subtitle,
  internalReference,
}: {
  projectId: string;
  active: WorkspaceSection;
  title: string;
  subtitle?: string;
  internalReference?: string | null;
}) {
  return (
    <>
      <header className="project-context card">
        <div>
          <Link className="muted" href={`/projects/${projectId}`}>← مساحة المشروع</Link>
          <h1>{title}</h1>
          {subtitle ? <p className="muted">{subtitle}</p> : null}
        </div>
      </header>
      <DemoBanner internalReference={internalReference} />
      <WorkspaceNav projectId={projectId} active={active} />
    </>
  );
}

export function ForbiddenCard({ projectId, message }: { projectId: string; message: string }) {
  return (
    <section className="card">
      <h1>غير مصرح</h1>
      <p className="error">{message}</p>
      <Link className="button" href={`/projects/${projectId}`}>العودة للمشروع</Link>
    </section>
  );
}

export function memberDisplayLabel(role: string, index: number) {
  const rank = index + 1;
  return role === 'OWNER' ? `مالك المنظمة ${rank}` : `عضو تشغيلي ${rank}`;
}
