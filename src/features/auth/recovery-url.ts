type Env = Record<string, string | undefined>;

function clean(value: string | undefined): string {
  return (value ?? '').trim();
}

function toHost(value: string): string {
  return value.replace(/^https?:\/\//, '').replace(/\/+$/, '');
}

/**
 * Build the password-recovery redirect URL.
 *
 * Fails closed: returns undefined when the app runs in a declared hosted
 * environment but no trusted origin is available, so a recovery email is never
 * aimed at the wrong site (for example a preview pointing at production).
 * Only a truly unconfigured local environment falls back to localhost.
 */
export function recoveryRedirectUrl(env: Env = process.env): string | undefined {
  const configured = clean(env.NEXT_PUBLIC_APP_URL).replace(/\/+$/, '');
  if (configured) return `${configured}/auth/recovery`;

  const currentHost = toHost(clean(env.VERCEL_URL));
  if (currentHost) return `https://${currentHost}/auth/recovery`;

  const vercelEnv = clean(env.VERCEL_ENV);
  const productionHost = toHost(clean(env.VERCEL_PROJECT_PRODUCTION_URL));

  if (vercelEnv || productionHost) {
    if (vercelEnv === 'production' && productionHost) {
      return `https://${productionHost}/auth/recovery`;
    }
    return undefined;
  }

  return 'http://localhost:3000/auth/recovery';
}
