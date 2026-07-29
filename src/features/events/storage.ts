import { createSupabaseStore } from '../../core/storage/supabaseStore';
import type { OperationalEvent, StockAdjustment } from '../../core/types/domain';

const EVENTS_TABLE = 'operational_events';
const ADJUSTMENTS_TABLE = 'stock_adjustments';

function parseEvent(raw: unknown): OperationalEvent {
  return raw as OperationalEvent;
}

function parseAdjustment(raw: unknown): StockAdjustment {
  return raw as StockAdjustment;
}

function makeId() {
  return crypto.randomUUID();
}

const evStore = createSupabaseStore<OperationalEvent>(EVENTS_TABLE, parseEvent, 'event_date');
const adjStore = createSupabaseStore<StockAdjustment>(ADJUSTMENTS_TABLE, parseAdjustment, 'adjustment_date');

export const operationalEventsReady = evStore.ready;
export const stockAdjustmentsReady = adjStore.ready;
export const operationalEventsHydration = evStore;
export const stockAdjustmentsHydration = adjStore;

export type OperationalEventInput = Omit<OperationalEvent, 'id' | 'created_at'>;
export type StockAdjustmentInput = Omit<StockAdjustment, 'id' | 'created_at'>;

export const operationalEventsStore = {
  getAll: () => evStore.get(),
  getByAsset: (assetId: string) => evStore.get().filter((e) => e.asset_id === assetId),
  getByProject: (projectId: string) => evStore.get().filter((e) => e.project_id === projectId),
  create: (input: OperationalEventInput): OperationalEvent => {
    const event: OperationalEvent = { ...input, id: makeId(), created_at: new Date().toISOString() };
    evStore.update((all) => [event, ...all]);
    return event;
  },
  update: (id: string, input: Partial<OperationalEventInput>): OperationalEvent => {
    const current = evStore.get().find((event) => event.id === id);
    if (!current) throw new Error('تعذر العثور على الحدث التشغيلي.');
    const next = { ...current, ...input };
    evStore.update((all) => all.map((event) => event.id === id ? next : event));
    return next;
  },
  remove: (id: string): void => {
    evStore.update((all) => all.filter((e) => e.id !== id));
  },
  subscribe: evStore.subscribe,
  flush: evStore.flush,
  rehydrate: evStore.rehydrate,
  getLoadError: evStore.getLoadError,
};

export const stockAdjustmentsStore = {
  getAll: () => adjStore.get(),
  getByAsset: (assetId: string) => adjStore.get().filter((a) => a.asset_id === assetId),
  create: (input: StockAdjustmentInput): StockAdjustment => {
    const adj: StockAdjustment = { ...input, id: makeId(), created_at: new Date().toISOString() };
    adjStore.update((all) => [adj, ...all]);
    return adj;
  },
  subscribe: adjStore.subscribe,
  flush: adjStore.flush,
  rehydrate: adjStore.rehydrate,
  getLoadError: adjStore.getLoadError,
};
