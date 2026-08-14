import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type FarmRead = {
  id: string;
  organization_id: string;
  project_id: string;
  name: string;
  internal_reference: string | null;
  operating_location: string | null;
  tenure_description: string | null;
  timezone: string;
  map_reference: string | null;
  created_by: string;
  created_at: string;
};

export type FieldRead = {
  id: string;
  organization_id: string;
  project_id: string;
  farm_id: string;
  identifier: string;
  area_quantity: string; // text-cast bigint/numeric for safe transport
  area_unit: 'M2' | 'HECTARE' | 'FEDDAN';
  soil_notes: string | null;
  irrigation_notes: string | null;
  created_by: string;
  created_at: string;
};

export type CropCycleRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop: string;
  variety: string | null;
  season_reference: string;
  planned_start_date: string;
  planned_end_date: string;
  target_yield_quantity: string | null;
  target_yield_unit: string | null;
  operational_state: 'PLANNED' | 'ESTABLISHED' | 'GROWING' | 'HARVESTING' | 'CLOSED' | 'CANCELLED' | 'FAILED';
  created_by: string;
  created_at: string;
};

export type CropAssignmentRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  field_id: string;
  assigned_area_quantity: string;
  assigned_area_unit: 'M2' | 'HECTARE' | 'FEDDAN';
  planned_start_date: string;
  planned_end_date: string;
  created_by: string;
  created_at: string;
};

export type FieldActivityRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  field_id: string;
  assignment_id: string;
  activity_date: string;
  activity_type: 'PREPARE' | 'PLANT' | 'IRRIGATE' | 'FERTILIZE' | 'SPRAY' | 'SCOUT' | 'WEED' | 'OTHER';
  quantity: string | null;
  unit: string | null;
  notes: string | null;
  evidence_reference: string | null;
  recorded_by: string;
  created_at: string;
};

export type CropCycleTimelineEntry = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  previous_state: string | null;
  new_state: string;
  reason: string;
  evidence_reference: string | null;
  changed_by: string;
  changed_at: string;
};

async function many<T>(
  view: string,
  columns: string,
  projectId: string,
  orderColumn: string,
): Promise<T[]> {
  const s = await createClient();
  const { data, error } = await s
    .from(view)
    .select(columns)
    .eq('project_id', projectId)
    .order(orderColumn, { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as T[];
}

export const getFarms = (projectId: string) =>
  many<FarmRead>(
    'farms_read',
    'id,organization_id,project_id,name,internal_reference,operating_location,tenure_description,timezone,map_reference,created_by,created_at',
    projectId,
    'created_at',
  );

export const getFields = (projectId: string) =>
  many<FieldRead>(
    'fields_read',
    'id,organization_id,project_id,farm_id,identifier,area_quantity,area_unit,soil_notes,irrigation_notes,created_by,created_at',
    projectId,
    'created_at',
  );

export const getCropCycles = (projectId: string) =>
  many<CropCycleRead>(
    'crop_cycles_read',
    'id,organization_id,project_id,crop,variety,season_reference,planned_start_date,planned_end_date,target_yield_quantity,target_yield_unit,operational_state,created_by,created_at',
    projectId,
    'created_at',
  );

export const getCropAssignments = (projectId: string) =>
  many<CropAssignmentRead>(
    'crop_cycle_field_assignments_read',
    'id,organization_id,project_id,crop_cycle_id,field_id,assigned_area_quantity,assigned_area_unit,planned_start_date,planned_end_date,created_by,created_at',
    projectId,
    'created_at',
  );

export const getFieldActivities = (projectId: string) =>
  many<FieldActivityRead>(
    'field_activities_read',
    'id,organization_id,project_id,crop_cycle_id,field_id,assignment_id,activity_date,activity_type,quantity,unit,notes,evidence_reference,recorded_by,created_at',
    projectId,
    'activity_date',
  );

export const getCropCycleTimeline = (projectId: string) =>
  many<CropCycleTimelineEntry>(
    'crop_cycle_timeline_read',
    'id,organization_id,project_id,crop_cycle_id,previous_state,new_state,reason,evidence_reference,changed_by,changed_at',
    projectId,
    'changed_at',
  );
