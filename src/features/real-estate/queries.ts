import { createClient } from '@/shared/supabase/server';

export type PropertyAsset = {
  id: string;
  project_id: string;
  display_name: string;
  strategy: 'ACQUIRE_HOLD' | 'DEVELOP_SELL' | 'LAND_TRADE';
  jurisdiction: string | null;
  title_status: 'PENDING' | 'CLEAR' | 'DISPUTED' | 'LEASED' | null;
  lifecycle_state: string;
  acquired_on: string | null;
  acquisition_cost_minor_units: string | null;
  currency: string;
  created_at: string;
};

export type Parcel = {
  id: string;
  property_asset_id: string;
  parcel_reference: string;
  area_sq_meters: number | null;
  legal_description: string | null;
  created_at: string;
};

export type PropertyCostItem = {
  id: string;
  property_asset_id: string;
  parcel_id: string | null;
  cost_category: string;
  is_capitalizable: boolean;
  cost_minor_units: string;
  currency: string;
  description: string | null;
  occurred_on: string;
  created_at: string;
};

export type PropertyValuation = {
  id: string;
  property_asset_id: string;
  effective_date: string;
  valuer_source: string;
  method: string;
  valuation_minor_units: string;
  currency: string;
  assumptions: string | null;
  confidence: 'LOW' | 'MEDIUM' | 'HIGH' | null;
  status: 'PROPOSED' | 'APPROVED' | 'REJECTED';
  approved_at: string | null;
  created_at: string;
};

export type PropertyCarryingAmount = {
  property_asset_id: string;
  currency: string;
  carrying_amount_minor_units: string;
};

export async function getPropertyAssets(projectId: string): Promise<PropertyAsset[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('property_assets_read')
    .select('id,project_id,display_name,strategy,jurisdiction,title_status,lifecycle_state,acquired_on,acquisition_cost_minor_units,currency,created_at')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as PropertyAsset[];
}

export async function getPropertyAsset(assetId: string): Promise<PropertyAsset | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('property_assets_read')
    .select('id,project_id,display_name,strategy,jurisdiction,title_status,lifecycle_state,acquired_on,acquisition_cost_minor_units,currency,created_at')
    .eq('id', assetId)
    .maybeSingle();
  if (error) throw error;
  return data as PropertyAsset | null;
}

export async function getParcels(propertyAssetId: string): Promise<Parcel[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('parcels')
    .select('id,property_asset_id,parcel_reference,area_sq_meters,legal_description,created_at')
    .eq('property_asset_id', propertyAssetId)
    .order('created_at');
  if (error) throw error;
  return data as Parcel[];
}

export async function getPropertyCostItems(propertyAssetId: string): Promise<PropertyCostItem[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('property_cost_items_read')
    .select('id,property_asset_id,parcel_id,cost_category,is_capitalizable,cost_minor_units,currency,description,occurred_on,created_at')
    .eq('property_asset_id', propertyAssetId)
    .order('occurred_on', { ascending: false });
  if (error) throw error;
  return data as PropertyCostItem[];
}

export async function getPropertyValuations(propertyAssetId: string): Promise<PropertyValuation[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('property_valuations_read')
    .select('id,property_asset_id,effective_date,valuer_source,method,valuation_minor_units,currency,assumptions,confidence,status,approved_at,created_at')
    .eq('property_asset_id', propertyAssetId)
    .order('effective_date', { ascending: false });
  if (error) throw error;
  return data as PropertyValuation[];
}

export async function getPropertyCarryingAmount(propertyAssetId: string): Promise<PropertyCarryingAmount | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('property_carrying_amount')
    .select('property_asset_id,currency,carrying_amount_minor_units')
    .eq('property_asset_id', propertyAssetId)
    .maybeSingle();
  if (error) throw error;
  return data as PropertyCarryingAmount | null;
}

export type Disposition = {
  id: string;
  project_id: string;
  property_asset_id: string;
  buyer_party_id: string;
  status: 'DRAFT' | 'APPROVED' | 'CONTROL_TRANSFERRED' | 'SETTLED' | 'CANCELLED';
  agreed_proceeds_minor_units: string;
  currency: string;
  agreement_date: string;
  control_transfer_date: string | null;
  selling_costs_minor_units: string;
  contract_reference: string | null;
  recognized_at: string | null;
  created_at: string;
};

export type SaleRecognition = {
  id: string;
  disposition_id: string;
  recognized_revenue_minor_units: string;
  derecognized_carrying_cost_minor_units: string;
  selling_costs_minor_units: string;
  realized_result_minor_units: string;
  currency: string;
  control_transfer_date: string;
  recognized_at: string;
};

