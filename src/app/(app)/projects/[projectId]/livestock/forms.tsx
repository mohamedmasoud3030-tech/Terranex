'use client';

import { useActionState, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { useCommandIdempotencyKey } from '@/features/livestock/use-command-idempotency-key';
import {
  approveLivestockSale,
  attributeLivestockCohortCost,
  closeLivestockCohort,
  collectLivestockSaleReceivable,
  createLivestockCohort,
  createLivestockHerd,
  createLivestockProfile,
  createLivestockSale,
  createLivestockSite,
  mergeLivestockCohorts,
  recognizeLivestockSale,
  recordLivestockBirth,
  recordLivestockMortality,
  recordLivestockMovement,
  recordLivestockPurchase,
  recordLivestockWeightEvent,
  reverseLivestockCohortCostAttribution,
  splitLivestockCohort,
  transitionLivestockCohort,
} from '@/features/livestock/actions';
import {
  COHORT_ORIGINS,
  DISPOSAL_METHODS,
  HERD_PURPOSES,
  LIVESTOCK_COST_CATEGORIES,
  MORTALITY_CAUSES,
  SITE_TYPES,
  SPECIES,
  WEIGHT_BASES,
  WEIGHT_CONFIDENCE_LEVELS,
  WEIGHT_METHODS,
} from '@/features/livestock/schema';
import {
  DISPOSAL_METHOD_LABEL,
  LIVESTOCK_COST_CATEGORY_LABEL,
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
  LivestockCostAttributionRead,
  LivestockCostSourceRead,
  LivestockSaleRead,
  SiteRead,
} from '@/features/livestock/queries';

type PartyOption = Readonly<{ id: string; legal_name: string }>;
type CashAccountOption = Readonly<{ cash_account_id: string; name: string; currency: string }>;

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

// ---------------------------------------------------------------------------
// GF-024 — Livestock commercial, profitability & closeout forms.
// ---------------------------------------------------------------------------

function PurchaseLinesEditor({
  cohorts,
}: Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [lines, setLines] = useState<Array<{
    cohortId: string;
    quantity: string;
    agreedUnitPrice: string;
  }>>([{ cohortId: cohorts[0]?.id ?? '', quantity: '', agreedUnitPrice: '' }]);
  if (cohorts.length === 0) return null;
  const update = (index: number, patch: Partial<(typeof lines)[number]>) => {
    setLines((current) => current.map((line, i) => (i === index ? { ...line, ...patch } : line)));
  };
  return (
    <div className="full stack">
      {lines.map((line, index) => (
        <div className="responsive-grid" key={index}>
          <label>
            <span>الدفعة</span>
            <select
              value={line.cohortId}
              onChange={(event) => update(index, { cohortId: event.target.value })}
            >
              {cohorts.map((cohort) => (
                <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
              ))}
            </select>
          </label>
          <label>
            <span>عدد الرؤوس</span>
            <input
              value={line.quantity}
              onChange={(event) => update(index, { quantity: event.target.value })}
              inputMode="numeric"
              pattern="[1-9][0-9]*"
              required
            />
          </label>
          <label>
            <span>سعر اتفاق الرأس <span className="muted">(اختياري — لقطة تجارية لا تُرحَّل)</span></span>
            <input
              value={line.agreedUnitPrice}
              onChange={(event) => update(index, { agreedUnitPrice: event.target.value })}
              inputMode="decimal"
              placeholder="0.00"
            />
          </label>
          <div>
            <button
              type="button"
              onClick={() => setLines((current) => current.filter((_, i) => i !== index))}
              disabled={lines.length === 1}
            >
              حذف السطر
            </button>
          </div>
        </div>
      ))}
      <div>
        <button type="button" onClick={() => setLines((current) => [...current, { cohortId: cohorts[0].id, quantity: '', agreedUnitPrice: '' }])}>
          إضافة سطر شراء
        </button>
      </div>
      <input type="hidden" name="linesJson" value={JSON.stringify(lines.map((line) => ({ ...line, quantity: line.quantity.trim(), agreedUnitPrice: line.agreedUnitPrice.trim() || null })))} />
    </div>
  );
}

function SaleLinesEditor({ cohorts }: Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [lines, setLines] = useState<Array<{ cohortId: string; quantity: string; unitPrice: string }>>(
    [{ cohortId: cohorts[0]?.id ?? '', quantity: '', unitPrice: '' }],
  );
  if (cohorts.length === 0) return null;
  const update = (index: number, patch: Partial<(typeof lines)[number]>) => {
    setLines((current) => current.map((line, i) => (i === index ? { ...line, ...patch } : line)));
  };
  return (
    <div className="full stack">
      {lines.map((line, index) => (
        <div className="responsive-grid" key={index}>
          <label>
            <span>الدفعة</span>
            <select
              value={line.cohortId}
              onChange={(event) => update(index, { cohortId: event.target.value })}
            >
              {cohorts.map((cohort) => (
                <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>
              ))}
            </select>
          </label>
          <label>
            <span>عدد الرؤوس</span>
            <input
              value={line.quantity}
              onChange={(event) => update(index, { quantity: event.target.value })}
              inputMode="numeric"
              pattern="[1-9][0-9]*"
              required
            />
          </label>
          <label>
            <span>سعر الرأس</span>
            <input
              value={line.unitPrice}
              onChange={(event) => update(index, { unitPrice: event.target.value })}
              inputMode="decimal"
              required
            />
          </label>
          <div>
            <button
              type="button"
              onClick={() => setLines((current) => current.filter((_, i) => i !== index))}
              disabled={lines.length === 1}
            >
              حذف السطر
            </button>
          </div>
        </div>
      ))}
      <div>
        <button type="button" onClick={() => setLines((current) => [...current, { cohortId: cohorts[0].id, quantity: '', unitPrice: '' }])}>
          إضافة سطر بيع
        </button>
      </div>
      <input type="hidden" name="linesJson" value={JSON.stringify(lines.map((line) => ({ ...line, quantity: line.quantity.trim(), unitPrice: line.unitPrice.trim() })))} />
    </div>
  );
}

/** SCOPE A — external purchase intake (additive PURCHASE_IN, no Finance effect). */
export function PurchaseForm({
  cohorts,
  parties,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  cohorts: readonly CohortRead[];
  parties: readonly PartyOption[];
}>) {
  const [state, action, pending] = useActionState(recordLivestockPurchase, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-purchase', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">فعّل دفعة أولًا قبل تسجيل شراء إضافي.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>المورد</span>
        <select name="supplierPartyId">
          {parties.map((party) => (
            <option key={party.id} value={party.id}>{party.legal_name}</option>
          ))}
        </select>
      </label>
      <label>
        <span>مرجع الشراء</span>
        <input name="purchaseReference" required maxLength={120} />
      </label>
      <label>
        <span>تاريخ ووقت الاستلام</span>
        <input name="effectiveAt" type="datetime-local" required />
      </label>
      <label>
        <span>مرجع العقد <span className="muted">(اختياري)</span></span>
        <input name="agreementReference" maxLength={200} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <label className="full">
        <span>ملاحظات <span className="muted">(اختياري)</span></span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <PurchaseLinesEditor cohorts={cohorts} />
      <p className="muted full">
        إضافة شراء تزيد الرصيد العددي المشتق فقط. لا ينشئ عنها قيد محاسبي أو مستحق أو تقييم.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل الشراء" />
      </div>
    </form>
  );
}

/** SCOPE B — bounded sale draft (no quantity or accounting effect yet). */
export function SaleForm({
  cohorts,
  parties,
  currency,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  cohorts: readonly CohortRead[];
  parties: readonly PartyOption[];
  currency: string;
}>) {
  const [state, action, pending] = useActionState(createLivestockSale, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-sale', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">فعّل دفعة أولًا قبل إنشاء مسودة بيع.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <input type="hidden" name="currency" value={currency} />
      <label>
        <span>المشتري</span>
        <select name="buyerPartyId">
          {parties.map((party) => (
            <option key={party.id} value={party.id}>{party.legal_name}</option>
          ))}
        </select>
      </label>
      <label>
        <span>مرجع البيع</span>
        <input name="saleReference" required maxLength={120} />
      </label>
      <label>
        <span>تاريخ البيع</span>
        <input name="saleDate" type="date" required />
      </label>
      <label>
        <span>مرجع العقد <span className="muted">(اختياري)</span></span>
        <input name="agreementReference" maxLength={200} />
      </label>
      <label>
        <span>شروط البيع <span className="muted">(اختياري)</span></span>
        <input name="terms" maxLength={1000} />
      </label>
      <label>
        <span>مرجع الدليل <span className="muted">(اختياري)</span></span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <SaleLinesEditor cohorts={cohorts} />
      <p className="muted full">
        المسودة لا تصرف أي رأس ولا تعترف بأي إيراد. الصرف الفعلي والاعتراف المالي يحدثان عند نقل السيطرة.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="حفظ مسودة البيع" />
      </div>
    </form>
  );
}

/** SCOPE B — OWNER approval (control, not recognition). */
export function SaleApprovalForm({
  sales,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ sales: readonly LivestockSaleRead[] }>) {
  const [state, action, pending] = useActionState(approveLivestockSale, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-sale-approve', state, commandNonce);
  if (sales.length === 0) return <p className="muted">لا توجد مسودة بيع بانتظار الاعتماد.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>مسودة البيع</span>
        <select name="saleId">
          {sales.map((sale) => (
            <option key={sale.sale_id} value={sale.sale_id}>{sale.sale_reference}</option>
          ))}
        </select>
      </label>
      <p className="muted full">الاعتماد خطوة رقابية؛ لا يحرك المخزون ولا يقيّد الإيراد.</p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="اعتماد البيع" />
      </div>
    </form>
  );
}

/** SCOPE B — control transfer: atomic SALE_OUT + revenue/receivable recognition. */
export function SaleRecognitionForm({
  sales,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ sales: readonly LivestockSaleRead[] }>) {
  const [state, action, pending] = useActionState(recognizeLivestockSale, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-sale-recognize', state, commandNonce);
  if (sales.length === 0) return <p className="muted">لا يوجد بيع معتمد بانتظار نقل السيطرة.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>البيع المعتمد</span>
        <select name="saleId">
          {sales.map((sale) => (
            <option key={sale.sale_id} value={sale.sale_id}>{sale.sale_reference}</option>
          ))}
        </select>
      </label>
      <label>
        <span>تاريخ نقل السيطرة</span>
        <input name="controlTransferDate" type="date" required />
      </label>
      <label>
        <span>مرجع دليل التسليم</span>
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        نقل السيطرة يصرف الرؤوس (SALE_OUT) ويعترف بالإيراد والذمة المدينة في معاملة واحدة؛ لا تكلفة بضاعة مباعة ولا تقييم.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="نقل السيطرة والاعتراف بالإيراد" />
      </div>
    </form>
  );
}

/** SCOPE C — collection against the recognized receivable. */
export function SaleCollectionForm({
  sales,
  cashAccounts,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  sales: readonly LivestockSaleRead[];
  cashAccounts: readonly CashAccountOption[];
}>) {
  const [state, action, pending] = useActionState(collectLivestockSaleReceivable, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-collection', state, commandNonce);
  if (sales.length === 0) return <p className="muted">لا يوجد بيع معترف به بانتظار التحصيل.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>البيع المعترف به</span>
        <select name="recognitionId">
          {sales.map((sale) => (
            <option key={sale.recognition_id!} value={sale.recognition_id!}>
              {sale.sale_reference} · المتبقي {sale.outstanding_receivable_minor_units}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>حساب النقدية</span>
        <select name="cashAccountId">
          {cashAccounts.map((account) => (
            <option key={account.cash_account_id} value={account.cash_account_id}>{account.name}</option>
          ))}
        </select>
      </label>
      <label>
        <span>مبلغ التحصيل</span>
        <input name="amount" inputMode="decimal" required />
      </label>
      <label>
        <span>تاريخ التحصيل</span>
        <input name="collectionDate" type="date" required />
      </label>
      <label>
        <span>مرجع دليل التحصيل</span>
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">التحصيل نقدية مقابل ذمة مدينة؛ لا يُعاد تصنيفه كإيراد. السقف محسوب من الحقائق الثابتة.</p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تسجيل التحصيل" />
      </div>
    </form>
  );
}

/** SCOPE D — attribute a posted Finance expense to a Cohort (no posting). */
export function CostAttributionForm({
  cohorts,
  sources,
  commandNonce,
  ...context
}: CommandContext & Readonly<{
  cohorts: readonly CohortRead[];
  sources: readonly LivestockCostSourceRead[];
}>) {
  const [state, action, pending] = useActionState(attributeLivestockCohortCost, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-cost', state, commandNonce);
  if (sources.length === 0) return <p className="muted">لا يوجد مصدر مصروف تشغيلي مرحّل قابل للتحميل.</p>;
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
        <span>مصدر المصروف المرحّل</span>
        <select name="sourceJournalLineId">
          {sources.map((source) => (
            <option key={source.source_journal_line_id} value={source.source_journal_line_id}>
              {source.description} · المتاح {source.available_amount_minor_units}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>المبلغ المُحمَّل</span>
        <input name="amount" inputMode="decimal" required />
      </label>
      <label>
        <span>تصنيف التكلفة</span>
        <select name="costCategory">
          {LIVESTOCK_COST_CATEGORIES.map((category) => (
            <option key={category} value={category}>{LIVESTOCK_COST_CATEGORY_LABEL[category]}</option>
          ))}
        </select>
      </label>
      <label>
        <span>مرجع السياسة</span>
        <input name="policyReference" required minLength={3} maxLength={200} />
      </label>
      <label>
        <span>مرجع الدليل</span>
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        التحمل بُعد تحليلي فوق قيد مالي مرحّل قائم؛ لا ينشئ قيدًا ولا قيمة مستقلة ولا ربحًا قابلًا للتحرير.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تحميل التكلفة على الدفعة" />
      </div>
    </form>
  );
}

/** SCOPE D — append-only offset of a cost attribution. */
export function CostAttributionReversalForm({
  attributions,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ attributions: readonly LivestockCostAttributionRead[] }>) {
  const [state, action, pending] = useActionState(reverseLivestockCohortCostAttribution, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-cost-reverse', state, commandNonce);
  if (attributions.length === 0) return <p className="muted">لا يوجد تحميل تكلفة نشط لعكسه.</p>;
  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} idempotencyKey={idempotencyKey} />
      <label>
        <span>تحميل التكلفة</span>
        <select name="attributionId">
          {attributions.map((attribution) => (
            <option key={attribution.id} value={attribution.id}>
              {LIVESTOCK_COST_CATEGORY_LABEL[attribution.cost_category]} · {attribution.attributed_amount_minor_units}
            </option>
          ))}
        </select>
      </label>
      <label>
        <span>سبب العكس</span>
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل</span>
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="عكس تحميل التكلفة" />
      </div>
    </form>
  );
}

/** SCOPE E — technical closeout; never a lifecycle mutation. */
export function CloseoutForm({
  cohorts,
  commandNonce,
  ...context
}: CommandContext & Readonly<{ cohorts: readonly CohortRead[] }>) {
  const [state, action, pending] = useActionState(closeLivestockCohort, initialState);
  const idempotencyKey = useCommandIdempotencyKey('ls-closeout', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">لا توجد دفعة لإقفالها تقنيًا.</p>;
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
        <span>سبب الإقفال</span>
        <input name="closeReason" required minLength={3} maxLength={500} />
      </label>
      <label>
        <span>مرجع الدليل</span>
        <input name="evidenceReference" required minLength={3} maxLength={200} />
      </label>
      <p className="muted full">
        الإقفال تقني وليس انتقال حالة دورة حياة: الدفعة المستنفدة تبقى نشطة، والإقفال المالي يبقى عبر S6.
      </p>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="إقفال تقني للدفعة" />
      </div>
    </form>
  );
}
