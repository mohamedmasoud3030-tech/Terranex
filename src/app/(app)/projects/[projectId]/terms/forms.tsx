'use client';

import { useActionState } from 'react';
import type { Party, Participant } from '@/features/funding/queries';
import {
  activateAgreementVersion,
  addParticipant,
  createAgreementDraft,
  createParty,
} from '@/features/funding/actions';
import { useCommandIdempotencyKey } from '@/shared/idempotency/use-command-idempotency-key';
import { useResolvedCommandNonce } from '@/shared/idempotency/use-resolved-command-nonce';

export function CreatePartyForm({ organizationId, projectId }: { organizationId: string; projectId: string }) {
  const [state, action, pending] = useActionState(createParty, { error: undefined });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        الاسم القانوني
        <input name="legalName" required maxLength={160} />
      </label>
      <label>
        النوع
        <select name="partyType" defaultValue="PERSON">
          <option value="PERSON">فرد</option>
          <option value="ORGANIZATION">منظمة</option>
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'إضافة الطرف'}</button>
    </form>
  );
}

export function AddParticipantForm({
  organizationId,
  projectId,
  parties,
}: {
  organizationId: string;
  projectId: string;
  parties: Party[];
}) {
  const [state, action, pending] = useActionState(addParticipant, { error: undefined });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        الطرف
        <select name="partyId" required>
          {parties.map((party) => (
            <option key={party.id} value={party.id}>{party.legal_name}</option>
          ))}
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending || parties.length === 0}>
        {pending ? 'جارٍ الإضافة…' : 'إضافة كمستثمر'}
      </button>
    </form>
  );
}

export function AgreementDraftForm({
  organizationId,
  projectId,
  participants,
  currency,
  serverNonce,
}: {
  organizationId: string;
  projectId: string;
  participants: Participant[];
  currency: string;
  serverNonce?: string;
}) {
  const [state, action, pending] = useActionState(createAgreementDraft, { error: undefined, successCount: 0 });
  const resolvedNonce = useResolvedCommandNonce(serverNonce);
  const idempotencyKey = useCommandIdempotencyKey('agreement', state, resolvedNonce ?? 'pending');

  if (!resolvedNonce) {
    return <p className="muted">جارٍ تجهيز نموذج الاتفاقية الآمن…</p>;
  }

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        تاريخ السريان
        <input type="date" name="effectiveDate" required />
      </label>
      <p className="muted">أدخل الالتزام بالمبلغ المعتاد في {currency}، ويمكن استخدام خانتين عشريتين.</p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr><th>المستثمر</th><th>الالتزام ({currency})</th></tr>
          </thead>
          <tbody>
            {participants.map((participant) => (
              <tr key={participant.id}>
                <td>{participant.parties.legal_name}</td>
                <td>
                  <input
                    type="text"
                    inputMode="decimal"
                    name="commitmentAmount"
                    placeholder="10000.00"
                    required
                  />
                  <input type="hidden" name="participantId" value={participant.id} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ المسودة'}</button>
    </form>
  );
}

export function ActivateVersionButton({
  organizationId,
  projectId,
  versionId,
}: {
  organizationId: string;
  projectId: string;
  versionId: string;
}) {
  const [state, action, pending] = useActionState(activateAgreementVersion, { error: undefined });
  return (
    <form action={action} style={{ display: 'inline' }}>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <input type="hidden" name="versionId" value={versionId} />
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ التفعيل…' : 'تفعيل'}
      </button>
      {state.error && <span className="error" role="alert"> {state.error}</span>}
    </form>
  );
}
