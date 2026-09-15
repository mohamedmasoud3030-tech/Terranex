'use client';

import { useActionState } from 'react';
import { updatePassword } from '@/features/auth/actions';
import { AuthShell } from '@/shared/ui/auth';

export function ResetPasswordForm() {
  const [state, action, pending] = useActionState(updatePassword, {});

  return (
    <AuthShell>
      <header className="auth-head">
        <h1>تعيين كلمة مرور جديدة</h1>
        <p className="muted">استخدم كلمة مرور من 8 أحرف على الأقل.</p>
      </header>

      <form action={action} className="stack auth-form" noValidate>
        <label className="auth-field">
          <span className="auth-field-label">كلمة المرور الجديدة</span>
          <span className="auth-control">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="4.25" y="8.75" width="11.5" height="7.75" rx="1.5" />
              <path d="M6.75 8.75V6.9a3.25 3.25 0 0 1 6.5 0v1.85" />
            </svg>
            <input name="password" type="password" autoComplete="new-password" minLength={8} required />
          </span>
        </label>
        <label className="auth-field">
          <span className="auth-field-label">تأكيد كلمة المرور</span>
          <span className="auth-control">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="4.25" y="8.75" width="11.5" height="7.75" rx="1.5" />
              <path d="M6.75 8.75V6.9a3.25 3.25 0 0 1 6.5 0v1.85" />
            </svg>
            <input name="confirmPassword" type="password" autoComplete="new-password" minLength={8} required />
          </span>
        </label>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ كلمة المرور'}</button>
      </form>
    </AuthShell>
  );
}