export type SaleReceivable = {
  id: string;
  sale_recognition_id: string;
  receivable_minor_units: string;
  currency: string;
  status: 'OUTSTANDING' | 'PARTIAL' | 'COLLECTED';
  created_at: string;
};

export type Collection = {
  id: string;
  sale_receivable_id: string;
  collection_minor_units: string;
  currency: string;
  collected_on: string;
  created_at: string;
};

export type ProjectRealizedResult = {
  project_id: string;
  currency: string;
  recognized_revenue_minor_units: string;
  derecognized_carrying_cost_minor_units: string;
  selling_costs_minor_units: string;
  realized_result_minor_units: string;
  collected_cash_minor_units: string;
  outstanding_receivable_minor_units: string;
};

export type ProjectLatestValuation = {
  project_id: string;
  valuation_id: string;
  effective_date: string;
  valuer_source: string;
  method: string;
  valuation_minor_units: string;
  currency: string;
  confidence: string | null;
  approved_at: string | null;
};

export async function getDispositions(projectId: string): Promise<Disposition[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('dispositions_read')
    .select('id,project_id,property_asset_id,buyer_party_id,status,agreed_proceeds_minor_units,currency,agreement_date,control_transfer_date,selling_costs_minor_units,contract_reference,recognized_at,created_at')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as Disposition[];
}

export async function getDisposition(dispositionId: string): Promise<Disposition | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('dispositions_read')
    .select('id,project_id,property_asset_id,buyer_party_id,status,agreed_proceeds_minor_units,currency,agreement_date,control_transfer_date,selling_costs_minor_units,contract_reference,recognized_at,created_at')
    .eq('id', dispositionId)
    .maybeSingle();
  if (error) throw error;
  return data as Disposition | null;
}

export async function getSaleRecognitions(projectId: string): Promise<SaleRecognition[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('sale_recognitions_read')
    .select('id,disposition_id,recognized_revenue_minor_units,derecognized_carrying_cost_minor_units,selling_costs_minor_units,realized_result_minor_units,currency,control_transfer_date,recognized_at')
    .eq('project_id', projectId)
    .order('recognized_at', { ascending: false });
  if (error) throw error;
  return data as SaleRecognition[];
}

export async function getSaleReceivables(projectId: string): Promise<SaleReceivable[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('sale_receivables_read')
    .select('id,sale_recognition_id,receivable_minor_units,currency,status,created_at')
    .eq('project_id', projectId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data as SaleReceivable[];
}

export async function getCollections(saleReceivableId: string): Promise<Collection[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('collections_read')
    .select('id,sale_receivable_id,collection_minor_units,currency,collected_on,created_at')
    .eq('sale_receivable_id', saleReceivableId)
    .order('collected_on', { ascending: false });
  if (error) throw error;
  return data as Collection[];
}

export async function getProjectRealizedResult(projectId: string): Promise<ProjectRealizedResult | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_realized_result')
    .select('project_id,currency,recognized_revenue_minor_units,derecognized_carrying_cost_minor_units,selling_costs_minor_units,realized_result_minor_units,collected_cash_minor_units,outstanding_receivable_minor_units')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throw error;
  return data as ProjectRealizedResult | null;
}

export async function getProjectLatestValuation(projectId: string): Promise<ProjectLatestValuation | null> {
  const s = await createClient();
  const { data, error } = await s
    .from('project_latest_valuation')
    .select('project_id,valuation_id,effective_date,valuer_source,method,valuation_minor_units,currency,confidence,approved_at')
    .eq('project_id', projectId)
    .maybeSingle();
  if (error) throw error;
  return data as ProjectLatestValuation | null;
}

export type FinancialAccount = {
  id: string;
  semantic_role: string;
  display_name: string;
  currency: string;
};

export async function getFinancialAccounts(organizationId: string): Promise<FinancialAccount[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('financial_accounts')
    .select('id,semantic_role,display_name,currency')
    .eq('organization_id', organizationId)
    .eq('is_active', true)
    .order('display_name');
  if (error) throw error;
  return data as FinancialAccount[];
}

export async function getCashAccounts(organizationId: string, currency: string): Promise<FinancialAccount[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('financial_accounts')
    .select('id,semantic_role,display_name,currency')
    .eq('organization_id', organizationId)
    .eq('currency', currency)
    .eq('is_active', true)
    .eq('semantic_role', 'cash')
    .order('display_name');
  if (error) throw error;
  return data as FinancialAccount[];
}
