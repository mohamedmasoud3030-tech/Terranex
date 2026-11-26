import { describe, expect, it } from 'vitest';
import { recoveryRedirectUrl } from '@/features/auth/recovery-url';

describe('recoveryRedirectUrl', () => {
  it('prefers an explicit app URL and trims slashes', () => {
    expect(recoveryRedirectUrl({ NEXT_PUBLIC_APP_URL: ' https://app.example.com// ', VERCEL_URL: 'x.vercel.app' })).toBe(
      'https://app.example.com/auth/recovery',
    );
  });

  it('uses the current deployment host before the production host', () => {
    expect(
      recoveryRedirectUrl({
        VERCEL_ENV: 'preview',
        VERCEL_URL: 'preview-abc.vercel.app',
        VERCEL_PROJECT_PRODUCTION_URL: 'prod.example.com',
      }),
    ).toBe('https://preview-abc.vercel.app/auth/recovery');
  });

  it('fails closed in preview or unknown hosted environments without a current host', () => {
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'preview', VERCEL_PROJECT_PRODUCTION_URL: 'prod.example.com' })).toBeUndefined();
    expect(recoveryRedirectUrl({ VERCEL_PROJECT_PRODUCTION_URL: 'prod.example.com' })).toBeUndefined();
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'development' })).toBeUndefined();
  });

  it('uses the production host only for explicit production', () => {
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'production', VERCEL_PROJECT_PRODUCTION_URL: 'https://prod.example.com/' })).toBe(
      'https://prod.example.com/auth/recovery',
    );
  });

  it('fails closed for production with missing, empty or blank hosts', () => {
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'production' })).toBeUndefined();
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'production', VERCEL_PROJECT_PRODUCTION_URL: '' })).toBeUndefined();
    expect(recoveryRedirectUrl({ VERCEL_ENV: 'production', VERCEL_PROJECT_PRODUCTION_URL: '   ', VERCEL_URL: '  ' })).toBeUndefined();
  });

  it('falls back to localhost only when nothing is configured', () => {
    expect(recoveryRedirectUrl({})).toBe('http://localhost:3000/auth/recovery');
    expect(recoveryRedirectUrl({ VERCEL_ENV: '  ' })).toBe('http://localhost:3000/auth/recovery');
  });
});
