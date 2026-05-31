import { describe, expect, it } from 'vitest';
import { computeGlobalSummary, computeProjectProfitability, computeSectorSummary } from './profitability';
import type { Obligation, Partner, Project, ProjectPartner, Transaction } from '../types/domain';

const now = '2026-01-01T00:00:00.000Z';

function project(id: string, sector_id: Project['sector_id']): Project {
  return {
    id,
    sector_id,
    name_ar: id,
    name_en: id,
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'EGP',
    created_at: now,
    updated_at: now,
  };
}

function transaction(id: string, project_id: string, direction: Transaction['direction'], amount_egp: number): Transaction {
  return {
    id,
    project_id,
    direction,
    category: 'other',
    amount: amount_egp,
    currency: 'EGP',
    fx_rate: 1,
    amount_egp,
    transaction_date: '2026-01-02',
    created_at: now,
    updated_at: now,
  };
}

function obligation(
  id: string,
  project_id: string,
  direction: Obligation['direction'],
  amount_egp: number,
  amount_settled_egp = 0,
): Obligation {
  return {
    id,
    project_id,
    partner_id: 'partner-1',
    direction,
    amount: amount_egp,
    currency: 'EGP',
    amount_egp,
    status: amount_settled_egp > 0 ? 'partial' : 'open',
    amount_settled_egp,
    created_at: now,
    updated_at: now,
  };
}

describe('profitability calculations', () => {
  const projects = [project('real-1', 'real-estate'), project('agri-1', 'agriculture')];
  const transactions = [
    transaction('tx-1', 'real-1', 'income', 1_000),
    transaction('tx-2', 'real-1', 'expense', 300),
    transaction('tx-3', 'agri-1', 'income', 500),
    transaction('tx-4', 'agri-1', 'expense', 800),
  ];
  const obligations = [
    obligation('obl-1', 'real-1', 'receivable', 400, 100),
    obligation('obl-2', 'real-1', 'payable', 150),
    obligation('obl-3', 'agri-1', 'payable', 200, 50),
  ];
  const partners: Partner[] = [{ id: 'partner-1', name_ar: 'Partner', category: 'equity_partner', created_at: now }];
  const projectPartners: ProjectPartner[] = [{ id: 'pp-1', project_id: 'real-1', partner_id: 'partner-1', equity_pct: 25, effective_from: '2026-01-01' }];

  it('computes project totals, exposure, and partner splits', () => {
    const summary = computeProjectProfitability(projects[0], transactions, obligations, projectPartners, partners);

    expect(summary.total_income_egp).toBe(1_000);
    expect(summary.total_expense_egp).toBe(300);
    expect(summary.gross_profit_egp).toBe(700);
    expect(summary.open_receivables_egp).toBe(300);
    expect(summary.open_payables_egp).toBe(150);
    expect(summary.cash_exposure_egp).toBe(150);
    expect(summary.partner_splits).toEqual([{ partner_id: 'partner-1', partner_name_ar: 'Partner', equity_pct: 25, share_egp: 175 }]);
  });

  it('computes sector totals from projects in the selected sector', () => {
    const summary = computeSectorSummary('real-estate', projects, transactions, obligations);

    expect(summary.project_count).toBe(1);
    expect(summary.total_income_egp).toBe(1_000);
    expect(summary.total_expense_egp).toBe(300);
    expect(summary.gross_profit_egp).toBe(700);
    expect(summary.open_receivables_egp).toBe(300);
    expect(summary.open_payables_egp).toBe(150);
    expect(summary.margin_pct).toBe(70);
  });

  it('computes global totals and sector summaries', () => {
    const summary = computeGlobalSummary(projects, transactions, obligations);

    expect(summary.total_income_egp).toBe(1_500);
    expect(summary.total_expense_egp).toBe(1_100);
    expect(summary.gross_profit_egp).toBe(400);
    expect(summary.open_receivables_egp).toBe(300);
    expect(summary.open_payables_egp).toBe(300);
    expect(summary.cash_exposure_egp).toBe(0);
    expect(summary.by_sector['agriculture'].net_profit_egp).toBe(-300);
  });
});
