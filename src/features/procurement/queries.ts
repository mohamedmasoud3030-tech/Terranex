// GF-025 / R4 — Procurement Foundation: read models.
//
// These match the security_invoker read views exposed by migration
// 20260815030000. Suppliers are organization-scoped; requests/orders and
// their lines are project-scoped. Quantities are text-cast numeric for safe
// transport. No financial amounts in this slice.

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
};

export type PurchaseRequestRead = {
  id: string;
  organization_id: string;
  project_id: string;
  internal_reference: string;
  description: string | null;
  status: 'DRAFT' | 'SUBMITTED' | 'APPROVED' | 'REJECTED';
  requested_by: string;
  submitted_by: string | null;
  submitted_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  rejection_reason: string | null;
  created_at: string;
  line_count: number;
};

export type PurchaseRequestLineRead = {
  id: string;
  organization_id: string;
  project_id: string;
  purchase_request_id: string;
  item_description: string;
  quantity: string;
  unit: string;
  notes: string | null;
  created_at: string;
};

export type PurchaseOrderRead = {
  id: string;
  organization_id: string;
  project_id: string;
  internal_reference: string;
  supplier_id: string | null;
  supplier_name: string | null;
  source_purchase_request_id: string | null;
  description: string | null;
  status: 'DRAFT' | 'SUBMITTED' | 'APPROVED' | 'REJECTED' | 'CANCELLED';
  expected_delivery_date: string | null;
  requested_by: string;
  submitted_by: string | null;
  submitted_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  rejection_reason: string | null;
  created_at: string;
  line_count: number;
};

export type PurchaseOrderLineRead = {
  id: string;
  organization_id: string;
  project_id: string;
  purchase_order_id: string;
  item_description: string;
  quantity: string;
  unit: string;
  notes: string | null;
  created_at: string;
};

async function many<T>(
  view: string,
  columns: string,
  orgOrProject: { organizationId?: string; projectId?: string },
  orderColumn: string,
): Promise<T[]> {
  const s = await createClient();
  let query = s.from(view).select(columns);
  if (orgOrProject.projectId) query = query.eq('project_id', orgOrProject.projectId);
  if (orgOrProject.organizationId) query = query.eq('organization_id', orgOrProject.organizationId);
  const { data, error } = await query.order(orderColumn, { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as unknown as T[];
}

export const getSuppliers = (organizationId: string) =>
  many<ProcurementSupplierRead>(
    'procurement_suppliers_read',
    'id,organization_id,name,tax_number,payment_terms,notes,status,created_by,created_at',
    { organizationId },
    'created_at',
  );

export const getPurchaseRequests = (projectId: string) =>
  many<PurchaseRequestRead>(
    'purchase_requests_read',
    'id,organization_id,project_id,internal_reference,description,status,requested_by,submitted_by,submitted_at,approved_by,approved_at,rejection_reason,created_at,line_count',
    { projectId },
    'created_at',
  );

export const getPurchaseRequestLines = (projectId: string) =>
  many<PurchaseRequestLineRead>(
    'purchase_request_lines_read',
    'id,organization_id,project_id,purchase_request_id,item_description,quantity,unit,notes,created_at',
    { projectId },
    'created_at',
  );

export const getPurchaseOrders = (projectId: string) =>
  many<PurchaseOrderRead>(
    'purchase_orders_read',
    'id,organization_id,project_id,internal_reference,supplier_id,supplier_name,source_purchase_request_id,description,status,expected_delivery_date,requested_by,submitted_by,submitted_at,approved_by,approved_at,rejection_reason,created_at,line_count',
    { projectId },
    'created_at',
  );

export const getPurchaseOrderLines = (projectId: string) =>
  many<PurchaseOrderLineRead>(
    'purchase_order_lines_read',
    'id,organization_id,project_id,purchase_order_id,item_description,quantity,unit,notes,created_at',
    { projectId },
    'created_at',
  );

// ---------------------------------------------------------------------------
// GF-026 — Receiving read models.
// ---------------------------------------------------------------------------
export type PurchaseReceiptRead = {
  id: string;
  organization_id: string;
  project_id: string;
  purchase_order_id: string;
  purchase_order_reference: string;
  supplier_name: string | null;
  received_at: string;
  evidence_reference: string;
  notes: string | null;
  received_by: string;
  created_at: string;
  line_count: number;
};

export type PurchaseReceiptLineRead = {
  id: string;
  organization_id: string;
  project_id: string;
  purchase_receipt_id: string;
  purchase_order_line_id: string;
  item_description: string;
  quantity_received: string;
  unit: string;
  notes: string | null;
  created_at: string;
};

export type PurchaseOrderLineReceivingRead = {
  purchase_order_line_id: string;
  organization_id: string;
  project_id: string;
  purchase_order_id: string;
  item_description: string;
  unit: string;
  ordered_quantity: string;
  received_quantity: string;
  remaining_quantity: string;
};

export const getPurchaseReceipts = (projectId: string) =>
  many<PurchaseReceiptRead>(
    'purchase_receipts_read',
    'id,organization_id,project_id,purchase_order_id,purchase_order_reference,supplier_name,received_at,evidence_reference,notes,received_by,created_at,line_count',
    { projectId },
    'received_at',
  );

export const getPurchaseReceiptLines = (projectId: string) =>
  many<PurchaseReceiptLineRead>(
    'purchase_receipt_lines_read',
    'id,organization_id,project_id,purchase_receipt_id,purchase_order_line_id,item_description,quantity_received,unit,notes,created_at',
    { projectId },
    'created_at',
  );

export const getPurchaseOrderLinesReceiving = (projectId: string) =>
  many<PurchaseOrderLineReceivingRead>(
    'purchase_order_lines_receiving_read',
    'purchase_order_line_id,organization_id,project_id,purchase_order_id,item_description,unit,ordered_quantity,received_quantity,remaining_quantity',
    { projectId },
    'item_description',
  );
