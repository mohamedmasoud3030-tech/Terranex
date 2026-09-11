'use client';

import { useActionState, useId } from 'react';
import { useFormStatus } from 'react-dom';
import type { ActionState } from '@/features/auth/actions';
import {
  acceptUatTaskAction,
  approveOpeningImportAction,
  recordCheckpointAction,
  recordUatExecutionAction,
  registerUatTaskAction,
  rejectOpeningImportAction,
  rejectUatTaskAction,
  resolveExceptionAction,
  reviewOpeningImportAction,
  setMembershipStatusAction,
  signOffCheckpointAction,
  stageOpeningImportAction,
  validateOpeningImportAction,
} from '@/features/pilot/actions';
import { OPENING_SCHEMA_VERSION } from '@/features/pilot/schema';

const initial: ActionState = {};

function key(prefix: string, reactId: string) {
  return `${prefix}-${reactId.replace(/[^a-zA-Z0-9]/g, '')}-idempotency`.slice(0, 120);
}

function ErrorBanner({ state }: { state: ActionState }) {
  return state.error ? <p className="error" role="alert">{state.error}</p> : null;
}

function Submit({ children, disabled = false }: { children: string; disabled?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button className="button" type="submit" disabled={disabled || pending}>
      {pending ? 'جارٍ التنفيذ…' : children}
    </button>
  );
}

export type MappingCodeOption = {
  code: string;
  label: string;
  naturalSide: 'DEBIT' | 'CREDIT';
  requiresParty: boolean;
  requiresCashAccount: boolean;
};

export type PartyOption = { id: string; legalName: string };
export type CashAccountOption = { id: string; name: string };
export type MemberOption = { userId: string; role: string; status: string };

const OPENING_ROW_SLOTS = [0, 1, 2, 3, 4, 5, 6, 7];

/**
 * Stages a controlled opening file. The browser never computes an accepted
 * amount, a control total or a mapping decision: it transports exactly what
 * the operator read from the source file, and PostgreSQL normalizes, validates
 * row by row, and recomputes the control totals itself.
 */
