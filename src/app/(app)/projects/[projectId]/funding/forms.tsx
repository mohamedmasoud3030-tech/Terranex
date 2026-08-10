'use client';

import { useActionState, useMemo } from 'react';
import type {
  CapitalCall,
  CapitalCallLine,
  CommitmentTerm,
  Participant,
} from '@/features/funding/queries';
import { createCapitalCall, recordContribution } from '@/features/funding/actions';

export function CapitalCallForm({
  organizationId,
  projectId,
  versionId,
  currency,
  participants,
  commitments,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
  currency: string;
  participants: Participant[];
  commitments: CommitmentTerm[];
}) {
  const [state, action, pending] = useActionState(createCapitalCall, { error: undefined });
  const commitmentByParticipant = useMemo(
    () => new Map(commitments.map((c) => [c.participant_id, c.commitment_minor_units])),
    [commitments],
  );
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="agreementVersionId" value={versionId} />
      <label>
        المرجع <span className="muted">(اختياري)</span>
        <input name="reference" maxLength={80} placeholder="CALL-1" />
      </label>
      <label>
        تاريخ الاستحقاق
        <input type="date" name="dueDate" required />
      </label>
      <table>
        <thead>
          <tr>
            <th>المستثمر</th>
            <th>المبلغ المطلوب</th>
            <th>الالتزام</th>
          </tr>
        </thead>
        <tbody>
          {participants.map((p) => (
            <tr key={p.id}>
              <td>{p.parties.legal_name}</td>
              <td>
                <input type="number" name="amountMinorUnits" min={1} step={1} required />
                <input type="hidden" name="participantId" value={p.id} />
              </td>
              <td>
                {commitmentByParticipant.get(p.id)?.toLocaleString('ar-EG') ?? '—'} {currency}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الإصدار…' : 'إصدار الطلب'}</button>
    </form>
  );
}

export function ContributionForm({
  organizationId,
  projectId,
  versionId,
  currency,
  calls,
  lines,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
  currency: string;
  calls: CapitalCall[];
  lines: CapitalCallLine[];
}) {
  const [state, action, pending] = useActionState(recordContribution, { error: undefined });
  const defaultIdempotencyKey = useMemo(
    () => `contrib-${crypto.randomUUID()}`,
    [],
  );
  const issuedCalls = calls.filter((c) => c.status === 'ISSUED');
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="agreementVersionId" value={versionId} />
      <input type="hidden" name="currency" value={currency} />
      <label>
        الطلب
        <select name="capitalCallId" required defaultValue="">
          <option value="" disabled>
            اختر الطلب
          </option>
          {issuedCalls.map((c) => (
            <option key={c.id} value={c.id}>
              {c.reference || c.id.slice(0, 8)} — استحقاق {c.due_date}
            </option>
          ))}
        </select>
      </label>
      <label>
        المستثمر
        <select name="participantId" required defaultValue="">
          <option value="" disabled>
            اختر المستثمر
          </option>
          {lines.map((l) => (
            <option key={l.id} value={l.participant_id}>
              {l.participant_id.slice(0, 8)} — {l.amount_minor_units.toLocaleString('ar-EG')} {l.currency}
            </option>
          ))}
        </select>
      </label>
      <label>
        المبلغ المستلم بالوحدات الصغرى
        <input type="number" name="contributionMinorUnits" min={1} step={1} required />
      </label>
      <label>
        تاريخ الاستلام
        <input type="date" name="occurredOn" required />
      </label>
      <label>
        مفتاح إعادة المحاولة <span className="muted">(ثابت لمنع التكرار)</span>
        <input
          name="idempotencyKey"
          required
          minLength={8}
          maxLength={120}
          defaultValue={defaultIdempotencyKey}
        />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending || issuedCalls.length === 0}>
        {pending ? 'جارٍ التسجيل…' : 'تسجيل المساهمة'}
      </button>
    </form>
  );
}
