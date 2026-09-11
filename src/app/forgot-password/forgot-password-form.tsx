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
      <section className="card stack">
        <div>
          <h1>استعادة كلمة المرور</h1>
          <p className="muted">أدخل بريدك الإلكتروني وسنرسل رابطًا آمنًا لإعادة تعيين كلمة المرور.</p>
        </div>

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
          <form action={action} className="stack" noValidate>
            <label>
              البريد الإلكتروني
              <input name="email" type="email" autoComplete="email" required />
            </label>
            {state.error && <p className="error" role="alert">{state.error}</p>}
            <button disabled={pending}>{pending ? 'جارٍ الإرسال…' : 'إرسال رابط الاستعادة'}</button>
          </form>
        )}

        <a href="/login">العودة إلى تسجيل الدخول</a>
      </section>
    </AuthShell>
  );
}