export function StageOpeningImportForm({
  organizationId, projectId, mappingCodes, parties, cashAccounts, disabled,
}: {
  organizationId: string;
  projectId: string;
  mappingCodes: MappingCodeOption[];
  parties: PartyOption[];
  cashAccounts: CashAccountOption[];
  disabled?: boolean;
}) {
  const [state, action] = useActionState(stageOpeningImportAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="schemaVersion" value={OPENING_SCHEMA_VERSION} />
      <input type="hidden" name="idempotencyKey" value={key('s7-stage', id)} />
      <div className="form-grid">
        <label>
          <span>اسم ملف المصدر</span>
          <input name="sourceFileName" minLength={3} maxLength={200} required placeholder="opening-balances-2026.csv" />
        </label>
        <label>
          <span>بصمة SHA-256 للملف</span>
          <input name="sourceFileChecksum" minLength={64} maxLength={64} pattern="[0-9a-fA-F]{64}" required
            placeholder="64 خانة ست عشرية" />
        </label>
        <label>
          <span>إجمالي المدين المعلن (وحدات صغرى)</span>
          <input name="declaredDebitTotal" inputMode="numeric" pattern="\d{1,19}" required defaultValue="0" />
        </label>
        <label>
          <span>إجمالي الدائن المعلن (وحدات صغرى)</span>
          <input name="declaredCreditTotal" inputMode="numeric" pattern="\d{1,19}" required defaultValue="0" />
        </label>
      </div>

      <div className="table-wrap">
        <table>
              <caption className="sr-only">جدول: الترميز المعتمد · الطرف · الحساب النقدي · مدين (وحدات صغرى) · دائن (وحدات صغرى) · الوصف</caption>
          <thead>
            <tr>
              <th scope="col" className="num">الترميز المعتمد</th>
              <th scope="col">الطرف</th>
              <th scope="col">الحساب النقدي</th>
              <th scope="col">مدين (وحدات صغرى)</th>
              <th scope="col">دائن (وحدات صغرى)</th>
              <th scope="col">الوصف</th>
            </tr>
          </thead>
          <tbody>
            {OPENING_ROW_SLOTS.map((slot) => (
              <tr key={slot}>
                <td className="num">
                  <select name="mappingCode" defaultValue="" aria-label={`ترميز السطر ${slot + 1}`}>
                    <option value="">— لا يُدرج —</option>
                    {mappingCodes.map((mapping) => (
                      <option key={mapping.code} value={mapping.code}>
                        {mapping.label} ({mapping.naturalSide === 'DEBIT' ? 'مدين' : 'دائن'})
                      </option>
                    ))}
                  </select>
                </td>
                <td>
                  <select name="partyId" defaultValue="" aria-label={`طرف السطر ${slot + 1}`}>
                    <option value="">—</option>
                    {parties.map((party) => (
                      <option key={party.id} value={party.id}>{party.legalName}</option>
                    ))}
                  </select>
                </td>
                <td>
                  <select name="cashAccountId" defaultValue="" aria-label={`حساب نقدي للسطر ${slot + 1}`}>
                    <option value="">—</option>
                    {cashAccounts.map((account) => (
                      <option key={account.id} value={account.id}>{account.name}</option>
                    ))}
                  </select>
                </td>
                <td><input name="debit" inputMode="numeric" pattern="\d{0,19}" aria-label={`مدين السطر ${slot + 1}`} /></td>
                <td><input name="credit" inputMode="numeric" pattern="\d{0,19}" aria-label={`دائن السطر ${slot + 1}`} /></td>
                <td><input name="description" maxLength={500} aria-label={`وصف السطر ${slot + 1}`} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="muted">
        السطور غير المُرمَّزة لا تُرسل. المبالغ تُدخل بالوحدات الصغرى الصحيحة كما وردت في الملف؛
        قاعدة البيانات هي التي تُطبّع النص وتقبل أو ترفض كل سطر وتعيد حساب مجاميع الرقابة.
      </p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تجهيز مسودة الاستيراد الافتتاحي</Submit>
    </form>
  );
}

export function ValidateOpeningImportForm({ organizationId, projectId, importId, disabled }: {
  organizationId: string; projectId: string; importId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(validateOpeningImportAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="importId" value={importId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-validate', id)} />
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تشغيل التحقق وإعادة حساب المجاميع</Submit>
    </form>
  );
}

export function ReviewOpeningImportForm({ organizationId, projectId, importId, disabled }: {
  organizationId: string; projectId: string; importId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(reviewOpeningImportAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="importId" value={importId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-review', id)} />
      <label>
        <span>ملاحظات المراجعة (اختياري)</span>
        <textarea name="reviewNotes" rows={2} maxLength={2000} />
      </label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>ترشيح الاستيراد للاعتماد</Submit>
    </form>
  );
}

export function ApproveOpeningImportForm({ organizationId, projectId, importId, postingDate, disabled }: {
  organizationId: string; projectId: string; importId: string; postingDate: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(approveOpeningImportAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="importId" value={importId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-approve', id)} />
      <label><span>تاريخ الترحيل</span><input type="date" name="postingDate" required defaultValue={postingDate} /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>اعتماد الاستيراد وترحيل القيد الافتتاحي</Submit>
    </form>
  );
}

export function RejectOpeningImportForm({ organizationId, projectId, importId, disabled }: {
  organizationId: string; projectId: string; importId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(rejectOpeningImportAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="importId" value={importId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-reject', id)} />
      <label>
        <span>سبب الرفض</span>
        <textarea name="reason" rows={2} minLength={3} maxLength={2000} required />
      </label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>رفض الاستيراد</Submit>
    </form>
  );
}

export function RecordCheckpointForm({
  organizationId, projectId, checkpointCodes, members, asOfDate, disabled,
}: {
  organizationId: string;
  projectId: string;
  checkpointCodes: { code: string; label: string }[];
  members: MemberOption[];
  asOfDate: string;
  disabled?: boolean;
}) {
  const [state, action] = useActionState(recordCheckpointAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-checkpoint', id)} />
      <div className="form-grid">
        <label>
          <span>نقطة المطابقة</span>
          <select name="checkpointCode" defaultValue={checkpointCodes[0]?.code ?? ''}>
            {checkpointCodes.map((checkpoint) => (
              <option key={checkpoint.code} value={checkpoint.code}>{checkpoint.label}</option>
            ))}
          </select>
        </label>
        <label><span>حتى تاريخ</span><input type="date" name="asOfDate" required defaultValue={asOfDate} /></label>
        <label>
          <span>القيمة الخارجية (وحدات صغرى، تقبل السالب)</span>
          <input name="externalValue" inputMode="numeric" pattern="-?\d{1,19}" required defaultValue="0" />
        </label>
        <label>
          <span>مرجع المصدر الخارجي</span>
          <input name="externalSourceReference" minLength={3} maxLength={200} required placeholder="كشف بنكي / مصادقة مورد" />
        </label>
        <label>
          <span>مرجع الدليل</span>
          <input name="externalEvidenceReference" minLength={3} maxLength={200} required placeholder="EVID-2026-01" />
        </label>
        <label>
          <span>مالك الاستثناء (يلزم عند وجود فرق)</span>
          <select name="exceptionOwnerId" defaultValue="">
            <option value="">—</option>
            {members.filter((member) => member.status === 'ACTIVE').map((member) => (
              <option key={member.userId} value={member.userId}>{member.userId.slice(0, 8)}… · {member.role}</option>
            ))}
          </select>
        </label>
        <label>
          <span>درجة الخطورة (تلزم عند وجود فرق)</span>
          <select name="exceptionSeverity" defaultValue="">
            <option value="">—</option>
            <option value="LOW">منخفضة</option>
            <option value="MEDIUM">متوسطة</option>
            <option value="HIGH">مرتفعة</option>
            <option value="CRITICAL">حرجة</option>
          </select>
        </label>
      </div>
      <p className="muted">
        القيمة الخارجية دليل لا حقيقة محاسبية. الرصيد المعتمد يُشتق داخل PostgreSQL من القيود المرحّلة،
        والفرق يُحسب كعدد صحيح تام؛ أي فرق غير صفري يفتح استثناءً ظاهرًا بمالك ودرجة خطورة.
      </p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تسجيل نقطة المطابقة</Submit>
    </form>
  );
}

export function ResolveExceptionForm({ organizationId, projectId, exceptionId, disabled }: {
  organizationId: string; projectId: string; exceptionId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(resolveExceptionAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="exceptionId" value={exceptionId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-resolve', id)} />
      <label><span>بيان المعالجة</span><textarea name="resolution" rows={2} minLength={3} maxLength={2000} required /></label>
      <label><span>مرجع الدليل</span><input name="evidenceReference" minLength={3} maxLength={200} required /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>إغلاق الاستثناء بالدليل</Submit>
    </form>
  );
}

export function SignOffCheckpointForm({ organizationId, projectId, checkpointId, disabled }: {
  organizationId: string; projectId: string; checkpointId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(signOffCheckpointAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="checkpointId" value={checkpointId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-signoff', id)} />
      <label><span>مرجع دليل الاعتماد</span><input name="evidenceReference" minLength={3} maxLength={200} required /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>اعتماد نهائي غير قابل للتعديل</Submit>
    </form>
  );
}

export function SetMembershipStatusForm({ organizationId, projectId, userId, nextStatus, disabled }: {
  organizationId: string; projectId: string; userId: string; nextStatus: 'ACTIVE' | 'INACTIVE'; disabled?: boolean;
}) {
  const [state, action] = useActionState(setMembershipStatusAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="userId" value={userId} />
      <input type="hidden" name="status" value={nextStatus} />
      <input type="hidden" name="idempotencyKey" value={key('s7-membership', id)} />
      <label>
        <span>السبب</span>
        <input name="reason" minLength={3} maxLength={500} required
          placeholder={nextStatus === 'INACTIVE' ? 'مغادرة موظف / حادث وصول' : 'استعادة وصول موثقة'} />
      </label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>{nextStatus === 'INACTIVE' ? 'إلغاء الوصول فورًا' : 'استعادة الوصول'}</Submit>
    </form>
  );
}

export function RegisterUatTaskForm({ organizationId, projectId, disabled }: {
  organizationId: string; projectId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(registerUatTaskAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-uat', id)} />
      <div className="form-grid">
        <label>
          <span>رمز المهمة</span>
          <input name="taskCode" minLength={10} maxLength={48} required placeholder="S7-UAT-OPENING-01" />
        </label>
        <label><span>العنوان</span><input name="title" minLength={3} maxLength={200} required /></label>
      </div>
      <label>
        <span>النتيجة المتوقعة كما يقرّها العميل</span>
        <textarea name="expectedOutcome" rows={2} minLength={3} maxLength={2000} required />
      </label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تسجيل مهمة اختبار قبول</Submit>
    </form>
  );
}

export function RecordUatExecutionForm({ organizationId, projectId, taskId, disabled }: {
  organizationId: string; projectId: string; taskId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(recordUatExecutionAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="taskId" value={taskId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-uat-exec', id)} />
      <label><span>مرجع دليل التنفيذ</span><input name="evidenceReference" minLength={3} maxLength={200} required /></label>
      <label><span>ملاحظات (اختياري)</span><textarea name="notes" rows={2} maxLength={2000} /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تسجيل تنفيذ المهمة</Submit>
    </form>
  );
}

export function AcceptUatTaskForm({ organizationId, projectId, taskId, disabled }: {
  organizationId: string; projectId: string; taskId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(acceptUatTaskAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="taskId" value={taskId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-uat-accept', id)} />
      <label>
        <span>مرجع دليل قبول العميل</span>
        <input name="acceptanceEvidenceReference" minLength={3} maxLength={200} required placeholder="محضر قبول موقّع" />
      </label>
      <p className="muted">قبول العميل يُسجَّل يدويًا بدليل بشري فقط. لا يوجد مسار يحوّل نجاح بروفة آلية إلى قبول عميل.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تسجيل قبول العميل</Submit>
    </form>
  );
}

export function RejectUatTaskForm({ organizationId, projectId, taskId, disabled }: {
  organizationId: string; projectId: string; taskId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(rejectUatTaskAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="taskId" value={taskId} />
      <input type="hidden" name="idempotencyKey" value={key('s7-uat-rejectt', id)} />
      <label><span>سبب الرفض</span><textarea name="rejectionReason" rows={2} minLength={3} maxLength={2000} required /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تسجيل رفض العميل</Submit>
    </form>
  );
}
