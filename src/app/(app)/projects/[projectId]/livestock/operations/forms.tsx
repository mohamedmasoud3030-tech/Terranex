'use client';

import { useActionState, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import { useCommandIdempotencyKey } from '@/features/livestock/use-command-idempotency-key';
import {
  createFeedItem,
  createMedicineProduct,
  identifyAnimal,
  recordFeedIssue,
  recordHealthEvent,
  recordReproductionEvent,
} from '@/features/livestock/operations-actions';
import {
  ADMINISTRATION_ROUTES,
  ANIMAL_IDENTIFIER_TYPES,
  ANIMAL_SEXES,
  BIRTH_QUANTITY_EFFECTS,
  CONDITION_CLASSIFICATIONS,
  DOSE_UNITS,
  FEED_CATEGORIES,
  FEED_UNITS,
  HEALTH_EVENT_TYPES,
  MEDICINE_PRODUCT_KINDS,
  PREGNANCY_STATUSES,
  REPRODUCTION_EVENT_TYPES,
  SERVICE_METHODS,
} from '@/features/livestock/operations-schema';
import {
  ADMINISTRATION_ROUTE_LABEL,
  ANIMAL_IDENTIFIER_TYPE_LABEL,
  ANIMAL_SEX_LABEL,
  BIRTH_QUANTITY_EFFECT_LABEL,
  CONDITION_LABEL,
  DOSE_UNIT_LABEL,
  FEED_CATEGORY_LABEL,
  FEED_UNIT_LABEL,
  HEALTH_EVENT_LABEL,
  MEDICINE_PRODUCT_KIND_LABEL,
  PREGNANCY_STATUS_LABEL,
  REPRODUCTION_EVENT_LABEL,
  SERVICE_METHOD_LABEL,
} from '@/features/livestock/operations-labels';
import type {
  AnimalRead,
  FeedItemRead,
  MedicineProductRead,
} from '@/features/livestock/operations-queries';
import type { CohortRead } from '@/features/livestock/queries';

const initialState: ActionState = {};
type Context = Readonly<{ organizationId: string; projectId: string; commandNonce: string }>;

function CommandFields({ organizationId, projectId, idempotencyKey }: Readonly<{
  organizationId: string; projectId: string; idempotencyKey: string;
}>) {
  return <>
    <input type="hidden" name="organizationId" value={organizationId} />
    <input type="hidden" name="projectId" value={projectId} />
    <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
  </>;
}

function SubmitResult({ state, pending, label }: Readonly<{
  state: ActionState; pending: boolean; label: string;
}>) {
  return <div className="full stack">
    {state.error ? <p className="error" role="alert">{state.error}</p> : null}
    {!state.error && (state.successCount ?? 0) > 0
      ? <output className="status">تم الحفظ بنجاح كحقيقة تشغيلية ثابتة.</output>
      : null}
    <button type="submit" disabled={pending}>{pending ? 'جارٍ الحفظ…' : label}</button>
  </div>;
}

function CohortSelect({ cohorts, name = 'cohortId' }: Readonly<{
  cohorts: readonly CohortRead[]; name?: string;
}>) {
  return <select name={name} required>
    {cohorts.map((cohort) => <option key={cohort.id} value={cohort.id}>{cohort.cohort_reference}</option>)}
  </select>;
}

export function MedicineProductForm({ commandNonce, ...context }: Context) {
  const [state, action, pending] = useActionState(createMedicineProduct, initialState);
  const key = useCommandIdempotencyKey('ls23-product', state, commandNonce);
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>مرجع المنتج</span><input name="productReference" required maxLength={80} /></label>
    <label><span>اسم المنتج</span><input name="name" required minLength={2} maxLength={160} /></label>
    <label><span>النوع</span><select name="productKind">{MEDICINE_PRODUCT_KINDS.map((v) => <option key={v} value={v}>{MEDICINE_PRODUCT_KIND_LABEL[v]}</option>)}</select></label>
    <label><span>المادة الفعالة <span className="muted">(اختياري)</span></span><input name="activeIngredient" maxLength={200} /></label>
    <label><span>فترة السحب الافتراضية بالأيام</span><input name="defaultWithdrawalDays" inputMode="numeric" pattern="[0-9]+" defaultValue="0" required /></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">هذا مرجع تشغيلي ثابت، وليس رصيد صيدلية أو مخزون دواء. صفر يعني صراحةً عدم وجود فترة سحب.</p>
    <SubmitResult state={state} pending={pending} label="إضافة مرجع المنتج" />
  </form>;
}

export function AnimalForm({ cohorts, commandNonce, ...context }: Context & Readonly<{
  cohorts: readonly CohortRead[];
}>) {
  const [state, action, pending] = useActionState(identifyAnimal, initialState);
  const key = useCommandIdempotencyKey('ls23-animal', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">لا توجد دفعة نشطة برصيد موجب لتعريف حيوان داخلها.</p>;
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>الدفعة</span><CohortSelect cohorts={cohorts} /></label>
    <label><span>نوع المعرّف</span><select name="identifierType">{ANIMAL_IDENTIFIER_TYPES.map((v) => <option key={v} value={v}>{ANIMAL_IDENTIFIER_TYPE_LABEL[v]}</option>)}</select></label>
    <label><span>قيمة المعرّف</span><input name="identifierValue" required maxLength={100} /></label>
    <label><span>الجنس</span><select name="sex">{ANIMAL_SEXES.map((v) => <option key={v} value={v}>{ANIMAL_SEX_LABEL[v]}</option>)}</select></label>
    <label><span>تاريخ الميلاد <span className="muted">(اختياري)</span></span><input name="birthDate" type="date" /></label>
    <label><span>السلالة <span className="muted">(اختياري)</span></span><input name="breedDescriptor" maxLength={120} /></label>
    <label><span>وقت التعريف</span><input name="identifiedAt" type="datetime-local" required /></label>
    <label><span>مرجع الدليل <span className="muted">(اختياري)</span></span><input name="evidenceReference" maxLength={200} /></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">التعريف اختياري ولا ينشئ رأسًا ولا ينقل رأسًا بين الدفعات. أثره على سجل العدد الموثق في GF-022 يساوي صفرًا.</p>
    <SubmitResult state={state} pending={pending} label="تعريف الحيوان" />
  </form>;
}

export function HealthEventForm({ cohorts, animals, products, commandNonce, ...context }: Context & Readonly<{
  cohorts: readonly CohortRead[]; animals: readonly AnimalRead[]; products: readonly MedicineProductRead[];
}>) {
  const [state, action, pending] = useActionState(recordHealthEvent, initialState);
  const [eventType, setEventType] = useState<(typeof HEALTH_EVENT_TYPES)[number]>('OBSERVATION');
  const key = useCommandIdempotencyKey('ls23-health', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">لا توجد دفعة تشغيلية نشطة لتسجيل واقعة صحية.</p>;
  const administration = eventType === 'TREATMENT' || eventType === 'VACCINATION';
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>الدفعة</span><CohortSelect cohorts={cohorts} /></label>
    <label><span>الحيوان المعرّف <span className="muted">(اختياري)</span></span><select name="animalId" defaultValue=""><option value="">الدفعة كاملة/بدون هوية فردية</option>{animals.map((a) => <option key={a.id} value={a.id}>{a.identifier_value} · {a.cohort_reference}</option>)}</select></label>
    <label><span>نوع الواقعة</span><select name="eventType" value={eventType} onChange={(e) => setEventType(e.target.value as typeof eventType)}>{HEALTH_EVENT_TYPES.map((v) => <option key={v} value={v}>{HEALTH_EVENT_LABEL[v]}</option>)}</select></label>
    {!administration ? <>
      <label><span>تصنيف الحالة <span className="muted">(مطلوب للتشخيص)</span></span><select name="conditionClassification" defaultValue=""><option value="">غير مصنف</option>{CONDITION_CLASSIFICATIONS.map((v) => <option key={v} value={v}>{CONDITION_LABEL[v]}</option>)}</select></label>
      <label><span>الحالة/التشخيص</span><input name="conditionName" required maxLength={200} /></label>
    </> : <>
      <label><span>المنتج</span><select name="medicineProductId" required><option value="">اختر منتجًا</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} · {MEDICINE_PRODUCT_KIND_LABEL[p.product_kind]}</option>)}</select></label>
      <label><span>الجرعة</span><input name="doseQuantity" inputMode="decimal" required /></label>
      <label><span>وحدة الجرعة</span><select name="doseUnit">{DOSE_UNITS.map((v) => <option key={v} value={v}>{DOSE_UNIT_LABEL[v]}</option>)}</select></label>
      <label><span>طريق الإعطاء</span><select name="administrationRoute">{ADMINISTRATION_ROUTES.map((v) => <option key={v} value={v}>{ADMINISTRATION_ROUTE_LABEL[v]}</option>)}</select></label>
    </>}
    <label><span>وقت الواقعة/الإعطاء</span><input name="effectiveAt" type="datetime-local" required /></label>
    <label><span>المنفذ/المختص</span><input name="practitionerName" required minLength={2} maxLength={160} /></label>
    <label><span>مرجع الدليل <span className="muted">(اختياري)</span></span><input name="evidenceReference" maxLength={200} /></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">فترة السحب ونهايتها تُثبتان من مرجع المنتج وقت الإعطاء. هذه حقيقة تشغيلية للاستعلام فقط؛ لا يطبق GF-023 قرار بيع أو حظرًا تجاريًا.</p>
    <SubmitResult state={state} pending={pending} label="تسجيل الواقعة الصحية" />
  </form>;
}

