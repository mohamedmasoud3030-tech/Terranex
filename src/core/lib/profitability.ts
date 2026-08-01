/**
 * Profitability Engine — Terranex
 * Computes profit/loss at project, sector, and global levels.
 * All values normalized to EGP.
 *
 * Ownership temporal rule (ADR-011/013 integration): partner entitlement is
 * sliced at transaction date. Each income/expense transaction is allocated to
 * the ownership percentages effective on that transaction_date. A distribution
 * freezes its own ownership snapshot and is reported separately; it never
 * becomes an operational expense in this engine.
 */

import { toDateOnly } from './dateOnly';
import type {
  DateRange,
  Distribution,
  DistributionAllocation,
  Obligation,
  Partner,
  PartnerLedgerEntry,
  Project,
  ProjectPartner,
  ProjectProfitability,
  SectorId,
  Transaction,
} from '../types/domain';

export interface SectorSummary {
  sector_id: SectorId;
  total_income_egp: number;
  total_expense_egp: number;
  gross_profit_egp: number;
  open_receivables_egp: number;
  open_payables_egp: number;
  cash_exposure_egp: number;
  net_profit_egp: number;
  project_count: number;
  margin_pct: number;
}

export interface GlobalSummary {
  total_income_egp: number;
  total_expense_egp: number;
  gross_profit_egp: number;
  open_receivables_egp: number;
  open_payables_egp: number;
  cash_exposure_egp: number;
  net_egp: number;
  margin_pct: number;
  by_sector: Record<SectorId, SectorSummary>;
}

export interface ProfitabilityOptions {
  as_of_date?: string;
  period?: DateRange;
  distributions?: Distribution[];
  distributionAllocations?: DistributionAllocation[];
  partnerLedgerEntries?: PartnerLedgerEntry[];
}

const TEMPORAL_RULE_AR = 'تُنسب كل معاملة إلى الشركاء حسب نسب الملكية الفعالة في تاريخ المعاملة؛ التوزيعات تُعرض منفصلة ولا تُسجل كمصروف تشغيلي.';
const TEMPORAL_RULE_EN = 'Each transaction is allocated to partners by ownership effective on the transaction date; distributions are reported separately and are not operational expenses.';

function openBalance(o: Obligation): number {
  return Math.max(0, o.amount_egp - o.amount_settled_egp);
}

function todayDateOnly(): string {
  return new Date().toISOString().slice(0, 10);
}

function normalizeDate(value: string | undefined, fallback: string): string {
  return toDateOnly(value) ?? fallback;
}

function inDateRange(value: string, range: DateRange): boolean {
  const date = normalizeDate(value, value.slice(0, 10));
  return date >= range.from && date <= range.to;
}

function activeOwnershipRows(projectPartners: ProjectPartner[], projectId: string, asOfDate: string): ProjectPartner[] {
  return projectPartners.filter((pp) => {
    const from = normalizeDate(pp.effective_from, pp.effective_from.slice(0, 10));
    const to = toDateOnly(pp.effective_to);
    return pp.project_id === projectId && from <= asOfDate && (!to || to >= asOfDate);
  });
}

function addTo(map: Map<string, number>, key: string, amount: number): void {
  map.set(key, (map.get(key) ?? 0) + amount);
}

function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function signedLedgerEffect(entry: PartnerLedgerEntry, reversedIds: Set<string>): number {
  if (entry.entry_type === 'reversal' || reversedIds.has(entry.id)) return 0;
  switch (entry.entry_type) {
    case 'capital_contribution':
    case 'distribution_entitlement':
    case 'correction':
      return entry.amount_egp;
    case 'withdrawal':
    case 'distribution_payment':
      return -entry.amount_egp;
  }
}

function reversedLedgerIds(entries: PartnerLedgerEntry[]): Set<string> {
  const ids = new Set<string>();
  for (const entry of entries) {
    if (entry.entry_type === 'reversal' && entry.reversal_of_id) ids.add(entry.reversal_of_id);
  }
  return ids;
}

