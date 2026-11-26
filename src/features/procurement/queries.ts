// R4 Procurement read models. Quantities and all integer minor-unit amounts are
// text-cast by PostgreSQL for exact transport through PostgREST/JavaScript.

import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type ProcurementSupplierRead = {
  id: string;
  organization_id: string;
  name: string;
  tax_number: string | null;
  payment_terms: string | null;
  notes: string | null;
  status: 'ACTIVE' | 'INACTIVE';
  created_by: string;
  created_at: string;
  party_id: string | null;
  party_name: string | null;
};

export type PurchaseRequestRead = {
  id: string; organization_id: string; project_id: string; internal_reference: string;
  description: string | null; status: 'DRAFT' | 'SUBMITTED' | 'APPROVED' | 'REJECTED';
  requested_by: string; submitted_by: string | null; submitted_at: string | null;
  approved_by: string | null; approved_at: string | null; rejection_reason: string | null;
  created_at: string; line_count: number;
};

export type PurchaseRequestLineRead = {
  id: string; organization_id: string; project_id: string; purchase_request_id: string;
  item_description: string; quantity: string; unit: string; notes: string | null; created_at: string;
};

export type PurchaseOrderRead = {
  id: string; organization_id: string; project_id: string; internal_reference: string;
  supplier_id: string | null; supplier_name: string | null; source_purchase_request_id: string | null;
  description: string | null; status: 'DRAFT' | 'SUBMITTED' | 'APPROVED' | 'REJECTED' | 'CANCELLED';
  expected_delivery_date: string | null; requested_by: string; submitted_by: string | null;
  submitted_at: string | null; approved_by: string | null; approved_at: string | null;
  rejection_reason: string | null; created_at: string; line_count: number;
  currency: string | null; commercial_reference: string | null; commercial_total_minor_units: string;
};

export type PurchaseOrderLineRead = {
  id: string; organization_id: string; project_id: string; purchase_order_id: string;
  item_description: string; quantity: string; unit: string; notes: string | null; created_at: string;
  unit_price_minor_units: string | null; line_amount_minor_units: string | null; currency: string | null;
};

export type PurchaseReceiptRead = {
  id: string; organization_id: string; project_id: string; purchase_order_id: string;
  purchase_order_reference: string; supplier_name: string | null; received_at: string;
  evidence_reference: string; notes: string | null; received_by: string; created_at: string; line_count: number;
};

export type PurchaseReceiptLineRead = {
  id: string; organization_id: string; project_id: string; purchase_receipt_id: string;
  purchase_order_line_id: string; item_description: string; quantity_received: string;
  unit: string; notes: string | null; created_at: string;
};

export type PurchaseOrderLineReceivingRead = {
  purchase_order_line_id: string; organization_id: string; project_id: string; purchase_order_id: string;
  item_description: string; unit: string; ordered_quantity: string; received_quantity: string;
  remaining_quantity: string; unit_price_minor_units: string | null;
  ordered_amount_minor_units: string | null; currency: string | null;
};

export type PurchaseReceiptInvoiceBasisRead = {
  purchase_receipt_line_id: string; organization_id: string; project_id: string;
  purchase_order_id: string; purchase_order_line_id: string; purchase_receipt_id: string;
  item_description: string; unit: string; received_quantity: string;
  approved_invoiced_quantity: string; available_to_invoice_quantity: string;
  unit_price_minor_units: string; currency: string; receipt_evidence_reference: string;
};

export type SupplierInvoiceRead = {
  id: string; organization_id: string; project_id: string; purchase_order_id: string;
  purchase_order_reference: string; supplier_id: string; supplier_name: string; party_id: string;
  invoice_reference: string; invoice_date: string; currency: string;
  cost_treatment: 'EXPENSE' | 'CAPITALIZABLE_WIP'; evidence_reference: string;
  notes: string | null; status: 'SUBMITTED' | 'APPROVED'; recorded_by: string; recorded_at: string;
  approved_by: string | null; approved_at: string | null; cost_obligation_id: string | null;
  authorization_batch_id: string | null; invoice_total_minor_units: string;
  paid_minor_units: string; outstanding_minor_units: string; reconciled_minor_units: string;
  payable_is_reversed: boolean;
  payment_state: 'PAYABLE_REVERSED' | 'UNPAID' | 'PARTIALLY_PAID' | 'FULLY_PAID';
  reconciliation_state: 'NOT_PAID' | 'PAID_UNRECONCILED' | 'PARTIALLY_RECONCILED' | 'RECONCILED';
  payment_count: number;
};

