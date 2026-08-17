import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync('src/proxy.ts', 'utf8');

describe('runtime auth sequencing', () => {
  it('fails hard when Supabase browser configuration is missing', () => {
    expect(source).toContain("throw new Error('Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.')");
  });

  it('resolves the authenticated user before allowing private route rendering', () => {
    const getUser = source.indexOf('await supabase.auth.getUser()');
    const publicRouteResolution = source.indexOf('const isPublicAuthRoute =');
    const anonymousGuard = source.indexOf('if (!user && !isPublicAuthRoute)');
    const finalReturn = source.lastIndexOf('return response;');

    expect(getUser).toBeGreaterThan(-1);
    expect(publicRouteResolution).toBeGreaterThan(getUser);
    expect(anonymousGuard).toBeGreaterThan(publicRouteResolution);
    expect(finalReturn).toBeGreaterThan(anonymousGuard);
  });

  it('redirects anonymous private requests to login instead of weakening database grants', () => {
    expect(source).toContain("loginUrl.pathname = '/login'");
    expect(source).toContain('return NextResponse.redirect(loginUrl)');
    expect(source).not.toContain('GRANT SELECT');
  });
});
