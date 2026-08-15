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
  operational_inception_at: string;
  is_operational_as_of_now: boolean;
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
  'id,organization_id,project_id,herd_id,herd_name,herd_reference,species,purpose,initial_site_id,initial_site_name,cohort_reference,origin_type,origin_date,opening_headcount,sex_composition,breed_descriptor,opening_weight_value,opening_weight_unit,opening_weight_basis,origin_evidence_reference,notes,created_by,created_at,lifecycle_state,operational_inception_at,is_operational_as_of_now',
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
  purchase_in: number;
  mortality: number;
  sale_out: number;
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
  is_effective_as_of_now: boolean;
  operation_id: string | null;
  cause_category: string | null;
  cause_detail: string | null;
  disposal_method: string | null;
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
  is_effective_as_of_now: boolean;
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
  confidence_level: string;
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
    'cohort_id,organization_id,project_id,cohort_reference,opening_headcount,births,purchase_in,mortality,sale_out,split_in,split_out,merge_in,merge_out,quantity_increase,quantity_decrease,current_quantity',
    projectId,
    'cohort_reference',
  );

export const getLivestockWeightEvents = (projectId: string) =>
  many<WeightEventRead>(
    'livestock_weight_events_read',
    'id,organization_id,project_id,cohort_id,cohort_reference,effective_at,method,weight_value,weight_unit,value_meaning,is_estimate,measured_animal_count,sample_size,confidence_level,evidence_reference,notes,recorded_by,recorded_at',
    projectId,
    'effective_at',
  );

export const getLivestockQuantityEvents = (projectId: string) =>
  many<QuantityEventRead>(
    'livestock_quantity_events_read',
    'id,organization_id,project_id,cohort_id,cohort_reference,event_type,event_label,direction,quantity,signed_quantity,effective_at,is_effective_as_of_now,operation_id,cause_category,cause_detail,disposal_method,evidence_reference,notes,recorded_by,recorded_at',
    projectId,
    'effective_at',
  );

export const getLivestockCohortLineage = (projectId: string) =>
  many<CohortLineageRead>(
    'livestock_cohort_lineage_read',
    'id,organization_id,project_id,operation_id,operation_type,effective_at,is_effective_as_of_now,reason,evidence_reference,source_cohort_id,source_cohort_reference,destination_cohort_id,destination_cohort_reference,quantity,performed_by,created_at',
    projectId,
    'effective_at',
  );

// ---------------------------------------------------------------------------
// GF-024 — Livestock commercial, profitability & closeout read models.
// Money is bigint in storage and text on the wire.
// ---------------------------------------------------------------------------

export type LivestockPurchaseRead = {
  purchase_id: string;
  organization_id: string;
  project_id: string;
  supplier_party_id: string;
  supplier_name: string;
  purchase_reference: string;
  agreement_reference: string | null;
  effective_at: string;
  evidence_reference: string | null;
  notes: string | null;
  prepared_by: string;
  prepared_at: string;
  line_count: number;
  total_quantity: number;
  agreed_total_minor_units: string | null;
};

export type LivestockPurchaseLineRead = {
  purchase_line_id: string;
  organization_id: string;
  project_id: string;
  purchase_id: string;
  line_no: number;
  cohort_id: string;
  cohort_reference: string;
  species: string;
  purpose: string;
  quantity: number;
  agreed_unit_price_minor_units: string | null;
  agreed_amount_minor_units: string | null;
  purchase_in_event_id: string | null;
  purchase_in_effective_at: string | null;
};

