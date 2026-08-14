'use client';

import { useActionState, useMemo, useState } from 'react';
import type { ActionState } from '@/features/auth/actions';
import {
  assignCropCycleToField,
  createAgriculturalLandAsset,
  createAgricultureProfile,
  createCropCycle,
  createFarm,
  createField,
  createFieldActivity,
  createInputItem,
  createInputLot,
  createStorageLocation,
  linkFarmToAgriculturalLandAsset,
  recordHarvestEvent,
  recordHarvestInventoryAdjustment,
  recordInputApplication,
  transferHarvestInventory,
  transitionCropCycle,
} from '@/features/agriculture/actions';
import type { Party } from '@/features/funding/queries';
import type {
  AgriculturalLandAssetRead,
  CropAssignmentRead,
  CropCycleRead,
  FarmRead,
  FieldActivityRead,
  FieldRead,
  HarvestInventoryByLocationRead,
  HarvestLotRead,
  InputItemRead,
  InputLotRead,
  StorageLocationRead,
} from '@/features/agriculture/queries';
import {
  CYCLE_STATES,
  CYCLE_TRANSITIONS,
  FIELD_ACTIVITY_TYPES,
  INPUT_BEARING_ACTIVITY_TYPES,
  INPUT_CATEGORIES,
  LAND_CONTROL_BASES,
  inputCategoryForActivity,
} from '@/features/agriculture/schema';
import {
  AREA_UNIT_LABEL,
  CYCLE_STATE_LABEL,
  FIELD_ACTIVITY_TYPE_LABEL,
  HARVEST_MOVEMENT_TYPE_LABEL,
  INPUT_CATEGORY_LABEL,
  LAND_CONTROL_BASIS_LABEL,
  formatCycleState,
  formatFieldActivityType,
} from '@/features/agriculture/labels';

const initial: ActionState = { error: undefined };
function Key({ prefix }: { prefix: string }) {
  const key = useMemo(() => `${prefix}-${crypto.randomUUID()}`, [prefix]);
  return <input type="hidden" name="idempotencyKey" value={key} />;
}
function Context({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  return (
    <>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
    </>
  );
}
function Result({
  state,
  pending,
  label,
  pendingLabel = 'جارٍ الحفظ…',
}: {
  state: ActionState;
  pending: boolean;
  label: string;
  pendingLabel?: string;
}) {
  return (
    <>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? pendingLabel : label}</button>
    </>
  );
}

export function ProfileForm({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  const [state, action, pending] = useActionState(createAgricultureProfile, initial);
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-profile" />
      <label className="full">
        ملاحظات تشغيلية أولية <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <div className="full">
        <Result state={state} pending={pending} label="إنشاء ملف الزراعة" />
      </div>
    </form>
  );
}

export function AgriculturalLandAssetForm({
  organizationId,
  projectId,
  currency,
  parties,
}: {
  organizationId: string;
  projectId: string;
  currency: string;
  parties: Party[];
}) {
  const [state, action, pending] = useActionState(createAgriculturalLandAsset, initial);
  const [basis, setBasis] = useState<(typeof LAND_CONTROL_BASES)[number]>('PURCHASED');
  if (parties.length === 0) {
    return <p className="muted">سجّل طرفًا (مالك/بائع/مؤجر/مساهم) من قسم الشروط أولًا.</p>;
  }
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-land" />
      <label>اسم الأرض/الأصل<input name="name" required minLength={2} maxLength={160} /></label>
      <label>المرجع الداخلي<input name="internalReference" required maxLength={80} /></label>
      <label>المرجع القانوني/الحيازي <span className="muted">(اختياري)</span><input name="legalReference" maxLength={160} /></label>
      <label>المالك/البائع/المؤجر/المساهم<select name="counterpartyPartyId" required><option value="">اختر الطرف</option>{parties.map((party) => <option key={party.id} value={party.id}>{party.legal_name}</option>)}</select></label>
      <label>المساحة القانونية/التعاقدية<input name="legalAreaQuantity" inputMode="decimal" required /></label>
      <label>وحدة المساحة<select name="areaUnit" defaultValue="FEDDAN"><option value="FEDDAN">{AREA_UNIT_LABEL.FEDDAN}</option><option value="HECTARE">{AREA_UNIT_LABEL.HECTARE}</option><option value="M2">{AREA_UNIT_LABEL.M2}</option></select></label>
      <label>أساس السيطرة<select name="controlBasis" value={basis} onChange={(event) => setBasis(event.target.value as typeof basis)}>{LAND_CONTROL_BASES.map((value) => <option key={value} value={value}>{LAND_CONTROL_BASIS_LABEL[value]}</option>)}</select></label>
      <label>بداية السيطرة<input type="date" name="controlStartDate" required /></label>
      <label>نهاية السيطرة <span className="muted">(اختياري)</span><input type="date" name="controlEndDate" /></label>
      <label>مرجع العقد/الاتفاق<input name="agreementReference" required minLength={2} maxLength={200} /></label>
      <label>مرجع دليل السيطرة<input name="evidenceReference" required minLength={3} maxLength={200} /></label>
      <label className="full">وصف قانوني/موقعي <span className="muted">(اختياري)</span><textarea name="legalLocationDescription" maxLength={1000} /></label>
      {basis === 'PURCHASED' ? (
        <>
          <label>المقابل المتفق عليه <span className="muted">(اختياري)</span><input name="agreedConsideration" inputMode="decimal" /></label>
          <label>عملة المقابل<select name="considerationCurrency" defaultValue=""><option value="">بدون مقابل مسجل</option><option value={currency}>{currency}</option></select></label>
          <p className="muted full">المقابل المتفق عليه ليس مبلغًا مسددًا ولا قيمة دفترية أو تقييمًا، ولا يدخل تلقائيًا ضمن تكلفة دورة المحصول. اترك المقابل والعملة فارغين معًا إن لم يكن المقابل موثقًا بعد.</p>
        </>
      ) : null}
      {basis === 'CONTRIBUTED_IN_KIND' ? <p className="muted full">يسجل هذا أساس السيطرة والدليل فقط. النواة الحالية تدعم مساهمات نقدية؛ لن ننشئ مساهمة نقدية أو دفعة وهمية للأرض العينية.</p> : null}
      {basis === 'LEASED' || basis === 'MANAGED_FOR_OWNER' ? <p className="muted full">حق تشغيل موثق فقط؛ لا يصف النظام هذه الأرض بأنها مملوكة ولا يستنتج قيمة دفترية.</p> : null}
      <div className="full"><Result state={state} pending={pending} label="تسجيل الأرض/الأصل" /></div>
    </form>
  );
}

