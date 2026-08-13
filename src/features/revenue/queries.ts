import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type PropertyDisposition = {
  disposition_id:string; organization_id:string; project_id:string; property_asset_id:string; buyer_party_id:string;
  agreement_reference:string; agreement_evidence_reference:string; agreed_proceeds_minor_units:string; currency:string;
  agreement_date:string; expected_control_transfer_date:string|null; status:'DRAFT'|'APPROVED'|'CONTROL_TRANSFERRED';
  prepared_by:string; prepared_at:string; approved_by:string|null; approved_at:string|null;
  control_transfer_date:string|null; control_transfer_evidence_reference:string|null;
  control_transferred_by:string|null; control_transferred_at:string|null;
  recognition_id:string|null; recognition_date:string|null; recognition_batch_id:string|null;
  recognized_revenue_minor_units:string|null; carrying_cost_minor_units:string|null;
  collected_minor_units:string; outstanding_receivable_minor_units:string;
};

export type SaleCollection = {
  collection_id:string; organization_id:string; project_id:string; recognition_id:string; disposition_id:string;
  cash_account_id:string; amount_minor_units:string; currency:string; collection_date:string;
  evidence_reference:string; journal_batch_id:string; collected_by:string; collected_at:string;
  is_reconciled:boolean; reconciliation_id:string|null; statement_line_id:string|null; matched_at:string|null;
};

export type RealizedResult = {
  organization_id:string; project_id:string; property_asset_id:string; disposition_id:string; recognition_id:string;
  buyer_party_id:string; currency:string; recognition_date:string; recognition_batch_id:string;
  recognized_revenue_minor_units:string; carrying_cost_derecognized_minor_units:string;
  selling_costs_minor_units:string; realized_result_minor_units:string;
  collected_cash_minor_units:string; outstanding_receivable_minor_units:string;
  latest_management_valuation_id:string|null; latest_management_valuation_minor_units:string|null;
  latest_management_valuation_date:string|null; latest_management_valuation_source:string|null;
  latest_management_valuation_method:string|null; latest_management_valuation_evidence_reference:string|null;
};

export type RealizedResultDrilldown = {
  organization_id:string; project_id:string; property_asset_id:string; disposition_id:string;
  fact_type:'SALE_RECOGNITION'|'CARRYING_COST_DERECOGNITION'|'CARRYING_COST_SOURCE'|'COLLECTION'|'SELLING_COST';
  source_entity_id:string; journal_batch_id:string; journal_line_id:string; account_role:string;
  debit_minor_units:string; credit_minor_units:string; currency:string; transaction_date:string;
  evidence_reference:string;
};

export type PositiveStatementLine = {
  line_id:string; project_id:string; cash_account_id:string; transaction_date:string;
  amount_minor_units:string; currency:string; description:string; provider_reference:string|null;
  is_reconciled:boolean;
};

async function many<T>(table:string,columns:string,projectId:string,orderColumn?:string):Promise<T[]> {
  const s=await createClient();
  let query=s.from(table).select(columns).eq('project_id',projectId);
  if(orderColumn) query=query.order(orderColumn,{ascending:false});
  const {data,error}=await query;
  if(error) throwOperatorQuery(error);
  return data as unknown as T[];
}

export const getPropertyDispositions=(projectId:string)=>many<PropertyDisposition>(
  'property_dispositions_read',
  'disposition_id,organization_id,project_id,property_asset_id,buyer_party_id,agreement_reference,agreement_evidence_reference,agreed_proceeds_minor_units,currency,agreement_date,expected_control_transfer_date,status,prepared_by,prepared_at,approved_by,approved_at,control_transfer_date,control_transfer_evidence_reference,control_transferred_by,control_transferred_at,recognition_id,recognition_date,recognition_batch_id,recognized_revenue_minor_units,carrying_cost_minor_units,collected_minor_units,outstanding_receivable_minor_units',
  projectId,'prepared_at',
);

export const getSaleCollections=(projectId:string)=>many<SaleCollection>(
  'property_sale_collections_read',
  'collection_id,organization_id,project_id,recognition_id,disposition_id,cash_account_id,amount_minor_units,currency,collection_date,evidence_reference,journal_batch_id,collected_by,collected_at,is_reconciled,reconciliation_id,statement_line_id,matched_at',
  projectId,'collected_at',
);

export const getRealizedResults=(projectId:string)=>many<RealizedResult>(
  'property_realized_result_read',
  'organization_id,project_id,property_asset_id,disposition_id,recognition_id,buyer_party_id,currency,recognition_date,recognition_batch_id,recognized_revenue_minor_units,carrying_cost_derecognized_minor_units,selling_costs_minor_units,realized_result_minor_units,collected_cash_minor_units,outstanding_receivable_minor_units,latest_management_valuation_id,latest_management_valuation_minor_units,latest_management_valuation_date,latest_management_valuation_source,latest_management_valuation_method,latest_management_valuation_evidence_reference',
  projectId,'recognition_date',
);

export const getRealizedResultDrilldown=(projectId:string)=>many<RealizedResultDrilldown>(
  'property_realized_result_drilldown_read',
  'organization_id,project_id,property_asset_id,disposition_id,fact_type,source_entity_id,journal_batch_id,journal_line_id,account_role,debit_minor_units,credit_minor_units,currency,transaction_date,evidence_reference',
  projectId,'transaction_date',
);

export async function getUnreconciledPositiveStatementLines(projectId:string):Promise<PositiveStatementLine[]> {
  const s=await createClient();
  const {data,error}=await s.from('bank_statement_line_status_read')
    .select('line_id,project_id,cash_account_id,transaction_date,amount_minor_units,currency,description,provider_reference,is_reconciled')
    .eq('project_id',projectId).eq('is_reconciled',false).order('transaction_date',{ascending:false});
  if(error) throwOperatorQuery(error);
  return (data as PositiveStatementLine[]).filter((line)=>BigInt(line.amount_minor_units)>0n);
}
