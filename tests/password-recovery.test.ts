import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const actions = readFileSync('src/features/auth/actions.ts', 'utf8');
const forgotPage = readFileSync('src/app/forgot-password/page.tsx', 'utf8');
const forgotForm = readFileSync('src/app/forgot-password/forgot-password-form.tsx', 'utf8');
const recoveryRoute = readFileSync('src/app/auth/recovery/route.ts', 'utf8');
const resetPage = readFileSync('src/app/reset-password/page.tsx', 'utf8');
const resetForm = readFileSync('src/app/reset-password/reset-password-form.tsx', 'utf8');
const proxy = readFileSync('src/proxy.ts', 'utf8');

describe('password recovery flow', () => {
  it('requests a PKCE recovery email without account-enumeration copy', () => {
    expect(actions).toContain('auth.resetPasswordForEmail');
    expect(actions).toContain('const redirectTo = recoveryRedirectUrl();');
    expect(actions.indexOf('if (!redirectTo)')).toBeLessThan(actions.indexOf('await createClient()', actions.indexOf('const redirectTo')));
    expect(forgotForm).toContain('إذا كان البريد مسجلًا لدينا');
    expect(forgotForm).toContain('role="status"');
    expect(forgotPage).toContain("params.recovery_error === '1'");
  });

  it('exchanges the one-time auth code before entering the protected reset page', () => {
    expect(recoveryRoute).toContain('auth.exchangeCodeForSession(code)');
    expect(recoveryRoute).toContain("target.pathname = '/reset-password'");
    expect(recoveryRoute).toContain("retry.pathname = '/forgot-password'");
    expect(proxy).toContain("pathname === '/auth/recovery'");
    expect(proxy).not.toContain("pathname === '/reset-password'");
  });

  it('requires a verified session and updates the authenticated user only', () => {
    expect(resetPage).toContain('auth.getUser()');
    expect(resetPage).toContain("redirect('/forgot-password?recovery_error=1')");
    expect(actions).toContain('auth.getUser()');
    expect(actions).toContain('auth.updateUser({ password: parsed.data.password })');
    expect(actions).toContain("parsed.data.password !== parsed.data.confirmPassword");
    expect(resetForm).toContain('autoComplete="new-password"');
  });
});
