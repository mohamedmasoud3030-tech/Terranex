import { useSyncExternalStore, useMemo } from 'react';
import { operationalEventsStore, stockAdjustmentsStore, type OperationalEventInput } from './storage';
import { recordStockAdjustmentAtomic } from './stockAdjustmentWorkflow';
import type { OperationalEvent, StockAdjustment } from '../../core/types/domain';

export function useOperationalEvents(assetId?: string, projectId?: string) {
  const events = useSyncExternalStore(
    operationalEventsStore.subscribe,
    operationalEventsStore.getAll,
    () => [] as OperationalEvent[],
  );

  const filtered = useMemo(() => {
    let list = events;
    if (assetId) list = list.filter((event) => event.asset_id === assetId);
    if (projectId) list = list.filter((event) => event.project_id === projectId);
    return list;
  }, [events, assetId, projectId]);

  return {
    events: filtered,
    allEvents: events,
    createEvent: async (input: OperationalEventInput) => {
      const created = operationalEventsStore.create(input);
      await operationalEventsStore.flush();
      return created;
    },
    updateEvent: async (id: string, input: Partial<OperationalEventInput>) => {
      const updated = operationalEventsStore.update(id, input);
      await operationalEventsStore.flush();
      return updated;
    },
    removeEvent: async (id: string) => {
      operationalEventsStore.remove(id);
      await operationalEventsStore.flush();
    },
    count: filtered.length,
  };
}

export function useStockAdjustments(assetId?: string) {
  const adjustments = useSyncExternalStore(
    stockAdjustmentsStore.subscribe,
    stockAdjustmentsStore.getAll,
    () => [] as StockAdjustment[],
  );

  const filtered = useMemo(
    () => assetId ? adjustments.filter((adjustment) => adjustment.asset_id === assetId) : adjustments,
    [adjustments, assetId],
  );

  return {
    adjustments: filtered,
    createAdjustment: recordStockAdjustmentAtomic,
    count: filtered.length,
  };
}

/**
 * Compute live asset quantity from base quantity + events + adjustments
 * ADR-003: dual-track — events and adjustments write to same balance view
 */
export function computeAssetLiveQuantity(
  baseQuantity: number,
  events: OperationalEvent[],
  adjustments: StockAdjustment[],
): { quantity: number; lastEventDate?: string; eventCount: number } {
  const eventDelta = events.reduce((sum, event) => sum + (event.quantity_delta ?? 0), 0);

  const sortedAdjustments = [...adjustments].sort((a, b) =>
    a.adjustment_date.localeCompare(b.adjustment_date),
  );

  let quantity = baseQuantity + eventDelta;
  let lastEventDate: string | undefined;

  if (events.length > 0) {
    lastEventDate = events.reduce((latest, event) =>
      event.event_date > latest ? event.event_date : latest, events[0].event_date,
    );
  }

  if (sortedAdjustments.length > 0) {
    const lastAdjustment = sortedAdjustments[sortedAdjustments.length - 1];
    quantity = lastAdjustment.quantity_after;
    lastEventDate = lastAdjustment.adjustment_date > (lastEventDate ?? '')
      ? lastAdjustment.adjustment_date
      : lastEventDate;

    const postAdjustmentEvents = events.filter((event) => event.event_date > lastAdjustment.adjustment_date);
    const postAdjustmentDelta = postAdjustmentEvents.reduce((sum, event) => sum + (event.quantity_delta ?? 0), 0);
    quantity += postAdjustmentDelta;
  }

  return {
    quantity: Math.max(0, quantity),
    lastEventDate,
    eventCount: events.length + adjustments.length,
  };
}
