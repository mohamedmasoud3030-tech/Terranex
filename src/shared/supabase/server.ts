import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { supabaseEnv } from './env';
export async function createClient() {
  const jar = await cookies(); const { url, key } = supabaseEnv();
  return createServerClient(url, key, { cookies: { getAll: () => jar.getAll(), setAll(items) { try { items.forEach(({ name, value, options }) => jar.set(name, value, options)); } catch { /* Server Components cannot write cookies. */ } } } });
}
