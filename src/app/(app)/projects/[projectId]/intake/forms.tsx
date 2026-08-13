'use client';

import { useActionState, useId } from 'react';
import { useFormStatus } from 'react-dom';
import type { ActionState } from '@/features/auth/actions';
import {
  acceptModellingGapAction,
  declareControlTotalsAction,
  declareSectionApplicabilityAction,
  recordEvidenceItemAction,
  recordFreezeDateAction,
  recordSetupReferencesAction,
  reportModellingGapAction,
} from '@/features/intake/actions';
import type { ConditionalSectionCode } from '@/features/intake/schema';

const initial: ActionState = {};

function Submit({ children, disabled = false }: { children: string; disabled?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button className="button" type="submit" disabled={disabled || pending}>
      {pending ? 'جارٍ الحفظ…' : children}
    </button>
  );
}

function ErrorBanner({ state }: { state: ActionState }) {
  return state.error ? <p className="error" role="alert">{state.error}</p> : null;
}

export function FreezeDateForm({
  organizationId, projectId, freezeDate, disabled,
}: {
  organizationId: string;
  projectId: string;
  freezeDate?: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(recordFreezeDateAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        تاريخ التجميد
        <input type="date" name="freezeDate" required defaultValue={freezeDate} />
      </label>
      <label>
        مرجع دليل الاتفاق على التاريخ
        <input name="evidenceReference" required minLength={3} maxLength={200} placeholder="مثال: FREEZE-2026-03-31" />
      </label>
      <p className="muted">يُسجَّل مرة واحدة. أي تصحيح لاحق هو استخراج مؤرخ جديد، لا إعادة كتابة.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تثبيت تاريخ التجميد</Submit>
    </form>
  );
}

export function SetupReferencesForm({
  organizationId, projectId, agreementTitle, organizationEvidence, projectEvidence, disabled,
}: {
  organizationId: string;
  projectId: string;
  agreementTitle?: string;
  organizationEvidence?: string;
  projectEvidence?: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(recordSetupReferencesAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        عنوان الاتفاقية أو مرجعها
        <input name="agreementTitleOrReference" minLength={2} maxLength={160} defaultValue={agreementTitle} placeholder="مثال: اتفاقية الشركاء — مشروع النخيل" />
      </label>
      <label>
        مرجع السجل التجاري للمنظمة
        <input name="organizationEvidenceReference" minLength={3} maxLength={200} defaultValue={organizationEvidence} placeholder="مثال: CR-12345" />
      </label>
      <label>
        مرجع نطاق المشروع التجريبي
        <input name="projectEvidenceReference" minLength={3} maxLength={200} defaultValue={projectEvidence} placeholder="مثال: PILOT-SCOPE-01" />
      </label>
      <p className="muted">المستندات تبقى في أنظمة العميل. هنا تُحفظ المعرّفات فقط.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>حفظ مراجع الإعداد</Submit>
    </form>
  );
}

export function ControlTotalsForm({
  organizationId, projectId, debit, credit, disabled,
}: {
  organizationId: string;
  projectId: string;
  debit?: string;
  credit?: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(declareControlTotalsAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        إجمالي المدين المعلن (وحدات صغرى)
        <input name="declaredDebitTotal" inputMode="numeric" pattern="\d{1,19}" required defaultValue={debit ?? ''} placeholder="مثال: 125000 لـ 1,250.00 جنيه" />
      </label>
      <label>
        إجمالي الدائن المعلن (وحدات صغرى)
        <input name="declaredCreditTotal" inputMode="numeric" pattern="\d{1,19}" required defaultValue={credit ?? ''} />
      </label>
      <label>
        مرجع المجاميع الموقعة
        <input name="evidenceReference" required minLength={3} maxLength={200} placeholder="مثال: TB-SIGNED-2026-03-31" />
      </label>
      <p className="muted">1,250.00 جنيه = 125000 وحدة صغرى. المدين يجب أن يساوي الدائن. لا قيد تسوية.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تثبيت المجاميع الرقابية</Submit>
    </form>
  );
}

const SECTION_LABEL: Record<ConditionalSectionCode, string> = {
  HISTORICAL_CALLS: 'طلبات رأس المال التاريخية',
  HISTORICAL_CONTRIBUTIONS: 'المساهمات التاريخية عبر مسار التمويل',
  ACQUISITION_BASIS: 'أساس الاستحواذ',
  DEVELOPMENT_BASELINE: 'ميزانية التطوير',
  UNPAID_SUPPLIERS: 'التزامات موردين غير مسددة',
  SALES_DISPOSITIONS: 'مبيعات أو تصرفات قبل التجميد',
  HISTORICAL_DISTRIBUTIONS: 'توزيعات معتمدة غير مدفوعة',
  BANK_STATEMENTS: 'كشوف البنك من التشغيل الحي',
};

export function SectionApplicabilityForm({
  organizationId, projectId, sectionCode, disabled,
}: {
  organizationId: string;
  projectId: string;
  sectionCode: ConditionalSectionCode;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(declareSectionApplicabilityAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="sectionCode" value={sectionCode} />
      <fieldset className="stack">
        <legend>{SECTION_LABEL[sectionCode]}</legend>
        <label>
          <input type="radio" name="applicable" value="true" defaultChecked />
          ينطبق — سأدخل البيانات عبر الأمر المعتمد
        </label>
        <label>
          <input type="radio" name="applicable" value="false" />
          لا ينطبق على هذا المشروع في تاريخ التجميد
        </label>
      </fieldset>
      <label>
        السبب
        <input name="reason" required minLength={3} maxLength={500} aria-describedby={`${id}-hint`} />
      </label>
      <label>
        مرجع الدليل <span className="muted">(اختياري)</span>
        <input name="evidenceReference" minLength={3} maxLength={200} />
      </label>
      <p id={`${id}-hint`} className="muted">التصريح «لا ينطبق» قرار تشغيلي موثق، لا تخمين محاسبي.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>حفظ تصنيف القسم</Submit>
    </form>
  );
}

export function ModellingGapForm({
  organizationId, projectId, disabled,
}: {
  organizationId: string;
  projectId: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(reportModellingGapAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        مرجع السطر في المصدر
        <input name="sourceReference" required minLength={3} maxLength={200} placeholder="مثال: TB-LINE-240" />
      </label>
      <label>
        وصف الرصيد
        <input name="description" required minLength={3} maxLength={500} />
      </label>
      <label>
        المبلغ بالوحدات الصغرى <span className="muted">(اختياري)</span>
        <input name="amountMinorUnits" inputMode="numeric" pattern="\d{1,19}" />
      </label>
      <label>
        لماذا لا يناسب أي ترميز افتتاحي معتمد؟
        <textarea name="whyUnmappable" required minLength={3} maxLength={1000} placeholder="مثال: قرض شريك — لا يوجد ترميز افتتاحي لالتزامات القروض في الإصدار الحالي." />
      </label>
      <p className="muted">لا تُجبر الرصيد على أقرب ترميز. الفجوة قرار تجاري لا مسار ترحيل.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>إيقاف السطر وتسجيل الفجوة</Submit>
    </form>
  );
}

export function AcceptModellingGapForm({
  organizationId, projectId, gapId, disabled,
}: {
  organizationId: string;
  projectId: string;
  gapId: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(acceptModellingGapAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="gapId" value={gapId} />
      <label>
        مرجع القبول التجاري
        <input name="resolutionEvidenceReference" required minLength={3} maxLength={200} />
      </label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>قبول الفجوة تجاريًا دون ترحيل</Submit>
    </form>
  );
}

export function EvidenceItemForm({
  organizationId, projectId, disabled,
}: {
  organizationId: string;
  projectId: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(recordEvidenceItemAction, initial);
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        معرّف الدليل
        <input name="evidenceIdentifier" required minLength={3} maxLength={200} placeholder="مثال: EVID-AGREEMENT-01" />
      </label>
      <label>
        الحقيقة المرتبطة
        <input name="linkedFact" required minLength={3} maxLength={200} placeholder="مثال: اتفاقية الشركاء / رصيد البنك الأهلي" />
      </label>
      <label>
        موقع الحفظ لدى العميل
        <input name="customerStorageLocation" required minLength={3} maxLength={300} placeholder="مثال: مجلد الشؤون القانونية / خزانة العقود" />
      </label>
      <p className="muted">لا تُرفع مستندات العميل إلى تيرانكس أو إلى GitHub.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>إضافة مرجع دليل</Submit>
    </form>
  );
}