export function ReproductionForm({ cohorts, animals, commandNonce, ...context }: Context & Readonly<{
  cohorts: readonly CohortRead[]; animals: readonly AnimalRead[];
}>) {
  const [state, action, pending] = useActionState(recordReproductionEvent, initialState);
  const [eventType, setEventType] = useState<(typeof REPRODUCTION_EVENT_TYPES)[number]>('BREEDING_SERVICE');
  const key = useCommandIdempotencyKey('ls23-repro', state, commandNonce);
  if (cohorts.length === 0) return <p className="muted">لا توجد دفعة تشغيلية نشطة لتسجيل واقعة تكاثر.</p>;
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>الدفعة</span><CohortSelect cohorts={cohorts} /></label>
    <label><span>حيوان موضوع الواقعة <span className="muted">(اختياري)</span></span><select name="subjectAnimalId" defaultValue=""><option value="">واقعة على مستوى الدفعة</option>{animals.map((a) => <option key={a.id} value={a.id}>{a.identifier_value} · {a.cohort_reference}</option>)}</select></label>
    <label><span>نوع الواقعة</span><select name="eventType" value={eventType} onChange={(e) => setEventType(e.target.value as typeof eventType)}>{REPRODUCTION_EVENT_TYPES.map((v) => <option key={v} value={v}>{REPRODUCTION_EVENT_LABEL[v]}</option>)}</select></label>
    <label><span>عدد الحالات/الأمهات</span><input name="subjectCount" inputMode="numeric" pattern="[1-9][0-9]*" defaultValue="1" required /></label>
    {eventType === 'BREEDING_SERVICE' ? <label><span>طريقة الخدمة</span><select name="serviceMethod">{SERVICE_METHODS.map((v) => <option key={v} value={v}>{SERVICE_METHOD_LABEL[v]}</option>)}</select></label> : null}
    {eventType === 'PREGNANCY_CHECK' ? <>
      <label><span>نتيجة الفحص</span><select name="pregnancyStatus">{PREGNANCY_STATUSES.map((v) => <option key={v} value={v}>{PREGNANCY_STATUS_LABEL[v]}</option>)}</select></label>
      <label><span>تاريخ الولادة المتوقع <span className="muted">(للحمل الموجب فقط)</span></span><input name="expectedBirthDate" type="date" /></label>
    </> : null}
    {eventType === 'BIRTH_OUTCOME' ? <>
      <label><span>المواليد الأحياء المرصودة</span><input name="observedLiveBirthCount" inputMode="numeric" pattern="[0-9]+" defaultValue="0" required /></label>
      <label><span>المواليد غير الأحياء</span><input name="stillbirthCount" inputMode="numeric" pattern="[0-9]+" defaultValue="0" required /></label>
      <label className="full"><span>أثر العدد</span><select name="birthQuantityEffect">{BIRTH_QUANTITY_EFFECTS.map((v) => <option key={v} value={v}>{BIRTH_QUANTITY_EFFECT_LABEL[v]}</option>)}</select></label>
      <label><span>الأم المعرّفة <span className="muted">(اختياري)</span></span><select name="damAnimalId" defaultValue=""><option value="">غير محددة</option>{animals.filter((a) => a.sex === 'FEMALE').map((a) => <option key={a.id} value={a.id}>{a.identifier_value}</option>)}</select></label>
      <label><span>الأب المعرّف <span className="muted">(اختياري)</span></span><select name="sireAnimalId" defaultValue=""><option value="">غير محدد</option>{animals.filter((a) => a.sex === 'MALE').map((a) => <option key={a.id} value={a.id}>{a.identifier_value}</option>)}</select></label>
    </> : null}
    {eventType === 'WEANING' ? <label><span>عدد المفطوم</span><input name="weanedCount" inputMode="numeric" pattern="[1-9][0-9]*" required /></label> : null}
    <label><span>وقت الواقعة</span><input name="effectiveAt" type="datetime-local" required /></label>
    <label><span>المنفذ</span><input name="performedByName" required minLength={2} maxLength={160} /></label>
    <label><span>مرجع الدليل <span className="muted">(اختياري)</span></span><input name="evidenceReference" maxLength={200} /></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">«ملاحظة فقط» لا تغيّر العدد. الخيار المرتبط ينفذ أمر BIRTH القائم في GF-022 مرة واحدة داخل المعاملة نفسها، ثم يحفظ رابط الواقعة؛ لا يوجد سجل ولادات ثانٍ.</p>
    <SubmitResult state={state} pending={pending} label="تسجيل واقعة التكاثر" />
  </form>;
}

