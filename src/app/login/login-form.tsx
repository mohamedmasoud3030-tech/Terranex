'use client';

import { useActionState } from 'react';
import { signIn } from '@/features/auth/actions';
import { AuthShell } from '@/shared/ui/auth';

export function LoginForm({ sessionExpired = false }: { sessionExpired?: boolean }) {
  const [state, action, pending] = useActionState(signIn, { error: undefined });
  return (
    <AuthShell>
      <header className="auth-head">
        <h1>مرحبًا بك</h1>
        <p className="auth-sub">سجّل الدخول للوصول إلى منظمة الاستثمار ومشاريعها.</p>
        {sessionExpired ? (
          <p className="auth-banner" role="status">انتهت جلستك أو لم تعد صالحة. سجّل الدخول مرة أخرى للمتابعة.</p>
        ) : null}
      </header>
      <form action={action} className="auth-form" noValidate>
        <label className="auth-field">
          <span className="auth-label">البريد الإلكتروني</span>
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label className="auth-field">
          <span className="auth-label">كلمة المرور</span>
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
        {state.error && <p className="auth-error" role="alert">{state.error}</p>}
        <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الدخول…' : 'تسجيل الدخول'}</button>
      </form>
      <a className="auth-alt-link" href="/forgot-password">نسيت كلمة المرور؟</a>
    </AuthShell>
  );
}
