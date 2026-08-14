'use client';

import { useActionState, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { useCommandIdempotencyKey } from '@/features/livestock/use-command-idempotency-key';
import {
  createLivestockCohort,
  createLivestockHerd,
  createLivestockProfile,
  createLivestockSite,
  mergeLivestockCohorts,
  recordLivestockBirth,
  recordLivestockMortality,
  recordLivestockMovement,
  recordLivestockWeightEvent,
  splitLivestockCohort,
  transitionLivestockCohort,
} from '@/features/livestock/actions';
import {
  COHORT_ORIGINS,
  DISPOSAL_METHODS,
  HERD_PURPOSES,
  MORTALITY_CAUSES,
  SITE_TYPES,
  SPECIES,
  WEIGHT_BASES,
  WEIGHT_CONFIDENCE_LEVELS,
  WEIGHT_METHODS,
} from '@/features/livestock/schema';
import {
  DISPOSAL_METHOD_LABEL,
  MORTALITY_CAUSE_LABEL,
  ORIGIN_LABEL,
  PURPOSE_LABEL,
  SITE_TYPE_LABEL,
  SPECIES_LABEL,
  WEIGHT_BASIS_LABEL,
  WEIGHT_CONFIDENCE_LABEL,
  WEIGHT_METHOD_LABEL,
} from '@/features/livestock/labels';
import type {
  CohortRead,
  CurrentPlacementRead,
  HerdRead,
  SiteRead,
} from '@/features/livestock/queries';

const initialState: ActionState = {};

type CommandContext = Readonly<{
  organizationId: string;
  projectId: string;
  /** Per-mount nonce generated in the Server Component (hydration-safe). */
  commandNonce: string;
}>;

function CommandFields({
  organizationId,
  projectId,
  idempotencyKey,
}: Readonly<{ organizationId: string; projectId: string; idempotencyKey: string }>) {
  return (
    <>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
    </>
  );
}

function SubmitResult({
  state,
  pending,
  label,
}: Readonly<{ state: ActionState; pending: boolean; label: string }>) {
  return (
    <>
      {state.error ? <p className="error" role="alert">{state.error}</p> : null}
      <button type="submit" disabled={pending}>{pending ? 'جارٍ الحفظ…' : label}</button>
    </>
  );
}

export function ProfileForm({ commandNonce, ...context }: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockProfile, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-profile', state, commandNonce);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label className="full">
        <span>ملاحظات تشغيلية <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تهيئة ملف الثروة الحيوانية" />
      </div>
    </form>
  );
}

export function SiteForm({ commandNonce, ...context }: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockSite, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-site', state, commandNonce);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>اسم موقع التشغيل</span>
        <input name="name" required minLength={2} maxLength={160} />
      </label>
      <label>
        <span>المرجع الداخلي</span>
        <input name="internalReference" required maxLength={80} />
      </label>
      <label>
        <span>نوع الموقع</span>
        <select name="siteType">
          {SITE_TYPES.map((type) => <option key={type} value={type}>{SITE_TYPE_LABEL[type]}</option>)}
        </select>
      </label>
      <label>
        <span>وصف الموقع <span className="muted">(اختياري)</span></span>
        <input name="locationDescription" maxLength={500} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        موقع تشغيل فقط؛ لا يثبت ملكية أرض أو أصل عقاري أو حقًا قانونيًا.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="إضافة موقع التشغيل" />
      </div>
    </form>
  );
}

