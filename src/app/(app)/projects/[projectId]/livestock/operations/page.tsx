import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getCurrentMembership } from '@/features/finance/queries';
import { getProject } from '@/features/projects/queries';
import { ForbiddenCard, WorkspaceChrome } from '@/features/workspace/chrome';
import { newCommandNonce } from '@/features/livestock/idempotency';
import { getLivestockCohorts, getLivestockQuantityRollforward } from '@/features/livestock/queries';
import {
  type HealthEventRead,
  getFcrMetrics,
  getFeedIssues,
  getFeedItems,
  getHealthEvents,
  getIdentifiedAnimals,
  getMedicineProducts,
  getReproductionEvents,
} from '@/features/livestock/operations-queries';
import {
  ANIMAL_IDENTIFIER_TYPE_LABEL,
  ANIMAL_SEX_LABEL,
  BIRTH_QUANTITY_EFFECT_LABEL,
  CONDITION_LABEL,
  FCR_STATUS_LABEL,
  FEED_CATEGORY_LABEL,
  FEED_UNIT_LABEL,
  HEALTH_EVENT_LABEL,
  MEDICINE_PRODUCT_KIND_LABEL,
  PREGNANCY_STATUS_LABEL,
  REPRODUCTION_EVENT_LABEL,
  WITHDRAWAL_STATUS_LABEL,
} from '@/features/livestock/operations-labels';
import {
  AnimalForm,
  FeedIssueForm,
  FeedItemForm,
  HealthEventForm,
  MedicineProductForm,
  ReproductionForm,
} from './forms';

export const dynamic = 'force-dynamic';
const dateTime = (value: string) => new Date(value).toLocaleString('ar-EG');

function HealthLog({ all, filtered }: Readonly<{
  all: readonly HealthEventRead[];
  filtered: readonly HealthEventRead[];
}>) {
  if (all.length === 0) return <p className="muted">لا توجد وقائع صحية بعد.</p>;
  if (filtered.length === 0) return <p className="muted">لا توجد نتائج مطابقة للمرشح الحالي.</p>;
  return <ol className="stack">{filtered.map((event) => <li key={event.id}>
    <strong>{HEALTH_EVENT_LABEL[event.event_type]} · {event.cohort_reference}{event.animal_identifier ? ` · ${event.animal_identifier}` : ''}</strong>
    <p>{event.condition_name ?? event.product_name}{event.condition_classification ? ` · ${CONDITION_LABEL[event.condition_classification]}` : ''}</p>
    {event.dose_quantity ? <p>{event.dose_quantity} {event.dose_unit} · {event.product_name}</p> : null}
    <p className={event.withdrawal_status === 'ACTIVE' ? 'error' : 'muted'}>
      {WITHDRAWAL_STATUS_LABEL[event.withdrawal_status]}
      {event.withdrawal_ends_at ? ` · حتى ${dateTime(event.withdrawal_ends_at)}` : ''}
    </p><small>{dateTime(event.effective_at)} · المنفذ: {event.practitioner_name}</small>
  </li>)}</ol>;
}

