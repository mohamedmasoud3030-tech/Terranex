import { notFound } from 'next/navigation';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  COHORT_STATE_LABEL,
  ORIGIN_LABEL,
  PURPOSE_LABEL,
  SITE_TYPE_LABEL,
  SPECIES_LABEL,
  WEIGHT_BASIS_LABEL,
} from '@/features/livestock/labels';
import {
  type CohortRead,
  type CohortTimelineRead,
  type HerdRead,
  type SiteRead,
  getLivestockCohorts,
  getLivestockCohortTimeline,
  getLivestockHerds,
  getLivestockSites,
} from '@/features/livestock/queries';
import { getProject } from '@/features/projects/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import { ActivateForm, CohortForm, HerdForm, ProfileForm, SiteForm } from './forms';

export const dynamic = 'force-dynamic';

const NO_LOCATION_DESCRIPTION = 'لم يسجل وصف موقع';

function Sites({ sites }: Readonly<{ sites: readonly SiteRead[] }>) {
  if (sites.length === 0) return <p className="muted">لا توجد مواقع تشغيل بعد.</p>;
  return (
    <div className="responsive-grid">
      {sites.map((site) => (
        <article className="card" key={site.id}>
          <h3>{site.name}</h3>
          <p>{site.internal_reference} · {SITE_TYPE_LABEL[site.site_type]}</p>
          <p className="muted">{site.location_description ?? NO_LOCATION_DESCRIPTION}</p>
          <small>موقع تشغيل لا يثبت ملكية الأرض.</small>
        </article>
      ))}
    </div>
  );
}

function Herds({ herds }: Readonly<{ herds: readonly HerdRead[] }>) {
  if (herds.length === 0) return <p className="muted">لا توجد قطعان بعد.</p>;
  return (
    <div className="responsive-grid">
      {herds.map((herd) => (
        <article className="card" key={herd.id}>
          <h3>{herd.name}</h3>
          <p>
            {herd.internal_reference} · {SPECIES_LABEL[herd.species]} ·{' '}
            {PURPOSE_LABEL[herd.purpose]}
          </p>
          <small>مجموعة إدارية غير مرتبطة دائمًا بموقع.</small>
        </article>
      ))}
    </div>
  );
}

function OpeningWeight({ cohort }: Readonly<{ cohort: CohortRead }>) {
  if (!cohort.opening_weight_value) return <>غير مسجل</>;
  return (
    <>
      {cohort.opening_weight_value} كجم ·{' '}
      {WEIGHT_BASIS_LABEL[cohort.opening_weight_basis ?? '']}
    </>
  );
}

function CohortTimeline({
  cohortId,
  timeline,
}: Readonly<{ cohortId: string; timeline: readonly CohortTimelineRead[] }>) {
  const entries = [...timeline]
    .filter((entry) => entry.cohort_id === cohortId)
    .reverse();
  return (
    <details>
      <summary>سجل دورة الحياة</summary>
      <ol>
        {entries.map((entry) => (
          <li key={entry.id}>{COHORT_STATE_LABEL[entry.new_state]} · {entry.reason}</li>
        ))}
      </ol>
    </details>
  );
}