export type LivestockSaleRead = {
  sale_id: string;
  organization_id: string;
  project_id: string;
  buyer_party_id: string;
  buyer_name: string;
  sale_reference: string;
  agreement_reference: string | null;
  sale_date: string;
  currency: string;
  terms: string | null;
  evidence_reference: string | null;
  state: string;
  control_state: string;
  prepared_by: string;
  prepared_at: string;
  approved_by: string | null;
  approved_at: string | null;
  control_transfer_date: string | null;
  control_transfer_evidence_reference: string | null;
  control_transferred_by: string | null;
  control_transferred_at: string | null;
  line_count: number;
  total_quantity: number;
  agreed_total_minor_units: string;
  recognition_id: string | null;
  recognition_date: string | null;
  revenue_journal_batch_id: string | null;
  recognized_revenue_minor_units: string;
  collected_minor_units: string;
  outstanding_receivable_minor_units: string;
};

export type LivestockSaleLineRead = {
  sale_line_id: string;
  organization_id: string;
  project_id: string;
  sale_id: string;
  line_no: number;
  cohort_id: string;
  cohort_reference: string;
  species: string;
  purpose: string;
  quantity: number;
  unit_price_minor_units: string;
  line_amount_minor_units: string;
  sale_out_event_id: string | null;
  sale_out_effective_at: string | null;
};

export type LivestockSaleCollectionRead = {
  collection_id: string;
  organization_id: string;
  project_id: string;
  recognition_id: string;
  sale_id: string;
  cash_account_id: string;
  cash_account_name: string;
  amount_minor_units: string;
  currency: string;
  collection_date: string;
  evidence_reference: string;
  journal_batch_id: string;
  collected_by: string;
  collected_at: string;
};

export type LivestockCostSourceRead = {
  source_journal_line_id: string;
  organization_id: string;
  project_id: string;
  batch_id: string;
  cost_obligation_id: string;
  description: string;
  transaction_date: string;
  party_id: string;
  posted_amount_minor_units: string;
  currency: string;
  attributed_amount_minor_units: string;
  available_amount_minor_units: string;
  authoritative_source: string;
};

export type LivestockCostAttributionRead = {
  id: string;
  organization_id: string;
  project_id: string;
  cohort_id: string;
  source_journal_line_id: string;
  source_journal_batch_id: string;
  obligation_id: string | null;
  source_description: string | null;
  source_transaction_date: string | null;
  attributed_amount_minor_units: string;
  currency: string;
  cost_category: string;
  policy_reference: string;
  evidence_reference: string;
  reversal_of_attribution_id: string | null;
  is_active: boolean;
  recorded_by: string;
  recorded_at: string;
  authoritative_source: string;
};

export type LivestockCohortResultRead = {
  cohort_id: string;
  organization_id: string;
  project_id: string;
  cohort_reference: string;
  herd_name: string;
  species: string;
  purpose: string;
  lifecycle_state: string;
  opening_headcount: number;
  births: number;
  purchase_in: number;
  split_in: number;
  merge_in: number;
  mortality: number;
  sale_out: number;
  split_out: number;
  merge_out: number;
  unsold_live_quantity: number;
  sale_count: number;
  recognized_revenue_minor_units: string;
  cash_collected_minor_units: string;
  receivable_outstanding_minor_units: string;
  attributed_operating_cost_minor_units: string;
  acquisition_attributed_cost_minor_units: string;
  operating_result_to_date_minor_units: string;
  currency: string;
  realized_average_selling_price_minor_units: string | null;
  unsold_live_quantity_value_status: string;
  biological_asset_value_status: string;
  cogs_status: string;
  closed_by: string | null;
  closed_at: string | null;
  close_reason: string | null;
};

export type LivestockCohortIssueRead = {
  organization_id: string;
  project_id: string;
  cohort_id: string;
  code: string;
  severity: string;
  message_ar: string;
};

export const getLivestockPurchases = (projectId: string) =>
  many<LivestockPurchaseRead>(
    'livestock_purchases_read',
    'purchase_id,organization_id,project_id,supplier_party_id,supplier_name,purchase_reference,agreement_reference,effective_at,evidence_reference,notes,prepared_by,prepared_at,line_count,total_quantity,agreed_total_minor_units',
    projectId,
    'effective_at',
  );

