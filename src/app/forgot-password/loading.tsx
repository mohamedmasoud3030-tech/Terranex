import { PageSkeleton } from '@/shared/ui';

/**
 * The auth pages `force-dynamic` because they await `supabase.auth.getUser()`
 * before deciding whether to redirect — a real network call, so the wait is
 * real. `AuthShell` is deliberately not rendered here: the login form renders
 * it itself, and drawing it twice would flash the identity panel.
 */
export default function Loading() {
  return <PageSkeleton blocks={1} />;
}
