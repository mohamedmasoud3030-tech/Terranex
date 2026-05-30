/**
 * Profitability Engine — Terranex
 * Computes profit/loss at project, sector, and global levels.
 * All values normalized to EGP.
 */

import type {
  Transaction,
  Obligation,
  Project,
  SectorId,
  ProjectProfitability,
  ProjectPartner,
  Partner,
} from '../types/domain';

export interface SectorSummary {
  sector_id: SectorId;
  total_income_egp: number;
  total_expense_egp: number;
  gross_profit_egp: number;
  open_receivables_egp: number;
  open_payables_egp: number;
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
  net_egp: number;
  margin_pct: number;
  by_sector: Record<SectorId, SectorSummary>;
}

function openBalance(o: Obligation): number {
  return Math.max(0, o.amount_egp - o.amount_settled_egp);
}

export function computeProjectProfitability(
  project: Project,
  transactions: Transaction[],
  obligations: Obligation[],
  projectPartners: ProjectPartner[],
  partners: Partner[],
): ProjectProfitability {
  const txs = transactions.filter((t) => t.project_id === project.id);
  const obls = obligations.filter((o) => o.project_id === project.id);

  const total_income_egp = txs.filter((t) => t.direction === 'income').reduce((s, t) => s + t.amount_egp, 0);
  const total_expense_egp = txs.filter((t) => t.direction === 'expense').reduce((s, t) => s + t.amount_egp, 0);
  const gross_profit_egp = total_income_egp - total_expense_egp;

  const open_obligations_egp = obls
    .filter((o) => o.direction === 'receivable' && o.status !== 'settled' && o.status !== 'written_off')
    .reduce((s, o) => s + openBalance(o), 0);

  const net_profit_egp = gross_profit_egp - open_obligations_egp;

  const pps = projectPartners.filter((pp) => pp.project_id === project.id);
  const partner_splits = pps.map((pp) => {
    const partner = partners.find((p) => p.id === pp.partner_id);
    return {
      partner_id: pp.partner_id,
      partner_name_ar: partner?.name_ar ?? 'غير معروف',
      equity_pct: pp.equity_pct,
      share_egp: (net_profit_egp * pp.equity_pct) / 100,
    };
  });

  return {
    project_id: project.id,
    project_name_ar: project.name_ar,
    project_name_en: project.name_en,
    sector_id: project.sector_id,
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    open_obligations_egp,
    net_profit_egp,
    partner_splits,
    period: { from: project.start_date, to: project.end_date ?? new Date().toISOString().slice(0, 10) },
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

  const net_profit_egp = gross_profit_egp;
  const margin_pct = total_income_egp > 0 ? (gross_profit_egp / total_income_egp) * 100 : 0;

  return {
    sector_id: sectorId,
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    open_receivables_egp,
    open_payables_egp,
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

  const net_egp = gross_profit_egp;
  const margin_pct = total_income_egp > 0 ? (gross_profit_egp / total_income_egp) * 100 : 0;

  return {
    total_income_egp,
    total_expense_egp,
    gross_profit_egp,
    open_receivables_egp,
    open_payables_egp,
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
