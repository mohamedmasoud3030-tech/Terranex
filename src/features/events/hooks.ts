import { useSyncExternalStore, useMemo } from 'react';
import { operationalEventsStore, stockAdjustmentsStore, type OperationalEventInput, type StockAdjustmentInput } from './storage';
import type { OperationalEvent, StockAdjustment } from '../../core/types/domain';

export function useOperationalEvents(assetId?: string, projectId?: string) {
  const events = useSyncExternalStore(
    operationalEventsStore.subscribe,
    operationalEventsStore.getAll,
    () => [] as OperationalEvent[]
  );

  const filtered = useMemo(() => {
    let list = events;
    if (assetId) list = list.filter(e => e.asset_id === assetId);
    if (projectId) list = list.filter(e => e.project_id === projectId);
    return list;
  }, [events, assetId, projectId]);

  return {
    events: filtered,
    allEvents: events,
    createEvent: (input: OperationalEventInput) => operationalEventsStore.create(input),
    removeEvent: (id: string) => operationalEventsStore.remove(id),
    count: filtered.length,
  };
}

export function useStockAdjustments(assetId?: string) {
  const adjustments = useSyncExternalStore(
    stockAdjustmentsStore.subscribe,
    stockAdjustmentsStore.getAll,
    () => [] as StockAdjustment[]
  );

  const filtered = useMemo(() => 
    assetId ? adjustments.filter(a => a.asset_id === assetId) : adjustments,
    [adjustments, assetId]
  );

  return {
    adjustments: filtered,
    createAdjustment: (input: StockAdjustmentInput) => stockAdjustmentsStore.create(input),
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
  adjustments: StockAdjustment[]
): { quantity: number; lastEventDate?: string; eventCount: number } {
  const eventDelta = events.reduce((sum, e) => sum + (e.quantity_delta ?? 0), 0);
  
  // Apply adjustments in chronological order (last adjustment wins for absolute value)
  const sortedAdjustments = [...adjustments].sort((a, b) => 
    a.adjustment_date.localeCompare(b.adjustment_date)
  );
  
  let quantity = baseQuantity + eventDelta;
  let lastEventDate: string | undefined;
  
  if (events.length > 0) {
    lastEventDate = events.reduce((latest, e) => 
      e.event_date > latest ? e.event_date : latest, events[0].event_date
    );
  }

  // If there are adjustments, the most recent adjustment sets absolute quantity,
  // then add events that occurred after that adjustment
  if (sortedAdjustments.length > 0) {
    const lastAdj = sortedAdjustments[sortedAdjustments.length - 1];
    quantity = lastAdj.quantity_after;
    lastEventDate = lastAdj.adjustment_date > (lastEventDate ?? '') 
      ? lastAdj.adjustment_date 
      : lastEventDate;
    
    // Add events after last adjustment
    const postAdjEvents = events.filter(e => e.event_date > lastAdj.adjustment_date);
    const postAdjDelta = postAdjEvents.reduce((sum, e) => sum + (e.quantity_delta ?? 0), 0);
    quantity += postAdjDelta;
  }

  return {
    quantity: Math.max(0, quantity),
    lastEventDate,
    eventCount: events.length + adjustments.length,
  };
}
