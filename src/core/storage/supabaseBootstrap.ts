/**
 * Wires the real Supabase client into the generic store factory.
 * Must be imported FIRST — before any feature `storage.ts` module — so the
 * client is available synchronously when each store's `hydrate()` runs at
 * import time. See `main.tsx`.
 *
 * This indirection (rather than `supabaseStore.ts` importing `supabaseClient.ts`
 * directly) keeps `import.meta.env` out of the module graph that the Node
 * test suite compiles, so tests can inject an in-memory fake client instead.
 */
import { supabase } from './supabaseClient';
import { setSupabaseClient } from './supabaseClientRegistry';

setSupabaseClient(supabase);
