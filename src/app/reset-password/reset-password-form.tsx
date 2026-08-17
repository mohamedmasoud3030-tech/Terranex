'use client';

import { useActionState } from 'react';
import { updatePassword } from '@/features/auth/actions';

export function ResetPasswordForm() {
  const [state, action, pending] = useActionState(updatePassword, {});

  return (
    <main className="shell" style={{ maxWidth: 480, paddingTop: '12vh' }}>
      <section className="card stack">
        <div>
          <h1>تعيين كلمة مرور جديدة</h1>
          <p className="muted">استخدم كلمة مرور من 8 أحرف على الأقل.</p>
        </div>

        <form action={action} className="stack" noValidate>
          <label>
            كلمة المرور الجديدة
            <input name="password" type="password" autoComplete="new-password" minLength={8} required />
          </label>
          <label>
            تأكيد كلمة المرور
            <input name="confirmPassword" type="password" autoComplete="new-password" minLength={8} required />
          </label>
          {state.error && <p className="error" role="alert">{state.error}</p>}
          <button disabled={pending}>{pending ? 'جارٍ الحفظ…' : 'حفظ كلمة المرور'}</button>
        </form>
      </section>
    </main>
  );
}
