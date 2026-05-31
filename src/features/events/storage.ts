import { createLocalStorageStore } from '../../core/storage/localStorageStore';
import type { OperationalEvent, StockAdjustment } from '../../core/types/domain';

const EVENTS_KEY = 'terranex.operationalEvents.v1';
const ADJUSTMENTS_KEY = 'terranex.stockAdjustments.v1';

function parseEvents(raw: unknown): OperationalEvent[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is OperationalEvent =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.asset_id === 'string',
  ).sort((a, b) => b.event_date.localeCompare(a.event_date));
}

function parseAdjustments(raw: unknown): StockAdjustment[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (r): r is StockAdjustment =>
      r && typeof r === 'object' &&
      typeof r.id === 'string' &&
      typeof r.asset_id === 'string',
  ).sort((a, b) => b.adjustment_date.localeCompare(a.adjustment_date));
}

function makeId(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

const evStore = createLocalStorageStore<OperationalEvent[]>(EVENTS_KEY, [], parseEvents);
const adjStore = createLocalStorageStore<StockAdjustment[]>(ADJUSTMENTS_KEY, [], parseAdjustments);

export type OperationalEventInput = Omit<OperationalEvent, 'id' | 'created_at'>;
export type StockAdjustmentInput = Omit<StockAdjustment, 'id' | 'created_at'>;

export const operationalEventsStore = {
  getAll: () => evStore.get(),
  getByAsset: (assetId: string) => evStore.get().filter((e) => e.asset_id === assetId),
  getByProject: (projectId: string) => evStore.get().filter((e) => e.project_id === projectId),
  create: (input: OperationalEventInput): OperationalEvent => {
    const event: OperationalEvent = { ...input, id: makeId('evt'), created_at: new Date().toISOString() };
    evStore.update((all) => [event, ...all]);
    return event;
  },
  remove: (id: string): void => {
    evStore.update((all) => all.filter((e) => e.id !== id));
  },
  subscribe: evStore.subscribe,
};

export const stockAdjustmentsStore = {
  getAll: () => adjStore.get(),
  getByAsset: (assetId: string) => adjStore.get().filter((a) => a.asset_id === assetId),
  getByProject: (projectId: string) => adjStore.get().filter((a) => a.project_id === projectId),
  create: (input: StockAdjustmentInput): StockAdjustment => {
    const adj: StockAdjustment = { ...input, id: makeId('adj'), created_at: new Date().toISOString() };
    adjStore.update((all) => [adj, ...all]);
    return adj;
  },
  remove: (id: string): void => {
    adjStore.update((all) => all.filter((a) => a.id !== id));
  },
  subscribe: adjStore.subscribe,
};
