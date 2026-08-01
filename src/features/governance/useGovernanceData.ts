import { useHydratedSnapshot } from '../../core/hooks';
import { assetsHydration } from '../assets/storage';
import { documentsHydration } from '../documents/storage';
import { operationalEventsHydration, stockAdjustmentsHydration } from '../events/storage';
import { obligationsHydration } from '../obligations/storage';
import { partnersHydration, projectPartnersHydration } from '../partners/storage';
import { projectsHydration } from '../projects/storage';
import { settlementAllocationsHydration } from '../settlement-allocations/storage';
import { settlementsHydration } from '../settlements/storage';
import { ALL_STORES, emptyRecords, hydratedSources, readRecords } from '../storeRegistry';
import { transactionsHydration } from '../transactions/storage';
import { inspectStore, type GovernanceRecords } from './dataHealth';

const sources = hydratedSources(ALL_STORES);
const empty: GovernanceRecords = emptyRecords(ALL_STORES);
const snapshot = (): GovernanceRecords => readRecords(ALL_STORES);

const storeDiagnostics = [
  ['projects', projectsHydration],
  ['assets', assetsHydration],
  ['partners', partnersHydration],
  ['project partners', projectPartnersHydration],
  ['transactions', transactionsHydration],
  ['obligations', obligationsHydration],
  ['settlements', settlementsHydration],
  ['settlement allocations', settlementAllocationsHydration],
  ['operational events', operationalEventsHydration],
  ['stock adjustments', stockAdjustmentsHydration],
  ['documents', documentsHydration],
] as const;

export function useGovernanceData() {
  const { data: records, status } = useHydratedSnapshot(sources, snapshot, empty);

  return {
    records,
    loading: status === 'loading',
    diagnostics: storeDiagnostics.map(([name, store]) => inspectStore(name, store)),
  };
}
