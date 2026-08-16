import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

/**
 * R8 — Cross-Sector Asset & Performance Layer (read side).
 *
 * These are reads over two read-only projections. There is no companion
 * `actions.ts` or `rpc.ts` in this feature, and that absence is deliberate:
 * the canonical domain model (docs/greenfield/03_DOMAIN_MODEL.md:64 and
 * :175) states that sector tables connect through investment_project_id and
 * their own roots, and do not share one universal asset table. R8 therefore
 * unifies reporting, not ownership — every fact shown here is still written
 * and owned by its sector slice.
 *
 * Money arrives as text (exact bigint minor units) and stays text until
 * formatMinorUnits renders it. Nothing here does arithmetic on money.
 */

export type AssetKind =
  | 'PROPERTY_ASSET'
  | 'AGRICULTURAL_LAND_ASSET'
  | 'FARM'
  | 'LIVESTOCK_SITE';

export type RegisteredAsset = {
  organization_id: string;
  project_id: string;
  project_name: string;
  project_sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';
  project_currency: string;
  portfolio_id: string | null;
  portfolio_name: string | null;
  asset_kind: AssetKind;
  asset_id: string;
  asset_name: string;
  asset_reference: string | null;
  asset_classification: string | null;
  operational_state: string | null;
  operational_state_basis: string;
  acquisition_cost_minor_units: string | null;
  acquisition_cost_currency: string | null;
  acquisition_cost_status: string;
  latest_approved_valuation_minor_units: string | null;
  latest_approved_valuation_currency: string | null;
  latest_approved_valuation_date: string | null;
  latest_approved_valuation_status: string;
  realized_result_minor_units: string | null;
  realized_result_currency: string | null;
  realized_result_status: string;
  registered_by: string | null;
  registered_at: string;
};

export type SectorPerformance = {
  organization_id: string;
  sector: 'REAL_ESTATE' | 'AGRICULTURE' | 'LIVESTOCK';
  currency: string;
  org_reporting_currency: string | null;
  project_count: number;
  asset_count: number;
  fx_status: string;
  fx_rate_snapshot_id: string | null;
  fx_rate_date: string | null;
  cash_balance_minor_units: string;
  revenue_recognized_minor_units: string;
  cost_of_sale_minor_units: string;
  expense_posted_minor_units: string;
  wip_posted_minor_units: string;
  contributions_received_minor_units: string;
  receivable_open_minor_units: string;
  payable_open_minor_units: string;
  realized_result_minor_units: string;
  converted_cash_balance_minor_units: string | null;
  converted_revenue_recognized_minor_units: string | null;
  converted_contributions_received_minor_units: string | null;
  converted_realized_result_minor_units: string | null;
};

const REGISTER_COLUMNS =
  'organization_id,project_id,project_name,project_sector,project_currency,' +
  'portfolio_id,portfolio_name,asset_kind,asset_id,asset_name,asset_reference,' +
  'asset_classification,operational_state,operational_state_basis,' +
  'acquisition_cost_minor_units,acquisition_cost_currency,acquisition_cost_status,' +
  'latest_approved_valuation_minor_units,latest_approved_valuation_currency,' +
  'latest_approved_valuation_date,latest_approved_valuation_status,' +
  'realized_result_minor_units,realized_result_currency,realized_result_status,' +
  'registered_by,registered_at';

const PERFORMANCE_COLUMNS =
  'organization_id,sector,currency,org_reporting_currency,project_count,asset_count,' +
  'fx_status,fx_rate_snapshot_id,fx_rate_date,cash_balance_minor_units,' +
  'revenue_recognized_minor_units,cost_of_sale_minor_units,expense_posted_minor_units,' +
  'wip_posted_minor_units,contributions_received_minor_units,receivable_open_minor_units,' +
  'payable_open_minor_units,realized_result_minor_units,' +
  'converted_cash_balance_minor_units,converted_revenue_recognized_minor_units,' +
  'converted_contributions_received_minor_units,converted_realized_result_minor_units';

export async function getRegisteredAssets(
  organizationId: string,
): Promise<RegisteredAsset[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('cross_sector_asset_register_read')
    .select(REGISTER_COLUMNS)
    .eq('organization_id', organizationId)
    .order('registered_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as RegisteredAsset[];
}

export async function getSectorPerformance(
  organizationId: string,
): Promise<SectorPerformance[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('sector_performance_read')
    .select(PERFORMANCE_COLUMNS)
    .eq('organization_id', organizationId)
    .order('sector');
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as SectorPerformance[];
}
