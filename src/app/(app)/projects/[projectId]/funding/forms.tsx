'use client';

import { useActionState, useMemo, useState } from 'react';
import type {
  CapitalCall,
  CapitalCallLine,
  CommitmentTerm,
  Participant,
} from '@/features/funding/queries';
import { formatMinorUnits } from '@/features/funding/money';
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
  const idempotencyKey = useMemo(() => `call-${crypto.randomUUID()}`, []);
  const commitmentByParticipant = useMemo(
    () => new Map(commitments.map((commitment) => [commitment.participant_id, commitment])),
    [commitments],
  );

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="agreementVersionId" value={versionId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        المرجع <span className="muted">(اختياري)</span>
        <input name="reference" maxLength={80} placeholder="CALL-1" />
      </label>
      <label>
        تاريخ الاستحقاق
        <input type="date" name="dueDate" required />
      </label>
      <p className="muted">أدخل المبلغ المطلوب في {currency}. اترك المستثمر فارغًا إذا لم يشمله هذا الطلب.</p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr><th>المستثمر</th><th>المبلغ المطلوب ({currency})</th><th>الالتزام</th></tr>
          </thead>
          <tbody>
            {participants.map((participant) => {
              const commitment = commitmentByParticipant.get(participant.id);
              if (!commitment) return null;
              return (
                <tr key={participant.id}>
                  <td>{participant.parties.legal_name}</td>
                  <td>
                    <input
                      type="text"
                      inputMode="decimal"
                      name="amount"
                      placeholder="5000.00"
                      aria-label={`المبلغ المطلوب من ${participant.parties.legal_name}`}
                    />
                    <input type="hidden" name="participantId" value={participant.id} />
                  </td>
                  <td>{formatMinorUnits(commitment.commitment_minor_units, commitment.currency)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
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
  participants,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
  currency: string;
  calls: CapitalCall[];
  lines: CapitalCallLine[];
  participants: Participant[];
}) {
  const [state, action, pending] = useActionState(recordContribution, { error: undefined });
  const [selectedCallId, setSelectedCallId] = useState('');
  const idempotencyKey = useMemo(() => `contrib-${crypto.randomUUID()}`, []);
  const issuedCalls = calls.filter((call) => call.status === 'ISSUED');
  const eligibleLines = lines.filter((line) => line.capital_call_id === selectedCallId);
  const participantName = new Map(participants.map((participant) => [participant.id, participant.parties.legal_name]));

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="agreementVersionId" value={versionId} />
      <input type="hidden" name="currency" value={currency} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        الطلب
        <select
          name="capitalCallId"
          required
          value={selectedCallId}
          onChange={(event) => setSelectedCallId(event.target.value)}
        >
          <option value="" disabled>اختر الطلب</option>
          {issuedCalls.map((call) => (
            <option key={call.id} value={call.id}>
              {call.reference || call.id.slice(0, 8)} — استحقاق {call.due_date}
            </option>
          ))}
        </select>
      </label>
      <label>
        المستثمر
        <select name="participantId" required defaultValue="" key={selectedCallId || 'none'} disabled={!selectedCallId}>
          <option value="" disabled>اختر المستثمر</option>
          {eligibleLines.map((line) => (
            <option key={line.id} value={line.participant_id}>
              {participantName.get(line.participant_id) ?? line.participant_id.slice(0, 8)} — طلب {formatMinorUnits(line.amount_minor_units, line.currency)}
            </option>
          ))}
        </select>
      </label>
      <label>
        المبلغ المستلم ({currency})
        <input type="text" inputMode="decimal" name="amount" placeholder="5000.00" required />
      </label>
      <label>
        تاريخ الاستلام
        <input type="date" name="occurredOn" required />
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending || issuedCalls.length === 0 || !selectedCallId}>
        {pending ? 'جارٍ التسجيل…' : 'تسجيل المساهمة'}
      </button>
    </form>
  );
}
