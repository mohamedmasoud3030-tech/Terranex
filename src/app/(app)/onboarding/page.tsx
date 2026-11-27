'use client';
import { useActionState } from 'react';
import { createOrganization } from '@/features/organizations/actions';
import { JourneySteps } from '@/features/plain-language/journey-steps';
import { ONBOARDING_COPY } from '@/features/plain-language/copy';

/**
 * First-run guided flow, step 1 of 3: create the organization.
 *
 * The plain-language layer (journey indicator + everyday words) wraps the
 * unchanged createOrganization command; the flow and its guarantees are the
 * same, only the explanation is new.
 */
export default function Onboarding() {
  const [state, action, pending] = useActionState(createOrganization, { error: undefined });
  return (
    <section className="card stack shell-form">
      <JourneySteps current={1} />
      <div>
        <h1>{ONBOARDING_COPY.title}</h1>
        <p className="muted">{ONBOARDING_COPY.plain}</p>
      </div>
      <form action={action} className="stack">
        <label>
          {ONBOARDING_COPY.nameLabel}
          <input name="name" required autoFocus placeholder={ONBOARDING_COPY.namePlaceholder} />
        </label>
        <p className="muted">{ONBOARDING_COPY.nameHint}</p>
        {state.error && (
          <p className="error" role="alert">
            {state.error}
          </p>
        )}
        <button disabled={pending}>{pending ? ONBOARDING_COPY.pending : ONBOARDING_COPY.submit}</button>
        <p className="muted">{ONBOARDING_COPY.afterNote}</p>
      </form>
    </section>
  );
}