function CohortCard({
  cohort,
  timeline,
  organizationId,
  projectId,
}: Readonly<{
  cohort: CohortRead;
  timeline: readonly CohortTimelineRead[];
  organizationId: string;
  projectId: string;
}>) {
  return (
    <article className="card stack">
      <div>
        <h3>{cohort.cohort_reference}</h3>
        <span className="status">{COHORT_STATE_LABEL[cohort.lifecycle_state]}</span>
      </div>
      <dl className="facts">
        <div><dt>القطيع الإداري</dt><dd>{cohort.herd_name}</dd></div>
        <div><dt>موقع الوضع الافتتاحي</dt><dd>{cohort.initial_site_name}</dd></div>
        <div>
          <dt>النوع والغرض</dt>
          <dd>{SPECIES_LABEL[cohort.species]} · {PURPOSE_LABEL[cohort.purpose]}</dd>
        </div>
        <div><dt>مصدر الدفعة</dt><dd>{ORIGIN_LABEL[cohort.origin_type]}</dd></div>
        <div>
          <dt>تاريخ المصدر</dt>
          <dd>{new Date(cohort.origin_date).toLocaleDateString('ar-EG')}</dd>
        </div>
        <div><dt>العدد عند بداية الدفعة</dt><dd>{cohort.opening_headcount}</dd></div>
        <div><dt>أساس الوزن الافتتاحي</dt><dd><OpeningWeight cohort={cohort} /></dd></div>
      </dl>
      {cohort.lifecycle_state === 'PLANNED' ? (
        <ActivateForm
          organizationId={organizationId}
          projectId={projectId}
          cohort={cohort}
        />
      ) : null}
      <CohortTimeline cohortId={cohort.id} timeline={timeline} />
    </article>
  );
}

function Cohorts({
  cohorts,
  timeline,
  organizationId,
  projectId,
}: Readonly<{
  cohorts: readonly CohortRead[];
  timeline: readonly CohortTimelineRead[];
  organizationId: string;
  projectId: string;
}>) {
  if (cohorts.length === 0) {
    return <p className="muted">لا توجد دفعات بعد. أنشئ دفعة لتسجيل حقيقة العدد الافتتاحي.</p>;
  }
  return (
    <div className="responsive-grid">
      {cohorts.map((cohort) => (
        <CohortCard
          key={cohort.id}
          cohort={cohort}
          timeline={timeline}
          organizationId={organizationId}
          projectId={projectId}
        />
      ))}
    </div>
  );
}

export default async function LivestockPage({
  params,
}: Readonly<{ params: Promise<{ projectId: string }> }>) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (!project || project.sector !== 'LIVESTOCK') notFound();

  const [membership, sites, herds, cohorts, timeline] = await Promise.all([
    getCurrentMembership(project.organization_id),
    getLivestockSites(projectId),
    getLivestockHerds(projectId),
    getLivestockCohorts(projectId),
    getLivestockCohortTimeline(projectId),
  ]);
  if (!membership) {
    return (
      <ForbiddenCard
        projectId={projectId}
        message="عضويتك الحالية لا تسمح بقراءة مساحة الثروة الحيوانية."
      />
    );
  }

  const context = { organizationId: project.organization_id, projectId };
  return (
    <section className="stack">
      <WorkspaceChrome
        projectId={projectId}
        active="livestock"
        sector="LIVESTOCK"
        title="الثروة الحيوانية"
        subtitle={`${project.name} · المواقع والقطعان`}
        internalReference={project.internal_reference}
      />
      <header className="card">
        <h1>الثروة الحيوانية</h1>
        <p className="muted">
          المواقع والقطعان والدفعات · تتبع جماعي قابل للعد دون افتراض سجل فردي لكل حيوان.
        </p>
      </header>
      <section className="card stack">
        <h2>تهيئة القطاع</h2>
        <ProfileForm {...context} />
      </section>
      <section className="card stack">
        <h2>مواقع التشغيل</h2>
        <SiteForm {...context} />
        <Sites sites={sites} />
      </section>
      <section className="card stack">
        <h2>القطعان (المجموعات الإدارية)</h2>
        <HerdForm {...context} />
        <Herds herds={herds} />
      </section>
      <section className="card stack">
        <h2>الدفعات الحيوانية القابلة للعد</h2>
        <CohortForm {...context} herds={herds} sites={sites} />
        <Cohorts {...context} cohorts={cohorts} timeline={timeline} />
      </section>
      <aside className="banner">
        <strong>حدود هذه المرحلة:</strong> لا حيوانات فردية أو RFID أو صحة أو علف أو نفوق أو حركة أو بيع أو تقييم محاسبي. العدد المعروض هو عدد بداية الدفعة، وليس رصيدًا حاليًا. الموقع المعروض هو الوضع الافتتاحي وليس ادعاءً بالموقع الحالي.
      </aside>
    </section>
  );
}
