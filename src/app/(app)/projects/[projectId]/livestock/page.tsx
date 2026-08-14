import { notFound } from 'next/navigation';
import { getCurrentMembership } from '@/features/finance/queries';
import {
  COHORT_STATE_LABEL,
  MORTALITY_CAUSE_LABEL,
  OPERATION_TYPE_LABEL,
  ORIGIN_LABEL,
  PLACEMENT_SOURCE_LABEL,
  QUANTITY_EVENT_LABEL,
  PURPOSE_LABEL,
  SITE_TYPE_LABEL,
  SPECIES_LABEL,
  WEIGHT_BASIS_LABEL,
  WEIGHT_MEANING_LABEL,
  WEIGHT_METHOD_LABEL,
  movementChangeLabel,
} from '@/features/livestock/labels';
import {
  type CohortLineageRead,
  type CohortRead,
  type CohortTimelineRead,
  type CurrentPlacementRead,
  type HerdRead,
  type MovementRead,
  type QuantityEventRead,
  type QuantityRollforwardRead,
  type SiteRead,
  type WeightEventRead,
  getLivestockCohortLineage,
  getLivestockCohortTimeline,
  getLivestockCohorts,
  getLivestockCurrentPlacements,
  getLivestockHerds,
  getLivestockMovements,
  getLivestockQuantityEvents,
  getLivestockQuantityRollforward,
  getLivestockSites,
  getLivestockWeightEvents,
} from '@/features/livestock/queries';
import { getProject } from '@/features/projects/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import { newCommandNonce } from '@/features/livestock/idempotency';
import {
  ActivateForm,
  BirthForm,
  CohortForm,
  HerdForm,
  MergeForm,
  MortalityForm,
  MovementForm,
  ProfileForm,
  SiteForm,
  SplitForm,
  WeightEventForm,
} from './forms';

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
  commandNonce,
}: Readonly<{
  cohort: CohortRead;
  timeline: readonly CohortTimelineRead[];
  organizationId: string;
  projectId: string;
  commandNonce: string;
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
          commandNonce={commandNonce}
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
          commandNonce={newCommandNonce()}
        />
      ))}
    </div>
  );
}


function dateTime(value: string): string {
  return new Date(value).toLocaleString('ar-EG');
}

/** GF-021.B — derived current placement, never editable master data. */
function CurrentPlacements({
  placements,
  sites,
  herds,
  organizationId,
  projectId,
}: Readonly<{
  placements: readonly CurrentPlacementRead[];
  sites: readonly SiteRead[];
  herds: readonly HerdRead[];
  organizationId: string;
  projectId: string;
}>) {
  if (placements.length === 0) {
    return <p className="muted">لا توجد دفعات لعرض موقعها الحالي.</p>;
  }
  return (
    <div className="responsive-grid">
      {placements.map((placement) => (
        <article className="card stack" key={placement.cohort_id}>
          <h3>{placement.cohort_reference}</h3>
          <dl className="facts">
            <div>
              <dt>الموقع الحالي المشتق</dt>
              <dd>{placement.current_site_name}</dd>
            </div>
            <div>
              <dt>القطيع الحالي المشتق</dt>
              <dd>{placement.current_herd_name}</dd>
            </div>
            <div>
              <dt>مصدر الموقع الحالي</dt>
              <dd>{PLACEMENT_SOURCE_LABEL[placement.placement_source]}</dd>
            </div>
            <div>
              <dt>ساري من</dt>
              <dd>{dateTime(placement.effective_from)}</dd>
            </div>
          </dl>
          <small className="muted">
            حقيقة مشتقة من الوضع الافتتاحي وسلسلة الحركات، وليست بيانًا أساسيًا قابلًا للتحرير.
          </small>
          <details>
            <summary>نقل الدفعة</summary>
            <MovementForm
              organizationId={organizationId}
              projectId={projectId}
              commandNonce={newCommandNonce()}
              placement={placement}
              sites={sites}
              herds={herds}
            />
          </details>
        </article>
      ))}
    </div>
  );
}

/** GF-021.A — the immutable movement history. */
function Movements({ movements }: Readonly<{ movements: readonly MovementRead[] }>) {
  if (movements.length === 0) {
    return <p className="muted">لا توجد حركات مسجلة بعد. الموقع الحالي لكل دفعة هو وضعها الافتتاحي.</p>;
  }
  return (
    <ol className="stack">
      {movements.map((movement) => (
        <li key={movement.id}>
          <strong>{movement.cohort_reference}</strong> ·{' '}
          {movementChangeLabel(movement.site_changed, movement.herd_changed)}
          <p className="muted">
            من {movement.source_site_name} / {movement.source_herd_name} إلى{' '}
            {movement.destination_site_name} / {movement.destination_herd_name} ·{' '}
            {dateTime(movement.effective_at)}
          </p>
          <p className="muted">{movement.reason}</p>
        </li>
      ))}
    </ol>
  );
}

