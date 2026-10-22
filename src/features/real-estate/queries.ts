import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type RealEstateProfile = {
  id: string;
  organization_id: string;
  project_id: string;
  strategy: string;
  jurisdiction: string | null;
};
export type PropertyWorkspace = {
  property_asset_id: string;
  organization_id: string;
  project_id: string;
  name: string;
  asset_reference: string | null;
  strategy: string;
  jurisdiction: string | null;
  operational_state: string;
  state_changed_at: string;
  title_status: string | null;
  title_effective_date: string | null;
  title_evidence_reference: string | null;
  possession_status: string | null;
  possession_effective_date: string | null;
  possession_evidence_reference: string | null;
  acquisition_id: string | null;
  acquisition_state: string;
  contract_reference: string | null;
  contract_date: string | null;
  consideration_minor_units: string | null;
  closing_costs_minor_units: string | null;
  acquisition_currency: string | null;
  consideration_obligation_id: string | null;
  acquisition_payment_status: string;
};
export type Parcel = {
  id: string;
  organization_id: string;
  project_id: string;
  property_asset_id: string;
  identifier: string;
  cadastral_reference: string | null;
  legal_description: string | null;
  area_quantity: string;
  area_unit: string;
  created_at: string;
};
export type ControlRecord = {
  id: string;
  property_asset_id: string;
  parcel_id: string | null;
  record_type: string;
  control_type: string;
  status: string;
  effective_date: string | null;
  expiry_date: string | null;
  result: string | null;
  responsible_actor_id: string;
  evidence_reference: string;
  notes: string | null;
  recorded_at: string;
};
export type DevelopmentPhase = {
  phase_id: string;
  property_asset_id: string;
  parcel_id: string | null;
  name: string;
  sequence_no: number;
  planned_start_date: string | null;
  planned_end_date: string | null;
  operational_state: string;
  actual_start_at: string | null;
  actual_end_at: string | null;
};
export type DevelopmentMilestone = {
  milestone_id: string;
  property_asset_id: string;
  phase_id: string;
  name: string;
  sequence_no: number;
  planned_date: string | null;
  operational_state: string;
  completed_at: string | null;
};
export type BudgetVersion = {
  budget_version_id: string;
  property_asset_id: string;
  version_no: number;
  status: string;
  currency: string;
  basis_notes: string;
  total_minor_units: string;
  prepared_at: string;
  approved_at: string | null;
};
export type Valuation = {
  valuation_id: string;
  property_asset_id: string;
  effective_date: string;
  valuer_source: string;
  method: string;
  amount_minor_units: string;
  currency: string;
  assumptions_notes: string;
  confidence: string | null;
  status: string;
  evidence_reference: string;
  prepared_at: string;
  reviewed_at: string | null;
};
export type SectorEvent = {
  event_id: string;
  property_asset_id: string | null;
  parcel_id: string | null;
  phase_id: string | null;
  milestone_id: string | null;
  event_type: string;
  occurred_at: string;
  recorded_at: string;
  quantity: string | null;
  unit: string | null;
  location: string | null;
  notes: string;
  evidence_reference: string | null;
};
export type CostControl = {
  property_asset_id: string;
  parcel_id: string | null;
  phase_id: string | null;
  cost_category: string;
  currency: string;
  budget_minor_units: string;
  committed_minor_units: string;
  actual_minor_units: string;
  variance_minor_units: string;
};
export type CostDrilldown = {
  property_cost_item_id: string;
  property_asset_id: string;
  parcel_id: string | null;
  phase_id: string | null;
  cost_category: string;
  policy_reference: string;
  obligation_id: string;
  description: string;
  cost_treatment: string;
  obligation_status: string;
  obligation_minor_units: string;
  currency: string;
  committed_minor_units: string;
  actual_minor_units: string;
  originating_batch_id: string | null;
  is_reversed: boolean;
  authorized_at: string | null;
  classified_at: string;
};
export type TimelineEntry = {
  id: string;
  property_asset_id: string | null;
  occurred_at: string;
  actor_id: string;
  event_type: string;
  state: string | null;
  reason: string;
  evidence_reference: string | null;
};

async function many<T>(
  table: string,
  columns: string,
  projectId: string,
  orderColumn?: string,
): Promise<T[]> {
  const s = await createClient();
  let query = s.from(table).select(columns).eq('project_id', projectId);
  if (orderColumn) query = query.order(orderColumn, { ascending: false });
  const { data, error } = await query;
  if (error) throwOperatorQuery(error);

  // No generated Database type is available for Supabase views. Each call site
  // pairs a fixed view projection with its corresponding read-model type.
  return data as T[];
}

