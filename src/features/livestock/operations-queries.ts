import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

async function many<T>(view: string, columns: string, projectId: string, order = 'created_at'): Promise<T[]> {
  const client = await createClient();
  const { data, error } = await client.from(view).select(columns)
    .eq('project_id', projectId).order(order, { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as T[];
}

export type MedicineProductRead = {
  id: string; organization_id: string; project_id: string; product_reference: string;
  name: string; product_kind: string; active_ingredient: string | null;
  default_withdrawal_days: number; notes: string | null; created_at: string;
};
export type AnimalRead = {
  id: string; organization_id: string; project_id: string; cohort_id: string;
  cohort_reference: string; identifier_type: string; identifier_value: string;
  sex: string; birth_date: string | null; breed_descriptor: string | null;
  identified_at: string; evidence_reference: string | null; notes: string | null;
  identity_status: string; identification_quantity_effect: number; recorded_at: string;
};
export type HealthEventRead = {
  id: string; organization_id: string; project_id: string; cohort_id: string;
  cohort_reference: string; animal_id: string | null; animal_identifier: string | null;
  event_type: string; condition_classification: string | null; condition_name: string | null;
  medicine_product_id: string | null; product_reference: string | null; product_name: string | null;
  dose_quantity: string | null; dose_unit: string | null; administration_route: string | null;
  effective_at: string; practitioner_name: string; withdrawal_period_days: number | null;
  withdrawal_ends_at: string | null; withdrawal_status: 'NONE' | 'ACTIVE' | 'ENDED';
  evidence_reference: string | null; notes: string | null; recorded_at: string;
};
export type ReproductionEventRead = {
  id: string; organization_id: string; project_id: string; cohort_id: string;
  cohort_reference: string; subject_animal_id: string | null; subject_animal_identifier: string | null;
  event_type: string; subject_count: number; service_method: string | null;
  pregnancy_status: string | null; expected_birth_date: string | null;
  observed_live_birth_count: number | null; stillbirth_count: number | null;
  birth_quantity_effect: string | null; birth_quantity_event_id: string | null;
  affects_authoritative_quantity: boolean; weaned_count: number | null;
  dam_identifier: string | null; sire_identifier: string | null; effective_at: string;
  performed_by_name: string; evidence_reference: string | null; notes: string | null;
  recorded_at: string;
};
export type FeedItemRead = {
  id: string; organization_id: string; project_id: string; item_reference: string;
  name: string; feed_category: string; issue_unit: 'KG' | 'LITER'; notes: string | null;
  created_at: string;
};
export type FeedIssueRead = {
  id: string; organization_id: string; project_id: string; cohort_id: string;
  cohort_reference: string; feed_item_id: string; item_reference: string;
  feed_item_name: string; feed_category: string; quantity: string; unit: string;
  effective_at: string; feeding_period_start: string | null; feeding_period_end: string | null;
  issued_by_name: string; evidence_reference: string | null; notes: string | null;
  recorded_at: string;
};
export type FcrMetricRead = {
  cohort_id: string; organization_id: string; project_id: string; cohort_reference: string;
  previous_weight_event_id: string | null; previous_weight_at: string | null;
  latest_weight_event_id: string | null; latest_weight_at: string | null;
  feed_quantity_kg: string | null; weight_gain_kg: string | null; fcr: string | null;
  metric_status: string;
};

export const getMedicineProducts = (projectId: string) => many<MedicineProductRead>(
  'livestock_medicine_products_read',
  'id,organization_id,project_id,product_reference,name,product_kind,active_ingredient,default_withdrawal_days,notes,created_at',
  projectId,
);
export const getIdentifiedAnimals = (projectId: string) => many<AnimalRead>(
  'livestock_animals_read',
  'id,organization_id,project_id,cohort_id,cohort_reference,identifier_type,identifier_value,sex,birth_date,breed_descriptor,identified_at,evidence_reference,notes,identity_status,identification_quantity_effect,recorded_at',
  projectId, 'identified_at',
);
export const getHealthEvents = (projectId: string) => many<HealthEventRead>(
  'livestock_health_events_read',
  'id,organization_id,project_id,cohort_id,cohort_reference,animal_id,animal_identifier,event_type,condition_classification,condition_name,medicine_product_id,product_reference,product_name,dose_quantity,dose_unit,administration_route,effective_at,practitioner_name,withdrawal_period_days,withdrawal_ends_at,withdrawal_status,evidence_reference,notes,recorded_at',
  projectId, 'effective_at',
);
export const getReproductionEvents = (projectId: string) => many<ReproductionEventRead>(
  'livestock_reproduction_events_read',
  'id,organization_id,project_id,cohort_id,cohort_reference,subject_animal_id,subject_animal_identifier,event_type,subject_count,service_method,pregnancy_status,expected_birth_date,observed_live_birth_count,stillbirth_count,birth_quantity_effect,birth_quantity_event_id,affects_authoritative_quantity,weaned_count,dam_identifier,sire_identifier,effective_at,performed_by_name,evidence_reference,notes,recorded_at',
  projectId, 'effective_at',
);
export const getFeedItems = (projectId: string) => many<FeedItemRead>(
  'livestock_feed_items_read',
  'id,organization_id,project_id,item_reference,name,feed_category,issue_unit,notes,created_at',
  projectId,
);
export const getFeedIssues = (projectId: string) => many<FeedIssueRead>(
  'livestock_feed_issues_read',
  'id,organization_id,project_id,cohort_id,cohort_reference,feed_item_id,item_reference,feed_item_name,feed_category,quantity,unit,effective_at,feeding_period_start,feeding_period_end,issued_by_name,evidence_reference,notes,recorded_at',
  projectId, 'effective_at',
);
export const getFcrMetrics = (projectId: string) => many<FcrMetricRead>(
  'livestock_feed_conversion_metrics',
  'cohort_id,organization_id,project_id,cohort_reference,previous_weight_event_id,previous_weight_at,latest_weight_event_id,latest_weight_at,feed_quantity_kg,weight_gain_kg,fcr,metric_status',
  projectId, 'cohort_reference',
);