export function HerdForm({ commandNonce, ...context }: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockHerd, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-herd', state, commandNonce);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>اسم القطيع</span>
        <input name="name" required minLength={2} maxLength={160} />
      </label>
      <label>
        <span>مرجع القطيع</span>
        <input name="internalReference" required maxLength={80} />
      </label>
      <label>
        <span>النوع</span>
        <select name="species">
          {SPECIES.map((species) => (
            <option key={species} value={species}>{SPECIES_LABEL[species]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>الغرض</span>
        <select name="purpose">
          {HERD_PURPOSES.map((purpose) => (
            <option key={purpose} value={purpose}>{PURPOSE_LABEL[purpose]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>السلالة/النوع الوصفي <span className="muted">(اختياري)</span></span>
        <input name="breedDescriptor" maxLength={120} />
      </label>
      <p className="muted full">
        القطيع مجموعة إدارية حسب النوع والغرض؛ موقع التشغيل ليس جزءًا دائمًا من هويته.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="إضافة القطيع" />
      </div>
    </form>
  );
}

function WeightFields() {
  return (
    <fieldset className="full form-grid">
      <legend>أساس الوزن الافتتاحي</legend>
      <label>
        <span>قيمة الوزن</span>
        <input name="openingWeightValue" inputMode="decimal" required />
      </label>
      <label>
        <span>الوحدة</span>
        <select name="openingWeightUnit"><option value="KG">كجم</option></select>
      </label>
      <label>
        <span>الأساس</span>
        <select name="openingWeightBasis">
          {WEIGHT_BASES.map((basis) => (
            <option key={basis} value={basis}>{WEIGHT_BASIS_LABEL[basis]}</option>
          ))}
        </select>
      </label>
      <p className="muted full">
        المتوسط بالعينة مؤجل حتى يسجل حدث الوزن حجم العينة وأدلته في مرحلة لاحقة.
      </p>
    </fieldset>
  );
}

export function CohortForm({
  herds,
  sites,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ herds: readonly HerdRead[]; sites: readonly SiteRead[] }>) {
  const [state, action, pending] = useActionState(createLivestockCohort, initialState);
  const [includeWeight, setIncludeWeight] = useState(false);
  const idempotencyKey = useCommandIdempotencyKey('ls-cohort', state, commandNonce);

  if (herds.length === 0 || sites.length === 0) {
    return <p className="muted">أضف قطيعًا وموقع تشغيل قبل إنشاء الدفعة.</p>;
  }

  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>القطيع الإداري</span>
        <select name="herdId">
          {herds.map((herd) => (
            <option key={herd.id} value={herd.id}>
              {herd.name} · {SPECIES_LABEL[herd.species]}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>موقع الوضع الافتتاحي</span>
        <select name="initialSiteId">
          {sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
        </select>
      </label>
      <p className="muted full">
        هذا موضع افتتاحي ثابت للدفعة. الحركة والموقع الحالي مشتقان لاحقًا من أحداث حركة صريحة.
      </p>
      <label>
        <span>مرجع الدفعة</span>
        <input name="cohortReference" required maxLength={100} />
      </label>
      <label>
        <span>مصدر الدفعة</span>
        <select name="originType">
          {COHORT_ORIGINS.map((origin) => (
            <option key={origin} value={origin}>{ORIGIN_LABEL[origin]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>تاريخ دخول الدفعة</span>
        <input name="originDate" type="date" required />
      </label>
      <label>
        <span>العدد عند بداية الدفعة</span>
        <input
          name="openingHeadcount"
          inputMode="numeric"
          pattern="[1-9][0-9]*"
          required
          aria-describedby="headcount-help"
        />
      </label>
      <p id="headcount-help" className="muted full">
        حقيقة افتتاحية ثابتة وليست «المخزون الحالي».
      </p>
      <label>
        <span>تركيب الجنس <span className="muted">(اختياري)</span></span>
        <select name="sexComposition" defaultValue="">
          <option value="">غير محدد</option>
          <option value="MALE">ذكور</option>
          <option value="FEMALE">إناث</option>
          <option value="MIXED">مختلط</option>
        </select>
      </label>
      <label>
        <span>السلالة <span className="muted">(اختياري)</span></span>
        <input name="breedDescriptor" maxLength={120} />
      </label>
      <label className="full">
        <input
          type="checkbox"
          checked={includeWeight}
          onChange={(event) => setIncludeWeight(event.target.checked)}
        />{' '}
        <span>تسجيل أساس وزن افتتاحي موثق (اختياري)</span>
      </label>
      {includeWeight ? <WeightFields /> : null}
      <label>
        <span>مرجع دليل المصدر <span className="muted">(اختياري)</span></span>
        <input name="originEvidenceReference" maxLength={200} />
      </label>
      <label>
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        الشراء هنا يثبت دخول العدد تشغيليًا فقط؛ لا ينشئ دفعة أو التزامًا أو قيدًا أو تقييمًا.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="إنشاء الدفعة المخططة" />
      </div>
    </form>
  );
}

export function ActivateForm({
  cohort,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ cohort: CohortRead }>) {
  const [state, action, pending] = useActionState(
    transitionLivestockCohort,
    initialState,
  );
  const idempotencyKey = useCommandIdempotencyKey('ls-activate', state, commandNonce);
  return (
    <form action={action} className="form-grid compact">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <input type="hidden" name="cohortId" value={cohort.id} />
      <input type="hidden" name="expectedState" value="PLANNED" />
      <input type="hidden" name="newState" value="ACTIVE" />
      <label>
        <span>سبب التفعيل</span>
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <div><SubmitResult state={state} pending={pending} label="تفعيل الدفعة" /></div>
    </form>
  );
}

/**
 * GF-021 — record a movement.
 *
 * The source placement is rendered read-only from the server-derived current
 * placement and submitted as a hidden field only so the server can reject a
 * stale view. It is never editable, and the server re-derives the truth
 * regardless of what the browser sends.
 */
export function MovementForm({
  placement,
  sites,
  herds,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  placement: CurrentPlacementRead;
  sites: readonly SiteRead[];
  herds: readonly HerdRead[];
}>) {
  const [state, action, pending] = useActionState(recordLivestockMovement, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-move', state, commandNonce);
  const otherSites = sites.filter((site) => site.id !== placement.current_site_id);
  const otherHerds = herds.filter(
    (herd) => herd.id !== placement.current_herd_id && herd.species === placement.species,
  );

  return (
    <form action={action} className="form-grid compact">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <input type="hidden" name="cohortId" value={placement.cohort_id} />
      <input type="hidden" name="sourceSiteId" value={placement.current_site_id} />
      <input type="hidden" name="sourceHerdId" value={placement.current_herd_id} />
      <p className="muted full">
        من: {placement.current_site_name} · {placement.current_herd_name}{' '}
        <span className="muted">(الموقع الحالي المشتق، غير قابل للتحرير)</span>
      </p>
      <label>
        <span>موقع التشغيل الوجهة</span>
        <select name="destinationSiteId" defaultValue={placement.current_site_id}>
          <option value={placement.current_site_id}>
            {placement.current_site_name} (بدون تغيير)
          </option>
          {otherSites.map((site) => (
            <option key={site.id} value={site.id}>{site.name}</option>
          ))}
        </select>
      </label>
      <label>
        <span>القطيع الوجهة</span>
        <select name="destinationHerdId" defaultValue={placement.current_herd_id}>
          <option value={placement.current_herd_id}>
            {placement.current_herd_name} (بدون تغيير)
          </option>
          {otherHerds.map((herd) => (
            <option key={herd.id} value={herd.id}>{herd.name}</option>
          ))}
        </select>
      </label>
      <label>
        <span>تاريخ ووقت النقل</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <label>
        <span>سبب النقل</span>
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        يجب أن يتغير الموقع أو القطيع. الحركة حدث ثابت يُضاف إلى السلسلة ولا يعدّل الوضع الافتتاحي.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل نقل الدفعة" />
      </div>
    </form>
  );
}

/** GF-021 — record a weight measurement event. */
export function WeightEventForm({
  cohorts,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [state, action, pending] = useActionState(
    recordLivestockWeightEvent,
    initialState,
  );
  const [method, setMethod] = useState<string>('COHORT_TOTAL');
  const idempotencyKey = useCommandIdempotencyKey('ls-weight', state, commandNonce);

  if (cohorts.length === 0) {
    return <p className="muted">لا توجد دفعة نشطة برصيد موجب؛ لا يمكن تسجيل وزن لدفعة مستنفدة.</p>;
  }

  const isSampled = method === 'SAMPLED_AVERAGE';
  const isIndividual = method === 'INDIVIDUAL_MEASURED';

  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <input type="hidden" name="weightUnit" value="KG" />
      <label>
        <span>الدفعة</span>
        <select name="cohortId">
          {cohorts.map((cohort) => (
            <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
          ))}
        </select>
      </label>
      <label>
        <span>تاريخ ووقت القياس</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <label>
        <span>أسلوب القياس</span>
        <select
          name="method"
          value={method}
          onChange={(event) => setMethod(event.target.value)}
        >
          {WEIGHT_METHODS.map((value) => (
            <option key={value} value={value}>{WEIGHT_METHOD_LABEL[value]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>
          {isSampled ? 'متوسط وزن الرأس في العينة (كجم)' : 'قيمة الوزن (كجم)'}
        </span>
        <input
          name="weightValue"
          inputMode="decimal"
          required
          aria-describedby="weight-meaning-help"
        />
      </label>
      <p id="weight-meaning-help" className="muted full">
        {isSampled
          ? 'الرقم متوسط للرأس داخل العينة فقط، وليس وزنًا مقاسًا لكل الدفعة.'
          : null}
        {method === 'ESTIMATED'
          ? 'رقم تقديري صريح؛ لا يُعرض ولا يُستخدم كوزن مقاس.'
          : null}
        {method === 'COHORT_TOTAL' ? 'إجمالي وزن مقاس للدفعة.' : null}
        {isIndividual ? 'إجمالي وزن الحيوانات التي شملها القياس الفردي.' : null}
      </p>
      {isIndividual ? (
        <label>
          <span>عدد الحيوانات التي شملها القياس</span>
          <input name="measuredAnimalCount" inputMode="numeric" pattern="[1-9][0-9]*" required />
        </label>
      ) : null}
      {isSampled ? (
        <label>
          <span>حجم العينة</span>
          <input
            name="sampleSize"
            inputMode="numeric"
            pattern="[1-9][0-9]*"
            required
            aria-describedby="sample-size-help"
          />
        </label>
      ) : null}
      {isSampled ? (
        <p id="sample-size-help" className="muted full">
          حجم العينة إلزامي ولا يجوز أن يتجاوز العدد الحالي المشتق للدفعة.
        </p>
      ) : null}
      <label>
        <span>درجة الثقة التشغيلية <span className="muted">(نوعية وليست فاصلًا إحصائيًا)</span></span>
        <select name="confidenceLevel" defaultValue="UNASSESSED">
          {WEIGHT_CONFIDENCE_LEVELS.map((level) => (
            <option key={level} value={level}>{WEIGHT_CONFIDENCE_LABEL[level]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>
          مرجع الدليل{' '}
          <span className="muted">{isSampled ? '(إلزامي للعينة)' : '(اختياري)'}</span>
        </span>
        <input name="evidenceReference" maxLength={200} required={isSampled} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        الوزن قياس ثابت بتاريخه، وليس خاصية متغيرة للدفعة. لا ينشئ أي أثر محاسبي أو تقييم.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل حدث الوزن" />
      </div>
    </form>
  );
}

/** Destination identity shared by the split and merge forms. */
function DerivedCohortFields({
  herds,
  sites,
}: Readonly<{ herds: readonly HerdRead[]; sites: readonly SiteRead[] }>) {
  return (
    <>
      <label>
        <span>مرجع الدفعة الناتجة</span>
        <input name="destinationCohortReference" required maxLength={100} />
      </label>
      <label>
        <span>القطيع الوجهة</span>
        <select name="destinationHerdId">
          {herds.map((herd) => (
            <option key={herd.id} value={herd.id}>
              {herd.name} · {SPECIES_LABEL[herd.species]}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>موقع التشغيل الوجهة</span>
        <select name="destinationSiteId">
          {sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
        </select>
      </label>
      <label>
        <span>تركيب الجنس للدفعة الناتجة <span className="muted">(اختياري)</span></span>
        <select name="destinationSexComposition" defaultValue="">
          <option value="">غير محدد</option>
          <option value="MALE">ذكور</option>
          <option value="FEMALE">إناث</option>
          <option value="MIXED">مختلط</option>
        </select>
      </label>
      <label>
        <span>السلالة للدفعة الناتجة <span className="muted">(اختياري)</span></span>
        <input name="destinationBreedDescriptor" maxLength={120} />
      </label>
    </>
  );
}

/** GF-022 — record births against a Cohort. */
export function BirthForm({
  cohorts,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [state, action, pending] = useActionState(recordLivestockBirth, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-birth', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">فعّل دفعة أولًا قبل تسجيل الولادات.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>الدفعة</span>
        <select name="cohortId">
          {cohorts.map((cohort) => (
            <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
          ))}
        </select>
      </label>
      <label>
        <span>عدد المواليد</span>
        <input name="quantity" inputMode="numeric" pattern="[1-9][0-9]*" required />
      </label>
      <label>
        <span>تاريخ ووقت الولادة</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        تُسجَّل واقعة العدد فقط. دورة التكاثر والحمل والفطام خارج نطاق هذه المرحلة.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل ولادات" />
      </div>
    </form>
  );
}

/** GF-022 — record mortality against a Cohort. */
export function MortalityForm({
  cohorts,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [state, action, pending] = useActionState(recordLivestockMortality, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-mortality', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">لا توجد دفعة نشطة برصيد موجب؛ لا يمكن تسجيل النفوق على دفعة مستنفدة.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>الدفعة</span>
        <select name="cohortId">
          {cohorts.map((cohort) => (
            <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
          ))}
        </select>
      </label>
      <label>
        <span>عدد النافق</span>
        <input
          name="quantity"
          inputMode="numeric"
          pattern="[1-9][0-9]*"
          required
          aria-describedby="mortality-help"
        />
      </label>
      <p id="mortality-help" className="muted full">
        لا يمكن أن يتجاوز العدد الرصيد العددي الحالي المشتق للدفعة.
      </p>
      <label>
        <span>تاريخ ووقت الواقعة</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <label>
        <span>تصنيف السبب</span>
        <select name="causeCategory">
          {MORTALITY_CAUSES.map((cause) => (
            <option key={cause} value={cause}>{MORTALITY_CAUSE_LABEL[cause]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>تفصيل السبب <span className="muted">(اختياري)</span></span>
        <input name="causeDetail" maxLength={500} />
      </label>
      <label>
        <span>طريقة التخلص</span>
        <select name="disposalMethod" defaultValue="PENDING" required>
          {DISPOSAL_METHODS.map((method) => (
            <option key={method} value={method}>{DISPOSAL_METHOD_LABEL[method]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        واقعة تشغيلية تقلل العدد المشتق فقط؛ طريقة التخلص محفوظة كحقيقة تشغيلية ولا ينشأ عنها أي قيد محاسبي أو تكلفة أو تقييم.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل نفوق" />
      </div>
    </form>
  );
}

/** GF-022 — split a Cohort into a new Cohort as one atomic operation. */
export function SplitForm({
  cohorts,
  herds,
  sites,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  cohorts: readonly CohortRead[];
  herds: readonly HerdRead[];
  sites: readonly SiteRead[];
}>) {
  const [state, action, pending] = useActionState(splitLivestockCohort, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-split', state, commandNonce);
  if (cohorts.length === 0 || herds.length === 0 || sites.length === 0) {
    return <p className="muted">لا توجد دفعة نشطة برصيد موجب، أو أضف قطيعًا وموقعًا قبل التقسيم.</p>;
  }
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>الدفعة المصدر</span>
        <select name="sourceCohortId">
          {cohorts.map((cohort) => (
            <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
          ))}
        </select>
      </label>
      <label>
        <span>العدد المُقسَّم</span>
        <input name="quantity" inputMode="numeric" pattern="[1-9][0-9]*" required />
      </label>
      <label>
        <span>تاريخ ووقت التقسيم</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <DerivedCohortFields herds={herds} sites={sites} />
      <label>
        <span>سبب التقسيم</span>
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        عملية واحدة ذرية: يخرج العدد من الدفعة المصدر ويدخل بالكامل إلى الدفعة الناتجة.
        لا يتغير العدد الافتتاحي للمصدر، ولا يُفقد أو يُستحدث أي رأس.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تقسيم الدفعة" />
      </div>
    </form>
  );
}

/** GF-022 — merge two or more Cohorts into one, as a single atomic operation. */
export function MergeForm({
  cohorts,
  herds,
  sites,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  cohorts: readonly CohortRead[];
  herds: readonly HerdRead[];
  sites: readonly SiteRead[];
}>) {
  const [state, action, pending] = useActionState(mergeLivestockCohorts, initialState);
  const [selected, setSelected] = useState<readonly string[]>([]);
  const idempotencyKey = useCommandIdempotencyKey('ls-merge', state, commandNonce);

  if (cohorts.length < 2 || herds.length === 0 || sites.length === 0) {
    return <p className="muted">يلزم وجود دفعتين نشطتين برصيد موجب على الأقل لتنفيذ الدمج.</p>;
  }

  function toggle(cohortId: string, checked: boolean) {
    setSelected((current) => checked
      ? [...current, cohortId]
      : current.filter((id) => id !== cohortId));
  }

  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <fieldset className="full">
        <legend>الدفعات المصدر والعدد المدموج من كل دفعة</legend>
        {cohorts.map((cohort) => {
          const checked = selected.includes(cohort.id);
          return (
            <div key={cohort.id}>
              <label>
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={(event) => toggle(cohort.id, event.target.checked)}
                />{' '}
                <span>{cohort.cohort_reference}</span>
              </label>
              {checked ? (
                <>
                  <input type="hidden" name="sourceCohortIds" value={cohort.id} />
                  <label>
                    <span>العدد المدموج من {cohort.cohort_reference}</span>
                    <input
                      name="quantities"
                      inputMode="numeric"
                      pattern="[1-9][0-9]*"
                      required
                    />
                  </label>
                </>
              ) : null}
            </div>
          );
        })}
        <p className="muted">
          اختر دفعتين مختلفتين على الأقل من النوع الحيواني نفسه. الدمج بين أنواع مختلفة مرفوض.
        </p>
      </fieldset>
      <label>
        <span>تاريخ ووقت الدمج</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <DerivedCohortFields herds={herds} sites={sites} />
      <label>
        <span>سبب الدمج</span>
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        عملية واحدة ذرية: تستهلك الأعداد من الدفعات المصدر وتضيف مجموعها بالضبط إلى الدفعة الناتجة.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="دمج الدفعات" />
      </div>
    </form>
  );
}
