'use client';

import { useActionState, useMemo } from 'react';
import { uploadGeneralDocument } from './actions';
import { DOCUMENT_CATEGORIES } from './schema';
import { DOCUMENT_CATEGORY_LABEL } from './labels';
import { commandIdempotencyKey } from '@/shared/idempotency';

type ProjectOption = { id: string; name: string };

export function GeneralDocumentUploadForm({
  organizationId,
  projects,
  commandNonce,
}: {
  organizationId: string;
  projects: ProjectOption[];
  commandNonce: string;
}) {
  const [state, action, pending] = useActionState(uploadGeneralDocument, { successCount: 0 });
  const idempotencyKey = useMemo(
    () => commandIdempotencyKey('general-document-upload', commandNonce, state.successCount ?? 0),
    [commandNonce, state.successCount],
  );

  return (
    <form action={action} className="stack">
      <input type="hidden" name="organizationId" value={organizationId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label>
        عنوان المستند
        <input name="title" required minLength={3} maxLength={200} />
      </label>
      <label>
        التصنيف
        <select name="category" defaultValue="GENERAL">
          {DOCUMENT_CATEGORIES.map((category) => (
            <option key={category} value={category}>{DOCUMENT_CATEGORY_LABEL[category]}</option>
          ))}
        </select>
      </label>
      <label>
        المشروع <span className="muted">(اختياري — بدونه يكون المستند على مستوى المنظمة)</span>
        <select name="projectId" defaultValue="">
          <option value="">مستند عام للمنظمة</option>
          {projects.map((project) => (
            <option key={project.id} value={project.id}>{project.name}</option>
          ))}
        </select>
      </label>
      <label>
        الملف
        <input type="file" name="file" required accept="application/pdf,image/jpeg,image/png" />
      </label>
      <small className="muted">PDF أو JPEG أو PNG، بحد أقصى 10 ميجابايت. يُحفظ الملف في تخزين خاص ولا يمكن تعديله بعد الرفع.</small>
      {state.error && <p className="error" role="alert">{state.error}</p>}
      <div>
        <button disabled={pending}>{pending ? 'جارٍ الرفع…' : 'رفع المستند'}</button>
      </div>
    </form>
  );
}
