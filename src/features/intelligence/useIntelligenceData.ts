import { useHydratedSnapshot } from '../../core/hooks';
import { ALL_STORES, emptyRecords, hydratedSources, readRecords } from '../storeRegistry';
import type { IntelligenceRecords } from './reportModel';

const sources = hydratedSources(ALL_STORES);
const empty: IntelligenceRecords = emptyRecords(ALL_STORES);
const snapshot = (): IntelligenceRecords => readRecords(ALL_STORES);

export function useIntelligenceData() {
  const { data: records, status } = useHydratedSnapshot(sources, snapshot, empty);
  return { records, loading: status === 'loading' };
}