export function FarmLandAssetLinkForm({
  organizationId,
  projectId,
  landAssets,
  farms,
  linkedFarmIds,
}: {
  organizationId: string;
  projectId: string;
  landAssets: AgriculturalLandAssetRead[];
  farms: FarmRead[];
  linkedFarmIds: string[];
}) {
  const [state, action, pending] = useActionState(linkFarmToAgriculturalLandAsset, initial);
  const availableFarms = farms.filter((farm) => !linkedFarmIds.includes(farm.id));
  if (landAssets.length === 0 || availableFarms.length === 0) {
    return <p className="muted">يلزم وجود أرض/أصل مسجل ومزرعة غير مرتبطة لإتمام الربط.</p>;
  }
  return (
    <form action={action} className="form-grid compact">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-land-farm-link" />
      <label>الأرض/الأصل<select name="landAssetId" required>{landAssets.map((asset) => <option key={asset.id} value={asset.id}>{asset.name} · {asset.internal_reference}</option>)}</select></label>
      <label>المزرعة<select name="farmId" required>{availableFarms.map((farm) => <option key={farm.id} value={farm.id}>{farm.name}</option>)}</select></label>
      <div><Result state={state} pending={pending} label="ربط المزرعة" /></div>
      <p className="muted full">الأرض أصل استثماري/قانوني، والمزرعة موقع تشغيل، والحقل وحدة زراعية داخل المزرعة.</p>
    </form>
  );
}

export function FarmForm({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  const [state, action, pending] = useActionState(createFarm, initial);
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-farm" />
      <label>
        اسم المزرعة
        <input name="name" required minLength={2} maxLength={160} autoFocus />
      </label>
      <label>
        مرجع داخلي <span className="muted">(اختياري)</span>
        <input name="internalReference" maxLength={80} />
      </label>
      <label>
        موقع التشغيل <span className="muted">(اختياري)</span>
        <input name="operatingLocation" maxLength={200} placeholder="مثال: الوادي الجديد، مصر" />
      </label>
      <label>
        المنطقة الزمنية
        <input name="timezone" required maxLength={64} defaultValue="Africa/Cairo" />
      </label>
      <label className="full">
        وصف الحيازة / السيطرة <span className="muted">(اختياري)</span>
        <textarea name="tenureDescription" maxLength={1000} placeholder="نوع العقد، المدة، الشروط الأساسية" />
      </label>
      <label className="full">
        مرجع الخريطة <span className="muted">(اختياري)</span>
        <input name="mapReference" maxLength={200} placeholder="وصف موضعي أو رابط مرجعي داخلي" />
      </label>
      <p className="muted full">
        لا نُضيف خدمة خرائط خارجية أو تكاملًا جغرافيًا. مرجع الخريطة نص وصفي يربط بمكان المزرعة فقط.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل المزرعة" />
      </div>
    </form>
  );
}

export function FieldForm({
  organizationId,
  projectId,
  farms,
}: {
  organizationId: string;
  projectId: string;
  farms: FarmRead[];
}) {
  const [state, action, pending] = useActionState(createField, initial);
  if (farms.length === 0) {
    return <p className="muted">أضف مزرعة أولًا قبل تسجيل الحقول.</p>;
  }
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-field" />
      <label>
        المزرعة
        <select name="farmId" required>
          {farms.map((f) => (
            <option key={f.id} value={f.id}>{f.name}</option>
          ))}
        </select>
      </label>
      <label>
        معرّف الحقل
        <input name="identifier" required minLength={1} maxLength={100} placeholder="مثال: حقل شمال-1" />
      </label>
      <label>
        المساحة
        <input name="areaQuantity" required inputMode="decimal" placeholder="12.5" />
      </label>
      <label>
        وحدة المساحة
        <select name="areaUnit" defaultValue="FEDDAN">
          <option value="FEDDAN">{AREA_UNIT_LABEL.FEDDAN}</option>
          <option value="HECTARE">{AREA_UNIT_LABEL.HECTARE}</option>
          <option value="M2">{AREA_UNIT_LABEL.M2}</option>
        </select>
      </label>
      <label className="full">
        ملاحظات التربة <span className="muted">(اختياري)</span>
        <textarea name="soilNotes" maxLength={2000} />
      </label>
      <label className="full">
        ملاحظات الري <span className="muted">(اختياري)</span>
        <textarea name="irrigationNotes" maxLength={2000} />
      </label>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل الحقل" />
      </div>
    </form>
  );
}

