import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type SiteRead = {
  id: string;
  organization_id: string;
  project_id: string;
  name: string;
  internal_reference: string;
  site_type: string;
  location_description: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export type HerdRead = {
  id: string;
  organization_id: string;
  project_id: string;
  name: string;
  internal_reference: string;
  species: string;
  purpose: string;
  breed_descriptor: string | null;
  created_by: string;
  created_at: string;
};

export type CohortRead = {
  id: string;
  organization_id: string;
  project_id: string;
  herd_id: string;
  herd_name: string;
  herd_reference: string;
  species: string;
  purpose: string;
  initial_site_id: string;
  initial_site_name: string;
  cohort_reference: string;
  origin_type: string;
  origin_date: string;
  opening_headcount: number;
  sex_composition: string | null;
  breed_descriptor: string | null;
  opening_weight_value: string | null;
  opening_weight_unit: string | null;
  opening_weight_basis: string | null;
  origin_evidence_reference: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
  lifecycle_state: string;
};

export type CohortTimelineRead = {
  id: string;
  organization_id: string;
  project_id: string;
  cohort_id: string;
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
  order = 'created_at',
): Promise<T[]> {
  const client = await createClient();
  const { data, error } = await client
    .from(view)
    .select(columns)
    .eq('project_id', projectId)
    .order(order, { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as T[];
}

export const getLivestockSites = (projectId: string) => many<SiteRead>(
  'livestock_sites_read',
  'id,organization_id,project_id,name,internal_reference,site_type,location_description,notes,created_by,created_at',
  projectId,
);

export const getLivestockHerds = (projectId: string) => many<HerdRead>(
  'livestock_herds_read',
  'id,organization_id,project_id,name,internal_reference,species,purpose,breed_descriptor,created_by,created_at',
  projectId,
);

export const getLivestockCohorts = (projectId: string) => many<CohortRead>(
  'livestock_cohorts_read',
  'id,organization_id,project_id,herd_id,herd_name,herd_reference,species,purpose,initial_site_id,initial_site_name,cohort_reference,origin_type,origin_date,opening_headcount,sex_composition,breed_descriptor,opening_weight_value,opening_weight_unit,opening_weight_basis,origin_evidence_reference,notes,created_by,created_at,lifecycle_state',
  projectId,
);

export const getLivestockCohortTimeline = (projectId: string) => many<CohortTimelineRead>(
  'livestock_cohort_timeline_read',
  'id,organization_id,project_id,cohort_id,previous_state,new_state,reason,evidence_reference,changed_by,changed_at',
  projectId,
  'changed_at',
);

/** GF-021 derived current placement. Never a stored column. */
export type CurrentPlacementRead = {
  cohort_id: string;
  organization_id: string;
  project_id: string;
  cohort_reference: string;
  current_site_id: string;
  current_site_name: string;
  current_herd_id: string;
  current_herd_name: string;
  species: string;
  purpose: string;
  placement_source: 'OPENING' | 'MOVEMENT';
  effective_from: string;
  movement_id: string | null;
};

export type MovementRead = {
  id: string;
  organization_id: string;
  project_id: string;
  cohort_id: string;
  cohort_reference: string;
  previous_movement_id: string | null;
  effective_at: string;
  source_site_id: string;
  source_site_name: string;
  source_herd_id: string;
  source_herd_name: string;
  destination_site_id: string;
  destination_site_name: string;
  destination_herd_id: string;
  destination_herd_name: string;
  site_changed: boolean;
  herd_changed: boolean;
  reason: string;
  evidence_reference: string | null;
  notes: string | null;
  moved_by: string;
  recorded_at: string;
};

/**
 * Exact integer quantity rollforward. Never a stored counter.
 *
 * GF-021 introduced it with aggregate increase/decrease only; GF-022 added the
 * per-class breakdown. The invariant the view guarantees is:
 *   current = opening + births + split_in + merge_in
 *                     - mortality - split_out - merge_out
 */
export type QuantityRollforwardRead = {
  cohort_id: string;
  organization_id: string;
  project_id: string;
  cohort_reference: string;
  opening_headcount: number;
  births: number;
  mortality: number;
  split_in: number;
  split_out: number;
  merge_in: number;
  merge_out: number;
  quantity_increase: number;
  quantity_decrease: number;
  current_quantity: number;
};

export type QuantityEventRead = {
  id: string;
  organization_id: string;
  project_id: string;
  cohort_id: string;
  cohort_reference: string;
  event_type: string;
  event_label: string;
  direction: number;
  quantity: number;
  signed_quantity: number;
  effective_at: string;
  operation_id: string | null;
  cause_category: string | null;
  cause_detail: string | null;
  evidence_reference: string | null;
  notes: string | null;
  recorded_by: string;
  recorded_at: string;
};

export type CohortLineageRead = {
  id: string;
  organization_id: string;
  project_id: string;
  operation_id: string;
  operation_type: 'SPLIT' | 'MERGE';
  effective_at: string;
  reason: string;
  evidence_reference: string | null;
  source_cohort_id: string;
  source_cohort_reference: string;
  destination_cohort_id: string;
  destination_cohort_reference: string;
  quantity: number;
  performed_by: string;
  created_at: string;
};

export type WeightEventRead = {
  id: string;
  organization_id: string;
  project_id: string;
  cohort_id: string;
  cohort_reference: string;
  effective_at: string;
  method: string;
  weight_value: string;
  weight_unit: string;
  value_meaning: string;
  is_estimate: boolean;
  measured_animal_count: number | null;
  sample_size: number | null;
  evidence_reference: string | null;
  notes: string | null;
  recorded_by: string;
  recorded_at: string;
};

export const getLivestockCurrentPlacements = (projectId: string) =>
  many<CurrentPlacementRead>(
    'livestock_cohort_current_placement_read',
    'cohort_id,organization_id,project_id,cohort_reference,current_site_id,current_site_name,current_herd_id,current_herd_name,species,purpose,placement_source,effective_from,movement_id',
    projectId,
    'effective_from',
  );

export const getLivestockMovements = (projectId: string) => many<MovementRead>(
  'livestock_cohort_movements_read',
  'id,organization_id,project_id,cohort_id,cohort_reference,previous_movement_id,effective_at,source_site_id,source_site_name,source_herd_id,source_herd_name,destination_site_id,destination_site_name,destination_herd_id,destination_herd_name,site_changed,herd_changed,reason,evidence_reference,notes,moved_by,recorded_at',
  projectId,
  'effective_at',
);

export const getLivestockQuantityRollforward = (projectId: string) =>
  many<QuantityRollforwardRead>(
    'livestock_cohort_quantity_rollforward',
    'cohort_id,organization_id,project_id,cohort_reference,opening_headcount,births,mortality,split_in,split_out,merge_in,merge_out,quantity_increase,quantity_decrease,current_quantity',
    projectId,
    'cohort_reference',
  );

export const getLivestockWeightEvents = (projectId: string) =>
  many<WeightEventRead>(
    'livestock_weight_events_read',
    'id,organization_id,project_id,cohort_id,cohort_reference,effective_at,method,weight_value,weight_unit,value_meaning,is_estimate,measured_animal_count,sample_size,evidence_reference,notes,recorded_by,recorded_at',
    projectId,
    'effective_at',
  );

export const getLivestockQuantityEvents = (projectId: string) =>
  many<QuantityEventRead>(
    'livestock_quantity_events_read',
    'id,organization_id,project_id,cohort_id,cohort_reference,event_type,event_label,direction,quantity,signed_quantity,effective_at,operation_id,cause_category,cause_detail,evidence_reference,notes,recorded_by,recorded_at',
    projectId,
    'effective_at',
  );

export const getLivestockCohortLineage = (projectId: string) =>
  many<CohortLineageRead>(
    'livestock_cohort_lineage_read',
    'id,organization_id,project_id,operation_id,operation_type,effective_at,reason,evidence_reference,source_cohort_id,source_cohort_reference,destination_cohort_id,destination_cohort_reference,quantity,performed_by,created_at',
    projectId,
    'effective_at',
  );
