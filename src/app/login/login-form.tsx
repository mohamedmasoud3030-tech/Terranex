'use client';

import { useActionState } from 'react';
import { signIn } from '@/features/auth/actions';
import { AuthShell } from '@/shared/ui/auth';

export function LoginForm({ sessionExpired = false }: { sessionExpired?: boolean }) {
  const [state, action, pending] = useActionState(signIn, { error: undefined });
  return (
    <AuthShell>
      <section className="card stack">
        <div>
          <h1>مرحبًا بك في تيرانكس</h1>
          <p className="muted">سجّل الدخول للوصول إلى منظمة الاستثمار ومشاريعها.</p>
          {sessionExpired ? (
            <p className="banner warning" role="status">انتهت جلستك أو لم تعد صالحة. سجّل الدخول مرة أخرى للمتابعة.</p>
          ) : null}
        </div>
        <form action={action} className="stack" noValidate>
          <label>
            البريد الإلكتروني
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            كلمة المرور
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          {state.error && <p className="error" role="alert">{state.error}</p>}
          <button disabled={pending}>{pending ? 'جارٍ الدخول…' : 'تسجيل الدخول'}</button>
        </form>
        <a href="/forgot-password">نسيت كلمة المرور؟</a>
      </section>
    </AuthShell>
  );
}
