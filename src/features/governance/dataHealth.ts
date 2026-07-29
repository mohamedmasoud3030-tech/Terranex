import type {
  Asset,
  Document,
  Obligation,
  OperationalEvent,
  Partner,
  Project,
  ProjectPartner,
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import type { SupabaseStore } from '../../core/storage/supabaseStore';
import type { SettlementAllocation } from '../settlement-allocations/types';
import type { Settlement } from '../settlements/types';

export interface GovernanceRecords {
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

export interface DataHealthFinding {
  code: string;
  entity: string;
  entityId: string;
  relationship: string;
  missingId: string;
  severity: 'error' | 'warning';
}

export interface StoreDiagnostic {
  name: string;
  loaded: boolean;
  loadError?: string;
  writeError?: string;
  readsBeforeHydration: number;
}

function finding(
  code: string,
  entity: string,
  entityId: string,
  relationship: string,
  missingId: string,
): DataHealthFinding {
  return { code, entity, entityId, relationship, missingId, severity: 'error' };
}

export function inspectOrphanReferences(records: GovernanceRecords): DataHealthFinding[] {
  const projectIds = new Set(records.projects.map((item) => item.id));
  const assetIds = new Set(records.assets.map((item) => item.id));
  const partnerIds = new Set(records.partners.map((item) => item.id));
  const documentIds = new Set(records.documents.map((item) => item.id));
  const transactionIds = new Set(records.transactions.map((item) => item.id));
  const obligationIds = new Set(records.obligations.map((item) => item.id));
  const settlementIds = new Set(records.settlements.map((item) => item.id));
  const findings: DataHealthFinding[] = [];

  for (const item of records.assets) {
    if (!projectIds.has(item.project_id)) findings.push(finding('asset.project', 'asset', item.id, 'project', item.project_id));
  }
  for (const item of records.projectPartners) {
    if (!projectIds.has(item.project_id)) findings.push(finding('project_partner.project', 'project_partner', item.id, 'project', item.project_id));
    if (!partnerIds.has(item.partner_id)) findings.push(finding('project_partner.partner', 'project_partner', item.id, 'partner', item.partner_id));
  }
  for (const item of records.transactions) {
    if (!projectIds.has(item.project_id)) findings.push(finding('transaction.project', 'transaction', item.id, 'project', item.project_id));
    if (item.asset_id && !assetIds.has(item.asset_id)) findings.push(finding('transaction.asset', 'transaction', item.id, 'asset', item.asset_id));
    if (item.partner_id && !partnerIds.has(item.partner_id)) findings.push(finding('transaction.partner', 'transaction', item.id, 'partner', item.partner_id));
    if (item.document_id && !documentIds.has(item.document_id)) findings.push(finding('transaction.document', 'transaction', item.id, 'document', item.document_id));
  }
  for (const item of records.obligations) {
    if (item.project_id && !projectIds.has(item.project_id)) findings.push(finding('obligation.project', 'obligation', item.id, 'project', item.project_id));
    if (!partnerIds.has(item.partner_id)) findings.push(finding('obligation.partner', 'obligation', item.id, 'partner', item.partner_id));
    if (item.source_transaction_id && !transactionIds.has(item.source_transaction_id)) findings.push(finding('obligation.transaction', 'obligation', item.id, 'transaction', item.source_transaction_id));
    if (item.document_id && !documentIds.has(item.document_id)) findings.push(finding('obligation.document', 'obligation', item.id, 'document', item.document_id));
  }
  for (const item of records.documents) {
    if (item.project_id && !projectIds.has(item.project_id)) findings.push(finding('document.project', 'document', item.id, 'project', item.project_id));
    if (item.asset_id && !assetIds.has(item.asset_id)) findings.push(finding('document.asset', 'document', item.id, 'asset', item.asset_id));
    if (item.partner_id && !partnerIds.has(item.partner_id)) findings.push(finding('document.partner', 'document', item.id, 'partner', item.partner_id));
    if (item.transaction_id && !transactionIds.has(item.transaction_id)) findings.push(finding('document.transaction', 'document', item.id, 'transaction', item.transaction_id));
  }
  for (const item of records.events) {
    if (!projectIds.has(item.project_id)) findings.push(finding('event.project', 'event', item.id, 'project', item.project_id));
    if (!assetIds.has(item.asset_id)) findings.push(finding('event.asset', 'event', item.id, 'asset', item.asset_id));
    if (item.document_id && !documentIds.has(item.document_id)) findings.push(finding('event.document', 'event', item.id, 'document', item.document_id));
    if (item.linked_transaction_id && !transactionIds.has(item.linked_transaction_id)) findings.push(finding('event.transaction', 'event', item.id, 'transaction', item.linked_transaction_id));
  }
  for (const item of records.adjustments) {
    if (!projectIds.has(item.project_id)) findings.push(finding('adjustment.project', 'adjustment', item.id, 'project', item.project_id));
    if (!assetIds.has(item.asset_id)) findings.push(finding('adjustment.asset', 'adjustment', item.id, 'asset', item.asset_id));
  }
  for (const item of records.settlements) {
    if (!obligationIds.has(item.obligation_id)) findings.push(finding('settlement.obligation', 'settlement', item.id, 'obligation', item.obligation_id));
    if (item.receipt_document_id && !documentIds.has(item.receipt_document_id)) findings.push(finding('settlement.document', 'settlement', item.id, 'document', item.receipt_document_id));
  }
  for (const item of records.allocations) {
    if (!settlementIds.has(item.settlement_id)) findings.push(finding('allocation.settlement', 'allocation', item.id, 'settlement', item.settlement_id));
    if (!obligationIds.has(item.obligation_id)) findings.push(finding('allocation.obligation', 'allocation', item.id, 'obligation', item.obligation_id));
  }
  return findings.sort((a, b) => a.code.localeCompare(b.code) || a.entityId.localeCompare(b.entityId));
}

export function inspectStore(
  name: string,
  store: Pick<SupabaseStore<{ id: string }>, 'isLoaded' | 'getLoadError' | 'getWriteError' | 'getReadsBeforeHydration'>,
): StoreDiagnostic {
  return {
    name,
    loaded: store.isLoaded(),
    loadError: store.getLoadError()?.message,
    writeError: store.getWriteError()?.message,
    readsBeforeHydration: store.getReadsBeforeHydration(),
  };
}

export const BACKUP_COVERAGE = {
  localBrowserRecords: true,
  localUploadedFiles: true,
  supabaseDomainRows: false,
  completeWorkspaceRestore: false,
} as const;

export function classifyDocumentExpiry(
  expiryDate: string | undefined,
  asOf: string,
): 'undated' | 'current' | 'expiring' | 'expired' {
  if (!expiryDate) return 'undated';
  if (expiryDate < asOf) return 'expired';
  const expiry = Date.parse(`${expiryDate}T00:00:00Z`);
  const current = Date.parse(`${asOf}T00:00:00Z`);
  return expiry - current <= 30 * 86_400_000 ? 'expiring' : 'current';
}
