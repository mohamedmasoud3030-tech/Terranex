import Link from 'next/link';
import { EmptyState, PageHeader, Section } from '@/shared/ui';
import { getActiveOrganization } from '@/features/organizations/context';
import { getProjects } from '@/features/projects/queries';
import {
  getOwnerBankSuggestions,
  getOwnerCashPositions,
  getOwnerOverdueObligations,
  getOwnerWeeklyCash,
} from '@/features/owner-insights/queries';
import { buildAskAnswers, type AskTone } from '@/features/owner-insights/ask';

export const dynamic = 'force-dynamic';

const TONE_LABEL: Record<AskTone, string> = {
  good: 'تمام',
  warn: 'محتاج نظرة',
  bad: 'متأخر',
  neutral: 'معلومة',
};

/** اسأل أرقامك: أسئلة ثابتة بالعربي البسيط، إجابتها محسوبة من الدفاتر مباشرة. */
export default async function OwnerAskPage() {
  const { organization: org } = await getActiveOrganization();
  if (!org) {
    return (
      <EmptyState
        title="لنبدأ بإنشاء منظمتك"
        description="الأسئلة بتتجاوب بعد إنشاء منظمة ومشروع."
        action={<Link className="button" href="/onboarding">إنشاء منظمة</Link>}
      />
    );
  }
  const today = new Date().toISOString().slice(0, 10);
  const [weeklyCash, overdue, suggestions, cashPositions, projects] = await Promise.all([
    getOwnerWeeklyCash(org.id),
    getOwnerOverdueObligations(org.id),
    getOwnerBankSuggestions(org.id),
    getOwnerCashPositions(org.id),
    getProjects(org.id),
  ]);
  const projectNames = new Map(projects.map((p) => [p.id, p.name]));
  const answers = buildAskAnswers({
    today,
    weeklyCash,
    overdue,
    suggestions,
    cashPositions,
    projectName: (id) => projectNames.get(id) ?? 'مشروع غير معروف',
  });

  return (
    <section className="stack-lg">
      <PageHeader
        eyebrow={org.name}
        title="اسأل أرقامك"
        description="أسئلة جاهزة بإجابات محسوبة من دفاترك في اللحظة دي. مفيش ذكاء اصطناعي خارجي، الأرقام كلها من قاعدة بياناتك."
        actions={<Link className="button secondary sm" href="/owner">الملخص الأسبوعي</Link>}
      />
      {answers.map((answer) => (
        <Section key={answer.id} title={answer.question} description={TONE_LABEL[answer.tone]}>
          <div className="stack">
            {answer.lines.map((line, index) => (
              <p key={index}>{line}</p>
            ))}
            {answer.href ? (
              <p>
                <Link className="button secondary sm" href={answer.href}>{answer.hrefLabel ?? 'التفاصيل'}</Link>
              </p>
            ) : null}
          </div>
        </Section>
      ))}
    </section>
  );
}
