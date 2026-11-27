import Link from 'next/link';
import { EmptyState, PageHeader, Section } from '@/shared/ui';
import { createClient } from '@/shared/supabase/server';
import { inviteToken } from '@/features/invites/schema';
import { inviteStatusLabel } from '@/features/invites/labels';
import { AcceptInviteForm } from './page-form';

export const dynamic = 'force-dynamic';

type InvitePreview = {
  organization_name: string;
  invite_status: 'PENDING' | 'ACCEPTED' | 'REVOKED' | 'EXPIRED';
};

/**
 * قبول دعوة عضوية منظمة عبر رابط. الرابط وحده لا يكشف شيئًا لغير المسجّل:
 * الوكيل (proxy) يوجّه الزائر غير المسجّل إلى صفحة الدخول أولًا.
 */
export default async function InviteAcceptPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const parsed = inviteToken.safeParse(token);
  const supabase = await createClient();
  const { data } = parsed.success
    ? await supabase.rpc('preview_organization_invite', { p_token: parsed.data })
    : { data: null };
  const preview = (data?.[0] ?? null) as InvitePreview | null;

  if (!preview) {
    return (
      <section className="stack-lg">
        <PageHeader title="دعوة منظمة" description="تعذر العثور على هذه الدعوة." />
        <EmptyState
          title="الرابط غير صالح"
          description="تأكد من نسخ الرابط كاملًا، أو اطلب رابطًا جديدًا من مالك المنظمة."
          action={<Link className="button" href="/">العودة إلى الرئيسية</Link>}
        />
      </section>
    );
  }

  return (
    <section className="stack-lg">
      <PageHeader
        title="دعوة منظمة"
        description={`دعوة للانضمام إلى منظمة «${preview.organization_name}» كعضو.`}
      />
      <Section title={preview.organization_name} description={`حالة الدعوة: ${inviteStatusLabel(preview.invite_status)}`}>
        {preview.invite_status === 'PENDING' ? (
          <AcceptInviteForm token={parsed.success ? parsed.data : ''} />
        ) : (
          <p className="muted">
            {preview.invite_status === 'ACCEPTED'
              ? 'استُخدمت هذه الدعوة بالفعل. إن كنت أنت من قبلها فستجد المنظمة في قائمتك.'
              : 'هذه الدعوة لم تعد صالحة. اطلب رابطًا جديدًا من مالك المنظمة.'}
          </p>
        )}
        <p className="muted"><Link href="/">العودة إلى الرئيسية</Link></p>
      </Section>
    </section>
  );
}
