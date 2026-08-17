import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getActiveOrganization } from '@/features/organizations/context';
import { getOrganizationMembers } from '@/features/portfolios/queries';
import { newCommandNonce } from '@/shared/idempotency';
import { memberDisplayLabel } from '@/features/workspace/chrome';
import { PortfolioForm } from '../forms';

export const dynamic = 'force-dynamic';

export default async function NewPortfolioPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) redirect('/onboarding');
  const members = await getOrganizationMembers(org.id);
  const memberOptions = members.map((m, index) => ({
    user_id: m.user_id,
    label: memberDisplayLabel(m.role, index),
  }));

  return (
    <section className="card stack" style={{ maxWidth: 640 }}>
      <div>
        <Link className="muted" href="/portfolios">← المحافظ الاستثمارية</Link>
        <h1>إنشاء محفظة استثمارية</h1>
        <p className="muted">
          تُنشأ المحفظة بحالة «مسودة»، ولا تُسند إليها المشاريع إلا بعد تنشيطها. المحفظة
          إطار إداري فقط ولا تنشئ أي حقوق ملكية أو أموال مجمعة.
        </p>
      </div>
      <PortfolioForm
        organizationId={org.id}
        commandNonce={newCommandNonce()}
        members={memberOptions}
      />
    </section>
  );
}
