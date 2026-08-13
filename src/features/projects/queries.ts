import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type ProjectSector = 'REAL_ESTATE' | 'AGRICULTURE';

export type ProjectListItem = {
  id: string;
  name: string;
  internal_reference: string | null;
  description: string | null;
  lifecycle_state: string;
  reporting_currency: string;
  sector: ProjectSector;
  created_at: string;
};

export type ProjectDetail = {
  id: string;
  organization_id: string;
  name: string;
  internal_reference: string | null;
  description: string | null;
  lifecycle_state: string;
  reporting_currency: string;
  sector: ProjectSector;
};

export async function getProjects(organizationId: string): Promise<ProjectListItem[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_projects')
    .select('id,name,internal_reference,description,lifecycle_state,reporting_currency,sector,created_at')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ProjectListItem[];
}

export async function getProject(id: string): Promise<ProjectDetail | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('investment_projects')
    .select('id,organization_id,name,internal_reference,description,lifecycle_state,reporting_currency,sector')
    .eq('id', id)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return (data ?? null) as ProjectDetail | null;
}
