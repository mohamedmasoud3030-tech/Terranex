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
        <p className="auth-sub">استخدم كلمة مرور من 8 أحرف على الأقل.</p>
      </header>

      <form action={action} className="auth-form" noValidate>
        <label className="auth-field">
          <span className="auth-label">كلمة المرور الجديدة</span>
          <input name="password" type="password" autoComplete="new-password" minLength={8} required />
        </label>
        <label className="auth-field">
          <span className="auth-label">تأكيد كلمة المرور</span>
          <input name="confirmPassword" type="password" autoComplete="new-password" minLength={8} required />
        </label>
        {state.error && <p className="auth-error" role="alert">{state.error}</p>}
        <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ كلمة المرور'}</button>
      </form>
    </AuthShell>
  );
}
