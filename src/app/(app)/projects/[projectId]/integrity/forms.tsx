'use client';

import { useActionState, useState } from 'react';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import type { ActionState } from '@/features/auth/actions';
import type { ApprovalException, FxSnapshot } from '@/features/control/queries';
import {
  decideApprovalException,
  openApprovalException,
  recordFxConversion,
  recordFxSnapshot,
  registerTaxTreatment,
  resubmitApprovalException,
  setApprovalPolicy,
  setOrgReportingCurrency,
} from '@/features/control/actions';

const initialState: ActionState = {};

const POLICY_DOMAIN_LABEL: Record<string, string> = {
  OBLIGATION_AUTHORIZATION: 'اعتماد الالتزامات',
  PAYMENT_APPROVAL: 'اعتماد المدفوعات',
  BUDGET_APPROVAL: 'اعتماد الموازنة',
  BUDGET_EXCEPTION: 'استثناء الموازنة',
  RETAINAGE_RELEASE: 'الإفراج عن الحجز',
  DISPUTE_RESOLUTION: 'تسوية النزاعات',
};

const EXCEPTION_DOMAIN_LABEL: Record<string, string> = {
  BUDGET_CEILING: 'سقف الموازنة',
  PAYMENT_BLOCKED: 'دفع محظور',
  INVOICE_TOLERANCE: 'تجاوز فاتورة مورد',
  CLOSE_GATE: 'بوابة إقفال',
  DISPUTE_HOLD: 'حجز نزاع',
  OTHER_DISCLOSED: 'إفصاح آخر',
};

const SEVERITY_LABEL: Record<string, string> = {
  LOW: 'منخفضة',
  MEDIUM: 'متوسطة',
  HIGH: 'عالية',
  CRITICAL: 'حرجة',
};

const TAX_DOMAIN_LABEL: Record<string, string> = {
  VALUE_ADDED: 'القيمة المضافة',
  INCOME: 'الدخل',
  WITHHOLDING: 'الخصم من المنبع',
  PROPERTY: 'عقارية',
  PAYROLL: 'مرتبات',
  OTHER_DECLARED: 'أخرى معلنة',
};

const APPLIES_TO_LABEL: Record<string, string> = {
  SALES_REVENUE: 'إيرادات المبيعات',
  PROCUREMENT_SPEND: 'إنفاق المشتريات',
  INVESTOR_DISTRIBUTIONS: 'توزيعات المستثمرين',
  PROJECT_INCOME: 'دخل المشروع',
  ASSET_TRANSFERS: 'نقل الأصول',
};

const TREATMENT_LABEL: Record<string, string> = {
  ASSESSED_EXTERNALLY_AND_RECORDED: 'مُقدَّر خارجيًا ومسجَّل',
  ASSESSED_EXTERNALLY_NOT_RECORDED: 'مُقدَّر خارجيًا وغير مسجَّل',
  DEFERRED_PENDING_TAX_ADVISORY: 'مؤجل بانتظار مستشار ضريبي',
};

