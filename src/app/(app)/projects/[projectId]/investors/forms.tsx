'use client';

import { useActionState, useId } from 'react';
import { useFormStatus } from 'react-dom';
import type { ActionState } from '@/features/auth/actions';
import {
  approveAllocationAction,
  approveDistributionAction,
  configureAllocationRulesAction,
  payDistributionAction,
  prepareAllocationAction,
  prepareDistributionAction,
} from '@/features/allocation/actions';

const initial: ActionState = {};

function key(prefix: string, reactId: string) {
  return `${prefix}-${reactId.replace(/[^a-zA-Z0-9]/g, '')}-idempotency`.slice(0, 120);
}

function ErrorBanner({ state }: { state: ActionState }) {
  return state.error ? <p className="error" role="alert">{state.error}</p> : null;
}

function Submit({ children, disabled = false }: { children: string; disabled?: boolean }) {
  const { pending } = useFormStatus();
  return <button className="button" type="submit" disabled={disabled || pending}>{pending ? 'جارٍ التنفيذ…' : children}</button>;
}

type RuleParticipant = {
  partyId: string;
  legalName: string;
};

export function ConfigureRulesForm({
  organizationId, projectId, governingVersionId, participants, disabled,
}: {
  organizationId: string;
  projectId: string;
  governingVersionId: string;
  participants: RuleParticipant[];
  disabled?: boolean;
}) {
  const [state, action] = useActionState(configureAllocationRulesAction, initial);
  const id = useId();
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="governingVersionId" value={governingVersionId} />
      <input type="hidden" name="idempotencyKey" value={key('s5-rules', id)} />
      <label>
        <span>سياسة التخصيص</span>
        <select name="policy" defaultValue="PRO_RATA">
          <option value="PRO_RATA">Pro Rata حسب وحدات الملكية / النسبة المثبتة</option>
          <option value="FIXED_SHARES">حصص توزيع ثابتة</option>
        </select>
      </label>
      <label>
        <span>مرجع مستند أساس التخصيص</span>
        <input name="basisEvidenceReference" minLength={3} maxLength={200} required placeholder="مثال: AGREEMENT-SCHEDULE-A" />
      </label>
      <label>
        <span>المقام المشترك للأوزان</span>
        <input name="commonDenominator" inputMode="numeric" pattern="[1-9][0-9]*" required defaultValue="10000" />
      </label>
      <div className="table-wrap">
        <table>
          <thead><tr><th>المستثمر</th><th>وزن التخصيص المستقل</th></tr></thead>
          <tbody>
            {participants.map((participant) => (
              <tr key={participant.partyId}>
                <td>{participant.legalName}<input type="hidden" name="partyId" value={participant.partyId} /></td>
                <td><input name="weightNumerator" inputMode="numeric" pattern="[1-9][0-9]*" required placeholder="مثال: 2500" aria-label={`وزن ${participant.legalName}`} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="muted">مبالغ الالتزام أو المساهمات لا تحدد الملكية ولا حصة الربح. أدخل الوحدات أو النسب من المستند الحاكم نفسه؛ يجب أن يساوي مجموع الأوزان المقام المشترك.</p>
      <ErrorBanner state={state} />
      <Submit disabled={disabled || participants.length === 0}>تثبيت أساس وقواعد التخصيص</Submit>
    </form>
  );
}

export function PrepareAllocationForm({ organizationId, projectId, snapshotId, governingVersionId, disabled }: {
  organizationId: string; projectId: string; snapshotId: string; governingVersionId: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(prepareAllocationAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="closeSnapshotId" value={snapshotId} />
      <input type="hidden" name="governingVersionId" value={governingVersionId} />
      <input type="hidden" name="idempotencyKey" value={key('s5-prepare', id)} />
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تحضير تخصيص النتيجة</Submit>
    </form>
  );
}

export function ApproveAllocationForm({ organizationId, projectId, allocationRunId, postingDate, disabled }: {
  organizationId: string; projectId: string; allocationRunId: string; postingDate: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(approveAllocationAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="allocationRunId" value={allocationRunId} />
      <input type="hidden" name="idempotencyKey" value={key('s5-approve', id)} />
      <label><span>تاريخ الترحيل</span><input type="date" name="postingDate" required defaultValue={postingDate} /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>اعتماد التخصيص وترحيله</Submit>
    </form>
  );
}

export function PrepareDistributionForm({ organizationId, projectId, allocationRunId, participantPartyId, currency, legalName, disabled }: {
  organizationId: string; projectId: string; allocationRunId: string; participantPartyId: string; currency: string; legalName: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(prepareDistributionAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="allocationRunId" value={allocationRunId} />
      <input type="hidden" name="participantPartyId" value={participantPartyId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={key('s5-dist-prepare', id)} />
      <label><span>مبلغ التوزيع لـ {legalName}</span><input name="amount" inputMode="decimal" required placeholder="0.00" /></label>
      <label><span>مرجع الدليل</span><input name="evidenceReference" minLength={3} maxLength={200} required /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>تحضير توزيع مستحق</Submit>
    </form>
  );
}

export function ApproveDistributionForm({ organizationId, projectId, distributionId, postingDate, disabled }: {
  organizationId: string; projectId: string; distributionId: string; postingDate: string; disabled?: boolean;
}) {
  const [state, action] = useActionState(approveDistributionAction, initial);
  const id = useId();
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="distributionId" value={distributionId} />
      <input type="hidden" name="idempotencyKey" value={key('s5-dist-approve', id)} />
      <label><span>تاريخ إثبات المستحق</span><input type="date" name="postingDate" required defaultValue={postingDate} /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled}>اعتماد كمستحق</Submit>
    </form>
  );
}

type CashAccount = { cash_account_id: string; name: string; currency: string; balance_minor_units: string };

export function PayDistributionForm({ organizationId, projectId, distributionId, currency, outstandingMajorHint, postingDate, cashAccounts, disabled }: {
  organizationId: string; projectId: string; distributionId: string; currency: string; outstandingMajorHint: string; postingDate: string; cashAccounts: CashAccount[]; disabled?: boolean;
}) {
  const [state, action] = useActionState(payDistributionAction, initial);
  const id = useId();
  const eligible = cashAccounts.filter((account) => account.currency === currency && BigInt(account.balance_minor_units) > 0n);
  return (
    <form action={action} className="inline-form">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="distributionId" value={distributionId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={key('s5-dist-pay', id)} />
      <label><span>المبلغ</span><input name="amount" inputMode="decimal" required placeholder={outstandingMajorHint} /></label>
      <label><span>الحساب النقدي</span><select name="cashAccountId" required defaultValue=""><option value="" disabled>اختر الحساب</option>{eligible.map((account) => <option key={account.cash_account_id} value={account.cash_account_id}>{account.name}</option>)}</select></label>
      <label><span>تاريخ الدفع</span><input type="date" name="paymentDate" required defaultValue={postingDate} /></label>
      <label><span>مرجع دليل الدفع</span><input name="evidenceReference" minLength={3} maxLength={200} required /></label>
      <ErrorBanner state={state} />
      <Submit disabled={disabled || eligible.length === 0}>دفع التوزيع</Submit>
    </form>
  );
}
