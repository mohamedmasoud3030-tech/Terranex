'use client';

import { useActionState, useMemo, useState } from 'react';
import type {
  CapitalCall,
  CapitalCallLine,
  CommitmentTerm,
  Participant,
} from '@/features/funding/queries';
import { formatMinorUnits } from '@/shared/money';
import { createCapitalCall, recordContribution } from '@/features/funding/actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { useResolvedCommandNonce } from '@/shared/idempotency/use-resolved-command-nonce';

export function CapitalCallForm({
  organizationId,
  projectId,
  versionId,
  currency,
  participants,
  commitments,
  serverNonce,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
  currency: string;
  participants: Participant[];
  commitments: CommitmentTerm[];
  serverNonce?: string;
}) {
  const [state, action, pending] = useActionState(createCapitalCall, { error: undefined, successCount: 0 });
  const resolvedNonce = useResolvedCommandNonce(serverNonce);
  const idempotencyKey = useCommandIdempotencyKey('call', state, resolvedNonce ?? 'pending');
  const commitmentByParticipant = useMemo(
    () => new Map(commitments.map((commitment) => [commitment.participant_id, commitment])),
    [commitments],
  );

  if (!resolvedNonce) {
    return <p className="muted">جارٍ تجهيز نموذج طلب رأس المال الآمن…</p>;
  }

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
        <table><caption className="sr-only">جدول: المستثمر · المبلغ المطلوب · الالتزام</caption>
          <thead>
            <tr><th scope="col">المستثمر</th><th scope="col" className="num">المبلغ المطلوب ({currency})</th><th scope="col" className="num">الالتزام</th></tr>
          </thead>
          <tbody>
            {participants.map((participant) => {
              const commitment = commitmentByParticipant.get(participant.id);
              if (!commitment) return null;
              return (
                <tr key={participant.id}>
                  <td>{participant.parties.legal_name}</td>
                  <td className="num">
                    <input
                      type="text"
                      inputMode="decimal"
                      name="amount"
                      placeholder="5000.00"
                      aria-label={`المبلغ المطلوب من ${participant.parties.legal_name}`}
                    />
                    <input type="hidden" name="participantId" value={participant.id} />
                  </td>
                  <td className="num">{formatMinorUnits(commitment.commitment_minor_units, commitment.currency)}</td>
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
  serverNonce,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
  currency: string;
  calls: CapitalCall[];
  lines: CapitalCallLine[];
  participants: Participant[];
  serverNonce?: string;
}) {
  const [state, action, pending] = useActionState(recordContribution, { error: undefined, successCount: 0 });
  const [selectedCallId, setSelectedCallId] = useState('');
  const resolvedNonce = useResolvedCommandNonce(serverNonce);
  const idempotencyKey = useCommandIdempotencyKey('contrib', state, resolvedNonce ?? 'pending');
  const issuedCalls = calls.filter((call) => call.status === 'ISSUED');
  const eligibleLines = lines.filter((line) => line.capital_call_id === selectedCallId);
  const participantName = new Map(participants.map((participant) => [participant.id, participant.parties.legal_name]));

  if (!resolvedNonce) {
    return <p className="muted">جارٍ تجهيز نموذج المساهمة الآمن…</p>;
  }

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
