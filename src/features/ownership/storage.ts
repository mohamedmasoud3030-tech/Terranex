import { newId } from '../../core/lib/id';
import { createSupabaseStore } from '../../core/storage/supabaseStore';
import type {
  EquityChangeEvent,
  PartnerLedgerEntry,
  Distribution,
  DistributionAllocation,
} from '../../core/types/domain';

const EQUITY_CHANGE_EVENTS_TABLE = 'equity_change_events';
const PARTNER_LEDGER_ENTRIES_TABLE = 'partner_ledger_entries';
const DISTRIBUTIONS_TABLE = 'distributions';
const DISTRIBUTION_ALLOCATIONS_TABLE = 'distribution_allocations';

function parseEquityChangeEvent(raw: unknown): EquityChangeEvent {
  return raw as EquityChangeEvent;
}

function parsePartnerLedgerEntry(raw: unknown): PartnerLedgerEntry {
  return raw as PartnerLedgerEntry;
}

function parseDistribution(raw: unknown): Distribution {
  return raw as Distribution;
}

function parseDistributionAllocation(raw: unknown): DistributionAllocation {
  return raw as DistributionAllocation;
}

export const equityChangeEventsHydration = createSupabaseStore<EquityChangeEvent>(
  EQUITY_CHANGE_EVENTS_TABLE,
  parseEquityChangeEvent,
  'created_at',
);

export const partnerLedgerEntriesHydration = createSupabaseStore<PartnerLedgerEntry>(
  PARTNER_LEDGER_ENTRIES_TABLE,
  parsePartnerLedgerEntry,
  'posting_date',
);

export const distributionsHydration = createSupabaseStore<Distribution>(
  DISTRIBUTIONS_TABLE,
  parseDistribution,
  'distribution_date',
);

export const distributionAllocationsHydration = createSupabaseStore<DistributionAllocation>(
  DISTRIBUTION_ALLOCATIONS_TABLE,
  parseDistributionAllocation,
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

export const equityChangeEventsStorage = {
  getAll: () => equityChangeEventsStore.get(),
  getByProject: (projectId: string) =>
    equityChangeEventsStore.get().filter((e) => e.project_id === projectId),
  getByPartner: (partnerId: string) =>
    equityChangeEventsStore.get().filter((e) => e.partner_id === partnerId),
  subscribe: equityChangeEventsStore.subscribe,
  flush: equityChangeEventsStore.flush,
  ready: equityChangeEventsStore.ready,
  rehydrate: equityChangeEventsStore.rehydrate,
  getLoadError: equityChangeEventsStore.getLoadError,
};

export const partnerLedgerEntriesStorage = {
  getAll: () => partnerLedgerEntriesStore.get(),
  getByProject: (projectId: string) =>
    partnerLedgerEntriesStore.get().filter((e) => e.project_id === projectId),
  getByPartner: (partnerId: string) =>
    partnerLedgerEntriesStore.get().filter((e) => e.partner_id === partnerId),
  getByProjectAndPartner: (projectId: string, partnerId: string) =>
    partnerLedgerEntriesStore.get().filter(
      (e) => e.project_id === projectId && e.partner_id === partnerId,
    ),
  /**
   * Calculate partner balance from ledger entries.
   * Balance = sum of contributions/distributions - sum of withdrawals/payments.
   * Excludes reversal entries (they cancel the original).
   */
  calculateBalance: (projectId: string, partnerId: string): number => {
    const entries = partnerLedgerEntriesStore
      .get()
      .filter(
        (e) =>
          e.project_id === projectId &&
          e.partner_id === partnerId &&
          e.entry_type !== 'reversal',
      );

    let balance = 0;
    for (const entry of entries) {
      switch (entry.entry_type) {
        case 'capital_contribution':
        case 'distribution_entitlement':
          balance += entry.amount_egp;
          break;
        case 'withdrawal':
        case 'distribution_payment':
          balance -= entry.amount_egp;
          break;
        case 'correction':
          balance += entry.amount_egp;
          break;
      }
    }
    return balance;
  },
  subscribe: partnerLedgerEntriesStore.subscribe,
  flush: partnerLedgerEntriesStore.flush,
  ready: partnerLedgerEntriesStore.ready,
  rehydrate: partnerLedgerEntriesStore.rehydrate,
  getLoadError: partnerLedgerEntriesStore.getLoadError,
};

export const distributionsStorage = {
  getAll: () => distributionsStore.get(),
  getByProject: (projectId: string) =>
    distributionsStore.get().filter((d) => d.project_id === projectId),
  getById: (id: string) =>
    distributionsStore.get().find((d) => d.id === id),
  create: (input: DistributionInput): Distribution => {
    const distribution: Distribution = {
      ...input,
      id: newId(),
      created_by: '', // Will be set by the server
      created_at: new Date().toISOString(),
    };
    distributionsStore.update((all) => [distribution, ...all]);
    return distribution;
  },
  subscribe: distributionsStore.subscribe,
  flush: distributionsStore.flush,
  ready: distributionsStore.ready,
  rehydrate: distributionsStore.rehydrate,
  getLoadError: distributionsStore.getLoadError,
};

export const distributionAllocationsStorage = {
  getAll: () => distributionAllocationsStore.get(),
  getByDistribution: (distributionId: string) =>
    distributionAllocationsStore.get().filter((a) => a.distribution_id === distributionId),
  getByPartner: (partnerId: string) =>
    distributionAllocationsStore.get().filter((a) => a.partner_id === partnerId),
  createMany: (allocations: DistributionAllocationInput[]): DistributionAllocation[] => {
    const newAllocations = allocations.map((a) => ({ ...a, id: newId() }));
    distributionAllocationsStore.update((all) => [...newAllocations, ...all]);
    return newAllocations;
  },
  subscribe: distributionAllocationsStore.subscribe,
  flush: distributionAllocationsStore.flush,
  ready: distributionAllocationsStore.ready,
  rehydrate: distributionAllocationsStore.rehydrate,
  getLoadError: distributionAllocationsStore.getLoadError,
};
