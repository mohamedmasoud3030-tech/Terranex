import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const loginPage = readFileSync('src/app/login/page.tsx', 'utf8');
const loginForm = readFileSync('src/app/login/login-form.tsx', 'utf8');
const proxy = readFileSync('src/proxy.ts', 'utf8');

describe('login route session handling', () => {
  it('redirects an authenticated user to the dashboard', () => {
    expect(loginPage).toContain('auth.getUser()');
    expect(loginPage).toContain("redirect('/')");
  });

  it('keeps the anonymous sign-in form intact as a client component', () => {
    expect(loginForm).toContain('useActionState(signIn');
    expect(loginForm).toContain('سجّل الدخول للوصول إلى منظمة الاستثمار ومشاريعها.');
    expect(loginForm).toContain('autoComplete="current-password"');
  });

  it('excludes the public health probe from the session proxy', () => {
    expect(proxy).toContain('api/health');
    expect(proxy).toContain("pathname !== '/login'");
  });
});
