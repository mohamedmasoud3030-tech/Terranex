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
  movement_type: 'HARVEST_RECEIPT' | 'TRANSFER' | 'ADJUSTMENT_IN' | 'ADJUSTMENT_OUT' | 'SPOILAGE';
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
    'id,organization_id,project_id,harvest_lot_id,movement_type,movement_date,quantity,unit,from_storage_id,to_storage_id,from_storage_name,to_storage_name,reason,evidence_reference,recorded_by,created_at,lot_reference',
    projectId,
    'movement_date',
  );