export function CropCycleForm({
  organizationId,
  projectId,
}: {
  organizationId: string;
  projectId: string;
}) {
  const [state, action, pending] = useActionState(createCropCycle, initial);
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-cycle" />
      <label>
        المحصول
        <input name="crop" required minLength={2} maxLength={80} autoFocus />
      </label>
      <label>
        الصنف <span className="muted">(اختياري)</span>
        <input name="variety" maxLength={80} />
      </label>
      <label>
        مرجع الموسم
        <input name="seasonReference" required minLength={2} maxLength={80} placeholder="مثال: 2026/2027-شتوي" />
      </label>
      <label>
        تاريخ البداية المخطط
        <input type="date" name="plannedStartDate" required />
      </label>
      <label>
        تاريخ النهاية المخطط
        <input type="date" name="plannedEndDate" required />
      </label>
      <label>
        كمية المحصول المستهدفة <span className="muted">(اختياري)</span>
        <input name="targetYieldQuantity" inputMode="decimal" placeholder="4500" />
      </label>
      <label>
        وحدة المحصول المستهدفة <span className="muted">(مع الكمية)</span>
        <input name="targetYieldUnit" maxLength={40} placeholder="كجم/فدان" />
      </label>
      <p className="muted full">
        دورة المحصول تبدأ في الحالة المخططة. الانتقال اللاحق يتم من قسم &quot;دورات المحصول&quot; أدناه.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="إنشاء دورة المحصول" />
      </div>
    </form>
  );
}

export function CycleTransitionForm({
  organizationId,
  projectId,
  cycle,
}: {
  organizationId: string;
  projectId: string;
  cycle: CropCycleRead;
}) {
  const stateKey = `ag-cycle-tr-${cycle.id}`;
  const [state, action, pending] = useActionState(transitionCropCycle, initial);
  const allowed = CYCLE_TRANSITIONS[cycle.operational_state] ?? [];
  if (allowed.length === 0) {
    return (
      <p className="muted" key={stateKey}>
        دورة مغلقة — لا توجد انتقالات لاحقة مسموح بها.
      </p>
    );
  }
  return (
    <form action={action} className="form-grid compact" key={stateKey}>
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix={`ag-cycle-tr-${cycle.id}`} />
      <input type="hidden" name="cropCycleId" value={cycle.id} />
      <input type="hidden" name="expectedState" value={cycle.operational_state} />
      <label>
        الحالة الجديدة
        <select name="newState" defaultValue={allowed[0]}>
          {allowed.map((s) => (
            <option key={s} value={s}>{CYCLE_STATE_LABEL[s]}</option>
          ))}
        </select>
      </label>
      <label>
        سبب الانتقال
        <input name="reason" required minLength={3} maxLength={500} />
      </label>
      <label>
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <div>
        <Result state={state} pending={pending} label="تأكيد الانتقال" pendingLabel="جارٍ التأكيد…" />
      </div>
    </form>
  );
}

export function AssignmentForm({
  organizationId,
  projectId,
  cycles,
  fields,
}: {
  organizationId: string;
  projectId: string;
  cycles: CropCycleRead[];
  fields: FieldRead[];
}) {
  const [state, action, pending] = useActionState(assignCropCycleToField, initial);
  const availableCycles = cycles.filter((c) => c.operational_state !== 'CANCELLED' && c.operational_state !== 'FAILED' && c.operational_state !== 'CLOSED');
  if (availableCycles.length === 0 || fields.length === 0) {
    return (
      <p className="muted">
        يلزم وجود دورة محصول نشطة وحقل مسجّل لتخصيص دورة لحقل.
      </p>
    );
  }
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-assign" />
      <label>
        دورة المحصول
        <select name="cropCycleId" required>
          {availableCycles.map((c) => (
            <option key={c.id} value={c.id}>
              {c.crop} — {c.season_reference} ({formatCycleState(c.operational_state)})
            </option>
          ))}
        </select>
      </label>
      <label>
        الحقل
        <select name="fieldId" required>
          {fields.map((f) => (
            <option key={f.id} value={f.id}>
              {f.identifier} — {f.area_quantity} {AREA_UNIT_LABEL[f.area_unit]}
            </option>
          ))}
        </select>
      </label>
      <label>
        المساحة المخصصة
        <input name="assignedAreaQuantity" required inputMode="decimal" placeholder="5" />
      </label>
      <label>
        وحدة المساحة
        <select name="assignedAreaUnit" defaultValue="FEDDAN">
          <option value="FEDDAN">{AREA_UNIT_LABEL.FEDDAN}</option>
          <option value="HECTARE">{AREA_UNIT_LABEL.HECTARE}</option>
          <option value="M2">{AREA_UNIT_LABEL.M2}</option>
        </select>
      </label>
      <label>
        تاريخ بداية التخصيص
        <input type="date" name="plannedStartDate" required />
      </label>
      <label>
        تاريخ نهاية التخصيص
        <input type="date" name="plannedEndDate" required />
      </label>
      <p className="muted full">
        وحدة المساحة يجب أن تطابق وحدة الحقل. مجموع المساحات المخصصة للحقل لا يتجاوز سعته.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تخصيص الحقل للدورة" />
      </div>
    </form>
  );
}

