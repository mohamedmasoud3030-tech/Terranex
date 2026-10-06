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
        <p className="auth-sub">أدخل بريدك الإلكتروني وسنرسل لك رابطًا آمنًا لإعادة التعيين.</p>
      </header>

      {recoveryError && (
        <p className="auth-error" role="alert">
          الرابط غير صالح أو انتهت صلاحيته. اطلب رابطًا جديدًا.
        </p>
      )}

      {state.sent ? (
        <p className="auth-note" role="status">
          إذا كان البريد مسجلًا لدينا فستصلك رسالة تحتوي على رابط إعادة التعيين. تحقق من البريد والرسائل غير المرغوب فيها.
        </p>
      ) : (
        <form action={action} className="auth-form" noValidate>
          <label className="auth-field">
            <span className="auth-label">البريد الإلكتروني</span>
            <input name="email" type="email" autoComplete="email" required />
          </label>
          {state.error && <p className="auth-error" role="alert">{state.error}</p>}
          <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الإرسال…' : 'إرسال رابط الاستعادة'}</button>
        </form>
      )}

      <a className="auth-alt-link" href="/login">العودة إلى تسجيل الدخول</a>
    </AuthShell>
  );
}
