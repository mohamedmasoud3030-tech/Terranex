'use client';
import { useActionState, useMemo, useState } from 'react';
import { createProject } from '@/features/projects/actions';
import { SECTORS } from '@/features/projects/schema';
import { commandIdempotencyKey } from '@/shared/idempotency';
import { SECTOR_LABEL } from '@/shared/labels';
import { JourneySteps } from '@/features/plain-language/journey-steps';
import { PROJECT_FORM_COPY, SECTOR_PLAIN } from '@/features/plain-language/copy';

type NewProjectFormProps = Readonly<{
  organizationId: string;
  commandNonce: string;
}>;

export default function NewProjectForm({ organizationId, commandNonce }: NewProjectFormProps) {
  const [state, action, pending] = useActionState(createProject, {
    error: undefined,
    successCount: 0,
  });
  const [sector, setSector] = useState<(typeof SECTORS)[number]>('REAL_ESTATE');
  const idempotencyKey = useMemo(
    () => commandIdempotencyKey('project-create', commandNonce, state.successCount ?? 0),
    [commandNonce, state.successCount],
  );

  return (
    <section className="card stack shell-reading">
      <JourneySteps current={2} />
      <div>
        <h1>{PROJECT_FORM_COPY.title}</h1>
        <p className="muted">{PROJECT_FORM_COPY.plain}</p>
        <p className="muted">{PROJECT_FORM_COPY.defaultsNote}</p>
      </div>
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
        <fieldset className="stack">
          <legend>{PROJECT_FORM_COPY.sectorLegend}</legend>
          <div className="form-grid">
            {SECTORS.map((value) => (
              <label key={value}>
                <input
                  type="radio"
                  name="sector"
                  value={value}
                  checked={sector === value}
                  onChange={() => setSector(value)}
                  required
                />
                <span className="ms-2">{SECTOR_LABEL[value]}</span>
              </label>
            ))}
          </div>
          <small className="muted">{SECTOR_PLAIN[sector]}</small>
        </fieldset>
        <label>
          {PROJECT_FORM_COPY.nameLabel}
          <input name="name" required autoFocus maxLength={160} placeholder={PROJECT_FORM_COPY.namePlaceholder} />
        </label>
        <label>
          {PROJECT_FORM_COPY.referenceLabel} <span className="muted">(اختياري)</span>
          <input name="internalReference" maxLength={80} />
        </label>
        <small className="muted">{PROJECT_FORM_COPY.referenceHint}</small>
        <label>
          {PROJECT_FORM_COPY.descriptionLabel} <span className="muted">(اختياري)</span>
          <textarea name="description" maxLength={2000} />
        </label>
        <small className="muted">{PROJECT_FORM_COPY.descriptionHint}</small>
        {state.error && (
          <p className="error" role="alert">{state.error}</p>
        )}
        <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'إنشاء المشروع'}</button>
      </form>
    </section>
  );
}
