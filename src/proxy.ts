import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function proxy(request: NextRequest) {
  const response = NextResponse.next({ request });
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !key) {
    throw new Error('Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.');
  }

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookies) {
        cookies.forEach(({ name, value }) => request.cookies.set(name, value));
        cookies.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const pathname = request.nextUrl.pathname;
  const isPublicAuthRoute =
    pathname === '/login' ||
    pathname === '/forgot-password' ||
    pathname === '/auth/recovery';

  // Next.js can render a page and its parent layout concurrently. Protect the
  // route here so anonymous requests never reach tenant queries before the
  // layout's auth check has a chance to redirect. Password-recovery entry
  // routes stay public; /reset-password remains protected by the recovery
  // session established in /auth/recovery.
  if (!user && !isPublicAuthRoute) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = '/login';
    loginUrl.search = '';
    // Tell the sign-in page why the user landed there so it can explain
    // "session ended" instead of silently showing the form (root is
    // the normal entry point and carries no such hint).
    if (pathname !== '/') loginUrl.searchParams.set('reason', 'expired');
    return NextResponse.redirect(loginUrl);
  }

  // A malformed project id can never exist: answer 404 here, because the
  // route-level loading boundary otherwise streams the not-found page with 200.
  const projectSegment = /^\/projects\/([^/]+)/.exec(pathname)?.[1];
  if (
    projectSegment &&
    projectSegment !== 'new' &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(projectSegment)
  ) {
    const notFoundUrl = request.nextUrl.clone();
    notFoundUrl.pathname = '/missing-project';
    return NextResponse.rewrite(notFoundUrl, { status: 404 });
  }

  return response;
}

export const config = {
  // /api/health is a public liveness probe with no tenant data; it must stay
  // reachable without a session. The brand lockups (logo.png mark,
  // logo-full.png lockup) are public brand assets shown on the sign-in
  // screen itself, requested before any session exists — both directly and
  // as the /_next/image upstream fetch, which would otherwise inherit this
  // redirect and break the mark on all three auth pages.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api/health|logo(?:-full)?\\.png|icon\\.png).*)'],
};