export default async function LivestockOperationsPage({ params, searchParams }: Readonly<{
  params: Promise<{ projectId: string }>;
  searchParams: Promise<{ healthType?: string }>;
}>) {
  const { projectId } = await params;
  const filter = (await searchParams).healthType ?? '';
  const project = await getProject(projectId);
  if (project?.sector !== 'LIVESTOCK') notFound();
  const [membership, cohorts, quantities, products, animals, health, reproduction, feedItems, feedIssues, fcr] = await Promise.all([
    getCurrentMembership(project.organization_id),
    getLivestockCohorts(projectId),
    getLivestockQuantityRollforward(projectId),
    getMedicineProducts(projectId),
    getIdentifiedAnimals(projectId),
    getHealthEvents(projectId),
    getReproductionEvents(projectId),
    getFeedItems(projectId),
    getFeedIssues(projectId),
    getFcrMetrics(projectId),
  ]);
  if (!membership) return <ForbiddenCard projectId={projectId} message="لا تسمح عضويتك الحالية بقراءة تشغيل الثروة الحيوانية." />;

  const quantity = new Map(quantities.map((row) => [row.cohort_id, row.current_quantity]));
  const operational = cohorts.filter((cohort) => cohort.lifecycle_state === 'ACTIVE' && cohort.is_operational_as_of_now);
  const positive = operational.filter((cohort) => (quantity.get(cohort.id) ?? 0) > 0);
  const filteredHealth = filter ? health.filter((event) => event.event_type === filter) : health;
  const context = { organizationId: project.organization_id, projectId };

  return <section className="stack">
    <WorkspaceChrome projectId={projectId} active="livestock" sector="LIVESTOCK"
      title="العمليات الحيوانية" subtitle={`${project.name} · الصحة والتكاثر والهوية والتغذية`}
      internalReference={project.internal_reference} />
    <header className="card stack">
      <div><Link href={`/projects/${projectId}/livestock`}>العودة إلى المواقع والقطعان والأعداد</Link></div>
      <h1>العمليات الحيوانية</h1>
      <p className="muted">حقائق تشغيلية عربية/RTL ثابتة فوق نموذج الدفعة. لا مبيعات ولا مشترين ولا مخزون مفترض ولا قيود مالية.</p>
    </header>

    <section className="card stack" id="health">
      <h2>الصحة والعلاجات والتطعيم</h2>
      <details><summary>إضافة مرجع دواء أو لقاح</summary><MedicineProductForm {...context} commandNonce={newCommandNonce()} /></details>
      <details open><summary>تسجيل واقعة صحية</summary><HealthEventForm {...context} commandNonce={newCommandNonce()} cohorts={positive} animals={animals} products={products} /></details>
      <h3>مراجع المنتجات</h3>
      {products.length === 0 ? <p className="muted">لا توجد مراجع دواء أو لقاح بعد.</p> : <div className="responsive-grid">{products.map((product) => <article className="card" key={product.id}>
        <h4>{product.name}</h4><p>{product.product_reference} · {MEDICINE_PRODUCT_KIND_LABEL[product.product_kind]}</p>
        <p className="muted">فترة السحب: {product.default_withdrawal_days} يوم</p>
      </article>)}</div>}
      <form method="get" className="form-grid" aria-label="ترشيح الوقائع الصحية">
        <label><span>ترشيح نوع الواقعة</span><select name="healthType" defaultValue={filter}>
          <option value="">كل الوقائع</option>{Object.entries(HEALTH_EVENT_LABEL).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select></label><button type="submit">تطبيق المرشح</button>
      </form>
      <HealthLog all={health} filtered={filteredHealth} />
    </section>

    <section className="card stack" id="animals">
      <h2>الحيوانات المعرّفة اختياريًا</h2>
      <AnimalForm {...context} commandNonce={newCommandNonce()} cohorts={positive} />
      {animals.length === 0 ? <p className="muted">لا توجد هويات فردية. هذا طبيعي: الدفعة لا تتطلب سجلًا لكل رأس.</p> : <div className="responsive-grid">{animals.map((animal) => <article className="card" key={animal.id}>
        <h3>{animal.identifier_value}</h3>
        <p>{ANIMAL_IDENTIFIER_TYPE_LABEL[animal.identifier_type]} · {ANIMAL_SEX_LABEL[animal.sex]}</p>
        <p>دفعة التعريف: {animal.cohort_reference}</p>
        <small className="muted">أثر التعريف على العدد: {animal.identification_quantity_effect} · {dateTime(animal.identified_at)}</small>
      </article>)}</div>}
    </section>

    <section className="card stack" id="reproduction">
      <h2>التكاثر</h2>
      <ReproductionForm {...context} commandNonce={newCommandNonce()} cohorts={operational} animals={animals} />
      {reproduction.length === 0 ? <p className="muted">لا توجد وقائع تكاثر بعد.</p> : <ol className="stack">{reproduction.map((event) => <li key={event.id}>
        <strong>{REPRODUCTION_EVENT_LABEL[event.event_type]} · {event.cohort_reference}{event.subject_animal_identifier ? ` · ${event.subject_animal_identifier}` : ''}</strong>
        <p>عدد الحالات: {event.subject_count}{event.pregnancy_status ? ` · النتيجة: ${PREGNANCY_STATUS_LABEL[event.pregnancy_status]}` : ''}</p>
        {event.birth_quantity_effect ? <p className={event.affects_authoritative_quantity ? 'status' : 'muted'}>{BIRTH_QUANTITY_EFFECT_LABEL[event.birth_quantity_effect]}{event.observed_live_birth_count != null ? ` · حي: ${event.observed_live_birth_count}` : ''}{event.stillbirth_count != null ? ` · غير حي: ${event.stillbirth_count}` : ''}</p> : null}
        <small>{dateTime(event.effective_at)} · المنفذ: {event.performed_by_name}</small>
      </li>)}</ol>}
    </section>

    <section className="card stack" id="feed">
      <h2>التغذية</h2>
      <details><summary>إضافة صنف علف</summary><FeedItemForm {...context} commandNonce={newCommandNonce()} /></details>
      <FeedIssueForm {...context} commandNonce={newCommandNonce()} cohorts={positive} items={feedItems} />
      <h3>أصناف العلف</h3>
      {feedItems.length === 0 ? <p className="muted">لا توجد أصناف علف بعد.</p> : <div className="responsive-grid">{feedItems.map((item) => <article className="card" key={item.id}><h4>{item.name}</h4><p>{item.item_reference} · {FEED_CATEGORY_LABEL[item.feed_category]} · {FEED_UNIT_LABEL[item.issue_unit]}</p></article>)}</div>}
      <h3>وقائع الصرف والاستهلاك</h3>
      {feedIssues.length === 0 ? <p className="muted">لا توجد وقائع صرف علف بعد.</p> : <ol className="stack">{feedIssues.map((issue) => <li key={issue.id}><strong>{issue.cohort_reference} · {issue.feed_item_name}</strong><p>{issue.quantity} {FEED_UNIT_LABEL[issue.unit]} · {dateTime(issue.effective_at)}</p><small>المنفذ: {issue.issued_by_name}{issue.evidence_reference ? ` · دليل: ${issue.evidence_reference}` : ' · بلا دليل مرفق'}</small></li>)}</ol>}
      <h3>معامل التحويل الغذائي (FCR)</h3>
      <p className="muted">يُحسب فقط بين وزنين موثقين لإجمالي الدفعة، مع علف كيلوجرام موثق وعدم تغير العدد. غير ذلك يظهر كبيانات غير كافية.</p>
      {fcr.length === 0 ? <p className="muted">لا توجد دفعات لحساب المؤشر.</p> : <div className="responsive-grid">{fcr.map((metric) => <article className="card" key={metric.cohort_id}>
        <h4>{metric.cohort_reference}</h4>
        {metric.metric_status === 'AVAILABLE' ? <><p className="status">FCR = {metric.fcr}</p><p>{metric.feed_quantity_kg} كجم علف ÷ {metric.weight_gain_kg} كجم زيادة وزن</p></> : <p className="muted">{FCR_STATUS_LABEL[metric.metric_status] ?? 'غير متاح: الأدلة غير كافية'}</p>}
      </article>)}</div>}
    </section>
  </section>;
}