export const getLivestockPurchaseLines = (projectId: string) =>
  many<LivestockPurchaseLineRead>(
    'livestock_purchase_lines_read',
    'purchase_line_id,organization_id,project_id,purchase_id,line_no,cohort_id,cohort_reference,species,purpose,quantity,agreed_unit_price_minor_units,agreed_amount_minor_units,purchase_in_event_id,purchase_in_effective_at',
    projectId,
    'line_no',
  );

export const getLivestockSales = (projectId: string) =>
  many<LivestockSaleRead>(
    'livestock_sales_read',
    'sale_id,organization_id,project_id,buyer_party_id,buyer_name,sale_reference,agreement_reference,sale_date,currency,terms,evidence_reference,state,control_state,prepared_by,prepared_at,approved_by,approved_at,control_transfer_date,control_transfer_evidence_reference,control_transferred_by,control_transferred_at,line_count,total_quantity,agreed_total_minor_units,recognition_id,recognition_date,revenue_journal_batch_id,recognized_revenue_minor_units,collected_minor_units,outstanding_receivable_minor_units',
    projectId,
    'sale_date',
  );

export const getLivestockSaleLines = (projectId: string) =>
  many<LivestockSaleLineRead>(
    'livestock_sale_lines_read',
    'sale_line_id,organization_id,project_id,sale_id,line_no,cohort_id,cohort_reference,species,purpose,quantity,unit_price_minor_units,line_amount_minor_units,sale_out_event_id,sale_out_effective_at',
    projectId,
    'line_no',
  );

export const getLivestockSaleCollections = (projectId: string) =>
  many<LivestockSaleCollectionRead>(
    'livestock_sale_collections_read',
    'collection_id,organization_id,project_id,recognition_id,sale_id,cash_account_id,cash_account_name,amount_minor_units,currency,collection_date,evidence_reference,journal_batch_id,collected_by,collected_at',
    projectId,
    'collection_date',
  );

export const getLivestockCostSources = (projectId: string) =>
  many<LivestockCostSourceRead>(
    'livestock_cohort_cost_sources_read',
    'source_journal_line_id,organization_id,project_id,batch_id,cost_obligation_id,description,transaction_date,party_id,posted_amount_minor_units,currency,attributed_amount_minor_units,available_amount_minor_units,authoritative_source',
    projectId,
    'transaction_date',
  );

export const getLivestockCostAttributions = (projectId: string) =>
  many<LivestockCostAttributionRead>(
    'livestock_cohort_cost_attributions_read',
    'id,organization_id,project_id,cohort_id,source_journal_line_id,source_journal_batch_id,obligation_id,source_description,source_transaction_date,attributed_amount_minor_units,currency,cost_category,policy_reference,evidence_reference,reversal_of_attribution_id,is_active,recorded_by,recorded_at,authoritative_source',
    projectId,
    'recorded_at',
  );

export const getLivestockCohortResults = (projectId: string) =>
  many<LivestockCohortResultRead>(
    'livestock_cohort_results_read',
    'cohort_id,organization_id,project_id,cohort_reference,herd_name,species,purpose,lifecycle_state,opening_headcount,births,purchase_in,split_in,merge_in,mortality,sale_out,split_out,merge_out,unsold_live_quantity,sale_count,recognized_revenue_minor_units,cash_collected_minor_units,receivable_outstanding_minor_units,attributed_operating_cost_minor_units,acquisition_attributed_cost_minor_units,operating_result_to_date_minor_units,currency,realized_average_selling_price_minor_units,unsold_live_quantity_value_status,biological_asset_value_status,cogs_status,closed_by,closed_at,close_reason',
    projectId,
    'cohort_reference',
  );

export const getLivestockCohortIssues = (projectId: string) =>
  many<LivestockCohortIssueRead>(
    'livestock_cohort_integrity_issues_read',
    'organization_id,project_id,cohort_id,code,severity,message_ar',
    projectId,
    'cohort_id',
  );
