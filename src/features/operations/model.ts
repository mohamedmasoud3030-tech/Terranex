import type {
  Asset,
  Document,
  OperationalEvent,
  OperationalEventType,
  Project,
  SectorId,
  StockAdjustment,
  Transaction,
} from '../../core/types/domain';
import { computeAssetLiveQuantity } from '../events/hooks';

export type OperationsSector = SectorId | 'all';

export interface OperationsContext {
  sector: OperationsSector;
  projectId?: string;
  assetId?: string;
}

export interface EventFilters extends OperationsContext {
  type?: OperationalEventType | 'all';
  dateFrom?: string;
  dateTo?: string;
}

export interface EventDefinition {
  ar: string;
  en: string;
  sector: Exclude<SectorId, 'real-estate'> | 'both';
  quantity: 'positive' | 'negative' | 'optional' | 'none';
  weight: boolean;
  cost: boolean;
}

export const EVENT_DEFINITIONS: Record<OperationalEventType, EventDefinition> = {
  birth: { ar: 'ولادة', en: 'Birth', sector: 'livestock', quantity: 'positive', weight: false, cost: false },
  death: { ar: 'نفوق', en: 'Death', sector: 'livestock', quantity: 'negative', weight: false, cost: false },
  purchase: { ar: 'شراء', en: 'Purchase', sector: 'livestock', quantity: 'positive', weight: false, cost: true },
  sale: { ar: 'بيع', en: 'Sale', sector: 'livestock', quantity: 'negative', weight: false, cost: true },
  vaccination: { ar: 'تحصين', en: 'Vaccination', sector: 'livestock', quantity: 'optional', weight: false, cost: true },
  treatment: { ar: 'علاج', en: 'Treatment', sector: 'livestock', quantity: 'optional', weight: false, cost: true },
  feed_consumption: { ar: 'استهلاك علف', en: 'Feed', sector: 'livestock', quantity: 'optional', weight: false, cost: true },
  weighing: { ar: 'وزن', en: 'Weighing', sector: 'livestock', quantity: 'none', weight: true, cost: false },
  transfer: { ar: 'نقل', en: 'Transfer', sector: 'livestock', quantity: 'optional', weight: false, cost: true },
  planting: { ar: 'زراعة', en: 'Planting', sector: 'agriculture', quantity: 'optional', weight: false, cost: true },
  irrigation: { ar: 'ري', en: 'Irrigation', sector: 'agriculture', quantity: 'none', weight: false, cost: true },
  fertilization: { ar: 'تسميد', en: 'Fertilization', sector: 'agriculture', quantity: 'none', weight: false, cost: true },
  pest_control: { ar: 'مكافحة آفات', en: 'Pest control', sector: 'agriculture', quantity: 'none', weight: false, cost: true },
  harvest: { ar: 'حصاد', en: 'Harvest', sector: 'agriculture', quantity: 'positive', weight: true, cost: true },
  crop_loss: { ar: 'فقد محصول', en: 'Crop loss', sector: 'agriculture', quantity: 'negative', weight: false, cost: true },
};

export function eventTypesForSector(sector: SectorId): OperationalEventType[] {
  if (sector === 'real-estate') return [];
  return (Object.keys(EVENT_DEFINITIONS) as OperationalEventType[]).filter((type) => {
    const definition = EVENT_DEFINITIONS[type];
    return definition.sector === 'both' || definition.sector === sector;
  });
}

export class QuantitySignError extends Error {
  readonly expected: 'positive' | 'negative' | 'nonzero';
  constructor(expected: 'positive' | 'negative' | 'nonzero', messageAr: string) {
    super(messageAr);
    this.name = 'QuantitySignError';
    this.expected = expected;
  }
}

/**
 * Validate & normalise the quantity delta for an operational event.
 *
 * The previous version silently flipped the sign (e.g. user typed -5 on a
 * birth event and we stored +5). That hid user mistakes — now we throw an
 * explicit QuantitySignError with an Arabic message that the UI surfaces.
 */
export function normalizeQuantityDelta(
  type: OperationalEventType,
  raw: number | undefined,
): number | undefined {
  const rule = EVENT_DEFINITIONS[type].quantity;
  if (rule === 'none') return undefined;

  const isMissing = raw == null || !Number.isFinite(raw) || raw === 0;
  if (isMissing) {
    if (rule === 'positive') return 1;
    if (rule === 'negative') return -1;
    return undefined;
  }

  if (rule === 'positive') {
    if (raw < 0) {
      throw new QuantitySignError('positive', 'هذا النوع من الأحداث يتطلب كمية موجبة (زيادة). لا يمكن إدخال قيمة سالبة.');
    }
    return Math.abs(raw);
  }
  if (rule === 'negative') {
    if (raw > 0) {
      throw new QuantitySignError('negative', 'هذا النوع من الأحداث يتطلب كمية سالبة (نقصان). لا يمكن إدخال قيمة موجبة.');
    }
    return -Math.abs(raw);
  }
  if (raw === 0) return undefined;
  return raw;
}

