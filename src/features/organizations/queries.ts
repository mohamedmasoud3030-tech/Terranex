import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';
import type { OrganizationSummary } from './active-org';

export async function getOrganizations(): Promise<OrganizationSummary[]> {
  const s = await createClient();
  const { data, error } = await s.from('organizations').select('id,name').order('created_at');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as OrganizationSummary[];
}
