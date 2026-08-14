'use client';
import { useActionState, useState } from 'react';
import { createProject } from '@/features/projects/actions';
import { SECTORS } from '@/features/projects/schema';

const SECTOR_LABEL: Record<(typeof SECTORS)[number], string> = {
  REAL_ESTATE: 'عقارات',
  AGRICULTURE: 'زراعة',
  LIVESTOCK: 'ثروة حيوانية',
};

const SECTOR_DESCRIPTION: Record<(typeof SECTORS)[number], string> = {
  REAL_ESTATE: 'سيُفتح المشروع في المسار الموجّه للعقارات بعد إنشائه.',
  AGRICULTURE: 'سيُفتح المشروع في مساحة الزراعة بعد إنشائه.',
  LIVESTOCK: 'سيُفتح المشروع في مساحة الثروة الحيوانية بعد إنشائه.',
};

export default function NewProjectForm({ organizationId }: Readonly<{ organizationId: string }>) {
  const [state, action, pending] = useActionState(createProject, { error: undefined });
  const [sector, setSector] = useState<(typeof SECTORS)[number]>('REAL_ESTATE');
  return (
    <section className="card stack" style={{ maxWidth: 720 }}>
      <div>
        <h1>مشروع استثماري جديد</h1>
        <p className="muted">اختر القطاع أولًا؛ الحالة والعملة محددتان مبدئيًا: مسودة، جنيه مصري.</p>
      </div>
      <form action={action} className="stack">
        <input type="hidden" name="organizationId" value={organizationId} />
        <fieldset className="stack">
          <legend>القطاع</legend>
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
                <span style={{ marginInlineStart: 8 }}>{SECTOR_LABEL[value]}</span>
              </label>
            ))}
          </div>
          <small className="muted">
            {SECTOR_DESCRIPTION[sector]}
          </small>
        </fieldset>
        <label>
          اسم المشروع
          <input name="name" required autoFocus maxLength={160} />
        </label>
        <label>
          المرجع الداخلي <span className="muted">(اختياري)</span>
          <input name="internalReference" maxLength={80} />
        </label>
        <label>
          الوصف <span className="muted">(اختياري)</span>
          <textarea name="description" maxLength={2000} />
        </label>
        {state.error && (
          <p className="error" role="alert">{state.error}</p>
        )}
        <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'إنشاء المشروع'}</button>
      </form>
    </section>
  );
}
