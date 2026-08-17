import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/shared/supabase/server';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get('code');

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (!error) {
      const target = request.nextUrl.clone();
      target.pathname = '/reset-password';
      target.search = '';
      return NextResponse.redirect(target);
    }
  }

  const retry = request.nextUrl.clone();
  retry.pathname = '/forgot-password';
  retry.search = '';
  retry.searchParams.set('recovery_error', '1');
  return NextResponse.redirect(retry);
}
