import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type CustomerInvoice = {
  invoice_id: string;
  organization_id: string;
  project_id: string;
  customer_party_id: string;
  customer_name: string;
  invoice_reference: string;
  description: string | null;
  invoice_date: string;
  currency: string;
  amount_minor_units: string;
  evidence_reference: string;
  journal_batch_id: string;
  issued_by: string;
  issued_at: string;
  is_reversed: boolean;
  collected_minor_units: string;
  outstanding_minor_units: string;
};

export type CustomerInvoiceCollection = {
  collection_id: string;
  organization_id: string;
  project_id: string;
  invoice_id: string;
  cash_account_id: string;
  amount_minor_units: string;
  currency: string;
  collection_date: string;
  evidence_reference: string;
  journal_batch_id: string;
  collected_by: string;
  collected_at: string;
  is_reversed: boolean;
};

export async function getCustomerInvoices(organizationId: string): Promise<CustomerInvoice[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('customer_invoices_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('invoice_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as CustomerInvoice[];
}

export async function getCustomerInvoiceCollections(
  organizationId: string,
): Promise<CustomerInvoiceCollection[]> {
  const s = await createClient();
  const { data, error } = await s
    .from('customer_invoice_collections_read')
    .select('*')
    .eq('organization_id', organizationId)
    .order('collection_date', { ascending: false });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as CustomerInvoiceCollection[];
}
