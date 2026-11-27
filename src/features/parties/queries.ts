import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';
import type { ObligationUsage, ParticipantUsage, PartyBase } from './directory';

/** All parties of the organization. RLS: parties_read (org members). */
export async function getParties(organizationId: string): Promise<PartyBase[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('parties')
    .select('id,legal_name,party_type,created_at')
    .eq('organization_id', organizationId)
    .order('legal_name', { ascending: true });
  if (error) throwOperatorQuery(error);
  return (data ?? []) as PartyBase[];
}

/** Investor usage: one row per (party, project) participation. */
export async function getParticipantUsage(organizationId: string): Promise<ParticipantUsage[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('project_participants')
    .select('party_id,project_id')
    .eq('organization_id', organizationId);
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ParticipantUsage[];
}

/** Supplier usage: obligations per party from the existing position read model. */
export async function getObligationUsage(organizationId: string): Promise<ObligationUsage[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('cost_obligation_position_read')
    .select('party_id,currency,outstanding_minor_units,is_posted')
    .eq('organization_id', organizationId);
  if (error) throwOperatorQuery(error);
  return (data ?? []) as ObligationUsage[];
}

/** Customer usage: open (unsettled, not reversed) customer invoices per party. */
export async function getCustomerInvoiceUsage(organizationId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('customer_invoices_read')
    .select('customer_party_id,outstanding_minor_units,is_reversed')
    .eq('organization_id', organizationId);
  if (error) throwOperatorQuery(error);
  return (data ?? []) as import('./directory').CustomerInvoiceUsage[];
}