export function computeProjectProfitability(
  project: Project,
  transactions: Transaction[],
  obligations: Obligation[],
  projectPartners: ProjectPartner[],
  partners: Partner[],
  options: ProfitabilityOptions = {},
): ProjectProfitability {
  const asOf = normalizeDate(options.as_of_date, project.end_date ?? todayDateOnly());
  const period = options.period ?? { from: normalizeDate(project.start_date, project.start_date.slice(0, 10)), to: asOf };
  const txs = transactions.filter((t) => t.project_id === project.id && inDateRange(t.transaction_date, period));
  const obls = obligations.filter((o) => o.project_id === project.id);

  const total_income_egp = txs.filter((t) => t.direction === 'income').reduce((s, t) => s + t.amount_egp, 0);
  const total_expense_egp = txs.filter((t) => t.direction === 'expense').reduce((s, t) => s + t.amount_egp, 0);
  const gross_profit_egp = total_income_egp - total_expense_egp;

  const openObls = obls.filter((o) => o.status !== 'settled' && o.status !== 'written_off');
  const open_receivables_egp = openObls.filter((o) => o.direction === 'receivable').reduce((s, o) => s + openBalance(o), 0);
  const open_payables_egp = openObls.filter((o) => o.direction === 'payable').reduce((s, o) => s + openBalance(o), 0);
  const cash_exposure_egp = open_receivables_egp - open_payables_egp;
  const open_obligations_egp = open_receivables_egp + open_payables_egp;

  const net_realized_profit_egp = gross_profit_egp;
  const net_profit_egp = gross_profit_egp;

  const entitlementByPartner = new Map<string, number>();
  for (const transaction of txs) {
    const transactionDate = normalizeDate(transaction.transaction_date, transaction.transaction_date.slice(0, 10));
    const signedAmount = transaction.direction === 'income' ? transaction.amount_egp : -transaction.amount_egp;
    const ownership = activeOwnershipRows(projectPartners, project.id, transactionDate);
    for (const row of ownership) {
      addTo(entitlementByPartner, row.partner_id, signedAmount * row.equity_pct / 100);
    }
  }

  const projectDistributions = (options.distributions ?? [])
    .filter((distribution) => distribution.project_id === project.id)
    .filter((distribution) => distribution.status !== 'reversed')
    .filter((distribution) => inDateRange(distribution.distribution_date, period));
  const distributionIds = new Set(projectDistributions.map((distribution) => distribution.id));
  const distributionAllocations = (options.distributionAllocations ?? [])
    .filter((allocation) => distributionIds.has(allocation.distribution_id))
    .filter((allocation) => allocation.status !== 'reversed');

  const distributed_profit_egp = projectDistributions.reduce((sum, distribution) => sum + distribution.total_amount_egp, 0);
  const allocationByPartner = new Map<string, number>();
  for (const allocation of distributionAllocations) addTo(allocationByPartner, allocation.partner_id, allocation.allocated_amount_egp);

  const ledgerEntries = (options.partnerLedgerEntries ?? [])
    .filter((entry) => entry.project_id === project.id)
    .filter((entry) => normalizeDate(entry.posting_date, entry.posting_date.slice(0, 10)) <= asOf);
  const reversedIds = reversedLedgerIds(ledgerEntries);
  const ledgerByPartner = new Map<string, number>();
  const paidByPartner = new Map<string, number>();
  for (const entry of ledgerEntries) {
    const effect = signedLedgerEffect(entry, reversedIds);
    addTo(ledgerByPartner, entry.partner_id, effect);
    if (entry.entry_type === 'distribution_payment') addTo(paidByPartner, entry.partner_id, -effect);
  }

  const paid_distribution_amounts_egp = [...paidByPartner.values()].reduce((sum, value) => sum + value, 0);
  const allocation_total_egp = [...allocationByPartner.values()].reduce((sum, value) => sum + value, 0);
  const unpaid_distribution_amounts_egp = Math.max(0, allocation_total_egp - paid_distribution_amounts_egp);
  const partner_ledger_position_egp = [...ledgerByPartner.values()].reduce((sum, value) => sum + value, 0);
  const partner_entitlement_egp = [...entitlementByPartner.values()].reduce((sum, value) => sum + value, 0);
  const undistributed_profit_egp = net_realized_profit_egp - distributed_profit_egp;

  const currentOwnership = activeOwnershipRows(projectPartners, project.id, asOf);
  const partnerIds = new Set<string>([
    ...currentOwnership.map((pp) => pp.partner_id),
    ...entitlementByPartner.keys(),
    ...allocationByPartner.keys(),
    ...ledgerByPartner.keys(),
  ]);

  const partner_splits = [...partnerIds].map((partnerId) => {
    const partner = partners.find((p) => p.id === partnerId);
    const equity_pct = currentOwnership
      .filter((pp) => pp.partner_id === partnerId)
      .reduce((sum, pp) => sum + pp.equity_pct, 0);
    const distributed = allocationByPartner.get(partnerId) ?? 0;
    const paid = paidByPartner.get(partnerId) ?? 0;
    return {
      partner_id: partnerId,
      partner_name_ar: partner?.name_ar ?? 'غير معروف',
      equity_pct,
      share_egp: roundMoney(entitlementByPartner.get(partnerId) ?? 0),
      distributed_egp: roundMoney(distributed),
      paid_egp: roundMoney(paid),
      unpaid_egp: roundMoney(Math.max(0, distributed - paid)),
      ledger_balance_egp: roundMoney(ledgerByPartner.get(partnerId) ?? 0),
    };
  }).sort((a, b) => b.share_egp - a.share_egp || a.partner_name_ar.localeCompare(b.partner_name_ar));

  return {
    project_id: project.id,
    project_name_ar: project.name_ar,
    project_name_en: project.name_en,
    sector_id: project.sector_id,
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    net_realized_profit_egp,
    open_obligations_egp,
    open_receivables_egp,
    open_payables_egp,
    cash_exposure_egp,
    net_profit_egp,
    distributed_profit_egp: roundMoney(distributed_profit_egp),
    undistributed_profit_egp: roundMoney(undistributed_profit_egp),
    partner_entitlement_egp: roundMoney(partner_entitlement_egp),
    paid_distribution_amounts_egp: roundMoney(paid_distribution_amounts_egp),
    unpaid_distribution_amounts_egp: roundMoney(unpaid_distribution_amounts_egp),
    partner_ledger_position_egp: roundMoney(partner_ledger_position_egp),
    as_of_date: asOf,
    temporal_rule_ar: TEMPORAL_RULE_AR,
    temporal_rule_en: TEMPORAL_RULE_EN,
    partner_splits,
    period,
  };
}

