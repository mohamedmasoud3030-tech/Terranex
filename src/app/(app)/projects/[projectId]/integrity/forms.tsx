'use client';

import { useActionState, useMemo, useState } from 'react';
import {
  decideApprovalException,
  openApprovalException,
  recordFxConversion,
  recordFxSnapshot,
  registerTaxTreatment,
  setApprovalPolicy,
  setOrgReportingCurrency,
} from '@/features/control/actions';
import type {
  ApprovalException,
  FxSnapshot,
} from '@/features/control/queries';

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

export function ApprovalPolicyForm({ organizationId }: { organizationId: string }) {
  const [state, action, pending] = useActionState(setApprovalPolicy, { error: undefined });
  const idempotencyKey = useMemo(() => `policy-${crypto.randomUUID()}`, []);
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
      </div>
      <label>
        <input type="checkbox" name="evidenceRequired" value="true" /> يتطلب مستندًا مرجعيًا عند تجاوز الحد
      </label>
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
}: {
  organizationId: string;
  projectId: string;
  subjects: { type: string; id: string; label: string }[];
}) {
  const [state, action, pending] = useActionState(openApprovalException, { error: undefined });
  const idempotencyKey = useMemo(() => `exception-${crypto.randomUUID()}`, []);
  const [subjectKey, setSubjectKey] = useState('');
  const subject = subjects.find((s) => s.type === subjectKey) ?? null;
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
              <option key={s.type} value={s.type}>{s.label}</option>
            ))}
          </select>
        </label>
      </div>
      <div className="grid">
        <label>
          المبلغ (بالوحدات الصغرى، اختياري)
          <input name="amountMinorUnits" inputMode="numeric" placeholder="100000" />
        </label>
        <label>
          العملة (اختياري)
          <input name="currency" maxLength={3} placeholder="EGP" />
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
}: {
  organizationId: string;
  projectId: string;
  exception: ApprovalException;
}) {
  const [state, action, pending] = useActionState(decideApprovalException, { error: undefined });
  const idempotencyKey = useMemo(() => `exception-decide-${crypto.randomUUID()}`, []);
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
          <option value="VOID">سحب (باطل)</option>
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

export function FxSnapshotForm({
  organizationId,
  projectId,
}: {
  organizationId: string;
  projectId: string;
}) {
  const [state, action, pending] = useActionState(recordFxSnapshot, { error: undefined });
  const idempotencyKey = useMemo(() => `fx-snapshot-${crypto.randomUUID()}`, []);
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
}: {
  organizationId: string;
  projectId: string;
  snapshots: FxSnapshot[];
}) {
  const [state, action, pending] = useActionState(recordFxConversion, { error: undefined });
  const idempotencyKey = useMemo(() => `fx-conversion-${crypto.randomUUID()}`, []);
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
        يُحسب الناتج حتميًا من كسر السعر المختار (تقريب نصف لأعلى بأعداد صحيحة)؛ مصدر العملة
        وعملة الهدف مأخوذان من اللقطة نفسها.
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
}: {
  organizationId: string;
  current: string | null;
}) {
  const [state, action, pending] = useActionState(setOrgReportingCurrency, { error: undefined });
  const idempotencyKey = useMemo(() => `org-currency-${crypto.randomUUID()}`, []);
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

export function TaxTreatmentForm({ organizationId }: { organizationId: string }) {
  const [state, action, pending] = useActionState(registerTaxTreatment, { error: undefined });
  const idempotencyKey = useMemo(() => `tax-${crypto.randomUUID()}`, []);
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
