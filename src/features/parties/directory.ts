// Party directory — one read model answering "who do we deal with, and as
// what?" across the organization.
//
// Concept ported from Kiyyal's directory read model (one row per party with
// its relationship facts attached), rebuilt to Terranex contracts: parties
// are org-scoped master data with RLS read access, and usage facts come from
// existing read models — never recomputed finance.
//
// A party is only ever *created* inside the flow that needs it (investor on
// the investors page, supplier on procurement, customer on invoices). The
// directory is the read side of that rule, so it adds no second create path.

export interface PartyBase {
  readonly id: string;
  readonly legal_name: string;
  readonly party_type: 'PERSON' | 'ORGANIZATION';
  readonly created_at: string;
}

export interface ParticipantUsage {
  readonly party_id: string;
  readonly project_id: string;
}

export interface ObligationUsage {
  readonly party_id: string;
  readonly currency: string;
  readonly outstanding_minor_units: string;
  readonly is_posted: boolean;
}

export interface CustomerInvoiceUsage {
  readonly customer_party_id: string;
  readonly outstanding_minor_units: string;
  readonly is_reversed: boolean;
}

export interface PartyDirectoryRow {
  readonly id: string;
  readonly legalName: string;
  readonly partyType: 'PERSON' | 'ORGANIZATION';
  readonly investorProjectCount: number;
  readonly openObligationCount: number;
  readonly openCustomerInvoiceCount: number;
  /** Outstanding supplier balance per currency; a party can be owed in two. */
  readonly outstandingByCurrency: Readonly<Record<string, string>>;
}

export function buildPartyDirectory(
  parties: readonly PartyBase[],
  participants: readonly ParticipantUsage[],
  obligations: readonly ObligationUsage[],
  customerInvoices: readonly CustomerInvoiceUsage[] = [],
): PartyDirectoryRow[] {
  const investorProjects = new Map<string, Set<string>>();
  for (const participant of participants) {
    const set = investorProjects.get(participant.party_id) ?? new Set<string>();
    set.add(participant.project_id);
    investorProjects.set(participant.party_id, set);
  }
  const supplierOpen = new Map<string, { count: number; byCurrency: Map<string, bigint> }>();
  for (const obligation of obligations) {
    if (!obligation.is_posted) continue;
    const outstanding = BigInt(obligation.outstanding_minor_units);
    if (outstanding <= 0n) continue;
    const entry = supplierOpen.get(obligation.party_id) ?? { count: 0, byCurrency: new Map<string, bigint>() };
    entry.count += 1;
    entry.byCurrency.set(obligation.currency, (entry.byCurrency.get(obligation.currency) ?? 0n) + outstanding);
    supplierOpen.set(obligation.party_id, entry);
  }
  const customerOpen = new Map<string, number>();
  for (const invoice of customerInvoices) {
    if (invoice.is_reversed || BigInt(invoice.outstanding_minor_units) <= 0n) continue;
    customerOpen.set(invoice.customer_party_id, (customerOpen.get(invoice.customer_party_id) ?? 0) + 1);
  }
  return parties.map((party) => {
    const supplier = supplierOpen.get(party.id);
    const outstandingByCurrency: Record<string, string> = {};
    for (const [currency, total] of supplier?.byCurrency ?? []) {
      outstandingByCurrency[currency] = total.toString();
    }
    return {
      id: party.id,
      legalName: party.legal_name,
      partyType: party.party_type,
      investorProjectCount: investorProjects.get(party.id)?.size ?? 0,
      openObligationCount: supplier?.count ?? 0,
      openCustomerInvoiceCount: customerOpen.get(party.id) ?? 0,
      outstandingByCurrency,
    };
  });
}

/** Plain-Arabic role summary, e.g. «مستثمر في مشروعين · مورد عليه التزامان». */
export function partyRolesAr(row: PartyDirectoryRow): string {
  const roles: string[] = [];
  if (row.investorProjectCount > 0) {
    roles.push(row.investorProjectCount === 1 ? 'مستثمر في مشروع واحد' : `مستثمر في ${row.investorProjectCount} مشاريع`);
  }
  if (row.openObligationCount > 0) {
    roles.push(row.openObligationCount === 1 ? 'مورد عليه التزام مفتوح' : `مورد عليه ${row.openObligationCount} التزامات مفتوحة`);
  }
  if (row.openCustomerInvoiceCount > 0) {
    roles.push(row.openCustomerInvoiceCount === 1 ? 'عميل عليه فاتورة مفتوحة' : `عميل عليه ${row.openCustomerInvoiceCount} فواتير مفتوحة`);
  }
  return roles.length > 0 ? roles.join(' · ') : 'لم يُستخدم بعد في أي مشروع';
}
