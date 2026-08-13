import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';
export async function getOrganizations() { const s = await createClient(); const { data, error } = await s.from('organizations').select('id,name').order('created_at'); if (error) throwOperatorQuery(error); return data; }