export function FieldActivityForm({
  organizationId,
  projectId,
  assignments,
  cycles,
  fields,
}: {
  organizationId: string;
  projectId: string;
  assignments: CropAssignmentRead[];
  cycles: CropCycleRead[];
  fields: FieldRead[];
}) {
  const [state, action, pending] = useActionState(createFieldActivity, initial);
  if (assignments.length === 0) {
    return (
      <p className="muted">
        يلزم وجود تخصيص دورة-حقل قائم قبل تسجيل نشاط ميداني. النشاط لا ينشئ تخصيصًا ولا يغيّر حالة الدورة.
      </p>
    );
  }
  const cycleById = new Map(cycles.map((c) => [c.id, c]));
  const fieldById = new Map(fields.map((f) => [f.id, f]));
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-activity" />
      <label className="full">
        التخصيص (الدورة والحقل)
        <select name="assignmentPicker" required defaultValue={assignments[0]?.id}
          onChange={(event) => {
            const selected = assignments.find((a) => a.id === event.target.value);
            const form = event.currentTarget.form;
            if (!form || !selected) return;
            (form.elements.namedItem('assignmentId') as HTMLInputElement).value = selected.id;
            (form.elements.namedItem('cropCycleId') as HTMLInputElement).value = selected.crop_cycle_id;
            (form.elements.namedItem('fieldId') as HTMLInputElement).value = selected.field_id;
          }}
        >
          {assignments.map((a) => {
            const cycle = cycleById.get(a.crop_cycle_id);
            const field = fieldById.get(a.field_id);
            return (
              <option key={a.id} value={a.id}>
                {cycle ? `${cycle.crop} — ${cycle.season_reference}` : 'دورة'} · {field?.identifier ?? 'حقل'}
              </option>
            );
          })}
        </select>
      </label>
      <input type="hidden" name="assignmentId" defaultValue={assignments[0].id} />
      <input type="hidden" name="cropCycleId" defaultValue={assignments[0].crop_cycle_id} />
      <input type="hidden" name="fieldId" defaultValue={assignments[0].field_id} />
      <label>
        تاريخ النشاط
        <input type="date" name="activityDate" required />
      </label>
      <label>
        نوع النشاط
        <select name="activityType" required defaultValue="IRRIGATE">
          {FIELD_ACTIVITY_TYPES.map((t) => (
            <option key={t} value={t}>{FIELD_ACTIVITY_TYPE_LABEL[t]}</option>
          ))}
        </select>
      </label>
      <label>
        الكمية <span className="muted">(اختياري)</span>
        <input name="quantity" inputMode="decimal" placeholder="12.5" />
      </label>
      <label>
        الوحدة <span className="muted">(مع الكمية)</span>
        <input name="unit" maxLength={40} placeholder="م³" />
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <label className="full">
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        تسجيل النشاط لا يحرّك دورة حياة المحصول ولا ينشئ مخزونًا أو قيدًا محاسبيًا.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل نشاط الحقل" />
      </div>
    </form>
  );
}

export { CYCLE_STATES };

// ---------------------------------------------------------------------------
// GF-015 — المدخلات والتطبيقات
//
// Three forms: define an input, register a traceable lot, and record an
// application of that lot against an existing field activity.
//
// The application form makes invalid combinations hard to select:
// choosing a FieldActivity fixes the project, crop cycle, field and
// assignment, and constrains the eligible input category; choosing an
// input filters the eligible lots and fixes the quantity unit; the
// treated-area unit is fixed to the assignment's own unit. The server
// re-derives and re-validates all of it and remains authoritative.
// ---------------------------------------------------------------------------

export function InputItemForm({
  organizationId,
  projectId,
}: {
  organizationId: string;
  projectId: string;
}) {
  const [state, action, pending] = useActionState(createInputItem, initial);
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-input-item" />
      <label>
        فئة المدخل
        <select name="category" required defaultValue="FERTILIZER">
          {INPUT_CATEGORIES.map((c) => (
            <option key={c} value={c}>{INPUT_CATEGORY_LABEL[c]}</option>
          ))}
        </select>
      </label>
      <label>
        اسم المدخل
        <input name="name" required minLength={2} maxLength={160} placeholder="مثال: يوريا 46%" />
      </label>
      <label>
        وحدة التطبيق
        <input name="applicationUnit" required maxLength={40} placeholder="كجم" />
      </label>
      <label>
        مرجع داخلي <span className="muted">(اختياري)</span>
        <input name="internalReference" maxLength={80} />
      </label>
      <label>
        المُصنِّع أو العلامة <span className="muted">(اختياري)</span>
        <input name="manufacturer" maxLength={160} />
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        تعريف المدخل لا يتضمن سعرًا أو موردًا محاسبيًا أو رصيد مخزون. هذه الشريحة تُثبت الهوية فقط.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل المدخل" />
      </div>
    </form>
  );
}

export function InputLotForm({
  organizationId,
  projectId,
  items,
}: {
  organizationId: string;
  projectId: string;
  items: InputItemRead[];
}) {
  const [state, action, pending] = useActionState(createInputLot, initial);
  const [itemId, setItemId] = useState(items[0]?.id ?? '');
  if (items.length === 0) {
    return <p className="muted">سجّل مدخلًا واحدًا على الأقل قبل تسجيل التشغيلات.</p>;
  }
  const selected = items.find((i) => i.id === itemId) ?? items[0];
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-input-lot" />
      <label>
        المدخل
        <select
          name="inputItemId"
          required
          value={itemId}
          onChange={(event) => setItemId(event.target.value)}
        >
          {items.map((i) => (
            <option key={i.id} value={i.id}>
              {INPUT_CATEGORY_LABEL[i.category]} · {i.name} ({i.application_unit})
            </option>
          ))}
        </select>
      </label>
      <label>
        مرجع التشغيلة
        <input name="lotReference" required minLength={1} maxLength={120} placeholder="LOT-2027-001" />
      </label>
      <label>
        مرجع المورد <span className="muted">(اختياري)</span>
        <input name="supplierReference" maxLength={200} />
      </label>
      <label>
        تاريخ التصنيع <span className="muted">(اختياري)</span>
        <input type="date" name="manufacturedOn" />
      </label>
      <label>
        تاريخ الانتهاء <span className="muted">(اختياري)</span>
        <input type="date" name="expiresOn" />
      </label>
      <label>
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        وحدة التشغيلة تُشتق من المدخل: <strong>{selected.application_unit}</strong>.
        التشغيلة سجل تتبّع وهوية، وليست رصيد مخزون: تسجيلها لا يعني توفر كمية.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل التشغيلة" />
      </div>
    </form>
  );
}

