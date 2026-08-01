import { computeGlobalSummary, computeProjectProfitability } from '../../core/lib/profitability';
import type {
  Asset,
  Distribution,
  DistributionAllocation,
  Document,
  EquityChangeEvent,
  Obligation,
  OperationalEvent,
  Partner,
  PartnerLedgerEntry,
  Project,
  ProjectPartner,
  SectorId,
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';
import { queryObligationAging, queryPartnerStatement } from '../finance/obligationQueries';
import { calculatePartnerLedgerSummary, decorateLedgerEntries } from '../ownership/model';
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
  equityChangeEvents: EquityChangeEvent[];
  partnerLedgerEntries: PartnerLedgerEntry[];
  distributions: Distribution[];
  distributionAllocations: DistributionAllocation[];
}

export function validateReportContext(context: ReportContext): string | undefined {
  if (context.dateFrom && context.dateTo && context.dateFrom > context.dateTo) {
    return 'The report start date must be on or before its end date.';
  }
  return undefined;
}

export function filterReportRecords(records: IntelligenceRecords, context: ReportContext): IntelligenceRecords {
  const equityChangeEventsSource = records.equityChangeEvents ?? [];
  const partnerLedgerEntriesSource = records.partnerLedgerEntries ?? [];
  const distributionsSource = records.distributions ?? [];
  const distributionAllocationsSource = records.distributionAllocations ?? [];
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
  const distributions = distributionsSource.filter((item) =>
    projectIds.has(item.project_id)
    && (!context.dateFrom || item.distribution_date >= context.dateFrom)
    && (!context.dateTo || item.distribution_date <= context.dateTo),
  );
  const distributionIds = new Set(distributions.map((item) => item.id));
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
    equityChangeEvents: equityChangeEventsSource.filter((item) => projectIds.has(item.project_id) && (!context.partnerId || item.partner_id === context.partnerId)),
    partnerLedgerEntries: partnerLedgerEntriesSource.filter((item) => projectIds.has(item.project_id) && (!context.partnerId || item.partner_id === context.partnerId) && (!context.dateFrom || item.posting_date >= context.dateFrom) && (!context.dateTo || item.posting_date <= context.dateTo)),
    distributions,
    distributionAllocations: distributionAllocationsSource.filter((item) => distributionIds.has(item.distribution_id) && (!context.partnerId || item.partner_id === context.partnerId)),
  };
}

export function buildIntelligenceReport(records: IntelligenceRecords, context: ReportContext, asOf: string) {
  const filtered = filterReportRecords(records, context);
  const executive = computeGlobalSummary(filtered.projects, filtered.transactions, filtered.obligations);
  const period = { from: context.dateFrom ?? '0001-01-01', to: context.dateTo ?? asOf };
  const projects = filtered.projects.map((project) => computeProjectProfitability(
    project,
    filtered.transactions,
    filtered.obligations,
    filtered.projectPartners,
    filtered.partners,
    {
      as_of_date: asOf,
      period,
      distributions: filtered.distributions,
      distributionAllocations: filtered.distributionAllocations,
      partnerLedgerEntries: filtered.partnerLedgerEntries,
    },
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
  const partnerLedgerRows = context.partnerId
    ? decorateLedgerEntries(filtered.partnerLedgerEntries.filter((entry) => entry.partner_id === context.partnerId))
    : [];
  const partnerLedgerSummary = context.partnerId
    ? calculatePartnerLedgerSummary(filtered.partnerLedgerEntries.filter((entry) => entry.partner_id === context.partnerId))
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
  return { context, filtered, executive, projects, sectors: executive.by_sector, aging, statement, partnerLedgerRows, partnerLedgerSummary, assetPositions };
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

function neutralizeCsvCell(value: string | number | undefined): string {
  const raw = String(value ?? '');
  const neutral = /^[=+\-@]/.test(raw) ? `'${raw}` : raw;
  return /[",\n\r]/.test(neutral) ? `"${neutral.replace(/"/g, '""')}"` : neutral;
}

export function buildFilteredReportCsv(report: ReturnType<typeof buildIntelligenceReport>) {
  const rows: Array<Array<string | number | undefined>> = [
    ['report_type', 'as_of_date', 'metric', 'value_egp'],
    ['executive', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'income', report.executive.total_income_egp],
    ['executive', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'expense', report.executive.total_expense_egp],
    ['executive', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'gross_profit', report.executive.gross_profit_egp],
    ['executive', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'receivables', report.executive.open_receivables_egp],
    ['executive', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'payables', report.executive.open_payables_egp],
    ['ownership', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'equity_change_events', report.filtered.equityChangeEvents.length],
    ['distribution', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'distributed_profit', report.projects.reduce((sum, item) => sum + item.distributed_profit_egp, 0)],
    ['distribution', report.projects[0]?.as_of_date ?? report.context.dateTo ?? '', 'unpaid_distributions', report.projects.reduce((sum, item) => sum + item.unpaid_distribution_amounts_egp, 0)],
  ];
  for (const project of report.projects) {
    rows.push(['project', project.as_of_date, `${project.project_name_ar} distributed`, project.distributed_profit_egp]);
    rows.push(['project', project.as_of_date, `${project.project_name_ar} undistributed`, project.undistributed_profit_egp]);
  }
  return rows.map((row) => row.map(neutralizeCsvCell).join(',')).join('\n');
}
