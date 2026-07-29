import { computeGlobalSummary, computeProjectProfitability } from '../../core/lib/profitability';
import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  SectorId,
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';
import { queryObligationAging, queryPartnerStatement } from '../finance/obligationQueries';
import type { SettlementAllocation } from '../settlement-allocations/types';
import type { Settlement } from '../settlements/types';

export interface ReportContext {
  dateFrom?: string;
  dateTo?: string;
  sector?: SectorId | 'all';
  projectId?: string;
  assetId?: string;
  partnerId?: string;
  displayCurrency: 'EGP';
}

export interface IntelligenceRecords {
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  projectPartners: ProjectPartner[];
  transactions: Transaction[];
  obligations: Obligation[];
  settlements: Settlement[];
  allocations: SettlementAllocation[];
  events: OperationalEvent[];
  adjustments: StockAdjustment[];
  documents: Document[];
}

export function validateReportContext(context: ReportContext): string | undefined {
  if (context.dateFrom && context.dateTo && context.dateFrom > context.dateTo) {
    return 'The report start date must be on or before its end date.';
  }
  return undefined;
}

export function filterReportRecords(records: IntelligenceRecords, context: ReportContext): IntelligenceRecords {
  const projects = records.projects.filter((project) =>
    (!context.sector || context.sector === 'all' || project.sector_id === context.sector)
    && (!context.projectId || project.id === context.projectId),
  );
  const projectIds = new Set(projects.map((project) => project.id));
  const assets = records.assets.filter((asset) =>
    projectIds.has(asset.project_id) && (!context.assetId || asset.id === context.assetId),
  );
  const assetIds = new Set(assets.map((asset) => asset.id));
  const transactions = records.transactions.filter((item) =>
    projectIds.has(item.project_id)
    && (!context.assetId || item.asset_id === context.assetId)
    && (!context.partnerId || item.partner_id === context.partnerId)
    && (!context.dateFrom || item.transaction_date >= context.dateFrom)
    && (!context.dateTo || item.transaction_date <= context.dateTo),
  );
  const obligations = records.obligations.filter((item) =>
    (!item.project_id || projectIds.has(item.project_id))
    && (!context.partnerId || item.partner_id === context.partnerId)
    && (!context.dateFrom || (item.created_at ?? item.due_date ?? '') >= context.dateFrom)
    && (!context.dateTo || (item.created_at ?? item.due_date ?? '') <= `${context.dateTo}T23:59:59`),
  );
  const obligationIds = new Set(obligations.map((item) => item.id));
  const eligibleSettlements = records.settlements.filter((item) =>
    (!context.dateFrom || item.settlement_date >= context.dateFrom)
    && (!context.dateTo || item.settlement_date <= context.dateTo),
  );
  const eligibleSettlementIds = new Set(eligibleSettlements.map((item) => item.id));
  const allocations = records.allocations.filter((item) =>
    obligationIds.has(item.obligation_id) && eligibleSettlementIds.has(item.settlement_id),
  );
  const settlementIds = new Set(allocations.map((item) => item.settlement_id));
  const settlements = eligibleSettlements.filter((item) => settlementIds.has(item.id));
  return {
    projects,
    assets,
    partners: context.partnerId ? records.partners.filter((item) => item.id === context.partnerId) : records.partners,
    projectPartners: records.projectPartners.filter((item) => projectIds.has(item.project_id) && (!context.partnerId || item.partner_id === context.partnerId)),
    transactions,
    obligations,
    settlements,
    allocations,
    events: records.events.filter((item) => projectIds.has(item.project_id) && (!context.assetId || item.asset_id === context.assetId) && assetIds.has(item.asset_id)),
    adjustments: records.adjustments.filter((item) => projectIds.has(item.project_id) && (!context.assetId || item.asset_id === context.assetId) && assetIds.has(item.asset_id)),
    documents: records.documents.filter((item) =>
      (!item.project_id || projectIds.has(item.project_id))
      && (!context.assetId || item.asset_id === context.assetId)
      && (!context.partnerId || item.partner_id === context.partnerId),
    ),
  };
}

export function buildIntelligenceReport(records: IntelligenceRecords, context: ReportContext, asOf: string) {
  const filtered = filterReportRecords(records, context);
  const executive = computeGlobalSummary(filtered.projects, filtered.transactions, filtered.obligations);
  const projects = filtered.projects.map((project) => computeProjectProfitability(
    project,
    filtered.transactions,
    filtered.obligations,
    filtered.projectPartners,
    filtered.partners,
  )).sort((a, b) => b.gross_profit_egp - a.gross_profit_egp);
  const aging = queryObligationAging(filtered.obligations, {
    as_of: asOf,
    partner_id: context.partnerId,
    project_id: context.projectId,
  });
  const statement = context.partnerId
    ? queryPartnerStatement(filtered.obligations, filtered.settlements, filtered.allocations, {
        partner_id: context.partnerId,
        project_id: context.projectId,
        include_reversed: true,
      })
    : undefined;
  const assetPositions = filtered.assets.map((asset) => ({
    asset,
    balance: asset.sector_id === 'real-estate'
      ? undefined
      : computeAssetLiveQuantity(
          asset.quantity ?? 0,
          filtered.events.filter((event) => event.asset_id === asset.id),
          filtered.adjustments.filter((adjustment) => adjustment.asset_id === asset.id),
        ),
  }));
  return { context, filtered, executive, projects, sectors: executive.by_sector, aging, statement, assetPositions };
}

export function reconcileIntelligenceReport(report: ReturnType<typeof buildIntelligenceReport>) {
  const projectIncome = report.projects.reduce((sum, item) => sum + item.total_income_egp, 0);
  const projectExpense = report.projects.reduce((sum, item) => sum + item.total_expense_egp, 0);
  const sectorIncome = Object.values(report.sectors).reduce((sum, item) => sum + item.total_income_egp, 0);
  const sectorExpense = Object.values(report.sectors).reduce((sum, item) => sum + item.total_expense_egp, 0);
  return {
    income: projectIncome === report.executive.total_income_egp && sectorIncome === report.executive.total_income_egp,
    expense: projectExpense === report.executive.total_expense_egp && sectorExpense === report.executive.total_expense_egp,
  };
}

export function buildFilteredReportCsv(report: ReturnType<typeof buildIntelligenceReport>) {
  const rows = [
    ['metric', 'value_egp'],
    ['income', report.executive.total_income_egp],
    ['expense', report.executive.total_expense_egp],
    ['gross_profit', report.executive.gross_profit_egp],
    ['receivables', report.executive.open_receivables_egp],
    ['payables', report.executive.open_payables_egp],
  ];
  return rows.map((row) => row.join(',')).join('\n');
}