export function InputApplicationForm({
  organizationId,
  projectId,
  activities,
  assignments,
  cycles,
  fields,
  items,
  lots,
}: {
  organizationId: string;
  projectId: string;
  activities: FieldActivityRead[];
  assignments: CropAssignmentRead[];
  cycles: CropCycleRead[];
  fields: FieldRead[];
  items: InputItemRead[];
  lots: InputLotRead[];
}) {
  const [state, action, pending] = useActionState(recordInputApplication, initial);

  // Only activities that semantically apply an input are selectable.
  const eligibleActivities = useMemo(
    () => activities.filter((a) =>
      (INPUT_BEARING_ACTIVITY_TYPES as readonly string[]).includes(a.activity_type)),
    [activities],
  );
  const [activityId, setActivityId] = useState(eligibleActivities[0]?.id ?? '');
  const activity = eligibleActivities.find((a) => a.id === activityId) ?? eligibleActivities[0];

  const requiredCategory = activity ? inputCategoryForActivity(activity.activity_type) : null;
  const eligibleItems = useMemo(
    () => items.filter((i) => i.category === requiredCategory),
    [items, requiredCategory],
  );
  const [itemId, setItemId] = useState('');
  const item = eligibleItems.find((i) => i.id === itemId) ?? eligibleItems[0];

  // Selecting an input filters the eligible lots, and a lot that had
  // already expired on the activity date is not offered.
  const eligibleLots = useMemo(
    () => lots.filter((l) =>
      l.input_item_id === item?.id
      && (l.expires_on === null || !activity || l.expires_on >= activity.activity_date)),
    [lots, item?.id, activity],
  );
  const [lotId, setLotId] = useState('');
  const lot = eligibleLots.find((l) => l.id === lotId) ?? eligibleLots[0];

  const assignment = assignments.find((a) => a.id === activity?.assignment_id);
  const cycle = cycles.find((c) => c.id === activity?.crop_cycle_id);
  const field = fields.find((f) => f.id === activity?.field_id);

  if (eligibleActivities.length === 0) {
    return (
      <p className="muted">
        يلزم وجود نشاط حقل من نوع زراعة أو تسميد أو رش قبل تسجيل تطبيق مدخل.
        أنشطة المعاينة والري والتعشيب لا تستقبل مدخلات.
      </p>
    );
  }
  // Honest blocked states: keep the activity picker usable so the
  // operator can switch to an activity they can actually record,
  // instead of being shown a form that cannot be submitted.
  const blockedReason = (() => {
    if (!assignment) {
      return 'تعذر تحديد تخصيص الدورة-الحقل لهذا النشاط. حدّث الصفحة ثم أعد المحاولة.';
    }
    if (eligibleItems.length === 0) {
      return `النشاط المختار من نوع ${formatFieldActivityType(activity?.activity_type)} ويتطلب مدخلًا من فئة `
        + `${requiredCategory ? INPUT_CATEGORY_LABEL[requiredCategory] : '—'}. لا يوجد مدخل مسجّل بهذه الفئة بعد.`;
    }
    if (eligibleLots.length === 0) {
      return 'لا توجد تشغيلة سارية لهذا المدخل في تاريخ النشاط. سجّل تشغيلة صالحة أولًا.';
    }
    return null;
  })();

  const activityPicker = (
    <label className="full">
      نشاط الحقل
      <select
        name={blockedReason ? undefined : 'fieldActivityId'}
        required={!blockedReason}
        value={activityId}
        onChange={(event) => {
          setActivityId(event.target.value);
          setItemId('');
          setLotId('');
        }}
      >
        {eligibleActivities.map((a) => {
          const c = cycles.find((x) => x.id === a.crop_cycle_id);
          const f = fields.find((x) => x.id === a.field_id);
          return (
            <option key={a.id} value={a.id}>
              {formatFieldActivityType(a.activity_type)} · {a.activity_date}
              {c ? ` · ${c.crop} — ${c.season_reference}` : ''}
              {f ? ` · ${f.identifier}` : ''}
            </option>
          );
        })}
      </select>
    </label>
  );

  if (blockedReason) {
    return (
      <div className="form-grid">
        {activityPicker}
        {eligibleItems.length > 0 ? (
          <label>
            المدخل <span className="muted">({requiredCategory ? INPUT_CATEGORY_LABEL[requiredCategory] : '—'})</span>
            <select
              value={item?.id ?? ''}
              onChange={(event) => {
                setItemId(event.target.value);
                setLotId('');
              }}
            >
              {eligibleItems.map((i) => (
                <option key={i.id} value={i.id}>{i.name} ({i.application_unit})</option>
              ))}
            </select>
          </label>
        ) : null}
        <p className="muted full" role="status">{blockedReason}</p>
      </div>
    );
  }

  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-input-app" />
      {activityPicker}

      <p className="muted full" aria-live="polite">
        النشاط يحدد المشروع ودورة المحصول والحقل والتخصيص تلقائيًا:{' '}
        <strong>{cycle ? `${cycle.crop} — ${cycle.season_reference}` : '—'}</strong> ·{' '}
        <strong>{field?.identifier ?? '—'}</strong> · المساحة المخصصة{' '}
        <strong>
          {assignment ? `${assignment.assigned_area_quantity} ${AREA_UNIT_LABEL[assignment.assigned_area_unit]}` : '—'}
        </strong>
        . لا يُطلب منك اختيار هذه المعرّفات يدويًا.
      </p>

      <label>
        المدخل <span className="muted">({requiredCategory ? INPUT_CATEGORY_LABEL[requiredCategory] : '—'})</span>
        <select
          name="inputItemId"
          required
          value={item?.id ?? ''}
          onChange={(event) => {
            setItemId(event.target.value);
            setLotId('');
          }}
        >
          {eligibleItems.map((i) => (
            <option key={i.id} value={i.id}>{i.name} ({i.application_unit})</option>
          ))}
        </select>
      </label>

      <label>
        التشغيلة
        <select
          name="inputLotId"
          required
          value={lot?.id ?? ''}
          onChange={(event) => setLotId(event.target.value)}
        >
          {eligibleLots.map((l) => (
            <option key={l.id} value={l.id}>
              {l.lot_reference}
              {l.expires_on ? ` · تنتهي ${l.expires_on}` : ' · بدون تاريخ انتهاء'}
            </option>
          ))}
        </select>
      </label>

      <label>
        تاريخ التطبيق
        <input type="date" name="applicationDate" required defaultValue={activity?.activity_date} />
      </label>
      <label>
        الكمية المطبَّقة
        <input name="quantity" required inputMode="decimal" placeholder="200" />
      </label>
      <label>
        وحدة الكمية <span className="muted">(من المدخل)</span>
        <input name="unit" required readOnly value={item?.application_unit ?? ''} />
      </label>
      <label>
        المساحة المعالجة
        <input name="appliedAreaQuantity" required inputMode="decimal" placeholder="4" />
      </label>
      <label>
        وحدة المساحة <span className="muted">(من التخصيص)</span>
        <input
          name="appliedAreaUnit"
          required
          readOnly
          value={assignment?.assigned_area_unit ?? ''}
        />
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <label className="full">
        ملاحظة سلامة أو طقس <span className="muted">(اختياري)</span>
        <textarea name="safetyNote" maxLength={2000} placeholder="مثال: فترة أمان 7 أيام، رياح خفيفة" />
      </label>
      <label className="full">
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        المساحة المعالجة يجب ألا تتجاوز المساحة المخصصة لهذا التخصيص، والتشغيلة يجب أن تكون سارية في تاريخ التطبيق.
        النظام لا يتحقق من توفر رصيد مخزون: لا توجد حركات مخزون في هذه الشريحة.
        التسجيل لا يغيّر حالة دورة المحصول ولا ينشئ قيدًا محاسبيًا.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل تطبيق المدخل" />
      </div>
    </form>
  );
}