export type SupplierInvoiceLineRead = {
  id: string; organization_id: string; project_id: string; supplier_invoice_id: string;
  purchase_order_id: string; purchase_order_line_id: string; purchase_receipt_line_id: string;
  item_description: string; unit: string; quantity_invoiced: string;
  unit_price_minor_units: string; line_amount_minor_units: string; currency: string;
};

export type ProcurementEvidenceRead = {
  evidence_link_id: string; organization_id: string; project_id: string; document_id: string;
  evidence_version_id: string; classification: 'CONTRACT' | 'PURCHASE_ORDER' | 'RECEIPT' | 'SUPPLIER_INVOICE';
  title: string; version_number: number; original_filename: string; mime_type: string;
  size_bytes: string; sha256: string; storage_bucket: string; storage_object_name: string;
  uploaded_by: string; uploaded_at: string; purchase_order_id: string | null;
  purchase_receipt_id: string | null; supplier_invoice_id: string | null;
  linked_by: string; linked_at: string; download_url: string | null;
};

export type ProcurementCommitmentRead = {
  purchase_order_id: string; organization_id: string; project_id: string; supplier_id: string;
  party_id: string; internal_reference: string; committed_at: string; currency: string;
  committed_minor_units: string; invoiced_minor_units: string; remaining_commitment_minor_units: string;
  accounting_effect: 'UNPOSTED_PURCHASE_COMMITMENT';
};