/**
 * GF-021.C / GF-022.G — the current operational headcount, derived exactly.
 *
 * The rollforward is shown in full so the operator can read the arithmetic:
 *   عدد افتتاحي + ولادات + وارد من تقسيم/دمج
 *   − نفوق − صادر إلى تقسيم/دمج = العدد الحالي
 *
 * This is an operational headcount, never an inventory valuation.
 */
function QuantityRollforward({
  rows,
}: Readonly<{ rows: readonly QuantityRollforwardRead[] }>) {
  if (rows.length === 0) return <p className="muted">لا توجد دفعات لعرض عددها.</p>;
  return (
    <table>
      <caption className="muted">
        العدد الحالي = عدد افتتاحي + ولادات + وارد من تقسيم/دمج − نفوق − صادر إلى تقسيم/دمج.
        رصيد تشغيلي بالعدد، وليس تقييمًا ماليًا للمخزون.
      </caption>
      <thead>
        <tr>
          <th scope="col">الدفعة</th>
          <th scope="col">عدد افتتاحي</th>
          <th scope="col">+ ولادات</th>
          <th scope="col">+ وارد من تقسيم</th>
          <th scope="col">+ وارد من دمج</th>
          <th scope="col">− نفوق</th>
          <th scope="col">− صادر إلى تقسيم</th>
          <th scope="col">− صادر إلى دمج</th>
          <th scope="col">= العدد الحالي المشتق</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.cohort_id}>
            <th scope="row">{row.cohort_reference}</th>
            <td>{row.opening_headcount}</td>
            <td>{row.births}</td>
            <td>{row.split_in}</td>
            <td>{row.merge_in}</td>
            <td>{row.mortality}</td>
            <td>{row.split_out}</td>
            <td>{row.merge_out}</td>
            <td><strong>{row.current_quantity}</strong></td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** GF-022 — the immutable quantity event history. */
function QuantityEvents({
  events,
}: Readonly<{ events: readonly QuantityEventRead[] }>) {
  if (events.length === 0) {
    return <p className="muted">لا توجد حركات على العدد بعد.</p>;
  }
  return (
    <ol className="stack">
      {events.map((event) => (
        <li key={event.id}>
          <strong>{event.cohort_reference}</strong> ·{' '}
          {QUANTITY_EVENT_LABEL[event.event_type] ?? event.event_label}
          <p>
            {event.direction > 0 ? '+' : '−'}{event.quantity} رأس ·{' '}
            <span className="muted">{dateTime(event.effective_at)}</span>
          </p>
          {event.cause_category ? (
            <p className="muted">
              السبب: {MORTALITY_CAUSE_LABEL[event.cause_category] ?? event.cause_category}
              {event.cause_detail ? ` — ${event.cause_detail}` : ''}
            </p>
          ) : null}
        </li>
      ))}
    </ol>
  );
}

/** GF-022 — split/merge lineage, so the two sides can never be read apart. */
function Lineage({ lineage }: Readonly<{ lineage: readonly CohortLineageRead[] }>) {
  if (lineage.length === 0) {
    return <p className="muted">لا توجد عمليات تقسيم أو دمج بعد.</p>;
  }
  return (
    <ol className="stack">
      {lineage.map((entry) => (
        <li key={entry.id}>
          <strong>{OPERATION_TYPE_LABEL[entry.operation_type]}</strong>
          <p>
            {entry.quantity} رأس من {entry.source_cohort_reference} إلى{' '}
            {entry.destination_cohort_reference}
          </p>
          <p className="muted">{dateTime(entry.effective_at)} · {entry.reason}</p>
        </li>
      ))}
    </ol>
  );
}

/** GF-021.D — the weight log, with each figure's meaning made explicit. */
function WeightLog({ events }: Readonly<{ events: readonly WeightEventRead[] }>) {
  if (events.length === 0) return <p className="muted">لا توجد أوزان مسجلة بعد.</p>;
  return (
    <ol className="stack">
      {events.map((event) => (
        <li key={event.id}>
          <strong>{event.cohort_reference}</strong> ·{' '}
          {WEIGHT_METHOD_LABEL[event.method]}
          {event.is_estimate ? <span className="status"> تقديري</span> : null}
          <p>
            {event.weight_value} كجم ·{' '}
            <span className="muted">{WEIGHT_MEANING_LABEL[event.value_meaning]}</span>
          </p>
          {event.sample_size ? (
            <p className="muted">حجم العينة: {event.sample_size} رأس</p>
          ) : null}
          {event.measured_animal_count ? (
            <p className="muted">عدد الحيوانات المقاسة: {event.measured_animal_count} رأس</p>
          ) : null}
          <p className="muted">{dateTime(event.effective_at)}</p>
        </li>
      ))}
    </ol>
  );
}

export default async function LivestockPage({
  params,
}: Readonly<{ params: Promise<{ projectId: string }> }>) {
  const { projectId } = await params;
  const project = await getProject(projectId);
  if (project?.sector !== 'LIVESTOCK') notFound();

  const [
    membership,
    sites,
    herds,
    cohorts,
    timeline,
    placements,
    movements,
    quantities,
    weightEvents,
    quantityEvents,
    lineage,
  ] = await Promise.all([
    getCurrentMembership(project.organization_id),
    getLivestockSites(projectId),
    getLivestockHerds(projectId),
    getLivestockCohorts(projectId),
    getLivestockCohortTimeline(projectId),
    getLivestockCurrentPlacements(projectId),
    getLivestockMovements(projectId),
    getLivestockQuantityRollforward(projectId),
    getLivestockWeightEvents(projectId),
    getLivestockQuantityEvents(projectId),
    getLivestockCohortLineage(projectId),
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
  // Operational events belong to an ACTIVE Cohort; a PLANNED one has not
  // entered operations yet and the database refuses events against it.
  const activeCohorts = cohorts.filter((cohort) => cohort.lifecycle_state === 'ACTIVE');
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
        <ProfileForm {...context} commandNonce={newCommandNonce()} />
      </section>
      <section className="card stack">
        <h2>مواقع التشغيل</h2>
        <SiteForm {...context} commandNonce={newCommandNonce()} />
        <Sites sites={sites} />
      </section>
      <section className="card stack">
        <h2>القطعان (المجموعات الإدارية)</h2>
        <HerdForm {...context} commandNonce={newCommandNonce()} />
        <Herds herds={herds} />
      </section>
      <section className="card stack">
        <h2>الدفعات الحيوانية القابلة للعد</h2>
        <CohortForm {...context} herds={herds} sites={sites} commandNonce={newCommandNonce()} />
        <Cohorts {...context} cohorts={cohorts} timeline={timeline} />
      </section>
      <section className="card stack">
        <h2>الموقع الحالي</h2>
        <p className="muted">
          الموقع الحالي المشتق لكل دفعة، ومنه تُسجَّل حركة النقل. الوضع الافتتاحي يظل ثابتًا في بطاقة الدفعة.
        </p>
        <CurrentPlacements
          placements={placements}
          sites={sites}
          herds={herds}
          organizationId={project.organization_id}
          projectId={projectId}
        />
      </section>
      <section className="card stack">
        <h2>سجل الحركات</h2>
        <Movements movements={movements} />
      </section>
      <section className="card stack">
        <h2>الرصيد العددي الحالي</h2>
        <QuantityRollforward rows={quantities} />
      </section>
      <section className="card stack">
        <h2>تسجيل ولادات</h2>
        <BirthForm {...context} commandNonce={newCommandNonce()} cohorts={activeCohorts} />
      </section>
      <section className="card stack">
        <h2>تسجيل نفوق</h2>
        <MortalityForm {...context} commandNonce={newCommandNonce()} cohorts={activeCohorts} />
      </section>
      <section className="card stack">
        <h2>تقسيم دفعة</h2>
        <SplitForm
          {...context}
          commandNonce={newCommandNonce()}
          cohorts={activeCohorts}
          herds={herds}
          sites={sites}
        />
      </section>
      <section className="card stack">
        <h2>دمج دفعات</h2>
        <MergeForm
          {...context}
          commandNonce={newCommandNonce()}
          cohorts={activeCohorts}
          herds={herds}
          sites={sites}
        />
      </section>
      <section className="card stack">
        <h2>حركة العدد</h2>
        <QuantityEvents events={quantityEvents} />
      </section>
      <section className="card stack">
        <h2>سلسلة التقسيم والدمج</h2>
        <Lineage lineage={lineage} />
      </section>
      <section className="card stack">
        <h2>تسجيل وزن</h2>
        <WeightEventForm {...context} commandNonce={newCommandNonce()} cohorts={activeCohorts} />
      </section>
      <section className="card stack">
        <h2>سجل الأوزان</h2>
        <WeightLog events={weightEvents} />
      </section>
      <aside className="banner">
        <strong>حدود هذه المرحلة:</strong> لا حيوانات فردية أو RFID أو صحة أو علاج أو فترات حظر أو تحصين أو علف أو دورة تكاثر أو بيع أو تحصيل أو ربحية أو تقييم محاسبي. الأعداد المعروضة أرصدة تشغيلية مشتقة من أحداث ثابتة، وليست تقييمًا للمخزون ولا أثرًا محاسبيًا.
      </aside>
    </section>
  );
}
