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
  remove: (id: string): void => {
    evStore.update((all) => all.filter((e) => e.id !== id));
  },
  subscribe: evStore.subscribe,
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
};