async function many<T>(
  view: string,
  columns: string,
  orgOrProject: { organizationId?: string; projectId?: string; purchaseOrderId?: string },
  orderColumn: string,
): Promise<T[]> {
  const s = await createClient();
  let query = s.from(view).select(columns);
  if (orgOrProject.projectId) query = query.eq('project_id', orgOrProject.projectId);
  if (orgOrProject.organizationId) query = query.eq('organization_id', orgOrProject.organizationId);
  if (orgOrProject.purchaseOrderId) query = query.eq('purchase_order_id', orgOrProject.purchaseOrderId);
  const { data, error } = await query.order(orderColumn, { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as T[];
}

export const getSuppliers = (organizationId: string) => many<ProcurementSupplierRead>(
  'procurement_suppliers_read',
  'id,organization_id,name,tax_number,payment_terms,notes,status,created_by,created_at,party_id,party_name',
  { organizationId }, 'created_at',
);
export const getPurchaseRequests = (projectId: string) => many<PurchaseRequestRead>(
  'purchase_requests_read',
  'id,organization_id,project_id,internal_reference,description,status,requested_by,submitted_by,submitted_at,approved_by,approved_at,rejection_reason,created_at,line_count',
  { projectId }, 'created_at',
);
export const getPurchaseRequestLines = (projectId: string) => many<PurchaseRequestLineRead>(
  'purchase_request_lines_read',
  'id,organization_id,project_id,purchase_request_id,item_description,quantity,unit,notes,created_at',
  { projectId }, 'created_at',
);
export const getPurchaseOrders = (projectId: string) => many<PurchaseOrderRead>(
  'purchase_orders_read',
  'id,organization_id,project_id,internal_reference,supplier_id,supplier_name,source_purchase_request_id,description,status,expected_delivery_date,requested_by,submitted_by,submitted_at,approved_by,approved_at,rejection_reason,created_at,line_count,currency,commercial_reference,commercial_total_minor_units',
  { projectId }, 'created_at',
);
export const getPurchaseOrderLines = (projectId: string) => many<PurchaseOrderLineRead>(
  'purchase_order_lines_read',
  'id,organization_id,project_id,purchase_order_id,item_description,quantity,unit,notes,created_at,unit_price_minor_units,line_amount_minor_units,currency',
  { projectId }, 'created_at',
);
export const getPurchaseReceipts = (projectId: string) => many<PurchaseReceiptRead>(
  'purchase_receipts_read',
  'id,organization_id,project_id,purchase_order_id,purchase_order_reference,supplier_name,received_at,evidence_reference,notes,received_by,created_at,line_count',
  { projectId }, 'received_at',
);
export const getPurchaseReceiptLines = (projectId: string) => many<PurchaseReceiptLineRead>(
  'purchase_receipt_lines_read',
  'id,organization_id,project_id,purchase_receipt_id,purchase_order_line_id,item_description,quantity_received,unit,notes,created_at',
  { projectId }, 'created_at',
);
export const getPurchaseOrderLinesReceiving = (projectId: string) => many<PurchaseOrderLineReceivingRead>(
  'purchase_order_lines_receiving_read',
  'purchase_order_line_id,organization_id,project_id,purchase_order_id,item_description,unit,ordered_quantity,received_quantity,remaining_quantity,unit_price_minor_units,ordered_amount_minor_units,currency',
  { projectId }, 'item_description',
);
export const getPurchaseReceiptInvoiceBasis = (projectId: string) => many<PurchaseReceiptInvoiceBasisRead>(
  'purchase_receipt_invoice_basis_read',
  'purchase_receipt_line_id,organization_id,project_id,purchase_order_id,purchase_order_line_id,purchase_receipt_id,item_description,unit,received_quantity,approved_invoiced_quantity,available_to_invoice_quantity,unit_price_minor_units,currency,receipt_evidence_reference',
  { projectId }, 'purchase_receipt_line_id',
);
const SUPPLIER_INVOICE_COLUMNS =
  'id,organization_id,project_id,purchase_order_id,purchase_order_reference,supplier_id,supplier_name,party_id,invoice_reference,invoice_date,currency,cost_treatment,evidence_reference,notes,status,recorded_by,recorded_at,approved_by,approved_at,cost_obligation_id,authorization_batch_id,invoice_total_minor_units,paid_minor_units,outstanding_minor_units,reconciled_minor_units,payable_is_reversed,payment_state,reconciliation_state,payment_count';
export const getSupplierInvoices = (projectId: string) => many<SupplierInvoiceRead>(
  'supplier_invoices_read',
  SUPPLIER_INVOICE_COLUMNS,
  { projectId }, 'recorded_at',
);
export const getSupplierInvoiceLines = (projectId: string) => many<SupplierInvoiceLineRead>(
  'supplier_invoice_lines_read',
  'id,organization_id,project_id,supplier_invoice_id,purchase_order_id,purchase_order_line_id,purchase_receipt_line_id,item_description,unit,quantity_invoiced,unit_price_minor_units,line_amount_minor_units,currency',
  { projectId }, 'id',
);
export const getProcurementCommitments = (projectId: string) => many<ProcurementCommitmentRead>(
  'project_procurement_commitments_read',
  'purchase_order_id,organization_id,project_id,supplier_id,party_id,internal_reference,committed_at,currency,committed_minor_units,invoiced_minor_units,remaining_commitment_minor_units,accounting_effect',
  { projectId }, 'committed_at',
);

export async function getProcurementEvidence(projectId: string): Promise<ProcurementEvidenceRead[]> {
  const rows = await many<Omit<ProcurementEvidenceRead, 'download_url'>>(
    'procurement_evidence_read',
    'evidence_link_id,organization_id,project_id,document_id,evidence_version_id,classification,title,version_number,original_filename,mime_type,size_bytes,sha256,storage_bucket,storage_object_name,uploaded_by,uploaded_at,purchase_order_id,purchase_receipt_id,supplier_invoice_id,linked_by,linked_at',
    { projectId }, 'uploaded_at',
  );
  if (rows.length === 0) return [];
  const supabase = await createClient();
  const { data, error } = await supabase.storage.from('procurement-evidence')
    .createSignedUrls(rows.map((row) => row.storage_object_name), 300);
  if (error) throwOperatorQuery(error);
  return rows.map((row, index) => ({ ...row, download_url: data?.[index]?.signedUrl ?? null }));
}

/** Supplier invoices across every project of the organization (read-only list). */
export const getOrganizationSupplierInvoices = (organizationId: string) => many<SupplierInvoiceRead>(
  'supplier_invoices_read',
  SUPPLIER_INVOICE_COLUMNS,
  { organizationId }, 'invoice_date',
);
