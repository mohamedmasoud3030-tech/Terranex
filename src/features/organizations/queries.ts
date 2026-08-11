import { createClient } from '@/shared/supabase/server';
export async function getOrganizations() { const s = await createClient(); const { data, error } = await s.from('organizations').select('id,name').order('created_at'); if (error) throw error; return data; }
