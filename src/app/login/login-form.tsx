'use client';

import { useActionState } from 'react';
import { signIn } from '@/features/auth/actions';
import { AuthShell } from '@/shared/ui/auth';

export function LoginForm({ sessionExpired = false }: { sessionExpired?: boolean }) {
  const [state, action, pending] = useActionState(signIn, { error: undefined });
  return (
    <AuthShell>
      <header className="auth-head">
        <h1>مرحبًا بك في تيرانكس</h1>
        <p className="muted">سجّل الدخول للوصول إلى منظمة الاستثمار ومشاريعها.</p>
        {sessionExpired ? (
          <p className="banner warning" role="status">انتهت جلستك أو لم تعد صالحة. سجّل الدخول مرة أخرى للمتابعة.</p>
        ) : null}
      </header>
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
        <label className="auth-field">
          <span className="auth-field-label">كلمة المرور</span>
          <span className="auth-control">
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="4.25" y="8.75" width="11.5" height="7.75" rx="1.5" />
              <path d="M6.75 8.75V6.9a3.25 3.25 0 0 1 6.5 0v1.85" />
            </svg>
            <input name="password" type="password" autoComplete="current-password" required />
          </span>
        </label>
        {state.error && <p className="error" role="alert">{state.error}</p>}
        <button className="auth-submit" disabled={pending}>{pending ? 'جارٍ الدخول…' : 'تسجيل الدخول'}</button>
      </form>
      <a className="auth-alt-link" href="/forgot-password">نسيت كلمة المرور؟</a>
    </AuthShell>
  );
}