// ---------------------------------------------------------------------------
// GF-016 — الحصاد والمخزون
//
// Four forms: define a storage location, record an atomic harvest event
// (which creates the lot and its initial receipt), transfer quantity
// between locations, and record an adjustment/spoilage with a reason.
//
// The harvest form makes invalid combinations hard to choose: selecting a
// CropCycle limits the eligible fields to its own assignments (and the
// assignment is derived, never asked for); the destination storage is a
// valid location in the same project. The server re-derives project, cycle,
// field and assignment from the assignment and remains authoritative.
// ---------------------------------------------------------------------------

export function StorageLocationForm({
  organizationId,
  projectId,
}: {
  organizationId: string;
  projectId: string;
}) {
  const [state, action, pending] = useActionState(createStorageLocation, initial);
  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-storage" />
      <label>
        اسم موقع التخزين
        <input name="name" required minLength={2} maxLength={160} placeholder="مثال: مخزن رئيسي" />
      </label>
      <label>
        مرجع داخلي <span className="muted">(اختياري)</span>
        <input name="internalReference" maxLength={80} />
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <p className="muted full">
        موقع التخزين بسيط: اسم ومرجع وملاحظات فقط. لا توجد سعة أو مناطق أو رفوف أو أتمتة حرارية في هذه الشريحة.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل موقع التخزين" />
      </div>
    </form>
  );
}