export function FeedItemForm({ commandNonce, ...context }: Context) {
  const [state, action, pending] = useActionState(createFeedItem, initialState);
  const key = useCommandIdempotencyKey('ls23-feed-item', state, commandNonce);
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>مرجع الصنف</span><input name="itemReference" required maxLength={80} /></label>
    <label><span>اسم العلف</span><input name="name" required minLength={2} maxLength={160} /></label>
    <label><span>الفئة</span><select name="feedCategory">{FEED_CATEGORIES.map((v) => <option key={v} value={v}>{FEED_CATEGORY_LABEL[v]}</option>)}</select></label>
    <label><span>وحدة الصرف</span><select name="issueUnit">{FEED_UNITS.map((v) => <option key={v} value={v}>{FEED_UNIT_LABEL[v]}</option>)}</select></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">مرجع استهلاك فقط؛ لا ينشئ مخزون علف أو مشتريات أو تكلفة.</p>
    <SubmitResult state={state} pending={pending} label="إضافة صنف العلف" />
  </form>;
}

export function FeedIssueForm({ cohorts, items, commandNonce, ...context }: Context & Readonly<{
  cohorts: readonly CohortRead[]; items: readonly FeedItemRead[];
}>) {
  const [state, action, pending] = useActionState(recordFeedIssue, initialState);
  const [unit, setUnit] = useState<'KG' | 'LITER'>(items[0]?.issue_unit ?? 'KG');
  const key = useCommandIdempotencyKey('ls23-feed-issue', state, commandNonce);
  if (cohorts.length === 0 || items.length === 0) return <p className="muted">أضف صنف علف وتأكد من وجود دفعة تشغيلية نشطة قبل تسجيل الصرف.</p>;
  return <form action={action} className="form-grid">
    <CommandFields {...context} idempotencyKey={key} />
    <label><span>الدفعة</span><CohortSelect cohorts={cohorts} /></label>
    <label><span>صنف العلف</span><select name="feedItemId" onChange={(e) => setUnit(items.find((item) => item.id === e.target.value)?.issue_unit ?? 'KG')}>{items.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.item_reference}</option>)}</select></label>
    <label><span>الكمية</span><input name="quantity" inputMode="decimal" required /></label>
    <label><span>الوحدة المعرّفة للصنف</span><output>{FEED_UNIT_LABEL[unit]}</output><input type="hidden" name="unit" value={unit} /></label>
    <label><span>وقت الصرف/الاستهلاك</span><input name="effectiveAt" type="datetime-local" required /></label>
    <label><span>منفذ الصرف</span><input name="issuedByName" required minLength={2} maxLength={160} /></label>
    <label><span>بداية فترة التغذية <span className="muted">(اختياري)</span></span><input name="feedingPeriodStart" type="date" /></label>
    <label><span>نهاية فترة التغذية <span className="muted">(اختياري)</span></span><input name="feedingPeriodEnd" type="date" /></label>
    <label><span>مرجع الدليل <span className="muted">(ضروري لحساب FCR)</span></span><input name="evidenceReference" maxLength={200} /></label>
    <label className="full"><span>ملاحظات <span className="muted">(اختياري)</span></span><textarea name="notes" maxLength={2000} /></label>
    <p className="muted full">الصرف واقعة استهلاك تشغيلية فقط. لا يُفترض رصيد مخزون أو تكلفة أو مورد.</p>
    <SubmitResult state={state} pending={pending} label="تسجيل صرف العلف" />
  </form>;
}