export function computeSectorSummary(
  sectorId: SectorId,
  projects: Project[],
  transactions: Transaction[],
  obligations: Obligation[],
): SectorSummary {
  const sectorProjects = projects.filter((p) => p.sector_id === sectorId);
  const projectIds = new Set(sectorProjects.map((p) => p.id));

  const txs = transactions.filter((t) => projectIds.has(t.project_id));
  const obls = obligations.filter((o) => o.project_id && projectIds.has(o.project_id));

  const total_income_egp = txs.filter((t) => t.direction === 'income').reduce((s, t) => s + t.amount_egp, 0);
  const total_expense_egp = txs.filter((t) => t.direction === 'expense').reduce((s, t) => s + t.amount_egp, 0);
  const gross_profit_egp = total_income_egp - total_expense_egp;

  const openObls = obls.filter((o) => o.status !== 'settled' && o.status !== 'written_off');
  const open_receivables_egp = openObls.filter((o) => o.direction === 'receivable').reduce((s, o) => s + openBalance(o), 0);
  const open_payables_egp = openObls.filter((o) => o.direction === 'payable').reduce((s, o) => s + openBalance(o), 0);
  const cash_exposure_egp = open_receivables_egp - open_payables_egp;

  const net_profit_egp = gross_profit_egp;
  const margin_pct = total_income_egp > 0 ? (gross_profit_egp / total_income_egp) * 100 : 0;

  return {
    sector_id: sectorId,
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    open_receivables_egp,
    open_payables_egp,
    cash_exposure_egp,
    net_profit_egp,
    project_count: sectorProjects.length,
    margin_pct,
  };
}

export function computeGlobalSummary(
  projects: Project[],
  transactions: Transaction[],
  obligations: Obligation[],
): GlobalSummary {
  const sectors: SectorId[] = ['real-estate', 'agriculture', 'livestock'];
  const bySector = Object.fromEntries(
    sectors.map((s) => [s, computeSectorSummary(s, projects, transactions, obligations)]),
  ) as Record<SectorId, SectorSummary>;

  const total_income_egp = transactions.filter((t) => t.direction === 'income').reduce((s, t) => s + t.amount_egp, 0);
  const total_expense_egp = transactions.filter((t) => t.direction === 'expense').reduce((s, t) => s + t.amount_egp, 0);
  const gross_profit_egp = total_income_egp - total_expense_egp;

  const openObls = obligations.filter((o) => o.status !== 'settled' && o.status !== 'written_off');
  const open_receivables_egp = openObls.filter((o) => o.direction === 'receivable').reduce((s, o) => s + openBalance(o), 0);
  const open_payables_egp = openObls.filter((o) => o.direction === 'payable').reduce((s, o) => s + openBalance(o), 0);
  const cash_exposure_egp = open_receivables_egp - open_payables_egp;

  const net_egp = gross_profit_egp;
  const margin_pct = total_income_egp > 0 ? (gross_profit_egp / total_income_egp) * 100 : 0;

  return {
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    open_receivables_egp,
    open_payables_egp,
    cash_exposure_egp,
    net_egp,
    margin_pct,
    by_sector: bySector,
  };
}

export function formatEgp(value: number, short = false): string {
  if (short) {
    if (Math.abs(value) >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}م`;
    if (Math.abs(value) >= 1_000) return `${(value / 1_000).toFixed(0)}ك`;
    return value.toFixed(0);
  }
  return new Intl.NumberFormat('ar-EG', { minimumFractionDigits: 0, maximumFractionDigits: 0 }).format(value);
}