export function HarvestEventForm({
  organizationId,
  projectId,
  cycles,
  assignments,
  fields,
  storages,
}: {
  organizationId: string;
  projectId: string;
  cycles: CropCycleRead[];
  assignments: CropAssignmentRead[];
  fields: FieldRead[];
  storages: StorageLocationRead[];
}) {
  const [state, action, pending] = useActionState(recordHarvestEvent, initial);

  // Only harvest-ready cycles are selectable.
  const harvestReadyCycles = cycles.filter((c) => c.operational_state === 'HARVESTING');
  const [cycleId, setCycleId] = useState(harvestReadyCycles[0]?.id ?? '');
  const cycle = harvestReadyCycles.find((c) => c.id === cycleId) ?? harvestReadyCycles[0];

  const eligibleAssignments = assignments.filter((a) => a.crop_cycle_id === cycle?.id);
  const [assignmentId, setAssignmentId] = useState(eligibleAssignments[0]?.id ?? '');
  const assignment = eligibleAssignments.find((a) => a.id === assignmentId) ?? eligibleAssignments[0];
  const field = fields.find((f) => f.id === assignment?.field_id);

  const fieldById = new Map(fields.map((f) => [f.id, f]));

  if (harvestReadyCycles.length === 0) {
    return (
      <p className="muted">
        لا توجد دورات محصول في حالة &quot;قيد الحصاد&quot;.
        انقل الدورة إلى حالة الحصاد أولًا من قسم &quot;دورات المحصول&quot; قبل تسجيل حدث حصاد.
      </p>
    );
  }

  const blockedReason = (() => {
    if (eligibleAssignments.length === 0) {
      return 'الدورة المختارة لا تحتوي على حقول مخصصة. خصّص حقلًا لهذه الدورة أولًا.';
    }
    if (storages.length === 0) {
      return 'لا يوجد موقع تخزين بعد. سجّل موقع تخزين لاستلام محصول الحصاد فيه.';
    }
    return null;
  })();

  const cyclePicker = (
    <label className="full">
      دورة المحصول (جاهزة للحصاد)
      <select
        name={blockedReason ? undefined : 'cyclePicker'}
        required={!blockedReason}
        value={cycleId}
        onChange={(event) => {
          setCycleId(event.target.value);
          setAssignmentId('');
        }}
      >
        {harvestReadyCycles.map((c) => (
          <option key={c.id} value={c.id}>
            {c.crop} — {c.season_reference} ({formatCycleState(c.operational_state)})
          </option>
        ))}
      </select>
    </label>
  );

  const assignmentPicker = eligibleAssignments.length > 0 ? (
    <label className="full">
      الحقل (التخصيص يُشتق تلقائيًا)
      <select
        name={blockedReason ? undefined : 'assignmentPicker'}
        required={!blockedReason}
        value={assignment?.id ?? ''}
        onChange={(event) => setAssignmentId(event.target.value)}
      >
        {eligibleAssignments.map((a) => {
          const f = fieldById.get(a.field_id);
          return (
            <option key={a.id} value={a.id}>
              {f?.identifier ?? 'حقل'} · {a.assigned_area_quantity} {AREA_UNIT_LABEL[a.assigned_area_unit]}
            </option>
          );
        })}
      </select>
    </label>
  ) : null;

  if (blockedReason) {
    return (
      <div className="form-grid">
        {cyclePicker}
        {assignmentPicker}
        <p className="muted full" role="status">{blockedReason}</p>
      </div>
    );
  }

  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-harvest" />
      <input type="hidden" name="assignmentId" value={assignment?.id ?? ''} />

      {cyclePicker}
      {assignmentPicker}

      <p className="muted full" aria-live="polite">
        التخصيص يحدد المشروع ودورة المحصول والحقل تلقائيًا:{' '}
        <strong>{cycle ? `${cycle.crop} — ${cycle.season_reference}` : '—'}</strong> ·{' '}
        <strong>{field?.identifier ?? '—'}</strong>. لا يُطلب منك إدخال هذه المعرّفات يدويًا.
      </p>

      <label>
        تاريخ الحصاد
        <input type="date" name="harvestDate" required />
      </label>
      <label>
        الكمية الإجمالية (الموزونة)
        <input name="grossQuantity" required inputMode="decimal" placeholder="100" />
      </label>
      <label>
        الكمية الصافية (المقبولة)
        <input name="netQuantity" required inputMode="decimal" placeholder="95" />
      </label>
      <label>
        وحدة الكمية
        <input name="quantityUnit" required maxLength={40} placeholder="كجم" />
      </label>
      <label>
        الدرجة / الجودة <span className="muted">(اختياري)</span>
        <input name="grade" maxLength={80} placeholder="درجة أولى" />
      </label>
      <label>
        مرجع تشغيلة الحصاد
        <input name="lotReference" required minLength={1} maxLength={120} placeholder="LOT-HV-001" />
      </label>
      <label>
        موقع التخزين المستلم
        <select name="destinationStorageId" required>
          {storages.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
      </label>
      <label className="full">
        ملاحظات <span className="muted">(اختياري)</span>
        <textarea name="notes" maxLength={2000} />
      </label>
      <label className="full">
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        الكمية الصافية يجب ألا تتجاوز الإجمالية، والفاقد (الإجمالي − الصافي) يُشتق تلقائيًا ولا يُخزَّن مرتين.
        تسجيل الحصاد ينشئ تشغيلة المحصول ويستلم كميتها الصافية في موقع التخزين المختار كحركة واحدة.
        لا يغيّر حالة دورة المحصول ولا ينشئ قيدًا محاسبيًا.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل حدث الحصاد" />
      </div>
    </form>
  );
}

