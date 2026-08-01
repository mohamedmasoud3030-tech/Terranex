import type { HydratedSource } from '../core/hooks';
import { assetsHydration, assetsStore } from './assets/storage';
import { documentsHydration, documentsStore } from './documents/storage';
import {
  operationalEventsHydration,
  operationalEventsStore,
  stockAdjustmentsHydration,
  stockAdjustmentsStore,
} from './events/storage';
import { obligationsHydration, obligationsStore } from './obligations/storage';
import {
  partnersHydration,
  partnersStore,
  projectPartnersHydration,
  projectPartnersStore,
} from './partners/storage';
import { projectsHydration, projectsStore } from './projects/storage';
import { settlementAllocationsHydration, settlementAllocationsStore } from './settlement-allocations/storage';
import { settlementsHydration, settlementsStore } from './settlements/storage';
import { transactionsHydration, transactionsStore } from './transactions/storage';

/**
 * Every hydrated store, keyed by the name hub data hooks use for its rows.
 * One entry pairs the store facade (rows + subscription) with the hydration
 * handle of its backing Supabase store, so a hook only names what it needs.
 */
const registry = {
  projects: { store: projectsStore, hydration: projectsHydration },
  assets: { store: assetsStore, hydration: assetsHydration },
  partners: { store: partnersStore, hydration: partnersHydration },
  projectPartners: { store: projectPartnersStore, hydration: projectPartnersHydration },
  transactions: { store: transactionsStore, hydration: transactionsHydration },
  obligations: { store: obligationsStore, hydration: obligationsHydration },
  settlements: { store: settlementsStore, hydration: settlementsHydration },
  allocations: { store: settlementAllocationsStore, hydration: settlementAllocationsHydration },
  events: { store: operationalEventsStore, hydration: operationalEventsHydration },
  adjustments: { store: stockAdjustmentsStore, hydration: stockAdjustmentsHydration },
  documents: { store: documentsStore, hydration: documentsHydration },
} as const;

export type StoreName = keyof typeof registry;

/** Every store — what the governance and intelligence hubs read. */
export const ALL_STORES = [
  'projects', 'assets', 'partners', 'projectPartners', 'transactions', 'obligations',
  'settlements', 'allocations', 'events', 'adjustments', 'documents',
] as const satisfies readonly StoreName[];
type RowsOf<K extends StoreName> = ReturnType<(typeof registry)[K]['store']['getAll']>;
export type Records<K extends StoreName> = { [P in K]: RowsOf<P> };

/** The store/hydration pairs behind `names`, ready for `useHydratedSnapshot`. */
export function hydratedSources(names: readonly StoreName[]): HydratedSource[] {
  return names.map((name) => registry[name]);
}

/** Current rows of every named store, keyed by store name. */
export function readRecords<K extends StoreName>(names: readonly K[]): Records<K> {
  return Object.fromEntries(names.map((name) => [name, registry[name].store.getAll()])) as Records<K>;
}

/** The pre-hydration value of `readRecords(names)` — every list empty. */
export function emptyRecords<K extends StoreName>(names: readonly K[]): Records<K> {
  return Object.fromEntries(names.map((name) => [name, []])) as Records<K>;
}
