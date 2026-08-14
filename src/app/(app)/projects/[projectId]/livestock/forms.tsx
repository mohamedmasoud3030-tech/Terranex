'use client';

import { useActionState, useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import {
  createLivestockCohort,
  createLivestockHerd,
  createLivestockProfile,
  createLivestockSite,
  transitionLivestockCohort,
} from '@/features/livestock/actions';
import {
  COHORT_ORIGINS,
  HERD_PURPOSES,
  SITE_TYPES,
  SPECIES,
  WEIGHT_BASES,
} from '@/features/livestock/schema';
import {
  ORIGIN_LABEL,
  PURPOSE_LABEL,
  SITE_TYPE_LABEL,
  SPECIES_LABEL,
  WEIGHT_BASIS_LABEL,
} from '@/features/livestock/labels';
import type { CohortRead, HerdRead, SiteRead } from '@/features/livestock/queries';

const initialState: ActionState = {};

type CommandContext = Readonly<{
  organizationId: string;
  projectId: string;
}>;

function CommandFields({
  organizationId,
  projectId,
  prefix,
}: CommandContext & Readonly<{ prefix: string }>) {
  const key = useMemo(() => `${prefix}-${crypto.randomUUID()}`, [prefix]);
  return (
    <>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={key} />
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
      <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : label}</button>
    </>
  );
}

export function ProfileForm(props: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockProfile, initialState);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...props} prefix="ls-profile" />
      <label className="full">
        ملاحظات تشغيلية <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <div className="full">
        <SubmitResult state={state} pending={pending} label="تهيئة ملف الثروة الحيوانية" />
      </div>
    </form>
  );
}

export function SiteForm(props: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockSite, initialState);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...props} prefix="ls-site" />
      <label>
        اسم موقع التشغيل
        <input name="name" required minLength={2} maxLength={160} />
      </label>
      <label>
        المرجع الداخلي
        <input name="internalReference" required maxLength={80} />
      </label>
      <label>
        نوع الموقع
        <select name="siteType">
          {SITE_TYPES.map((type) => <option key={type} value={type}>{SITE_TYPE_LABEL[type]}</option>)}
        </select>
      </label>
      <label>
        وصف الموقع <span className="muted">(اختياري)</span>
        <input name="locationDescription" maxLength={500} />
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
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

export function HerdForm(props: CommandContext) {
  const [state, action, pending] = useActionState(createLivestockHerd, initialState);
  return (
    <form action={action} className="form-grid">
      <CommandFields {...props} prefix="ls-herd" />
      <label>
        اسم القطيع
        <input name="name" required minLength={2} maxLength={160} />
      </label>
      <label>
        مرجع القطيع
        <input name="internalReference" required maxLength={80} />
      </label>
      <label>
        النوع
        <select name="species">
          {SPECIES.map((species) => (
            <option key={species} value={species}>{SPECIES_LABEL[species]}</option>
          ))}
        </select>
      </label>
      <label>
        الغرض
        <select name="purpose">
          {HERD_PURPOSES.map((purpose) => (
            <option key={purpose} value={purpose}>{PURPOSE_LABEL[purpose]}</option>
          ))}
        </select>
      </label>
      <label>
        السلالة/النوع الوصفي <span className="muted">(اختياري)</span>
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
        قيمة الوزن
        <input name="openingWeightValue" inputMode="decimal" required />
      </label>
      <label>
        الوحدة
        <select name="openingWeightUnit"><option value="KG">كجم</option></select>
      </label>
      <label>
        الأساس
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
  ...context
}: CommandContext & Readonly<{ herds: readonly HerdRead[]; sites: readonly SiteRead[] }>) {
  const [state, action, pending] = useActionState(createLivestockCohort, initialState);
  const [includeWeight, setIncludeWeight] = useState(false);

  if (herds.length === 0 || sites.length === 0) {
    return <p className="muted">أضف قطيعًا وموقع تشغيل قبل إنشاء الدفعة.</p>;
  }

  return (
    <form action={action} className="form-grid">
      <CommandFields {...context} prefix="ls-cohort" />
      <label>
        القطيع الإداري
        <select name="herdId">
          {herds.map((herd) => (
            <option key={herd.id} value={herd.id}>
              {herd.name} · {SPECIES_LABEL[herd.species]}
            </option>
          ))}
        </select>
      </label>
      <label>
        موقع الوضع الافتتاحي
        <select name="initialSiteId">
          {sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}
        </select>
      </label>
      <p className="muted full">
        هذا موضع افتتاحي ثابت للدفعة. الحركة والموقع الحالي مشتقان لاحقًا من أحداث حركة صريحة.
      </p>
      <label>
        مرجع الدفعة
        <input name="cohortReference" required maxLength={100} />
      </label>
      <label>
        مصدر الدفعة
        <select name="originType">
          {COHORT_ORIGINS.map((origin) => (
            <option key={origin} value={origin}>{ORIGIN_LABEL[origin]}</option>
          ))}
        </select>
      </label>
      <label>
        تاريخ دخول الدفعة
        <input name="originDate" type="date" required />
      </label>
      <label>
        العدد عند بداية الدفعة
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
        تركيب الجنس <span className="muted">(اختياري)</span>
        <select name="sexComposition" defaultValue="">
          <option value="">غير محدد</option>
          <option value="MALE">ذكور</option>
          <option value="FEMALE">إناث</option>
          <option value="MIXED">مختلط</option>
        </select>
      </label>
      <label>
        السلالة <span className="muted">(اختياري)</span>
        <input name="breedDescriptor" maxLength={120} />
      </label>
      <label className="full">
        <input
          type="checkbox"
          checked={includeWeight}
          onChange={(event) => setIncludeWeight(event.target.checked)}
        />{' '}
        تسجيل أساس وزن افتتاحي موثق (اختياري)
      </label>
      {includeWeight ? <WeightFields /> : null}
      <label>
        مرجع دليل المصدر <span className="muted">(اختياري)</span>
        <input name="originEvidenceReference" maxLength={200} />
      </label>
      <label>
        ملاحظات <span className="muted">(اختياري)</span>
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
  ...context
}: CommandContext & Readonly<{ cohort: CohortRead }>) {
  const [state, action, pending] = useActionState(
    transitionLivestockCohort,
    initialState,
  );
  return (
    <form action={action} className="form-grid compact">
      <CommandFields {...context} prefix="ls-activate" />
      <input type="hidden" name="cohortId" value={cohort.id} />
      <input type="hidden" name="expectedState" value="PLANNED" />
      <input type="hidden" name="newState" value="ACTIVE" />
      <label>
        سبب التفعيل
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <div><SubmitResult state={state} pending={pending} label="تفعيل الدفعة" /></div>
    </form>
  );
}
