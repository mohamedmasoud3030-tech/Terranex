import { createSupabaseStore, type SupabaseStore } from '../../core/storage/supabaseStore';
import { sumLedgerEffects } from './model';
import type {
  EquityChangeEvent,
  PartnerLedgerEntry,
  Distribution,
  DistributionAllocation,
} from '../../core/types/domain';

/**
 * Every ownership-domain storage facade re-exposes the same lifecycle
 * methods (subscribe/flush/ready/rehydrate/getLoadError) from its backing
 * SupabaseStore. Centralizing that here avoids repeating the same five
 * pass-through lines across all four stores in this file.
 */
function lifecycleMethods<T extends { id: string }>(store: SupabaseStore<T>) {
  return {
    subscribe: store.subscribe,
    flush: store.flush,
    ready: store.ready,
    rehydrate: store.rehydrate,
    getLoadError: store.getLoadError,
  };
}

// Every row shape here is already validated server-side (RLS + RPCs), so the
// parse step is a plain identity cast rather than four near-identical
// wrapper functions.
const identity = <T>(raw: unknown): T => raw as T;

export const equityChangeEventsHydration = createSupabaseStore<EquityChangeEvent>(
  'equity_change_events',
  identity,
  'created_at',
);

export const partnerLedgerEntriesHydration = createSupabaseStore<PartnerLedgerEntry>(
  'partner_ledger_entries',
  identity,
  'posting_date',
);

export const distributionsHydration = createSupabaseStore<Distribution>(
  'distributions',
  identity,
  'distribution_date',
);

export const distributionAllocationsHydration = createSupabaseStore<DistributionAllocation>(
  'distribution_allocations',
  identity,
  'created_at',
);

// Aliases for the stores (the hydration objects are also the stores)
const equityChangeEventsStore = equityChangeEventsHydration;
const partnerLedgerEntriesStore = partnerLedgerEntriesHydration;
const distributionsStore = distributionsHydration;
const distributionAllocationsStore = distributionAllocationsHydration;

export const ownershipReady = Promise.all([
  equityChangeEventsStore.ready,
  partnerLedgerEntriesStore.ready,
  distributionsStore.ready,
  distributionAllocationsStore.ready,
]);

export type EquityChangeEventInput = Omit<EquityChangeEvent, 'id' | 'created_at' | 'created_by'>;
export type PartnerLedgerEntryInput = Omit<PartnerLedgerEntry, 'id' | 'created_at' | 'created_by'>;
export type DistributionInput = Omit<Distribution, 'id' | 'created_at' | 'created_by'>;
export type DistributionAllocationInput = Omit<DistributionAllocation, 'id'>;

/** Shared by any ownership record shaped with `project_id` / `partner_id`. */
function byProjectAndPartnerFilters<
  T extends { id: string; project_id: string; partner_id: string },
>(store: SupabaseStore<T>) {
  return {
    getByProject: (projectId: string) =>
      store.get().filter((e) => e.project_id === projectId),
    getByPartner: (partnerId: string) =>
      store.get().filter((e) => e.partner_id === partnerId),
    getByProjectAndPartner: (projectId: string, partnerId: string) =>
      store.get().filter((e) => e.project_id === projectId && e.partner_id === partnerId),
  };
}

export const equityChangeEventsStorage = {
  getAll: () => equityChangeEventsStore.get(),
  ...byProjectAndPartnerFilters(equityChangeEventsStore),
  ...lifecycleMethods(equityChangeEventsStore),
};

export const partnerLedgerEntriesStorage = {
  getAll: () => partnerLedgerEntriesStore.get(),
  ...byProjectAndPartnerFilters(partnerLedgerEntriesStore),
  /**
   * Calculate partner balance from immutable ledger entries. Reversal rows and
   * originals referenced by reversal rows remain visible but have zero active
   * financial effect.
   */
  calculateBalance: (projectId: string, partnerId: string): number => {
    const entries = partnerLedgerEntriesStore
      .get()
      .filter((e) => e.project_id === projectId && e.partner_id === partnerId);
    return sumLedgerEffects(entries);
  },
  ...lifecycleMethods(partnerLedgerEntriesStore),
};

export const distributionsStorage = {
  getAll: () => distributionsStore.get(),
  getByProject: (projectId: string) =>
    distributionsStore.get().filter((d) => d.project_id === projectId),
  getById: (id: string) =>
    distributionsStore.get().find((d) => d.id === id),
  ...lifecycleMethods(distributionsStore),
};

export const distributionAllocationsStorage = {
  getAll: () => distributionAllocationsStore.get(),
  getByDistribution: (distributionId: string) =>
    distributionAllocationsStore.get().filter((a) => a.distribution_id === distributionId),
  getByPartner: (partnerId: string) =>
    distributionAllocationsStore.get().filter((a) => a.partner_id === partnerId),
  ...lifecycleMethods(distributionAllocationsStore),
};
