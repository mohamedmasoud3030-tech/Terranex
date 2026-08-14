'use client';

import { useActionState, useMemo } from 'react';
import type { ActionState } from '@/features/auth/actions';
import {
  assignCropCycleToField,
  createAgricultureProfile,
  createCropCycle,
  createFarm,
  createField,
  createFieldActivity,
  transitionCropCycle,
} from '@/features/agriculture/actions';
import type {
  CropAssignmentRead,
  CropCycleRead,
  FarmRead,
  FieldRead,
} from '@/features/agriculture/queries';
import { CYCLE_STATES, CYCLE_TRANSITIONS, FIELD_ACTIVITY_TYPES } from '@/features/agriculture/schema';
import {
  AREA_UNIT_LABEL,
  CYCLE_STATE_LABEL,
  FIELD_ACTIVITY_TYPE_LABEL,
  formatCycleState,
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
