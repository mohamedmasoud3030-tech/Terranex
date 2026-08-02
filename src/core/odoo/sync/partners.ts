/**
 * Partner sync: Terranex Partner ↔ Odoo res.partner
 *
 * - Equity partners → res.partner with is_company = true (or individual depending on type)
 * - Counterparty suppliers → res.partner with supplier_rank = 1
 * - Counterparty clients    → res.partner with customer_rank = 1
 *
 * The sync is idempotent: if a Partner already carries an `odoo_res_id`, we
 * update the Odoo record rather than creating a duplicate.
 */
import type { Partner } from '../../types/domain';
import type { OdooClient } from '../client';

const DEFAULT_COMPANY_VAT = ''; // populate from company settings later

function mapPartnerToOdoo(partner: Partner, companyLang = 'ar_AR') {
  const isEquity = partner.category === 'equity_partner';
  const isClient = partner.counterparty_role === 'client';
  const isSupplier = partner.counterparty_role === 'supplier' || partner.counterparty_role === 'service_provider';
  return {
    name: partner.name_ar,
    // Odoo supports a single display name — keep Arabic primary, English in comment
    comment: [
      partner.name_en ? `EN: ${partner.name_en}` : '',
      partner.notes || '',
    ].filter(Boolean).join('\n'),
    lang: companyLang,
    customer_rank: isClient || isEquity ? 1 : 0,
    supplier_rank: isSupplier ? 1 : 0,
    is_company: isEquity,
    phone: partner.phone || false,
    email: partner.email || false,
    street: partner.address || false,
    vat: DEFAULT_COMPANY_VAT,
    ref: partner.id, // store Terranex id for cross-reference
  };
}

export async function syncPartner(
  client: OdooClient,
  partner: Partner,
): Promise<{ odooId: number; created: boolean }> {
  const existing = (partner as unknown as { odoo_res_id?: number }).odoo_res_id;
  const values = mapPartnerToOdoo(partner);
  if (existing) {
    await client.write('res.partner', [existing], values);
    return { odooId: existing, created: false };
  }
  const odooId = await client.create('res.partner', values);
  return { odooId, created: true };
}