export function ApprovalPolicyForm({
  organizationId,
  commandNonce,
}: {
  organizationId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(setApprovalPolicy, initialState);
  const idempotencyKey = useCommandIdempotencyKey('policy-set', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          مجال السياسة
          <select name="policyDomain" required>
            {Object.entries(POLICY_DOMAIN_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          حد المبلغ (بالوحدات الصغرى، اختياري)
          <input name="thresholdMinorUnits" inputMode="numeric" placeholder="500000" />
        </label>
        <label>
          العملة (اختياري)
          <input name="currency" maxLength={3} placeholder="EGP" />
        </label>
        <label>
          عدد المعتمدين المستقلين (تدرج الاعتماد 1-3)
          <select name="minApprovers" defaultValue="1">
            <option value="1">معتمد واحد (حد المالك الأساسي)</option>
            <option value="2">معتمدان مستقلان</option>
            <option value="3">ثلاثة معتمدين مستقلين</option>
          </select>
        </label>
      </div>
      <input type="hidden" name="evidenceRequired" value="false" />
      <label>
        <input type="checkbox" name="evidenceRequired" value="true" /> يتطلب مستندًا مرجعيًا عند تجاوز الحد
      </label>
      <input type="hidden" name="active" value="false" />
      <label>
        <input type="checkbox" name="active" value="true" defaultChecked /> سياسة مفعّلة
      </label>
      <p className="muted">السياسة تزيد الصرامة فقط؛ لا يمكنها أبدًا تخفيف حدّ المالك أو فصل الصلاحيات.</p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الحفظ…' : 'حفظ السياسة'}
      </button>
    </form>
  );
}

export function OpenExceptionForm({
  organizationId,
  projectId,
  subjects,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  subjects: { type: string; id: string; label: string }[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(openApprovalException, initialState);
  const idempotencyKey = useCommandIdempotencyKey('exception-open', state, commandNonce);
  // Subject selection is keyed by a unique `type::id` so picking the second
  // budget line can never record the exception against the first one.
  const [subjectKey, setSubjectKey] = useState('');
  const subject = subjects.find((s) => `${s.type}::${s.id}` === subjectKey) ?? null;
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <input type="hidden" name="subjectType" value={subject ? subject.type : 'none'} />
      <input type="hidden" name="subjectId" value={subject ? subject.id : ''} />
      <div className="grid">
        <label>
          مجال الاستثناء
          <select name="exceptionDomain" required>
            {Object.entries(EXCEPTION_DOMAIN_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          الموضوع
          <select
            value={subjectKey}
            onChange={(event) => setSubjectKey(event.target.value)}
            aria-label="موضوع الاستثناء"
          >
            <option value="">بدون موضوع محدد</option>
            {subjects.map((s) => (
              <option key={`${s.type}::${s.id}`} value={`${s.type}::${s.id}`}>{s.label}</option>
            ))}
          </select>
        </label>
        <label>
          الخطورة
          <select name="severity" defaultValue="MEDIUM" required>
            {Object.entries(SEVERITY_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          تاريخ الاستحقاق (اختياري)
          <input type="date" name="dueDate" />
        </label>
      </div>
      <div className="grid">
        <label>
          المبلغ (بالوحدات الصغرى، اختياري)
          <input name="amountMinorUnits" inputMode="numeric" placeholder="100000" />
        </label>
        <label>
          العملة (اختياري — تُشتق من الموازنة لاستثناءات السقف)
          <input name="currency" maxLength={3} placeholder="EGP" />
        </label>
        <label>
          المالك المسؤول (اختياري — افتراضيًا فاتح الاستثناء)
          <input name="ownerId" placeholder="00000000-0000-4000-8000-000000000000" />
        </label>
      </div>
      <label>
        السبب
        <textarea name="reason" required minLength={3} maxLength={1000} placeholder="سبب طلب الاستثناء" />
      </label>
      <label>
        مرجع المستند
        <input name="evidenceReference" maxLength={500} placeholder="مستند داعم" />
      </label>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الفتح…' : 'فتح استثناء'}
      </button>
    </form>
  );
}

export function DecideExceptionForm({
  organizationId,
  projectId,
  exception,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  exception: ApprovalException;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(decideApprovalException, initialState);
  const idempotencyKey = useCommandIdempotencyKey('exception-decide', state, commandNonce);
  if (exception.status !== 'OPEN') return null;
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="exceptionId" value={exception.exception_id} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        القرار
        <select name="decision" required>
          <option value="APPROVED">اعتماد</option>
          <option value="REJECTED">رفض</option>
          <option value="VOID">إبطال</option>
        </select>
      </label>
      <label>
        ملاحظة القرار
        <textarea name="decisionNote" required minLength={3} maxLength={1000} />
      </label>
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ التسجيل…' : 'تسجيل القرار'}
      </button>
      {state.error ? <p className="error">{state.error}</p> : null}
    </form>
  );
}

export function ResubmitExceptionForm({
  organizationId,
  projectId,
  exception,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  exception: ApprovalException;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(resubmitApprovalException, initialState);
  const idempotencyKey = useCommandIdempotencyKey('exception-resubmit', state, commandNonce);
  if (exception.status !== 'REJECTED') return null;
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="exceptionId" value={exception.exception_id} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        سبب إعادة التقديم
        <textarea name="reason" required minLength={3} maxLength={1000} />
      </label>
      <label>
        مرجع المستند (اختياري)
        <input name="evidenceReference" maxLength={500} />
      </label>
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ إعادة التقديم…' : 'إعادة التقديم (استثناء جديد مفتوح)'}
      </button>
      {state.error ? <p className="error">{state.error}</p> : null}
    </form>
  );
}

export function FxSnapshotForm({
  organizationId,
  projectId,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(recordFxSnapshot, initialState);
  const idempotencyKey = useCommandIdempotencyKey('fx-snapshot', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          عملة الأساس
          <input name="baseCurrency" maxLength={3} required placeholder="EGP" />
        </label>
        <label>
          عملة التسعير
          <input name="quoteCurrency" maxLength={3} required placeholder="USD" />
        </label>
        <label>
          البسط (وحدات التسعير)
          <input name="rateNumerator" inputMode="numeric" required placeholder="1" />
        </label>
        <label>
          المقام (وحدات الأساس)
          <input name="rateDenominator" inputMode="numeric" required placeholder="100" />
        </label>
      </div>
      <div className="grid">
        <label>
          تاريخ السعر
          <input type="date" name="rateDate" required />
        </label>
        <label>
          المصدر
          <select name="rateSource" required>
            <option value="EXTERNAL_PROVIDER_STATEMENT">بيان مزود خارجي</option>
            <option value="MANUAL_ENTRY">إدخال يدوي</option>
          </select>
        </label>
      </div>
      <label>
        مرجع المزود (اختياري)
        <input name="providerReference" maxLength={200} placeholder="rate-provider-001" />
      </label>
      <label>
        ملاحظات (اختياري)
        <input name="notes" maxLength={1000} />
      </label>
      <p className="muted">اللقطة حقيقة مسجلة غير قابلة للتعديل بعد الحفظ.</p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الحفظ…' : 'تسجيل لقطة سعر الصرف'}
      </button>
    </form>
  );
}

export function FxConversionForm({
  organizationId,
  projectId,
  snapshots,
  commandNonce,
}: {
  organizationId: string;
  projectId: string;
  snapshots: FxSnapshot[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(recordFxConversion, initialState);
  const idempotencyKey = useCommandIdempotencyKey('fx-conversion', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          المبلغ (بالوحدات الصغرى لعملة المصدر)
          <input name="sourceAmountMinorUnits" inputMode="numeric" required placeholder="250000" />
        </label>
        <label>
          لقطة السعر
          <select name="rateSnapshotId" required>
            <option value="" disabled>اختر اللقطة</option>
            {snapshots.map((s) => (
              <option key={s.snapshot_id} value={s.snapshot_id}>
                {s.base_currency} → {s.quote_currency} ({s.rate_numerator}/{s.rate_denominator}) في {s.rate_date}
              </option>
            ))}
          </select>
        </label>
        <label>
          تاريخ التحويل
          <input type="date" name="conversionDate" required />
        </label>
        <label>
          الغرض
          <select name="purpose" required>
            <option value="REPORTING_ROLLUP">تجميع تقارير</option>
            <option value="DISCLOSURE">إفصاح</option>
            <option value="RECONCILIATION">مطابقة</option>
          </select>
        </label>
      </div>
      <p className="muted">
        تُشتق عملتا المصدر والهدف من اللقطة نفسها؛ يُحسب الناتج حتميًا من كسر السعر المختار.
      </p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ التسجيل…' : 'تسجيل تحويل محدد'}
      </button>
    </form>
  );
}

export function OrgReportingCurrencyForm({
  organizationId,
  current,
  commandNonce,
}: {
  organizationId: string;
  current: string | null;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(setOrgReportingCurrency, initialState);
  const idempotencyKey = useCommandIdempotencyKey('org-currency', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        عملة التقارير الموحدة للمنظمة
        <input name="reportingCurrency" maxLength={3} defaultValue={current ?? ''} placeholder="USD" />
      </label>
      <p className="muted">
        تُترك فارغة لتعطيل التوحيد. الأرقام الموحدة لا تظهر أبدًا إلا إذا توفرت لقطة سعر
        لكل عملة مشروع.
      </p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الحفظ…' : 'حفظ عملة التقارير'}
      </button>
    </form>
  );
}

export function TaxTreatmentForm({
  organizationId,
  commandNonce,
}: {
  organizationId: string;
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(registerTaxTreatment, initialState);
  const idempotencyKey = useCommandIdempotencyKey('tax-register', state, commandNonce);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <div className="grid">
        <label>
          مجال الضريبة
          <select name="taxDomain" required>
            {Object.entries(TAX_DOMAIN_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          اسم الضريبة
          <input name="taxName" required minLength={2} maxLength={160} placeholder="ضريبة القيمة المضافة" />
        </label>
        <label>
          نطاق التطبيق
          <select name="appliesTo" required>
            {Object.entries(APPLIES_TO_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          حالة المعالجة
          <select name="treatmentStatus" required>
            {Object.entries(TREATMENT_LABEL).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
      </div>
      <div className="grid">
        <label>
          جهة التقدير (اختياري)
          <input name="authority" maxLength={200} placeholder="مصلحة الضرائب / مستشار معتمد" />
        </label>
        <label>
          تاريخ السريان
          <input type="date" name="effectiveFrom" required />
        </label>
        <label>
          تاريخ الانتهاء (اختياري)
          <input type="date" name="effectiveTo" />
        </label>
      </div>
      <label>
        ملاحظات المعالجة
        <textarea name="notes" required minLength={3} maxLength={1000} placeholder="مثال: تتطلب اعتماد مستشار ضريبي قبل أي ترحيل" />
      </label>
      <p className="muted">
        Terranex يسجل عقد المعالجة الضريبية صراحةً ولا يحسب أي ضريبة من تلقاء نفسه.
      </p>
      {state.error ? <p className="error">{state.error}</p> : null}
      <button disabled={pending} type="submit" className="button">
        {pending ? 'جارٍ الحفظ…' : 'تسجيل المعالجة الضريبية'}
      </button>
    </form>
  );
}
