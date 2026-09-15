'use client';

import { useActionState } from 'react';
import { requestPasswordReset } from '@/features/auth/actions';
import { AuthShell } from '@/shared/ui/auth';

type ForgotPasswordFormProps = {
  recoveryError?: boolean;
};

export function ForgotPasswordForm({ recoveryError = false }: ForgotPasswordFormProps) {
  const [state, action, pending] = useActionState(requestPasswordReset, {});

  return (
    <AuthShell>
      <header className="auth-head">
        <h1>استعادة كلمة المرور</h1>
        <p className="muted">أدخل بريدك الإلكتروني وسنرسل رابطًا آمنًا لإعادة تعيين كلمة المرور.</p>
      </header>

      {recoveryError && (
        <p className="error" role="alert">
          الرابط غير صالح أو انتهت صلاحيته. اطلب رابطًا جديدًا.
        </p>
      )}

      {state.sent ? (
        <p role="status">
          إذا كان البريد مسجلًا لدينا فستصلك رسالة تحتوي على رابط إعادة التعيين. تحقق من البريد والرسائل غير المرغوب فيها.
        </p>
      ) : (
        <form action={action} className="stack auth-form" noValidate>
          <label className="auth-field">
            <span className="auth-field-label">البريد الإلكتروني</span>
            <span className="auth-control">
              <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <rect x="2.5" y="4.5" width="15" height="11" rx="1.5" />
                <path d="m3.75 5.75 6.25 4.75 6.25-4.75" />
              </svg>
              <input name="email" type="email" autoComplete="email" required />
            </span>
          </label>
          {state.error && <p className="error" role="alert">{state.error}</p>}
          <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الإرسال…' : 'إرسال رابط الاستعادة'}</button>
        </form>
      )}

      <a className="auth-alt-link" href="/login">العودة إلى تسجيل الدخول</a>
    </AuthShell>
  );
}
