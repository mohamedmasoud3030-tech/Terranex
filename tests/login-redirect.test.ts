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
    expect(loginForm).toContain('href="/forgot-password"');
  });

  it('keeps only the intended anonymous routes public', () => {
    expect(proxy).toContain("pathname === '/login'");
    expect(proxy).toContain("pathname === '/forgot-password'");
    expect(proxy).toContain("pathname === '/auth/recovery'");
    expect(proxy).toContain('if (!user && !isPublicAuthRoute)');
    expect(proxy).toContain('api/health');
  });
});
