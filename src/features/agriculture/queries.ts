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

export type InputItemRead = {
  id: string;
  organization_id: string;
  project_id: string;
  category: 'SEED' | 'FERTILIZER' | 'CHEMICAL';
  name: string;
  internal_reference: string | null;
  application_unit: string;
  manufacturer: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export type InputLotRead = {
  id: string;
  organization_id: string;
  project_id: string;
  input_item_id: string;
  input_item_name: string;
  input_category: 'SEED' | 'FERTILIZER' | 'CHEMICAL';
  lot_reference: string;
  supplier_reference: string | null;
  manufactured_on: string | null;
  expires_on: string | null;
  unit: string;
  evidence_reference: string | null;
  expiry_status: 'VALID' | 'EXPIRED' | 'NO_EXPIRY';
  created_by: string;
  created_at: string;
};

export type InputApplicationRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  field_id: string;
  assignment_id: string;
  field_activity_id: string;
  input_item_id: string;
  input_lot_id: string;
  input_category: 'SEED' | 'FERTILIZER' | 'CHEMICAL';
  activity_type: 'PLANT' | 'FERTILIZE' | 'SPRAY';
  application_date: string;
  quantity: string;
  unit: string;
  applied_area_quantity: string;
  applied_area_unit: 'M2' | 'HECTARE' | 'FEDDAN';
  /** Derived for display only (quantity / applied area); never stored twice. */
  application_rate: string;
  input_item_name: string;
  lot_reference: string;
  expires_on: string | null;
  lot_expiry_status: 'VALID' | 'EXPIRED' | 'NO_EXPIRY';
  field_identifier: string;
  crop: string;
  season_reference: string;
  notes: string | null;
  safety_note: string | null;
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

export const getInputItems = (projectId: string) =>
  many<InputItemRead>(
    'input_items_read',
    'id,organization_id,project_id,category,name,internal_reference,application_unit,manufacturer,notes,created_by,created_at',
    projectId,
    'created_at',
  );

export const getInputLots = (projectId: string) =>
  many<InputLotRead>(
    'input_lots_read',
    'id,organization_id,project_id,input_item_id,input_item_name,input_category,lot_reference,supplier_reference,manufactured_on,expires_on,unit,evidence_reference,expiry_status,created_by,created_at',
    projectId,
    'created_at',
  );

export const getInputApplications = (projectId: string) =>
  many<InputApplicationRead>(
    'input_applications_read',
    'id,organization_id,project_id,crop_cycle_id,field_id,assignment_id,field_activity_id,input_item_id,input_lot_id,input_category,activity_type,application_date,quantity,unit,applied_area_quantity,applied_area_unit,application_rate,input_item_name,lot_reference,expires_on,lot_expiry_status,field_identifier,crop,season_reference,notes,safety_note,evidence_reference,recorded_by,created_at',
    projectId,
    'application_date',
  );

export const getCropCycleTimeline = (projectId: string) =>
  many<CropCycleTimelineEntry>(
    'crop_cycle_timeline_read',
    'id,organization_id,project_id,crop_cycle_id,previous_state,new_state,reason,evidence_reference,changed_by,changed_at',
    projectId,
    'changed_at',
  );

// ---------------------------------------------------------------------------
// GF-016 — Harvest & Inventory Flow Foundation.
//
// Read models for Storage Location, Harvest Event, Harvest Lot, inventory
// by location, and append-only movement history. Current balances are
// derived in the database from movement facts, never stored.
// ---------------------------------------------------------------------------
export type StorageLocationRead = {
  id: string;
  organization_id: string;
  project_id: string;
  name: string;
  internal_reference: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export type HarvestEventRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  field_id: string;
  assignment_id: string;
  harvest_date: string;
  gross_quantity: string;
  net_quantity: string;
  /** Derived for display only (gross - net); never stored twice. */
  harvest_loss: string;
  quantity_unit: string;
  grade: string | null;
  notes: string | null;
  evidence_reference: string | null;
  recorded_by: string;
  recorded_at: string;
  crop: string;
  season_reference: string;
  field_identifier: string;
  harvest_lot_id: string;
  lot_reference: string;
  destination_storage_id: string | null;
  destination_storage_name: string | null;
};

export type HarvestLotRead = {
  id: string;
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  field_id: string;
  assignment_id: string;
  harvest_event_id: string;
  lot_reference: string;
  harvest_date: string;
  initial_quantity: string;
  quantity_unit: string;
  grade: string | null;
  /** Derived for display only; never stored twice. */
  current_total_balance: string;
  crop: string;
  season_reference: string;
  field_identifier: string;
  created_by: string;
  created_at: string;
};

export type HarvestInventoryByLocationRead = {
  harvest_lot_id: string;
  organization_id: string;
  project_id: string;
  lot_reference: string;
  quantity_unit: string;
  grade: string | null;
  storage_id: string;
  storage_name: string;
  /** Derived for display only; never stored twice. */
  current_balance: string;
  last_movement_date: string | null;
};

export type HarvestInventoryMovementRead = {
  id: string;
  organization_id: string;
  project_id: string;
  harvest_lot_id: string;
  movement_type: 'HARVEST_RECEIPT' | 'TRANSFER' | 'ADJUSTMENT_IN' | 'ADJUSTMENT_OUT' | 'SPOILAGE' | 'SALE_ISSUE';
  movement_date: string;
  quantity: string;
  unit: string;
  from_storage_id: string | null;
  to_storage_id: string | null;
  from_storage_name: string | null;
  to_storage_name: string | null;
  reason: string | null;
  evidence_reference: string | null;
  recorded_by: string;
  created_at: string;
  lot_reference: string;
  agriculture_sale_line_id: string | null;
  sale_id: string | null;
  sale_reference: string | null;
};

export const getStorageLocations = (projectId: string) =>
  many<StorageLocationRead>(
    'storage_locations_read',
    'id,organization_id,project_id,name,internal_reference,notes,created_by,created_at',
    projectId,
    'created_at',
  );

export const getHarvestEvents = (projectId: string) =>
  many<HarvestEventRead>(
    'harvest_events_read',
    'id,organization_id,project_id,crop_cycle_id,field_id,assignment_id,harvest_date,gross_quantity,net_quantity,harvest_loss,quantity_unit,grade,notes,evidence_reference,recorded_by,recorded_at,crop,season_reference,field_identifier,harvest_lot_id,lot_reference,destination_storage_id,destination_storage_name',
    projectId,
    'harvest_date',
  );

export const getHarvestLots = (projectId: string) =>
  many<HarvestLotRead>(
    'harvest_lots_read',
    'id,organization_id,project_id,crop_cycle_id,field_id,assignment_id,harvest_event_id,lot_reference,harvest_date,initial_quantity,quantity_unit,grade,current_total_balance,crop,season_reference,field_identifier,created_by,created_at',
    projectId,
    'harvest_date',
  );

export const getHarvestInventoryByLocation = (projectId: string) =>
  many<HarvestInventoryByLocationRead>(
    'harvest_inventory_by_location_read',
    'harvest_lot_id,organization_id,project_id,lot_reference,quantity_unit,grade,storage_id,storage_name,current_balance,last_movement_date',
    projectId,
    'last_movement_date',
  );

export const getHarvestInventoryMovements = (projectId: string) =>
  many<HarvestInventoryMovementRead>(
    'harvest_inventory_movements_read',
    'id,organization_id,project_id,harvest_lot_id,movement_type,movement_date,quantity,unit,from_storage_id,to_storage_id,from_storage_name,to_storage_name,reason,evidence_reference,recorded_by,created_at,lot_reference,agriculture_sale_line_id,sale_id,sale_reference',
    projectId,
    'movement_date',
  );

// ---------------------------------------------------------------------------
// GF-017 — Agricultural Land Asset, Acquisition & Control read models.
// ---------------------------------------------------------------------------
export type AgriculturalLandAssetRead = {
  id: string;
  organization_id: string;
  project_id: string;
  name: string;
  internal_reference: string;
  legal_reference: string | null;
  legal_area_quantity: string;
  area_unit: 'M2' | 'HECTARE' | 'FEDDAN';
  legal_location_description: string | null;
  control_basis: 'PURCHASED' | 'LEASED' | 'CONTRIBUTED_IN_KIND' | 'MANAGED_FOR_OWNER';
  control_start_date: string;
  control_end_date: string | null;
  counterparty_party_id: string;
  counterparty_name: string;
  agreement_reference: string;
  evidence_reference: string;
  agreed_consideration_minor_units: string | null;
  consideration_currency: string | null;
  consideration_obligation_id: string | null;
  recorded_by: string;
  recorded_at: string;
  linked_farm_count: number;
};

export type FarmLandAssetLinkRead = {
  id: string;
  organization_id: string;
  project_id: string;
  land_asset_id: string;
  farm_id: string;
  land_asset_name: string;
  land_asset_reference: string;
  control_basis: AgriculturalLandAssetRead['control_basis'];
  legal_area_quantity: string;
  area_unit: AgriculturalLandAssetRead['area_unit'];
  farm_name: string;
  linked_by: string;
  linked_at: string;
};

export const getAgriculturalLandAssets = (projectId: string) =>
  many<AgriculturalLandAssetRead>(
    'agricultural_land_assets_read',
    'id,organization_id,project_id,name,internal_reference,legal_reference,legal_area_quantity,area_unit,legal_location_description,control_basis,control_start_date,control_end_date,counterparty_party_id,counterparty_name,agreement_reference,evidence_reference,agreed_consideration_minor_units,consideration_currency,consideration_obligation_id,recorded_by,recorded_at,linked_farm_count',
    projectId,
    'recorded_at',
  );

export const getFarmLandAssetLinks = (projectId: string) =>
  many<FarmLandAssetLinkRead>(
    'farm_land_asset_links_read',
    'id,organization_id,project_id,land_asset_id,farm_id,land_asset_name,land_asset_reference,control_basis,legal_area_quantity,area_unit,farm_name,linked_by,linked_at',
    projectId,
    'linked_at',
  );

// ---------------------------------------------------------------------------
// GF-018 — Agriculture Sale, Dispatch & Revenue read models.
// ---------------------------------------------------------------------------
export type AgricultureSaleRead = {
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
  state: 'DRAFT' | 'APPROVED' | 'CONTROL_TRANSFERRED' | 'SETTLED';
  control_state: 'DRAFT' | 'APPROVED' | 'CONTROL_TRANSFERRED';
  prepared_by: string;
  prepared_at: string;
  approved_by: string | null;
  approved_at: string | null;
  control_transfer_date: string | null;
  control_transfer_evidence_reference: string | null;
  control_transferred_by: string | null;
  control_transferred_at: string | null;
  line_count: number;
  aggregate_quantity: string | null;
  quantity_unit: string | null;
  agreed_total_minor_units: string;
  recognition_id: string | null;
  recognition_date: string | null;
  revenue_journal_batch_id: string | null;
  recognized_revenue_minor_units: string;
  collected_minor_units: string;
  outstanding_receivable_minor_units: string;
};

export type AgricultureSaleLineRead = {
  sale_line_id: string;
  organization_id: string;
  project_id: string;
  sale_id: string;
  line_no: number;
  harvest_lot_id: string;
  lot_reference: string;
  crop_cycle_id: string;
  field_id: string;
  harvest_date: string;
  source_storage_id: string;
  source_storage_name: string;
  quantity: string;
  unit: string;
  unit_price_minor_units: string;
  line_amount_minor_units: string;
  sale_issue_movement_id: string | null;
  dispatch_date: string | null;
};

export type AgricultureSaleCollectionRead = {
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

export type HarvestLotSaleTraceabilityRead = {
  harvest_lot_id: string;
  organization_id: string;
  project_id: string;
  lot_reference: string;
  crop_cycle_id: string;
  field_id: string;
  harvest_event_id: string;
  harvest_date: string;
  initial_quantity: string;
  quantity_unit: string;
  sale_line_id: string | null;
  sale_id: string | null;
  sale_reference: string | null;
  buyer_party_id: string | null;
  buyer_name: string | null;
  source_storage_id: string | null;
  source_storage_name: string | null;
  sold_quantity: string | null;
  unit_price_minor_units: string | null;
  line_amount_minor_units: string | null;
  sale_issue_movement_id: string | null;
  dispatch_date: string | null;
  recognition_id: string | null;
  revenue_journal_batch_id: string | null;
};

export const getAgricultureSales = (projectId: string) =>
  many<AgricultureSaleRead>(
    'agriculture_sales_read',
    'sale_id,organization_id,project_id,buyer_party_id,buyer_name,sale_reference,agreement_reference,sale_date,currency,terms,evidence_reference,state,control_state,prepared_by,prepared_at,approved_by,approved_at,control_transfer_date,control_transfer_evidence_reference,control_transferred_by,control_transferred_at,line_count,aggregate_quantity,quantity_unit,agreed_total_minor_units,recognition_id,recognition_date,revenue_journal_batch_id,recognized_revenue_minor_units,collected_minor_units,outstanding_receivable_minor_units',
    projectId,
    'sale_date',
  );

export const getAgricultureSaleLines = (projectId: string) =>
  many<AgricultureSaleLineRead>(
    'agriculture_sale_lines_read',
    'sale_line_id,organization_id,project_id,sale_id,line_no,harvest_lot_id,lot_reference,crop_cycle_id,field_id,harvest_date,source_storage_id,source_storage_name,quantity,unit,unit_price_minor_units,line_amount_minor_units,sale_issue_movement_id,dispatch_date',
    projectId,
    'line_no',
  );

export const getAgricultureSaleCollections = (projectId: string) =>
  many<AgricultureSaleCollectionRead>(
    'agriculture_sale_collections_read',
    'collection_id,organization_id,project_id,recognition_id,sale_id,cash_account_id,cash_account_name,amount_minor_units,currency,collection_date,evidence_reference,journal_batch_id,collected_by,collected_at',
    projectId,
    'collection_date',
  );

export const getHarvestLotSaleTraceability = (projectId: string) =>
  many<HarvestLotSaleTraceabilityRead>(
    'harvest_lot_sale_traceability_read',
    'harvest_lot_id,organization_id,project_id,lot_reference,crop_cycle_id,field_id,harvest_event_id,harvest_date,initial_quantity,quantity_unit,sale_line_id,sale_id,sale_reference,buyer_party_id,buyer_name,source_storage_id,source_storage_name,sold_quantity,unit_price_minor_units,line_amount_minor_units,sale_issue_movement_id,dispatch_date,recognition_id,revenue_journal_batch_id',
    projectId,
    'harvest_date',
  );

// ---------------------------------------------------------------------------
// GF-019 — result, integrity and authoritative cost-source read models.
// ---------------------------------------------------------------------------
export type CropCycleCostSourceRead = {
  source_journal_line_id: string;
  organization_id: string;
  project_id: string;
  batch_id: string;
  cost_obligation_id: string;
  description: string;
  transaction_date: string;
  party_id: string;
  posted_amount_minor_units: string;
  attributed_amount_minor_units: string;
  available_amount_minor_units: string;
  currency: string;
  authoritative_source: 'FINANCE_CORE_POSTED_JOURNAL_LINE';
};

export type CropCycleResultRead = {
  crop_cycle_id: string;
  organization_id: string;
  project_id: string;
  crop: string;
  variety: string | null;
  season_reference: string;
  operational_state: CropCycleRead['operational_state'];
  farm_names: string;
  field_identifiers: string;
  assignment_count: number;
  assigned_area_quantity: string | null;
  area_unit: FieldRead['area_unit'] | null;
  harvest_event_count: number;
  gross_harvest_quantity: string | null;
  net_accepted_harvest_quantity: string | null;
  harvest_loss: string | null;
  spoilage_quantity: string | null;
  quantity_sold: string | null;
  remaining_physical_inventory: string | null;
  quantity_unit: string | null;
  recognized_revenue_minor_units: string;
  cash_collected_minor_units: string;
  receivable_outstanding_minor_units: string;
  attributed_operating_cost_minor_units: string;
  operating_result_to_date_minor_units: string;
  currency: string;
  yield_per_area: string | null;
  recognized_revenue_minor_units_per_area: string | null;
  operating_cost_minor_units_per_area: string | null;
  realized_average_selling_price_minor_units: string | null;
  activity_count: number;
  input_application_count: number;
  source_evidence_completeness: 'COMPLETE' | 'PARTIAL' | 'INCOMPLETE';
  open_exception_count: number;
  hard_exception_count: number;
  open_exception_codes: string | null;
  land_asset_names: string | null;
  land_control_bases: string | null;
  land_consideration_minor_units: string;
  land_cost_treatment: 'EXCLUDED_FROM_CROP_CYCLE_OPERATING_COST';
  remaining_inventory_value_status: 'UNAVAILABLE_NOT_RECOGNIZED_BY_CURRENT_POLICY';
  cogs_status: 'NOT_GUESSED';
  closed_by: string | null;
  closed_at: string | null;
  close_reason: string | null;
  close_evidence_reference: string | null;
};

export type CropCycleIntegrityIssueRead = {
  organization_id: string;
  project_id: string;
  crop_cycle_id: string;
  code: string;
  severity: 'HARD' | 'WARN';
  message_ar: string;
};

export const getCropCycleCostSources = (projectId: string) =>
  many<CropCycleCostSourceRead>(
    'crop_cycle_cost_sources_read',
    'source_journal_line_id,organization_id,project_id,batch_id,cost_obligation_id,description,transaction_date,party_id,posted_amount_minor_units,attributed_amount_minor_units,available_amount_minor_units,currency,authoritative_source',
    projectId,
    'transaction_date',
  );

export const getCropCycleResults = (projectId: string) =>
  many<CropCycleResultRead>(
    'crop_cycle_results_read',
    'crop_cycle_id,organization_id,project_id,crop,variety,season_reference,operational_state,farm_names,field_identifiers,assignment_count,assigned_area_quantity,area_unit,harvest_event_count,gross_harvest_quantity,net_accepted_harvest_quantity,harvest_loss,spoilage_quantity,quantity_sold,remaining_physical_inventory,quantity_unit,recognized_revenue_minor_units,cash_collected_minor_units,receivable_outstanding_minor_units,attributed_operating_cost_minor_units,operating_result_to_date_minor_units,currency,yield_per_area,recognized_revenue_minor_units_per_area,operating_cost_minor_units_per_area,realized_average_selling_price_minor_units,activity_count,input_application_count,source_evidence_completeness,open_exception_count,hard_exception_count,open_exception_codes,land_asset_names,land_control_bases,land_consideration_minor_units,land_cost_treatment,remaining_inventory_value_status,cogs_status,closed_by,closed_at,close_reason,close_evidence_reference',
    projectId,
    'season_reference',
  );

export const getCropCycleIntegrityIssues = (projectId: string) =>
  many<CropCycleIntegrityIssueRead>(
    'crop_cycle_integrity_issues_read',
    'organization_id,project_id,crop_cycle_id,code,severity,message_ar',
    projectId,
    'code',
  );
