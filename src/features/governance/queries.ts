import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type ProjectRiskRead = {
  risk_item_id: string;
  organization_id: string;
  project_id: string;
  title: string;
  description: string;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  owner_user_id: string;
  due_date: string | null;
  source_reference: string | null;
  recorded_by: string;
  recorded_at: string;
  status: 'OPEN' | 'RESOLVED';
  resolution_id: string | null;
  resolution_outcome: string | null;
  resolution_evidence_reference: string | null;
  resolved_by: string | null;
  resolved_at: string | null;
};

export type ProjectDecisionRead = {
  id: string;
  organization_id: string;
  project_id: string;
  title: string;
  decision_text: string;
  rationale: string | null;
  decision_date: string;
  evidence_reference: string;
  recorded_by: string;
  recorded_at: string;
};

export async function getProjectRisks(projectId: string): Promise<ProjectRiskRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_risk_items_read')
    .select('*')
    .eq('project_id', projectId)
    .order('recorded_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ProjectRiskRead[];
}

export async function getProjectDecisions(projectId: string): Promise<ProjectDecisionRead[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_decision_records')
    .select('id,organization_id,project_id,title,decision_text,rationale,decision_date,evidence_reference,recorded_by,recorded_at')
    .eq('project_id', projectId)
    .order('decision_date', { ascending: false })
    .order('recorded_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ProjectDecisionRead[];
}