export async function getRealEstateProfile(projectId: string): Promise<RealEstateProfile | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('real_estate_project_profiles')
    .select('id,organization_id,project_id,strategy,jurisdiction')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throwOperatorQuery(error);
  return data as RealEstateProfile | null;
}
export const getPropertyWorkspaces = (projectId: string): Promise<PropertyWorkspace[]> =>
  many<PropertyWorkspace>(
    'property_asset_workspace_read',
    'property_asset_id,organization_id,project_id,name,asset_reference,strategy,jurisdiction,operational_state,state_changed_at,title_status,title_effective_date,title_evidence_reference,possession_status,possession_effective_date,possession_evidence_reference,acquisition_id,acquisition_state,contract_reference,contract_date,consideration_minor_units,closing_costs_minor_units,acquisition_currency,consideration_obligation_id,acquisition_payment_status',
    projectId,
  );
export const getParcels = (projectId: string): Promise<Parcel[]> =>
  many<Parcel>(
    'parcels_read',
    'id,organization_id,project_id,property_asset_id,identifier,cadastral_reference,legal_description,area_quantity,area_unit,created_at',
    projectId,
    'created_at',
  );
export const getControls = (projectId: string): Promise<ControlRecord[]> =>
  many<ControlRecord>(
    'property_controls_read',
    'id,project_id,property_asset_id,parcel_id,record_type,control_type,status,effective_date,expiry_date,result,responsible_actor_id,evidence_reference,notes,recorded_at',
    projectId,
    'recorded_at',
  );
export const getPhases = (projectId: string): Promise<DevelopmentPhase[]> =>
  many<DevelopmentPhase>(
    'development_phases_read',
    'phase_id,project_id,property_asset_id,parcel_id,name,sequence_no,planned_start_date,planned_end_date,operational_state,actual_start_at,actual_end_at',
    projectId,
  );
export const getMilestones = (projectId: string): Promise<DevelopmentMilestone[]> =>
  many<DevelopmentMilestone>(
    'development_milestones_read',
    'milestone_id,project_id,property_asset_id,phase_id,name,sequence_no,planned_date,operational_state,completed_at',
    projectId,
  );
export const getBudgets = (projectId: string): Promise<BudgetVersion[]> =>
  many<BudgetVersion>(
    'property_budget_versions_read',
    'budget_version_id,project_id,property_asset_id,version_no,status,currency,basis_notes,total_minor_units,prepared_at,approved_at',
    projectId,
    'prepared_at',
  );
export const getValuations = (projectId: string): Promise<Valuation[]> =>
  many<Valuation>(
    'property_valuations_read',
    'valuation_id,project_id,property_asset_id,effective_date,valuer_source,method,amount_minor_units,currency,assumptions_notes,confidence,status,evidence_reference,prepared_at,reviewed_at',
    projectId,
    'prepared_at',
  );
export const getSectorEvents = (projectId: string): Promise<SectorEvent[]> =>
  many<SectorEvent>(
    'real_estate_events_read',
    'event_id,project_id,property_asset_id,parcel_id,phase_id,milestone_id,event_type,occurred_at,recorded_at,quantity,unit,location,notes,evidence_reference',
    projectId,
    'occurred_at',
  );
export const getCostControls = (projectId: string): Promise<CostControl[]> =>
  many<CostControl>(
    'property_cost_control_read',
    'project_id,property_asset_id,parcel_id,phase_id,cost_category,currency,budget_minor_units,committed_minor_units,actual_minor_units,variance_minor_units',
    projectId,
  );
export const getCostDrilldown = (projectId: string): Promise<CostDrilldown[]> =>
  many<CostDrilldown>(
    'property_cost_drilldown_read',
    'project_id,property_cost_item_id,property_asset_id,parcel_id,phase_id,cost_category,policy_reference,obligation_id,description,cost_treatment,obligation_status,obligation_minor_units,currency,committed_minor_units,actual_minor_units,originating_batch_id,is_reversed,authorized_at,classified_at',
    projectId,
    'classified_at',
  );
export const getTimeline = (projectId: string): Promise<TimelineEntry[]> =>
  many<TimelineEntry>(
    'real_estate_timeline_read',
    'id,project_id,property_asset_id,occurred_at,actor_id,event_type,state,reason,evidence_reference',
    projectId,
    'occurred_at',
  );