export function filterOperationalEvents(
  events: OperationalEvent[],
  assets: Asset[],
  filters: EventFilters,
): OperationalEvent[] {
  const assetById = new Map(assets.map((asset) => [asset.id, asset]));
  return events.filter((event) => {
    const asset = assetById.get(event.asset_id);
    if (!asset) return false;
    if (filters.sector !== 'all' && asset.sector_id !== filters.sector) return false;
    if (filters.projectId && event.project_id !== filters.projectId) return false;
    if (filters.assetId && event.asset_id !== filters.assetId) return false;
    if (filters.type && filters.type !== 'all' && event.type !== filters.type) return false;
    if (filters.dateFrom && event.event_date < filters.dateFrom) return false;
    if (filters.dateTo && event.event_date > filters.dateTo) return false;
    return true;
  });
}

export function resolveOperationsContext(
  requested: OperationsContext,
  projects: Project[],
  assets: Asset[],
): OperationsContext {
  const project = requested.projectId
    ? projects.find((item) => item.id === requested.projectId)
    : undefined;
  const asset = requested.assetId
    ? assets.find((item) => item.id === requested.assetId)
    : undefined;
  if (requested.assetId && !asset) return { sector: requested.sector };
  if (requested.projectId && !project) return { sector: requested.sector };
  if (asset && project && asset.project_id !== project.id) {
    return { sector: asset.sector_id, projectId: asset.project_id, assetId: asset.id };
  }
  const inferredSector = asset?.sector_id ?? project?.sector_id;
  if (requested.sector !== 'all' && inferredSector && requested.sector !== inferredSector) {
    return { sector: inferredSector, projectId: project?.id ?? asset?.project_id, assetId: asset?.id };
  }
  return {
    sector: inferredSector ?? requested.sector,
    projectId: project?.id ?? asset?.project_id,
    assetId: asset?.id,
  };
}

export function computeOperationsOverview(
  projects: Project[],
  assets: Asset[],
  events: OperationalEvent[],
  adjustments: StockAdjustment[],
  documents: Document[],
  transactions: Transaction[],
  sector: OperationsSector,
) {
  const scopedProjects = sector === 'all' ? projects : projects.filter((project) => project.sector_id === sector);
  const projectIds = new Set(scopedProjects.map((project) => project.id));
  const scopedAssets = assets.filter((asset) => projectIds.has(asset.project_id));
  const assetIds = new Set(scopedAssets.map((asset) => asset.id));
  const scopedEvents = events.filter((event) => assetIds.has(event.asset_id));
  const scopedAdjustments = adjustments.filter((adjustment) => assetIds.has(adjustment.asset_id));
  const scopedDocuments = documents.filter((document) =>
    Boolean(document.project_id && projectIds.has(document.project_id)),
  );
  const linkedTransactions = transactions.filter((transaction) =>
    Boolean(transaction.operational_event_id && scopedEvents.some((event) => event.id === transaction.operational_event_id)),
  );
  const assetsNeedingAttention = scopedAssets.filter((asset) => {
    if (asset.sector_id === 'real-estate') return false;
    const balance = computeAssetLiveQuantity(
      asset.quantity ?? 0,
      scopedEvents.filter((event) => event.asset_id === asset.id),
      scopedAdjustments.filter((adjustment) => adjustment.asset_id === asset.id),
    );
    return balance.quantity === 0 || !balance.lastEventDate;
  });

  return {
    projectCount: scopedProjects.length,
    assetCount: scopedAssets.length,
    eventCount: scopedEvents.length,
    adjustmentCount: scopedAdjustments.length,
    documentCount: scopedDocuments.length,
    linkedTransactionCount: linkedTransactions.length,
    recentEvents: [...scopedEvents].sort((a, b) => b.event_date.localeCompare(a.event_date)).slice(0, 6),
    recentAdjustments: [...scopedAdjustments]
      .sort((a, b) => b.adjustment_date.localeCompare(a.adjustment_date))
      .slice(0, 6),
    assetsNeedingAttention,
  };
}

export function validateStockAdjustment(
  currentQuantity: number,
  adjustment: Pick<
    StockAdjustment,
    'quantity_before' | 'quantity_after' | 'value_egp_before' | 'value_egp_after' | 'adjustment_date'
  >,
): string[] {
  const errors: string[] = [];
  if (!Number.isFinite(adjustment.quantity_before) || adjustment.quantity_before !== currentQuantity) {
    errors.push('quantity_before_must_match_live_balance');
  }
  if (!Number.isFinite(adjustment.quantity_after) || adjustment.quantity_after < 0) {
    errors.push('quantity_after_must_be_non_negative');
  }
  if (!Number.isFinite(adjustment.value_egp_before) || adjustment.value_egp_before < 0) {
    errors.push('value_before_must_be_non_negative');
  }
  if (!Number.isFinite(adjustment.value_egp_after) || adjustment.value_egp_after < 0) {
    errors.push('value_after_must_be_non_negative');
  }
  if (!adjustment.adjustment_date) errors.push('adjustment_date_required');
  return errors;
}