export function TransferHarvestInventoryForm({
  organizationId,
  projectId,
  lots,
  inventory,
  storages,
}: {
  organizationId: string;
  projectId: string;
  lots: HarvestLotRead[];
  inventory: HarvestInventoryByLocationRead[];
  storages: StorageLocationRead[];
}) {
  const [state, action, pending] = useActionState(transferHarvestInventory, initial);

  const [lotId, setLotId] = useState(lots[0]?.id ?? '');
  const lot = lots.find((l) => l.id === lotId) ?? lots[0];

  const lotLocations = inventory.filter((e) => e.harvest_lot_id === lot?.id && Number(e.current_balance) > 0);
  const [fromStorageId, setFromStorageId] = useState(lotLocations[0]?.storage_id ?? '');
  const source = lotLocations.find((e) => e.storage_id === fromStorageId) ?? lotLocations[0];

  if (lots.length === 0) {
    return <p className="muted">لا توجد تشغيلات حصاد بعد. سجّل حدث حصاد أولًا قبل نقل المخزون.</p>;
  }
  if (lotLocations.length === 0) {
    return <p className="muted">لا يوجد رصيد حالي قابل للنقل لتشغيلة الحصاد المختارة.</p>;
  }

  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-transfer" />
      <input type="hidden" name="harvestLotId" value={lot?.id ?? ''} />

      <label>
        تشغيلة الحصاد
        <select
          name="lotPicker"
          value={lotId}
          onChange={(event) => {
            setLotId(event.target.value);
            setFromStorageId('');
          }}
        >
          {lots.map((l) => (
            <option key={l.id} value={l.id}>
              {l.lot_reference} · {l.crop} ({l.quantity_unit})
            </option>
          ))}
        </select>
      </label>

      <label>
        الموقع الحالي
        <select
          name="fromStorageId"
          required
          value={source?.storage_id ?? ''}
          onChange={(event) => setFromStorageId(event.target.value)}
        >
          {lotLocations.map((e) => (
            <option key={e.storage_id} value={e.storage_id}>
              {e.storage_name} · الرصيد الحالي {e.current_balance} {e.quantity_unit}
            </option>
          ))}
        </select>
      </label>

      <label>
        الموقع الوجهة
        <select name="toStorageId" required>
          {storages
            .filter((s) => s.id !== source?.storage_id)
            .map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
        </select>
      </label>

      <label>
        الكمية المنقولة
        <input name="quantity" required inputMode="decimal" placeholder="30" />
      </label>
      <label>
        تاريخ الحركة
        <input type="date" name="movementDate" required />
      </label>
      <label className="full">
        سبب <span className="muted">(اختياري)</span>
        <textarea name="reason" maxLength={500} />
      </label>
      <label className="full">
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        النقل يغيّر الموقع فقط ولا ينشئ كمية جديدة. وحدة الكمية تُشتق من تشغيلة الحصاد ولا يمكن تغييرها هنا.
        الرصيد المتاح يُحتسب من حركات المخزون ولا يُدخَل يدويًا.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تنفيذ النقل" />
      </div>
    </form>
  );
}

export function HarvestInventoryAdjustmentForm({
  organizationId,
  projectId,
  lots,
  inventory,
}: {
  organizationId: string;
  projectId: string;
  lots: HarvestLotRead[];
  inventory: HarvestInventoryByLocationRead[];
}) {
  const [state, action, pending] = useActionState(recordHarvestInventoryAdjustment, initial);

  const [lotId, setLotId] = useState(lots[0]?.id ?? '');
  const lot = lots.find((l) => l.id === lotId) ?? lots[0];

  const lotLocations = inventory.filter((e) => e.harvest_lot_id === lot?.id);
  const [storageId, setStorageId] = useState(lotLocations[0]?.storage_id ?? '');
  const location = lotLocations.find((e) => e.storage_id === storageId) ?? lotLocations[0];

  if (lots.length === 0) {
    return <p className="muted">لا توجد تشغيلات حصاد بعد. سجّل حدث حصاد أولًا قبل تعديل المخزون.</p>;
  }
  if (lotLocations.length === 0) {
    return <p className="muted">لا توجد مواقع تخزين لهذه التشغيلة بعد.</p>;
  }

  return (
    <form action={action} className="form-grid">
      <Context organizationId={organizationId} projectId={projectId} />
      <Key prefix="ag-adjust" />
      <input type="hidden" name="harvestLotId" value={lot?.id ?? ''} />

      <label>
        تشغيلة الحصاد
        <select
          name="lotPicker"
          value={lotId}
          onChange={(event) => {
            setLotId(event.target.value);
            setStorageId('');
          }}
        >
          {lots.map((l) => (
            <option key={l.id} value={l.id}>
              {l.lot_reference} · {l.crop} ({l.quantity_unit})
            </option>
          ))}
        </select>
      </label>

      <label>
        موقع التخزين
        <select
          name="storageId"
          required
          value={location?.storage_id ?? ''}
          onChange={(event) => setStorageId(event.target.value)}
        >
          {lotLocations.map((e) => (
            <option key={e.storage_id} value={e.storage_id}>
              {e.storage_name} · الرصيد الحالي {e.current_balance} {e.quantity_unit}
            </option>
          ))}
        </select>
      </label>

      <label>
        نوع الحركة
        <select name="movementType" required defaultValue="ADJUSTMENT_IN">
          <option value="ADJUSTMENT_IN">{HARVEST_MOVEMENT_TYPE_LABEL.ADJUSTMENT_IN}</option>
          <option value="ADJUSTMENT_OUT">{HARVEST_MOVEMENT_TYPE_LABEL.ADJUSTMENT_OUT}</option>
          <option value="SPOILAGE">{HARVEST_MOVEMENT_TYPE_LABEL.SPOILAGE}</option>
        </select>
      </label>

      <label>
        الكمية
        <input name="quantity" required inputMode="decimal" placeholder="10" />
      </label>
      <label>
        تاريخ الحركة
        <input type="date" name="movementDate" required />
      </label>
      <label className="full">
        السبب <span className="muted">(مطلوب)</span>
        <textarea name="reason" required minLength={3} maxLength={500} placeholder="مثال: جرد فعلي، تسوية، تلف أثناء التخزين" />
      </label>
      <label className="full">
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" maxLength={200} />
      </label>
      <p className="muted full">
        التعديل أو التالف يتطلب سببًا، ولا يمكن أن يجعل الرصيد سالبًا. التصحيحات حركات إضافية وليست تعديلًا على حركة سابقة.
      </p>
      <div className="full">
        <Result state={state} pending={pending} label="تسجيل الحركة" />
      </div>
    </form>
  );
}
