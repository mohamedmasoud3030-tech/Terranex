'use client';

import { useActionState } from 'react';
import type { Party, Participant } from '@/features/funding/queries';
import {
  activateAgreementVersion,
  addParticipant,
  createAgreementDraft,
  createParty,
} from '@/features/funding/actions';

export function CreatePartyForm({ organizationId }: { organizationId: string }) {
  const [state, action, pending] = useActionState(createParty, { error: undefined });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
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
            <option key={party.id} value={party.id}>
              {party.legal_name}
            </option>
          ))}
        </select>
      </label>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الإضافة…' : 'إضافة كمستثمر'}</button>
    </form>
  );
}

export function AgreementDraftForm({
  organizationId,
  projectId,
  participants,
  currency,
}: {
  organizationId: string;
  projectId: string;
  participants: Participant[];
  currency: string;
}) {
  const [state, action, pending] = useActionState(createAgreementDraft, { error: undefined });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="projectId" value={projectId} />
      <label>
        تاريخ السريان
        <input type="date" name="effectiveDate" required />
      </label>
      <p className="muted">أدخل الالتزام بالوحدات الصغرى (مثلًا 1000000 = 10,000 {currency}).</p>
      <table>
        <thead>
          <tr>
            <th>المستثمر</th>
            <th>الالتزام</th>
          </tr>
        </thead>
        <tbody>
          {participants.map((p) => (
            <tr key={p.id}>
              <td>{p.parties.legal_name}</td>
              <td>
                <input
                  type="number"
                  name="commitmentMinorUnits"
                  min={1}
                  step={1}
                  required
                />
                <input type="hidden" name="participantId" value={p.id} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ المسودة'}</button>
    </form>
  );
}

export function ActivateVersionButton({
  organizationId,
  versionId,
}: {
  organizationId: string;
  versionId: string;
}) {
  const [state, action, pending] = useActionState(activateAgreementVersion, { error: undefined });
  return (
    <form action={action} style={{ display: 'inline' }}>
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="versionId" value={versionId} />
      <button className="secondary" disabled={pending}>
        {pending ? 'جارٍ التفعيل…' : 'تفعيل'}
      </button>
      {state.error && <span className="error"> {state.error}</span>}
    </form>
  );
}
