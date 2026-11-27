'use client';

import { useActionState } from 'react';
import { acceptInvite } from '@/features/invites/actions';

export function AcceptInviteForm({ token }: { token: string }) {
  const [state, action, pending] = useActionState(acceptInvite, { successCount: 0 });
  return (
    <form action={action} className="stack">
      <input type="hidden" name="token" value={token} />
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <button disabled={pending}>{pending ? 'جارٍ الانضمام…' : 'قبول الدعوة والانضمام'}</button>
    </form>
  );
}
