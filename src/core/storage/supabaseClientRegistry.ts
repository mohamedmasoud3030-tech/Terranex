/**
 * Shared registry for the injected Supabase client.
 * Kept separate from `supabaseClient.ts` (which reads `import.meta.env`) so
 * that any module needing DB access — `supabaseStore.ts`, `deletionGuards.ts`,
 * future RPC callers — can depend on this instead, keeping `import.meta.env`
 * out of the module graph the Node test suite compiles.
 *
 * `setSupabaseClient` must be called once at app bootstrap
 * (see `supabaseBootstrap.ts`, imported first thing in `main.tsx`) or, in
 * tests, with an in-memory fake client (see `tests/helpers/fakeSupabase.cjs`).
 */
import type { SupabaseClient } from '@supabase/supabase-js';

let injectedClient: SupabaseClient | null = null;

export function setSupabaseClient(client: SupabaseClient): void {
  injectedClient = client;
}

export function requireClient(): SupabaseClient {
  if (!injectedClient) {
    throw new Error(
      'Supabase client غير مهيأ. تأكد من استدعاء setSupabaseClient عند بدء التطبيق (راجع supabaseBootstrap.ts) أو في إعداد الاختبار.',
    );
  }
  return injectedClient;
}
